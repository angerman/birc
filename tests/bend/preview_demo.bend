# M16.1 local PNG preview command and DrawOp goldens.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/submit.bend as Sub
import ../../src/bend/view.bend as V

def take_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def take_outs(pair: Cl.Client & List<&2, String>) -> List<&2, String>:
  match pair:
    case (_, outs): outs

def active_topic.on(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{_, _, +topic, _, _, _, _, _}}: topic

def active_topic(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, +active, _, _, +auth, +log_seq, _}:
      active_topic.on(Cl.nth_buf(bufs, active))

def preview_client() -> Cl.Client:
  take_client(Sub.submit(Cl.init("me", "irc.example"), "/preview file:///tmp/image.png"))

def has_image.go(ops: List<&2, V.DrawOp>) -> Bool:
  match ops:
    case Nil{}: False{}
    case Con{V.OpImage{_, _, w, h, +path}, _}:
      U32.is_gt(w, 0) && U32.is_gt(h, 0) && String.eq(path, "/tmp/image.png")
    case Con{_, t}: has_image.go(t)

def has_image(vm: V.ViewModel) -> Bool:
  match vm:
    case V.ViewModel{ops, _}: has_image.go(ops)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("active", Sub.active_name(preview_client()), "*preview*")
    Unit <- E.must_eq("path", active_topic(preview_client()), "/tmp/image.png")
    Unit <- E.must("draw_op", has_image(V.view_draft(preview_client(), 24, 80, "", "demo")))
    Unit <- E.must(
      "no_outbound",
      List.is_empty(&2, String, take_outs(Sub.submit(Cl.init("me", "irc.example"), "/preview /tmp/image.png")))
    )
    Unit <- E.must_eq(
      "remote_opened",
      Sub.active_name(take_client(Sub.submit(Cl.init("me", "irc.example"), "/preview https://example.test/image.png"))),
      "*preview*"
    )
    IO.print("preview_demo=ok")
