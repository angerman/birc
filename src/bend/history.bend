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
    case Cl.Presence{}: "PRS"
    case Cl.Nick{}: "NCK"

def parse_kind.on(is_msg: Bool, is_self: Bool, is_sys: Bool, is_act: Bool, is_not: Bool, is_hl: Bool, is_prs: Bool, is_nck: Bool) -> Cl.LineKind:
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
                        case False{}:
                          match is_prs:
                            case True{}: Cl.Presence{}
                            case False{}:
                              match is_nck:
                                case True{}: Cl.Nick{}
                                case False{}: Cl.Error{}

def parse_kind(+s: String) -> Cl.LineKind:
  parse_kind.on(
    String.eq(s, "MSG"),
    String.eq(s, "SELF"),
    String.eq(s, "SYS"),
    String.eq(s, "ACT"),
    String.eq(s, "NOT"),
    String.eq(s, "HL"),
    String.eq(s, "PRS"),
    String.eq(s, "NCK")
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
        ++ Irc.sanitize_in(author) ++ "\t" ++ Irc.sanitize_keep_style(text) ++ "\n"

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

# Presence rows persist under PRS/NCK so the joins/nicks toggles filter them
# retroactively. Pre-changeover SYS join rows keep parsing as System and
# stay unfilterable: no text heuristic may reclassify them as Presence.
def valid_kind(+kind: String) -> Bool:
  String.eq(kind, "MSG") || String.eq(kind, "SELF") || String.eq(kind, "SYS")
    || String.eq(kind, "ACT") || String.eq(kind, "NOT") || String.eq(kind, "ERR") || String.eq(kind, "HL")
    || String.eq(kind, "PRS") || String.eq(kind, "NCK")

def parse_line_for.valid(ok: Bool, +target: String, +kind: String, +ts: String, +author: String, +text: String) -> Maybe<&2, HistEntry>:
  match ok:
    case False{}: None{}
    case True{}: Some{parse_entry.control(String.eq(target, "*server*"), target, Cl.Line{parse_kind(kind), ts, text, author, 0n})}

def parse_line_for.tokens(tokens: List<&2, String>, +endpoint: String) -> Maybe<&2, HistEntry>:
  match tokens:
    case Con{+version, Con{+server, Con{+target, Con{+kind, Con{+ts, Con{+author, Con{+text, Nil{}}}}}}}}:
      parse_line_for.valid(String.eq(version, "BIRC2") && Irc.ieq(server, endpoint)
        && Bool.not(String.is_empty(Cl.target_name(target))) && (String.eq(target, "*server*") || Cl.target_wire(target))
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

# Exclusion variant: imported archive rows (the drain's claimed IDs) become
# the next baseline instead of being appended again. Live rows are never
# excluded: claim sets only ever hold fresh import IDs.
def lines_after_except(lines: List<&2, Cl.Line>, +seq: Nat, +excluded: List<&2, Nat>) -> List<&2, Cl.Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+line, t}:
      match line:
        case Cl.Line{_, _, _, _, +id}:
          lines_after.keep(Nat.is_gt(id, seq) && Bool.not(List.contains(~Nat, ~Nat.is_eq, excluded, id)),
            line, lines_after_except(t, seq, excluded))

def extract_new_buf(+seq: Nat, b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, _, lines, _, _}:
      Bool.pick(String, Cl.target_is_synthetic(name), "", serialize_lines(name, lines_after(lines, seq)))

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
        Bool.pick(List<&2, HistEntry>, Cl.target_is_synthetic(name), Nil{}, new_entries.lines(lines_after(lines, seq), name, first)),
        new_entries(t, seq, False{}))

def new_entries_except(bufs: List<&2, Cl.Buffer>, +seq: Nat, first: Bool, +excluded: List<&2, Nat>) -> List<&2, HistEntry>:
  match bufs:
    case Nil{}: Nil{}
    case Con{Cl.Buffer{+name, _, _, lines, _, _}, t}:
      List.append(&2, HistEntry,
        Bool.pick(List<&2, HistEntry>, Cl.target_is_synthetic(name), Nil{}, new_entries.lines(lines_after_except(lines, seq, excluded), name, first)),
        new_entries_except(t, seq, False{}, excluded))

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

