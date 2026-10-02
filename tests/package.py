#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed package controls: local images, helper overrides, and offline CA.

No URL is supplied to a helper. The only PTY command besides quit is a local
JPEG preview; automatic images are off. Child PATH contains only owned fakes.
"""
from __future__ import annotations

import base64
import fcntl
import io
import json
import os
from pathlib import Path
import pty
import re
import shlex
import struct
import subprocess
import sys
import tempfile
import termios
import time

from PIL import Image

# Import Pillow first: tests/pty/typing.py must not shadow its typing import.
sys.path.insert(0, str(Path(__file__).resolve().parent / "pty"))
try:
    from output_stall import drain
finally:
    sys.path.pop(0)


MAX_LOCAL_BYTES = 16 * 1024 * 1024
MAX_PAYLOAD = 2 * 1024 * 1024


def environment(root: Path, fake_bin: Path) -> dict[str, str]:
    return {"HOME": str(root), "TMPDIR": str(root), "PATH": str(fake_bin),
            "LANG": "C", "PYTHONDONTWRITEBYTECODE": "1"}


def run(command, env, timeout=15):
    return subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


def provenance(binary: Path) -> tuple[Path, Path, Path, Path]:
    wrapper = binary.read_text()
    found = re.findall(r"/nix/store/[^\s'\"{}]+/bin/birc-image", wrapper)
    assert len(set(found)) == 1, "installed birc wrapper has no unique absolute helper"
    helper = Path(found[0])
    assert helper.is_file() and os.access(helper, os.X_OK), "installed helper missing"
    body = helper.read_text()
    commands = [shlex.split(line) for line in body.splitlines() if line.startswith("exec ")]
    assert len(commands) == 1 and len(commands[0]) == 4, "unexpected installed helper exec"
    _, python, script, args = commands[0]
    assert args == "$@", "installed helper lost argument forwarding"
    python, script = Path(python), Path(script)
    assert str(python).startswith("/nix/store/") and python.name == "python3" and python.is_file(), "Python is not installed"
    assert str(script).startswith("/nix/store/") and script.is_file(), "helper source is not installed"
    expected = Path(__file__).resolve().parents[1] / "src/media/image.py"
    assert script.read_bytes() == expected.read_bytes(), "installed helper source differs from this checkout"
    bundles = re.findall(r"/nix/store/[^\s'\"{}]+/etc/ssl/certs/ca-bundle\.crt", body)
    assert len(set(bundles)) == 1 and Path(bundles[0]).is_file(), "installed CA bundle missing"
    return helper, python, script, Path(bundles[0])


def unpack(output: bytes, expected_size: tuple[int, int]) -> bytes:
    assert output.endswith(b"\n") and output.count(b"\n") == 1, "helper output is not one envelope"
    assert len(output) <= 4 * ((MAX_PAYLOAD + 2) // 3) + 1, "helper stdout exceeds its bound"
    payload = base64.b64decode(output.strip(), validate=True)
    assert payload[:8] == b"BIRCIMG1" and len(payload) <= MAX_PAYLOAD, "invalid or oversized envelope"
    width, height, count, iterations, rgba_length, gif_length = struct.unpack(">6I", payload[8:32])
    assert (width, height) == expected_size and 0 < width <= 320 and 0 < height <= 320, "incorrect normalized dimensions"
    assert (count, iterations, rgba_length, gif_length) == (1, 1, width * height * 4, 0), "invalid static metadata"
    offset = 32 + rgba_length
    duration, length = struct.unpack(">2I", payload[offset:offset + 8])
    offset += 8
    assert 20 <= duration <= 10000 and offset + length == len(payload), "invalid frame bounds"
    with Image.open(io.BytesIO(payload[offset:])) as frame:
        assert frame.format == "PNG" and frame.size == expected_size, "normalized frame is not PNG"
        assert frame.convert("RGBA").tobytes() == payload[32:32 + rgba_length], "PNG and RGBA disagree"
    return output


def local_controls(helper: Path, root: Path, env: dict[str, str]) -> tuple[Path, Path, Path]:
    png, jpeg = root / "synthetic image.png", root / "synthetic image.jpg"
    payload = root / "payload"
    for path, fmt in ((png, "PNG"), (jpeg, "JPEG")):
        Image.new("RGB", (17, 11), (20, 40, 60)).save(path, format=fmt)
        result = run([str(helper), "--local", str(path)], env)
        assert result.returncode == 0 and not result.stderr, "installed local helper failed"
        unpack(result.stdout, (17, 11))
        if fmt == "PNG":
            payload.write_bytes(result.stdout)
    larger = root / "resize.png"
    Image.new("RGB", (640, 480), (20, 40, 60)).save(larger)
    result = run([str(helper), "--local", str(larger)], env)
    assert result.returncode == 0 and not result.stderr, "normalization failed"
    unpack(result.stdout, (320, 240))

    malformed, dimensions, oversized, fifo, empty = [root / name for name in
        ("malformed.png", "dimensions.png", "oversized.png", "blocked.fifo", "empty.png")]
    malformed.write_bytes(b"not an image")
    Image.new("1", (4097, 1)).save(dimensions)
    with oversized.open("wb") as file:
        file.truncate(MAX_LOCAL_BYTES + 1)
    os.mkfifo(fifo)
    empty.touch()
    for path in (malformed, dimensions, oversized, fifo, empty, root, root / "missing.png"):
        result = run([str(helper), "--local", str(path)], env)
        assert result.returncode != 0 and not result.stdout, "invalid local input emitted a payload"
        assert result.stderr == b"birc-image: image unavailable\n", "failure exposed decoder/path text"
    return png, jpeg, payload


def ca_controls(helper: Path, python: Path, bundle: Path, png: Path, root: Path, env: dict[str, str]) -> None:
    # Trace only synthetic local execution, then load the chosen trust offline.
    shell = shlex.split(helper.read_text().splitlines()[0][2:])
    assert shell and shell[0].startswith("/nix/store/"), "helper shell is not installed"
    custom = root / "custom CA bundle.pem"
    custom.write_bytes(bundle.read_bytes())
    for value, expected in ((None, bundle), ("", bundle), (str(custom), custom)):
        current = dict(env)
        if value is not None:
            current["SSL_CERT_FILE"] = value
        result = run(shell + ["-x", str(helper), "--local", str(png)], current)
        assert result.returncode == 0, "CA wrapper local execution failed"
        unpack(result.stdout, (17, 11))
        selected = []
        for line in result.stderr.decode().splitlines():
            fields = shlex.split(line)
            if len(fields) == 3 and fields[:2] == ["+", "export"] and fields[2].startswith("SSL_CERT_FILE="):
                selected.append(fields[2].split("=", 1)[1])
        assert selected == [str(expected)], "CA fallback/override was not preserved"
        current["SSL_CERT_FILE"] = selected[0]
        check = run([str(python), "-c",
            "import ssl,sys; assert ssl.get_default_verify_paths().cafile == sys.argv[1]; "
            "assert ssl.create_default_context().cert_store_stats()['x509_ca'] > 0",
            selected[0]], current)
        assert check.returncode == 0 and not check.stderr, "installed Python cannot load selected CA trust"


def fake_helper(path: Path, label: str, python: Path, payload: Path) -> None:
    path.write_text(f"#!{python}\n" +
        "import json, os, pathlib, sys\n"
        "assert len(sys.argv) == 3 and sys.argv[1] == '--local'\n"
        "with open(os.environ['BIRC_PACKAGE_CALLS'], 'a') as out:\n"
        f"    out.write(json.dumps([{label!r}, sys.argv[1:]]) + '\\n')\n"
        f"sys.stdout.buffer.write(pathlib.Path({str(payload)!r}).read_bytes())\n")
    path.chmod(0o755)


def wrapper_case(binary: Path, jpeg: Path, env: dict[str, str], log: Path, case: str) -> list:
    master, slave = pty.openpty()
    saved = termios.tcgetattr(slave)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    try:
        process = subprocess.Popen([str(binary), "--plain", "--demo", "--frames", "0"],
            stdin=slave, stdout=slave, stderr=slave, env=env)
    except BaseException:
        os.close(master)
        raise
    finally:
        os.close(slave)

    captured = bytearray()
    phase = "startup"

    def painted(needle: bytes) -> None:
        output = bytearray()
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            chunk = drain(master, 0.05)
            output.extend(chunk)
            captured.extend(chunk)
            del captured[:-65536]
            if needle in output:
                return
            assert process.poll() is None, f"installed client exited before paint ({case}: {phase})"
        raise AssertionError(f"installed client did not paint local fixture ({case}: {phase})")

    try:
        painted(b"#birc")
        phase = "local-preview"
        os.write(master, f"/preview {jpeg}\r".encode())
        painted(b"\x1b_Ga=t,")
        phase = "shutdown"
        os.write(master, b"/quit\r")
        drain(master, 0.2)
        assert process.wait(timeout=3) == 0, "installed client did not quit cleanly"
        assert termios.tcgetattr(master) == saved, "installed client left tty state changed"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        # The child sees only this clean synthetic fixture. Keep bounded tails
        # outside its temporary directory so a failure remains diagnosable.
        try:
            evidence_root = Path(__file__).resolve().parents[1] / "build"
            evidence_root.mkdir(exist_ok=True)
            evidence = Path(tempfile.mkdtemp(prefix="package-failure-", dir=evidence_root))
            (evidence / "output-tail.bin").write_bytes(captured)
            calls = b""
            if log.exists():
                with log.open("rb") as stream:
                    stream.seek(max(0, log.stat().st_size - 16384))
                    calls = stream.read(16384)
            (evidence / "helper-calls-tail.jsonl").write_bytes(calls)
            (evidence / "failure.json").write_text(json.dumps({
                "case": case, "phase": phase, "error": str(error),
                "returncode": process.poll(), "output_tail_bytes": len(captured),
                "helper_calls_tail_bytes": len(calls),
            }) + "\n")
            print(f"package evidence: case={case!r} phase={phase} path={evidence}", file=sys.stderr)
        except OSError as evidence_error:
            print(f"package evidence: case={case!r} phase={phase} unavailable: {evidence_error}", file=sys.stderr)
        raise
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        os.close(master)


def wrapper_controls(binary: Path, python: Path, jpeg: Path, payload: Path, root: Path, env: dict[str, str]) -> None:
    fallback = Path(env["PATH"]) / "birc-image"
    override = root / "override helper with spaces"
    fake_helper(fallback, "fallback", python, payload)
    fake_helper(override, "override", python, payload)
    failures = []
    for name, value, expected in (("unset", None, []),
            ("nonempty override", str(override), [["override", ["--local", str(jpeg)]]]),
            ("empty PATH fallback", "", [["fallback", ["--local", str(jpeg)]]])):
        log = root / (name.replace(" ", "-") + ".calls")
        current = {**env, "TERM": "xterm-kitty", "TERM_PROGRAM": "kitty",
            "BIRC_FORCE_IMAGE_PROTOCOL": "kitty", "BIRC_HISTORY": "none", "BIRC_IMAGES": "off",
            "BIRC_PACKAGE_CALLS": str(log)}
        if value is not None:
            current["BIRC_MEDIA_HELPER"] = value
        if wrapper_case(binary, jpeg, current, log, name) != expected:
            failures.append(name)
    assert not failures, "installed wrapper rejected: " + ", ".join(failures)


def main(argument: str) -> None:
    target = Path(argument).resolve()
    binary = target / "bin/birc" if target.is_dir() else target
    helper, python, _, bundle = provenance(binary)
    with tempfile.TemporaryDirectory(prefix="birc-package-") as temporary:
        root = Path(temporary)
        fake_bin = root / "fake-bin"
        fake_bin.mkdir()
        env = environment(root, fake_bin)
        help_result = run([str(binary), "--help-irc"], env)
        assert help_result.returncode == 2 and b"--connect" in help_result.stdout + help_result.stderr, "installed usage smoke failed"
        demo_result = run([str(binary), "--plain", "--demo", "--frames", "1"],
            {**env, "TERM": "xterm-256color", "BIRC_HISTORY": "none", "BIRC_IMAGES": "off"})
        assert demo_result.returncode == 0 and b"birc=ok" in demo_result.stdout + demo_result.stderr, "installed headless smoke failed"
        png, jpeg, payload = local_controls(helper, root, env)
        ca_controls(helper, python, bundle, png, root, env)
        wrapper_controls(binary, python, jpeg, payload, root, env)
    print("package=ok")


if __name__ == "__main__":
    try:
        assert len(sys.argv) == 2, "expected installed package or birc wrapper path"
        main(sys.argv[1])
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"package: {error}", file=sys.stderr)
        raise SystemExit(1)
