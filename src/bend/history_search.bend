# Disk-history search with stateless paging plus IRCv3 draft/chathistory
# server history. Pure policy first; the bounded file scan mirrors
# history.bend (snapshot size bound, 4096-byte chunks, 8192-byte records,
# endpoint isolation, replay of framed records only).
# Results import into *search* through the checkpoint-neutral buffer replace
# used by memory search, so restored rows are never appended again.
# Integration seams (integrator-owned, flagged, not implemented here):
# a Sub.Slash HistoryCmd arm calling submit_history, Session interception
# running search_file/import_page, and CAP-lane negotiation state feeding
# the `negotiated` argument. This module never owns CAP END.
# MERGE POINTS (flagged for the integrator, Session/Net owned):
# checked native open before search_file (disk_file_admitted rule),
# ticket+generation+endpoint completion checks (search_completion_admitted),
# negotiated-flag reset (chat_negotiated), and preference gating
# (disk_search_allowed) ahead of any disk IO.
import Base
import ./buffer.bend as Cl
import ./irc.bend as Irc
import ./client.bend as Feed
import ./history.bend as Hist
import ./frame.bend as Fr
import ./irc_commands.bend as Commands
import ./utc_time.bend as Utc

def PAGE_SIZE() -> Nat:
  50n

def RECORD_MAX() -> Nat:
  8192n

def SCAN_CHUNK() -> Nat:
  4096n

def BATCH_CAP() -> Nat:
  100n

def SEEN_CAP() -> Nat:
  100n

def CAP_NAME() -> String:
  "draft/chathistory"

# ---- shared word scan -------------------------------------------------
# Same Irc.take_until_space scan as Sub.take_word: drop all separators.

def take_word.pair(pair: String & String) -> String & String:
  match pair:
    case (token, rest): (token, Irc.drop_spaces(rest))

def take_word(s: String) -> String & String:
  take_word.pair(Irc.take_until_space(s))

# ---- disk query -------------------------------------------------------
# `#channel: text` or `nick: text` filters one target; anything else
# searches every target. The `@` audience alias is never a filter.

type DiskQuery is Data:
  DiskQuery{text: String, target: String}

def history_target(+t: String) -> Bool:
  Commands.word(t) && Cl.target_wire(t)
    && Bool.not(String.starts_with(t, "@")) && Bool.not(String.is_empty(Cl.target_name(t)))

def stem_of.rev(rev: String) -> String:
  match rev:
    case SCon{_, t}: String.reverse(t)
    case SNil{}: ""

def stem_of(+first: String) -> String:
  stem_of.rev(String.reverse(first))

def target_stem.word(+stem: String) -> String:
  Bool.pick(String, history_target(stem), stem, "")

def target_stem.colon(colon: Bool, +first: String) -> String:
  match colon:
    case False{}: ""
    case True{}: target_stem.word(stem_of(first))

def target_stem(+first: String) -> String:
  target_stem.colon(String.ends_with(first, ":"), first)

def parse_query.plain(ok: Bool, +cleaned: String) -> Maybe<&2, DiskQuery>:
  match ok:
    case True{}: Some{DiskQuery{cleaned, ""}}
    case False{}: None{}

def parse_query.use(use: Bool, +after: String, +stem: String, +cleaned: String) -> Maybe<&2, DiskQuery>:
  match use:
    case True{}: Some{DiskQuery{after, stem}}
    case False{}: parse_query.plain(Bool.not(String.is_empty(cleaned)), cleaned)

def parse_query.target(+first: String, +after: String, +cleaned: String, +stem: String) -> Maybe<&2, DiskQuery>:
  parse_query.use(Bool.not(String.is_empty(stem)) && Bool.not(String.is_empty(after)), after, stem, cleaned)

def parse_query.words(pair: String & String, +cleaned: String) -> Maybe<&2, DiskQuery>:
  match pair:
    case (+first, +after): parse_query.target(first, after, cleaned, target_stem(first))

def parse_query.clean(+cleaned: String) -> Maybe<&2, DiskQuery>:
  parse_query.words(take_word(cleaned), cleaned)

def parse_query(+rest: String) -> Maybe<&2, DiskQuery>:
  parse_query.clean(Irc.drop_spaces(rest))

def match_target(+qt: String, +rt: String) -> Bool:
  String.is_empty(qt) || Irc.ieq(qt, rt)

# Empty queries never match: reuse the memory-search fuzzy matcher so disk
# and memory search share one text policy.
def match_text.empty(empty: Bool, +text: String, +q: String) -> Bool:
  match empty:
    case True{}: False{}
    case False{}: Feed.search_text_matches(text, q)

def match_text(+text: String, +q: String) -> Bool:
  match_text.empty(String.is_empty(q), text, q)

def line_text(+line: Cl.Line) -> String:
  match line:
    case Cl.Line{_, _, +text, _, _}: text

# `at` is the record's byte offset in the snapshot. Appends never move
# older offsets, so a cursor stays valid while the file only grows.
type DiskMatch is Data:
  DiskMatch{target: String, line: Cl.Line, at: Nat}

def match_record.keep(keep: Bool, +target: String, +line: Cl.Line, +at: Nat) -> Maybe<&2, DiskMatch>:
  match keep:
    case True{}: Some{DiskMatch{target, line, at}}
    case False{}: None{}

def match_record.line(+query: DiskQuery, +target: String, +line: Cl.Line, +at: Nat) -> Maybe<&2, DiskMatch>:
  match query:
    case DiskQuery{+text, +qtarget}:
      match_record.keep(match_target(qtarget, target) && match_text(line_text(line), text), target, line, at)

def match_record.entry(+query: DiskQuery, entry: Maybe<&2, Hist.HistEntry>, +at: Nat) -> Maybe<&2, DiskMatch>:
  match entry:
    case None{}: None{}
    case Some{Hist.Entry{+target, +line}}: match_record.line(query, target, line, at)
    case Some{Hist.ServerEntry{+line}}: match_record.line(query, "*server*", line, at)

def match_record(+query: DiskQuery, +endpoint: String, +raw: String, +at: Nat) -> Maybe<&2, DiskMatch>:
  match_record.entry(query, Hist.parse_line_for(endpoint, raw), at)

def format_match(+m: DiskMatch) -> Cl.Line:
  match m:
    case DiskMatch{+target, +line, _}: Feed.format_search_match(target, line)

# ---- paging -----------------------------------------------------------
# The scan keeps the newest PAGE_SIZE matches older than the cursor.
# Cursor 0 with no matches means the window is exhausted.

def retain_evicted(kept: List<&2, DiskMatch>, +hit: DiskMatch) -> List<&2, DiskMatch> & Bool:
  match kept:
    case Nil{}: (hit <> Nil{}, True{})
    case Con{_, t}: (List.append(&2, DiskMatch, t, hit <> Nil{}), True{})

def retain.full(kept: List<&2, DiskMatch>, +hit: DiskMatch, full: Bool) -> List<&2, DiskMatch> & Bool:
  match full:
    case False{}: (List.append(&2, DiskMatch, kept, hit <> Nil{}), False{})
    case True{}: retain_evicted(kept, hit)

def retain(+kept: List<&2, DiskMatch>, +hit: DiskMatch) -> List<&2, DiskMatch> & Bool:
  retain.full(kept, hit, Nat.is_ge(List.length(&2, DiskMatch, kept), PAGE_SIZE()))

def next_cursor.go(xs: List<&2, DiskMatch>, +best: Nat) -> Nat:
  match xs:
    case Nil{}: best
    case Con{DiskMatch{_, _, +at}, t}: next_cursor.go(t, Bool.pick(Nat, Nat.is_lt(at, best), at, best))

