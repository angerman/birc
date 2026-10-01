#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Painter bytes: Unicode clusters and exact terminal OSC8 targets."""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def main():
    birc = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else './build/birc')
    short = 'https://example.test/ok'
    long = 'https://example.test/' + 'a' * 276
    text = 'ASCIICONTROL é é 👍🏽 👩‍💻 ❤︎ ENDUNICODE'
    env = {**os.environ, 'TERM': 'xterm-256color', 'TERM_PROGRAM': '',
           'BIRC_IMAGES': 'off', 'BIRC_HISTORY': 'none',
           'BIRC_MEDIA_HELPER': '/nonexistent-test-helper'}
    for key in ('BIRC_DIE_AFTER_OPEN', 'BIRC_FRAME_PROFILE', 'BIRC_FORCE_IMAGE_PROTOCOL', 'TIMUI_TRACE'):
        env.pop(key, None)
    with tempfile.TemporaryDirectory(prefix='birc-ui-output-') as directory:
        replay = Path(directory) / 'synthetic.irc'
        replay.write_text(':me!u@h JOIN #t\n'
                          ':alice!u@h PRIVMSG #t :' + text + '\n'
                          ':alice!u@h PRIVMSG #t :SHORT ' + short + ' END_SHORT\n'
                          ':alice!u@h PRIVMSG #t :LONG ' + long + ' END_LONG\n', encoding='utf-8')
        reader, writer = os.pipe()  # held input: bounded headless paint, not EOF
        try:
            result = subprocess.run([birc, '--nick', 'me', '--channel', '#t', '--replay', str(replay), '--frames', '1'],
                                    stdin=reader, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=env, timeout=15)
        finally:
            os.close(reader); os.close(writer)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    output = result.stdout
    assert text.encode() in output, 'painter lost or separated cluster components'
    targets = re.findall(rb'\x1b\]8;;([^\x1b\x07]+)(?:\x1b\\|\x07)', output)
    assert short.encode() in targets, 'short URL positive control'
    assert long.encode() in targets, 'long terminal URL was altered'
    assert all(target == long.encode() for target in targets if target.startswith(b'https://example.test/aaaa'))
    print('ui_review_output=ok')


if __name__ == '__main__':
    main()
