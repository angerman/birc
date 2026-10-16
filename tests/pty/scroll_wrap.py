#!/usr/bin/env python3
"""PageUp reaches a wrapped message's first row; PageDown returns to live."""
import fcntl
import os
import pty
import socket
import struct
import subprocess
import sys
import termios

from softwrap import drain, plain, recv_until


def main():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        listener.settimeout(10)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 8, 40, 0, 0))
        proc = subprocess.Popen(
            [sys.argv[1], "--plain", "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
             "--nick", "probe", "--channel", "#t", "--frames", "0"],
            stdin=slave, stdout=slave, stderr=slave, close_fds=True,
            env={**os.environ, "TERM": "xterm-256color", "BIRC_PREFERENCES": "none", "BIRC_HISTORY": "none"},
        )
        os.close(slave)
        conn = None
        try:
            conn, _ = listener.accept()
            recv_until(conn, master, b"USER probe")
            conn.setblocking(True)
            conn.sendall(b":s 001 probe :Welcome\r\n")
            recv_until(conn, master, b"JOIN #t\r\n")
            conn.setblocking(True)
            conn.sendall(b":probe!p@h JOIN #t\r\n")
            drain(master, 0.5)
            conn.sendall(b":a!a@h PRIVMSG #t :HEAD" + b"x" * 101 + b"TAIL\r\n")
            initial = plain(drain(master, 0.8))
            assert b"HEAD" not in initial, "fixture did not wrap beyond the viewport"
            assert b"TAIL" in initial, "live tail was not visible"
            top = bytearray()
            for _ in range(16):
                os.write(master, b"\x1b[5~")
                top.extend(drain(master, 0.12))
            top.extend(drain(master, 0.4))
            assert b"HEAD" in plain(bytes(top)), "PageUp cannot reach the first wrapped row"
            bottom = bytearray()
            for _ in range(16):
                os.write(master, b"\x1b[6~")
                bottom.extend(drain(master, 0.12))
            bottom.extend(drain(master, 0.4))
            assert b"TAIL" in plain(bytes(bottom)), "PageDown cannot return to the live tail"
            os.write(master, b"/quit\r")
            proc.wait(timeout=8)
            assert proc.returncode == 0, proc.returncode
            print("scroll_wrap=ok")
        finally:
            if conn is not None:
                conn.close()
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)


if __name__ == "__main__":
    main()