def next_cursor(+xs: List<&2, DiskMatch>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{DiskMatch{_, _, +at}, t}: next_cursor.go(t, at)

def match_noun.one(one: Bool, +total: Nat) -> String:
  match one:
    case True{}: "1 match"
    case False{}: Nat.show(total) ++ " matches"

def match_noun(+total: Nat) -> String:
  match_noun.one(Nat.is_eq(total, 1n), total)

def header_line(+text: String) -> Cl.Line:
  Cl.Line{Cl.System{}, "", text, "", 0n}

def render_header.complete(done: Bool, +orig: String, +shown: Nat, +total: Nat, +next: Nat) -> Cl.Line:
  match done:
    case True{}:
      header_line("disk history: " ++ match_noun(total) ++ " for \"" ++ orig ++ "\"")
    case False{}:
      header_line("disk history: newest " ++ Nat.show(shown) ++ " of " ++ Nat.show(total)
        ++ " matches for \"" ++ orig ++ "\"; /history page " ++ Nat.show(next) ++ " " ++ orig ++ " for older")

def render_header.total(zero: Bool, +orig: String, +shown: Nat, +total: Nat, +complete: Bool, +next: Nat) -> Cl.Line:
  match zero:
    case True{}: header_line("no disk history matches for \"" ++ orig ++ "\"")
    case False{}: render_header.complete(complete, orig, shown, total, next)

def render_header(+orig: String, +shown: Nat, +total: Nat, +complete: Bool, +next: Nat) -> Cl.Line:
  render_header.total(Nat.is_eq(total, 0n), orig, shown, total, complete, next)

def format_all(xs: List<&2, DiskMatch>) -> List<&2, Cl.Line>:
  match xs:
    case Nil{}: Nil{}
    case Con{DiskMatch{+target, +line, _}, t}: Feed.format_search_match(target, line) <> format_all(t)

type DiskPage is Data:
  DiskPage{matches: List<&2, DiskMatch>, next: Nat, total: Nat, complete: Bool}

type DiskResult is Data:
  DiskFound{page: DiskPage}
  DiskFailed{diagnostic: String}

# Checkpoint-neutral like memory search: buf_set_lines_at keeps log_seq,
# and *search* is synthetic so results are never appended again.
def import_page.at(+cl: Cl.Client, +bi: Nat, lines: List<&2, Cl.Line>) -> Cl.Client:
  Cl.set_active(Cl.buf_set_lines_at(cl, bi, lines), bi)

def import_page.got(pair: Cl.Client & Maybe<&2, Nat>, +lines: List<&2, Cl.Line>) -> Cl.Client:
  match pair:
    case (+cl2, None{}):
      Feed.search_and_open.full(cl2, Nat.is_eq(Cl.active_of(cl2), 0n))
    case (cl2, Some{+bi}):
      import_page.at(cl2, bi, lines)

def import_page(+cl: Cl.Client, +orig: String, page: DiskPage) -> Cl.Client:
  match page:
    case DiskPage{+matches, +next, +total, +complete}:
      import_page.got(Cl.buf_get(cl, "*search*", False{}, True{}),
        render_header(orig, List.length(&2, DiskMatch, matches), total, complete, next) <> format_all(matches))

# ---- bounded file scan --------------------------------------------------
# Forward-only reads (no seek): every page scans the snapshot once and
# retains the newest matches older than the cursor. State holds at most
# PAGE_SIZE matches plus one 8192-byte record, regardless of file size.
# The unterminated tail is dropped like history load: it may be torn.

type ScanState is Data:
  ScanState{kept: List<&2, DiskMatch>, evicted: Nat, rev: List<&2, U32>, count: Nat, dropping: Bool, pos: Nat, rec_start: Nat}

def scan_initial() -> ScanState:
  ScanState{Nil{}, 0n, Nil{}, 0n, False{}, 0n, 0n}

def scan_record.retained(pair: List<&2, DiskMatch> & Bool, +evicted: Nat) -> List<&2, DiskMatch> & Nat:
  match pair:
    case (+kept2, +dropped): (kept2, Bool.pick(Nat, dropped, 1n+evicted, evicted))

def scan_record.hit(got: Maybe<&2, DiskMatch>, kept: List<&2, DiskMatch>, +evicted: Nat) -> List<&2, DiskMatch> & Nat:
  match got:
    case None{}: (kept, evicted)
    case Some{+hit}: scan_record.retained(retain(kept, hit), evicted)

def scan_record.decoded(+query: DiskQuery, +endpoint: String, kept: List<&2, DiskMatch>, +evicted: Nat, text: Maybe<&2, String>, +start: Nat) -> List<&2, DiskMatch> & Nat:
  match text:
    case None{}: (kept, evicted)
    case Some{+raw}: scan_record.hit(match_record(query, endpoint, raw, start), kept, evicted)

def scan_record.old(older: Bool, +query: DiskQuery, +endpoint: String, kept: List<&2, DiskMatch>, +evicted: Nat, +rev: List<&2, U32>, +start: Nat) -> List<&2, DiskMatch> & Nat:
  match older:
    case False{}: (kept, evicted)
    case True{}: scan_record.decoded(query, endpoint, kept, evicted, Fr.utf8_decode(List.reverse(&2, U32, rev)), start)

def scan_record(+query: DiskQuery, +endpoint: String, +cursor: Nat, kept: List<&2, DiskMatch>, +evicted: Nat, rev: List<&2, U32>, +start: Nat) -> List<&2, DiskMatch> & Nat:
  scan_record.old(Nat.is_lt(start, cursor), query, endpoint, kept, evicted, rev, start)

def scan_newline.done(pair: List<&2, DiskMatch> & Nat, +pos: Nat) -> ScanState:
  match pair:
    case (+kept2, +evicted2): ScanState{kept2, evicted2, Nil{}, 0n, False{}, 1n+pos, 1n+pos}

def scan_newline(+query: DiskQuery, +endpoint: String, +cursor: Nat, kept: List<&2, DiskMatch>, +evicted: Nat, rev: List<&2, U32>, +start: Nat, +pos: Nat) -> ScanState:
  scan_newline.done(scan_record(query, endpoint, cursor, kept, evicted, rev, start), pos)

def scan_store(drop: Bool, kept: List<&2, DiskMatch>, +evicted: Nat, +rev: List<&2, U32>, +count: Nat, +byte: U32, +pos: Nat, +rec_start: Nat) -> ScanState:
  match drop:
    case True{}: ScanState{kept, evicted, Nil{}, 0n, True{}, 1n+pos, rec_start}
    case False{}: ScanState{kept, evicted, byte <> rev, 1n+count, False{}, 1n+pos, rec_start}

def scan_step.newline(+query: DiskQuery, +endpoint: String, +cursor: Nat, kept: List<&2, DiskMatch>, +evicted: Nat, rev: List<&2, U32>, +count: Nat, +dropping: Bool, +pos: Nat, +rec_start: Nat, +byte: U32, nl: Bool) -> ScanState:
  match nl:
    case True{}: scan_newline(query, endpoint, cursor, kept, evicted, rev, rec_start, pos)
    case False{}: scan_store(dropping || Nat.is_ge(count, RECORD_MAX()), kept, evicted, rev, count, byte, pos, rec_start)

def scan_step(+query: DiskQuery, +endpoint: String, +cursor: Nat, state: ScanState, +byte: U32) -> ScanState:
  match state:
    case ScanState{+kept, +evicted, +rev, +count, +dropping, +pos, +rec_start}:
      scan_step.newline(query, endpoint, cursor, kept, evicted, rev, count, dropping, pos, rec_start, byte, U32.is_eq(byte, 10))

def scan_chunk(bytes: List<&2, U32>, state: ScanState, +query: DiskQuery, +endpoint: String, +cursor: Nat) -> ScanState:
  match bytes:
    case Nil{}: state
    case Con{+byte, t}: scan_chunk(t, scan_step(query, endpoint, cursor, state, byte), query, endpoint, cursor)

def search_finish(state: ScanState, f: File) -> IO(DiskResult):
  match state:
    case ScanState{+kept, +evicted, _, _, _, _, _}:
      do IO<DiskResult>:
        Unit <- File.close(f)
        return DiskFound{DiskPage{kept, next_cursor(kept), Nat.add(List.length(&2, DiskMatch, kept), evicted), Nat.is_eq(evicted, 0n)}}

def search_failure(f: File, +stage: String, error: U32 & String) -> IO(DiskResult):
  do IO<DiskResult>:
    Unit <- File.close(f)
    return DiskFailed{Hist.read_failure_text(error, stage)}

# An empty read with bytes still expected means the file shrank under the
# snapshot size: report truncation (restart the search), never partial
# DiskFound success. Only an empty read at remaining 0 is a complete file.
def scan_eof_truncated(+remaining: Nat, empty: Bool) -> Bool:
  empty && Nat.is_gt(remaining, 0n)

def search_loop.truncated(f: File, state: ScanState) -> IO(DiskResult):
  do IO<DiskResult>:
    Unit <- File.close(f)
    return DiskFailed{"history changed; restart search"}

def search_loop.eof(truncated: Bool, f: File, state: ScanState) -> IO(DiskResult):
  match truncated:
    case True{}: search_loop.truncated(f, state)
    case False{}: search_finish(state, f)

def search_loop.empty(empty: Bool, f: File, +bytes: List<&2, U32>, +query: DiskQuery, +endpoint: String, +cursor: Nat, state: ScanState, +remaining: Nat, next: File -> ScanState -> Nat -> IO(DiskResult)) -> IO(DiskResult):
  match empty:
    case True{}: search_loop.eof(scan_eof_truncated(remaining, True{}), f, state)
    case False{}:
      next(f, scan_chunk(bytes, state, query, endpoint, cursor), Nat.sub(remaining, List.length(&2, U32, bytes)))

def search_loop.got(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>, +query: DiskQuery, +endpoint: String, +cursor: Nat, state: ScanState, +remaining: Nat, next: File -> ScanState -> Nat -> IO(DiskResult)) -> IO(DiskResult):
  match pair:
    case (f, Fail{error}): search_failure(f, "read failed; partial matches were discarded", error)
    case (f, Done{+bytes}):
      search_loop.empty(Nat.is_eq(List.length(&2, U32, bytes), 0n), f, bytes, query, endpoint, cursor, state, remaining, next)

def search_loop.read(done: Bool, f: File, +query: DiskQuery, +endpoint: String, +cursor: Nat, state: ScanState, +remaining: Nat, next: File -> ScanState -> Nat -> IO(DiskResult)) -> IO(DiskResult):
  match done:
    case True{}: search_finish(state, f)
    case False{}:
      do IO<DiskResult>:
        pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, U32.from_nat(Cl.clamp_nat(remaining, SCAN_CHUNK())))
        search_loop.got(pair, query, endpoint, cursor, state, remaining, next)

