# SPDX-License-Identifier: Apache-2.0
# Framed theme paint and wire-style storage controls.
# A literal styled PRIVMSG crosses Fr -> Feed after a real self-JOIN. The
# resulting client is painted through a Demo Session, a pure taken-read
# L.loaded completion, and session_paint_vm under Dark/Light/Mono.
#
# Coverage:
# - Stored client/history text retains valid mIRC bold and foreground codes.
# - Current themed and unthemed View entries use the Ws render path. Wire
#   styles, markdown attrs, exact link identity and visible text are inspected
#   as Bend spans; themed foregrounds are inspected as complete decimal tokens.
# - Actual /theme input and parsed preference records select paint palettes.
#   Shape, runs, raw client text and serialized history are compared across
#   loaded themes; field-break removal is pinned separately.
# - SpanOp carries attrs/text, URL/text or attrs/fg/text, with no bg field.
#   The guards inspect consumed bg digits, not native terminal backgrounds.
#
# This fixture does not launch a preference worker, fetch its synthetic URL,
# operate a live connection, paint a native TimUI frame or establish a proof
# result. Assertions below define the coverage; this header records no pass
# or approval claim about another fixture.
import Base
import ./expect.bend as E
import ../../src/bend/theme.bend as Theme
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as Laws
import ../../src/bend/frame.bend as Fr
import ../../src/bend/irc.bend as Irc
import ../../src/bend/links.bend as Links
import ../../src/bend/wire_style.bend as Ws
import ../../src/bend/view.bend as V
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/media.bend as M
import ../../src/bend/history.bend as Hist
import ../../src/bend/preferences.bend as P
import ../../src/bend/preferences_runtime.bend as R
import ../../src/bend/preferences_live.bend as L

# Raw framed body: wire bold, mIRC fg, mIRC fg+bg (bg consumed), markdown,
# and an exact URL. Ingest retains the valid wire codes; paint styles them.
def wire_body() -> String:
  SCon{Chr{2}, "b"} ++ SCon{Chr{2}, " "}
    ++ SCon{Chr{3}, "04red"} ++ SCon{Chr{15}, " "}
    ++ SCon{Chr{3}, "04,02bg"} ++ SCon{Chr{15}, " *bold* _it_ `code` https://x.test/a end"}

def framed.got(pair: List<&2, String> & List<&2, U32> & Bool) -> Cl.Client:
  match pair:
    case (lines, _, _):
      Feed.feed_all(Feed.feed(Cl.init("me", "irc.example"), ":me!u@h JOIN #t"), lines)

def framed_client() -> Cl.Client:
  framed.got(Fr.push_ex(False{}, Nil{},
    Fr.string_to_octets(":alice!u@h PRIVMSG #t :" ++ wire_body() ++ "\r\n")))

def base() -> Sess.Session:
  Sess.session_demo_at(framed_client(), "#t", 6697)

def enter(+st: Sess.Session, +text: String) -> Sess.Session:
  Sess.st_of_keys(Sess.step_enter(st, text))

def theme_of(+st: Sess.Session) -> String:
  Theme.show(Sess.session_theme(st))

def ops_of(vm: V.ViewModel) -> List<&2, V.DrawOp>:
  match vm:
    case V.ViewModel{ops, _}: ops

def paint_ops(+st: Sess.Session) -> List<&2, V.DrawOp>:
  ops_of(Sess.session_paint_vm(st))

def direct_framed() -> List<&2, V.DrawOp>:
  ops_of(V.view_draft.state_typing_media_themed(framed_client(), 24, 80, "", "online", Nil{}, Sp.Off{}, M.empty(), Theme.Dark{}, Nil{}))

def dark_wire() -> String:
  P.show(L.capture(base(), 1))

def light_wire() -> String:
  P.show(L.capture(enter(base(), "/theme light"), 1))

def mono_wire() -> String:
  P.show(L.capture(enter(base(), "/theme mono"), 1))

def buf_lines.on(got: Maybe<&2, Cl.Buffer>) -> List<&2, Cl.Line>:
  match got:
    case None{}: Nil{}
    case Some{b}:
      match b:
        case Cl.Buffer{_, _, _, +lines, _, _}: lines

def buf_lines(+cl: Cl.Client, +i: Nat) -> List<&2, Cl.Line>:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _}:
      buf_lines.on(Cl.nth_buf(bufs, i))

def hist_of(+cl: Cl.Client, +i: Nat) -> String:
  Hist.serialize_lines_for(buf_lines(cl, i), "irc.example:6697", "#t")

