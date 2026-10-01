"""Replay all bytes, including final records and split UTF-8. No network."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HEAD = b":irc NOTICE * :CAPHEADMARKER\r\n"
TAIL = b":irc NOTICE * :CAPTAILMARKER\r\n"


def padding(size):
    # Blank IRC lines produce no events. Keep each line within the wire limit.
    full, rest = divmod(size, 512)
    return (b" " * 510 + b"\r\n") * full + b"\n" * rest


def run(label, data, markers):
    fixture = directory / (label + ".irc")
    fixture.write_bytes(data)
    read_fd, write_fd = os.pipe()
    try:
        result = subprocess.run(
            [sys.argv[1], "--nick", "probe", "--replay", str(fixture), "--frames", "1"],
            stdin=read_fd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=env, timeout=20, check=False,
        )
    finally:
        os.close(read_fd)
        os.close(write_fd)
    assert result.returncode == 0 and b"birc=ok" in result.stdout, (
        label, result.returncode, result.stderr)
    for marker in markers:
        assert marker in result.stdout, (label, f"missing {marker!r}")
    print(f"{label}: bytes={len(data)} complete", flush=True)


def fail_closed(label, fixture):
    result = subprocess.run(
        [sys.argv[1], "--replay", str(fixture), "--frames", "1"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=env, timeout=20, check=False,
    )
    assert result.returncode != 0 and b"cannot read replay" in result.stderr, (
        label, result.returncode, result.stderr)
    assert b"birc=ok" not in result.stdout, (label, result.stdout)
    print(f"{label}: failed closed", flush=True)


env = dict(os.environ, TERM="xterm-256color", TERM_PROGRAM="",
           BIRC_HISTORY="none", BIRC_IMAGES="off", BIRC_SASL_USER="", BIRC_SASL_PASS="")
for name in ("BIRC_DIE_AFTER_OPEN", "BIRC_FRAME_PROFILE", "BIRC_FORCE_IMAGE_PROTOCOL", "TIMUI_TRACE"):
    env.pop(name, None)

with tempfile.TemporaryDirectory(prefix="replay-stream-", dir="build") as temp:
    directory = Path(temp)
    run("small", HEAD + TAIL, (b"CAPHEADMARKER", b"CAPTAILMARKER"))
    run("large", HEAD + padding(1048576 - len(HEAD)) + TAIL,
        (b"CAPHEADMARKER", b"CAPTAILMARKER"))
    prefix = b":irc NOTICE * :UTFMARK"
    split = padding(4095 - len(prefix)) + prefix + "éDONE\r\n".encode()
    assert split[4095:4097] == "é".encode()
    run("split-utf8", split, ("UTFMARKéDONE".encode(),))
    prefix = b":irc NOTICE * :"
    marker = b"CHUNKBOUNDARYMARKER"
    split = padding(4090 - len(prefix)) + prefix + marker + b"\r\n"
    assert split.index(marker) == 4090
    run("split-record", split, (marker,))
    record = prefix + b"CRLFMARKER"
    split = padding(4095 - len(record)) + record + b"\r\n"
    assert split[4095:4097] == b"\r\n"
    run("split-crlf", split, (b"CRLFMARKER",))
    run("unterminated", HEAD + TAIL.rstrip(b"\r\n"), (b"CAPHEADMARKER", b"CAPTAILMARKER"))
    run("empty", b"", ())
    fail_closed("missing", directory / "missing.irc")
    # A sparse file exercises File.size's U32 limit without a 4-GiB read.
    oversized = directory / "oversized.irc"
    with oversized.open("wb") as file:
        file.truncate(4294967296)
    fail_closed("oversized", oversized)
print("replay_stream=ok", flush=True)
