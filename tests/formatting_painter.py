#!/usr/bin/env python3
"""Exercise real Bend-to-TimUI formatting without a network or a pty."""

import os
import subprocess
import sys

from richtext_painter import rendered


URL = "https://x.test/a_b/:eyes:?q=**z**"
STYLED_URL = "https://nested.test/a_b/:eyes:"


def check(data):
    text, attrs = rendered(data)
    failures = []
    for token, wanted in (("SINGLE", 1), ("DOUBLE", 1), ("BOTH", 5),
                          ("BOLDCODE", 3), ("*ESCAPED*", 0), ("👀", 0),
                          ("🤣", 0), (":Eyes:", 0), (":unknown:", 0),
                          (":fire:", 2), ("**UNMATCHED", 0), (STYLED_URL, 5)):
        start = text.find(token)
        if start < 0 or attrs[start:start + len(token)] != [wanted] * len(token):
            failures.append(f"{token!r}: expected attrs={wanted}")
    if URL not in text or f"\x1b]8;;{URL}\x1b\\".encode() not in data:
        failures.append("exact hyperlink URL missing")
    if f"\x1b]8;;{STYLED_URL}\x1b\\".encode() in data:
        failures.append("styled URL unexpectedly became a hyperlink")
    if "birc=ok" not in text:
        failures.append("completion token missing")
    return failures


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: formatting_painter.py ./build/birc fixtures/formatting.irc")
    control = ("\x1b[0;1mSINGLE DOUBLE\x1b[0;1;3mBOTH\x1b[0;1;2mBOLDCODE"
               "\x1b[0m*ESCAPED* 👀 🤣 :Eyes: :unknown:"
               "\x1b[0;2m:fire:\x1b[0m**UNMATCHED "
               f"\x1b]8;;{URL}\x1b\\{URL}\x1b]8;;\x1b\\ "
               f"\x1b[0;1;3m{STYLED_URL}\x1b[0m birc=ok").encode()
    bad_style = control.replace(b"\x1b[0;1;3mBOTH", b"\x1b[0;1mBOTH")
    bad_alias = control.replace("👀".encode(), b":eyes:")
    bad_url = control.replace(URL.encode(), URL.replace(":eyes:", "👀").encode())
    bad_identity = control + f"\x1b]8;;{STYLED_URL}\x1b\\".encode()
    if check(control) or not all(check(case) for case in (bad_style, bad_alias, bad_url, bad_identity)):
        raise SystemExit("formatting_painter: checker +/- controls failed")
    env = os.environ.copy()
    env.update(TERM="xterm-256color", TERM_PROGRAM="", BIRC_HISTORY="none")
    for name in ("BIRC_DIE_AFTER_OPEN", "BIRC_FRAME_PROFILE", "BIRC_FORCE_IMAGE_PROTOCOL", "TIMUI_TRACE"):
        env.pop(name, None)
    read_fd, write_fd = os.pipe()
    try:
        proc = subprocess.run([sys.argv[1], "--nick", "me", "--replay", sys.argv[2], "--frames", "1"],
                              stdin=read_fd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              env=env, timeout=10, check=False)
    except subprocess.TimeoutExpired as error:
        raise SystemExit("formatting_painter: native fixture exceeded 10 seconds") from error
    finally:
        os.close(read_fd)
        os.close(write_fd)
    failures = check(proc.stdout)
    if proc.returncode:
        failures.append(f"native exit={proc.returncode}, stderr={proc.stderr!r}")
    if failures:
        raise SystemExit("formatting_painter: " + "; ".join(failures)
                         + f"; rendered={rendered(proc.stdout)[0][-3000:]!r}")
    print("formatting_painter=ok")


if __name__ == "__main__":
    main()