def search_loop(fuel: Nat, f: File, +query: DiskQuery, +endpoint: String, +cursor: Nat, state: ScanState, +remaining: Nat) -> IO(DiskResult):
  match fuel:
    case 0n: search_finish(state, f)
    case 1n+p:
      search_loop.read(Nat.is_eq(remaining, 0n), f, query, endpoint, cursor, state, remaining,
        f2 => st2 => rest => search_loop(p, f2, query, endpoint, cursor, st2, rest))

def search_size.over(moved: Bool, f: File, +size: Nat, +query: DiskQuery, +endpoint: String, +cursor: Nat) -> IO(DiskResult):
  match moved:
    case True{}:
      do IO<DiskResult>:
        Unit <- File.close(f)
        return DiskFailed{"history changed; restart search"}
    case False{}: search_loop(1n+size, f, query, endpoint, cursor, scan_initial(), size)

def search_size(pair: File & Result<&1, &1, U32 & String, U32>, +query: DiskQuery, +endpoint: String, +cursor: Nat) -> IO(DiskResult):
  match pair:
    case (f, Fail{error}): search_failure(f, "size unavailable", error)
    case (f, Done{+size}):
      search_size.over(Nat.is_gt(cursor, U32.to_nat(size)), f, U32.to_nat(size), query, endpoint, cursor)

def search_open.missing(missing: Bool, +code: U32, +msg: String) -> IO(DiskResult):
  match missing:
    case True{}: IO.pure(DiskResult, DiskFound{DiskPage{Nil{}, 0n, 0n, True{}}})
    case False{}: IO.pure(DiskResult, DiskFailed{Hist.read_failure_text((code, msg), "open failed")})

def search_open.failed(error: U32 & String) -> IO(DiskResult):
  match error:
    case (+code, +msg): search_open.missing(U32.is_eq(code, 2), code, msg)

def search_opened(+query: DiskQuery, +endpoint: String, +cursor: Nat, result: Result<&1, &1, U32 & String, File>) -> IO(DiskResult):
  match result:
    case Fail{error}: search_open.failed(error)
    case Done{f}:
      do IO<DiskResult>:
        pair : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
        search_size(pair, query, endpoint, cursor)

# MERGE POINT: bare File.open. The integrator must admit the path through a
# checked native open (O_NOFOLLOW, regular file, euid-owned, mode 0600 per
# disk_file_admitted) before this read; Session must also consult
# disk_search_allowed so disabled history performs no disk IO at all.
def search_file.go(+path: String, +endpoint: String, +query: DiskQuery, +cursor: Nat) -> IO(DiskResult):
  do IO<DiskResult>:
    result : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    search_opened(query, endpoint, cursor, result)

def search_file.pick(disabled: Bool, +path: String, +endpoint: String, +query: DiskQuery, +cursor: Nat) -> IO(DiskResult):
  match disabled:
    case True{}: IO.pure(DiskResult, DiskFound{DiskPage{Nil{}, 0n, 0n, True{}}})
    case False{}: search_file.go(path, endpoint, query, cursor)

# An empty path means history is disabled: report no matches, not an error.
def search_file(+path: String, +endpoint: String, +query: DiskQuery, +cursor: Nat) -> IO(DiskResult):
  search_file.pick(String.is_empty(path), path, endpoint, query, cursor)

# ---- draft/chathistory capability ---------------------------------------
# Detection mirrors the SASL cap check. Negotiation state and CAP END stay
# with the CAP lane; these builders only gate on the given flag.

type CapEvent is Data:
  ChathistoryAck{}
  ChathistoryNak{}
  ChathistoryOther{}

def cap_offered(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}:
      Irc.ieq(h, CAP_NAME()) || String.starts_with(h, CAP_NAME() ++ "=") || cap_offered(t)

def cap_event.nak(nak: Bool) -> CapEvent:
  match nak:
    case True{}: ChathistoryNak{}
    case False{}: ChathistoryOther{}

def cap_event.ack(ack: Bool, +nak: Bool) -> CapEvent:
  match ack:
    case True{}: ChathistoryAck{}
    case False{}: cap_event.nak(nak)

def cap_event.cap(ok: Bool, +m: Irc.Message) -> CapEvent:
  match ok:
    case False{}: ChathistoryOther{}
    case True{}: cap_event.ack(Irc.ieq(Irc.msg_param(m, 1n), "ACK"), Irc.ieq(Irc.msg_param(m, 1n), "NAK"))

# The '*' recipient is the established pre-registration broadcast address.
# Only the single CAP/registration owner knows the phase, so it supplies
# `registered`: an unregistered session may accept '*', a registered one
# must see its own current nick. Any other wrong recipient is rejected in
# both phases — never global wrong-recipient acceptance.
# MERGE POINT: Session passes its JoinPlan.welcomed registration flag
# (owned with the CAP lane); this module never infers phase from traffic.
def cap_recipient_ok(+recipient: String, +self: String, registered: Bool) -> Bool:
  Irc.ieq(recipient, self) || (Bool.not(registered) && String.eq(recipient, "*"))

# Trust: the full source prefix must be server-shaped (Message.nick alone
# loses the !/@ user markers, so a dotted user nick would pass a nick-only
# check) and the first CAP parameter must pass the phase-aware recipient
# gate above. Anything else is ChathistoryOther, never an ACK/NAK.
def cap_event.msg(+m: Irc.Message, +prefix: String, +server: String, +self: String, registered: Bool) -> CapEvent:
  cap_event.cap(Irc.ieq(Irc.msg_command(m), "CAP")
    && Irc.source_is_server(prefix, server)
    && cap_recipient_ok(Irc.msg_param(m, 0n), self, registered)
    && cap_offered(String.split(Irc.msg_param(m, 2n), Chr{32})), m)

def cap_event.parsed(m: Maybe<&2, Irc.Message>, +line: String, +server: String, +self: String, registered: Bool) -> CapEvent:
  match m:
    case None{}: ChathistoryOther{}
    case Some{+msg}: cap_event.msg(msg, Irc.source_prefix(line), server, self, registered)

def cap_event(+line: String, +server: String, +self: String, registered: Bool) -> CapEvent:
  cap_event.parsed(Irc.parse(line), line, server, self, registered)

# ---- chathistory commands -----------------------------------------------
# Reject, never truncate. Limits are 1..100 per request; the server may
# clamp further. Targets are channels or bare nicks, never synthetic tabs
# or the `@` audience alias.

def valid_target(+t: String) -> Bool:
  history_target(t)

# Incoming msgids arrive as bare `msgid` tag values inside batches.
def valid_msgid(+s: String) -> Bool:
  Commands.word(s) && Nat.is_le(String.length(s), 128n)

# ---- chathistory anchor normalization --------------------------------------
# BEFORE/AFTER/AROUND/BETWEEN anchors are always prefixed on the wire:
# `msgid=<id>` or `timestamp=<iso>`. Bare user input defaults to a msgid
# unless it has UTC-stamp shape (contains T, ends Z, long enough that short
# opaque ids never match); a token carrying `=` must use a recognized
# prefix. Timestamps must be full UTC stamps
# (YYYY-MM-DDThh:mm:ss[.frac]Z with calendar range checks) through the
# shared server-time validator; malformed refs are rejected, never
# truncated or sent raw. A bare stamp-shaped token that fails validation
# is rejected too: spell the id explicitly (`msgid=<id>`) instead.

