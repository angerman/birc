# Uncited view *_ok / show_* helpers. body_ys_ok and show_spans stay in src.
import Base
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/view.bend as V

def style_spec_ok() -> Bool:
  U32.is_eq(V.style_of(Cl.Msg{}), 13158600)
    && U32.is_eq(V.style_of(Cl.Self{}), 5893695)
    && U32.is_eq(V.style_of(Cl.System{}), 10526880)
    && U32.is_eq(V.style_of(Cl.Action{}), 13079274)
    && U32.is_eq(V.style_of(Cl.Notice{}), 8563455)
    && U32.is_eq(V.style_of(Cl.Error{}), 16223340)

def show_spanop.ital(+tx: String, ital: Bool) -> String:
  match ital:
    case True{}:
      "_" ++ tx ++ "_"
    case False{}:
      tx

def show_spanop.bold(+tx: String, bold: Bool, ital: Bool) -> String:
  match bold:
    case True{}:
      "*" ++ tx ++ "*"
    case False{}:
      show_spanop.ital(tx, ital)

def show_spanop.spn(+attrs: U32, +tx: String) -> String:
  show_spanop.bold(tx, U32.is_eq(attrs, 1), U32.is_eq(attrs, 4))

def show_spanop(sp: V.SpanOp) -> String:
  match sp:
    case V.Spn{attrs, +tx}:
      show_spanop.spn(attrs, tx)
    case V.Lnk{+url, +text}:
      "[" ++ url ++ "]" ++ text

def show_spanops.chunks(+xs: List<&2, V.SpanOp>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      show_spanop(h) <> show_spanops.chunks(t)

def show_spanops(+xs: List<&2, V.SpanOp>) -> String:
  String.concat(show_spanops.chunks(xs))

def show_names(+xs: List<&2, String>) -> String:
  String.join(xs, ",")

def show_op(op: V.DrawOp) -> String:
  match op:
    case V.OpBox{x, y, w, h}:
      "X:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h)
    case V.OpText{_, y, _, _, _, +text}:
      "t:" ++ U32.show(y) ++ "|" ++ text
    case V.OpTabs{_, _, _, sel, names}:
      "T:" ++ U32.show(sel) ++ "|" ++ show_names(names)
    case V.OpLine{_, y, _, fg, +ts, spans}:
      "L:" ++ U32.show(y) ++ "|" ++ U32.show(fg) ++ "|" ++ ts ++ "|" ++ show_spanops(spans)

def show_ops.chunks(+xs: List<&2, V.DrawOp>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      show_op(h) <> show_ops.chunks(t)

def show_ops(+xs: List<&2, V.DrawOp>) -> String:
  String.join(show_ops.chunks(xs), ";")

def draw_line_ok() -> Bool:
  String.eq(
    show_op(V.line_op(Cl.Line{Cl.Msg{}, "12:00:00", "hello"})),
    "L:0|13158600|12:00:00|hello"
  )

def draw_link_ok() -> Bool:
  String.eq(
    show_op(V.line_op(Cl.Line{Cl.Msg{}, "", "see https://timui.dev x"})),
    "L:0|13158600||see [https://timui.dev]https://timui.dev x"
  )

def hostile_body() -> String:
  "look "
    ++ SCon{Chr{31}, "Lhttps://evil.example"}
    ++ SCon{Chr{29}, "https://github.com/zw3rk/birc"}
    ++ SCon{Chr{27}, "x"}

def draw_hostile_ok() -> Bool:
  String.eq(
    show_op(V.line_op(Cl.Line{Cl.Msg{}, "", hostile_body()})),
    "L:0|13158600||look "
      ++ SCon{Chr{31}, "Lhttps://evil.example"}
      ++ SCon{Chr{29}, "[https://github.com/zw3rk/birc]https://github.com/zw3rk/birc"}
      ++ SCon{Chr{27}, "x"}
  )

def draw_tabs_ok() -> Bool:
  String.eq(
    show_op(V.OpTabs{0, 1, 10, 1, "server" <> "#birc" <> Nil{}}),
    "T:1|server,#birc"
  )

def tab_star_ok() -> Bool:
  V.tab_names_ok()

def tab_collide.labs(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+a, Con{+b, t}}:
      String.eq(a, "*server*") && String.eq(b, "server")
    case Nil{}:
      False{}
    case Con{_, Nil{}}:
      False{}

def tab_collide_ok.on(cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{_, _, +bufs, _, _}:
      tab_collide.labs(V.tab_names(bufs))

def tab_collide_ok() -> Bool:
  tab_collide_ok.on(Feed.feed(Cl.init("me", "s"), ":server!s@h PRIVMSG me :hi"))

def draw_nicks_ok() -> Bool:
  String.eq(
    show_ops(V.nick_ops(V.Rect{0, 2, 8, 10}, "#birc", "me" <> "alice" <> Nil{})),
    "X:0,2,8,10;t:2|#birc;t:3|me;t:4|alice"
  )