def extract_new_history_for_except(+endpoint: String, +old_cl: Cl.Client, new_cl: Cl.Client, +excluded: List<&2, Nat>) -> String:
  match new_cl:
    case Cl.Client{_, _, bufs, _, _, _, _, _}:
      serialize_entries(List.sort(~HistEntry, ~entry_id_le, new_entries_except(bufs, Cl.log_seq_of(old_cl), True{}, excluded)), endpoint)

# ---- applying history on load ---------------------------------------------

# The bounded buffer set follows target recency as well as per-buffer row
# recency. Restored IDs advance in file order, so each target's last row is
# its last use. Server and synthetic local tabs are never eviction candidates.
def last_id(lines: List<&2, Cl.Line>) -> Nat:
  match lines:
    case Nil{}: 0n
    case Con{Cl.Line{_, _, _, _, id}, Nil{}}: id
    case Con{_, rest}: last_id(rest)

type OldestTarget is Data:
  OldestTarget{index: Nat, id: Nat}

def oldest_target.choose(older: Bool, +i: Nat, +id: Nat, old: Maybe<&2, OldestTarget>) -> Maybe<&2, OldestTarget>:
  match older:
    case True{}: Some{OldestTarget{i, id}}
    case False{}: old

def oldest_target.compare(old: Maybe<&2, OldestTarget>, +i: Nat, +id: Nat) -> Maybe<&2, OldestTarget>:
  match old:
    case None{}: Some{OldestTarget{i, id}}
    case Some{OldestTarget{+oi, +oid}}: oldest_target.choose(Nat.is_lt(id, oid), i, id, Some{OldestTarget{oi, oid}})

def oldest_target.at(eligible: Bool, old: Maybe<&2, OldestTarget>, i: Nat, lines: List<&2, Cl.Line>) -> Maybe<&2, OldestTarget>:
  match eligible:
    case False{}: old
    case True{}: oldest_target.compare(old, i, last_id(lines))

def oldest_target(bufs: List<&2, Cl.Buffer>, +i: Nat, old: Maybe<&2, OldestTarget>) -> Maybe<&2, OldestTarget>:
  match bufs:
    case Nil{}: old
    case Con{Cl.Buffer{+name, _, _, lines, _, _}, rest}:
      oldest_target(rest, 1n+i, oldest_target.at(Nat.is_gt(i, 0n) && Bool.not(Cl.target_is_synthetic(name)), old, i, lines))

def evict_target.got(old: Maybe<&2, OldestTarget>, cl: Cl.Client) -> Cl.Client:
  match old:
    case None{}: cl
    case Some{OldestTarget{i, _}}: Cl.drop_buf(cl, i)

def evict_target(full: Bool, +cl: Cl.Client) -> Cl.Client:
  match full:
    case False{}: cl
    case True{}: evict_target.got(oldest_target(Cl.client_bufs(cl), 0n, None{}), cl)

def history_target.found(found: Maybe<&2, Nat>, +cl: Cl.Client, +target: String) -> Cl.Client & Maybe<&2, Nat>:
  match found:
    case Some{_}: Cl.buf_get(cl, target, Cl.target_channel(target), True{})
    case None{}:
      +bufs = Cl.client_bufs(cl)
      Cl.buf_get(evict_target(Nat.is_ge(Cl.buf_count(bufs), Cl.MAX_BUFFERS()) || Nat.is_ge(Cl.normal_buffer_count(bufs), Cl.NORMAL_BUFFERS()), cl), target, Cl.target_channel(target), True{})

def history_target.allowed(allowed: Bool, +cl: Cl.Client, +target: String) -> Cl.Client & Maybe<&2, Nat>:
  match allowed:
    case False{}: (cl, None{})
    case True{}: history_target.found(Cl.buf_find(cl, target), cl, target)