def TIMESTAMP_MIN() -> Nat:
  16n

def looks_timestamp(+s: String) -> Bool:
  String.contains(s, "T") && String.ends_with(s, "Z") && Nat.is_ge(String.length(s), TIMESTAMP_MIN())

def valid_msgid_bare(+s: String) -> Bool:
  Commands.word(s) && Nat.is_le(String.length(s), 128n) && Bool.not(String.contains(s, "="))

def timestamp_parsed(got: Maybe<&2, Utc.Utc>) -> Bool:
  match got:
    case Some{_}: True{}
    case None{}: False{}

def valid_timestamp_bare(+s: String) -> Bool:
  Commands.word(s) && Bool.not(String.contains(s, "=")) && timestamp_parsed(Utc.parse(s))

def anchor_wire.keep(ok: Bool, +token: String) -> Maybe<&2, String>:
  match ok:
    case True{}: Some{token}
    case False{}: None{}

def anchor_wire.bare(+anchor: String, stamped: Bool) -> Maybe<&2, String>:
  match stamped:
    case True{}: anchor_wire.keep(valid_timestamp_bare(anchor), "timestamp=" ++ anchor)
    case False{}: anchor_wire.keep(valid_msgid_bare(anchor), "msgid=" ++ anchor)

def anchor_wire.plain(+anchor: String, has_eq: Bool) -> Maybe<&2, String>:
  match has_eq:
    case True{}: None{}
    case False{}: anchor_wire.bare(anchor, looks_timestamp(anchor))

def anchor_wire.stamped(+anchor: String, is_timestamp: Bool) -> Maybe<&2, String>:
  match is_timestamp:
    case True{}: anchor_wire.keep(valid_timestamp_bare(String.drop(anchor, 10n)), anchor)
    case False{}: anchor_wire.plain(anchor, String.contains(anchor, "="))

def anchor_wire.msgid_tagged(tagged: Bool, +anchor: String) -> Maybe<&2, String>:
  match tagged:
    case True{}: anchor_wire.keep(valid_msgid(String.drop(anchor, 6n)), anchor)
    case False{}: anchor_wire.stamped(anchor, String.starts_with(anchor, "timestamp="))

def anchor_wire(+anchor: String) -> Maybe<&2, String>:
  anchor_wire.msgid_tagged(String.starts_with(anchor, "msgid="), anchor)

def valid_limit(+n: Nat) -> Bool:
  Nat.is_ge(n, 1n) && Nat.is_le(n, 100n)

def latest_line(+target: String, +limit: Nat) -> Maybe<&2, String>:
  Commands.checked(valid_target(target) && valid_limit(limit),
    "CHATHISTORY LATEST " ++ target ++ " * " ++ Nat.show(limit))

def before_line.emit(+target: String, tok: Maybe<&2, String>, +limit: Nat) -> Maybe<&2, String>:
  match tok:
    case None{}: None{}
    case Some{+t}:
      Commands.checked(valid_target(target) && valid_limit(limit),
        "CHATHISTORY BEFORE " ++ target ++ " " ++ t ++ " " ++ Nat.show(limit))

def before_line(+target: String, +anchor: String, +limit: Nat) -> Maybe<&2, String>:
  before_line.emit(target, anchor_wire(anchor), limit)

def after_line.emit(+target: String, tok: Maybe<&2, String>, +limit: Nat) -> Maybe<&2, String>:
  match tok:
    case None{}: None{}
    case Some{+t}:
      Commands.checked(valid_target(target) && valid_limit(limit),
        "CHATHISTORY AFTER " ++ target ++ " " ++ t ++ " " ++ Nat.show(limit))

def after_line(+target: String, +anchor: String, +limit: Nat) -> Maybe<&2, String>:
  after_line.emit(target, anchor_wire(anchor), limit)

def around_line.emit(+target: String, tok: Maybe<&2, String>, +limit: Nat) -> Maybe<&2, String>:
  match tok:
    case None{}: None{}
    case Some{+t}:
      Commands.checked(valid_target(target) && valid_limit(limit),
        "CHATHISTORY AROUND " ++ target ++ " " ++ t ++ " " ++ Nat.show(limit))

def around_line(+target: String, +anchor: String, +limit: Nat) -> Maybe<&2, String>:
  around_line.emit(target, anchor_wire(anchor), limit)

def between_line.second(+target: String, +a: String, tok: Maybe<&2, String>, +limit: Nat) -> Maybe<&2, String>:
  match tok:
    case None{}: None{}
    case Some{+bt}:
      Commands.checked(valid_target(target) && valid_limit(limit),
        "CHATHISTORY BETWEEN " ++ target ++ " " ++ a ++ " " ++ bt ++ " " ++ Nat.show(limit))

def between_line.first(+target: String, tok: Maybe<&2, String>, +b: String, +limit: Nat) -> Maybe<&2, String>:
  match tok:
    case None{}: None{}
    case Some{+at}: between_line.second(target, at, anchor_wire(b), limit)

def between_line(+target: String, +a: String, +b: String, +limit: Nat) -> Maybe<&2, String>:
  between_line.first(target, anchor_wire(a), b, limit)

def gate.issued(ok: Bool, line: Maybe<&2, String>) -> Maybe<&2, String>:
  match ok:
    case True{}: line
    case False{}: None{}

# Gated builders: no negotiated capability, no wire output.
def latest(negotiated: Bool, +target: String, +limit: Nat) -> Maybe<&2, String>:
  gate.issued(negotiated, latest_line(target, limit))

def before(negotiated: Bool, +target: String, +anchor: String, +limit: Nat) -> Maybe<&2, String>:
  gate.issued(negotiated, before_line(target, anchor, limit))

def after(negotiated: Bool, +target: String, +anchor: String, +limit: Nat) -> Maybe<&2, String>:
  gate.issued(negotiated, after_line(target, anchor, limit))

def around(negotiated: Bool, +target: String, +anchor: String, +limit: Nat) -> Maybe<&2, String>:
  gate.issued(negotiated, around_line(target, anchor, limit))

def between(negotiated: Bool, +target: String, +a: String, +b: String, +limit: Nat) -> Maybe<&2, String>:
  gate.issued(negotiated, between_line(target, a, b, limit))

# ---- chathistory batch parsing ------------------------------------------
# BATCH +ref chathistory <target> ... BATCH -ref. Only PRIVMSG/NOTICE with
# a msgid and a `batch` tag equal to the collect ref reach the results;
# foreign targets, missing msgids, other-batch/live traffic, and other
# commands are ignored. Stamps are UTC clocks from the wire; the live
# Clock.line_stamps layer normalizes them at import (integrator seam).

type BatchMsg is Data:
  BatchMsg{msgid: String, stamp: String, text: String, author: String}

type ChatBatch is Data:
  ChatIdle{}
  ChatCollect{ref: String, target: String, channel: Bool, messages: List<&2, BatchMsg>, overflow: Bool}
  ChatDone{ref: String, target: String, messages: List<&2, BatchMsg>, overflow: Bool}

def tag_seg.got(pair: String & String) -> String:
  match pair:
    case (+tok, _): tok

def tag_seg(+line: String) -> String:
  tag_seg.got(Irc.take_until_space(String.drop(line, 1n)))

def tag_value.tags(tags: List<&2, String>, +key: String) -> String:
  match tags:
    case Nil{}: ""
    case Con{+h, t}:
      Bool.pick(String, String.starts_with(h, key ++ "="),
        String.drop(h, Nat.add(String.length(key), 1n)), tag_value.tags(t, key))

def tag_value.seg(+line: String, +key: String, tagged: Bool) -> String:
  match tagged:
    case False{}: ""
    case True{}: tag_value.tags(String.split(tag_seg(line), Chr{59}), key)

def tag_value(+line: String, +key: String) -> String:
  tag_value.seg(line, key, String.starts_with(line, "@"))

def bare_ref.head(plus: Bool, +t: String) -> String:
  match plus:
    case True{}: t
    case False{}: ""

def bare_ref(+ref: String) -> String:
  match ref:
    case SCon{+h, +t}: bare_ref.head(Char.is_eq(h, Chr{43}), t)
    case SNil{}: ""

def batch_open.bare(ok: Bool, +bare: String, +target: String) -> Maybe<&2, ChatBatch>:
  match ok:
    case False{}: None{}
    case True{}: Some{ChatCollect{bare, target, Irc.starts_channel(target), Nil{}, False{}}}

def batch_open.kind(ok: Bool, +ref: String, +target: String) -> Maybe<&2, ChatBatch>:
  match ok:
    case False{}: None{}
    case True{}:
      +bare = bare_ref(ref)
      batch_open.bare(Commands.word(bare) && Nat.is_le(String.length(bare), 64n), bare, target)

