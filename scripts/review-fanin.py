#!/usr/bin/env python3
"""Per-file rebuild fan-in: how many test binaries `make` rebuilds when a file changes.

At the pre-review baseline 208f7c9 the Makefile had

    BEND_SRC_DEPS := $(wildcard src/bend/*.bend)

on every build rule, so touching ANY src/bend file rebuilt ALL 196 test binaries,
regardless of whether that binary imported the file. Each rule now depends on a
generated build/<stem>.bend.d instead, so touching a file rebuilds only the
binaries whose real import closure contains it.

This computes that closure count from the source import graph, which is what
scripts/bend-deps.sh emits into the .bend.d files. Read-only: never writes,
never builds.

Usage: python3 scripts/review-fanin.py [tree-root]

Measured result on the final tree: 15,288 assumed edges -> 5,611 real, i.e. 63.3%
of rebuild edges eliminated; app.bend 196 -> 6, timui_ffi.c 196 -> 20. The eight
hub modules (irc, links, emoji, diagnostic, buffer, dns_wire, endpoint,
wire_style) still sit at 155-183 of 196 and are the remaining lever.
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

    graph = {}
    for d in ("src/bend", "tests/bend"):
        for p in bend_files(d):
            text = open(p, encoding="utf-8", errors="replace").read()
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

    tests = [p for p in graph if p.startswith("tests/bend")]
    srcs = [p for p in graph if p.startswith("src/bend")]
    ntest = len(tests)

    # fan-in: for every file (bend, C, header), how many test binaries depend on it
    rev = collections.Counter()
    for t in tests:
        for x in closure(t) | {t}:
            rev[x] += 1

    print(f"tree={root}  test binaries={ntest}  src modules={len(srcs)}")
    print(f"baseline fan-in for ANY src/bend file = {ntest} (wildcard BEND_SRC_DEPS)")
    print()

    src_fan = sorted(((rev[s], s) for s in srcs), reverse=True)
    tot_assumed = ntest * len(srcs)
    tot_real = sum(c for c, _ in src_fan)
    print(f"aggregate rebuild edges : {tot_assumed:,} assumed -> {tot_real:,} real"
          f"  = {100.0*(1-tot_real/max(tot_assumed,1)):.1f}% eliminated")
    print()

    print("--- worst-case hubs (touching these still rebuilds most binaries) ---")
    for c, s in src_fan[:8]:
        print(f"  {os.path.basename(s):34s} {c:4d} / {ntest}   ({100.0*c/ntest:.0f}%)")
    print()

    print("--- best case: files that now rebuild almost nothing ---")
    for c, s in src_fan[-10:]:
        print(f"  {os.path.basename(s):34s} {c:4d} / {ntest}")
    print()

    print("--- specific files cited in the review ---")
    for w in ("app.bend", "replay.bend", "view_laws.bend", "wsnet.bend", "net.bend",
              "session.bend", "view.bend", "media.bend", "buffer.bend", "irc.bend",
              "client.bend", "helper_io.bend", "net_msg.bend"):
        p = f"src/bend/{w}"
        if p in rev or p in graph:
            print(f"  {w:34s} {rev[p]:4d} / {ntest}   (was {ntest})")
    print()

    print("--- native / header fan-in (link rules use BEND_UI_SRCS) ---")
    for p in sorted(x for x in rev if x.startswith(("src/ffi", "src/ui"))):
        print(f"  {p:34s} {rev[p]:4d} / {ntest}")
    print()

    hist = collections.Counter()
    for c, _ in src_fan:
        if c <= 10:
            hist["<=10"] += 1
        elif c <= 50:
            hist["11-50"] += 1
        elif c <= 100:
            hist["51-100"] += 1
        elif c <= 150:
            hist["101-150"] += 1
        else:
            hist[">150"] += 1
    print("--- fan-in distribution over src/bend modules ---")
    for k in ("<=10", "11-50", "51-100", "101-150", ">150"):
        if hist[k]:
            print(f"  {k:9s} : {hist[k]:3d} modules")
    print(f"  median    : {src_fan[len(src_fan) // 2][0]} / {ntest}")


if __name__ == "__main__":
    main()