# Stored + channel identities are not message audiences. Only the historical
# @ audience alias is unambiguous: @ cannot begin an actual channel name.
def history_key.alias(alias: Bool, +name: String) -> String:
  match alias:
    case False{}: name
    case True{}: Irc.chan_target(name)

def history_key(+target: String) -> String:
  +name = Cl.target_name(target)
  history_key.alias(String.starts_with(name, "@"), name)

def history_target(+cl: Cl.Client, +target: String) -> Cl.Client & Maybe<&2, Nat>:
  +canonical = history_key(target)
  history_target.allowed(Cl.target_wire(canonical) && Bool.not(String.is_empty(canonical)), cl, canonical)

def apply_entry.bi(+cl: Cl.Client, +bi: Nat, ln: Cl.Line) -> Cl.Client:
  match ln:
    case Cl.Line{kind, +ts, +text, +author, _}:
      Cl.client_restore_author_ts(cl, bi, kind, ts, text, author)

def apply_entry.got(pair: Cl.Client & Maybe<&2, Nat>, ln: Cl.Line) -> Cl.Client:
  match pair:
    case (cl2, None{}): cl2
    case (cl2, Some{bi}): apply_entry.bi(cl2, bi, ln)

def apply_entry.target(is_srv: Bool, +cl: Cl.Client, +target: String, ln: Cl.Line) -> Cl.Client:
  match is_srv:
    case True{}: apply_entry.bi(cl, 0n, ln)
    case False{}: apply_entry.got(history_target(cl, target), ln)

def apply_entry(+cl: Cl.Client, +target: String, ln: Cl.Line) -> Cl.Client:
  # Only the synthetic control identity routes to index 0. A peer named
  # `server` is a query: buf_find skips control, target_name leaves the
  # plain name alone, and the BIRC2 loader already routes plain "server"
  # through history_target (only "*server*" parses to ServerEntry).
  apply_entry.target(Irc.ieq(target, "*server*"), cl, target, ln)

def apply_hist_entry(entry: HistEntry, cl: Cl.Client) -> Cl.Client:
  match entry:
    case ServerEntry{line}: apply_entry.bi(cl, 0n, line)
    case Entry{+target, line}: apply_entry.got(history_target(cl, target), line)

def apply_entries(entries: List<&2, HistEntry>, cl: Cl.Client) -> Cl.Client:
  match entries:
    case Nil{}: cl
    case Con{+e, t}:
      apply_entries(t, apply_hist_entry(e, cl))

def add_markers_cl(+cl: Cl.Client, +now: String) -> Cl.Client:
  Cl.reconnect_markers(cl, now)

def cap_buf_history(b: Cl.Buffer, cap: U32) -> Cl.Buffer:
  match b:
    case Cl.Buffer{+name, is_ch, +topic, +lines, +nicks, scroll}:
      Cl.Buffer{name, is_ch, topic, Bool.pick(List<&2, Cl.Line>, Cl.target_is_synthetic(name), lines, Cl.take_last(lines, U32.to_nat(cap))), nicks, scroll}

def cap_bufs_history(bufs: List<&2, Cl.Buffer>, +cap: U32) -> List<&2, Cl.Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{+b, t}:
      cap_buf_history(b, cap) <> cap_bufs_history(t, cap)

def apply_history.cap(cl: Cl.Client, +now: String, +cap: U32) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      Cl.reconnect_markers(Cl.Client{nick, server, cap_bufs_history(bufs, cap), active, now, stg, auth, log_seq}, now)

def apply_history.capped(zero: Bool, cl: Cl.Client, entries: List<&2, HistEntry>, now: String, cap: U32) -> Cl.Client:
  match zero:
    case True{}: apply_history.cap(cl, now, cap)
    case False{}: apply_history.cap(apply_entries(entries, cl), now, cap)

def apply_history(+cl: Cl.Client, entries: List<&2, HistEntry>, +now: String, +cap: U32) -> Cl.Client:
  apply_history.capped(U32.is_eq(cap, 0), cl, entries, now, cap)

