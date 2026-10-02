#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""TLS profile policy and child argv; all credentials and programs are fake."""
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "src/launcher/keychain_birc.py"
spec = importlib.util.spec_from_file_location("keychain_birc_tls", SOURCE)
assert spec is not None and spec.loader is not None
launcher = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = launcher
spec.loader.exec_module(launcher)


def config(path, extra="", host="irc.invalid"):
    path.write_text('[profiles.test]\nhost=' + json.dumps(host)
                    + '\naccount="alice"\n' + extra)
    path.chmod(0o600)


def main():
    with tempfile.TemporaryDirectory(prefix="birc-keychain-tls-") as directory:
        root = Path(directory)
        cfg = root / "config.toml"
        child = root / "fake-birc"
        child.write_text("#!" + sys.executable + "\n" + '''
import json, os, sys
from pathlib import Path
fd = int(os.environ["BIRC_AUTH_SECRET_FD"])
value = b""
while True:
    part = os.read(fd, 2048)
    if not part: break
    value += part
os.close(fd)
assert value == b"synthetic-tls-secret"
Path(__file__).with_name("argv.json").write_text(json.dumps(sys.argv[1:]))
os.close(int(os.environ["BIRC_AUTH_EVENT_FD"]))
''')
        child.chmod(0o700)
        recorded = root / "argv.json"

        def run(*args, expected=0):
            recorded.unlink(missing_ok=True)
            output = io.StringIO()
            with patch.object(launcher, "load_secret", return_value=b"synthetic-tls-secret") as lookup, \
                    patch.object(launcher, "save_secret", side_effect=AssertionError("must not save without success")), \
                    redirect_stdout(output), redirect_stderr(output):
                try:
                    result = launcher.main(["--profile", "test", "--config", str(cfg), *args],
                                           security="unused fake", birc=str(child),
                                           prompt=lambda _: (_ for _ in ()).throw(AssertionError("must not prompt")),
                                           platform="darwin")
                except SystemExit as error:
                    result = error.code
            assert result == expected, output.getvalue()
            assert "synthetic-tls-secret" not in output.getvalue()
            if expected:
                assert not lookup.called and not recorded.exists(), "refusal happened after credential access"
                return output.getvalue(), None
            assert lookup.call_count == 1
            argv = json.loads(recorded.read_text())
            queried = lookup.call_args.args[1]
            assert queried.host == argv[argv.index("--connect") + 1]
            assert queried.port == int(argv[argv.index("--port") + 1])
            assert json.loads(queried.service.split(":", 1)[1]) == ["test", queried.host, queried.port]
            assert ("--tls" in argv, "--plain" in argv) == (queried.tls, not queried.tls)
            return output.getvalue(), argv

        # (+) No mode metadata means TLS, before endpoint-bound credential access.
        config(cfg)
        default = launcher.read_profile(cfg, "test")
        assert default.tls and default.port == 6697
        _, args = run()
        assert "--tls" in args and args[args.index("--port") + 1] == "6697"

        # (-/+) Match the core frame cap before any credential access/prompt.
        for cap in ("-1", "65536", "4294967295"):
            run("--frames", cap, expected=1)
        _, args = run("--frames", "65535")
        assert args[args.index("--frames") + 1] == "65535"
        _, args = run("--frames", "0")
        assert args[args.index("--frames") + 1] == "0"

        # (-/+) CLI modes override profiles, not just enable TLS. Plaintext still
        # requires an explicit relay declaration or per-launch unsafe consent.
        run("--plain", expected=1)
        text, args = run("--plain", "--allow-insecure-auth")
        assert "WARNING" in text and "--plain" in args
        assert args[args.index("--port") + 1] == "6667"
        downgraded = launcher.read_profile(cfg, "test", tls=False)
        assert not downgraded.tls and downgraded.service != default.service
        for flags in (("--tls", "--plain"), ("--plain", "--tls")):
            run(*flags, expected=2)
        for extra in ("tls=true\nport=7000\n", "port=7000\ntls=true\n"):
            config(cfg, extra)
            run("--plain", expected=1)
            _, args = run("--plain", "--allow-insecure-auth")
            assert "--plain" in args and args[args.index("--port") + 1] == "7000"
        for extra in ("tls=false\nport=7000\n", "port=7000\ntls=false\n"):
            config(cfg, extra)
            _, args = run("--tls")
            assert "--tls" in args and args[args.index("--port") + 1] == "7000"

        # (+) Inline endpoint ports normalize before lookup and retain mode.
        config(cfg, host="irc.invalid:07000")
        inline = launcher.read_profile(cfg, "test")
        assert inline.host == "irc.invalid" and inline.port == 7000 and inline.tls
        _, args = run()
        assert args[args.index("--connect") + 1] == "irc.invalid"
        assert args[args.index("--port") + 1] == "7000"
        config(cfg, "port=7000\n", host="irc.invalid")
        assert launcher.read_profile(cfg, "test").service == inline.service
        config(cfg, "port=7000\n", host="irc.invalid:7000")
        assert launcher.read_profile(cfg, "test").service == inline.service
        run()
        config(cfg, "port=7001\n", host="irc.invalid:7000")
        run(expected=1)
        config(cfg, "tls=false\ntrusted_relay=true\n", host="127.0.0.1:6697")
        _, args = run()
        assert "--plain" in args and args[args.index("--port") + 1] == "6697"

        # (-) No malformed/conflicting endpoint reaches Keychain or child launch.
        for host in ("irc.invalid:", "irc.invalid:0", "irc.invalid:65536", "irc.invalid:-1",
                     "irc.invalid:7:8", ":6697", "[::1]:6697", "irc.invalid:６６９７",
                     ".irc.invalid", "irc..invalid", "irc.invalid..", "a" * 64 + ".invalid"):
            config(cfg, host=host)
            run(expected=1)
        for port in ("true", "0", "65536", '"7000"'):
            config(cfg, "port=" + port + "\n", host="irc.invalid:7000")
            run(expected=1)
        maximum = ".".join(("a" * 63, "b" * 63, "c" * 63, "d" * 61))
        assert len(maximum) == 253
        config(cfg, host=maximum + ".:65535")
        profile = launcher.read_profile(cfg, "test")
        assert profile.host == maximum + "." and profile.port == 65535
        run()
        for host in (maximum + "x", maximum + "x."):
            config(cfg, host=host)
            run(expected=1)

        # (+) TLS profiles resolve their default endpoint before credential lookup.
        config(cfg, "tls=true\n")
        profile = launcher.read_profile(cfg, "test")
        assert profile.tls and profile.port == 6697
        assert json.loads(profile.service.split(":", 1)[1]) == ["test", "irc.invalid", 6697]
        text, args = run()
        assert "--tls" in args and args[args.index("--port") + 1] == "6697"
        assert "WARNING" not in text
        text, args = run("--allow-insecure-auth")
        assert "--tls" in args and "WARNING" not in text, "unsafe opt-in downgraded a TLS profile"

        # (+) An explicit port changes only the port, not the selected mode.
        config(cfg, "tls=true\nport=7000\n")
        _, args = run()
        assert "--tls" in args and args[args.index("--port") + 1] == "7000"
        config(cfg, "tls=true\nport=6697\n")
        assert launcher.read_profile(cfg, "test").tls
        _, args = run()
        assert "--tls" in args and args[args.index("--port") + 1] == "6697"
        config(cfg, "tls=false\nport=6697\n")
        assert not launcher.read_profile(cfg, "test").tls
        run(expected=1)
        _, args = run("--allow-insecure-auth")
        assert "--plain" in args and args[args.index("--port") + 1] == "6697"
        config(cfg, "port=6667\n")
        _, args = run()
        assert "--tls" in args and args[args.index("--port") + 1] == "6667"

        # (-/+) Legacy plaintext defaults and its explicit per-launch opt-in stay intact.
        config(cfg, "tls=false\n")
        plain = launcher.read_profile(cfg, "test")
        assert not plain.tls and plain.port == 6667
        run(expected=1)
        text, args = run("--allow-insecure-auth")
        assert "WARNING" in text and "--tls" not in args
        assert args[args.index("--port") + 1] == "6667"

        # (+) CLI TLS resolves its endpoint/service key before secrets; explicit ports stay put.
        text, args = run("--tls")
        assert "WARNING" not in text and "--tls" in args
        assert args[args.index("--port") + 1] == "6697"
        upgraded = launcher.read_profile(cfg, "test", tls=True)
        assert upgraded.service != plain.service and upgraded.port == 6697
        config(cfg, "port=7000\n")
        _, args = run("--tls")
        assert "--tls" in args and args[args.index("--port") + 1] == "7000"

        # (+) Explicitly trusted IPv4 loopback relay remains valid without native TLS.
        config(cfg, "tls=false\ntrusted_relay=true\n", host="127.0.0.1")
        text, args = run()
        assert "WARNING" not in text and "--tls" not in args

        # (-) Metadata must be an actual Bool; no credential access on bad TLS configuration.
        for value in ('"true"', "1", "1.0"):
            config(cfg, "tls=" + value + "\n")
            run(expected=1)
            run("--tls", expected=1)
        print("keychain_tls=ok")


if __name__ == "__main__":
    main()
