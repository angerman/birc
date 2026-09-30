# Persisted IRC chat scrollback history across sessions with reconnect markers.
import Base
import ./buffer.bend as Cl
import ./irc.bend as Irc
import ./frame.bend as Fr

# ---- line serialization & parsing -----------------------------------------

def serialize_kind(k: Cl.LineKind) -> String:
  match k:
    case Cl.Msg{}: "MSG"
    case Cl.Self{}: "SELF"
    case Cl.System{}: "SYS"
    case Cl.Action{}: "ACT"
    case Cl.Notice{}: "NOT"
    case Cl.Error{}: "ERR"
    case Cl.Highlight{}: "HL"
    case Cl.Reconnect{}: "REC"
    case Cl.LinkResult{}: "LINK"

def parse_kind.on(is_msg: Bool, is_self: Bool, is_sys: Bool, is_act: Bool, is_not: Bool, is_hl: Bool) -> Cl.LineKind:
  match is_msg:
    case True{}: Cl.Msg{}
    case False{}:
      match is_self:
        case True{}: Cl.Self{}
        case False{}:
          match is_sys:
            case True{}: Cl.System{}
            case False{}:
              match is_act:
                case True{}: Cl.Action{}
                case False{}:
                  match is_not:
                    case True{}: Cl.Notice{}
                    case False{}:
                      match is_hl:
                        case True{}: Cl.Highlight{}
                        case False{}: Cl.Error{}

def parse_kind(+s: String) -> Cl.LineKind:
  parse_kind.on(
    String.eq(s, "MSG"),
    String.eq(s, "SELF"),
    String.eq(s, "SYS"),
    String.eq(s, "ACT"),
    String.eq(s, "NOT"),
    String.eq(s, "HL")
  )

def serialize_line.recon(is_recon: Bool, +target: String, kind: Cl.LineKind, +ts: String, +text: String) -> String:
  match is_recon:
    case True{}: ""
    case False{}: target ++ "\t" ++ serialize_kind(kind) ++ "\t" ++ ts ++ "\t" ++ text ++ "\n"

def serialize_line(+target: String, +ln: Cl.Line) -> String:
  match ln:
    case Cl.Line{+kind, +ts, +text, _, _}:
      serialize_line.recon(Cl.is_reconnect(kind) || Cl.is_link_result(kind), target, kind, ts, text)

def serialize_lines.go(+target: String, lines: List<&2, Cl.Line>, +acc: String) -> String:
  match lines:
    case Nil{}: acc
    case Con{+h, t}:
      serialize_lines.go(target, t, acc ++ serialize_line(target, h))

def serialize_lines(+target: String, lines: List<&2, Cl.Line>) -> String:
  serialize_lines.go(target, lines, "")

# Version 2 has an explicit endpoint and author. Legacy records have no server
# identity and are not loaded by the IO path: guessing could disclose one
# server's private conversation on another server.
def serialize_line_for.recon(marker: Bool, +endpoint: String, +target: String, kind: Cl.LineKind, +ts: String, +text: String, +author: String) -> String:
  match marker:
    case True{}: ""
    case False{}:
      "BIRC2\t" ++ Irc.sanitize_in(endpoint) ++ "\t" ++ Irc.sanitize_in(target) ++ "\t"
        ++ serialize_kind(kind) ++ "\t" ++ Irc.sanitize_in(ts) ++ "\t"
        ++ Irc.sanitize_in(author) ++ "\t" ++ Irc.sanitize_in(text) ++ "\n"

def serialize_line_for(+endpoint: String, +target: String, line: Cl.Line) -> String:
  match line:
    case Cl.Line{+kind, +ts, +text, +author, _}:
      serialize_line_for.recon(Cl.is_reconnect(kind) || Cl.is_link_result(kind), endpoint, target, kind, ts, text, author)

def serialize_lines_for(lines: List<&2, Cl.Line>, +endpoint: String, +target: String) -> String:
  match lines:
    case Nil{}: ""
    case Con{line, t}: serialize_line_for(endpoint, target, line) ++ serialize_lines_for(t, endpoint, target)

def join_tokens.go(+xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+h, t}: join_tokens.go(t, acc ++ "\t" ++ h)

def join_tokens(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, t}: join_tokens.go(t, h)

type HistEntry is Data:
  Entry{target: String, line: Cl.Line}
  ServerEntry{line: Cl.Line}

