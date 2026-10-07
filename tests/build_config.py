"""Incremental builds must notice headers and effective compiler flags."""
import ast
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
# Test defaults must not start an unrelated Cards worker for fixture URLs.
def cards_off_make(source):
    lines = [line for line in source.splitlines()
             if line.startswith(("test%:", "check:")) and "BIRC_CARDS" in line.split()]
    return lines == [f"{target}: export BIRC_CARDS := off" for target in ("test%", "check")]


def cards_off_env(source):
    values = []
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Dict):
            if any(isinstance(t, ast.Name) and t.id == "env" for t in node.targets):
                values.extend(v.value if isinstance(v, ast.Constant) else None
                              for k, v in zip(node.value.keys, node.value.values)
                              if isinstance(k, ast.Constant) and k.value == "BIRC_CARDS")
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id == "env" and node.func.attr == "update"):
            values.extend(k.value.value if isinstance(k.value, ast.Constant) else None
                          for k in node.keywords if k.arg == "BIRC_CARDS")
    return bool(values) and all(value == "off" for value in values)


safe_make = "test%: export BIRC_CARDS := off\ncheck: export BIRC_CARDS := off\n"
assert cards_off_make(safe_make)
for bad in (safe_make.splitlines()[0], safe_make.splitlines()[1],
            safe_make.replace(":=", "?="), safe_make.replace("off", "on"),
            safe_make + "test%: export BIRC_CARDS := on\n"):
    assert not cards_off_make(bad), "missing or permissive Cards default admitted"
# Dedicated Cards recipes may enable their explicitly owned fake helper.
assert cards_off_make(safe_make + '\texport BIRC_CARDS=on BIRC_CARDS_HELPER="$$d/cards-helper"\n')
assert cards_off_make(pathlib.Path("Makefile").read_text()), "test/check Cards default is not forced off"
for good in ('env = {"BIRC_CARDS": "off"}',
             'env = {k: v for k, v in inherited.items() if not k.startswith("BIRC_")}\nenv.update(BIRC_CARDS="off")'):
    assert cards_off_env(good)
    for bad in (good.replace("BIRC_CARDS", "OTHER"), good.replace('"off"', '"on"'),
                good.replace("env.update", "env.setdefault")):
        if bad != good:
            assert not cards_off_env(bad), "missing or enabled Cards fixture environment admitted"
for name in ("upload", "history_images", "image_marker", "deferred_redraw"):
    assert cards_off_env(pathlib.Path(f"tests/pty/{name}.py").read_text()), name + " does not disable Cards"
print("build_config=ok")
