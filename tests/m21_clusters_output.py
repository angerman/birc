#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Actual Bend SpanOps reach native paint as complete styled clusters."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    birc = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "./build/birc")
    source = "M21CLUSTER e*́*X 👩*‍💻*X M21END"
    expected = "M21CLUSTER éX 👩‍💻X M21END".encode()
    control = "M21CONTROL éX 👩‍💻X M21DONE".encode()
    env = {**os.environ, "TERM": "xterm-256color", "TERM_PROGRAM": "",
           "BIRC_IMAGES": "off", "BIRC_HISTORY": "none",
           "BIRC_MEDIA_HELPER": "/nonexistent-test-helper"}
    for key in ("BIRC_DIE_AFTER_OPEN", "BIRC_FRAME_PROFILE", "BIRC_FORCE_IMAGE_PROTOCOL", "TIMUI_TRACE"):
        env.pop(key, None)
    with tempfile.TemporaryDirectory(prefix="birc-m21-clusters-") as directory:
        replay = Path(directory) / "synthetic.irc"
        replay.write_text(":me!u@h JOIN #t\n"
                          ":alice!u@h PRIVMSG #t :" + control.decode() + "\n"
                          ":alice!u@h PRIVMSG #t :" + source + "\n", encoding="utf-8")
        reader, writer = os.pipe()  # held headless input; not an EOF paint
        try:
            result = subprocess.run([birc, "--nick", "me", "--channel", "#t", "--replay", str(replay), "--frames", "1"],
                                    stdin=reader, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=env, timeout=15)
        finally:
            os.close(reader)
            os.close(writer)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    assert control in result.stdout, "whole-cluster positive control did not paint"
    assert expected in result.stdout, "styled boundary split or dropped a painted cluster"
    print("m21_clusters_output=ok")


if __name__ == "__main__":
    main()
