#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Only numeric HTTP metadata may leave an owned mock upload failure."""
from __future__ import annotations

import http.client
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "src/media/upload.py"
spec = importlib.util.spec_from_file_location("upload_diagnostics_helper", HELPER)
upload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upload)
PRIVATE = b"private local path /owned/private.html https://private.test/token \x1b[31m"


class Diagnostics(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="birc-upload-status-")
        self.path = Path(self.temp.name) / "private.html"
        self.path.write_bytes(b"<html>synthetic owned fixture</html>")
        self.status = 200
        self.body = b"https://0x0.st/s/test/file.html\n"
        self.requests = []
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(2)

            def log_message(self, *_):
                pass

            def do_POST(self):
                owner.requests.append(self.rfile.read(int(self.headers["Content-Length"])))
                self.send_response(owner.status, "private reason phrase")
                self.send_header("Content-Length", str(len(owner.body)))
                self.send_header("X-Private", "private response metadata")
                self.end_headers()
                try:
                    self.wfile.write(owner.body)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       kwargs={"poll_interval": 0.02}, daemon=True)
        self.thread.start()

    def tearDown(self):
        try:
            self.server.shutdown()
            self.server.server_close()
            self.thread.join(timeout=2)
            self.assertFalse(self.thread.is_alive(), "owned server reaped")
        finally:
            self.temp.cleanup()

    def connection(self, host, *, timeout, context):
        self.assertEqual(host, "0x0.st")
        self.assertTrue(context.check_hostname)
        return http.client.HTTPConnection("127.0.0.1", self.server.server_port,
                                          timeout=timeout)

    def test_html_success_keeps_url_validation_and_has_no_local_ban(self):
        self.assertEqual(upload.upload(str(self.path), connection=self.connection),
                         "https://0x0.st/s/test/file.html")
        self.assertIn(b'filename="upload.html"', self.requests[0])
        self.assertNotIn(b"private.html", self.requests[0])

    def test_http_rejections_expose_only_numeric_status_keep_exit_five(self):
        self.body = PRIVATE
        for status in (302, 403, 415, 418, 500):
            with self.subTest(status=status):
                self.status = status
                with self.assertRaises(upload.UploadError) as caught:
                    upload.upload(str(self.path), connection=self.connection)
                self.assertEqual(caught.exception.code, 5)
                self.assertEqual(caught.exception.http_status, status)
                self.assertEqual(upload.diagnostic(caught.exception),
                                 f"birc-upload: failed (code:5, http:{status})")

    def test_invalid_success_body_and_unknown_status_have_no_http_detail(self):
        self.body = PRIVATE
        for status in (200, 999):
            with self.subTest(status=status):
                self.status = status
                with self.assertRaises(upload.UploadError) as caught:
                    upload.upload(str(self.path), connection=self.connection)
                self.assertEqual(caught.exception.code, 5)
                self.assertEqual(caught.exception.http_status, 0)
                self.assertEqual(upload.diagnostic(caught.exception),
                                 "birc-upload: failed (code:5)")

    def test_status_cannot_be_attached_to_another_error_or_untrusted_type(self):
        for code, status in ((4, 403), (5, True), (5, "403"), (5, 99), (5, 600), (5, 200)):
            with self.subTest(code=code, status=status):
                error = upload.UploadError(code, http_status=status)
                self.assertEqual(error.http_status, 0)
                self.assertEqual(upload.diagnostic(error), f"birc-upload: failed (code:{code})")

    def test_cli_returns_five_with_only_exact_status_envelope(self):
        self.status = 418
        self.body = PRIVATE
        code = (
            "import http.client,runpy,sys\n"
            "real=http.client.HTTPConnection\n"
            f"http.client.HTTPSConnection=lambda host,timeout,context:real('127.0.0.1',{self.server.server_port},timeout=timeout)\n"
            f"sys.argv=['upload','--local',{str(self.path)!r}]\n"
            f"runpy.run_path({str(HELPER)!r},run_name='__main__')\n"
        )
        result = subprocess.run([sys.executable, "-c", code], capture_output=True, timeout=4)
        self.assertEqual(result.returncode, 5)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"birc-upload: failed (code:5, http:418)\n")


if __name__ == "__main__":
    unittest.main()