# ---- file IO --------------------------------------------------------------

# Read complete UTF-8 records, not decoded chunks. A character may straddle a
# read boundary. The record bound also rejects a corrupt unterminated line.
type ReadState is Data:
  ReadState{cl: Cl.Client, rev: List<&2, U32>, count: Nat, dropping: Bool}

def cap_client_history(cl: Cl.Client, cap: U32) -> Cl.Client:
  match cl:
    case Cl.Client{nick, server, bufs, active, now, stg, auth, seq}:
      Cl.Client{nick, server, cap_bufs_history(bufs, cap), active, now, stg, auth, seq}

def read_record.present(entry: Maybe<&2, HistEntry>, cl: Cl.Client, cap: U32) -> Cl.Client:
  match entry:
    case None{}: cl
    case Some{entry}: cap_client_history(apply_hist_entry(entry, cl), cap)

def read_record.capped(zero: Bool, entry: Maybe<&2, HistEntry>, cl: Cl.Client, cap: U32) -> Cl.Client:
  match zero:
    case True{}: cl
    case False{}: read_record.present(entry, cl, cap)

def read_record.entry(entry: Maybe<&2, HistEntry>, cl: Cl.Client, +cap: U32) -> Cl.Client:
  read_record.capped(U32.is_eq(cap, 0), entry, cl, cap)

def read_record.utf8(text: Maybe<&2, String>, cl: Cl.Client, +endpoint: String, +cap: U32) -> Cl.Client:
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

def read_finish.client(snapshot: Bool, cl: Cl.Client, now: String) -> Cl.Client:
  match snapshot:
    case True{}: cl
    case False{}: Cl.reconnect_markers(cl, now)

# A worker snapshot spends its bounded row capacity only on archive records.
# The UI adds its divider after import, when spare capacity is known.
def read_finish.mode(snapshot: Bool, f: File, state: ReadState, now: String) -> IO(Cl.Client):
  match state:
    case ReadState{cl, _, _, _}:
      do IO<Cl.Client>:
        Unit <- File.close(f)
        return read_finish.client(snapshot, cl, now)

def read_failure_text(error: U32 & String, +stage: String) -> String:
  match error:
    case (code, +msg): "history " ++ stage ++ " (" ++ U32.show(code) ++ "): " ++ msg

# A failed load does not replace the current client or lose completed records.
# Close the descriptor before adding its visible, credential-free diagnostic.
def read_error(snapshot: Bool, cl: Cl.Client, error: U32 & String, stage: String) -> Cl.Client:
  match snapshot:
    case True{}: Cl.diagnostic(cl, Cl.Error{}, read_failure_text(error, stage))
    case False{}: Cl.client_log(cl, 0n, Cl.Error{}, read_failure_text(error, stage))

def read_failure.mode(+snapshot: Bool, f: File, state: ReadState, now: String, error: U32 & String, stage: String) -> IO(Cl.Client):
  do IO<Cl.Client>:
    cl : Cl.Client <- read_finish.mode(snapshot, f, state, now)
    return read_error(snapshot, cl, error, stage)

