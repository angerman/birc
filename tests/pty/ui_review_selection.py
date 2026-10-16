#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Selection dismissal must repaint the same frame; no clipboard helper."""
import fcntl
import os
import pty
import re
import select
import signal
import struct
import sys
import subprocess
import termios
import time
import unicodedata

BIRC = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else './build/birc')


def drain(fd, seconds):
    data = bytearray()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], min(0.05, max(0, deadline - time.monotonic())))
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            data.extend(chunk)
    return bytes(data)


def cells(data):
    """Minimal cursor/SGR emulator; no terminal or helper side effects."""
    grid = [[[' ', False] for _ in range(80)] for _ in range(24)]
    y = x = 0
    reverse = False
    saved = (0, 0)
    source = data.decode('utf-8', 'replace')
    token = re.compile(r'\x1b\][^\x1b\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]|\x1b.|[^\x1b]+', re.S)
    for item in token.finditer(source):
        text = item.group()
        if text.startswith('\x1b]'):
            continue
        if text.startswith('\x1b['):
            body, final = text[2:-1], text[-1]
            if body.startswith(('?', '>', '=')):
                continue
            params = [int(p or '0') for p in body.split(';')] if body else [0]
            amount = params[0] or 1
            if final in ('H', 'f'):
                y = max(0, min(23, amount - 1))
                x = max(0, min(79, (params[1] if len(params) > 1 and params[1] else 1) - 1))
            elif final == 'A': y = max(0, y - amount)
            elif final == 'B': y = min(23, y + amount)
            elif final == 'C': x = min(79, x + amount)
            elif final == 'D': x = max(0, x - amount)
            elif final == 'G': x = min(79, amount - 1)
            elif final == 'd': y = min(23, amount - 1)
            elif final == 's': saved = (y, x)
            elif final == 'u': y, x = saved
            elif final == 'J' and params[0] in (2, 3):
                grid = [[[' ', reverse] for _ in range(80)] for _ in range(24)]
            elif final == 'K':
                start = 0 if params[0] in (1, 2) else x
                end = 80 if params[0] in (0, 2) else x + 1
                for col in range(start, end): grid[y][col] = [' ', reverse]
            elif final == 'm':
                pos = 0
                while pos < len(params):
                    attr = params[pos]
                    if attr in (38, 48) and pos + 1 < len(params):
                        pos += 5 if params[pos + 1] == 2 else 3
                        continue
                    if attr == 0: reverse = False
                    elif attr == 7: reverse = True
                    elif attr == 27: reverse = False
                    pos += 1
            continue
        if text.startswith('\x1b'):
            continue
        for ch in text:
            if ch == '\r': x = 0
            elif ch == '\n': y = min(23, y + 1)
            elif ch == '\b': x = max(0, x - 1)
            elif ord(ch) >= 32 and not unicodedata.combining(ch):
                if x >= 80:
                    x = 0
                    y = min(23, y + 1)
                grid[y][x] = [ch, reverse]
                x += 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
    return grid


def row_state(data):
    grid = cells(data)
    segment = grid[4][4:15]
    return ''.join(c[0] for c in segment), [c[1] for c in segment]


def main():
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    env = {**os.environ, 'TERM': 'xterm-256color', 'TERM_PROGRAM': '',
           'BIRC_IMAGES': 'off', 'BIRC_HISTORY': 'none',
           'BIRC_PREFERENCES': 'none',
           'BIRC_MEDIA_HELPER': '/nonexistent-audit-helper',
           'PATH': '/nonexistent-audit-path'}
    for key in ('BIRC_DIE_AFTER_OPEN', 'BIRC_FRAME_PROFILE', 'BIRC_FORCE_IMAGE_PROTOCOL', 'TIMUI_TRACE'):
        env.pop(key, None)
    proc = subprocess.Popen([BIRC, '--plain', '--demo', '--frames', '0'],
                            stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True)
    os.close(slave)
    stages = {}
    accumulated = bytearray()
    try:
        stages['initial'] = drain(master, 1.0)
        accumulated.extend(stages['initial'])
        initial = row_state(accumulated)
        assert initial[0] == ' ' * 11 and not any(initial[1]), initial
        os.write(master, b'\x1b[<0;5;5M')
        accumulated.extend(drain(master, 0.15))
        os.write(master, b'\x1b[<32;15;5M')
        accumulated.extend(drain(master, 0.15))
        os.write(master, b'\x1b[<0;15;5m')
        stages['selected'] = drain(master, 0.4)
        accumulated.extend(stages['selected'])
        selected = row_state(accumulated)
        assert selected[0] == ' ' * 11 and any(selected[1]), selected
        assert b'\x1b]52;' not in accumulated, 'blank selection unexpectedly copied'
        os.write(master, b'\x1b')
        stages['escaped'] = drain(master, 1.3)
        accumulated.extend(stages['escaped'])
        escaped = row_state(accumulated)
        assert proc.poll() is None, 'Escape quit rather than dismissed selection'
        proc.send_signal(signal.SIGWINCH)
        stages['resized'] = drain(master, 0.6)
        accumulated.extend(stages['resized'])
        resized = row_state(accumulated)
        assert not any(escaped[1]), 'Escape left the selected cells highlighted'
        assert not any(resized[1]), 'resize positive control'
        print('ui_review_selection=ok')
        os.write(master, b'/quit\r')
        proc.wait(timeout=5)
        assert proc.returncode == 0, proc.returncode
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)
        os.close(master)


if __name__ == '__main__':
    main()
