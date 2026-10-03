#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Owned-loopback IPv6 transport qualification.

Modes of the fixture binary: literal (no sockets), dial6(+eof/bad) /
dial6refused (TCP over ::1, 5 bytes under one deadline, 2+3 fragments),
dns6 (production AAAA via explicit port), v6dst (v6 datagram without a
v6 socket fails closed), tls6 / tls6wrong (verified TLS over ::1 with a
synthetic IP-SAN certificate).
"""
import os
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

RDATA_V6 = bytes([32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])


def run(binary, args, env=None, timeout=20):
    merged = dict(os.environ)
    if env:
        merged.update(env)
    result = subprocess.run([binary, *args], capture_output=True, text=True,
                            timeout=timeout, env=merged)
    assert result.returncode == 0, (args, result.returncode, result.stdout, result.stderr)
    return result.stdout.strip()


def check(token, got):
    assert got == token, (token, got)
    print(token, flush=True)


def free_port_v6():
    probe = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    with probe:
        probe.bind(("::1", 0))
        return probe.getsockname()[1]


def mode_literal(binary):
    check("literal=ok", run(binary, ["literal"]))


def mode_bind6probe(binary):
    got = run(binary, ["bind6probe"])
    assert got in ("bind6=supported", "bind6=unsupported"), got
    print(got, flush=True)
    return got == "bind6=supported"


def collect_five(conn, deadline, tag):
    data = bytearray()
    while len(data) < 5:
        assert time.monotonic() < deadline, f"{tag} exceeded one deadline"
        try:
            chunk = conn.recv(5 - len(data))
        except socket.timeout:
            raise AssertionError(f"{tag} recv timed out under deadline")
        assert chunk, f"{tag} closed before 5 bytes"
        data.extend(chunk)
    return bytes(data)


def mode_dial6(binary):
    received = []
    listener = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    listener.bind(("::1", 0))
    listener.listen(1)
    listener.settimeout(10)
    port = listener.getsockname()[1]

    def server():
        with listener:
            conn, peer = listener.accept()
            with conn:
                assert peer[0] == "::1", peer
                conn.settimeout(2)
                deadline = time.monotonic() + 8
                data = collect_five(conn, deadline, "dial6")
                received.append(data)
                assert data == b"hello", data
                conn.sendall(data[:2])
                time.sleep(0.05)
                conn.sendall(data[2:])

    worker = threading.Thread(target=server, daemon=True)
    worker.start()
    try:
        check("dial6=ok", run(binary, ["dial6", str(port)]))
    finally:
        worker.join(timeout=10)
        assert not worker.is_alive(), "dial6 server stuck"
    assert received == [b"hello"], received


def mode_dial6eof(binary):
    received = []
    listener = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    listener.bind(("::1", 0))
    listener.listen(1)
    listener.settimeout(10)
    port = listener.getsockname()[1]

    def server():
        with listener:
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(2)
                deadline = time.monotonic() + 8
                data = collect_five(conn, deadline, "dial6eof")
                received.append(data)
                conn.sendall(b"he")

    worker = threading.Thread(target=server, daemon=True)
    worker.start()
    try:
        check("dial6eof=ok", run(binary, ["dial6eof", str(port)]))
    finally:
        worker.join(timeout=10)
        assert not worker.is_alive(), "dial6eof server stuck"
    assert received == [b"hello"], received


def mode_dial6bad(binary):
    received = []
    listener = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    listener.bind(("::1", 0))
    listener.listen(1)
    listener.settimeout(10)
    port = listener.getsockname()[1]

    def server():
        with listener:
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(2)
                deadline = time.monotonic() + 8
                data = collect_five(conn, deadline, "dial6bad")
                received.append(data)
                conn.sendall(b"hellX")

    worker = threading.Thread(target=server, daemon=True)
    worker.start()
    try:
        check("dial6bad=ok", run(binary, ["dial6bad", str(port)]))
    finally:
        worker.join(timeout=10)
        assert not worker.is_alive(), "dial6bad server stuck"
    assert received == [b"hello"], received


def mode_dial6refused(binary):
    check("dial6refused=ok", run(binary, ["dial6refused", str(free_port_v6())]))


def mode_dns6(binary):
    seen = []
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    sock.settimeout(10)
    port = sock.getsockname()[1]

    def server():
        with sock:
            query, peer = sock.recvfrom(512)
            seen.append(query)
            assert len(query) >= 29, len(query)
            txid = query[0:2]
            assert query[2:4] == b"\x01\x00", query[2:4].hex()
            assert query[4:6] == b"\x00\x01", "qdcount"
            qname = b"\x01a\x00"
            assert qname in query, query.hex()
            tail = query[query.index(qname) + len(qname):]
            assert tail[0:2] == b"\x00\x1c", ("qtype", tail.hex())
            assert tail[2:4] == b"\x00\x01", ("qclass", tail.hex())
            header = txid + bytes([129, 128, 0, 1, 0, 1, 0, 0, 0, 0])
            question = qname + bytes([0, 28, 0, 1])
            answer = (bytes([192, 12, 0, 28, 0, 1, 0, 0, 0, 1, 0, 16]) + RDATA_V6)
            sock.sendto(header + question + answer, peer)

    worker = threading.Thread(target=server, daemon=True)
    worker.start()
    try:
        check("dns6=ok", run(binary, ["dns6", str(port)]))
    finally:
        worker.join(timeout=10)
        assert not worker.is_alive(), "dns6 server stuck"
    assert len(seen) == 1, seen


def mode_dns6fb(binary):
    seen = []
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    sock.settimeout(10)
    port = sock.getsockname()[1]

    def server():
        with sock:
            for _ in range(2):
                query, peer = sock.recvfrom(512)
                seen.append(query)
                assert len(query) >= 29, len(query)
                txid = query[0:2]
                qname = b"\x01a\x00"
                assert qname in query, query.hex()
                tail = query[query.index(qname) + len(qname):]
                qtype = tail[0:2]
                if qtype == b"\x00\x1c":
                    header = txid + bytes([129, 128, 0, 1, 0, 0, 0, 0, 0, 0])
                    question = qname + bytes([0, 28, 0, 1])
                    sock.sendto(header + question, peer)
                elif qtype == b"\x00\x01":
                    header = txid + bytes([129, 128, 0, 1, 0, 1, 0, 0, 0, 0])
                    question = qname + bytes([0, 1, 0, 1])
                    answer = bytes([192, 12, 0, 1, 0, 1, 0, 0, 0, 1, 0, 4, 127, 0, 0, 1])
                    sock.sendto(header + question + answer, peer)
                else:
                    raise AssertionError(f"unexpected qtype {qtype.hex()}")

    worker = threading.Thread(target=server, daemon=True)
    worker.start()
    try:
        check("dns6fb=ok", run(binary, ["dns6fb", str(port)]))
    finally:
        worker.join(timeout=10)
        assert not worker.is_alive(), "dns6fb server stuck"
    assert len(seen) == 2, seen


def mode_dns6tcp(binary):
    seen_udp = []
    seen_tcp = []
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind(("127.0.0.1", 0))
    udp.settimeout(10)
    port = udp.getsockname()[1]
    tcp_listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp_listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp_listener.bind(("127.0.0.1", port))
    tcp_listener.listen(1)
    tcp_listener.settimeout(10)

    def udp_server():
        with udp:
            query, peer = udp.recvfrom(512)
            seen_udp.append(query)
            txid = query[0:2]
            qname = b"\x01a\x00"
            header = txid + bytes([131, 128, 0, 1, 0, 0, 0, 0, 0, 0])
            question = qname + bytes([0, 28, 0, 1])
            udp.sendto(header + question, peer)

    def tcp_server():
        with tcp_listener:
            conn, _ = tcp_listener.accept()
            with conn:
                conn.settimeout(10)
                data = bytearray()
                while len(data) < 2:
                    chunk = conn.recv(2 - len(data))
                    assert chunk, "dns6tcp client closed prefix"
                    data.extend(chunk)
                (size,) = struct.unpack("!H", bytes(data))
                query = bytearray()
                while len(query) < size:
                    chunk = conn.recv(size - len(query))
                    assert chunk, "dns6tcp client closed query"
                    query.extend(chunk)
                seen_tcp.append(bytes(query))
                assert bytes(query)[0:2] and True
                txid = bytes(query)[0:2]
                qname = b"\x01a\x00"
                header = txid + bytes([129, 128, 0, 1, 0, 1, 0, 0, 0, 0])
                question = qname + bytes([0, 28, 0, 1])
                answer = bytes([192, 12, 0, 28, 0, 1, 0, 0, 0, 1, 0, 16]) + RDATA_V6
                packet = header + question + answer
                conn.sendall(struct.pack("!H", len(packet)) + packet)

    udp_worker = threading.Thread(target=udp_server, daemon=True)
    tcp_worker = threading.Thread(target=tcp_server, daemon=True)
    udp_worker.start()
    tcp_worker.start()
    try:
        check("dns6tcp=ok", run(binary, ["dns6tcp", str(port)]))
    finally:
        udp_worker.join(timeout=10)
        tcp_worker.join(timeout=10)
        assert not udp_worker.is_alive(), "dns6tcp udp stuck"
        assert not tcp_worker.is_alive(), "dns6tcp tcp stuck"
    assert len(seen_udp) == 1, seen_udp
    assert len(seen_tcp) == 1, seen_tcp


def mode_v6dst(binary):
    check("v6dst=ok", run(binary, ["v6dst", "53"]))


def mode_v6udp(binary):
    seen = []
    sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    sock.bind(("::1", 0))
    sock.settimeout(10)
    port = sock.getsockname()[1]

    def server():
        with sock:
            data, peer = sock.recvfrom(512)
            seen.append((data, peer))
            assert data == b"hello", data
            assert peer[0] == "::1", peer
            sock.sendto(data, peer)

    worker = threading.Thread(target=server, daemon=True)
    worker.start()
    try:
        check("v6udp=ok", run(binary, ["v6udp", str(port)]))
    finally:
        worker.join(timeout=10)
        assert not worker.is_alive(), "v6udp server stuck"
    assert len(seen) == 1, seen
    assert seen[0][0] == b"hello", seen


def echo_five(conn, tag):
    conn.settimeout(2)
    deadline = time.monotonic() + 8
    data = collect_five(conn, deadline, tag)
    assert data == b"hello", (tag, data)
    conn.sendall(data[:2])
    time.sleep(0.05)
    conn.sendall(data[2:])
    return data


def mode_dualfb(binary):
    received = []
    v4 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    v4.bind(("127.0.0.1", 0))
    v4.listen(1)
    v4.settimeout(10)
    port = v4.getsockname()[1]

    def server4():
        with v4:
            conn, _ = v4.accept()
            with conn:
                received.append(echo_five(conn, "dualfb"))

    worker4 = threading.Thread(target=server4, daemon=True)
    worker4.start()
    try:
        check("dualfb=ok", run(binary, ["dualfb", str(port)]))
    finally:
        worker4.join(timeout=10)
        assert not worker4.is_alive(), "dualfb v4 stuck"
    assert received == [b"hello"], received


def mode_dual6win(binary):
    received6 = []
    received4 = []
    v4 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    v4.bind(("127.0.0.1", 0))
    v4.listen(1)
    v4.settimeout(10)
    port = v4.getsockname()[1]
    v6 = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    v6.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        v6.bind(("::1", port))
    except OSError:
        v4.close()
        v6.close()
        print("dual6win=skipped", flush=True)
        return
    v6.listen(1)
    v6.settimeout(10)

    def server6():
        with v6:
            conn, _ = v6.accept()
            with conn:
                received6.append(echo_five(conn, "dual6win"))

    def server4():
        with v4:
            try:
                conn, _ = v4.accept()
            except socket.timeout:
                return
            with conn:
                received4.append(echo_five(conn, "dual6win-v4"))

    worker6 = threading.Thread(target=server6, daemon=True)
    worker4 = threading.Thread(target=server4, daemon=True)
    worker6.start()
    worker4.start()
    try:
        check("dual6win=ok", run(binary, ["dual6win", str(port)]))
    finally:
        worker6.join(timeout=10)
        worker4.join(timeout=10)
        assert not worker6.is_alive(), "dual6win v6 stuck"
        assert not worker4.is_alive(), "dual6win v4 stuck"
    assert received6 == [b"hello"], received6
    assert received4 == [], ("v6 must win without v4 fallback", received4)


RDATA_LOOP6 = bytes([0] * 15 + [1])


def mode_dualdns(binary):
    seen = []
    received = []
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind(("127.0.0.1", 0))
    udp.settimeout(10)
    port = udp.getsockname()[1]
    tcp4 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp4.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp4.bind(("127.0.0.1", port))
    tcp4.listen(1)
    tcp4.settimeout(10)

    def dns_server():
        with udp:
            for _ in range(2):
                query, peer = udp.recvfrom(512)
                seen.append(query)
                txid = query[0:2]
                qname = b"\x01a\x00"
                assert qname in query, query.hex()
                tail = query[query.index(qname) + len(qname):]
                qtype = tail[0:2]
                if qtype == b"\x00\x1c":
                    header = txid + bytes([129, 128, 0, 1, 0, 1, 0, 0, 0, 0])
                    question = qname + bytes([0, 28, 0, 1])
                    answer = bytes([192, 12, 0, 28, 0, 1, 0, 0, 0, 1, 0, 16]) + RDATA_LOOP6
                    udp.sendto(header + question + answer, peer)
                elif qtype == b"\x00\x01":
                    header = txid + bytes([129, 128, 0, 1, 0, 1, 0, 0, 0, 0])
                    question = qname + bytes([0, 1, 0, 1])
                    answer = bytes([192, 12, 0, 1, 0, 1, 0, 0, 0, 1, 0, 4, 127, 0, 0, 1])
                    udp.sendto(header + question + answer, peer)
                else:
                    raise AssertionError(f"unexpected qtype {qtype.hex()}")

    def tcp_server():
        with tcp4:
            conn, _ = tcp4.accept()
            with conn:
                received.append(echo_five(conn, "dualdns"))

    udp_worker = threading.Thread(target=dns_server, daemon=True)
    tcp_worker = threading.Thread(target=tcp_server, daemon=True)
    udp_worker.start()
    tcp_worker.start()
    try:
        check("dualdns=ok", run(binary, ["dualdns", str(port)]))
    finally:
        udp_worker.join(timeout=10)
        tcp_worker.join(timeout=10)
        assert not udp_worker.is_alive(), "dualdns dns stuck"
        assert not tcp_worker.is_alive(), "dualdns tcp stuck"
    assert len(seen) == 2, seen
    qname = b"\x01a\x00"
    types = [q[q.index(qname) + len(qname):q.index(qname) + len(qname) + 2] for q in seen]
    assert types == [b"\x00\x1c", b"\x00\x01"], ("AAAA first then A", types)
    assert received == [b"hello"], received


class Certificates:
    def __init__(self, folder, openssl):
        self.folder = folder
        folder.mkdir()
        (folder / "req.cnf").write_text("[req]\ndistinguished_name=subject\n[subject]\n")

        def command(*args, good=True):
            result = subprocess.run([openssl, *args], cwd=folder,
                                    capture_output=True, timeout=15)
            assert (result.returncode == 0) == good, (args, result.stderr[-200:])

        command("req", "-config", "req.cnf", "-x509", "-newkey", "rsa:2048",
                "-noenc", "-sha256", "-days", "2",
                "-addext", "basicConstraints=critical,CA:TRUE",
                "-addext", "keyUsage=critical,keyCertSign,cRLSign",
                "-subj", "/CN=birc-synthetic-v6ca",
                "-keyout", "ca.key", "-out", "ca.pem")
        command("req", "-config", "req.cnf", "-new", "-newkey", "rsa:2048",
                "-noenc", "-sha256", "-subj", "/CN=birc-synthetic-v6leaf",
                "-keyout", "server.key", "-out", "server.csr")
        (folder / "valid.ext").write_text(
            "basicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\nsubjectAltName=IP:::1\n")
        command("x509", "-req", "-in", "server.csr", "-CA", "ca.pem",
                "-CAkey", "ca.key", "-set_serial", "1", "-days", "1",
                "-sha256", "-extfile", "valid.ext", "-out", "valid.pem")
        command("req", "-config", "req.cnf", "-new", "-newkey", "rsa:2048",
                "-noenc", "-sha256", "-subj", "/CN=birc-synthetic-v6dnslf",
                "-keyout", "server_dns.key", "-out", "server_dns.csr")
        (folder / "valid_dns.ext").write_text(
            "basicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\nsubjectAltName=DNS:birc.test\n")
        command("x509", "-req", "-in", "server_dns.csr", "-CA", "ca.pem",
                "-CAkey", "ca.key", "-set_serial", "2", "-days", "1",
                "-sha256", "-extfile", "valid_dns.ext", "-out", "valid_dns.pem")
        for path in folder.glob("*.key"):
            path.chmod(0o600)
        (folder / "empty-trust-dir").mkdir()
        command("verify", "-CAfile", "ca.pem", "-verify_ip", "::1", "valid.pem")
        command("verify", "-CAfile", "ca.pem", "-verify_ip", "127.0.0.1",
                "valid.pem", good=False)
        command("verify", "-CAfile", "ca.pem", "-verify_hostname", "birc.test",
                "valid_dns.pem")
        command("verify", "-CAfile", "ca.pem", "-verify_hostname", "wrong.test",
                "valid_dns.pem", good=False)

    def context(self):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(self.folder / "valid.pem", self.folder / "server.key")
        return context

    def context_dns(self):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(self.folder / "valid_dns.pem", self.folder / "server_dns.key")
        return context


def serve_tls_once(context, record):
    listener = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    listener.bind(("::1", 0))
    listener.listen(1)
    listener.settimeout(10)
    port = listener.getsockname()[1]

    def server():
        with listener:
            raw, _ = listener.accept()
            with raw:
                raw.settimeout(2)
                try:
                    with context.wrap_socket(raw, server_side=True) as tls:
                        tls.settimeout(2)
                        deadline = time.monotonic() + 8
                        data = collect_five(tls, deadline, "tls")
                        record["data"] = data
                        tls.sendall(data)
                except (ssl.SSLError, OSError, AssertionError) as exc:
                    record["failed"] = repr(exc)

    worker = threading.Thread(target=server, daemon=True)
    worker.start()
    return port, worker


def mode_tls(binary, certs, name, expect_data):
    sni = []
    context = certs.context()
    context.sni_callback = lambda sock, server_name, ctx: sni.append(server_name)
    record = {}
    port, worker = serve_tls_once(context, record)
    env = {"SSL_CERT_FILE": str(certs.folder / "ca.pem"),
           "SSL_CERT_DIR": str(certs.folder / "empty-trust-dir")}
    try:
        check(name + "=ok", run(binary, [name, str(port)], env=env))
    finally:
        worker.join(timeout=10)
        assert not worker.is_alive(), name + " server stuck"
    assert all(name is None for name in sni), ("SNI must be absent for IP literals", sni)
    if expect_data:
        assert record.get("data") == b"hello", record
    else:
        assert record.get("failed"), ("wrong-host handshake must fail", record)


def mode_tls_name(binary, certs, name, expect_host, expect_data):
    sni = []
    context = certs.context_dns()
    context.sni_callback = lambda sock, server_name, ctx: sni.append(server_name)
    record = {}
    port, worker = serve_tls_once(context, record)
    env = {"SSL_CERT_FILE": str(certs.folder / "ca.pem"),
           "SSL_CERT_DIR": str(certs.folder / "empty-trust-dir")}
    try:
        check(name + "=ok", run(binary, [name, str(port)], env=env))
    finally:
        worker.join(timeout=10)
        assert not worker.is_alive(), name + " server stuck"
    assert sni == [expect_host], ("SNI must carry the DNS hostname", sni)
    if expect_data:
        assert record.get("data") == b"hello", record
    else:
        assert record.get("failed"), ("wrong DNS host must fail", record)


def main():
    binary = sys.argv[1]
    openssl = sys.argv[2] if len(sys.argv) > 2 else "openssl"
    mode_literal(binary)
    v6 = mode_bind6probe(binary)
    mode_dial6(binary)
    mode_dial6eof(binary)
    mode_dial6bad(binary)
    mode_dial6refused(binary)
    mode_dns6(binary)
    mode_dns6fb(binary)
    mode_dns6tcp(binary)
    mode_v6dst(binary)
    if v6:
        mode_v6udp(binary)
    else:
        print("v6udp=skipped", flush=True)
    mode_dualfb(binary)
    mode_dual6win(binary)
    mode_dualdns(binary)
    with tempfile.TemporaryDirectory(prefix="birc-ipv6-transport-") as directory:
        certs = Certificates(Path(directory) / "certs", openssl)
        mode_tls(binary, certs, "tls6", True)
        mode_tls(binary, certs, "tls6wrong", False)
        mode_tls_name(binary, certs, "tls6name", "birc.test", True)
        mode_tls_name(binary, certs, "tls6namewrong", "wrong.test", False)
    print("ipv6_transport_native=ok", flush=True)


if __name__ == "__main__":
    main()
