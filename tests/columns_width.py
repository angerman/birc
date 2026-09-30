#!/usr/bin/env python3
"""Compare Bend column widths to the actual vendored TimUI function."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


header = Path("src/ui/timui.h").read_text(encoding="utf-8")
start = header.index("TIMUI_API int timui_utf8_width(uint32_t cp) {")
opening = header.index("{", start)
depth = 1
end = opening + 1
while depth:
    depth += (header[end] == "{") - (header[end] == "}")
    end += 1
function = header[start:end].removeprefix("TIMUI_API ")
source = "#include <stdint.h>\n#include <stdio.h>\n" + function + r"""
int main(void) {
  for (uint32_t cp = 0; cp <= 0x10FFFF; cp++)
    putchar('0' + timui_utf8_width(cp));
  putchar('\n');
  return 0;
}
"""
with tempfile.TemporaryDirectory(prefix="birc-columns-") as tmp:
    helper = str(Path(tmp) / "timui-width")
    subprocess.run([os.environ["CC"], "-std=c11", "-Wall", "-Wextra", "-Werror",
                    "-pedantic", "-x", "c", "-", "-o", helper],
                   input=source.encode(), check=True, timeout=30)
    expected = subprocess.run([helper], capture_output=True, check=True, timeout=30).stdout
    actual = subprocess.run([sys.argv[1]], capture_output=True, check=True, timeout=60).stdout
    assert len(actual) == len(expected), (len(actual), len(expected))
    for cp, (a, e) in enumerate(zip(actual, expected)):
        assert a == e, f"width differs at U+{cp:04X}: Bend {chr(a)}, TimUI {chr(e)}"
print("columns_width=ok")
