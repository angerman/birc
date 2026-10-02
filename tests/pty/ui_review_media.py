#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Local manual PNG previews obey the actual helper's acceptance boundary."""
import base64
import fcntl
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

# This directory has an IRC typing.py fixture; do not shadow stdlib typing
# when Pillow imports it. No local test modules are needed by this guard.
sys.path = [entry for entry in sys.path if Path(entry).resolve() != Path(__file__).resolve().parent]
from PIL import Image


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
    helper = sys.argv[2] if len(sys.argv) > 2 else os.environ.get('BIRC_MEDIA_HELPER') or shutil.which('birc-image')
    assert helper and os.path.isfile(helper), 'the provisioned image helper is required'
    with tempfile.TemporaryDirectory(prefix='birc-ui-media-') as directory:
        apng, positive = Path(directory) / '25frames.png', Path(directory) / 'valid.png'
        frames = [Image.new('RGB', (17, 11), (index * 10, 20, 30)) for index in range(25)]
        frames[0].save(apng, format='PNG', save_all=True, append_images=frames[1:], duration=80, loop=0)
        Image.new('RGB', (17, 11), (20, 40, 60)).save(positive, format='PNG')
        with Image.open(apng) as source:
            assert source.n_frames == 25 and source.size == (17, 11)
        negative = subprocess.run([helper, '--local', str(apng)], capture_output=True, timeout=12)
        control = subprocess.run([helper, '--local', str(positive)], capture_output=True, timeout=12)
        assert negative.returncode == 1 and not negative.stdout
        assert control.returncode == 0
        envelope = base64.b64decode(control.stdout.strip(), validate=True)
        assert envelope.startswith(b'BIRCIMG1')
        _, _, count, _, rgba_size, gif_size = struct.unpack('>6I', envelope[8:32])
        assert count == 1
        offset = 32 + rgba_size + gif_size
        _, png_size = struct.unpack('>2I', envelope[offset:offset + 8])
        normalized_png = envelope[offset + 8:offset + 8 + png_size]
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        env = {**os.environ, 'TERM': 'xterm-kitty', 'TERM_PROGRAM': '',
               'BIRC_FORCE_IMAGE_PROTOCOL': 'kitty', 'BIRC_HISTORY': 'none',
               'BIRC_IMAGES': 'off', 'BIRC_MEDIA_HELPER': helper, 'PATH': '/nonexistent-test-path'}
        for key in ('BIRC_DIE_AFTER_OPEN', 'BIRC_FRAME_PROFILE', 'TIMUI_TRACE'):
            env.pop(key, None)
        proc = subprocess.Popen([birc, '--plain', '--demo', '--frames', '0'], stdin=slave, stdout=slave, stderr=slave,
                                env=env, close_fds=True)
        os.close(slave)
        try:
            assert b'#birc' in drain(master, 0.5)
            os.write(master, ('/preview ' + str(apng) + '\r').encode())
            output = bytearray()
            deadline = time.monotonic() + 6
            while b'image preview unavailable' not in output and time.monotonic() < deadline:
                output.extend(drain(master, 0.1))
                assert not uploads(output), 'pending/rejected original image was uploaded'
            output.extend(drain(master, 0.3))
            assert b'image preview unavailable' in output, 'helper rejection was not reported'
            assert not uploads(output), 'failed local PNG bypassed the helper'
            os.write(master, ('/preview ' + str(positive) + '\r').encode())
            output = bytearray()
            deadline = time.monotonic() + 6
            while normalized_png not in uploads(output) and time.monotonic() < deadline:
                output.extend(drain(master, 0.1))
            assert normalized_png in uploads(output), 'accepted helper PNG was not painted'
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
