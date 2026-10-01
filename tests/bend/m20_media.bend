# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ./m20_media_preds.bend as P
import ../../src/bend/media.bend as M

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("manual refresh/distinct insertion/failed placeholder/stale targets", P.coherence_ok())
    Unit <- E.must_eq("old tokens before manual admission", P.tokens(M.complete(P.active(M.Manual{}, "manual.png"), P.client(), 1n, 9n, "manual.png", 0)), "7,6,5,4,3,2,1")
    Unit <- E.must_eq("unmatched completion keeps all owners", P.tokens(M.complete(P.active(M.Manual{}, "manual.png"), P.client(), 1n, 99n, "manual.png", 0)), "7,6,5,4,3,2,1")
    IO.print("m20_media=ok")
