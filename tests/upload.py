#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Upload guards use injected transports or owned loopback servers only."""

from __future__ import annotations

import contextlib
import http.client
import importlib.util
import io
import os
from pathlib import Path
import signal
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "src/media/upload.py"
spec = importlib.util.spec_from_file_location("birc_upload", HELPER)
upload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upload)


class FakeSocket:
    def __init__(self):
        self.timeouts = []

    def settimeout(self, timeout):
        self.timeouts.append(timeout)


class FakeResponse:
    def __init__(self, body=b"https://0x0.st/s/secret/abc.png\n", status=200, headers=None):
        self.status = status
        self.headers = headers or {}
        self.stream = io.BytesIO(body)
        self.read_sizes = []

    def getheader(self, name, default=None):
        return self.headers.get(name, default)

    def read(self, size):
        self.read_sizes.append(size)
        return self.stream.read(size)

    def close(self):
        self.stream.close()


class FakeConnection:
    def __init__(self, response=None, on_send=None):
        self.response = response or FakeResponse()
        self.on_send = on_send
        self.sock = FakeSocket()
        self.headers = {}
        self.parts = []
        self.closed = False
        self.host = self.context = self.timeout = None

    def factory(self, host, *, timeout, context):
        self.host, self.timeout, self.context = host, timeout, context
        return self

    def connect(self):
        pass

    def putrequest(self, method, path, **kwargs):
        self.method, self.path = method, path

    def putheader(self, name, value):
        self.headers[name] = value

    def endheaders(self):
        pass

    def send(self, data):
        self.parts.append(data)
        if self.on_send:
            self.on_send(len(self.parts))

    def getresponse(self):
        return self.response

    def close(self):
        self.closed = True


class UploadTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="birc-upload-test-")
        self.path = Path(self.temp.name) / "private name.png"
        self.path.write_bytes(b"\x00\xffsample\r\n")

    def tearDown(self):
        self.temp.cleanup()

    def fails(self, code, path=None, connection=None, **kwargs):
        client = connection or FakeConnection()
        with self.assertRaises(upload.UploadError) as caught:
            upload.upload(str(self.path if path is None else path), connection=client.factory, **kwargs)
        self.assertEqual(caught.exception.code, code)
        return client

    def test_streamed_multipart_keeps_binary_and_hides_local_basename(self):
        payload = b"\x00\xff01234567" * 20000
        self.path.write_bytes(payload)
        client = FakeConnection()
        result = upload.upload(str(self.path), connection=client.factory)
        self.assertEqual(result, "https://0x0.st/s/secret/abc.png")
        self.assertEqual((client.method, client.path, client.host), ("POST", "/", "0x0.st"))
        self.assertTrue(client.context.check_hostname)
        self.assertEqual(client.context.verify_mode, ssl.CERT_REQUIRED)
        self.assertIn("birc", client.headers["User-Agent"])
        body = b"".join(client.parts)
        self.assertEqual(int(client.headers["Content-Length"]), len(body))
        self.assertIn(b'name="secret"\r\n\r\n\r\n', body)
        self.assertIn(b'name="file"; filename="upload.png"', body)
        self.assertNotIn(b"private name", body)
        self.assertIn(payload, body)
        self.assertGreater(len(client.parts), 4)
        self.assertLessEqual(max(map(len, client.parts[1:-1])), upload.CHUNK_SIZE)
        self.assertTrue(body.endswith(b"--\r\n"))
        self.assertTrue(client.closed)
        self.assertTrue(all(0 < value <= upload.TIMEOUT for value in client.sock.timeouts))

    def test_unusual_filename_uses_safe_generic_extension(self):
        path = Path(self.temp.name) / 'private\n"name.unknown extension'
        path.write_bytes(b"file")
        client = FakeConnection()
        upload.upload(str(path), connection=client.factory)
        self.assertIn(b'filename="upload.bin"', client.parts[0])
        self.assertNotIn(b"private", client.parts[0])

    def test_invalid_sources_are_rejected_before_network(self):
        empty = Path(self.temp.name) / "empty"
        empty.touch()
        large = Path(self.temp.name) / "large"
        with large.open("wb") as stream:
            stream.truncate(upload.MAX_FILE + 1)
        fifo = Path(self.temp.name) / "fifo"
        os.mkfifo(fifo)
        link = Path(self.temp.name) / "link"
        link.symlink_to(self.path)
        for path in (Path(self.temp.name), empty, large, fifo, link,
                     Path(self.temp.name) / "missing", os.devnull, "bad\x00path"):
            with self.subTest(path=repr(path)):
                client = self.fails(2, path)
                self.assertIsNone(client.host)

    def test_source_change_aborts_without_multipart_footer(self):
        original = self.path.read_bytes()
        def change(index):
            if index == 1:
                self.path.write_bytes(b"z" * len(original))
        client = FakeConnection(on_send=change)
        self.fails(3, connection=client)
        self.assertTrue(client.closed)
        self.assertFalse(client.parts[-1].endswith(b"--\r\n"))

    def test_source_truncation_and_growth_are_rejected(self):
        for content in (b"", b"longer-than-original-file"):
            with self.subTest(content=content):
                self.path.write_bytes(b"original")
                client = FakeConnection(on_send=lambda index: self.path.write_bytes(content) if index == 1 else None)
                self.fails(3, connection=client)
                self.assertTrue(client.closed)

    def test_successful_response_framing(self):
        for body in (b"https://0x0.st/aaa.jpg", b"https://0x0.st/aaa.jpg\n",
                     b"https://0x0.st/aaa.jpg\r\n", b"https://0x0.st/aaa.jpg/image.jpeg\n"):
            with self.subTest(body=body):
                client = FakeConnection(FakeResponse(body))
                self.assertEqual(upload.upload(str(self.path), connection=client.factory), body.decode().rstrip("\r\n"))

    def test_exact_response_limit_is_accepted_but_larger_is_not(self):
        origin = b"https://0x0.st/"
        body = origin + b"x" * (upload.MAX_RESPONSE - len(origin))
        client = FakeConnection(FakeResponse(body))
        self.assertEqual(upload.upload(str(self.path), connection=client.factory), body.decode())
        self.fails(5, connection=FakeConnection(FakeResponse(body + b"x")))

    def test_untrusted_response_is_never_a_chat_message(self):
        bad = (b"", b"https://0x0.st/", b"http://0x0.st/abc", b"https://evil.test/abc",
               b"https://0x0.st.evil.test/abc", b"https://u@0x0.st/abc", b"https://0x0.st:443/abc",
               b"https://0x0.st/abc?q=x", b"https://0x0.st/abc#x", b"https://0x0.st/abc\nother",
               b"https://0x0.st/abc\n\n", b"https://0x0.st/abc\r", b" https://0x0.st/abc",
               b"https://0x0.st/ab\x02c", b"https://0x0.st/ab c", b"https://0x0.st/\xff",
               b"https://0x0.st//abc", b"https://0x0.st/../abc", b"https://0x0.st/./abc",
               b"https://0x0.st/" + b"x" * upload.MAX_RESPONSE)
        for body in bad:
            with self.subTest(body=body[:70]):
                client = FakeConnection(FakeResponse(body))
                self.fails(5, connection=client)
                self.assertTrue(client.closed)
                self.assertLessEqual(sum(client.response.read_sizes), upload.MAX_RESPONSE + 1)

    def test_http_errors_encoding_and_length_fail_closed(self):
        for response in (FakeResponse(status=302), FakeResponse(status=403),
                         FakeResponse(headers={"Content-Encoding": "gzip"}),
                         FakeResponse(headers={"Content-Length": "not-a-number"}),
                         FakeResponse(headers={"Content-Length": str(upload.MAX_RESPONSE + 1)}),
                         FakeResponse(headers={"Content-Length": "1"})):
            client = FakeConnection(response)
            self.fails(5, connection=client)
            self.assertTrue(client.closed)

    def test_deadline_checked_before_connect(self):
        client = self.fails(6, deadline=time.monotonic() - 1)
        self.assertIsNone(client.host)

    def test_transport_failure_closes_source_and_has_no_private_diagnostic(self):
        descriptors = []
        real_open = os.open
        def opened(*args):
            fd = real_open(*args)
            descriptors.append(fd)
            return fd
        def failed(*args, **kwargs):
            raise OSError("private file path and private server response")
        with patch.object(upload.os, "open", side_effect=opened):
            with self.assertRaises(upload.UploadError) as caught:
                upload.upload(str(self.path), connection=failed)
        self.assertEqual(caught.exception.code, 4)
        self.assertEqual(str(caught.exception), "4")
        with self.assertRaises(OSError):
            os.fstat(descriptors[0])

    def test_owned_loopback_http_round_trip_and_slow_headers(self):
        requests = []
        delay = [0, 0]
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass
            def do_POST(self):
                before, after = delay
                body = self.rfile.read(int(self.headers["Content-Length"]))
                requests.append((self.path, dict(self.headers), body))
                time.sleep(before)
                try:
                    self.send_response(200)
                    response = b"https://0x0.st/s/secret/test.png\n"
                    self.send_header("Content-Length", str(len(response)))
                    self.end_headers()
                    time.sleep(after)
                    self.wfile.write(response)
                except (BrokenPipeError, ConnectionResetError):
                    pass
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
        thread.start()
        def local(host, *, timeout, context):
            self.assertEqual(host, "0x0.st")
            self.assertTrue(context.check_hostname)
            return http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=timeout)
        try:
            self.assertEqual(upload.upload(str(self.path), connection=local), "https://0x0.st/s/secret/test.png")
            self.assertEqual(requests[0][0], "/")
            self.assertIn(self.path.read_bytes(), requests[0][2])
            for delays in ((0.4, 0), (0, 0.4)):
                with self.subTest(delays=delays):
                    delay[:] = delays
                    started = time.monotonic()
                    with self.assertRaises(upload.UploadError) as caught:
                        upload.upload(str(self.path), connection=local, deadline=started + 0.15)
                    self.assertEqual(caught.exception.code, 6)
                    self.assertLess(time.monotonic() - started, 0.5)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=1)

    def test_cli_error_is_numeric_and_does_not_echo_path(self):
        for args in ([], ["--local", "private-password-path-does-not-exist"], ["--url", "https://evil.test/"]):
            result = subprocess.run([sys.executable, str(HELPER), *args], capture_output=True, timeout=3)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
            self.assertRegex(result.stderr, rb"\Abirc-upload: failed \(code:[1-6]\)\n\Z")
            self.assertNotIn(b"private-password", result.stderr)

    def test_cli_success_prints_only_one_url(self):
        output = io.StringIO()
        with patch.object(upload, "upload", return_value="https://0x0.st/s/secret/file.png") as sender, \
                patch.object(upload.signal, "signal"), patch.object(upload.signal, "alarm") as alarm, \
                contextlib.redirect_stdout(output):
            upload.main(["--local", str(self.path)])
        sender.assert_called_once_with(str(self.path))
        alarm.assert_called_once_with(upload.TIMEOUT)
        self.assertEqual(output.getvalue(), "https://0x0.st/s/secret/file.png\n")

    def test_cli_keyboard_interrupt_has_no_private_diagnostic(self):
        code = (
            "import http.client,runpy,sys\n"
            "class Connection:\n"
            " def __init__(self,*args,**kwargs):pass\n"
            " def connect(self):raise KeyboardInterrupt('private transport detail')\n"
            " def close(self):pass\n"
            "http.client.HTTPSConnection=Connection\n"
            f"sys.argv=['upload','--local',{str(self.path)!r}]\n"
            f"runpy.run_path({str(HELPER)!r},run_name='__main__')\n"
        )
        result = subprocess.run([sys.executable, "-c", code], capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 4)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"birc-upload: failed (code:4)\n")

    def test_main_has_kernel_wall_bound_even_if_transport_hangs(self):
        code = (
            "import importlib.util,time;from unittest.mock import patch;"
            f"s=importlib.util.spec_from_file_location('u',{str(HELPER)!r});"
            "u=importlib.util.module_from_spec(s);s.loader.exec_module(u);"
            "u.TIMEOUT=1;u.upload=lambda _:time.sleep(30);u.main(['--local','file'])"
        )
        started = time.monotonic()
        result = subprocess.run([sys.executable, "-c", code], capture_output=True, timeout=3)
        self.assertEqual(result.returncode, -signal.SIGALRM)
        self.assertLess(time.monotonic() - started, 2.5)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"")


if __name__ == "__main__":
    unittest.main()
