#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Keychain default ports must match Bend transport_policy, without a Bend binary.

Python cannot call Bend. This reads the literals and default_port expression
from src/bend/transport_policy.bend and the conflict rule from
src/bend/endpoint.bend, then checks keychain_birc.profile_endpoint.
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "src/bend/transport_policy.bend"
ENDPOINT = ROOT / "src/bend/endpoint.bend"
KEYCHAIN = ROOT / "tests/lib/keychain_birc.py"


def load_keychain():
    spec = importlib.util.spec_from_file_location("keychain_transport_parity", KEYCHAIN)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bend_ports(text: str) -> tuple[int, int]:
    tls = re.search(r"def TLS_PORT\(\) -> U32:\n\s+(\d+)\n", text)
    plain = re.search(r"def PLAIN_PORT\(\) -> U32:\n\s+(\d+)\n", text)
    assert tls is not None and plain is not None, "transport_policy port literals moved"
    body = re.search(
        r"def default_port\(secure: Bool, port_explicit: Bool, port: U32\) -> U32:\n"
        r"\s+Bool\.pick\(U32, port_explicit, port, Bool\.pick\(U32, secure, TLS_PORT\(\), PLAIN_PORT\(\)\)\)\n",
        text)
    assert body is not None, "default_port no longer picks an explicit port, else TLS_PORT/PLAIN_PORT"
    return int(tls.group(1)), int(plain.group(1))


def main() -> None:
    tls_port, plain_port = bend_ports(POLICY.read_text())
    endpoint = ENDPOINT.read_text()
    assert "def select_port(" in endpoint, "endpoint select_port missing"
    assert "select_port.same(U32.is_eq(n, m), n)" in endpoint, "conflicting ports no longer fail closed"
    keychain = load_keychain()
    assert keychain._CACHE is not None, "source tree did not load the shared helper"
    host = "irc.example"
    # Omitted port follows transport_policy.default_port(secure, port_explicit=false, _).
    assert keychain.profile_endpoint(host, None, True) == (host, tls_port)
    assert keychain.profile_endpoint(host, None, False) == (host, plain_port)
    # An explicit port wins and does not follow the transport default.
    assert keychain.profile_endpoint(host, plain_port, True) == (host, plain_port)
    assert keychain.profile_endpoint(host, tls_port, False) == (host, tls_port)
    assert keychain.profile_endpoint(host + ":" + str(tls_port), None, False) == (host, tls_port)
    try:
        keychain.profile_endpoint(host + ":7", 8, True)
    except keychain.Refusal as error:
        assert "conflicting" in str(error)
    else:
        raise AssertionError("inline and separate ports were both accepted")
    print("keychain_transport_parity=ok tls=%s plain=%s" % (tls_port, plain_port))


if __name__ == "__main__":
    main()
