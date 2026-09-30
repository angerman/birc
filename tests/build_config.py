"""Incremental builds must notice headers and effective compiler flags."""
import pathlib
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix="birc-build-config-") as directory:
    stamp = pathlib.Path(directory) / "config"
    command = ["sh", "scripts/build-config.sh", str(stamp)]
    subprocess.run(command + ["-O2"], check=True)
    before = stamp.stat().st_mtime_ns
    subprocess.run(command + ["-O2"], check=True)
    assert stamp.stat().st_mtime_ns == before, "unchanged flags cause rebuilds"
    subprocess.run(command + ["-O0"], check=True)
    assert stamp.stat().st_mtime_ns != before, "changed flags missed"
    assert "flags=-O0" in stamp.read_text()
plan = subprocess.check_output(
    ["make", "-n", "-W", "src/ffi/birc_utf8_fit.h", "build-ui"], text=True
)
assert "bend src/bend/app.bend" in plan, "FFI helper header is not a dependency"
assert "birc_bend.c -o" in plan, "header change does not relink"
print("build_config=ok")
