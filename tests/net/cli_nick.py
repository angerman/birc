"""Check final registration nicknames against a bounded loopback server."""
import os
import socket
import subprocess
import sys


def capture(label, options, expected, env_user=""):
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(3)
        env = dict(os.environ, BIRC_HISTORY="none", BIRC_IMAGES="off",
                   BIRC_SASL_USER=env_user, BIRC_SASL_PASS="synthetic")
        proc = subprocess.Popen(
            [sys.argv[1], "--plain", "--connect", "127.0.0.1", "--port",
             str(listener.getsockname()[1]), "--frames", "2",
             "--channel", "#audit", *options], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
        try:
            with listener.accept()[0] as conn:
                conn.settimeout(3)
                wire = bytearray()
                while b"\r\nUSER " not in wire:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    wire.extend(chunk)
            output, _ = proc.communicate(timeout=3)
            nick = next((line[5:].decode("ascii") for line in wire.split(b"\r\n")
                         if line.startswith(b"NICK ")), None)
            assert proc.returncode == 0 and b"birc=ok" in output, (
                label, proc.returncode, output)
            assert nick == expected, (label, expected, nick)
            print(f"{label}: nick={nick}", flush=True)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=2)


capture("implicit-default", [], "birc")
capture("implicit-cli-user", ["--sasl-user", "alice"], "alice")
capture("implicit-env-user", [], "alice", "alice")
capture("explicit-bob", ["--nick", "bob", "--sasl-user", "alice"], "bob")
for nick in ("me", "birc"):
    capture(f"{nick}-before-user", ["--nick", nick, "--sasl-user", "alice"], nick)
    capture(f"{nick}-after-user", ["--sasl-user", "alice", "--nick", nick], nick)
    capture(f"{nick}-env-user", ["--nick", nick], nick, "alice")
    capture(f"{nick}-without-user", ["--nick", nick], nick)
print("cli_nick=ok", flush=True)