def batch_open.arity(ok: Bool, +m: Irc.Message) -> Maybe<&2, ChatBatch>:
  match ok:
    case False{}: None{}
    case True{}:
      batch_open.kind(Irc.ieq(Irc.msg_param(m, 1n), "chathistory") && valid_target(Irc.msg_param(m, 2n)),
        Irc.msg_param(m, 0n), Irc.msg_param(m, 2n))

# Trust: only a server-shaped full source prefix opens a batch. A forged
# user BATCH open must never start collection.
def batch_open.msg(+m: Irc.Message, +line: String, +server: String) -> Maybe<&2, ChatBatch>:
  batch_open.arity(Irc.ieq(Irc.msg_command(m), "BATCH")
    && Nat.is_eq(List.length(&2, String, Irc.msg_params(m)), 3n)
    && Irc.source_is_server(Irc.source_prefix(line), server), m)

def batch_open.parsed(m: Maybe<&2, Irc.Message>, +line: String, +server: String) -> Maybe<&2, ChatBatch>:
  match m:
    case None{}: None{}
    case Some{+msg}: batch_open.msg(msg, line, server)

def batch_open(+line: String, +server: String) -> Maybe<&2, ChatBatch>:
  batch_open.parsed(Irc.parse(line), line, server)

# Channel batches accept any sender to the channel. Private batches pair one
# subject with self: requested `bob` accepts bob->me and me->bob only, so a
# third party writing to me never lands in bob's history.
def batch_target_ok.private(+p0: String, +target: String, +self: String, +nick: String) -> Bool:
  (Irc.ieq(nick, target) && Irc.ieq(p0, self)) || (Irc.ieq(nick, self) && Irc.ieq(p0, target))

def batch_target_ok(channel: Bool, +p0: String, +target: String, +self: String, +nick: String) -> Bool:
  match channel:
    case True{}: Irc.ieq(p0, target)
    case False{}: batch_target_ok.private(p0, target, self, nick)

def batch_body.action(action: Bool, +nick: String, +body: String) -> String:
  match action:
    case True{}: Feed.fmt_action(nick, Feed.action_text(body))
    case False{}: Feed.fmt_msg(nick, body)

def batch_collect.full(full: Bool, +ref: String, +target: String, +channel: Bool, messages: List<&2, BatchMsg>, +overflow: Bool, +mid: String, +stamp: String, +body: String, +author: String) -> ChatBatch:
  match full:
    case True{}: ChatCollect{ref, target, channel, messages, True{}}
    case False{}:
      ChatCollect{ref, target, channel, List.append(&2, BatchMsg, messages, BatchMsg{mid, stamp, body, author} <> Nil{}), overflow}

def batch_collect.decide(ok: Bool, +full: Bool, +ref: String, +target: String, +channel: Bool, messages: List<&2, BatchMsg>, +overflow: Bool, +mid: String, +stamp: String, +body: String, +author: String) -> ChatBatch:
  match ok:
    case True{}: batch_collect.full(full, ref, target, channel, messages, overflow, mid, stamp, body, author)
    case False{}: ChatCollect{ref, target, channel, messages, overflow}

def batch_collect.msg(+ref: String, +target: String, +channel: Bool, +messages: List<&2, BatchMsg>, +overflow: Bool, +self: String, +line: String, +msg: Irc.Message) -> ChatBatch:
  +mid = tag_value(line, "msgid")
  +nick = Feed.msg_nick(msg)
  +raw = Irc.msg_param(msg, 1n)
  batch_collect.decide(
    (Irc.ieq(Irc.msg_command(msg), "PRIVMSG") || Irc.ieq(Irc.msg_command(msg), "NOTICE"))
      && batch_target_ok(channel, Irc.msg_param(msg, 0n), target, self, nick)
      && valid_msgid(mid)
      && Bool.not(String.is_empty(ref))
      && String.eq(tag_value(line, "batch"), ref),
    Nat.is_ge(List.length(&2, BatchMsg, messages), BATCH_CAP()),
    ref, target, channel, messages, overflow, mid,
    Irc.sanitize_in(Irc.msg_time(msg)),
    Irc.sanitize_in(batch_body.action(Feed.is_action(raw), nick, raw)),
    Irc.sanitize_in(nick))

def batch_collect.parsed(+ref: String, +target: String, +channel: Bool, messages: List<&2, BatchMsg>, +overflow: Bool, +self: String, +line: String, m: Maybe<&2, Irc.Message>) -> ChatBatch:
  match m:
    case None{}: ChatCollect{ref, target, channel, messages, overflow}
    case Some{+msg}: batch_collect.msg(ref, target, channel, messages, overflow, self, line, msg)

def batch_collect(+ref: String, +target: String, +channel: Bool, messages: List<&2, BatchMsg>, +overflow: Bool, +self: String, +line: String) -> ChatBatch:
  batch_collect.parsed(ref, target, channel, messages, overflow, self, line, Irc.parse(line))

def batch_line(batch: ChatBatch, +self: String, +line: String) -> ChatBatch:
  match batch:
    case ChatCollect{+ref, +target, +channel, +messages, +overflow}:
      batch_collect(ref, target, channel, messages, overflow, self, line)
    case _: batch

def batch_close.done(done: Bool, +ref: String, +target: String, +channel: Bool, messages: List<&2, BatchMsg>, +overflow: Bool) -> ChatBatch:
  match done:
    case True{}: ChatDone{ref, target, messages, overflow}
    case False{}: ChatCollect{ref, target, channel, messages, overflow}

# Trust: only a server-shaped full source prefix closes a batch. A forged
# user BATCH close must never complete collection early.
def batch_close.msg(+ref: String, +target: String, +channel: Bool, messages: List<&2, BatchMsg>, +overflow: Bool, +msg: Irc.Message, +line: String, +server: String) -> ChatBatch:
  batch_close.done(Irc.ieq(Irc.msg_command(msg), "BATCH")
    && Nat.is_eq(List.length(&2, String, Irc.msg_params(msg)), 1n)
    && String.eq(Irc.msg_param(msg, 0n), "-" ++ ref)
    && Irc.source_is_server(Irc.source_prefix(line), server),
    ref, target, channel, messages, overflow)

def batch_close.parsed(+ref: String, +target: String, +channel: Bool, messages: List<&2, BatchMsg>, +overflow: Bool, m: Maybe<&2, Irc.Message>, +line: String, +server: String) -> ChatBatch:
  match m:
    case None{}: ChatCollect{ref, target, channel, messages, overflow}
    case Some{+msg}: batch_close.msg(ref, target, channel, messages, overflow, msg, line, server)

def batch_close.expect(+ref: String, +target: String, +channel: Bool, messages: List<&2, BatchMsg>, +overflow: Bool, +line: String, +server: String) -> ChatBatch:
  batch_close.parsed(ref, target, channel, messages, overflow, Irc.parse(line), line, server)

def batch_close(batch: ChatBatch, +line: String, +server: String) -> ChatBatch:
  match batch:
    case ChatCollect{+ref, +target, +channel, +messages, +overflow}:
      batch_close.expect(ref, target, channel, messages, overflow, line, server)
    case _: batch

def batch_messages(batch: ChatBatch) -> List<&2, BatchMsg>:
  match batch:
    case ChatCollect{_, _, _, +messages, _}: messages
    case ChatDone{_, _, +messages, _}: messages
    case ChatIdle{}: Nil{}

def batch_done(batch: ChatBatch) -> Bool:
  match batch:
    case ChatDone{_, _, _, _}: True{}
    case _: False{}

def batch_msgid(+m: BatchMsg) -> String:
  match m:
    case BatchMsg{+msgid, _, _, _}: msgid

# ---- server results -------------------------------------------------------
# Server matches carry msgids, not file offsets; paging reissues BEFORE
# against the oldest msgid. Import is checkpoint-neutral like disk search.

type ServerMatch is Data:
  ServerMatch{target: String, line: Cl.Line, msgid: String}

def batch_matches.go(msgs: List<&2, BatchMsg>, +target: String) -> List<&2, ServerMatch>:
  match msgs:
    case Nil{}: Nil{}
    case Con{BatchMsg{+msgid, +stamp, +text, +author}, t}:
      ServerMatch{target, Cl.Line{Cl.Msg{}, stamp, text, author, 0n}, msgid} <> batch_matches.go(t, target)

def batch_matches(batch: ChatBatch) -> List<&2, ServerMatch>:
  match batch:
    case ChatDone{_, +target, +messages, _}: batch_matches.go(messages, target)
    case _: Nil{}