def parse_entry.control(control: Bool, target: String, line: Cl.Line) -> HistEntry:
  match control:
    case True{}: ServerEntry{line}
    case False{}: Entry{target, line}

def parse_line_tokens(+tokens: List<&2, String>) -> Maybe<&2, HistEntry>:
  match tokens:
    case Con{+target, rest1}:
      match rest1:
        case Con{+kstr, rest2}:
          match rest2:
            case Con{+ts, rest3}:
              Some{parse_entry.control(Irc.ieq(target, "server"), target, Cl.Line{parse_kind(kstr), ts, join_tokens(rest3), "", 0n})}
            case Nil{}: None{}
        case Nil{}: None{}
    case Nil{}: None{}

def parse_line.empty(empty: Bool, +raw: String) -> Maybe<&2, HistEntry>:
  match empty:
    case True{}: None{}
    case False{}: parse_line_tokens(String.split(raw, Chr{9}))

def parse_line(+raw: String) -> Maybe<&2, HistEntry>:
  parse_line.empty(String.is_empty(raw), raw)

def valid_kind(+kind: String) -> Bool:
  String.eq(kind, "MSG") || String.eq(kind, "SELF") || String.eq(kind, "SYS")
    || String.eq(kind, "ACT") || String.eq(kind, "NOT") || String.eq(kind, "ERR") || String.eq(kind, "HL")

def parse_line_for.valid(ok: Bool, +target: String, +kind: String, +ts: String, +author: String, +text: String) -> Maybe<&2, HistEntry>:
  match ok:
    case False{}: None{}
    case True{}: Some{parse_entry.control(String.eq(target, "*server*"), target, Cl.Line{parse_kind(kind), ts, text, author, 0n})}

def parse_line_for.tokens(tokens: List<&2, String>, +endpoint: String) -> Maybe<&2, HistEntry>:
  match tokens:
    case Con{+version, Con{+server, Con{+target, Con{+kind, Con{+ts, Con{+author, Con{+text, Nil{}}}}}}}}:
      parse_line_for.valid(String.eq(version, "BIRC2") && Irc.ieq(server, endpoint)
        && Bool.not(String.is_empty(target)) && (String.eq(target, "*server*") || Bool.not(String.starts_with(target, "*")))
        && valid_kind(kind), target, kind, ts, author, text)
    case _: None{}

def parse_line_for(+endpoint: String, +raw: String) -> Maybe<&2, HistEntry>:
  parse_line_for.tokens(String.split(raw, Chr{9}), endpoint)

def parse_entries.on(m: Maybe<&2, HistEntry>, acc: List<&2, HistEntry>) -> List<&2, HistEntry>:
  match m:
    case None{}: acc
    case Some{entry}: entry <> acc

def parse_entries.step(+raw: String, acc: List<&2, HistEntry>) -> List<&2, HistEntry>:
  parse_entries.on(parse_line(raw), acc)

def parse_entries.go(lines: List<&2, String>, acc: List<&2, HistEntry>) -> List<&2, HistEntry>:
  match lines:
    case Nil{}: List.reverse(&2, HistEntry, acc)
    case Con{+h, t}: parse_entries.go(t, parse_entries.step(h, acc))

def parse_history_text(+text: String) -> List<&2, HistEntry>:
  parse_entries.go(String.split(text, Chr{10}), Nil{})

# ---- history diff extraction ----------------------------------------------

def lines_after.keep(new: Bool, +line: Cl.Line, rest: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match new:
    case True{}: line <> rest
    case False{}: rest

# Event identity, not text equality: two equal messages are distinct additions.
def lines_after(lines: List<&2, Cl.Line>, +seq: Nat) -> List<&2, Cl.Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+line, t}:
      match line:
        case Cl.Line{_, _, _, _, +id}:
          lines_after.keep(Nat.is_gt(id, seq), line, lines_after(t, seq))

def extract_new_buf(+seq: Nat, b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, _, lines, _, _}:
      Bool.pick(String, String.starts_with(name, "*"), "", serialize_lines(name, lines_after(lines, seq)))

def extract_new_bufs(bufs: List<&2, Cl.Buffer>, +seq: Nat) -> String:
  match bufs:
    case Nil{}: ""
    case Con{b, t}: extract_new_buf(seq, b) ++ extract_new_bufs(t, seq)

