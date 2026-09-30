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
    && U32.is_eq(V.style_of(Cl.Highlight{}), 16766720)

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
    case V.Col{attrs, _, +tx}:
      show_spanop.spn(attrs, tx)

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

def show_u32s.chunks(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: U32.show(h) <> show_u32s.chunks(t)

def show_u32s(+xs: List<&2, U32>) -> String:
  String.join(show_u32s.chunks(xs), ",")

def u32s_eq(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      match ys:
        case Nil{}: True{}
        case Con{_, _}: False{}
    case Con{h, t}:
      match ys:
        case Nil{}: False{}
        case Con{j, u}: U32.is_eq(h, j) && u32s_eq(t, u)

def show_op(op: V.DrawOp) -> String:
  match op:
    case V.OpBox{x, y, w, h}:
      "X:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h)
    case V.OpSplit{x, y, w, h, axis}:
      "S:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(axis)
    case V.OpText{_, y, _, _, _, +text}:
      "t:" ++ U32.show(y) ++ "|" ++ text
    case V.OpTabs{_, _, _, sel, names, alerts, bell, bell_seq}:
      "T:" ++ U32.show(sel) ++ "|" ++ show_names(names) ++ "|" ++ show_u32s(alerts) ++ "|" ++ U32.show(bell) ++ "|" ++ U32.show(bell_seq)
    case V.OpLine{_, y, _, fg, spans}:
      "L:" ++ U32.show(y) ++ "|" ++ U32.show(fg) ++ "|" ++ show_spanops(spans)
    case V.OpImage{x, y, w, h, +path}:
      "I:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "|" ++ path

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
    show_ops(V.line_ops(Cl.Line{Cl.Msg{}, "12:00:00", "hello"})),
    "t:0|12:00:00;L:0|13158600|hello"
  )

def draw_link_ok() -> Bool:
  String.eq(
    show_ops(V.line_ops(Cl.Line{Cl.Msg{}, "", "see https://timui.dev x"})),
    "L:0|13158600|see [https://timui.dev]https://timui.dev x"
  )

def wrap_rows_ok.rows(rows: List<&2, V.BodyRow>) -> Bool:
  match rows:
    case Con{V.BodyRow{+ts1, sw1, off1, w1, _, spans1}, Con{V.BodyRow{+ts2, _, off2, w2, _, spans2}, Con{V.BodyRow{+ts3, _, off3, w3, _, spans3}, Nil{}}}}:
      String.eq(ts1, "12:00:00")
        && U32.is_eq(sw1, 8)
        && U32.is_eq(off1, 9)
        && U32.is_eq(w1, 12)
        && String.eq(show_spanops(spans1), "<*alice*> abcd")
        && String.is_empty(ts2)
        && U32.is_eq(off2, 17)
        && U32.is_eq(w2, 4)
        && String.eq(show_spanops(spans2), "efgh")
        && String.is_empty(ts3)
        && U32.is_eq(off3, 17)
        && U32.is_eq(w3, 4)
        && String.eq(show_spanops(spans3), "ij")
    case _:
      False{}

def wrap_rows_ok() -> Bool:
  wrap_rows_ok.rows(V.wrap_line(Cl.Line{Cl.Msg{}, "12:00:00", "<alice> abcdefghij"}, 21, True{}))

def wrap_resize_ok() -> Bool:
  Nat.is_eq(List.length(&2, V.BodyRow, V.wrap_line(Cl.Line{Cl.Msg{}, "", "<alice> abcdefghij"}, 12, False{})), 3n)
    && Nat.is_eq(List.length(&2, V.BodyRow, V.wrap_line(Cl.Line{Cl.Msg{}, "", "<alice> abcdefghij"}, 16, False{})), 2n)

def hostile_body() -> String:
  "look "
    ++ SCon{Chr{31}, "Lhttps://evil.example"}
    ++ SCon{Chr{29}, "https://github.com/zw3rk/birc"}
    ++ SCon{Chr{27}, "x"}

def draw_hostile_ok() -> Bool:
  String.eq(
    show_ops(V.line_ops(Cl.Line{Cl.Msg{}, "", hostile_body()})),
    "L:0|13158600|look "
      ++ SCon{Chr{31}, "Lhttps://evil.example"}
      ++ SCon{Chr{29}, "[https://github.com/zw3rk/birc]https://github.com/zw3rk/birc"}
      ++ SCon{Chr{27}, "x"}
  )

def draw_tabs_ok() -> Bool:
  String.eq(
    show_op(V.OpTabs{0, 1, 10, 1, "server" <> "#birc" <> Nil{}, 0 <> 2 <> Nil{}, 1, 7}),
    "T:1|server,#birc|0,2|1|7"
  )

def tab_alerts_ok.on(+cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _}:
      u32s_eq(V.tab_alerts(bufs, "#a" <> "!#b" <> Nil{}), 0 <> 1 <> 2 <> Nil{})

def tab_alerts_ok() -> Bool:
  tab_alerts_ok.on(Feed.feed_all(Cl.init("me", "s"), ":me!m@h JOIN #a" <> ":me!m@h JOIN #b" <> Nil{}))

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
    case Cl.Client{_, _, +bufs, _, _, +stg}:
      tab_collide.labs(V.tab_names(bufs, Cl.settings_unreads(stg)))

def tab_collide_ok() -> Bool:
  tab_collide_ok.on(Feed.feed(Cl.init("me", "s"), ":server!s@h PRIVMSG me :hi"))

def draw_nicks_ok() -> Bool:
  String.eq(
    show_ops(V.nick_ops(V.Rect{0, 2, 8, 10}, "#birc", "me" <> "alice" <> Nil{})),
    "X:0,2,8,10;t:2|#birc;t:3|me;t:4|alice"
  )