def batch_overflow(batch: ChatBatch) -> Bool:
  match batch:
    case ChatCollect{_, _, _, _, +overflow}: overflow
    case ChatDone{_, _, _, +overflow}: overflow
    case ChatIdle{}: False{}

def server_oldest(+xs: List<&2, ServerMatch>) -> String:
  match xs:
    case Nil{}: ""
    case Con{ServerMatch{_, _, +msgid}, _}: msgid

def server_newest.go(xs: List<&2, ServerMatch>, +last: String) -> String:
  match xs:
    case Nil{}: last
    case Con{ServerMatch{_, _, +msgid}, t}: server_newest.go(t, msgid)

def server_newest(+xs: List<&2, ServerMatch>) -> String:
  server_newest.go(xs, "")

def message_noun.one(one: Bool, +count: Nat) -> String:
  match one:
    case True{}: "1 message"
    case False{}: Nat.show(count) ++ " messages"

def message_noun(+count: Nat) -> String:
  message_noun.one(Nat.is_eq(count, 1n), count)

def render_server_header.capped(capped: Bool, +base: String) -> Cl.Line:
  match capped:
    case True{}: header_line(base ++ " (batch capped at 100)")
    case False{}: header_line(base)

def render_server_header.empty(empty: Bool, +target: String, +count: Nat, +oldest: String, +newest: String, +overflow: Bool) -> Cl.Line:
  match empty:
    case True{}: header_line("no server history for " ++ target)
    case False{}:
      render_server_header.capped(overflow,
        "server history: " ++ message_noun(count) ++ " for " ++ target
          ++ " (" ++ oldest ++ ".." ++ newest ++ "); /history before " ++ target ++ " " ++ oldest ++ " for older")

def render_server_header(+target: String, +count: Nat, +oldest: String, +newest: String, +overflow: Bool) -> Cl.Line:
  render_server_header.empty(Nat.is_eq(count, 0n), target, count, oldest, newest, overflow)

def format_server(xs: List<&2, ServerMatch>) -> List<&2, Cl.Line>:
  match xs:
    case Nil{}: Nil{}
    case Con{ServerMatch{+target, +line, _}, t}: Feed.format_search_match(target, line) <> format_server(t)

def import_server_page(+cl: Cl.Client, +target: String, +matches: List<&2, ServerMatch>, +overflow: Bool) -> Cl.Client:
  import_page.got(Cl.buf_get(cl, "*search*", False{}, True{}),
    render_server_header(target, List.length(&2, ServerMatch, matches),
      server_oldest(matches), server_newest(matches), overflow) <> format_server(matches))

# ---- fetch cursor ---------------------------------------------------------
# Bounded msgid memory dedupes refetch overlap. Oldest/newest drive
# BEFORE/AFTER paging without touching Client, Buffer, or Session types.
# Bounds move by requested direction and page order only: a BEFORE page
# moves oldest to the page head and leaves newest alone, an AFTER page
# moves newest to the page tail and leaves oldest alone, and the initial
# LATEST page sets both ends. Msgids are opaque: never lexical-sort them.
# MERGE POINT: the integrator passes the direction of the issued fetch.

type HistoryCursor is Data:
  HistoryCursor{target: String, oldest: String, newest: String, seen: List<&2, String>, count: Nat}

type FetchDir is Data:
  DirLatest{}
  DirBefore{}
  DirAfter{}

def cursor_new(+target: String) -> HistoryCursor:
  HistoryCursor{target, "", "", Nil{}, 0n}

def cursor_seen(+c: HistoryCursor, +msgid: String) -> Bool:
  match c:
    case HistoryCursor{_, _, _, +seen, _}: List.contains(~String, ~String.eq, seen, msgid)

# Fresh ids in page order, skipping seen ids and within-page duplicates.
def cursor_fresh.seen(known: Bool, +h: String, rest: List<&2, String>) -> List<&2, String>:
  match known:
    case True{}: rest
    case False{}: h <> rest