def extract_new_history(+old_cl: Cl.Client, new_cl: Cl.Client) -> String:
  match new_cl:
    case Cl.Client{_, _, bufs, _, _, _, _, _}:
      extract_new_bufs(bufs, Cl.log_seq_of(old_cl))

def new_entries.lines(lines: List<&2, Cl.Line>, +target: String, +control: Bool) -> List<&2, HistEntry>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, t}: parse_entry.control(control, target, line) <> new_entries.lines(t, target, control)

def new_entries(bufs: List<&2, Cl.Buffer>, +seq: Nat, first: Bool) -> List<&2, HistEntry>:
  match bufs:
    case Nil{}: Nil{}
    case Con{Cl.Buffer{+name, _, _, lines, _, _}, t}:
      List.append(&2, HistEntry,
        Bool.pick(List<&2, HistEntry>, String.starts_with(name, "*"), Nil{}, new_entries.lines(lines_after(lines, seq), name, first)),
        new_entries(t, seq, False{}))

def entry_line(entry: HistEntry) -> Cl.Line:
  match entry:
    case Entry{_, line}: line
    case ServerEntry{line}: line

def entry_id_le(a: HistEntry, b: HistEntry) -> Bool:
  Cl.line_id_le(entry_line(a), entry_line(b))

def serialize_entries(entries: List<&2, HistEntry>, +endpoint: String) -> String:
  match entries:
    case Nil{}: ""
    case Con{entry, t}:
      match entry:
        case Entry{target, line}: serialize_line_for(endpoint, target, line) ++ serialize_entries(t, endpoint)
        case ServerEntry{line}: serialize_line_for(endpoint, "*server*", line) ++ serialize_entries(t, endpoint)

def extract_new_history_for(+endpoint: String, +old_cl: Cl.Client, new_cl: Cl.Client) -> String:
  match new_cl:
    case Cl.Client{_, _, bufs, _, _, _, _, _}:
      serialize_entries(List.sort(~HistEntry, ~entry_id_le, new_entries(bufs, Cl.log_seq_of(old_cl), True{})), endpoint)

# ---- applying history on load ---------------------------------------------

def apply_entry.bi(+cl: Cl.Client, +bi: Nat, ln: Cl.Line) -> Cl.Client:
  match ln:
    case Cl.Line{kind, +ts, +text, +author, _}:
      Cl.client_log_author_ts(cl, bi, kind, ts, text, author)

def apply_entry.got(pair: Cl.Client & Maybe<&2, Nat>, ln: Cl.Line) -> Cl.Client:
  match pair:
    case (cl2, None{}): cl2
    case (cl2, Some{bi}): apply_entry.bi(cl2, bi, ln)

def apply_entry.target(is_srv: Bool, +cl: Cl.Client, +target: String, ln: Cl.Line) -> Cl.Client:
  match is_srv:
    case True{}: apply_entry.bi(cl, 0n, ln)
    case False{}: apply_entry.got(Cl.buf_get(cl, target, Irc.starts_channel(target), True{}), ln)

def apply_entry(+cl: Cl.Client, +target: String, ln: Cl.Line) -> Cl.Client:
  apply_entry.target(Irc.ieq(target, "server"), cl, target, ln)

def apply_hist_entry(entry: HistEntry, cl: Cl.Client) -> Cl.Client:
  match entry:
    case ServerEntry{line}: apply_entry.bi(cl, 0n, line)
    case Entry{+target, line}: apply_entry.got(Cl.buf_get(cl, target, Irc.starts_channel(target), True{}), line)

def apply_entries(entries: List<&2, HistEntry>, cl: Cl.Client) -> Cl.Client:
  match entries:
    case Nil{}: cl
    case Con{+e, t}:
      apply_entries(t, apply_hist_entry(e, cl))

def buf_has_lines(+b: Cl.Buffer) -> Bool:
  match b:
    case Cl.Buffer{_, _, _, lines, _, _}:
      match lines:
        case Nil{}: False{}
        case Con{_, _}: True{}

def add_reconnect_marker.has(has: Bool, +b: Cl.Buffer, +now: String) -> Cl.Buffer:
  match has:
    case False{}: b
    case True{}:
      Cl.buf_reconnect(b, now)

def add_reconnect_marker(+b: Cl.Buffer, +now: String) -> Cl.Buffer:
  add_reconnect_marker.has(buf_has_lines(b), b, now)

