#!/usr/bin/env python3
"""Check the real Bend-to-TimUI painter with pipes, not a timing-sensitive pty."""

import os
import re
import subprocess
import sys


ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")


def rendered(data):
    """Retain printable cells and their bold/dim/italic SGR attributes."""
    text = data.decode("utf-8", errors="strict")
    cells = []
    attrs = 0
    cursor = 0
    for match in ESCAPE.finditer(text):
        cells.extend((char, attrs) for char in text[cursor:match.start()] if char >= " ")
        escape = match.group()
        if escape.startswith("\x1b[") and escape.endswith("m"):
            values = [int(value or "0") for value in escape[2:-1].split(";")]
            index = 0
            while index < len(values):
                value = values[index]
                if value == 0:
                    attrs = 0
                elif value == 1:
                    attrs |= 1
                elif value == 2:
                    attrs |= 2
                elif value == 3:
                    attrs |= 4
                elif value == 22:
                    attrs &= ~3
                elif value == 23:
                    attrs &= ~4
                elif value in (38, 48) and index + 1 < len(values):
                    mode = values[index + 1]
                    index += 4 if mode == 2 else 2 if mode == 5 else 1
                index += 1
        cursor = match.end()
    cells.extend((char, attrs) for char in text[cursor:] if char >= " ")
    return "".join(char for char, _ in cells), [attr for _, attr in cells]


def check(data):
    text, attrs = rendered(data)
    failures = []
    for token, wanted in (("BOLD", 1), ("ITALIC", 4), ("CODE", 2), ("PLAIN", 0)):
        start = text.find(token)
        if start < 0 or attrs[start:start + len(token)] != [wanted] * len(token):
            failures.append(f"{token}: expected attrs={wanted}, got {attrs[start:start + len(token)]}")
    for token in ("*UNCLOSED_STAR", "_UNCLOSEDUNDERSCORE", "`UNCLOSED_TICK"):
        start = text.find(token)
        if start < 0 or attrs[start:start + len(token)] != [0] * len(token):
            failures.append(f"literal plain source order missing: {token}")
    if "birc=ok" not in text:
        failures.append("missing native completion token")
    return failures


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: richtext_painter.py ./build/birc fixtures/richtext.irc")
    control = (b"\x1b[0;1mBOLD\x1b[0;3mITALIC\x1b[0;2mCODE"
               b"\x1b[0;38;2;2;2;2mPLAIN *UNCLOSED_STAR _UNCLOSEDUNDERSCORE"
               b" `UNCLOSED_TICK birc=ok")
    if (check(control) or not check(control.replace(b"\x1b[0;2mCODE", b"\x1b[0mCODE"))
            or not check(control.replace(b"*UNCLOSED_STAR", b"UNCLOSED_STAR*"))):
        raise SystemExit("richtext_painter: checker positive/negative controls failed")
    env = os.environ.copy()
    env.update(TERM="xterm-256color", TERM_PROGRAM="", BIRC_HISTORY="none")
    for name in ("BIRC_DIE_AFTER_OPEN", "BIRC_FRAME_PROFILE", "BIRC_FORCE_IMAGE_PROTOCOL", "TIMUI_TRACE"):
        env.pop(name, None)
    read_fd, write_fd = os.pipe()
    try:
        # Keep the pipe writer open: immediate EOF correctly abandons the frame.
        # The non-tty path remains headless and exits after its one requested frame.
        proc = subprocess.run([sys.argv[1], "--nick", "me", "--replay", sys.argv[2], "--frames", "1"],
                              stdin=read_fd, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, env=env, timeout=10, check=False)
    except subprocess.TimeoutExpired as error:
        raise SystemExit("richtext_painter: native fixture exceeded 10 seconds") from error
    finally:
        os.close(read_fd)
        os.close(write_fd)
    failures = check(proc.stdout)
    if proc.returncode:
        failures.append(f"native exit={proc.returncode}, stderr={proc.stderr!r}")
    if failures:
        raise SystemExit("richtext_painter: " + "; ".join(failures)
                         + f"; rendered={rendered(proc.stdout)[0][-3000:]!r}")
    print("richtext_painter=ok")


if __name__ == "__main__":
    main()
