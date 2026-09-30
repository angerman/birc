#!/usr/bin/env python3
"""Native metadata-only size edges and visible history read failures.

Large files are sparse. Only File.size is used on the UINT32_MAX positive
boundary. Oversize restore fails before any read, so no 4 GiB scan occurs.
"""
from __future__ import annotations

import errno
from pathlib import Path
import subprocess
import sys
import tempfile


def probe(binary: str, path: Path, mode: str) -> str:
    return subprocess.check_output([binary, str(path), mode], text=True, timeout=3).strip()


def main() -> None:
    binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else "./build/history_errors").resolve())
    with tempfile.TemporaryDirectory(prefix="birc-history-errors-") as directory:
        root = Path(directory)
        sparse = root / "sparse"
        for size in (0, 37, 2**32 - 1, 2**32, 2**32 + 101):
            with sparse.open("wb") as file:
                file.truncate(size)
            result = probe(binary, sparse, "size")
            print(f"file size {size}: {result}", flush=True)
            if size < 2**32:
                assert result == f"done:{size}", (size, result)
            else:
                assert result.startswith(f"fail:{errno.EOVERFLOW}:"), (size, result)
        overflow = probe(binary, sparse, "load")
        assert "history size unavailable" in overflow and str(errno.EOVERFLOW) in overflow, overflow
        assert overflow.startswith("texts:prefix|"), overflow
        ordinary = root / "ordinary"
        ordinary.write_text("BIRC2\ta:6667\t*server*\tMSG\t\tauthor\trestored\n")
        loaded = probe(binary, ordinary, "load")
        assert "restored|" in loaded and "history " not in loaded, loaded
        missing = probe(binary, root / "absent", "load")
        assert missing == "texts:prefix|", missing
        open_error = probe(binary, ordinary / "child", "load")
        assert "history open failed" in open_error and str(errno.ENOTDIR) in open_error, open_error
        actual_read_error = probe(binary, root, "load")
        assert "history read failed" in actual_read_error and str(errno.EISDIR) in actual_read_error, actual_read_error
        injected = probe(binary, ordinary, "read-error")
        assert "history read failed" in injected and "completed records" in injected and "injected I/O failure" in injected, injected
        assert injected.startswith("texts:prefix|"), injected
    print("history errors: metadata boundaries, overflow, ordinary, missing, open, and partial-read PASS")


if __name__ == "__main__":
    main()
