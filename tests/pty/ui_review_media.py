#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Local manual PNG previews obey native admission: reject garbage, paint accepted."""
import base64
import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

from media_envelope import png_rgba


def drain(fd, seconds):
    result = bytearray()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], min(0.05, max(0, deadline - time.monotonic())))
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            result.extend(data)
    return bytes(result)


def uploads(output):
    result, current = [], bytearray()
    for command in re.findall(rb'\x1b_G([^\x1b]*)\x1b\\', output):
        if b';' not in command:
            continue
        parameters, encoded = command.split(b';', 1)
        if parameters.startswith(b'a=t,'):
            current = bytearray()
        if parameters.startswith(b'a=t,') or parameters.startswith(b'm='):
            current.extend(base64.b64decode(encoded, validate=True))
            if b'm=1' not in parameters:
                result.append(bytes(current))
                current = bytearray()
    return result


def main():
    birc = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else './build/birc')
    with tempfile.TemporaryDirectory(prefix='birc-ui-media-') as directory:
        reject, positive = Path(directory) / 'reject.png', Path(directory) / 'valid.png'
        reject.write_bytes(b'not-an-image')
        positive.write_bytes(png_rgba(17, 11, (20, 40, 60, 255)))
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        env = {**os.environ, 'TERM': 'xterm-kitty', 'TERM_PROGRAM': '',
               'BIRC_FORCE_IMAGE_PROTOCOL': 'kitty', 'BIRC_HISTORY': 'none',
               'BIRC_PREFERENCES': 'none',
               'BIRC_IMAGES': 'off', 'BIRC_MEDIA_HELPER': 'native', 'PATH': '/nonexistent-test-path'}
        for key in ('BIRC_DIE_AFTER_OPEN', 'BIRC_FRAME_PROFILE', 'TIMUI_TRACE'):
            env.pop(key, None)
        proc = subprocess.Popen([birc, '--plain', '--demo', '--frames', '0'], stdin=slave, stdout=slave, stderr=slave,
                                env=env, close_fds=True)
        os.close(slave)
        try:
            assert b'#birc' in drain(master, 0.5)
            os.write(master, ('/preview ' + str(reject) + '\r').encode())
            output = bytearray()
            deadline = time.monotonic() + 6
            while b'image preview unavailable' not in output and time.monotonic() < deadline:
                output.extend(drain(master, 0.1))
                assert not uploads(output), 'pending/rejected original image was uploaded'
            output.extend(drain(master, 0.3))
            assert b'image preview unavailable' in output, 'native rejection was not reported'
            assert not uploads(output), 'failed local PNG bypassed native admission'
            os.write(master, ('/preview ' + str(positive) + '\r').encode())
            output = bytearray()
            deadline = time.monotonic() + 6
            while not any(item.startswith(b'\x89PNG') for item in uploads(output)) and time.monotonic() < deadline:
                output.extend(drain(master, 0.1))
            assert any(item.startswith(b'\x89PNG') for item in uploads(output)), 'accepted native PNG was not painted'
            os.write(master, b'/quit\r')
            proc.wait(timeout=5)
            assert proc.returncode == 0
        finally:
            if proc.poll() is None:
                proc.kill(); proc.wait(timeout=5)
            os.close(master)
    print('ui_review_media=ok')


if __name__ == '__main__':
    main()
