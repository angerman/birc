# Disk-history search/paging + draft/chathistory server history goldens.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/irc.bend as Irc
import ../../src/bend/history.bend as Hist
import ../../src/bend/history_search.bend as Hs

def soh() -> String:
  SCon{Chr{1}, ""}

def query_text(+got: Maybe<&2, Hs.DiskQuery>) -> String:
  match got:
    case None{}: "<none>"
    case Some{Hs.DiskQuery{+text, +target}}: target ++ "|" ++ text

def open_ref(+got: Maybe<&2, Hs.ChatBatch>) -> String:
  match got:
    case None{}: "<none>"
    case Some{Hs.ChatCollect{+ref, +target, _, _, _}}: ref ++ "|" ++ target
    case Some{Hs.ChatDone{+ref, +target, _, _}}: "done:" ++ ref ++ "|" ++ target
    case Some{Hs.ChatIdle{}}: "idle"

def or_idle(got: Maybe<&2, Hs.ChatBatch>) -> Hs.ChatBatch:
  match got:
    case None{}: Hs.ChatIdle{}
    case Some{+b}: b

def batch_tag(batch: Hs.ChatBatch) -> String:
  match batch:
    case Hs.ChatIdle{}: "idle"
    case Hs.ChatCollect{_, _, _, +messages, _}: "collect:" ++ Nat.show(List.length(&2, Hs.BatchMsg, messages))
    case Hs.ChatDone{_, _, _, _}: "done"

def batch_count(batch: Hs.ChatBatch) -> Nat:
  List.length(&2, Hs.BatchMsg, Hs.batch_messages(batch))

def first_of(msgs: List<&2, Hs.BatchMsg>) -> String:
  match msgs:
    case Nil{}: "<empty>"
    case Con{Hs.BatchMsg{+msgid, +stamp, +text, +author}, _}: msgid ++ "|" ++ stamp ++ "|" ++ text ++ "|" ++ author

def batch_first_text(batch: Hs.ChatBatch) -> String:
  first_of(Hs.batch_messages(batch))

def maybe_line(+got: Maybe<&2, String>) -> String:
  match got:
    case None{}: "<none>"
    case Some{+l}: l

def outs_of(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, +outs): String.join(outs, "|")

def submitted_outs(+cl: Cl.Client, +rest: String, +neg: Bool) -> String:
  outs_of(Hs.submit_history(cl, rest, neg))

