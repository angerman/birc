#!/usr/bin/env python3
"""Re-measure the metrics from the 2026-10-16 design review.

Run from a birc checkout. Prints the same quantities the review established so a
before/after comparison is apples-to-apples. Read-only: never writes, never builds.

Baseline values below were produced by running THIS script on a lane pinned at
208f7c9 (the pre-review master), not transcribed from an earlier draft:

  src/bend modules            77      44,774 lines
  tests/bend files           196      29,043 lines
  total Bend lines recompiled by a full test build   4,052,124
  make over-invalidation      15,092 assumed edges vs 5,615 real  = 2.69x
  app.bend closure            72 modules / 43,882 lines
  median test closure         19,431 lines / 27 modules
  largest test closure        45,176 lines / 82 modules (mss_stale_socket)
  modules under 100 lines     22
  largest module              session.bend 5,254
  Bend throughput (calibrated from auth_privacy 92s / 29,918 lines)
                              ~325 lines/sec

Note on over-invalidation: it is `(tests x src modules) / real dependency edges`,
so it measures how much the coarse wildcard dependency would over-rebuild relative
to the real import graph. It does NOT measure whether make actually uses the real
graph -- at baseline make did not (BEND_SRC_DEPS was a wildcard), and at final it
does. Use review-fanin.py for the rebuild counts make actually performs.
"""
import collections
import os
import re
import sys

IMP = re.compile(r'^\s*import\s+"?(\.?\.?/?[\w./-]+\.(?:bend|c|h|js))"?', re.M)


def bend_files(d):
    if not os.path.isdir(d):
        return []
    return [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".bend")]


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    os.chdir(root)

    graph, lines = {}, {}
    for d in ("src/bend", "tests/bend"):
        for p in bend_files(d):
            text = open(p, encoding="utf-8", errors="replace").read()
            lines[p] = text.count("\n")
            deps = set()
            for m in IMP.finditer(text):
                n = os.path.normpath(os.path.join(d, m.group(1)))
                if os.path.exists(n):
                    deps.add(n)
            graph[p] = deps

    def closure(p, seen=None):
        if seen is None:
            seen = set()
        for d in graph.get(p, ()):
            if d not in seen:
                seen.add(d)
                closure(d, seen)
        return seen

    def csize(p):
        return sum(lines.get(x, 0) for x in closure(p) | {p})

    srcs = [p for p in graph if p.startswith("src/bend")]
    tests = [p for p in graph if p.startswith("tests/bend")]

    print(f"src/bend modules        : {len(srcs):5d}   {sum(lines[s] for s in srcs):9,d} lines")
    print(f"tests/bend files        : {len(tests):5d}   {sum(lines[t] for t in tests):9,d} lines")

    # total lines recompiled if every test binary is built
    tot = sum(csize(t) + lines[t] for t in tests)
    print(f"total Bend lines in a full test build : {tot:12,d}")
    print(f"  at ~325 lines/s  => {tot/325/3600:.2f} h single-threaded")

    real = sum(len([x for x in closure(t) if x.startswith('src/bend')]) for t in tests)
    assumed = len(tests) * len(srcs)
    print(f"over-invalidation       : {assumed:,d} assumed vs {real:,d} real = {assumed/max(real,1):.2f}x")

    app = "src/bend/app.bend"
    if app in lines:
        ac = closure(app) | {app}
        a = [x for x in ac if x.startswith("src/bend")]
        print(f"app.bend closure        : {len(a):5d} modules / {sum(lines[x] for x in a):9,d} lines"
              f"  ({len(srcs)-len(a)} modules unreachable from the app)")

    sizes = sorted((csize(t) + lines[t], len(closure(t) | {t}), t) for t in tests)
    if sizes:
        med = sizes[len(sizes) // 2]
        print(f"median test closure     : {med[0]:9,d} lines / {med[1]} modules   (all {len(tests)} files)")
        progs = sorted((s for s in sizes if lines[s[2]] > 20), key=lambda x: x[0])
        if progs:
            pm = progs[len(progs) // 2]
            print(f"median program closure  : {pm[0]:9,d} lines / {pm[1]} modules   ({len(progs)} real programs)")
        print(f"largest test closure    : {sizes[-1][0]:9,d} lines / {sizes[-1][1]} modules"
              f"  ({os.path.basename(sizes[-1][2])})")
        print(f"smallest test closure   : {sizes[0][0]:9,d} lines / {sizes[0][1]} modules"
              f"  ({os.path.basename(sizes[0][2])})")

    print(f"modules under 100 lines : {sum(1 for s in srcs if lines[s] < 100)}")
    big = sorted(((lines[s], s) for s in srcs), reverse=True)[:6]
    print("largest modules         : " + ", ".join(f"{os.path.basename(s)}={n}" for n, s in big))

    # hub fan-in: how many tests transitively import each src module
    rev = collections.Counter()
    for t in tests:
        for s in closure(t):
            if s.startswith("src/bend"):
                rev[s] += 1
    print("top hub fan-in          : " + ", ".join(
        f"{os.path.basename(s)}={c}" for s, c in rev.most_common(6)))

    # FFI-bearing tests (the blast radius of a change to any inlined C file)
    ffi = {p for p in graph if any(x.startswith("src/ffi") for x in closure(p) | {p})}
    aff = [t for t in tests if (closure(t) | {t}) & ffi]
    print(f"tests inlining FFI C    : {len(aff)} of {len(tests)}")

    # laws / proofs
    for f, pat in (("LAWS.bend", r"^law "), ("PROOF.bend", r"^def Laws\.")):
        if os.path.exists(f):
            n = len(re.findall(pat, open(f, encoding="utf-8", errors="replace").read(), re.M))
            print(f"{f:22s}: {n}")


if __name__ == "__main__":
    main()