def read_loop.empty.mode(empty: Bool, snapshot: Bool, f: File, +bytes: List<&2, U32>, state: ReadState, endpoint: String, cap: U32, now: String, remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match empty:
    case True{}: read_finish.mode(snapshot, f, state, now)
    case False{}: next(f, read_chunk(bytes, state, endpoint, cap), Nat.sub(remaining, List.length(&2, U32, bytes)))

def read_loop.got.mode(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>, snapshot: Bool, state: ReadState, endpoint: String, cap: U32, now: String, remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match pair:
    case (f, Fail{error}): read_failure.mode(snapshot, f, state, now, error, "read failed; only completed records were restored")
    case (f, Done{+bytes}): read_loop.empty.mode(Nat.is_eq(List.length(&2, U32, bytes), 0n), snapshot, f, bytes, state, endpoint, cap, now, remaining, next)

def read_loop.got(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>, state: ReadState, endpoint: String, cap: U32, now: String, remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  read_loop.got.mode(pair, False{}, state, endpoint, cap, now, remaining, next)

def read_loop.read.mode(done: Bool, +snapshot: Bool, f: File, state: ReadState, +endpoint: String, +cap: U32, +now: String, +remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match done:
    case True{}: read_finish.mode(snapshot, f, state, now)
    case False{}:
      do IO<Cl.Client>:
        pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, U32.from_nat(Cl.clamp_nat(remaining, 4096n)))
        read_loop.got.mode(pair, snapshot, state, endpoint, cap, now, remaining, next)

# The file's initial size bounds the loop. Appends during loading cannot keep it
# alive forever. Short reads still consume the full snapshot; state holds at most 8192 bytes and
# MAX_BUFFERS * min(cap, SCROLL_CAP) lines, regardless of file size.
def read_loop.mode(fuel: Nat, +snapshot: Bool, f: File, state: ReadState, +endpoint: String, +cap: U32, +now: String, +remaining: Nat) -> IO(Cl.Client):
  match fuel:
    case 0n: read_finish.mode(snapshot, f, state, now)
    case 1n+p:
      read_loop.read.mode(Nat.is_eq(remaining, 0n), snapshot, f, state, endpoint, cap, now, remaining,
        f2 => st2 => rest => read_loop.mode(p, snapshot, f2, st2, endpoint, cap, now, rest))

def read_size.mode(pair: File & Result<&1, &1, U32 & String, U32>, snapshot: Bool, cl: Cl.Client, endpoint: String, cap: U32, now: String) -> IO(Cl.Client):
  match pair:
    case (f, Fail{error}): read_failure.mode(snapshot, f, ReadState{cl, Nil{}, 0n, False{}}, now, error, "size unavailable")
    case (f, Done{+size}): read_loop.mode(1n+U32.to_nat(size), snapshot, f, ReadState{cl, Nil{}, 0n, False{}}, endpoint, cap, now, U32.to_nat(size))

# ENOENT is the normal first-run case on this POSIX runtime. Other open
# failures must be visible; an inaccessible history file is not an empty one.
def read_open.error.mode(missing: Bool, snapshot: Bool, cl: Cl.Client, error: U32 & String) -> IO(Cl.Client):
  match missing:
    case True{}: IO.pure(Cl.Client, cl)
    case False{}: IO.pure(Cl.Client, read_error(snapshot, cl, error, "open failed"))

def read_open.failed.mode(error: U32 & String, snapshot: Bool, cl: Cl.Client) -> IO(Cl.Client):
  match error:
    case (+code, +msg): read_open.error.mode(U32.is_eq(code, 2), snapshot, cl, (code, msg))

def read_open.mode(result: Result<&1, &1, U32 & String, File>, +snapshot: Bool, cl: Cl.Client, +endpoint: String, +cap: U32, +now: String) -> IO(Cl.Client):
  match result:
    case Fail{error}: read_open.failed.mode(error, snapshot, cl)
    case Done{f}:
      do IO<Cl.Client>:
        pair : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
        read_size.mode(pair, snapshot, cl, endpoint, cap, now)

def read_open(result: Result<&1, &1, U32 & String, File>, cl: Cl.Client, endpoint: String, cap: U32, now: String) -> IO(Cl.Client):
  read_open.mode(result, False{}, cl, endpoint, cap, now)

def history_snapshot_client(+path: String, +endpoint: String, +cap: U32, cl: Cl.Client) -> IO(Cl.Client):
  do IO<Cl.Client>:
    result : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read_open.mode(result, True{}, cl, endpoint, cap, "")

def save_error(error: U32 & String, +stage: String) -> String:
  match error:
    case (code, _): "history save " ++ stage ++ " (" ++ U32.show(code) ++ ")"

def save_result(result: Result<&1, &1, U32 & String, Unit>) -> Maybe<&2, String>:
  match result:
    case Done{_}: None{}
    case Fail{error}: Some{save_error(error, "write failed")}

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
