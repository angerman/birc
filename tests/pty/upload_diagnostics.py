#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Actual UI numeric upload errors, using fake helpers and loopback IRC only."""
from __future__ import annotations

import os
from pathlib import Path
import shlex
import sys
import tempfile

from upload import Client, FAKE_HELPER, PRIVATE_ERROR, url


def main(binary: str) -> None:
    os.environ["BIRC_PREFERENCES"] = "none"
    with tempfile.TemporaryDirectory(prefix="birc-upload-diagnostics-") as directory:
        client = Client(Path(binary).resolve(), Path(directory) / "case")
        try:
            helper = FAKE_HELPER.replace(
                '    if kind == "failed":',
                '''    if kind in ("http418", "hostile418"):
        text = "birc-upload: failed (code:5, http:418)\\n"
        if kind == "hostile418": text += "PRIVATE-UPLOAD-HELPER-STDERR\\n"
        os.write(2, text.encode())
        raise SystemExit(5)
    if kind == "failed":''',
            )
            assert helper != FAKE_HELPER, "fake helper insertion point changed"
            client.helper.write_text("#!" + sys.executable + "\n" + helper)
            client.welcome()
            for kind, expected in (
                ("http418", "upload failed (HTTP 418; code: 5)"),
                ("hostile418", "upload failed (code: 5)"),
            ):
                path = client.file(kind, ".html")
                client.offer("/upload " + shlex.quote(str(path)), path)
                start = len(client.wire)
                client.confirm(path)
                client.finished(kind)
                client.quiet_urls(start)
                client.command("/log")
                client.painted("*log*", expected)
                assert PRIVATE_ERROR not in client.screen.text()
                assert "birc-upload: failed" not in client.screen.text(), "raw stderr leaked"
                client.private()
                client.command("/query #t")
                client.painted("CHANNEL-READY")
            # An HTML success after both failures releases the same worker.
            path = client.file("accepted-html", ".html")
            client.offer("/upload " + shlex.quote(str(path)), path)
            client.confirm(path)
            client.finished("accepted-html")
            client.sent(url(path))
            client.quit()
            print("upload_diagnostics_pty=ok")
        finally:
            client.close()


if __name__ == "__main__":
    main(sys.argv[1])
