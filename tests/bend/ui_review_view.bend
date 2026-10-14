# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/view.bend as V
import ../../src/bend/view_laws.bend as VL
import ../../src/bend/media.bend as M
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/split.bend as Sp

def path() -> String:
  "/tmp/synthetic-local.png"

def client() -> Cl.Client:
  Cl.Client{"me", "s", Cl.server_buf() <> Cl.Buffer{"*preview*", False{}, path(), Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}} <> Nil{}, 1n, "", Cl.settings0(), Cl.AuthIdle{}, 0n}

def no_raw.ops(xs: List<&2, V.DrawOp>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{V.OpImage{_, _, _, _, _}, _}: False{}
    case Con{_, t}: no_raw.ops(t)

def no_raw(vm: V.ViewModel) -> Bool:
  match vm:
    case V.ViewModel{ops, _}: no_raw.ops(ops)

def has_token.ops(xs: List<&2, V.DrawOp>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{V.OpMedia{_, _, _, _, _, _, token}, t}: U32.is_eq(token, 7) || has_token.ops(t)
    case Con{_, t}: has_token.ops(t)

def has_token(vm: V.ViewModel) -> Bool:
  match vm:
    case V.ViewModel{ops, _}: has_token.ops(ops)

def production(+media: M.State, split: Sp.State) -> V.ViewModel:
  V.view_draft.state_typing_media(client(), 24, 80, "", "demo", Nil{}, split, media)

def helper_only(+media: M.State) -> Bool:
  no_raw(production(media, Sp.Off{}))
    && no_raw(production(media, Sp.On{Sp.SideBySide{}, "*preview*", "*server*", 0}))
    && no_raw(production(media, Sp.On{Sp.Stacked{}, "*preview*", "*server*", 0}))

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text(t)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("idle local preview helper-only", helper_only(M.empty()))
    Unit <- E.must("pending local preview helper-only", helper_only(M.enqueue(M.initial(False{}), M.Manual{}, path())))
    Unit <- E.must("failed local preview helper-only", helper_only(M.State{False{}, 1n, 2n, None{}, Nil{}, Nil{}, M.Supported{}}))
    +ready : M.State = M.State{False{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Manual{}, path(), 7}], M.Supported{}}
    Unit <- E.must("accepted local preview helper-only", helper_only(ready))
    Unit <- E.must("accepted local preview paints token", has_token(production(ready, Sp.Off{})))
    Unit <- E.must("legacy pure preview adapter remains", Bool.not(no_raw(V.view_draft(client(), 24, 80, "", "demo"))))
    Unit <- E.must_eq("direct runs preserve rendered text", spans_text(V.render_spans("**é** 👩‍💻 :eyes: https://example.test/x")), spans_text(VL.span_ops(VL.tokenize("**é** 👩‍💻 :eyes: https://example.test/x"))))
    IO.print("ui_review_view=ok")