def echo_of(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (+cl2, _): CL.buf_texts(cl2, Cl.active_of(cl2))

def submitted_echo(+cl: Cl.Client, +rest: String, +neg: Bool) -> String:
  echo_of(Hs.submit_history(cl, rest, neg))

def request_tag(req: Hs.HistoryRequest) -> String:
  match req:
    case Hs.ReqSearch{+text, +target, _}: "search:" ++ target ++ "|" ++ text
    case Hs.ReqPage{+cursor, +text, +target, _}: "page:" ++ Nat.show(cursor) ++ ":" ++ target ++ "|" ++ text
    case Hs.ReqLatest{+target, +limit}: "latest:" ++ target ++ ":" ++ Nat.show(limit)
    case Hs.ReqBefore{+target, +anchor, +limit}: "before:" ++ target ++ ":" ++ anchor ++ ":" ++ Nat.show(limit)
    case Hs.ReqAfter{+target, +anchor, +limit}: "after:" ++ target ++ ":" ++ anchor ++ ":" ++ Nat.show(limit)
    case Hs.ReqAround{+target, +anchor, +limit}: "around:" ++ target ++ ":" ++ anchor ++ ":" ++ Nat.show(limit)
    case Hs.ReqBetween{+target, +a, +b, +limit}: "between:" ++ target ++ ":" ++ a ++ ":" ++ b ++ ":" ++ Nat.show(limit)
    case Hs.ReqUsage{}: "usage"

def record_sig(got: Maybe<&2, Hs.DiskMatch>) -> String:
  match got:
    case None{}: "<none>"
    case Some{Hs.DiskMatch{+target, _, +at}}: target ++ "|" ++ Nat.show(at)

def cap_tag(+e: Hs.CapEvent) -> String:
  match e:
    case Hs.ChathistoryAck{}: "ack"
    case Hs.ChathistoryNak{}: "nak"
    case Hs.ChathistoryOther{}: "other"

def cursor_sig(+c: Hs.HistoryCursor) -> String:
  match c:
    case Hs.HistoryCursor{_, +oldest, +newest, +seen, +count}:
      oldest ++ "|" ++ newest ++ "|" ++ Nat.show(List.length(&2, String, seen)) ++ "|" ++ Nat.show(count)

def retain_second(pair: List<&2, Hs.DiskMatch> & Bool) -> List<&2, Hs.DiskMatch>:
  match pair:
    case (+k, _): k

def retain_first(pair: List<&2, Hs.DiskMatch> & Bool, +b: Hs.DiskMatch) -> List<&2, Hs.DiskMatch>:
  match pair:
    case (+k, _): retain_second(Hs.retain(k, b))

def retain_two(+a: Hs.DiskMatch, +b: Hs.DiskMatch) -> List<&2, Hs.DiskMatch>:
  retain_first(Hs.retain(Nil{}, a), b)

def batch_msg(+n: Nat) -> String:
  "@batch=abc;msgid=m" ++ Nat.show(n) ++ " :alice!u@h PRIVMSG #chan :text " ++ Nat.show(n)

def feed_many(n: Nat, +i: Nat, batch: Hs.ChatBatch) -> Hs.ChatBatch:
  match n:
    case 0n: batch
    case 1n+p: feed_many(p, 1n+i, Hs.batch_line(batch, "me", batch_msg(i)))

def open_chan_batch() -> Hs.ChatBatch:
  or_idle(Hs.batch_open(":irc.test BATCH +abc chathistory #chan", "irc.test"))

def open_query_batch() -> Hs.ChatBatch:
  or_idle(Hs.batch_open(":irc.test BATCH +q chathistory bob", "irc.test"))

def collected(batch: Hs.ChatBatch) -> Hs.ChatBatch:
  Hs.batch_close(Hs.batch_line(Hs.batch_line(batch, "me",
    "@batch=abc;msgid=m1;time=2026-10-03T10:00:00Z :alice!u@h PRIVMSG #chan :hello"),
    "me", "@batch=abc;msgid=m2 :bob!u@h NOTICE #chan :note"), ":irc.test BATCH -abc", "irc.test")

def fixture_client() -> Cl.Client:
  Feed.feed_all(Cl.init("me", "irc.test"),
    ":me!u@h JOIN #chan" <> ":alice!u@h PRIVMSG #chan :live hello" <> Nil{})

def texts_or_missing(got: Maybe<&2, Nat>, +cl: Cl.Client) -> String:
  match got:
    case None{}: "<missing>"
    case Some{+i}: CL.buf_texts(cl, i)

def search_texts(+cl: Cl.Client) -> String:
  texts_or_missing(Cl.buf_find(cl, "*search*"), cl)

def repeat_char(n: Nat, +c: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: c ++ repeat_char(p, c)

# H5y fixtures: a full 100-id saved set plus fresh pages.
def saved_ids(n: Nat, +i: Nat) -> List<&2, String>:
  match n:
    case 0n: Nil{}
    case 1n+p: ("s" ++ Nat.show(i)) <> saved_ids(p, 1n+i)

def fresh_msgs(n: Nat, +i: Nat) -> List<&2, Hs.BatchMsg>:
  match n:
    case 0n: Nil{}
    case 1n+p: Hs.BatchMsg{"f" ++ Nat.show(i), "", "t", "a"} <> fresh_msgs(p, 1n+i)

def main() -> IO(Unit):
  +rec : String = "BIRC2\ta:6667\t#chan\tMSG\t10:00:00\talice\thello disk"
  +mka : Hs.DiskMatch = Hs.DiskMatch{"#a", Cl.Line{Cl.Msg{}, "", "a", "", 0n}, 10n}
  +mkb : Hs.DiskMatch = Hs.DiskMatch{"#a", Cl.Line{Cl.Msg{}, "", "b", "", 0n}, 4n}
  +kept : List<&2, Hs.DiskMatch> = retain_two(mka, mkb)
  +full : Hs.ChatBatch = collected(open_chan_batch())
  +matches : List<&2, Hs.ServerMatch> = Hs.batch_matches(full)
  +srv : Cl.Client = Hs.import_server_page(fixture_client(), "#chan", matches, False{})
  +page : Hs.DiskPage = Hs.DiskPage{Hs.DiskMatch{"#chan", Cl.Line{Cl.Msg{}, "10:00:00", "old hello", "alice", 0n}, 5n} <> Nil{}, 5n, 1n, True{}}
  +imp : Cl.Client = Hs.import_page(fixture_client(), "hello", page)
  +cur : Hs.HistoryCursor = Hs.cursor_page(Hs.cursor_new("#a"), ["m1", "m2"], Hs.DirLatest{})
  +cur2 : Hs.HistoryCursor = Hs.cursor_page(Hs.cursor_new("#chan"), ["m1", "m2"], Hs.DirLatest{})
  +opaque : String = "opaqueT12345678Z"
  +cur_opaque : Hs.HistoryCursor = Hs.HistoryCursor{"#a", opaque, "m2", Nil{}, 2n}
  +cur_eq : Hs.HistoryCursor = Hs.HistoryCursor{"#a", "a=b", "x=y", Nil{}, 2n}
  +saved100 : Hs.HistoryCursor = Hs.cursor_page(Hs.cursor_new("#a"), saved_ids(100n, 0n), Hs.DirLatest{})
  +tailpage : List<&2, Hs.BatchMsg> = List.append(&2, Hs.BatchMsg, fresh_msgs(99n, 0n), [Hs.BatchMsg{"s99", "", "t", "a"}])
  +fresh100 : List<&2, Hs.BatchMsg> = fresh_msgs(100n, 0n)
  +flood : Hs.ChatBatch = feed_many(101n, 0n, open_chan_batch())
  do IO<Unit>:
    # Query parsing: positive.
    Unit <- E.must_eq("query_plain", query_text(Hs.parse_query("hello world")), "|hello world")
    Unit <- E.must_eq("query_channel", query_text(Hs.parse_query("#birc: hello")), "#birc|hello")
    Unit <- E.must_eq("query_nick", query_text(Hs.parse_query("bob: hi there")), "bob|hi there")
    Unit <- E.must_eq("query_spaces", query_text(Hs.parse_query("  padded  ")), "|padded  ")
    # Query parsing: negative.
    Unit <- E.must_eq("query_empty", query_text(Hs.parse_query("")), "<none>")
    Unit <- E.must_eq("query_blank", query_text(Hs.parse_query("   ")), "<none>")
    Unit <- E.must_eq("query_bare_filter", query_text(Hs.parse_query("#birc:")), "|#birc:")
    Unit <- E.must_eq("query_alias_not_filter", query_text(Hs.parse_query("@#room: hi")), "|@#room: hi")
    Unit <- E.must_eq("query_synthetic_not_filter", query_text(Hs.parse_query("*search*: hi")), "|*search*: hi")
    # Text matching shares the memory-search fuzzy policy.
    Unit <- E.must("match_case_insensitive", Hs.match_text("Hello World", "hello"))
    Unit <- E.must("match_fuzzy", Hs.match_text("Hello World", "hlo"))
    Unit <- E.must("match_miss", Bool.not(Hs.match_text("Hello World", "goodbye")))
    Unit <- E.must("match_empty_query", Bool.not(Hs.match_text("Hello World", "")))
    Unit <- E.must("match_target_all", Hs.match_target("", "#anything"))
    Unit <- E.must("match_target_case", Hs.match_target("#BIRC", "#birc"))
    Unit <- E.must("match_target_miss", Bool.not(Hs.match_target("#a", "#b")))
    # Record matching: endpoint isolation.
    Unit <- E.must_eq("record_hit", record_sig(Hs.match_record(Hs.DiskQuery{"hello", ""}, "a:6667", rec, 7n)), "#chan|7")
    Unit <- E.must_eq("record_wrong_endpoint", record_sig(Hs.match_record(Hs.DiskQuery{"hello", ""}, "b:6667", rec, 0n)), "<none>")
    Unit <- E.must_eq("record_text_miss", record_sig(Hs.match_record(Hs.DiskQuery{"goodbye", ""}, "a:6667", rec, 0n)), "<none>")
    Unit <- E.must_eq("record_target_hit", record_sig(Hs.match_record(Hs.DiskQuery{"hello", "#chan"}, "a:6667", rec, 0n)), "#chan|0")
    Unit <- E.must_eq("record_target_miss", record_sig(Hs.match_record(Hs.DiskQuery{"hello", "#other"}, "a:6667", rec, 0n)), "<none>")
    Unit <- E.must_eq("record_malformed", record_sig(Hs.match_record(Hs.DiskQuery{"hello", ""}, "a:6667", "not a record", 0n)), "<none>")
    Unit <- E.must_eq("record_legacy_rejected", record_sig(Hs.match_record(Hs.DiskQuery{"hello", ""}, "a:6667", "#chan\tMSG\t\thello", 0n)), "<none>")
    # Retention keeps the newest page; the cursor is the oldest offset.
    Unit <- E.must("retain_order", Nat.is_eq(List.length(&2, Hs.DiskMatch, kept), 2n) && Nat.is_eq(Hs.next_cursor(kept), 4n))
    Unit <- E.must("retain_empty_cursor", Nat.is_eq(Hs.next_cursor(Nil{}), 0n))
    # Headers pin the paging contract.
    Unit <- E.must_eq("header_none", Hs.line_text(Hs.render_header("foo", 0n, 0n, True{}, 0n)),
      "no disk history matches for \"foo\"")
    Unit <- E.must_eq("header_one", Hs.line_text(Hs.render_header("foo", 1n, 1n, True{}, 0n)),
      "disk history: 1 match for \"foo\"")
    Unit <- E.must_eq("header_full", Hs.line_text(Hs.render_header("foo", 3n, 3n, True{}, 0n)),
      "disk history: 3 matches for \"foo\"")
    Unit <- E.must_eq("header_partial", Hs.line_text(Hs.render_header("foo", 50n, 137n, False{}, 1234n)),
      "disk history: newest 50 of 137 matches for \"foo\"; /history page 1234 foo for older")
    # H5.3 truncation signal: early EOF is truncation, EOF at 0 is complete.
    Unit <- E.must("eof_truncated", Hs.scan_eof_truncated(5n, True{}))
    Unit <- E.must("eof_complete", Bool.not(Hs.scan_eof_truncated(0n, True{})))
    Unit <- E.must("eof_data", Bool.not(Hs.scan_eof_truncated(5n, False{})))
    # Capability detection.
    Unit <- E.must("cap_offered", Hs.cap_offered(["draft/chathistory"]))
    Unit <- E.must("cap_offered_value", Hs.cap_offered(["sasl", "draft/chathistory=v2"]))
    Unit <- E.must("cap_offered_case", Hs.cap_offered(["DRAFT/CHATHISTORY"]))
    Unit <- E.must("cap_absent", Bool.not(Hs.cap_offered(["sasl", "server-time"])))
    Unit <- E.must("cap_empty", Bool.not(Hs.cap_offered(Nil{})))
    Unit <- E.must_eq("cap_event_ack", cap_tag(Hs.cap_event(":irc.test CAP me ACK :draft/chathistory", "irc.test", "me", True{})), "ack")
    Unit <- E.must_eq("cap_event_nak", cap_tag(Hs.cap_event(":irc.test CAP me NAK :draft/chathistory", "irc.test", "me", True{})), "nak")
    Unit <- E.must_eq("cap_event_ack_value", cap_tag(Hs.cap_event(":irc.test CAP me ACK :sasl draft/chathistory", "irc.test", "me", True{})), "ack")
    Unit <- E.must_eq("cap_event_ls_other", cap_tag(Hs.cap_event(":irc.test CAP me LS :draft/chathistory", "irc.test", "me", True{})), "other")
    Unit <- E.must_eq("cap_event_wrong_cap", cap_tag(Hs.cap_event(":irc.test CAP me ACK :sasl", "irc.test", "me", True{})), "other")
    Unit <- E.must_eq("cap_event_chat_is_other", cap_tag(Hs.cap_event(":a!u@h PRIVMSG #c :CAP ACK draft/chathistory", "irc.test", "me", True{})), "other")
    # H5.4 hostile CAP trust guards.
    Unit <- E.must_eq("cap_event_user_prefix", cap_tag(Hs.cap_event(":alice!u@h CAP me ACK :draft/chathistory", "irc.test", "me", True{})), "other")
    Unit <- E.must_eq("cap_event_dotted_user", cap_tag(Hs.cap_event(":alice.smith!u@h CAP me ACK :draft/chathistory", "irc.test", "me", True{})), "other")
    Unit <- E.must_eq("cap_event_wrong_recipient", cap_tag(Hs.cap_event(":irc.test CAP other ACK :draft/chathistory", "irc.test", "me", True{})), "other")
    # H5c prereg star: the broadcast recipient is accepted only while the
    # CAP/registration owner reports unregistered; any other wrong
    # recipient stays rejected in both phases.
    Unit <- E.must_eq("cap_event_star_prereg", cap_tag(Hs.cap_event(":irc.test CAP * ACK :draft/chathistory", "irc.test", "me", False{})), "ack")
    Unit <- E.must_eq("cap_event_nak_star_prereg", cap_tag(Hs.cap_event(":irc.test CAP * NAK :draft/chathistory", "irc.test", "me", False{})), "nak")
    Unit <- E.must_eq("cap_event_self_prereg", cap_tag(Hs.cap_event(":irc.test CAP me ACK :draft/chathistory", "irc.test", "me", False{})), "ack")
    Unit <- E.must_eq("cap_event_star_postreg", cap_tag(Hs.cap_event(":irc.test CAP * ACK :draft/chathistory", "irc.test", "me", True{})), "other")
    Unit <- E.must_eq("cap_event_wrong_recipient_prereg", cap_tag(Hs.cap_event(":irc.test CAP other ACK :draft/chathistory", "irc.test", "me", False{})), "other")
    Unit <- E.must_eq("cap_event_star_user_prefix", cap_tag(Hs.cap_event(":alice!u@h CAP * ACK :draft/chathistory", "irc.test", "me", False{})), "other")
    # Command builders: positive.
    Unit <- E.must_eq("cmd_latest", maybe_line(Hs.latest(True{}, "#a", 10n)), "CHATHISTORY LATEST #a * 10")
    Unit <- E.must_eq("cmd_before", maybe_line(Hs.before(True{}, "#a", "m1", 25n)), "CHATHISTORY BEFORE #a msgid=m1 25")
    Unit <- E.must_eq("cmd_after", maybe_line(Hs.after(True{}, "bob", "m1", 1n)), "CHATHISTORY AFTER bob msgid=m1 1")
    Unit <- E.must_eq("cmd_around", maybe_line(Hs.around(True{}, "#a", "m1", 100n)), "CHATHISTORY AROUND #a msgid=m1 100")
    Unit <- E.must_eq("cmd_between", maybe_line(Hs.between(True{}, "#a", "m1", "m9", 50n)), "CHATHISTORY BETWEEN #a msgid=m1 msgid=m9 50")
    # H5.5 prefixed and timestamp anchors.
    Unit <- E.must_eq("cmd_before_prefixed", maybe_line(Hs.before(True{}, "#a", "msgid=m1", 25n)), "CHATHISTORY BEFORE #a msgid=m1 25")
    Unit <- E.must_eq("cmd_before_stamp", maybe_line(Hs.before(True{}, "#a", "2026-10-03T10:00:00Z", 25n)),
      "CHATHISTORY BEFORE #a timestamp=2026-10-03T10:00:00Z 25")
    Unit <- E.must_eq("cmd_before_stamp_prefixed", maybe_line(Hs.before(True{}, "#a", "timestamp=2026-10-03T10:00:00Z", 25n)),
      "CHATHISTORY BEFORE #a timestamp=2026-10-03T10:00:00Z 25")
    Unit <- E.must_eq("cmd_after_stamp", maybe_line(Hs.after(True{}, "#a", "timestamp=2026-10-03T10:00:00.123Z", 5n)),
      "CHATHISTORY AFTER #a timestamp=2026-10-03T10:00:00.123Z 5")
    Unit <- E.must_eq("cmd_around_prefixed", maybe_line(Hs.around(True{}, "#a", "msgid=m7", 3n)), "CHATHISTORY AROUND #a msgid=m7 3")
    Unit <- E.must_eq("cmd_between_mixed", maybe_line(Hs.between(True{}, "#a", "m1", "2026-10-03T10:00:00Z", 10n)),
      "CHATHISTORY BETWEEN #a msgid=m1 timestamp=2026-10-03T10:00:00Z 10")
    # Command builders: negative.
    Unit <- E.must_eq("cmd_unnegotiated", maybe_line(Hs.latest(False{}, "#a", 10n)), "<none>")
    Unit <- E.must_eq("cmd_synthetic", maybe_line(Hs.latest(True{}, "*search*", 10n)), "<none>")
    Unit <- E.must_eq("cmd_alias", maybe_line(Hs.latest(True{}, "@#a", 10n)), "<none>")
    Unit <- E.must_eq("cmd_empty_target", maybe_line(Hs.latest(True{}, "", 10n)), "<none>")
    Unit <- E.must_eq("cmd_spaced_target", maybe_line(Hs.latest(True{}, "#a b", 10n)), "<none>")
    Unit <- E.must_eq("cmd_limit_zero", maybe_line(Hs.latest(True{}, "#a", 0n)), "<none>")
    Unit <- E.must_eq("cmd_limit_huge", maybe_line(Hs.latest(True{}, "#a", 101n)), "<none>")
    Unit <- E.must_eq("cmd_bad_anchor", maybe_line(Hs.before(True{}, "#a", "m 1", 10n)), "<none>")
    Unit <- E.must_eq("cmd_empty_anchor", maybe_line(Hs.before(True{}, "#a", "", 10n)), "<none>")
    Unit <- E.must_eq("cmd_long_anchor", maybe_line(Hs.before(True{}, "#a", repeat_char(129n, "m"), 10n)), "<none>")
    Unit <- E.must_eq("cmd_between_bad", maybe_line(Hs.between(True{}, "#a", "m1", "m 2", 10n)), "<none>")
    # H5.5 malformed-ref rejection.
    Unit <- E.must_eq("cmd_unknown_prefix", maybe_line(Hs.before(True{}, "#a", "foo=bar", 10n)), "<none>")
    Unit <- E.must_eq("cmd_bare_msgid_prefix", maybe_line(Hs.before(True{}, "#a", "msgid=", 10n)), "<none>")
    Unit <- E.must_eq("cmd_bare_stamp_prefix", maybe_line(Hs.before(True{}, "#a", "timestamp=", 10n)), "<none>")
    Unit <- E.must_eq("cmd_bad_stamp", maybe_line(Hs.before(True{}, "#a", "timestamp=yesterday", 10n)), "<none>")
    Unit <- E.must_eq("cmd_upper_prefix", maybe_line(Hs.before(True{}, "#a", "MSGID=m1", 10n)), "<none>")
    Unit <- E.must_eq("cmd_between_second_bad", maybe_line(Hs.between(True{}, "#a", "m1", "foo=bar", 10n)), "<none>")
    # H5c full-stamp validation: bare and explicit millisecond positives plus
    # paired malformed refs (bad calendar, truncated shape, non-date text).
    Unit <- E.must_eq("cmd_before_stamp_millis", maybe_line(Hs.before(True{}, "#a", "2026-10-03T10:00:00.123Z", 25n)),
      "CHATHISTORY BEFORE #a timestamp=2026-10-03T10:00:00.123Z 25")
    Unit <- E.must_eq("cmd_explicit_stamp_millis", maybe_line(Hs.before(True{}, "#a", "timestamp=2026-10-03T10:00:00.123Z", 10n)),
      "CHATHISTORY BEFORE #a timestamp=2026-10-03T10:00:00.123Z 10")
    Unit <- E.must_eq("cmd_before_stamp_bad_month", maybe_line(Hs.before(True{}, "#a", "2026-13-03T10:00:00Z", 10n)), "<none>")
    Unit <- E.must_eq("cmd_before_stamp_truncated", maybe_line(Hs.before(True{}, "#a", "2026-10-03T10:00Z", 10n)), "<none>")
    Unit <- E.must_eq("cmd_explicit_stamp_bad_day", maybe_line(Hs.before(True{}, "#a", "timestamp=2026-02-30T10:00:00Z", 10n)), "<none>")
    Unit <- E.must_eq("cmd_explicit_stamp_opaque", maybe_line(Hs.before(True{}, "#a", "timestamp=opaqueT12345678Z", 10n)), "<none>")
    Unit <- E.must_eq("cmd_bare_opaque_stamp_rejected", maybe_line(Hs.before(True{}, "#a", "opaqueT12345678Z", 10n)), "<none>")
    # H5.8 explicit msgid values may carry `=`; bare user `=` stays rejected.
    Unit <- E.must_eq("cmd_explicit_msgid_equals", maybe_line(Hs.before(True{}, "#a", "msgid=a=b", 10n)),
      "CHATHISTORY BEFORE #a msgid=a=b 10")
    Unit <- E.must_eq("cmd_bare_equals_rejected", maybe_line(Hs.before(True{}, "#a", "a=b", 10n)), "<none>")
    Unit <- E.must_eq("cmd_around_stamp_prefixed", maybe_line(Hs.around(True{}, "#a", "timestamp=2026-10-03T10:00:00Z", 5n)),
      "CHATHISTORY AROUND #a timestamp=2026-10-03T10:00:00Z 5")
    # Batch open: positive and negative.
    Unit <- E.must_eq("batch_open", open_ref(Hs.batch_open(":irc.test BATCH +abc chathistory #chan", "irc.test")), "abc|#chan")
    Unit <- E.must_eq("batch_open_case", open_ref(Hs.batch_open(":irc.test batch +abc Chathistory #chan", "irc.test")), "abc|#chan")
    Unit <- E.must_eq("batch_open_query", open_ref(Hs.batch_open(":irc.test BATCH +q chathistory bob", "irc.test")), "q|bob")
    Unit <- E.must_eq("batch_open_wrong_kind", open_ref(Hs.batch_open(":irc.test BATCH +abc netsplit #chan", "irc.test")), "<none>")
    Unit <- E.must_eq("batch_open_no_plus", open_ref(Hs.batch_open(":irc.test BATCH abc chathistory #chan", "irc.test")), "<none>")
    Unit <- E.must_eq("batch_open_bad_target", open_ref(Hs.batch_open(":irc.test BATCH +abc chathistory *search*", "irc.test")), "<none>")
    Unit <- E.must_eq("batch_open_extra", open_ref(Hs.batch_open(":irc.test BATCH +abc chathistory #chan extra", "irc.test")), "<none>")
    Unit <- E.must_eq("batch_open_chat", open_ref(Hs.batch_open(":a!u@h PRIVMSG #c :BATCH +abc chathistory #c", "irc.test")), "<none>")
    # H5.6 hostile open guards: forged user BATCH opens never collect.
    Unit <- E.must_eq("batch_open_user_prefix", open_ref(Hs.batch_open(":alice!u@h BATCH +abc chathistory #chan", "irc.test")), "<none>")
    Unit <- E.must_eq("batch_open_dotted_user", open_ref(Hs.batch_open(":alice.smith!u@h BATCH +abc chathistory #chan", "irc.test")), "<none>")
    # Batch lines: collection, formatting, and rejection.
    Unit <- E.must("batch_done", Hs.batch_done(full))
    Unit <- E.must("batch_count", Nat.is_eq(batch_count(full), 2n))
    Unit <- E.must_eq("batch_first", batch_first_text(full), "m1|10:00:00|<alice> hello|alice")
    # H5.1 batch-tag binding: hostile/valid guards.
    Unit <- E.must("batch_needs_tag", Nat.is_eq(batch_count(Hs.batch_line(open_chan_batch(), "me",
      "@msgid=m9 :x!u@h PRIVMSG #chan :nope")), 0n))
    Unit <- E.must("batch_wrong_tag", Nat.is_eq(batch_count(Hs.batch_line(open_chan_batch(), "me",
      "@batch=zzz;msgid=m9 :x!u@h PRIVMSG #chan :nope")), 0n))
    Unit <- E.must("batch_live_ignored", Nat.is_eq(batch_count(Hs.batch_line(open_chan_batch(), "me",
      ":x!u@h PRIVMSG #chan :live")), 0n))
    Unit <- E.must("batch_right_tag", Nat.is_eq(batch_count(Hs.batch_line(open_chan_batch(), "me",
      "@batch=abc;msgid=m9 :x!u@h PRIVMSG #chan :ok")), 1n))
    Unit <- E.must("batch_foreign_target", Nat.is_eq(batch_count(Hs.batch_line(open_chan_batch(), "me",
      "@batch=abc;msgid=m9 :x!u@h PRIVMSG #other :nope")), 0n))
    Unit <- E.must("batch_no_msgid", Nat.is_eq(batch_count(Hs.batch_line(open_chan_batch(), "me",
      "@batch=abc :x!u@h PRIVMSG #chan :nope")), 0n))
    Unit <- E.must("batch_join_ignored", Nat.is_eq(batch_count(Hs.batch_line(open_chan_batch(), "me",
      "@batch=abc;msgid=m9 :x!u@h JOIN #chan")), 0n))
    Unit <- E.must_eq("batch_action", batch_first_text(Hs.batch_line(open_chan_batch(), "me",
      "@batch=abc;msgid=m7 :alice!u@h PRIVMSG #chan :" ++ SCon{Chr{1}, "ACTION waves" ++ soh()})), "m7||* alice waves|alice")
    Unit <- E.must("batch_query_self_target", Nat.is_eq(batch_count(
      Hs.batch_line(open_query_batch(), "me", "@batch=q;msgid=m1 :bob!u@h PRIVMSG me :hi")), 1n))
    # H5.6 private sender-vs-subject: requested bob rejects charlie->me.
    Unit <- E.must("batch_query_own_side", Nat.is_eq(batch_count(
      Hs.batch_line(open_query_batch(), "me", "@batch=q;msgid=m2 :me!u@h PRIVMSG bob :yo")), 1n))
    Unit <- E.must("batch_query_third_party", Nat.is_eq(batch_count(
      Hs.batch_line(open_query_batch(), "me", "@batch=q;msgid=m9 :charlie!u@h PRIVMSG me :hi")), 0n))
    Unit <- E.must("batch_query_misdirected", Nat.is_eq(batch_count(
      Hs.batch_line(open_query_batch(), "me", "@batch=q;msgid=m9 :bob!u@h PRIVMSG charlie :hi")), 0n))
    Unit <- E.must_eq("batch_idle_stable", batch_tag(Hs.batch_line(Hs.ChatIdle{}, "me", batch_msg(1n))), "idle")
    Unit <- E.must("batch_cap_count", Nat.is_eq(batch_count(flood), 100n))
    Unit <- E.must("batch_cap_overflow", Hs.batch_overflow(flood))
    # Batch close: exact ref match only.
    Unit <- E.must("close_wrong_ref", Bool.not(Hs.batch_done(Hs.batch_close(open_chan_batch(), ":irc.test BATCH -other", "irc.test"))))
    Unit <- E.must_eq("close_idle", batch_tag(Hs.batch_close(Hs.ChatIdle{}, ":irc.test BATCH -abc", "irc.test")), "idle")
    Unit <- E.must("close_chat_ignored", Bool.not(Hs.batch_done(Hs.batch_close(open_chan_batch(),
      ":a!u@h PRIVMSG #c :BATCH -abc", "irc.test"))))
    # H5.6 hostile/valid close guards.
    Unit <- E.must("close_user_prefix", Bool.not(Hs.batch_done(Hs.batch_close(open_chan_batch(),
      ":alice!u@h BATCH -abc", "irc.test"))))
    Unit <- E.must("close_valid", Hs.batch_done(Hs.batch_close(open_chan_batch(), ":irc.test BATCH -abc", "irc.test")))
    # Server matches and import.
    Unit <- E.must("server_match_count", Nat.is_eq(List.length(&2, Hs.ServerMatch, matches), 2n))
    Unit <- E.must("server_collecting_empty", Nat.is_eq(List.length(&2, Hs.ServerMatch, Hs.batch_matches(open_chan_batch())), 0n))
    Unit <- E.must_eq("server_oldest", Hs.server_oldest(matches), "m1")
    Unit <- E.must_eq("server_newest", Hs.server_newest(matches), "m2")
    Unit <- E.must("server_import_focus", String.eq(Cl.active_buf_name(srv), "*search*"))
    Unit <- E.must("server_import_checkpoint", Nat.is_eq(Cl.log_seq_of(srv), Cl.log_seq_of(fixture_client())))
    Unit <- E.must("server_import_nosave", String.is_empty(Hist.extract_new_history_for("irc.test:6697", srv, srv)))
    Unit <- E.must("server_header_present", String.starts_with(search_texts(srv), "server history: 2 messages for #chan (m1..m2)"))
    # Disk import is checkpoint-neutral and focuses *search*.
    Unit <- E.must("disk_import_focus", String.eq(Cl.active_buf_name(imp), "*search*"))
    Unit <- E.must("disk_import_checkpoint", Nat.is_eq(Cl.log_seq_of(imp), Cl.log_seq_of(fixture_client())))
    Unit <- E.must("disk_import_nosave", String.is_empty(Hist.extract_new_history_for("irc.test:6697", imp, imp)))
    Unit <- E.must_eq("disk_import_text", search_texts(imp),
      "disk history: 1 match for \"hello\"|[#chan] old hello|")
    # Cursor: dedupe, bounds, and fetch selection.
    Unit <- E.must("cursor_seen", Hs.cursor_seen(cur, "m1") && Bool.not(Hs.cursor_seen(cur, "m9")))
    Unit <- E.must_eq("cursor_fetch_older", maybe_line(Hs.fetch_older(cur, True{}, 10n)), "CHATHISTORY BEFORE #a msgid=m1 10")
    Unit <- E.must_eq("cursor_fetch_newer", maybe_line(Hs.fetch_newer(cur, True{}, 10n)), "CHATHISTORY AFTER #a msgid=m2 10")
    Unit <- E.must_eq("cursor_fetch_initial", maybe_line(Hs.fetch_older(Hs.cursor_new("#a"), True{}, 10n)),
      "CHATHISTORY LATEST #a * 10")
    Unit <- E.must_eq("cursor_fetch_newer_fresh", maybe_line(Hs.fetch_newer(Hs.cursor_new("#a"), True{}, 10n)), "<none>")
    Unit <- E.must_eq("cursor_fetch_gated", maybe_line(Hs.fetch_older(cur, False{}, 10n)), "<none>")
    Unit <- E.must_eq("cursor_dup_stable", cursor_sig(Hs.cursor_page(cur, ["m1"], Hs.DirLatest{})), "m1|m2|2|2")
    # H5.2 backward/forward cursor guards: direction/page order, never lexical.
    Unit <- E.must_eq("cursor_before_moves_oldest", cursor_sig(Hs.cursor_page(cur, ["m0a", "m0b"], Hs.DirBefore{})), "m0a|m2|4|4")
    Unit <- E.must_eq("cursor_after_moves_newest", cursor_sig(Hs.cursor_page(cur, ["m3", "m4"], Hs.DirAfter{})), "m1|m4|4|4")
    Unit <- E.must_eq("cursor_before_page_order", cursor_sig(Hs.cursor_page(Hs.cursor_new("#a"), ["zeta", "alpha"], Hs.DirBefore{})), "zeta||2|2")
    Unit <- E.must_eq("cursor_after_page_order", cursor_sig(Hs.cursor_page(Hs.cursor_new("#a"), ["zeta", "alpha"], Hs.DirAfter{})), "|alpha|2|2")
    Unit <- E.must_eq("cursor_latest_sets_both", cursor_sig(Hs.cursor_page(Hs.cursor_new("#a"), ["m1", "m2"], Hs.DirLatest{})), "m1|m2|2|2")
    Unit <- E.must_eq("cursor_empty_page", cursor_sig(Hs.cursor_page(cur, Nil{}, Hs.DirBefore{})), "m1|m2|2|2")
    Unit <- E.must_eq("cursor_dup_page", cursor_sig(Hs.cursor_page(cur2, ["m1", "m2"], Hs.DirAfter{})), "m1|m2|2|2")
    Unit <- E.must_eq("cursor_page_dup_noted_once", cursor_sig(Hs.cursor_page(Hs.cursor_new("#a"), ["m9", "m9"], Hs.DirLatest{})), "m9|m9|1|1")
    Unit <- E.must("cursor_filter_unseen", Nat.is_eq(List.length(&2, Hs.BatchMsg,
      Hs.filter_unseen(Hs.cursor_page(Hs.cursor_new("#chan"), ["x1"], Hs.DirLatest{}), Hs.batch_messages(full))), 2n))
    Unit <- E.must("cursor_filter_seen", Nat.is_eq(List.length(&2, Hs.BatchMsg,
      Hs.filter_unseen(cur2, Hs.batch_messages(full))), 0n))
    # H5.7 within-batch dedup.
    Unit <- E.must("filter_dup_one", Nat.is_eq(List.length(&2, Hs.BatchMsg,
      Hs.filter_unseen(Hs.cursor_new("#a"), [Hs.BatchMsg{"m1", "", "t", "a"}, Hs.BatchMsg{"m1", "", "t", "a"}])), 1n))
    Unit <- E.must("filter_two_kept", Nat.is_eq(List.length(&2, Hs.BatchMsg,
      Hs.filter_unseen(Hs.cursor_new("#a"), [Hs.BatchMsg{"m1", "", "t", "a"}, Hs.BatchMsg{"m2", "", "t", "a"}])), 2n))
    Unit <- E.must("filter_seen_prefix_dup", Nat.is_eq(List.length(&2, Hs.BatchMsg,
      Hs.filter_unseen(Hs.cursor_page(Hs.cursor_new("#a"), ["m1"], Hs.DirLatest{}),
        [Hs.BatchMsg{"m1", "", "t", "a"}, Hs.BatchMsg{"m1", "", "t", "a"}])), 0n))
    # H5.8 known-cursor fetch pins opaque ids as msgids, never timestamps.
    Unit <- E.must_eq("fetch_older_opaque_stamp", maybe_line(Hs.fetch_older(cur_opaque, True{}, 10n)),
      "CHATHISTORY BEFORE #a msgid=opaqueT12345678Z 10")
    Unit <- E.must_eq("fetch_older_opaque_equals", maybe_line(Hs.fetch_older(cur_eq, True{}, 10n)),
      "CHATHISTORY BEFORE #a msgid=a=b 10")
    Unit <- E.must_eq("fetch_newer_opaque_equals", maybe_line(Hs.fetch_newer(cur_eq, True{}, 10n)),
      "CHATHISTORY AFTER #a msgid=x=y 10")
    # H5y saved-tail reimport: original membership survives a full fresh page.
    Unit <- E.must("filter_saved_tail_kept_out", Nat.is_eq(List.length(&2, Hs.BatchMsg,
      Hs.filter_unseen(saved100, tailpage)), 99n))
    Unit <- E.must("filter_100fresh_all_kept", Nat.is_eq(List.length(&2, Hs.BatchMsg,
      Hs.filter_unseen(saved100, fresh100)), 100n))
    Unit <- E.must("filter_cap_tail_small", Nat.is_eq(List.length(&2, Hs.BatchMsg,
      Hs.filter_unseen_cap(Hs.HistoryCursor{"#a", "", "", ["s0", "s1"], 2n},
        [Hs.BatchMsg{"f0", "", "t", "a"}, Hs.BatchMsg{"f1", "", "t", "a"}, Hs.BatchMsg{"s0", "", "t", "a"}], 2n)), 2n))
    # Request parsing.
    Unit <- E.must_eq("req_search", request_tag(Hs.parse_request("search hello")), "search:|hello")
    Unit <- E.must_eq("req_search_target", request_tag(Hs.parse_request("search #a: hello")), "search:#a|hello")
    Unit <- E.must_eq("req_page", request_tag(Hs.parse_request("page 42 hello")), "page:42:|hello")
    Unit <- E.must_eq("req_latest", request_tag(Hs.parse_request("latest #a")), "latest:#a:50")
    Unit <- E.must_eq("req_latest_limit", request_tag(Hs.parse_request("latest #a 7")), "latest:#a:7")
    Unit <- E.must_eq("req_before", request_tag(Hs.parse_request("before #a m1 9")), "before:#a:m1:9")
    Unit <- E.must_eq("req_after", request_tag(Hs.parse_request("AFTER #a m1")), "after:#a:m1:50")
    Unit <- E.must_eq("req_around", request_tag(Hs.parse_request("around #a m1 3")), "around:#a:m1:3")
    Unit <- E.must_eq("req_between", request_tag(Hs.parse_request("between #a m1 m2")), "between:#a:m1:m2:50")
    Unit <- E.must_eq("req_empty", request_tag(Hs.parse_request("")), "usage")
    Unit <- E.must_eq("req_bogus", request_tag(Hs.parse_request("frobnicate x")), "usage")
    Unit <- E.must_eq("req_search_empty", request_tag(Hs.parse_request("search   ")), "usage")
    Unit <- E.must_eq("req_page_nocursor", request_tag(Hs.parse_request("page nope hello")), "usage")
    Unit <- E.must_eq("req_latest_badlimit", request_tag(Hs.parse_request("latest #a lots")), "usage")
    Unit <- E.must_eq("req_before_short", request_tag(Hs.parse_request("before #a")), "usage")
    Unit <- E.must_eq("req_latest_bare", request_tag(Hs.parse_request("latest")), "usage")
    Unit <- E.must_eq("req_between_short", request_tag(Hs.parse_request("between #a m1")), "usage")
    # Submit adapter: wire output is gated; usage never sends.
    Unit <- E.must_eq("sub_fetch", submitted_outs(fixture_client(), "latest #a 5", True{}), "CHATHISTORY LATEST #a * 5")
    Unit <- E.must_eq("sub_fetch_before", submitted_outs(fixture_client(), "before #a m1 5", True{}), "CHATHISTORY BEFORE #a msgid=m1 5")
    Unit <- E.must_eq("sub_fetch_before_stamp", submitted_outs(fixture_client(), "before #a 2026-10-03T10:00:00Z 5", True{}),
      "CHATHISTORY BEFORE #a timestamp=2026-10-03T10:00:00Z 5")
    Unit <- E.must_eq("sub_fetch_gated", submitted_outs(fixture_client(), "latest #a 5", False{}), "")
    Unit <- E.must("sub_fetch_gated_echo", String.ends_with(submitted_echo(fixture_client(), "latest #a 5", False{}),
      "server history unavailable (draft/chathistory not negotiated)|"))
    Unit <- E.must_eq("sub_fetch_invalid", submitted_outs(fixture_client(), "latest *search* 5", True{}), "")
    Unit <- E.must("sub_usage_echo", String.contains(submitted_echo(fixture_client(), "frobnicate", True{}), "usage: /history search"))
    Unit <- E.must_eq("sub_usage_outs", submitted_outs(fixture_client(), "frobnicate", True{}), "")
    Unit <- E.must("sub_search_live", String.ends_with(submitted_echo(fixture_client(), "search hello", True{}),
      "disk history search runs in the live session|"))
    Unit <- E.must("sub_needs_conn", Hs.history_needs_connection("latest #a")
      && Hs.history_needs_connection("between #a m1 m2")
      && Bool.not(Hs.history_needs_connection("search hello"))
      && Bool.not(Hs.history_needs_connection("page 1 hello"))
      && Bool.not(Hs.history_needs_connection("bogus")))
    # Completion admission: ticket + generation + exact endpoint.
    Unit <- E.must("admit_match", Hs.search_completion_admitted(7n, 7n, 3n, 3n, "a:6667", "a:6667"))
    Unit <- E.must("admit_ticket_stale", Bool.not(Hs.search_completion_admitted(6n, 7n, 3n, 3n, "a:6667", "a:6667")))
    Unit <- E.must("admit_gen_stale", Bool.not(Hs.search_completion_admitted(7n, 7n, 2n, 3n, "a:6667", "a:6667")))
    Unit <- E.must("admit_endpoint_case", Bool.not(Hs.search_completion_admitted(7n, 7n, 3n, 3n, "A:6667", "a:6667")))
    Unit <- E.must("admit_endpoint_moved", Bool.not(Hs.search_completion_admitted(7n, 7n, 3n, 3n, "b:6667", "a:6667")))
    # Private-file admission.
    Unit <- E.must("file_admit_ok", Hs.disk_file_admitted(True{}, True{}, False{}, True{}))
    Unit <- E.must("file_reject_nonregular", Bool.not(Hs.disk_file_admitted(False{}, True{}, False{}, True{})))
    Unit <- E.must("file_reject_foreign", Bool.not(Hs.disk_file_admitted(True{}, False{}, False{}, True{})))
    Unit <- E.must("file_reject_symlink", Bool.not(Hs.disk_file_admitted(True{}, True{}, True{}, True{})))
    Unit <- E.must("file_reject_mode", Bool.not(Hs.disk_file_admitted(True{}, True{}, False{}, False{})))
    # Negotiation reset.
    Unit <- E.must("neg_live", Hs.chat_negotiated(True{}, True{}, True{}))
    Unit <- E.must("neg_no_ack", Bool.not(Hs.chat_negotiated(False{}, True{}, True{})))
    Unit <- E.must("neg_endpoint_moved", Bool.not(Hs.chat_negotiated(True{}, False{}, True{})))
    Unit <- E.must("neg_gen_stale", Bool.not(Hs.chat_negotiated(True{}, True{}, False{})))
    # Disk-IO preference gate.
    Unit <- E.must("disk_allowed", Hs.disk_search_allowed(True{}, "build/x"))
    Unit <- E.must("disk_pref_off", Bool.not(Hs.disk_search_allowed(False{}, "build/x")))
    Unit <- E.must("disk_no_path", Bool.not(Hs.disk_search_allowed(True{}, "")))
    IO.print("history_search=ok")
