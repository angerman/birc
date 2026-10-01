# SPDX-License-Identifier: Apache-2.0
# Regression guards use production DNS parsing and replay finalization.
import Base
import ./expect.bend as E
import ./m21_dns_preds.bend as D
import ../../src/bend/dns_wire.bend as W
import ../../src/bend/replay.bend as R
import ../../src/bend/frame.bend as F
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as L

def record() -> String:
  ":me!u@h JO" ++ SCon{Chr{31}, "IN #room"}

def joined(cl: Cl.Client) -> Bool:
  L.has_buf(cl, "#room")

def completed(state: R.ReadState) -> Cl.Client:
  match state:
    case R.ReadState{cl, _, _}: cl

def replay_ok() -> Bool:
  joined(R.finish_client(False{}, Cl.init("me", "s"), F.string_to_octets(record())))
    && joined(completed(R.chunk(R.ReadState{Cl.init("me", "s"), Nil{}, False{}}, F.crlf(record()))))
    && joined(R.finish_client(False{}, Cl.init("me", "s"), F.string_to_octets(":me!u@h JOIN #room")))
    && Bool.not(joined(R.finish_client(True{}, Cl.init("me", "s"), F.string_to_octets(record()))))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("label identity", D.label_identity_ok())
    Unit <- E.must_eq("uncompressed dotted name", D.parsed(D.complete(D.dotted(), D.dotted())), "ok:1.2.3.4")
    Unit <- E.must_eq("mixed case and rooted host", D.parsed.got(W.parse_q(1, "A.B.", D.complete([1, 65, 1, 66, 0], [192, 12]))), "ok:1.2.3.4")
    Unit <- E.must("error reply identity", D.error_identity_ok())
    Unit <- E.must_eq("error wrong id", D.taken(D.error(2, 129, 1, D.dotted())), "miss")
    Unit <- E.must_eq("error zero questions", D.taken(D.error(1, 129, 0, D.dotted())), "miss")
    Unit <- E.must_eq("error missing question", D.taken(D.response(1, 129, 131, 1, 0, Nil{}, Nil{})), "miss")
    Unit <- E.must_eq("error dotted-label question", D.taken(D.error(1, 129, 1, D.label_dot())), "miss")
    Unit <- E.must_eq("error wrong type", D.taken(D.response(1, 129, 131, 1, 0, [1, 97, 1, 98, 0, 0, 255, 0, 1], Nil{})), "miss")
    Unit <- E.must_eq("error wrong class", D.taken(D.response(1, 129, 131, 1, 0, [1, 97, 1, 98, 0, 0, 1, 0, 3], Nil{})), "miss")
    Unit <- E.must_eq("error wrong peer", D.taken.got(W.take_pkt("127.0.0.1", 1, "a.b", "127.0.0.2", 53, D.error(1, 129, 1, D.dotted()))), "miss")
    Unit <- E.must_eq("error wrong port", D.taken.got(W.take_pkt("127.0.0.1", 1, "a.b", "127.0.0.1", 54, D.error(1, 129, 1, D.dotted()))), "miss")
    Unit <- E.must("final replay normalization and retained/drop controls", replay_ok())
    Unit <- E.must("final replay UTF-8", L.has_buf(R.finish_client(False{}, Cl.init("me", "s"), F.string_to_octets(":me!u@h JOIN #café")), "#café"))
    Unit <- E.must("final replay Latin-1 fallback", L.has_buf(R.finish_client(False{}, Cl.init("me", "s"), List.append(&2, U32, F.string_to_octets(":me!u@h JOIN #caf"), [233])), "#café"))
    Unit <- E.must("empty final replay", Bool.not(joined(R.finish_client(False{}, Cl.init("me", "s"), Nil{}))))
    IO.print("m21_runtime=ok")
