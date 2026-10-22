# M16.3 scrollback search goldens.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/history_search.bend as Hs

def fixture() -> Cl.Client:
  Feed.feed_all(
    Cl.init("me", "irc.example"),
    ":me!u@h JOIN #birc"
      <> ":alice!u@h PRIVMSG #birc :Hello World"
      <> ":bob!u@h PRIVMSG me :hello private"
      <> Nil{}
  )

def take_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _):
      cl

def take_outs(pair: Cl.Client & List<&2, String>) -> List<&2, String>:
  match pair:
    case (_, outs):
      outs

def texts_at.got(+cl: Cl.Client, got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}:
      ""
    case Some{i}:
      CL.buf_texts(cl, i)

def texts_at(+cl: Cl.Client, +name: String) -> String:
  texts_at.got(cl, Cl.buf_find(cl, name))

def search_client() -> Cl.Client:
  take_client(Sub.submit(fixture(), "/search HELLO"))

def repeat_hit(n: Nat, +i: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Cl.Line{Cl.Msg{}, "", "hit " ++ Nat.show(i), "", 0n} <> repeat_hit(p, Nat.add(i, 1n))

def cap_fixture() -> Cl.Buffer:
  Cl.buf_indexed("#many", True{}, "", repeat_hit(Nat.add(Cl.SCROLL_CAP(), 1n), 0n), Nil{}, Cl.ScrollAt{0n, 0n})

def first_text(xs: List<&2, Cl.Line>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{Cl.Line{_, _, +text, +author, +id}, _}:
      text

def last_text.go(xs: List<&2, Cl.Line>, +last: String) -> String:
  match xs:
    case Nil{}:
      last
    case Con{Cl.Line{_, _, +text, +author, +id}, t}:
      last_text.go(t, text)

def last_text(xs: List<&2, Cl.Line>) -> String:
  last_text.go(xs, "")

def empty_query_active() -> String:
  Sub.active_name(take_client(Sub.submit(fixture(), "/search")))

def ctl(+n: U32, +s: String) -> String:
  SCon{Chr{n}, s}

def color_fixture() -> Cl.Client:
  Feed.feed_all(
    Cl.init("me", "irc.example"),
    ":me!u@h JOIN #birc"
      <> (":alice!u@h PRIVMSG #birc :" ++ ctl(3, "04hello"))
      <> ":bob!u@h PRIVMSG #birc :call 04 now"
      <> Nil{}
  )

def fill_buffers.go(n: Nat, +i: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n:
      cl
    case 1n+p:
      fill_buffers.go(
        p,
        Nat.add(i, 1n),
        Feed.feed(cl, ":me!u@h JOIN #full" ++ Nat.show(i))
      )

def full_client() -> Cl.Client:
  fill_buffers.go(15n, 0n, Cl.init("me", "irc.example"))

def full_search_client() -> Cl.Client:
  take_client(Sub.submit(full_client(), "/search hello"))

def kind_name(kind: Cl.LineKind) -> String:
  match kind:
    case Cl.Msg{}: "MSG"
    case Cl.Action{}: "ACT"
    case Cl.Notice{}: "NOT"
    case _: "?"

def line_sig(ln: Cl.Line) -> String:
  match ln:
    case Cl.Line{kind, _, text, author, _}:
      kind_name(kind) ++ "|" ++ author ++ "|" ++ text

def lines_sig(xs: List<&2, Cl.Line>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: line_sig(h) ++ "\n" ++ lines_sig(t)

def chan_lines.buf(b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, _, lines, _, _, _, _}: lines_sig(lines)

def chan_lines.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: "<missing>"
    case Some{b}: chan_lines.buf(b)

def chan_lines.idx(cl: Cl.Client, i: Nat) -> String:
  match cl:
    case Cl.Client{_, _, bufs, _, _, _, _, _, _}:
      chan_lines.got(Cl.nth_buf(bufs, i))

def chan_lines.find(cl: Cl.Client, got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "<missing>"
    case Some{i}: chan_lines.idx(cl, i)

def chan_lines(+cl: Cl.Client) -> String:
  chan_lines.find(cl, Cl.buf_find(cl, "#chan"))

def or_idle(got: Maybe<&2, Hs.ChatBatch>) -> Hs.ChatBatch:
  match got:
    case None{}: Hs.ChatIdle{}
    case Some{b}: b

def color_byte() -> String:
  SCon{Chr{3}, "04red"}

def ctcp_action() -> String:
  ctl(1, "ACTION " ++ color_byte() ++ ctl(1, ""))

def styled_open() -> Hs.ChatBatch:
  or_idle(Hs.batch_open(":irc.test BATCH +abc chathistory #chan", "irc.test"))

def styled_batch() -> Hs.ChatBatch:
  Hs.batch_close(
    Hs.batch_line(
      Hs.batch_line(
        Hs.batch_line(styled_open(), "me", "@batch=abc;msgid=n1 :bob!u@h NOTICE #chan :note"),
        "me", "@batch=abc;msgid=a1 :alice!u@h PRIVMSG #chan :" ++ ctcp_action()),
      "me", "@batch=abc;msgid=p1 :carol!u@h PRIVMSG #chan :hi"),
    ":irc.test BATCH -abc", "irc.test")

def styled_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def styled_imported() -> Cl.Client:
  styled_client(Hs.import_source_page(Cl.init("me", "irc.test"), "#chan",
    Hs.batch_matches(styled_batch()), False{}, Nil{}))

def want_styled() -> String:
  "NOT|bob|<bob> note\nACT|alice|* alice " ++ color_byte() ++ "\nMSG|carol|<carol> hi\n"

def id_page(fuel: Nat, +prefix: String, +i: Nat) -> List<&2, Hs.ServerMatch>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      Hs.ServerMatch{"#chan", Cl.Line{Cl.Msg{}, "", "t", "a", 0n}, prefix ++ Nat.show(i)}
        <> id_page(p, prefix, Nat.add(i, 1n))

def step_page.got(hl: Hs.HistLive, pair: Cl.Client & List<&2, String>) -> Hs.HistLive & Cl.Client:
  match pair:
    case (cl, seen): (Hs.hist_live_note_seen(hl, seen), cl)

def step_page(+hl: Hs.HistLive, cl: Cl.Client, matches: List<&2, Hs.ServerMatch>) -> Hs.HistLive & Cl.Client:
  step_page.got(hl, Hs.import_source_page(cl, "#chan", matches, False{}, Hs.hist_live_seen(hl)))

def step_page_hl(pair: Hs.HistLive & Cl.Client) -> Hs.HistLive:
  match pair:
    case (hl, _): hl

def two_pages.second(pair: Hs.HistLive & Cl.Client) -> Hs.HistLive:
  match pair:
    case (hl, cl): step_page_hl(step_page(hl, cl, id_page(100n, "b", 0n)))

def two_pages() -> Hs.HistLive:
  two_pages.second(step_page(Hs.hist_live0(), Cl.init("me", "irc.test"), id_page(100n, "a", 0n)))

def fresh_count(seen: List<&2, String>, msgid: String) -> Nat:
  List.length(&2, Hs.ServerMatch,
    Hs.import_source_fresh(
      Hs.ServerMatch{"#chan", Cl.Line{Cl.Msg{}, "", "t", "a", 0n}, msgid} <> Nil{},
      "#chan", seen))

def seen_has(seen: List<&2, String>, id: String) -> Bool:
  List.contains(~String, ~String.eq, seen, id)

def main() -> IO(Unit):
  +styled : String = chan_lines(styled_imported())
  +seen : List<&2, String> = Hs.hist_live_seen(two_pages())
  do IO<Unit>:
    Unit <- E.must_eq("active", Sub.active_name(search_client()), "*search*")
    Unit <- E.must_eq("count", Nat.show(CL.nbuf(search_client())), "4")
    Unit <- E.must_eq(
      "matches",
      texts_at(search_client(), "*search*"),
      "[#birc] <alice> Hello World|[bob] <bob> hello private|"
    )
    Unit <- E.must(
      "no_outbound",
      List.is_empty(&2, String, take_outs(Sub.submit(fixture(), "/search hello")))
    )
    Unit <- E.must(
      "read_only",
      List.is_empty(&2, String, take_outs(Sub.submit(search_client(), "do not send")))
    )
    Unit <- E.must_eq(
      "repeat_replaces",
      texts_at(take_client(Sub.submit(search_client(), "/search private")), "*search*"),
      "[bob] <bob> hello private|"
    )
    Unit <- E.must_eq("empty_usage", empty_query_active(), "#birc")
    Unit <- E.must("fuzzy", Feed.search_text_matches("Hello World", "hlo"))
    Unit <- E.must_eq(
      "style04_only_literal",
      texts_at(take_client(Sub.submit(color_fixture(), "/search 04")), "*search*"),
      "[#birc] <bob> call 04 now|"
    )
    Unit <- E.must_eq(
      "hello_styled_traversal",
      texts_at(take_client(Sub.submit(color_fixture(), "/search hello")), "*search*"),
      "[#birc] <alice> " ++ ctl(3, "04hello") ++ "|"
    )
    Unit <- E.must_eq("full_count", Nat.show(CL.nbuf(full_search_client())), "16")
    Unit <- E.must_eq("full_active", Sub.active_name(full_search_client()), "#full13")
    Unit <- E.must(
      "full_error",
      String.contains(texts_at(full_search_client(), "#full13"), "search unavailable: buffer limit reached")
    )
    Unit <- E.must_eq(
      "cap",
      Nat.show(List.length(&2, Cl.Line, Feed.search_buf(cap_fixture(), "hit"))),
      Nat.show(Cl.SCROLL_CAP())
    )
    Unit <- E.must_eq("cap_first", first_text(Feed.search_buf(cap_fixture(), "hit")), "[#many] hit 1")
    Unit <- E.must_eq("cap_last", last_text(Feed.search_buf(cap_fixture(), "hit")), "[#many] hit 1024")
    Unit <- E.must_eq("import_notice_action_color", styled, want_styled())
    Unit <- E.must("seen_cap_above_page", Nat.is_gt(Hs.SEEN_CAP(), Hs.BATCH_CAP()))
    Unit <- E.must_eq("seen_two_pages", Nat.show(List.length(&2, String, seen)), "200")
    Unit <- E.must("seen_keeps_a0", seen_has(seen, "a0"))
    Unit <- E.must("seen_keeps_a99", seen_has(seen, "a99"))
    Unit <- E.must("seen_keeps_b0", seen_has(seen, "b0"))
    Unit <- E.must("seen_keeps_b99", seen_has(seen, "b99"))
    Unit <- E.must_eq("seen_page1_not_reinserted", Nat.show(fresh_count(seen, "a0")), "0")
    Unit <- E.must_eq("seen_admits_new", Nat.show(fresh_count(seen, "z9")), "1")
    IO.print("search_demo=ok")
