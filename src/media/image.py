#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Load and normalize one image. No shell, cookies, proxies, or decode files.

The parent owns scheduling and the output limit. This helper also has a total
deadline, so a helper adopted during application exit cannot run indefinitely.
Only validated public addresses are contacted, including after redirects.
"""

import base64
import fcntl
import hashlib
import http.client
import io
import ipaddress
import os
import secrets
import signal
import socket
import ssl
import stat
import struct
import sys
import time
import warnings
from urllib.parse import quote, urljoin, urlsplit

from PIL import Image, ImageOps, PngImagePlugin

MAX_DOWNLOAD = 8 * 1024 * 1024
MAX_CACHE_ENTRIES = 64
MAX_CACHE_BYTES = 64 * 1024 * 1024
MAX_CACHE_SCAN = 256
MAX_LOCAL_BYTES = 16 * 1024 * 1024
MAX_PIXELS = 16 * 1024 * 1024
MAX_SOURCE_FRAME_PIXELS = 32 * 1024 * 1024
MAX_SIDE = 320
MAX_FRAMES = 24
MAX_FRAME_PIXELS = 1536000
MAX_PAYLOAD = 2 * 1024 * 1024
TIMEOUT = 8
FORMATS = ("PNG", "JPEG", "GIF", "WEBP", "BMP", "TIFF", "AVIF")
Image.MAX_IMAGE_PIXELS = MAX_PIXELS
# Previews do not need large text/profile payloads. Use the decoder's existing
# limits instead of adding a separate PNG parser or metadata inflater.
PngImagePlugin.MAX_TEXT_CHUNK = 65536
PngImagePlugin.MAX_TEXT_MEMORY = 262144


class ImageError(Exception):
    pass


def public_address(value):
    """Reject private, loopback, link-local, multicast, and mapped aliases."""
    address = ipaddress.ip_address(value.split("%", 1)[0])
    if isinstance(address, ipaddress.IPv6Address):
        if address.ipv4_mapped is not None:
            address = address.ipv4_mapped
        elif address.sixtofour is not None or address.teredo is not None:
            return False
        elif address not in ipaddress.IPv6Network("2000::/3"):
            # Exclude NAT64/site-local aliases, even where is_global is true.
            return False
    return address.is_global and not address.is_multicast


def url_parts(url):
    """Validate even an offline cache hit, without resolving its host."""
    if len(url) > 4096 or any(ord(char) <= 32 or ord(char) == 127 for char in url):
        raise ImageError("invalid image URL")
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ImageError("image URL must use HTTP or HTTPS")
    if parsed.username is not None or parsed.password is not None:
        raise ImageError("image URL cannot contain credentials")
    host = parsed.hostname.encode("idna").decode("ascii")
    port = parsed.port if parsed.port is not None else (443 if parsed.scheme == "https" else 80)
    if port != (443 if parsed.scheme == "https" else 80):
        raise ImageError("image URL must use the standard HTTP or HTTPS port")
    path = quote(parsed.path or "/", safe="/%:@!$&'()*+,;=-._~")
    if parsed.query:
        path += "?" + quote(parsed.query, safe="/%?:@!$&'()*+,;=-._~")
    return parsed.scheme, host, port, path


def destination(url, resolver=socket.getaddrinfo):
    scheme, host, port, path = url_parts(url)
    addresses = resolver(host, port, type=socket.SOCK_STREAM)
    if not addresses or any(not public_address(item[4][0]) for item in addresses):
        raise ImageError("image host must resolve only to public addresses")
    return scheme, host, port, path, addresses


def cache_directory(create=False):
    explicit = os.environ.get("BIRC_IMAGE_CACHE")
    if explicit in ("", "none"):
        return None
    base = os.environ.get("XDG_CACHE_HOME", "")
    if not os.path.isabs(base):
        base = os.path.expanduser("~/.cache")
    path = explicit if explicit is not None else os.path.join(base, "birc", "images")
    fd = None
    try:
        # Descriptor-relative traversal does not follow a swapped/symlinked
        # parent. An override must already be private; never chmod its folder.
        path = os.path.abspath(os.path.expanduser(path))
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        fd = os.open("/", flags)
        for component in path.split("/"):
            if not component:
                continue
            if create:
                try:
                    os.mkdir(component, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            previous_fd = fd
            fd = os.open(component, flags, dir_fd=previous_fd)
            os.close(previous_fd)
        info = os.fstat(fd)
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077):
            raise OSError("unsafe image cache directory")
        return fd
    except (OSError, ValueError):
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
        return None


def cache_owned(info):
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        raise OSError("unsafe image cache file")


def cache_identity(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


def cache_name(url):
    # Names/side metadata never store the requested URL or chat metadata.
    # The validated image's original source bytes remain intact.
    return hashlib.sha256(url.encode("utf-8")).hexdigest() + ".img"


def cards_usage(directory):
    """Bounded (count, bytes) of card payloads in the private subdirectory.

    Images and cards share one explicit budget under this directory's lock.
    A missing subdirectory means no cards yet; any scan failure returns None
    so the writer skips instead of exceeding the shared budget.
    """
    subdir = None
    try:
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        try:
            subdir = os.open("cards", flags, dir_fd=directory)
        except FileNotFoundError:
            return 0, 0
        info = os.fstat(subdir)
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077):
            return None
        count = total = 0
        with os.scandir(subdir) as scan:
            for index, entry in enumerate(scan):
                if index >= MAX_CACHE_SCAN:
                    return None
                name = entry.name
                page = (len(name) == 69 and name.endswith(".card")
                        and all(c in "0123456789abcdef" for c in name[:64]))
                staging = (len(name) == 35 and name.startswith(".write-")
                           and name.endswith(".tmp")
                           and all(c in "0123456789abcdef" for c in name[7:-4]))
                if not page and not staging:
                    continue
                try:
                    entry_info = entry.stat(follow_symlinks=False)
                    cache_owned(entry_info)
                except OSError:
                    return None
                count += 1
                total += entry_info.st_size
        return count, total
    except OSError:
        return None
    finally:
        if subdir is not None:
            try:
                os.close(subdir)
            except OSError:
                pass


def cache_read(url):
    directory = cache_directory()
    fd = None
    if directory is None:
        return None
    try:
        name = cache_name(url)
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                     dir_fd=directory)
        info = os.fstat(fd)
        cache_owned(info)
        if not 0 < info.st_size <= MAX_DOWNLOAD:
            return None
        os.fchmod(fd, 0o600)
        info = os.fstat(fd)
        data = bytearray()
        while len(data) < info.st_size:
            chunk = os.read(fd, min(65536, info.st_size - len(data)))
            if not chunk:
                return None
            data.extend(chunk)
        current = os.stat(name, dir_fd=directory, follow_symlinks=False)
        if cache_identity(os.fstat(fd)) != cache_identity(info) or cache_identity(current) != cache_identity(info):
            return None
        return bytes(data)
    except (OSError, ValueError):
        return None
    finally:
        for opened in (fd, directory):
            if opened is not None:
                try:
                    os.close(opened)
                except OSError:
                    pass


def cache_write(url, data):
    """Best-effort bounded FIFO, serialized across cooperating helpers.

    Steady cache files use at most 64 MiB; atomic replacement can temporarily
    retain the old target plus one additional staging file of at most 8 MiB.
    Orphaned staging files count toward the next writer's eviction budget.
    Images and cards share one explicit budget under this directory's lock:
    this writer counts both pools, evicts only its own oldest entries, and
    skips the write when cards alone fill it.
    """
    if not 0 < len(data) <= min(MAX_DOWNLOAD, MAX_CACHE_BYTES) or MAX_CACHE_ENTRIES < 1:
        return
    directory = cache_directory(create=True)
    lock = temporary_fd = None
    temporary = None
    if directory is None:
        return
    try:
        lock = os.open(".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK
                       | os.O_CLOEXEC, 0o600, dir_fd=directory)
        cache_owned(os.fstat(lock))
        os.fchmod(lock, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        other = cards_usage(directory)
        if other is None:
            raise OSError("shared media budget unreadable")
        other_count, other_bytes = other
        if (other_count + 1 > MAX_CACHE_ENTRIES
                or other_bytes + len(data) > MAX_CACHE_BYTES):
            return  # Cards alone fill the shared budget: skip without evicting.
        target = cache_name(url)
        try:
            previous = os.stat(target, dir_fd=directory, follow_symlinks=False)
            cache_owned(previous)
        except FileNotFoundError:
            previous = None
        entries = []
        with os.scandir(directory) as scan:
            for index, entry in enumerate(scan):
                if index >= MAX_CACHE_SCAN:
                    raise OSError("image cache scan limit")
                name = entry.name
                image = len(name) == 68 and name.endswith(".img") and all(c in "0123456789abcdef" for c in name[:64])
                staging = len(name) == 35 and name.startswith(".write-") and name.endswith(".tmp") and all(c in "0123456789abcdef" for c in name[7:-4])
                if not image and not staging:
                    continue
                info = entry.stat(follow_symlinks=False)
                cache_owned(info)
                if name == target:
                    if previous is None or cache_identity(info) != cache_identity(previous):
                        raise OSError("image cache changed")
                    continue  # Replacement reuses this entry's slot and bytes.
                entries.append((info.st_mtime_ns, name, info))
        # A crashed writer can leave a staging file; no live writer owns one
        # while this lock is held. Include it in accounting/eviction too.
        entries.sort(key=lambda item: (item[0], item[1]))
        total = sum(item[2].st_size for item in entries)
        while entries and (other_count + len(entries) + 1 > MAX_CACHE_ENTRIES
                           or other_bytes + total + len(data) > MAX_CACHE_BYTES):
            _, name, info = entries.pop(0)
            if cache_identity(os.stat(name, dir_fd=directory, follow_symlinks=False)) != cache_identity(info):
                raise OSError("image cache changed")
            os.unlink(name, dir_fd=directory)
            total -= info.st_size
        temporary = ".write-" + secrets.token_hex(12) + ".tmp"
        temporary_fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
                               | os.O_CLOEXEC, 0o600, dir_fd=directory)
        os.fchmod(temporary_fd, 0o600)
        view = memoryview(data)
        while view:
            count = os.write(temporary_fd, view)
            if count <= 0:
                raise OSError("short image cache write")
            view = view[count:]
        try:
            current = os.stat(target, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            current = None
        if ((previous is None) != (current is None)
                or (current is not None and cache_identity(current) != cache_identity(previous))):
            raise OSError("image cache changed")
        os.replace(temporary, target, src_dir_fd=directory, dst_dir_fd=directory)
        temporary = None
    except (OSError, ValueError):
        pass
    finally:
        if temporary is not None and temporary_fd is not None:
            try:
                os.unlink(temporary, dir_fd=directory)
            except OSError:
                pass
        for fd in (temporary_fd, lock, directory):
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass


def encode_remote(url, deadline):
    url_parts(url)
    data = cache_read(url)
    if data is not None:
        try:
            return encode(data)
        except Exception:
            pass  # Never trust cached bytes without the same bounded decode.
    data = fetch(url, deadline)
    result = encode(data)
    cache_write(url, data)
    return result


class PinnedHTTP(http.client.HTTPConnection):
    """Use the address already checked above; never resolve during connect."""

    def __init__(self, scheme, host, port, addresses, timeout):
        super().__init__(host, port, timeout=timeout)
        self.scheme = scheme
        self.addresses = addresses

    def connect(self):
        last_error = None
        for family, kind, protocol, _, address in self.addresses:
            sock = socket.socket(family, kind, protocol)
            try:
                sock.settimeout(self.timeout)
                sock.connect(address)
                if self.scheme == "https":
                    # The standard TLS library checks the original host name,
                    # not the pinned IP. No custom certificate or crypto code.
                    sock = ssl.create_default_context().wrap_socket(
                        sock, server_hostname=self.host
                    )
                self.sock = sock
                return
            except OSError as error:
                sock.close()
                last_error = error
        raise ImageError("cannot connect to image host") from last_error


def fetch(url, deadline, resolver=socket.getaddrinfo, connection=PinnedHTTP):
    for redirect in range(4):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ImageError("image fetch timed out")
        scheme, host, port, path, addresses = destination(url, resolver)
        client = connection(scheme, host, port, addresses, remaining)
        try:
            client.request("GET", path, headers={
                "User-Agent": "birc-image/1", "Accept": "image/*",
                "Accept-Encoding": "identity", "Connection": "close",
            })
            response = client.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if not location or redirect == 3:
                    raise ImageError("too many image redirects")
                target = urljoin(url, location)
                if scheme == "https" and urlsplit(target).scheme != "https":
                    raise ImageError("image redirect cannot downgrade HTTPS")
                url = target
                continue
            if response.status != 200:
                raise ImageError("image server returned an error")
            if response.getheader("Content-Encoding", "identity").lower() != "identity":
                raise ImageError("compressed HTTP responses are not accepted")
            length = response.getheader("Content-Length")
            if length is not None and (not length.isdecimal() or int(length) > MAX_DOWNLOAD):
                raise ImageError("image download is too large")
            data = bytearray()
            while len(data) <= MAX_DOWNLOAD:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise ImageError("image fetch timed out")
                if client.sock is not None:
                    client.sock.settimeout(remaining)
                chunk = response.read(min(65536, MAX_DOWNLOAD + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
            if len(data) > MAX_DOWNLOAD:
                raise ImageError("image download is too large")
            if length is not None and len(data) != int(length):
                raise ImageError("incomplete image download")
            return bytes(data)
        finally:
            client.close()
    raise ImageError("too many image redirects")


def checked_source_pixels(size):
    width, height = size
    if width <= 0 or height <= 0 or width > 4096 or height > 4096 or width * height > MAX_PIXELS:
        raise ImageError("image dimensions are too large")
    return width * height


def encode(data):
    """Bound decode work; emit normalized PNG frames and predecoded first RGBA.

    The compact binary envelope is base64 on stdout because Bend Process.run
    returns UTF-8 strings. The UI owns the decoded bytes, not temporary paths.
    """
    if not data or len(data) > MAX_LOCAL_BYTES:
        raise ImageError("image input is empty or too large")
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(data), formats=FORMATS) as image:
            initial_pixels = checked_source_pixels(image.size)
            animated = image.format in ("GIF", "PNG", "WEBP") and getattr(image, "is_animated", False)
            # APNG's static fallback is not animated, but still counts toward
            # source decode work when seeking to the actual first frame.
            start = 1 if animated and image.format == "PNG" and image.info.get("default_image", False) else 0
            count = (getattr(image, "n_frames", 1) if animated else 1) - start
            if count > MAX_FRAMES or initial_pixels * (count + start) > MAX_SOURCE_FRAME_PIXELS:
                raise ImageError("image animation is too large")
            loops = image.info.get("loop") if animated else None
            # GIF stores repeat count; APNG and WebP store total plays.
            iterations = 1 if loops is None else (0 if loops == 0 else min(int(loops) + (image.format == "GIF"), 65535))
            frames, durations, pngs = [], [], []
            frame_pixels = 0
            source_pixels = initial_pixels if start else 0
            encoded_size = 32
            for index in range(count):
                image.seek(index + start)
                # GIF can expand its canvas on a later seek. Charge its actual
                # size before conversion/thumbnailing, not the initial estimate.
                source_pixels += checked_source_pixels(image.size)
                if source_pixels > MAX_SOURCE_FRAME_PIXELS:
                    raise ImageError("image animation is too large")
                frame = ImageOps.exif_transpose(image).convert("RGBA")
                frame.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS)
                if frames and frame.size != frames[0].size:
                    raise ImageError("animation frame dimensions differ")
                frame_pixels += frame.width * frame.height
                if frame_pixels > MAX_FRAME_PIXELS:
                    raise ImageError("image animation is too large")
                duration = max(20, min(10000, int(image.info.get("duration", 100) or 100)))
                output = io.BytesIO()
                frame.save(output, format="PNG")
                png = output.getvalue()
                encoded_size += 8 + len(png)
                if encoded_size > MAX_PAYLOAD:
                    raise ImageError("image preview is too large")
                frames.append(frame)
                durations.append(duration)
                pngs.append(png)
            first = frames[0]
            rgba = first.tobytes()
            gif = b""
            if count > 1:
                output = io.BytesIO()
                # Do not inherit the source's different loop-count convention,
                # especially when one play omits the GIF repeat extension.
                first.info.pop("loop", None)
                options = {"loop": 0 if iterations == 0 else iterations - 1} if iterations != 1 else {}
                first.save(output, format="GIF", save_all=True, append_images=frames[1:],
                           duration=durations, disposal=2, **options)
                gif = output.getvalue()
            header = b"BIRCIMG1" + struct.pack(">6I", first.width, first.height, count, iterations, len(rgba), len(gif))
            payload = header + rgba + gif + b"".join(
                struct.pack(">2I", duration, len(png)) + png
                for duration, png in zip(durations, pngs)
            )
            if len(payload) > MAX_PAYLOAD:
                raise ImageError("image preview is too large")
            return base64.b64encode(payload).decode("ascii")


def read_local(path):
    """Only an explicit --local argument can enter this path."""
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= MAX_LOCAL_BYTES:
            raise ImageError("local image must be a bounded regular file")
        data = bytearray()
        while len(data) <= metadata.st_size:
            chunk = os.read(fd, min(65536, metadata.st_size + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        if len(data) != metadata.st_size:
            raise ImageError("local image changed while reading")
        return bytes(data)
    finally:
        os.close(fd)


def main(args):
    # Terminate in the kernel even if a decoder/DNS call cannot dispatch a
    # Python exception. Process.run observes failure and reaps this helper.
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.alarm(TIMEOUT)
    if len(args) == 1:
        result = encode_remote(args[0], time.monotonic() + TIMEOUT)
    elif len(args) == 2 and args[0] == "--local":
        result = encode(read_local(args[1]))
    else:
        raise ImageError("usage: birc-image <HTTP-or-HTTPS-image-URL> | --local <path>")
    print(result)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Exception:
        # Do not echo a URL, server text, or decoder diagnostics into the tty.
        print("birc-image: image unavailable", file=sys.stderr)
        sys.exit(1)