def cursor_fresh(msgids: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match msgids:
    case Nil{}: Nil{}
    case Con{+h, t}: cursor_fresh.seen(List.contains(~String, ~String.eq, seen, h), h, cursor_fresh(t, h <> seen))

def cursor_head(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, _}: h

def cursor_last.go(xs: List<&2, String>, +last: String) -> String:
  match xs:
    case Nil{}: last
    case Con{+h, t}: cursor_last.go(t, h)

def cursor_last(+xs: List<&2, String>) -> String:
  cursor_last.go(xs, "")

def cursor_apply.latest_end(empty: Bool, +target: String, +oldest: String, +newest: String, +seen: List<&2, String>, +count: Nat, +fresh: List<&2, String>) -> HistoryCursor:
  match empty:
    case True{}: HistoryCursor{target, oldest, newest, seen, count}
    case False{}: HistoryCursor{target, cursor_head(fresh), cursor_last(fresh), seen, count}

def cursor_apply.latest(+target: String, +oldest: String, +newest: String, +seen: List<&2, String>, +count: Nat, +fresh: List<&2, String>) -> HistoryCursor:
  cursor_apply.latest_end(List.is_empty(&2, String, fresh), target, oldest, newest, seen, count, fresh)

def cursor_apply.before_end(empty: Bool, +target: String, +oldest: String, +newest: String, +seen: List<&2, String>, +count: Nat, +fresh: List<&2, String>) -> HistoryCursor:
  match empty:
    case True{}: HistoryCursor{target, oldest, newest, seen, count}
    case False{}: HistoryCursor{target, cursor_head(fresh), newest, seen, count}

def cursor_apply.before(+target: String, +oldest: String, +newest: String, +seen: List<&2, String>, +count: Nat, +fresh: List<&2, String>) -> HistoryCursor:
  cursor_apply.before_end(List.is_empty(&2, String, fresh), target, oldest, newest, seen, count, fresh)

def cursor_apply.after_end(empty: Bool, +target: String, +oldest: String, +newest: String, +seen: List<&2, String>, +count: Nat, +fresh: List<&2, String>) -> HistoryCursor:
  match empty:
    case True{}: HistoryCursor{target, oldest, newest, seen, count}
    case False{}: HistoryCursor{target, oldest, cursor_last(fresh), seen, count}

def cursor_apply.after(+target: String, +oldest: String, +newest: String, +seen: List<&2, String>, +count: Nat, +fresh: List<&2, String>) -> HistoryCursor:
  cursor_apply.after_end(List.is_empty(&2, String, fresh), target, oldest, newest, seen, count, fresh)

def cursor_page.dir(+target: String, +oldest: String, +newest: String, +seen: List<&2, String>, +count: Nat, +fresh: List<&2, String>, dir: FetchDir) -> HistoryCursor:
  match dir:
    case DirLatest{}: cursor_apply.latest(target, oldest, newest, seen, count, fresh)
    case DirBefore{}: cursor_apply.before(target, oldest, newest, seen, count, fresh)
    case DirAfter{}: cursor_apply.after(target, oldest, newest, seen, count, fresh)

def cursor_page.fresh(+target: String, +oldest: String, +newest: String, +seen: List<&2, String>, +count: Nat, +fresh: List<&2, String>, dir: FetchDir) -> HistoryCursor:
  cursor_page.dir(target, oldest, newest,
    List.take(&2, String, List.append(&2, String, fresh, seen), SEEN_CAP()),
    Nat.add(count, List.length(&2, String, fresh)), fresh, dir)

def cursor_page.c(+c: HistoryCursor, +msgids: List<&2, String>, dir: FetchDir) -> HistoryCursor:
  match c:
    case HistoryCursor{+target, +oldest, +newest, +seen, +count}:
      cursor_page.fresh(target, oldest, newest, seen, count, cursor_fresh(msgids, seen), dir)

def cursor_page(+c: HistoryCursor, +msgids: List<&2, String>, dir: FetchDir) -> HistoryCursor:
  cursor_page.c(c, msgids, dir)

# Known-cursor anchors are opaque incoming msgids, never bare user input:
# always prefix `msgid=` under the same valid_msgid contract the batch
# collector enforces. A cursor id with stamp shape (contains T, ends Z) or
# carrying `=` stays a msgid; bare-stamp detection lives only on the
# user-typed anchor_wire path above.
def msgid_anchor(+msgid: String) -> Maybe<&2, String>:
  anchor_wire.keep(valid_msgid(msgid), "msgid=" ++ msgid)

def before_cursor_line(+target: String, +msgid: String, +limit: Nat) -> Maybe<&2, String>:
  before_line.emit(target, msgid_anchor(msgid), limit)

def after_cursor_line(+target: String, +msgid: String, +limit: Nat) -> Maybe<&2, String>:
  after_line.emit(target, msgid_anchor(msgid), limit)

def before_cursor(negotiated: Bool, +target: String, +msgid: String, +limit: Nat) -> Maybe<&2, String>:
  gate.issued(negotiated, before_cursor_line(target, msgid, limit))

def after_cursor(negotiated: Bool, +target: String, +msgid: String, +limit: Nat) -> Maybe<&2, String>:
  gate.issued(negotiated, after_cursor_line(target, msgid, limit))

def fetch_older.initial(initial: Bool, +negotiated: Bool, +target: String, +oldest: String, +limit: Nat) -> Maybe<&2, String>:
  match initial:
    case True{}: latest(negotiated, target, limit)
    case False{}: before_cursor(negotiated, target, oldest, limit)

def fetch_older(+c: HistoryCursor, +negotiated: Bool, +limit: Nat) -> Maybe<&2, String>:
  match c:
    case HistoryCursor{+target, +oldest, _, _, _}:
      fetch_older.initial(String.is_empty(oldest), negotiated, target, oldest, limit)

def fetch_newer.known(known: Bool, +negotiated: Bool, +target: String, +newest: String, +limit: Nat) -> Maybe<&2, String>:
  match known:
    case True{}: after_cursor(negotiated, target, newest, limit)
    case False{}: None{}

def fetch_newer(+c: HistoryCursor, +negotiated: Bool, +limit: Nat) -> Maybe<&2, String>:
  match c:
    case HistoryCursor{+target, _, +newest, _, _}:
      fetch_newer.known(Bool.not(String.is_empty(newest)), negotiated, target, newest, limit)

# Membership tests the immutable original seen set plus a within-page
# accumulator, so prepending fresh ids mid-page can never truncate original
# membership and reimport a saved tail id ([99 fresh + saved tail] keeps 99).
# The union stays bounded: seen holds SEEN_CAP ids and the page accumulator
# holds one capped page. Prepending unconditionally stays sound: re-adding a
# known id changes no later test, and a fresh id is marked before its dup.
def filter_unseen.keep(known: Bool, +h: BatchMsg, rest: List<&2, BatchMsg>) -> List<&2, BatchMsg>:
  match known:
    case True{}: rest
    case False{}: h <> rest

def filter_unseen_cap.go(msgs: List<&2, BatchMsg>, +orig: List<&2, String>, +page: List<&2, String>, +cap: Nat) -> List<&2, BatchMsg>:
  match msgs:
    case Nil{}: Nil{}
    case Con{+h, t}:
      filter_unseen.keep(List.contains(~String, ~String.eq, orig, batch_msgid(h))
        || List.contains(~String, ~String.eq, page, batch_msgid(h)), h,
        filter_unseen_cap.go(t, orig, List.take(&2, String, batch_msgid(h) <> page, cap), cap))

def filter_unseen_cap(+c: HistoryCursor, msgs: List<&2, BatchMsg>, +cap: Nat) -> List<&2, BatchMsg>:
  match c:
    case HistoryCursor{_, _, _, +seen, _}: filter_unseen_cap.go(msgs, seen, Nil{}, cap)

def filter_unseen(+c: HistoryCursor, msgs: List<&2, BatchMsg>) -> List<&2, BatchMsg>:
  filter_unseen_cap(c, msgs, BATCH_CAP())

# ---- admission predicates (open gates) --------------------------------------
# Pure rules for integrator-owned Session/CAP decisions. Each names the
# merge point that must enforce it; this module never touches Session,
# Workspace, Client, Buffer, Net, or View state itself.

# Disk search results are admitted only for the live request: the ticket
# must be the outstanding one, the generation current, and the endpoint
# exactly equal (host spelling and port scope, never case-folded).
# MERGE POINT: Session interception stamps (ticket, gen, endpoint) when the
# search starts and checks this predicate before import_page.
def search_completion_admitted(+ticket: Nat, +want_ticket: Nat, +gen: Nat, +want_gen: Nat, +endpoint: String, +want_endpoint: String) -> Bool:
  Nat.is_eq(ticket, want_ticket) && Nat.is_eq(gen, want_gen) && String.eq(endpoint, want_endpoint)

# Private history files open only when the final path is a regular file
# owned by us, reached without a final symlink, with a private (0600) mode.
# Reads reject; they never repair. Mirrors the native append rule.
# MERGE POINT: the checked native open ahead of search_file.
def disk_file_admitted(is_regular: Bool, owned: Bool, final_symlink: Bool, mode_private: Bool) -> Bool:
  is_regular && owned && Bool.not(final_symlink) && mode_private

# The negotiated flag that gates CHATHISTORY wire output is scoped to one
# endpoint and generation: any endpoint change or generation bump clears it
# until the next ACK arrives on the new connection.
# MERGE POINT: the CAP lane / Session owns the flag and applies this reset.
def chat_negotiated(acked: Bool, endpoint_stable: Bool, gen_current: Bool) -> Bool:
  acked && endpoint_stable && gen_current

# Disk search needs both the history preference and a configured path, so
# disabled history performs no disk IO at all.
# MERGE POINT: Session checks this before search_file; search_file keeps its
# empty-path short-circuit as defense in depth.
def disk_search_allowed(history_on: Bool, +path: String) -> Bool:
  match history_on:
    case False{}: False{}
    case True{}: Bool.not(String.is_empty(path))

# ---- /history requests ----------------------------------------------------
# Malformed input selects ReqUsage, never a partial fetch. Search/page run
# in the live session (Session interception over search_file); fetch lines
# are ordinary wire output gated on negotiation.

type HistoryRequest is Data:
  ReqSearch{text: String, target: String, rest: String}
  ReqPage{cursor: Nat, text: String, target: String, rest: String}
  ReqLatest{target: String, limit: Nat}
  ReqBefore{target: String, anchor: String, limit: Nat}
  ReqAfter{target: String, anchor: String, limit: Nat}
  ReqAround{target: String, anchor: String, limit: Nat}
  ReqBetween{target: String, a: String, b: String, limit: Nat}
  ReqUsage{}

def parse_limit.num(num: Maybe<&2, U32>) -> Maybe<&2, Nat>:
  match num:
    case None{}: None{}
    case Some{+n}: Some{U32.to_nat(n)}

def parse_limit.empty(empty: Bool, +rest: String) -> Maybe<&2, Nat>:
  match empty:
    case True{}: Some{PAGE_SIZE()}
    case False{}: parse_limit.num(U32.read(rest))

def parse_limit(+rest: String) -> Maybe<&2, Nat>:
  parse_limit.empty(String.is_empty(rest), rest)

def parse_search_request.got(got: Maybe<&2, DiskQuery>, +rest: String) -> HistoryRequest:
  match got:
    case None{}: ReqUsage{}
    case Some{DiskQuery{+text, +target}}: ReqSearch{text, target, rest}

def parse_search_request(+args: String) -> HistoryRequest:
  parse_search_request.got(parse_query(args), args)

def parse_page_request.query(got: Maybe<&2, DiskQuery>, +cursor: Nat, +qr: String) -> HistoryRequest:
  match got:
    case None{}: ReqUsage{}
    case Some{DiskQuery{+text, +target}}: ReqPage{cursor, text, target, qr}

def parse_page_request.num(num: Maybe<&2, U32>, +qr: String) -> HistoryRequest:
  match num:
    case None{}: ReqUsage{}
    case Some{+n}: parse_page_request.query(parse_query(qr), U32.to_nat(n), qr)

def parse_page_request.words(pair: String & String) -> HistoryRequest:
  match pair:
    case (+cw, +qr): parse_page_request.num(U32.read(cw), qr)

def parse_page_request(+args: String) -> HistoryRequest:
  parse_page_request.words(take_word(args))

def parse_latest.limit(got: Maybe<&2, Nat>, +target: String) -> HistoryRequest:
  match got:
    case None{}: ReqUsage{}
    case Some{+limit}: ReqLatest{target, limit}

def parse_latest.named(named: Bool, +target: String, +rest: String) -> HistoryRequest:
  match named:
    case True{}: parse_latest.limit(parse_limit(rest), target)
    case False{}: ReqUsage{}

def parse_latest.words(pair: String & String) -> HistoryRequest:
  match pair:
    case (+target, +rest): parse_latest.named(Bool.not(String.is_empty(target)), target, rest)

def parse_latest(+args: String) -> HistoryRequest:
  parse_latest.words(take_word(args))

def parse_fetch2.after(after: Bool, +target: String, +anchor: String, +limit: Nat) -> HistoryRequest:
  match after:
    case True{}: ReqAfter{target, anchor, limit}
    case False{}: ReqAround{target, anchor, limit}

def parse_fetch2.before(before: Bool, +target: String, +anchor: String, +limit: Nat, after: Bool, +target2: String, +anchor2: String, +limit2: Nat) -> HistoryRequest:
  match before:
    case True{}: ReqBefore{target, anchor, limit}
    case False{}: parse_fetch2.after(after, target2, anchor2, limit2)

def parse_fetch2.tag(+tag: Nat, +target: String, +anchor: String, +limit: Nat) -> HistoryRequest:
  parse_fetch2.before(Nat.is_eq(tag, 0n), target, anchor, limit, Nat.is_eq(tag, 1n), target, anchor, limit)

def parse_fetch2.limit(got: Maybe<&2, Nat>, +target: String, +anchor: String, +tag: Nat) -> HistoryRequest:
  match got:
    case None{}: ReqUsage{}
    case Some{+limit}: parse_fetch2.tag(tag, target, anchor, limit)

def parse_fetch2.anchored(ok: Bool, +anchor: String, +rest: String, +target: String, +tag: Nat) -> HistoryRequest:
  match ok:
    case True{}: parse_fetch2.limit(parse_limit(rest), target, anchor, tag)
    case False{}: ReqUsage{}

def parse_fetch2.rest(pair: String & String, +target: String, +tag: Nat) -> HistoryRequest:
  match pair:
    case (+anchor, +rest): parse_fetch2.anchored(Bool.not(String.is_empty(anchor)), anchor, rest, target, tag)

def parse_fetch2.named(named: Bool, +target: String, +rest: String, +tag: Nat) -> HistoryRequest:
  match named:
    case True{}: parse_fetch2.rest(take_word(rest), target, tag)
    case False{}: ReqUsage{}

def parse_fetch2.words(pair: String & String, +tag: Nat) -> HistoryRequest:
  match pair:
    case (+target, +rest): parse_fetch2.named(Bool.not(String.is_empty(target)), target, rest, tag)

def parse_fetch2(+args: String, +tag: Nat) -> HistoryRequest:
  parse_fetch2.words(take_word(args), tag)

def parse_between.limit(got: Maybe<&2, Nat>, +target: String, +a: String, +b: String) -> HistoryRequest:
  match got:
    case None{}: ReqUsage{}
    case Some{+limit}: ReqBetween{target, a, b, limit}

def parse_between.second_b(ok: Bool, +b: String, +rest: String, +target: String, +a: String) -> HistoryRequest:
  match ok:
    case True{}: parse_between.limit(parse_limit(rest), target, a, b)
    case False{}: ReqUsage{}

def parse_between.rest(pair: String & String, +target: String, +a: String) -> HistoryRequest:
  match pair:
    case (+b, +rest): parse_between.second_b(Bool.not(String.is_empty(b)), b, rest, target, a)

def parse_between.first_a(ok: Bool, +a: String, +rest: String, +target: String) -> HistoryRequest:
  match ok:
    case True{}: parse_between.rest(take_word(rest), target, a)
    case False{}: ReqUsage{}

def parse_between.second(pair: String & String, +target: String) -> HistoryRequest:
  match pair:
    case (+a, +rest): parse_between.first_a(Bool.not(String.is_empty(a)), a, rest, target)

def parse_between.named(named: Bool, +target: String, +rest: String) -> HistoryRequest:
  match named:
    case True{}: parse_between.second(take_word(rest), target)
    case False{}: ReqUsage{}

def parse_between.words(pair: String & String) -> HistoryRequest:
  match pair:
    case (+target, +rest): parse_between.named(Bool.not(String.is_empty(target)), target, rest)

def parse_between(+args: String) -> HistoryRequest:
  parse_between.words(take_word(args))

def parse_request.between(yes: Bool, +args: String) -> HistoryRequest:
  match yes:
    case True{}: parse_between(args)
    case False{}: ReqUsage{}

def parse_request.around(yes: Bool, +verb: String, +args: String) -> HistoryRequest:
  match yes:
    case True{}: parse_fetch2(args, 2n)
    case False{}: parse_request.between(Irc.ieq(verb, "between"), args)

def parse_request.after(yes: Bool, +verb: String, +args: String) -> HistoryRequest:
  match yes:
    case True{}: parse_fetch2(args, 1n)
    case False{}: parse_request.around(Irc.ieq(verb, "around"), verb, args)

def parse_request.before(yes: Bool, +verb: String, +args: String) -> HistoryRequest:
  match yes:
    case True{}: parse_fetch2(args, 0n)
    case False{}: parse_request.after(Irc.ieq(verb, "after"), verb, args)

def parse_request.latest(yes: Bool, +verb: String, +args: String) -> HistoryRequest:
  match yes:
    case True{}: parse_latest(args)
    case False{}: parse_request.before(Irc.ieq(verb, "before"), verb, args)

def parse_request.page(yes: Bool, +verb: String, +args: String) -> HistoryRequest:
  match yes:
    case True{}: parse_page_request(args)
    case False{}: parse_request.latest(Irc.ieq(verb, "latest"), verb, args)

def parse_request.search(yes: Bool, +verb: String, +args: String) -> HistoryRequest:
  match yes:
    case True{}: parse_search_request(args)
    case False{}: parse_request.page(Irc.ieq(verb, "page"), verb, args)

def parse_request.verb(+verb: String, +args: String) -> HistoryRequest:
  parse_request.search(Irc.ieq(verb, "search"), verb, args)

def parse_request.words(pair: String & String) -> HistoryRequest:
  match pair:
    case (+verb, +args): parse_request.verb(verb, args)

def parse_request(+rest: String) -> HistoryRequest:
  parse_request.words(take_word(Irc.drop_spaces(rest)))

def usage() -> String:
  "usage: /history search <text> | /history page <offset> <text> | /history latest <target> [limit] | /history before|after|around <target> <msgid|timestamp> [limit] | /history between <target> <a> <b> [limit]"

def unavailable() -> String:
  "server history unavailable (draft/chathistory not negotiated)"

def live_only() -> String:
  "disk history search runs in the live session"

def echo_history(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, Cl.active_of(cl), Cl.Error{}, msg)

def submit_fetch.gated(+cl: Cl.Client, +line: String, gated: Bool) -> Cl.Client & List<&2, String>:
  match gated:
    case True{}: (cl, line <> Nil{})
    case False{}: (echo_history(cl, unavailable()), Nil{})

def submit_fetch.line(+cl: Cl.Client, line: Maybe<&2, String>, +negotiated: Bool) -> Cl.Client & List<&2, String>:
  match line:
    case None{}: (echo_history(cl, usage()), Nil{})
    case Some{+l}: submit_fetch.gated(cl, l, negotiated)

def submit_history.req(+cl: Cl.Client, req: HistoryRequest, +negotiated: Bool) -> Cl.Client & List<&2, String>:
  match req:
    case ReqUsage{}: (echo_history(cl, usage()), Nil{})
    case ReqSearch{_, _, _}: (echo_history(cl, live_only()), Nil{})
    case ReqPage{_, _, _, _}: (echo_history(cl, live_only()), Nil{})
    case ReqLatest{+target, +limit}: submit_fetch.line(cl, latest_line(target, limit), negotiated)
    case ReqBefore{+target, +anchor, +limit}: submit_fetch.line(cl, before_line(target, anchor, limit), negotiated)
    case ReqAfter{+target, +anchor, +limit}: submit_fetch.line(cl, after_line(target, anchor, limit), negotiated)
    case ReqAround{+target, +anchor, +limit}: submit_fetch.line(cl, around_line(target, anchor, limit), negotiated)
    case ReqBetween{+target, +a, +b, +limit}: submit_fetch.line(cl, between_line(target, a, b, limit), negotiated)

# Pure adapter for the integrator's Sub.Slash arm. Disk search/page need
# Session file IO, so they report live_only until Session interception
# (mirroring upload_input) runs search_file/import_page.
def submit_history(+cl: Cl.Client, +rest: String, +negotiated: Bool) -> Cl.Client & List<&2, String>:
  submit_history.req(cl, parse_request(rest), negotiated)

# Fetch subcommands need a connection; search/page/usage work offline.
def history_needs_connection.req(req: HistoryRequest) -> Bool:
  match req:
    case ReqLatest{_, _}: True{}
    case ReqBefore{_, _, _}: True{}
    case ReqAfter{_, _, _}: True{}
    case ReqAround{_, _, _}: True{}
    case ReqBetween{_, _, _, _}: True{}
    case _: False{}

def history_needs_connection(+rest: String) -> Bool:
  history_needs_connection.req(parse_request(rest))
