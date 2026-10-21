#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Live Bend completion and native payload ownership agree at cache capacity.

All image URLs are synthetic. The local fake helper returns fixture envelopes;
no URL is fetched and no desktop helper is invoked.
"""
import base64
import os
from pathlib import Path
import re
import sys
import tempfile

from media import Live, assets
from media_envelope import envelope


def png_uploads(data):
    result, current = [], bytearray()
    for command in re.findall(rb'\x1b_G([^\x1b]*)\x1b\\', data):
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


def fixtures(directory):
    assets(directory)
    expected = {}
    for index, name in enumerate(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i']):
        encoded, png = envelope(4, 4, (index * 20, 50, 100, 255))
        (directory / (name + '.png.txt')).write_text(encoded + '\n')
        expected[name] = png
    return expected


def main():
    binary = os.path.abspath(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix='birc-m20-cache-') as name:
        directory = Path(name)
        expected = fixtures(directory)
        live = Live(binary, directory, 'kitty')
        try:
            helper = directory / 'helper'
            source = helper.read_text()
            old = '("animated.txt" if ".GIF" in source or "slow" in source else "still.txt")'
            assert old in source
            helper.write_text(source.replace(old, '(source.rsplit("/", 1)[-1] + ".txt")'))
            for index, letter in enumerate('abcdefg', 1):
                url = 'https://offline.invalid/' + letter + '.png'
                live.conn.sendall(f':alice{index}!u@h PRIVMSG probe :{url}\r\n'.encode())
                live.command('/query alice' + str(index))
                live.until(lambda: expected[letter] in png_uploads(live.output))
            manual = 'https://offline.invalid/h.png'
            live.command('/preview ' + manual)
            live.until(lambda: expected['h'] in png_uploads(live.output))
            live.command('/preview ' + manual)
            live.until(lambda: png_uploads(live.output).count(expected['h']) == 2)
            live.output.clear()
            live.command('/query alice1')
            live.until(lambda: expected['a'] in png_uploads(live.output))
            assert live.calls().count(['https://offline.invalid/a.png']) == 1, 'retained inline result was refetched'
            # Keep H's manual topic alive; a ninth inline result now evicts A.
            live.conn.sendall(b':alice8!u@h PRIVMSG probe :https://offline.invalid/i.png\r\n')
            live.command('/query alice8')
            live.until(lambda: expected['i'] in png_uploads(live.output))
            live.output.clear()
            live.command('/query alice1')
            live.until(lambda: b'https://offline.invalid/a.png' in live.output)
            assert expected['a'] not in png_uploads(live.output), 'evicted oldest result was uploaded'
            assert live.calls().count(['https://offline.invalid/a.png']) == 1, 'old eviction incorrectly retriggered automatic fetch'
            live.output.clear()
            live.command('/query alice2')
            live.until(lambda: expected['b'] in png_uploads(live.output))
            live.pong('cache-coherent')
            live.stop()
        finally:
            live.close()
    print('m20_media_cache_pty=ok')


if __name__ == '__main__':
    main()