def str_list(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: h ++ ";" ++ str_list(t)

def u32_list(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: U32.show(h) ++ ";" ++ u32_list(t)

def span_full(sp: V.SpanOp) -> String:
  match sp:
    case V.Spn{attrs, text}: "S" ++ U32.show(attrs) ++ ":" ++ text ++ ";"
    case V.Lnk{url, text}: "L" ++ url ++ ":" ++ text ++ ";"
    case V.Col{attrs, fg, text}: "C" ++ U32.show(attrs) ++ "/" ++ U32.show(fg) ++ ":" ++ text ++ ";"

def spans_full(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: span_full(h) ++ spans_full(t)

def span_shape(sp: V.SpanOp) -> String:
  match sp:
    case V.Spn{attrs, text}: "S" ++ U32.show(attrs) ++ ":" ++ text ++ ";"
    case V.Lnk{url, text}: "L" ++ url ++ ":" ++ text ++ ";"
    case V.Col{attrs, _, text}: "C" ++ U32.show(attrs) ++ ":" ++ text ++ ";"

def spans_shape(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: span_shape(h) ++ spans_shape(t)

def coords(x: U32, y: U32, w: U32) -> String:
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ ","

def op_full(op: V.DrawOp) -> String:
  match op:
    case V.OpBox{x, y, w, h}: "B" ++ coords(x, y, w) ++ U32.show(h) ++ ";"
    case V.OpSplit{x, y, w, h, axis}: "P" ++ coords(x, y, w) ++ U32.show(h) ++ "," ++ U32.show(axis) ++ ";"
    case V.OpText{x, y, w, fg, attrs, text}:
      "T" ++ coords(x, y, w) ++ U32.show(fg) ++ "/" ++ U32.show(attrs) ++ ":" ++ text ++ ";"
    case V.OpTabs{x, y, w, sel, names, alerts, bell, bell_seq}:
      "A" ++ coords(x, y, w) ++ U32.show(sel) ++ ":" ++ str_list(names) ++ "|" ++ u32_list(alerts)
        ++ "|" ++ U32.show(bell) ++ "," ++ U32.show(bell_seq) ++ ";"
    case V.OpLine{x, y, w, fg, spans}: "N" ++ coords(x, y, w) ++ U32.show(fg) ++ ":" ++ spans_full(spans)
    case V.OpImage{x, y, w, h, path}:
      "I" ++ coords(x, y, w) ++ U32.show(h) ++ ":" ++ path ++ ";"
    case V.OpMedia{x, y, w, h, clip_y, clip_h, token}:
      "M" ++ coords(x, y, w) ++ U32.show(h) ++ "," ++ U32.show(clip_y) ++ ","
        ++ U32.show(clip_h) ++ "," ++ U32.show(token) ++ ";"

def full_list(ops: List<&2, V.DrawOp>) -> String:
  match ops:
    case Nil{}: ""
    case Con{h, t}: op_full(h) ++ full_list(t)

def op_shape(op: V.DrawOp) -> String:
  match op:
    case V.OpBox{x, y, w, h}: "B" ++ coords(x, y, w) ++ U32.show(h) ++ ";"
    case V.OpSplit{x, y, w, h, axis}: "P" ++ coords(x, y, w) ++ U32.show(h) ++ "," ++ U32.show(axis) ++ ";"
    case V.OpText{x, y, w, _, attrs, text}: "T" ++ coords(x, y, w) ++ U32.show(attrs) ++ ":" ++ text ++ ";"
    case V.OpTabs{x, y, w, sel, names, alerts, bell, bell_seq}:
      "A" ++ coords(x, y, w) ++ U32.show(sel) ++ ":" ++ str_list(names) ++ "|" ++ u32_list(alerts)
        ++ "|" ++ U32.show(bell) ++ "," ++ U32.show(bell_seq) ++ ";"
    case V.OpLine{x, y, w, _, spans}: "N" ++ coords(x, y, w) ++ spans_shape(spans)
    case V.OpImage{x, y, w, h, path}:
      "I" ++ coords(x, y, w) ++ U32.show(h) ++ ":" ++ path ++ ";"
    case V.OpMedia{x, y, w, h, clip_y, clip_h, token}:
      "M" ++ coords(x, y, w) ++ U32.show(h) ++ "," ++ U32.show(clip_y) ++ ","
        ++ U32.show(clip_h) ++ "," ++ U32.show(token) ++ ";"

def shape_list(ops: List<&2, V.DrawOp>) -> String:
  match ops:
    case Nil{}: ""
    case Con{h, t}: op_shape(h) ++ shape_list(t)

def span_fgs(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.Col{_, fg, _}, t}: U32.show(fg) ++ "," ++ span_fgs(t)
    case Con{_, t}: span_fgs(t)

def op_fgs(op: V.DrawOp) -> String:
  match op:
    case V.OpText{_, _, _, fg, _, _}: U32.show(fg) ++ ","
    case V.OpLine{_, _, _, fg, spans}: U32.show(fg) ++ "," ++ span_fgs(spans)
    case _: ""

def fg_list(ops: List<&2, V.DrawOp>) -> String:
  match ops:
    case Nil{}: ""
    case Con{h, t}: op_fgs(h) ++ fg_list(t)

# fg_list emits one complete decimal foreground followed by a comma.
def has_fg(+colors: String, fg: U32) -> Bool:
  String.contains("," ++ colors, "," ++ U32.show(fg) ++ ",")

def op_runs(op: V.DrawOp) -> String:
  match op:
    case V.OpLine{_, _, _, _, spans}: spans_shape(spans)
    case _: ""

def runs_list(ops: List<&2, V.DrawOp>) -> String:
  match ops:
    case Nil{}: ""
    case Con{h, t}: op_runs(h) ++ runs_list(t)

def spans_text_of(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text_of(t)

def op_text(op: V.DrawOp) -> String:
  match op:
    case V.OpLine{_, _, _, _, spans}: spans_text_of(spans)
    case _: ""

def lines_text(ops: List<&2, V.DrawOp>) -> String:
  match ops:
    case Nil{}: ""
    case Con{h, t}: op_text(h) ++ lines_text(t)

# Real pending-read context: initial snapshot plus one taken read, exactly
# like the live preferences worker. The ticket owns the completion.
def started(pair: R.State & Maybe<&2, R.Job>) -> L.Context:
  match pair:
    case (state, _): L.wrap(state)

def context_for(+st: Sess.Session) -> L.Context:
  started(R.take(R.initial(True{}, "irc.example", 6697, L.capture(st, 1), 0n, False{}, False{}, False{})))

def loaded_st(res: L.Context & Sess.Session & List<&2, String> & Bool) -> Sess.Session:
  match res:
    case (_, st, _, _): st

def loaded_theme(res: L.Context & Sess.Session & List<&2, String> & Bool) -> String:
  theme_of(loaded_st(res))

def loaded_ops(res: L.Context & Sess.Session & List<&2, String> & Bool) -> List<&2, V.DrawOp>:
  paint_ops(loaded_st(res))

def loaded_cl(res: L.Context & Sess.Session & List<&2, String> & Bool) -> Cl.Client:
  Sess.session_cl(loaded_st(res))

def dark_res() -> L.Context & Sess.Session & List<&2, String> & Bool:
  L.loaded(context_for(base()), base(), 1, 1n, P.parse(dark_wire()), 0)

def light_res() -> L.Context & Sess.Session & List<&2, String> & Bool:
  L.loaded(context_for(base()), base(), 1, 1n, P.parse(light_wire()), 0)

def mono_res() -> L.Context & Sess.Session & List<&2, String> & Bool:
  L.loaded(context_for(base()), base(), 1, 1n, P.parse(mono_wire()), 0)

def main() -> IO(Unit):
  do IO<Unit>:
    # Shared Ws blob pins (theme-independent content): mIRC red is a fixed
    # content byte, and Ws parsing strips exactly what sanitize strips.
    Unit <- E.must_eq("ws2 palette red exact", U32.show(Ws.fg_of(4)), "16711680")
    Unit <- E.must_eq("ws2 visible matches sanitize",
      Ws.visible(Ws.parse(wire_body())), Irc.sanitize_in(wire_body()))
    # Framed ingest RETAINS valid style bytes in storage (G3 keep-style).
    Unit <- E.must_eq("ws2 framed ingest stores retained style bytes",
      Laws.buf_texts(framed_client(), 1n), "-> me joined #t|<alice> " ++ wire_body() ++ "|")
    Unit <- E.must("ws2 framed stored bytes keep controls",
      String.contains(Laws.buf_texts(framed_client(), 1n), SCon{Chr{2}, ""})
        && String.contains(Laws.buf_texts(framed_client(), 1n), SCon{Chr{3}, ""})
        && String.contains(Laws.buf_texts(framed_client(), 1n), SCon{Chr{15}, ""}))
    # Loaded-path theme resolution for the framed session.
    Unit <- E.must_eq("ws2 loaded dark resolves dark", loaded_theme(dark_res()), "dark")
    Unit <- E.must_eq("ws2 loaded light resolves light", loaded_theme(light_res()), "light")
    Unit <- E.must_eq("ws2 loaded mono resolves mono", loaded_theme(mono_res()), "mono")
    # Positive: actual kind fg bytes per loaded theme through framed paint.
    Unit <- E.must("ws2 loaded dark paints exact message color",
      String.contains(fg_list(loaded_ops(dark_res())), "13158600")
        && Bool.not(String.contains(fg_list(loaded_ops(dark_res())), "3355443")))
    Unit <- E.must("ws2 loaded light paints exact message color",
      String.contains(fg_list(loaded_ops(light_res())), "3355443")
        && Bool.not(String.contains(fg_list(loaded_ops(light_res())), "13158600")))
    Unit <- E.must("ws2 loaded mono paints exact kind color",
      String.contains(fg_list(loaded_ops(mono_res())), "14211288"))
    # Positive: exact wire attrs/fg bytes under every loaded theme (Ws owns
    # production paint; content styles are theme-independent by construction).
    Unit <- E.must("ws2 loaded dark keeps exact wire spans",
      String.contains(full_list(loaded_ops(dark_res())), "S1:b;")
        && String.contains(full_list(loaded_ops(dark_res())), "C0/16711680:red;")
        && String.contains(full_list(loaded_ops(dark_res())), "C0/16711680:bg;"))
    Unit <- E.must("ws2 loaded light keeps exact wire spans",
      String.contains(full_list(loaded_ops(light_res())), "S1:b;")
        && String.contains(full_list(loaded_ops(light_res())), "C0/16711680:red;")
        && String.contains(full_list(loaded_ops(light_res())), "C0/16711680:bg;"))
    Unit <- E.must("ws2 loaded mono keeps exact wire spans",
      String.contains(full_list(loaded_ops(mono_res())), "S1:b;")
        && String.contains(full_list(loaded_ops(mono_res())), "C0/16711680:red;")
        && String.contains(full_list(loaded_ops(mono_res())), "C0/16711680:bg;"))
    # Positive: markdown attrs and exact link identity on the styled text.
    Unit <- E.must("ws2 framed dark keeps markdown attrs",
      String.contains(full_list(loaded_ops(dark_res())), "S1:bold;")
        && String.contains(full_list(loaded_ops(dark_res())), "S4:it;")
        && String.contains(full_list(loaded_ops(dark_res())), "S2:code;"))
    Unit <- E.must("ws2 framed dark keeps exact link",
      String.contains(full_list(loaded_ops(dark_res())), "Lhttps://x.test/a:https://x.test/a;"))
    # Positive: nick keeps bold attr, fg follows the loaded theme.
    Unit <- E.must("ws2 nick bold attr with themed fg",
      String.contains(runs_list(loaded_ops(dark_res())), "C1:alice;")
        && String.contains(fg_list(loaded_ops(dark_res())), U32.show(V.nick_color_themed(Theme.Dark{}, "alice")))
        && String.contains(fg_list(loaded_ops(light_res())), U32.show(V.nick_color_themed(Theme.Light{}, "alice")))
        && String.contains(fg_list(loaded_ops(mono_res())), U32.show(V.nick_color_themed(Theme.Mono{}, "alice"))))
    # Positive: exact rendered visible bytes; color digits and bg consumed.
    # lines_text keeps every OpLine. The composer prefix (nine-space timestamp
    # indent plus <nick>) is one of those lines, from composer_ops.
    Unit <- E.must_eq("ws2 framed rendered bytes exact",
      lines_text(direct_framed()), "-> me joined #t<alice> b red bg bold it code https://x.test/a end         <me> ")
    Unit <- E.must("ws2 color digits and bg consumed",
      Bool.not(String.contains(lines_text(direct_framed()), "04"))
        && Bool.not(String.contains(lines_text(direct_framed()), ",02"))
        && Bool.not(String.contains(lines_text(loaded_ops(dark_res())), "04")))
    # Positive: themes change actual paint bytes, not just the selector.
    Unit <- E.must("ws2 light paint bytes differ from dark",
      Bool.not(String.eq(full_list(loaded_ops(light_res())), full_list(loaded_ops(dark_res())))))
    # Positive: production /theme path paints framed content too.
    Unit <- E.must("ws2 slash theme light paints light",
      String.contains(fg_list(paint_ops(enter(base(), "/theme light"))), "3355443"))
    # Control: layout/text identical across loaded themes; only fg bytes move.
    Unit <- E.must_eq("ws2 shape identical light vs dark",
      shape_list(loaded_ops(light_res())), shape_list(loaded_ops(dark_res())))
    Unit <- E.must_eq("ws2 shape identical mono vs dark",
      shape_list(loaded_ops(mono_res())), shape_list(loaded_ops(dark_res())))
    Unit <- E.must_eq("ws2 runs identical light vs dark",
      runs_list(loaded_ops(light_res())), runs_list(loaded_ops(dark_res())))
    Unit <- E.must_eq("ws2 runs identical mono vs dark",
      runs_list(loaded_ops(mono_res())), runs_list(loaded_ops(dark_res())))
    # Control: framed Client bytes (with styles) identical across loaded themes.
    Unit <- E.must_eq("ws2 raw bytes identical light vs dark",
      Laws.buf_texts(loaded_cl(light_res()), 1n), Laws.buf_texts(loaded_cl(dark_res()), 1n))
    Unit <- E.must_eq("ws2 raw bytes identical mono vs dark",
      Laws.buf_texts(loaded_cl(mono_res()), 1n), Laws.buf_texts(loaded_cl(dark_res()), 1n))
    # Control: history bytes identical across loaded themes, styles retained.
    Unit <- E.must_eq("ws2 history identical light vs dark",
      hist_of(loaded_cl(light_res()), 1n), hist_of(loaded_cl(dark_res()), 1n))
    Unit <- E.must_eq("ws2 history identical mono vs dark",
      hist_of(loaded_cl(mono_res()), 1n), hist_of(loaded_cl(dark_res()), 1n))
    Unit <- E.must("ws2 history holds retained style bytes",
      String.contains(hist_of(framed_client(), 1n), SCon{Chr{2}, ""})
        && String.contains(hist_of(framed_client(), 1n), SCon{Chr{3}, ""})
        && String.contains(hist_of(framed_client(), 1n), "https://x.test/a end"))
    Unit <- E.must_eq("ws2 history drops field breaks",
      Hist.serialize_line_for("e", "#t", Cl.Line{Cl.Msg{}, "ts", "a\tb\nc", "au", 0n}),
      "BIRC2\te\t#t\tMSG\tts\tau\tabc\n")
    # Ws-only: the single accepted render path strips wire codes on every
    # production paint entry, themed and unthemed alike (no Links entry).
    Unit <- E.must_eq("ws2 production strips wire codes",
      V.spans_text(V.render_spans(SCon{Chr{2}, "b"})), "b")
    Unit <- E.must_eq("ws2 unthemed msg strips wire codes",
      V.spans_text(V.line_spans_raw(Cl.Msg{}, SCon{Chr{2}, "b"})), "b")
    Unit <- E.must_eq("ws2 unthemed system strips wire codes",
      V.spans_text(V.line_spans_raw(Cl.System{}, SCon{Chr{2}, "b"})), "b")
    Unit <- E.must_eq("ws2 unthemed action strips wire codes",
      V.spans_text(V.line_spans_raw(Cl.Action{}, SCon{Chr{2}, "b"})), "b")
    # Exact-token controls reject decimal prefixes/suffixes and retain both
    # first and later colors; the original substring checks above stay intact.
    Unit <- E.must("ws2 exact fg rejects partial decimal tokens",
      Bool.not(has_fg("33554430,13355443,", 3355443)))
    Unit <- E.must("ws2 exact fg accepts complete decimal tokens",
      has_fg("3355443,13158600,", 3355443)
        && has_fg("3355443,13158600,", 13158600))
    Unit <- E.must("ws2 exact fg rejects empty list",
      Bool.not(has_fg("", 3355443)))
    Unit <- E.must("ws2 loaded dark contains exact foreground",
      has_fg(fg_list(loaded_ops(dark_res())), 13158600)
        && Bool.not(has_fg(fg_list(loaded_ops(dark_res())), 3355443)))
    Unit <- E.must("ws2 loaded light contains exact foreground",
      has_fg(fg_list(loaded_ops(light_res())), 3355443)
        && Bool.not(has_fg(fg_list(loaded_ops(light_res())), 13158600)))
    Unit <- E.must("ws2 loaded mono contains exact foreground",
      has_fg(fg_list(loaded_ops(mono_res())), 14211288)
        && Bool.not(has_fg(fg_list(loaded_ops(mono_res())), 13158600))
        && Bool.not(has_fg(fg_list(loaded_ops(mono_res())), 3355443)))
    IO.print("theme_ws_render=ok")
