# SPDX-License-Identifier: Apache-2.0
# Prospective Bend ownership drives the actual native cache guard.
import Base
import ../../src/bend/media.bend as M
import ../../src/bend/buffer.bend as Cl

def url(id: Nat) -> String:
  "https://offline.invalid/" ++ Nat.show(id) ++ ".png"

def lines(+n: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p: Cl.Line{Cl.Msg{}, "", url(n), "alice", n} <> lines(p)

def ready(+n: Nat) -> List<&2, M.MediaReady>:
  match n:
    case 0n: Nil{}
    case 1n+p: M.MediaReady{M.Inline{n}, url(n), U32.from_nat(n)} <> ready(p)

def client() -> Cl.Client:
  Cl.Client{"me", "s", [Cl.Buffer{"*server*", False{}, "", lines(8n), Nil{}, Cl.ScrollAt{0n, 0n}},
    Cl.Buffer{"*preview*", False{}, "manual.png", Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}}],
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 8n}

def full() -> M.State:
  M.State{True{}, 1n, 9n, None{}, Nil{}, M.MediaReady{M.Manual{}, "manual.png", 8} <> ready(7n), M.Supported{}}

def started(pair: M.State & Maybe<&2, M.Request>) -> M.State:
  match pair:
    case (state, _): state

def active(target: M.Target, source: String) -> M.State:
  started(M.take_job(M.enqueue(full(), target, source)))

def token_strings(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: U32.show(h) <> token_strings(t)

def tokens(state: M.State) -> String:
  String.join(token_strings(M.retained_tokens(state)), ",")

def coherence_ok() -> Bool:
  +manual = active(M.Manual{}, "manual.png")
  String.eq(tokens(M.complete(manual, client(), 1n, 9n, "manual.png", 0)), "7,6,5,4,3,2,1")
    && String.eq(tokens(M.complete(manual, client(), 1n, 9n, "manual.png", 9)), "9,7,6,5,4,3,2,1")
    && String.eq(tokens(M.complete(active(M.Inline{8n}, url(8n)), client(), 1n, 9n, url(8n), 0)), "8,7,6,5,4,3,2")
    && String.eq(tokens(M.maintain(full(), Cl.init("me", "s"))), "")