def add_markers_bufs(bufs: List<&2, Cl.Buffer>, +now: String) -> List<&2, Cl.Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{+b, t}:
      add_reconnect_marker(b, now) <> add_markers_bufs(t, now)

def add_markers_cl(+cl: Cl.Client, +now: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now_old, +stg, +auth, +log_seq}:
      Cl.stamp_logs(Cl.Client{nick, server, add_markers_bufs(bufs, now), active, now_old, stg, auth, log_seq})

def cap_buf_history(b: Cl.Buffer, cap: U32) -> Cl.Buffer:
  match b:
    case Cl.Buffer{+name, is_ch, +topic, lines, +nicks, scroll}:
      Cl.Buffer{name, is_ch, topic, Cl.take_last(lines, U32.to_nat(cap)), nicks, scroll}

def cap_bufs_history(bufs: List<&2, Cl.Buffer>, +cap: U32) -> List<&2, Cl.Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{+b, t}:
      cap_buf_history(b, cap) <> cap_bufs_history(t, cap)

def apply_history.cap(cl: Cl.Client, +now: String, +cap: U32) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      add_markers_cl(Cl.Client{nick, server, cap_bufs_history(bufs, cap), active, now, stg, auth, log_seq}, now)

def apply_history(+cl: Cl.Client, entries: List<&2, HistEntry>, +now: String, +cap: U32) -> Cl.Client:
  apply_history.cap(apply_entries(entries, cl), now, cap)

# ---- file IO --------------------------------------------------------------

# Read complete UTF-8 records, not decoded chunks. A character may straddle a
# read boundary. The record bound also rejects a corrupt unterminated line.
type ReadState is Data:
  ReadState{cl: Cl.Client, rev: List<&2, U32>, count: Nat, dropping: Bool}

def cap_client_history(cl: Cl.Client, cap: U32) -> Cl.Client:
  match cl:
    case Cl.Client{nick, server, bufs, active, now, stg, auth, seq}:
      Cl.Client{nick, server, cap_bufs_history(bufs, cap), active, now, stg, auth, seq}

def read_record.entry(entry: Maybe<&2, HistEntry>, cl: Cl.Client, cap: U32) -> Cl.Client:
  match entry:
    case None{}: cl
    case Some{entry}: cap_client_history(apply_hist_entry(entry, cl), cap)

def read_record.utf8(text: Maybe<&2, String>, cl: Cl.Client, +endpoint: String, cap: U32) -> Cl.Client:
  match text:
    case None{}: cl
    case Some{raw}: read_record.entry(parse_line_for(endpoint, raw), cl, cap)

def read_record(drop: Bool, cl: Cl.Client, rev: List<&2, U32>, +endpoint: String, cap: U32) -> Cl.Client:
  match drop:
    case True{}: cl
    case False{}: read_record.utf8(Fr.utf8_decode(List.reverse(&2, U32, rev)), cl, endpoint, cap)

def read_step.store(drop: Bool, cl: Cl.Client, rev: List<&2, U32>, count: Nat, byte: U32) -> ReadState:
  match drop:
    case True{}: ReadState{cl, Nil{}, 0n, True{}}
    case False{}: ReadState{cl, byte <> rev, 1n+count, False{}}

def read_step.newline(nl: Bool, +endpoint: String, cap: U32, cl: Cl.Client, rev: List<&2, U32>, +count: Nat, dropping: Bool, byte: U32) -> ReadState:
  match nl:
    case True{}: ReadState{read_record(dropping, cl, rev, endpoint, cap), Nil{}, 0n, False{}}
    case False{}: read_step.store(dropping || Nat.is_ge(count, 8192n), cl, rev, count, byte)

def read_step(+endpoint: String, cap: U32, state: ReadState, +byte: U32) -> ReadState:
  match state:
    case ReadState{cl, rev, count, dropping}:
      read_step.newline(U32.is_eq(byte, 10), endpoint, cap, cl, rev, count, dropping, byte)

def read_chunk(bytes: List<&2, U32>, state: ReadState, +endpoint: String, +cap: U32) -> ReadState:
  match bytes:
    case Nil{}: state
    case Con{byte, t}: read_chunk(t, read_step(endpoint, cap, state, byte), endpoint, cap)

