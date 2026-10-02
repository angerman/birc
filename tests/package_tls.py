#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed TLS trust/linkage and fail-closed controls. No public network.

The child has an empty PATH and an owned HOME. Offline demo traces contain
only synthetic settings. A plaintext loopback peer never receives IRC bytes.
The separate TLS PTY suite tests successful certificate/name verification.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import socket
import ssl
import subprocess
import sys
import tempfile
import time


def run(command, env):
    result = subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert len(result.stdout) + len(result.stderr) <= 128 * 1024, "installed TLS output exceeded its bound"
    return result


def provenance(binary):
    body = binary.read_text()
    paths = re.findall(r"/nix/store/[^\s'\"{}]+/etc/ssl/certs/ca-bundle\.crt", body)
    assert len(set(paths)) == 1, "installed wrapper has no unique pinned TLS CA default"
    bundle = Path(paths[0])
    assert bundle.is_file() and os.access(bundle, os.R_OK), "installed TLS CA default is unreadable"
    context = ssl.create_default_context(cafile=str(bundle))
    assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
    assert context.cert_store_stats()["x509_ca"] > 0, "installed TLS CA default has no trusted certificates"
    shell = shlex.split(body.splitlines()[0][2:])
    assert shell and shell[0].startswith("/nix/store/") and Path(shell[0]).is_file(), "wrapper shell is not provisioned"
    commands = [shlex.split(line) for line in body.splitlines() if line.startswith("exec ")]
    assert len(commands) == 1 and commands[0][:3] == ["exec", "-a", "$0"], "unexpected installed client exec"
    executable = Path(commands[0][3])
    assert executable.parent == binary.parent and executable.is_file(), "wrapper executable is not installed beside it"
    return bundle, shell, executable


def trust_controls(binary, bundle, shell, root, env):
    custom = root / "custom CA with spaces.pem"
    custom.write_bytes(bundle.read_bytes())
    for value, expected in ((None, bundle), (str(custom), custom)):
        current = dict(env)
        if value is not None:
            current["SSL_CERT_FILE"] = value
        result = run(shell + ["-x", str(binary), "--demo", "--frames", "1"], current)
        assert result.returncode == 0, "installed offline client failed with selected CA"
        chosen = []
        for line in result.stderr.decode().splitlines():
            fields = shlex.split(line)
            if len(fields) == 3 and fields[:2] == ["+", "export"] and fields[2].startswith("SSL_CERT_FILE="):
                chosen.append(fields[2].split("=", 1)[1])
        assert chosen == [str(expected)], "installed wrapper changed the CA default or explicit override"
    return custom


def linkage(binary, library, env):
    current = dict(env)
    if sys.platform == "darwin":
        # DYLD_PRINT_LIBRARIES also lists delayed Apple framework closures,
        # including unrelated system libssl versions. Check this executable's
        # load commands, not all libraries in the process's shared cache.
        command = ["/usr/bin/otool", "-L", str(binary)]
    elif sys.platform.startswith("linux"):
        current["LD_DEBUG"] = "libs"
        command = [str(binary), "--demo", "--frames", "1"]
    else:
        raise AssertionError("TLS linkage qualification requires Darwin or Linux loader diagnostics")
    result = run(command, current)
    assert result.returncode == 0, "installed client failed during linkage qualification"
    found = {"ssl": [], "crypto": []}
    evidence = result.stdout if sys.platform == "darwin" else result.stderr
    for line in evidence.decode().splitlines():
        if sys.platform.startswith("linux") and "calling init:" not in line:
            continue  # Search candidates are not loaded-library evidence.
        for path in re.findall(r"/[^\s'\"<>]+", line):
            name = Path(path).name
            for kind in found:
                if name.startswith("lib" + kind + "."):
                    found[kind].append(Path(path).resolve())
    for kind, paths in found.items():
        assert paths and all(path.parent == library / "lib" and path.is_file() for path in paths), \
            "installed lib" + kind + " does not use the provisioned OpenSSL store"


def rejected(binary, root, env, invalid_ca=False):
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(4)
        current = dict(env)
        if invalid_ca:
            ca = root / "synthetic invalid CA.pem"
            ca.write_text("not a certificate\n")
            current["SSL_CERT_FILE"] = str(ca)
        command = [str(binary), "--connect", "127.0.0.1", "--port", str(server.getsockname()[1]),
                   "--tls", "--nick", "probe", "--frames", "1"]
        process = subprocess.Popen(command, env=current, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        peer = None
        wire = bytearray()
        try:
            peer, _ = server.accept()
            peer.settimeout(0.05)
            if not invalid_ca:
                peer.sendall(b":synthetic 001 probe :plaintext is not TLS\r\n")
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                try:
                    data = peer.recv(4096)
                    if not data:
                        break
                    wire.extend(data)
                    assert len(wire) <= 65536, "rejected TLS peer received unbounded bytes"
                except socket.timeout:
                    if process.poll() is not None:
                        break
                except ConnectionResetError:
                    break
            out, error = process.communicate(timeout=3)
            assert process.returncode != 0 and len(out) + len(error) <= 65536, "headless TLS failure reported success"
            assert b"birc=ok" not in out + error, "failed TLS registration painted a successful headless result"
            assert not any(token in wire for token in (b"NICK ", b"USER ", b"CAP ", b"AUTHENTICATE ", b"QUIT ")), \
                "TLS failure leaked plaintext IRC application bytes"
            expected = b"tls-config" if invalid_ca else b"tls-handshake"
            assert expected in out + error, "headless TLS failure lost its fixed stage diagnostic"
            assert str(root).encode() not in out + error, "TLS diagnostic exposed a synthetic private path"
        finally:
            if peer is not None:
                peer.close()
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
            process.stdout.close()
            process.stderr.close()


def main(package, openssl_library):
    target = Path(package).resolve()
    binary = target / "bin/birc" if target.is_dir() else target
    library = Path(openssl_library).resolve()
    assert str(library).startswith("/nix/store/") and (library / "lib").is_dir(), "expected pinned OpenSSL library output"
    bundle, shell, executable = provenance(binary)
    with tempfile.TemporaryDirectory(prefix="birc-tls-package-") as temporary:
        root = Path(temporary)
        env = {"HOME": str(root), "TMPDIR": str(root), "PATH": "", "LANG": "C", "TERM": "xterm-256color",
               "BIRC_HISTORY": "none", "BIRC_IMAGES": "off", "PYTHONDONTWRITEBYTECODE": "1"}
        trust_controls(binary, bundle, shell, root, env)
        linkage(executable, library, env)
        rejected(binary, root, env)
        rejected(binary, root, env, invalid_ca=True)
    print("package_tls=ok")


if __name__ == "__main__":
    try:
        assert len(sys.argv) == 3, "expected installed package/client and pinned OpenSSL library output"
        main(*sys.argv[1:])
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired, ssl.SSLError) as error:
        print(f"package_tls: {error}", file=sys.stderr)
        raise SystemExit(1)
