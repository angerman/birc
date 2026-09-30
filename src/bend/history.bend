# Persisted IRC chat scrollback history across sessions with reconnect markers.
import Base
import ./buffer.bend as Cl
import ./irc.bend as Irc

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

def is_reconnect_marker(+text: String) -> Bool:
  String.contains(text, "Reconnected:")

def serialize_line.recon(is_recon: Bool, +target: String, kind: Cl.LineKind, +ts: String, +text: String) -> String:
  match is_recon:
    case True{}: ""
    case False{}: target ++ "\t" ++ serialize_kind(kind) ++ "\t" ++ ts ++ "\t" ++ text ++ "\n"

def serialize_line(+target: String, +ln: Cl.Line) -> String:
  match ln:
    case Cl.Line{kind, +ts, +text, +author, +id}:
      serialize_line.recon(is_reconnect_marker(text), target, kind, ts, text)

def serialize_lines.go(+target: String, lines: List<&2, Cl.Line>, +acc: String) -> String:
  match lines:
    case Nil{}: acc
    case Con{+h, t}:
      serialize_lines.go(target, t, acc ++ serialize_line(target, h))

def serialize_lines(+target: String, lines: List<&2, Cl.Line>) -> String:
  serialize_lines.go(target, lines, "")

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

def parse_line_tokens(+tokens: List<&2, String>) -> Maybe<&2, HistEntry>:
  match tokens:
    case Con{+target, rest1}:
      match rest1:
        case Con{+kstr, rest2}:
          match rest2:
            case Con{+ts, rest3}:
              Some{Entry{target, Cl.Line{parse_kind(kstr), ts, join_tokens(rest3), "", 0n}}}
            case Nil{}: None{}
        case Nil{}: None{}
    case Nil{}: None{}

def parse_line.empty(empty: Bool, +raw: String) -> Maybe<&2, HistEntry>:
  match empty:
    case True{}: None{}
    case False{}: parse_line_tokens(String.split(raw, Chr{9}))

def parse_line(+raw: String) -> Maybe<&2, HistEntry>:
  parse_line.empty(String.is_empty(raw), raw)

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

def kind_eq(k1: Cl.LineKind, k2: Cl.LineKind) -> Bool:
  match k1:
    case Cl.Msg{}:
      match k2:
        case Cl.Msg{}: True{}
        case _: False{}
    case Cl.Self{}:
      match k2:
        case Cl.Self{}: True{}
        case _: False{}
    case Cl.System{}:
      match k2:
        case Cl.System{}: True{}
        case _: False{}
    case Cl.Action{}:
      match k2:
        case Cl.Action{}: True{}
        case _: False{}
    case Cl.Notice{}:
      match k2:
        case Cl.Notice{}: True{}
        case _: False{}
    case Cl.Error{}:
      match k2:
        case Cl.Error{}: True{}
        case _: False{}
    case Cl.Highlight{}:
      match k2:
        case Cl.Highlight{}: True{}
        case _: False{}

def line_eq(l1: Cl.Line, l2: Cl.Line) -> Bool:
  match l1:
    case Cl.Line{k1, +ts1, +t1, +author, +id}:
      match l2:
        case Cl.Line{k2, +ts2, +t2, +author, +id}:
          kind_eq(k1, k2) && String.eq(ts1, ts2) && String.eq(t1, t2)

def take_last_lines(+xs: List<&2, Cl.Line>, n: Nat) -> List<&2, Cl.Line>:
  List.drop(&2, Cl.Line, xs, Nat.sub(List.length(&2, Cl.Line, xs), n))