def read_finish(f: File, state: ReadState, now: String) -> IO(Cl.Client):
  match state:
    case ReadState{cl, _, _, _}:
      do IO<Cl.Client>:
        Unit <- File.close(f)
        return add_markers_cl(cl, now)

def read_failure_text(error: U32 & String, +stage: String) -> String:
  match error:
    case (code, +msg): "history " ++ stage ++ " (" ++ U32.show(code) ++ "): " ++ msg

# A failed load does not replace the current client or lose completed records.
# Close the descriptor before adding its visible, credential-free diagnostic.
def read_failure(f: File, state: ReadState, now: String, error: U32 & String, stage: String) -> IO(Cl.Client):
  do IO<Cl.Client>:
    cl : Cl.Client <- read_finish(f, state, now)
    return Cl.client_log(cl, 0n, Cl.Error{}, read_failure_text(error, stage))

def read_loop.empty(empty: Bool, f: File, +bytes: List<&2, U32>, state: ReadState, endpoint: String, cap: U32, now: String, remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match empty:
    case True{}: read_finish(f, state, now)
    case False{}: next(f, read_chunk(bytes, state, endpoint, cap), Nat.sub(remaining, List.length(&2, U32, bytes)))

def read_loop.got(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>, state: ReadState, endpoint: String, cap: U32, now: String, remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match pair:
    case (f, Fail{error}): read_failure(f, state, now, error, "read failed; only completed records were restored")
    case (f, Done{+bytes}): read_loop.empty(Nat.is_eq(List.length(&2, U32, bytes), 0n), f, bytes, state, endpoint, cap, now, remaining, next)

def read_loop.read(done: Bool, f: File, state: ReadState, +endpoint: String, +cap: U32, +now: String, +remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match done:
    case True{}: read_finish(f, state, now)
    case False{}:
      do IO<Cl.Client>:
        pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, U32.from_nat(Cl.clamp_nat(remaining, 4096n)))
        read_loop.got(pair, state, endpoint, cap, now, remaining, next)

# The file's initial size bounds the loop. Appends during loading cannot keep it
# alive forever. Short reads still consume the full snapshot; state holds at most 8192 bytes and
# MAX_BUFFERS * min(cap, SCROLL_CAP) lines, regardless of file size.
def read_loop(fuel: Nat, f: File, state: ReadState, +endpoint: String, +cap: U32, +now: String, +remaining: Nat) -> IO(Cl.Client):
  match fuel:
    case 0n: read_finish(f, state, now)
    case 1n+p:
      read_loop.read(Nat.is_eq(remaining, 0n), f, state, endpoint, cap, now, remaining,
        f2 => st2 => rest => read_loop(p, f2, st2, endpoint, cap, now, rest))

def read_size(pair: File & Result<&1, &1, U32 & String, U32>, cl: Cl.Client, endpoint: String, cap: U32, now: String) -> IO(Cl.Client):
  match pair:
    case (f, Fail{error}): read_failure(f, ReadState{cl, Nil{}, 0n, False{}}, now, error, "size unavailable")
    case (f, Done{+size}): read_loop(1n+U32.to_nat(size), f, ReadState{cl, Nil{}, 0n, False{}}, endpoint, cap, now, U32.to_nat(size))

# ENOENT is the normal first-run case on this POSIX runtime. Other open
# failures must be visible; an inaccessible history file is not an empty one.
def read_open.error(missing: Bool, cl: Cl.Client, error: U32 & String) -> IO(Cl.Client):
  match missing:
    case True{}: IO.pure(Cl.Client, cl)
    case False{}: IO.pure(Cl.Client, Cl.client_log(cl, 0n, Cl.Error{}, read_failure_text(error, "open failed")))

def read_open.failed(error: U32 & String, cl: Cl.Client) -> IO(Cl.Client):
  match error:
    case (+code, +msg): read_open.error(U32.is_eq(code, 2), cl, (code, msg))

def read_open(result: Result<&1, &1, U32 & String, File>, cl: Cl.Client, endpoint: String, cap: U32, now: String) -> IO(Cl.Client):
  match result:
    case Fail{error}: read_open.failed(error, cl)
    case Done{f}:
      do IO<Cl.Client>:
        pair : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
        read_size(pair, cl, endpoint, cap, now)

def history_append_file.done(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (f, _):
      File.close(f)

def history_append_file.open(r: Result<&1, &1, U32 & String, File>, +data: String) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.pure(Unit, Unit{})
    case Done{f}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, data)
        history_append_file.done(pair)

def history_append_file.check(skip: Bool, +path: String, +data: String) -> IO(Unit):
  match skip:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
        history_append_file.open(r, data)

def history_append_file(+path: String, +data: String) -> IO(Unit):
  history_append_file.check(String.is_empty(path) || String.is_empty(data), path, data)

def resolve_history_path.home(h: Result<&1, &1, U32 & String, String>) -> IO(String):
  match h:
    case Done{+home}:
      IO.pure(String, home ++ "/.birc_history.log")
    case Fail{_}:
      IO.pure(String, ".birc_history.log")

def resolve_history_path.val(none: Bool, +val: String) -> IO(String):
  match none:
    case True{}: IO.pure(String, "")
    case False{}: IO.pure(String, val)

def resolve_history_path.birc_env(b: Result<&1, &1, U32 & String, String>) -> IO(String):
  match b:
    case Done{+val}:
      resolve_history_path.val(String.eq(val, "none") || String.is_empty(val), val)
    case Fail{_}:
      do IO<String>:
        h : Result<&1, &1, U32 & String, String> <- IO.get_env("HOME")
        resolve_history_path.home(h)

def resolve_history_path() -> IO(String):
  do IO<String>:
    b : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_HISTORY")
    resolve_history_path.birc_env(b)

def resolve_history_cap.num(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}: 100
    case Some{n}: n

def resolve_history_cap.val(b: Result<&1, &1, U32 & String, String>) -> U32:
  match b:
    case Fail{_}: 100
    case Done{+s}: resolve_history_cap.num(U32.read(s))

def resolve_history_cap() -> IO(U32):
  do IO<U32>:
    b : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_HISTORY_LINES")
    IO.pure(U32, resolve_history_cap.val(b))

def history_init_client.has(empty: Bool, +content: String, +nick: String, +host: String, +now: String, +cap: U32) -> Cl.Client:
  match empty:
    case True{}:
      Cl.init_with_cap(nick, host, cap)
    case False{}:
      apply_history(Cl.init_with_cap(nick, host, cap), parse_history_text(content), now, cap)

def history_init_client.content(+content: String, +nick: String, +host: String, +now: String, +cap: U32) -> Cl.Client:
  history_init_client.has(String.is_empty(content), content, nick, host, now, cap)

def history_load_client.pick(skip: Bool, +path: String, +endpoint: String, +cap: U32, +cl: Cl.Client, +now: String) -> IO(Cl.Client):
  match skip:
    case True{}: IO.pure(Cl.Client, cl)
    case False{}:
      do IO<Cl.Client>:
        result : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        read_open(result, cl, endpoint, cap, now)

# Endpoint switches reset the buffers before this call. Load into that client,
# not a fresh init: settings, authentication, and global event IDs must survive.
def history_load_client(+path: String, +endpoint: String, +cap: U32, +cl: Cl.Client) -> IO(Cl.Client):
  match cl:
    case Cl.Client{_, _, _, _, +now, _, _, _}:
      history_load_client.pick(String.is_empty(path) || Bool.not(Cl.settings_history(Cl.get_settings(cl))), path, endpoint, cap, cl, now)

def history_init_client.pick(empty: Bool, +path: String, +endpoint: String, +cap: U32, +nick: String, +host: String, +now: String) -> IO(Cl.Client):
  match empty:
    case True{}:
      IO.pure(Cl.Client, Cl.init_with_cap(nick, host, cap))
    case False{}:
      history_load_client(path, endpoint, cap, Cl.set_now(Cl.init_with_cap(nick, host, cap), now))

def history_init_client(+path: String, +endpoint: String, +cap: U32, +nick: String, +host: String, +now: String) -> IO(Cl.Client):
  history_init_client.pick(String.is_empty(path), path, endpoint, cap, nick, host, now)

def maybe_save_history.check(enabled: Bool, +path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Unit):
  match enabled:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      history_append_file(path, extract_new_history_for(endpoint, old_cl, new_cl))

def maybe_save_history(+path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Unit):
  maybe_save_history.check(
    Bool.not(String.is_empty(path)) && Cl.settings_history(Cl.get_settings(new_cl)),
    path, endpoint, old_cl, new_cl
  )