def take_until_last.step(same: Bool, +h: Cl.Line, +cont: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match same:
    case True{}: Nil{}
    case False{}: h <> cont

def take_until_last(rev_new: List<&2, Cl.Line>, +last_old: Cl.Line) -> List<&2, Cl.Line>:
  match rev_new:
    case Nil{}: Nil{}
    case Con{+h, t}:
      take_until_last.step(line_eq(h, last_old), h, take_until_last(t, last_old))

def lines_added.check_rev(rev_old: List<&2, Cl.Line>, +new_lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match rev_old:
    case Nil{}: new_lines
    case Con{+last_old, _}:
      List.reverse(&2, Cl.Line, take_until_last(List.reverse(&2, Cl.Line, new_lines), last_old))

def lines_added.check_cap(+old_lines: List<&2, Cl.Line>, +new_lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  lines_added.check_rev(List.reverse(&2, Cl.Line, old_lines), new_lines)

def lines_added.lens(diff: Nat, +old_lines: List<&2, Cl.Line>, +new_lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match diff:
    case 0n: lines_added.check_cap(old_lines, new_lines)
    case 1n+p: take_last_lines(new_lines, diff)

def lines_added(+old_lines: List<&2, Cl.Line>, +new_lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  lines_added.lens(
    Nat.sub(List.length(&2, Cl.Line, new_lines), List.length(&2, Cl.Line, old_lines)),
    old_lines,
    new_lines
  )

def find_buf_lines.rest(lines: List<&2, Cl.Line>, cont: Maybe<&2, List<&2, Cl.Line>>, hit: Bool) -> Maybe<&2, List<&2, Cl.Line>>:
  match hit:
    case True{}: Some{lines}
    case False{}: cont

def find_buf_lines(bufs: List<&2, Cl.Buffer>, +name: String) -> Maybe<&2, List<&2, Cl.Line>>:
  match bufs:
    case Nil{}: None{}
    case Con{h, t}:
      match h:
        case Cl.Buffer{+bname, _, _, lines, _, _}:
          find_buf_lines.rest(lines, find_buf_lines(t, name), String.eq(bname, name))

def extract_lines_against_old(old_m: Maybe<&2, List<&2, Cl.Line>>, lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match old_m:
    case None{}: lines
    case Some{old_lines}:
      lines_added(old_lines, lines)

def extract_new_buf.named(is_special: Bool, old_bufs: List<&2, Cl.Buffer>, +name: String, lines: List<&2, Cl.Line>) -> String:
  match is_special:
    case True{}: ""
    case False{}:
      serialize_lines(name, extract_lines_against_old(find_buf_lines(old_bufs, name), lines))

def extract_new_buf(old_bufs: List<&2, Cl.Buffer>, +new_b: Cl.Buffer) -> String:
  match new_b:
    case Cl.Buffer{+name, _, _, lines, _, _}:
      extract_new_buf.named(String.starts_with(name, "*"), old_bufs, name, lines)

def extract_new_bufs.go(new_bufs: List<&2, Cl.Buffer>, +old_bufs: List<&2, Cl.Buffer>, +acc: String) -> String:
  match new_bufs:
    case Nil{}: acc
    case Con{+b, t}:
      extract_new_bufs.go(t, old_bufs, acc ++ extract_new_buf(old_bufs, b))

def extract_new_bufs(+old_bufs: List<&2, Cl.Buffer>, new_bufs: List<&2, Cl.Buffer>) -> String:
  extract_new_bufs.go(new_bufs, old_bufs, "")

def extract_new_history(old_cl: Cl.Client, new_cl: Cl.Client) -> String:
  match old_cl:
    case Cl.Client{_, _, +old_bufs, _, _, _, +auth, +log_seq}:
      match new_cl:
        case Cl.Client{_, _, new_bufs, _, _, _, +auth, +log_seq}:
          extract_new_bufs(old_bufs, new_bufs)

# ---- applying history on load ---------------------------------------------

def apply_entry.bi(+cl: Cl.Client, +bi: Nat, ln: Cl.Line) -> Cl.Client:
  match ln:
    case Cl.Line{kind, +ts, +text, +author, +id}:
      Cl.buf_modify_client(cl, bi, b => Cl.buf_log_ts(b, kind, ts, text))

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

def apply_entries(entries: List<&2, HistEntry>, cl: Cl.Client) -> Cl.Client:
  match entries:
    case Nil{}: cl
    case Con{+e, t}:
      match e:
        case Entry{+target, ln}:
          apply_entries(t, apply_entry(cl, target, ln))

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
      Cl.buf_log_ts(b, Cl.System{}, "", "--- Reconnected: " ++ now ++ " ---")

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
      Cl.Client{nick, server, add_markers_bufs(bufs, now), active, now_old, stg, auth, log_seq}

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

def history_read_file.result(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{_}: ""
    case Done{+s}: s

def history_read_file.got(pair: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match pair:
    case (f, r):
      do IO<String>:
        Unit <- File.close(f)
        IO.pure(String, history_read_file.result(r))

def history_read_file.open(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{_}:
      IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        pair : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        history_read_file.got(pair)

def history_read_file.check(empty: Bool, +path: String) -> IO(String):
  match empty:
    case True{}:
      IO.pure(String, "")
    case False{}:
      do IO<String>:
        r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        history_read_file.open(r)

def history_read_file(+path: String) -> IO(String):
  history_read_file.check(String.is_empty(path), path)

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

def history_init_client.pick(empty: Bool, +path: String, +cap: U32, +nick: String, +host: String, +now: String) -> IO(Cl.Client):
  match empty:
    case True{}:
      IO.pure(Cl.Client, Cl.init_with_cap(nick, host, cap))
    case False{}:
      do IO<Cl.Client>:
        content : String <- history_read_file(path)
        return history_init_client.content(content, nick, host, now, cap)

def history_init_client(+path: String, +cap: U32, +nick: String, +host: String, +now: String) -> IO(Cl.Client):
  history_init_client.pick(String.is_empty(path), path, cap, nick, host, now)

def maybe_save_history.check(enabled: Bool, +path: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Unit):
  match enabled:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      history_append_file(path, extract_new_history(old_cl, new_cl))

def maybe_save_history(+path: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Unit):
  maybe_save_history.check(
    Bool.not(String.is_empty(path)) && Cl.settings_history(Cl.get_settings(new_cl)),
    path, old_cl, new_cl
  )
