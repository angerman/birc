# IRC client state + feed (M1). Pure. Uses Irc.parse/classify.
import Base
import ./irc.bend as Irc

def MAX_BUFFERS() -> Nat:
  16n

def SCROLL_CAP() -> Nat:
  512n

def MAX_NICKS() -> Nat:
  256n

type LineKind is Data:
  Msg{}
  Self{}
  System{}
  Action{}
  Notice{}
  Error{}

type Line is Data:
  Line{kind: LineKind, ts: String, text: String}

type Buffer is Data:
  Buffer{
    name: String,
    is_channel: Bool,
    topic: String,
    lines: List<&2, Line>,
    nicks: List<&2, String>,
    scroll: Nat
  }

type Client is Data:
  Client{
    nick: String,
    server: String,
    bufs: List<&2, Buffer>,
    active: Nat,
    now: String
  }

# ---- init ---------------------------------------------------------------

def server_buf() -> Buffer:
  Buffer{"server", False{}, "", Nil{}, Nil{}, 0n}

def init(+nick: String, +server: String) -> Client:
  Client{nick, server, server_buf() <> Nil{}, 0n, ""}

# ---- list helpers -------------------------------------------------------

def nth_buf(+bufs: List<&2, Buffer>, +i: Nat) -> Maybe<&2, Buffer>:
  List.get(&2, Buffer, bufs, i)

def set_nth_buf(+bufs: List<&2, Buffer>, +i: Nat, +b: Buffer) -> List<&2, Buffer>:
  List.set(&2, Buffer, bufs, i, b)

def buf_count(+bufs: List<&2, Buffer>) -> Nat:
  List.length(&2, Buffer, bufs)

# ---- buffer find/get ----------------------------------------------------

type FindAcc is Data:
  FindAcc{name: String, i: Nat, found: Maybe<&2, Nat>}

def buf_find.hit.if(eq: Bool, +name: String, +i: Nat) -> FindAcc:
  match eq:
    case True{}:
      FindAcc{name, 1n+i, Some{i}}
    case False{}:
      FindAcc{name, 1n+i, None{}}

def buf_find.hit.skip(+name: String, +i: Nat, +n: String, skip: Bool) -> FindAcc:
  match skip:
    case True{}:
      FindAcc{name, 1n+i, None{}}
    case False{}:
      buf_find.hit.if(Irc.ieq(n, name), name, i)

def buf_find.hit(+name: String, +i: Nat, +n: String) -> FindAcc:
  buf_find.hit.skip(name, i, n, Nat.is_eq(i, 0n))

def buf_find.step(st: FindAcc, h: Buffer) -> FindAcc:
  match st:
    case FindAcc{+name, +i, found}:
      match found:
        case Some{j}:
          FindAcc{name, i, Some{j}}
        case None{}:
          match h:
            case Buffer{+n, _, _, _, _, _}:
              buf_find.hit(name, i, n)

def buf_find.fin(st: FindAcc) -> Maybe<&2, Nat>:
  match st:
    case FindAcc{_, _, found}:
      found

def buf_find(+cl: Client, +name: String) -> Maybe<&2, Nat>:
  match cl:
    case Client{_, _, +bufs, _, _}:
      buf_find.fin(List.foldl(~&2, ~Buffer, ~FindAcc, ~buf_find.step, bufs, FindAcc{name, 0n, None{}}))

def empty_buf(+name: String, is_channel: Bool) -> Buffer:
  Buffer{Irc.sanitize_in(name), is_channel, "", Nil{}, Nil{}, 0n}

def cap_note(+b: Buffer, +now: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, List.append(&2, Line, lines, Line{Error{}, Irc.sanitize_in(now), "buffer limit reached"} <> Nil{}), nicks, scroll}

def buf_get.full(got: Maybe<&2, Buffer>, +nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String) -> Client & Maybe<&2, Nat>:
  match got:
    case None{}:
      (Client{nick, server, bufs, active, now}, None{})
    case Some{b}:
      (Client{nick, server, set_nth_buf(bufs, 0n, cap_note(b, now)), active, now}, None{})

def buf_get.create.cap(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +name: String, is_channel: Bool, full: Bool) -> Client & Maybe<&2, Nat>:
  match full:
    case True{}:
      buf_get.full(nth_buf(bufs, 0n), nick, server, bufs, active, now)
    case False{}:
      +b = empty_buf(name, is_channel)
      +i = buf_count(bufs)
      +bufs2 = List.append(&2, Buffer, bufs, b <> Nil{})
      (Client{nick, server, bufs2, active, now}, Some{i})

def buf_get.create(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +name: String, is_channel: Bool) -> Client & Maybe<&2, Nat>:
  buf_get.create.cap(nick, server, bufs, active, now, name, is_channel, Nat.is_ge(buf_count(bufs), MAX_BUFFERS()))

def buf_get.miss(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +name: String, is_channel: Bool, create: Bool) -> Client & Maybe<&2, Nat>:
  match create:
    case False{}:
      (Client{nick, server, bufs, active, now}, None{})
    case True{}:
      buf_get.create(nick, server, bufs, active, now, name, is_channel)

def buf_get.found(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +name: String, is_channel: Bool, create: Bool, found: Maybe<&2, Nat>) -> Client & Maybe<&2, Nat>:
  match found:
    case Some{i}:
      (Client{nick, server, bufs, active, now}, Some{i})
    case None{}:
      buf_get.miss(nick, server, bufs, active, now, name, is_channel, create)

def buf_get.fin(+cl: Client, +name: String, is_channel: Bool, create: Bool, found: Maybe<&2, Nat>) -> Client & Maybe<&2, Nat>:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      buf_get.found(nick, server, bufs, active, now, name, is_channel, create, found)

def buf_get(+cl: Client, +name: String, is_channel: Bool, create: Bool) -> Client & Maybe<&2, Nat>:
  buf_get.fin(cl, name, is_channel, create, buf_find(cl, name))

# ---- scrollback ---------------------------------------------------------

# Keep the last n lines in original order (oldest → newest). Reverse + cons
# already restores order; a second reverse was flipping the log on every append.
def take_last.go(+xs: List<&2, Line>, n: Nat, acc: List<&2, Line>) -> List<&2, Line>:
  match xs:
    case Nil{}:
      acc
    case Con{+h, t}:
      match n:
        case 0n:
          acc
        case 1n+p:
          take_last.go(t, p, h <> acc)

def take_last(+xs: List<&2, Line>, n: Nat) -> List<&2, Line>:
  take_last.go(List.reverse(&2, Line, xs), n, Nil{})

def buf_log.scroll.on(gt: Bool, +scroll: Nat) -> Nat:
  match gt:
    case True{}:
      1n+scroll
    case False{}:
      0n

def buf_log.scroll(+scroll: Nat) -> Nat:
  buf_log.scroll.on(Nat.is_gt(scroll, 0n), scroll)

def buf_log_ts(+b: Buffer, kind: LineKind, +ts: String, +text: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      +lines2 = take_last(List.append(&2, Line, lines, Line{kind, Irc.sanitize_in(ts), Irc.sanitize_in(text)} <> Nil{}), SCROLL_CAP())
      Buffer{name, ch, topic, lines2, nicks, buf_log.scroll(scroll)}

# Tests pass ts="" (init.now is empty). Live/demo set Client.now at the IO
# edge before feed/submit so buf_log_ts stores HH:MM:SS at log time.
def buf_log(+b: Buffer, kind: LineKind, +text: String) -> Buffer:
  buf_log_ts(b, kind, "", text)

def client_log.on(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +i: Nat, kind: LineKind, +text: String, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      Client{nick, server, set_nth_buf(bufs, i, buf_log_ts(b, kind, now, text)), active, now}

def client_log(+cl: Client, +i: Nat, kind: LineKind, +text: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      client_log.on(nick, server, bufs, active, now, i, kind, text, nth_buf(bufs, i))

def set_now(+cl: Client, +ts: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, _}:
      Client{nick, server, bufs, active, ts}

def strip_cr.on(+s: String, cr: Bool) -> String:
  match cr:
    case True{}:
      String.take(s, Nat.sub(String.length(s), 1n))
    case False{}:
      s

def strip_cr.rev(+s: String, rev: String) -> String:
  match rev:
    case SNil{}:
      s
    case SCon{+h, _}:
      strip_cr.on(s, Irc.code_is(h, 13))

def strip_cr(+s: String) -> String:
  strip_cr.rev(s, String.reverse(s))

def replay_keep.cons(acc: List<&2, String>, +s: String, empty: Bool) -> List<&2, String>:
  match empty:
    case True{}:
      acc
    case False{}:
      s <> acc

def replay_step(acc: List<&2, String>, h: String) -> List<&2, String>:
  +s = strip_cr(h)
  replay_keep.cons(acc, s, String.is_empty(s))

def replay_lines(+text: String) -> List<&2, String>:
  List.reverse(&2, String, List.foldl(~&2, ~String, ~List<&2, String>, ~replay_step, String.lines(text), Nil{}))

# ---- nicks --------------------------------------------------------------

type StripPhase is Data:
  StRead{}
  StDecide{}

def is_sigil(+c: Char) -> Bool:
  Irc.code_is(c, 64) || Irc.code_is(c, 43) || Irc.code_is(c, 126) || Irc.code_is(c, 38) || Irc.code_is(c, 37)

def nick_strip.go(fuel: Nat, phase: StripPhase, s: String, h: Char, sig: Bool) -> String:
  match fuel:
    case 0n:
      s
    case 1n+p:
      match phase:
        case StRead{}:
          match s:
            case SNil{}:
              SNil{}
            case SCon{+hd, t}:
              nick_strip.go(p, StDecide{}, t, hd, is_sigil(hd))
        case StDecide{}:
          match sig:
            case True{}:
              nick_strip.go(p, StRead{}, s, h, False{})
            case False{}:
              SCon{h, s}

def nick_strip(+s: String) -> String:
  nick_strip.go(Nat.add(1n, Nat.mul(2n, String.length(s))), StRead{}, s, Chr{0}, False{})

def nick_len(+ns: List<&2, String>) -> Nat:
  List.length(&2, String, ns)

type HasAcc is Data:
  HasAcc{nick: String, found: Bool}

def nick_has.miss.if(eq: Bool, +nick: String) -> HasAcc:
  match eq:
    case True{}:
      HasAcc{nick, True{}}
    case False{}:
      HasAcc{nick, False{}}

def nick_has.miss(+nick: String, h: String) -> HasAcc:
  nick_has.miss.if(Irc.ieq(h, nick), nick)

def nick_has.step(st: HasAcc, h: String) -> HasAcc:
  match st:
    case HasAcc{+nick, found}:
      match found:
        case True{}:
          HasAcc{nick, True{}}
        case False{}:
          nick_has.miss(nick, h)

def nick_has.fin(st: HasAcc) -> Bool:
  match st:
    case HasAcc{_, found}:
      found

def nick_has(+b: Buffer, +nick: String) -> Bool:
  match b:
    case Buffer{_, _, _, _, +nicks, _}:
      nick_has.fin(List.foldl(~&2, ~String, ~HasAcc, ~nick_has.step, nicks, HasAcc{nick, False{}}))

def nick_add.keep(+b: Buffer, skip: Bool, +nick: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      match skip:
        case True{}:
          Buffer{name, ch, topic, lines, nicks, scroll}
        case False{}:
          Buffer{name, ch, topic, lines, List.append(&2, String, nicks, nick <> Nil{}), scroll}

def nick_add.body(+b: Buffer, +nick: String, empty: Bool) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      match empty:
        case True{}:
          Buffer{name, ch, topic, lines, nicks, scroll}
        case False{}:
          nick_add.keep(
            Buffer{name, ch, topic, lines, nicks, scroll},
            nick_has(Buffer{name, ch, topic, lines, nicks, scroll}, nick) || Nat.is_ge(nick_len(nicks), MAX_NICKS()),
            nick)

def nick_add(+b: Buffer, +raw: String) -> Buffer:
  +n = nick_strip(raw)
  nick_add.body(b, n, String.is_empty(n))

def nick_add_idx.on(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +i: Nat, +who: String, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      Client{nick, server, set_nth_buf(bufs, i, nick_add(b, who)), active, now}

def nick_add_idx(+cl: Client, +i: Nat, +who: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      nick_add_idx.on(nick, server, bufs, active, now, i, who, nth_buf(bufs, i))

type DelAcc is Data:
  DelAcc{nick: String, done: Bool, acc: List<&2, String>}

def nick_del.keep.if(eq: Bool, +nick: String, h: String, acc: List<&2, String>) -> DelAcc:
  match eq:
    case True{}:
      DelAcc{nick, True{}, acc}
    case False{}:
      DelAcc{nick, False{}, h <> acc}

def nick_del.keep(+nick: String, +h: String, acc: List<&2, String>) -> DelAcc:
  nick_del.keep.if(Irc.ieq(h, nick), nick, h, acc)

def nick_del.step(st: DelAcc, h: String) -> DelAcc:
  match st:
    case DelAcc{+nick, done, acc}:
      match done:
        case True{}:
          DelAcc{nick, True{}, h <> acc}
        case False{}:
          nick_del.keep(nick, h, acc)

def nick_del.fin(st: DelAcc) -> List<&2, String>:
  match st:
    case DelAcc{_, _, acc}:
      List.reverse(&2, String, acc)

def nick_del(+b: Buffer, +raw: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      +nick = nick_strip(raw)
      Buffer{name, ch, topic, lines, nick_del.fin(List.foldl(~&2, ~String, ~DelAcc, ~nick_del.step, nicks, DelAcc{nick, False{}, Nil{}})), scroll}

type RenAcc is Data:
  RenAcc{from: String, to: String, done: Bool, acc: List<&2, String>}

def nick_rename.keep.if(eq: Bool, +from: String, +to: String, h: String, acc: List<&2, String>) -> RenAcc:
  match eq:
    case True{}:
      RenAcc{from, to, True{}, to <> acc}
    case False{}:
      RenAcc{from, to, False{}, h <> acc}

def nick_rename.keep(+from: String, +to: String, +h: String, acc: List<&2, String>) -> RenAcc:
  nick_rename.keep.if(Irc.ieq(h, from), from, to, h, acc)

def nick_rename.step(st: RenAcc, h: String) -> RenAcc:
  match st:
    case RenAcc{+from, +to, done, acc}:
      match done:
        case True{}:
          RenAcc{from, to, True{}, h <> acc}
        case False{}:
          nick_rename.keep(from, to, h, acc)

def nick_rename.fin(st: RenAcc) -> List<&2, String>:
  match st:
    case RenAcc{_, _, _, acc}:
      List.reverse(&2, String, acc)

def nick_rename(+b: Buffer, +from: String, +to: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, lines, nick_rename.fin(List.foldl(~&2, ~String, ~RenAcc, ~nick_rename.step, nicks, RenAcc{nick_strip(from), nick_strip(to), False{}, Nil{}})), scroll}

# ---- set topic / active / nick ------------------------------------------

def set_topic(+b: Buffer, +topic: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, _, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, lines, nicks, scroll}

def set_active(+cl: Client, +i: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, _, +now}:
      Client{nick, server, bufs, i, now}

def set_active_clamp.on(+cl: Client, +i: Nat, ok: Bool) -> Client:
  match ok:
    case True{}:
      set_active(cl, i)
    case False{}:
      cl

def set_active_clamp(+cl: Client, +i: Nat) -> Client:
  match cl:
    case Client{_, _, +bufs, _, _}:
      set_active_clamp.on(cl, i, Nat.is_lt(i, buf_count(bufs)))

def set_buf_scroll(+b: Buffer, +sc: Nat) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, _}:
      Buffer{name, ch, topic, lines, nicks, sc}

def set_buf_name(+b: Buffer, +name: String) -> Buffer:
  match b:
    case Buffer{_, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, lines, nicks, scroll}

def snap_active.got(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      Client{nick, server, set_nth_buf(bufs, active, set_buf_scroll(b, 0n)), active, now}

def snap_active(+cl: Client) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      snap_active.got(nick, server, bufs, active, now, nth_buf(bufs, active))

def scroll_add_nat(+scroll: Nat, +up: Nat, +dn: Nat) -> Nat:
  Nat.sub(Nat.add(scroll, up), dn)

def clamp_nat.on(+n: Nat, +maxs: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      maxs
    case False{}:
      n

def clamp_nat(+n: Nat, +maxs: Nat) -> Nat:
  clamp_nat.on(n, maxs, Nat.is_ge(n, maxs))

def apply_buf_scroll.on(+b: Buffer, +up: Nat, +dn: Nat) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{
        name,
        ch,
        topic,
        lines,
        nicks,
        clamp_nat(scroll_add_nat(scroll, up, dn), List.length(&2, Line, lines))
      }

def apply_active_scroll.got(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +up: Nat, +dn: Nat, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      Client{nick, server, set_nth_buf(bufs, active, apply_buf_scroll.on(b, up, dn)), active, now}

def apply_active_scroll(+cl: Client, +up: Nat, +dn: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      apply_active_scroll.got(nick, server, bufs, active, now, up, dn, nth_buf(bufs, active))

def buf_scroll_of.on(got: Maybe<&2, Buffer>) -> Nat:
  match got:
    case None{}:
      0n
    case Some{b}:
      match b:
        case Buffer{_, _, _, _, _, +scroll}:
          scroll

def buf_scroll_of(+cl: Client, +i: Nat) -> Nat:
  match cl:
    case Client{_, _, +bufs, _, _}:
      buf_scroll_of.on(nth_buf(bufs, i))

def active_of(+cl: Client) -> Nat:
  match cl:
    case Client{_, _, _, +active, _}:
      active

def cycle_next.i.on(wrap: Bool, +active: Nat) -> Nat:
  match wrap:
    case True{}:
      0n
    case False{}:
      Nat.add(active, 1n)

def cycle_next.i(+active: Nat, +n: Nat) -> Nat:
  cycle_next.i.on(Nat.is_eq(Nat.add(active, 1n), n), active)

def cycle_prev.i.on(z: Bool, +active: Nat, +n: Nat) -> Nat:
  match z:
    case True{}:
      Nat.sub(n, 1n)
    case False{}:
      Nat.sub(active, 1n)

def cycle_prev.i(+active: Nat, +n: Nat) -> Nat:
  cycle_prev.i.on(Nat.is_eq(active, 0n), active, n)

def cycle_next(+cl: Client) -> Client:
  match cl:
    case Client{_, _, +bufs, +active, _}:
      set_active(cl, cycle_next.i(active, buf_count(bufs)))

def cycle_prev(+cl: Client) -> Client:
  match cl:
    case Client{_, _, +bufs, +active, _}:
      set_active(cl, cycle_prev.i(active, buf_count(bufs)))

def cycle_tab.pick(+cl: Client, next: Bool, prev: Bool) -> Client:
  match next:
    case True{}:
      cycle_next(cl)
    case False{}:
      match prev:
        case True{}:
          cycle_prev(cl)
        case False{}:
          cl

# dir 1 = next, 2 = prev, else no-op.
def cycle_tab(+cl: Client, +dir: U32) -> Client:
  cycle_tab.pick(cl, U32.is_eq(dir, 1), U32.is_eq(dir, 2))

def set_nick(+cl: Client, +nick: String) -> Client:
  match cl:
    case Client{_, +server, +bufs, +active, +now}:
      Client{nick, server, bufs, active, now}

def set_server(+cl: Client, +server: String) -> Client:
  match cl:
    case Client{+nick, _, +bufs, +active, +now}:
      Client{nick, server, bufs, active, now}

# ---- drop buffer (PART/KICK self) ---------------------------------------

def remove_buf(+bufs: List<&2, Buffer>, +i: Nat) -> List<&2, Buffer>:
  +xs = bufs
  List.append(&2, Buffer, List.take(&2, Buffer, xs, i), List.drop(&2, Buffer, xs, 1n+i))

def clamp_active.pick(+last: Nat, +active: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      last
    case False{}:
      active

def clamp_active.ge(+nbufs: Nat, +active: Nat, ge: Bool) -> Nat:
  match nbufs:
    case 0n:
      0n
    case 1n+p:
      clamp_active.pick(p, active, ge)

def clamp_active(+nbufs: Nat, +active: Nat) -> Nat:
  clamp_active.ge(nbufs, active, Nat.is_ge(active, nbufs))

def drop_buf.act(+active: Nat, +bi: Nat, +nbufs2: Nat, shift: Bool) -> Nat:
  match shift:
    case True{}:
      Nat.sub(active, 1n)
    case False{}:
      clamp_active(nbufs2, active)

def drop_buf.go(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat) -> Client:
  +bufs2 = remove_buf(bufs, bi)
  Client{nick, server, bufs2, drop_buf.act(active, bi, buf_count(bufs2), Nat.is_gt(active, bi)), now}

def drop_buf.body(+cl: Client, +bi: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      drop_buf.go(nick, server, bufs, active, now, bi)

def drop_buf.keep(+cl: Client, +bi: Nat, is_server: Bool) -> Client:
  match is_server:
    case True{}:
      cl
    case False{}:
      drop_buf.body(cl, bi)

def drop_buf(+cl: Client, +bi: Nat) -> Client:
  drop_buf.keep(cl, bi, Nat.is_eq(bi, 0n))

def drop_buf.at(+cl: Client, found: Maybe<&2, Nat>) -> Client:
  match found:
    case None{}:
      cl
    case Some{+bi}:
      drop_buf(cl, bi)

# ---- format helpers -----------------------------------------------------

def msg_nick(+m: Irc.Message) -> String:
  match m:
    case Irc.Message{+nick, _, _, _}:
      nick

def fmt_msg.empty(empty: Bool, +nick: String, +body: String) -> String:
  match empty:
    case True{}:
      "<*> " ++ body
    case False{}:
      "<" ++ nick ++ "> " ++ body

def fmt_msg(+nick: String, +body: String) -> String:
  fmt_msg.empty(String.is_empty(nick), nick, body)

def fmt_action(+nick: String, +body: String) -> String:
  "* " ++ nick ++ " " ++ body

def fmt_join(+nick: String, +chan: String) -> String:
  "-> " ++ nick ++ " joined " ++ chan

def fmt_part(+nick: String, +chan: String) -> String:
  "<- " ++ nick ++ " left " ++ chan

def fmt_quit(+nick: String, +reason: String) -> String:
  "<- " ++ nick ++ " quit (" ++ reason ++ ")"

def fmt_nick_chg(+from: String, +to: String) -> String:
  from ++ " is now known as " ++ to

def fmt_topic_set(+nick: String, +topic: String) -> String:
  nick ++ " set topic: " ++ topic

def fmt_num(+code: U32, +text: String) -> String:
  "[" ++ U32.show(code) ++ "] " ++ text

def fmt_err(+text: String) -> String:
  "ERROR " ++ text

def fmt_unk(+cmd: String, +p0: String) -> String:
  cmd ++ " " ++ p0

def join_sp.go(+ps: List<&2, String>, +acc: String) -> String:
  match ps:
    case Nil{}:
      acc
    case Con{+h, t}:
      join_sp.go(t, acc ++ " " ++ h)

def join_sp(+ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{+h, t}:
      h ++ join_sp.go(t, "")

def fmt_mode(+from: String, +ps: List<&2, String>) -> String:
  from ++ " MODE " ++ join_sp(ps)

# CTCP ACTION: \x01ACTION text\x01  (SOH = 1)
def is_action(+body: String) -> Bool:
  String.starts_with(body, SCon{Chr{1}, "ACTION "})

def action_text.soh(soh: Bool, +rest: String, t: String) -> String:
  match soh:
    case True{}:
      String.reverse(t)
    case False{}:
      rest

def action_text.fin(+rest: String, rev: String) -> String:
  match rev:
    case SCon{+h, t}:
      action_text.soh(Irc.code_is(h, 1), rest, t)
    case SNil{}:
      SNil{}

def action_text(+body: String) -> String:
  +rest = String.drop(body, 8n)
  action_text.fin(rest, String.reverse(rest))

# ---- feed arms ----------------------------------------------------------

def feed_none(+cl: Client) -> Client:
  cl

def feed_ping(+cl: Client) -> Client:
  cl

def feed_priv.write.msg(+cl: Client, +bi: Nat, +from: String, +body: String, act: Bool) -> Client:
  match act:
    case True{}:
      client_log(cl, bi, Action{}, fmt_action(from, action_text(body)))
    case False{}:
      client_log(cl, bi, Msg{}, fmt_msg(from, body))

def feed_priv.write(+cl: Client, +bi: Nat, +from: String, notice: Bool, +body: String) -> Client:
  match notice:
    case True{}:
      client_log(cl, bi, Notice{}, fmt_msg(from, body))
    case False{}:
      feed_priv.write.msg(cl, bi, from, body, is_action(body))

def feed_priv.write_got(pair: Client & Maybe<&2, Nat>, +from: String, notice: Bool, +body: String) -> Client:
  match pair:
    case (cl2, Some{+bi}):
      feed_priv.write(cl2, bi, from, notice, body)
    case (cl2, None{}):
      cl2

def feed_priv.key.on(+from: String, +target: String, self: Bool) -> String:
  match self:
    case True{}:
      target
    case False{}:
      from

def feed_priv.key(+cl: Client, +from: String, +target: String) -> String:
  match cl:
    case Client{+nick, _, _, _, _}:
      feed_priv.key.on(from, target, Irc.ieq(from, nick))

def feed_priv.nonchan(
  +cl: Client,
  +from: String,
  notice: Bool,
  +body: String,
  empty: Bool,
  +target: String
) -> Client:
  match empty:
    case True{}:
      feed_priv.write(cl, 0n, from, notice, body)
    case False{}:
      feed_priv.write_got(buf_get(cl, feed_priv.key(cl, from, target), False{}, True{}), from, notice, body)

def feed_priv.to_server.on(empty: Bool, broadcast: Bool) -> Bool:
  match empty:
    case True{}:
      True{}
    case False{}:
      broadcast

# NOTICE * / AUTH (and a missing nick) is a server broadcast, not a query.
def feed_priv.to_server(+from: String, +target: String) -> Bool:
  feed_priv.to_server.on(String.is_empty(from), Irc.ieq(target, "*") || Irc.ieq(target, "AUTH"))

def feed_priv.route.on(+cl: Client, +target: String, +from: String, notice: Bool, +body: String, chan: Bool) -> Client:
  match chan:
    case True{}:
      feed_priv.write_got(buf_get(cl, target, True{}, False{}), from, notice, body)
    case False{}:
      feed_priv.nonchan(cl, from, notice, body, feed_priv.to_server(from, target), target)

def feed_priv.route(+cl: Client, +target: String, +from: String, notice: Bool, +body: String) -> Client:
  +tgt = Irc.chan_target(target)
  feed_priv.route.on(cl, tgt, from, notice, body, Irc.starts_channel(tgt))

def feed_join.self(+cl: Client, +bi: Nat, self: Bool) -> Client:
  match self:
    case True{}:
      set_active(cl, bi)
    case False{}:
      cl

def feed_join.apply.on(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat, +from: String, +chan: String, self: Bool, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      +b2 = nick_add(b, from)
      +b3 = buf_log_ts(b2, System{}, now, fmt_join(from, chan))
      feed_join.self(Client{nick, server, set_nth_buf(bufs, bi, b3), active, now}, bi, self)

def feed_join.from_cl(+cl2: Client, +bi: Nat, +from: String, +chan: String, self: Bool) -> Client:
  match cl2:
    case Client{+nick, +server, +bufs, +active, +now}:
      feed_join.apply.on(nick, server, bufs, active, now, bi, from, chan, self, nth_buf(bufs, bi))

def feed_join.from_pair(pair: Client & Maybe<&2, Nat>, +from: String, +chan: String, self: Bool) -> Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_join.from_cl(cl2, bi, from, chan, self)

def feed_join.with.on(+cl: Client, +from: String, +chan: String, +self: Bool, empty: Bool) -> Client:
  match empty:
    case True{}:
      cl
    case False{}:
      feed_join.from_pair(buf_get(cl, chan, True{}, self), from, chan, self)

def feed_join.with(+cl: Client, +from: String, +chan: String, +self: Bool) -> Client:
  feed_join.with.on(cl, from, chan, self, String.is_empty(chan))

def feed_join(+cl: Client, +m: Irc.Message, self: Bool) -> Client:
  feed_join.with(cl, msg_nick(m), Irc.msg_param(m, 0n), self)

def feed_part.member(
  +nick: String,
  +server: String,
  +bufs: List<&2, Buffer>,
  +active: Nat,
  +now: String,
  +bi: Nat,
  +from: String,
  +chan: String,
  +b: Buffer,
  has: Bool
) -> Client:
  match has:
    case False{}:
      Client{nick, server, bufs, active, now}
    case True{}:
      +b2 = nick_del(b, from)
      +b3 = buf_log_ts(b2, System{}, now, fmt_part(from, chan))
      Client{nick, server, set_nth_buf(bufs, bi, b3), active, now}

def feed_part.at.got(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat, +from: String, +chan: String, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{+b}:
      feed_part.member(nick, server, bufs, active, now, bi, from, chan, b, nick_has(b, from))

def feed_part.at(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat, +from: String, +chan: String) -> Client:
  feed_part.at.got(nick, server, bufs, active, now, bi, from, chan, nth_buf(bufs, bi))

def feed_part.on(+cl: Client, +chan: String, +from: String, found: Maybe<&2, Nat>) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      match found:
        case None{}:
          Client{nick, server, bufs, active, now}
        case Some{bi}:
          feed_part.at(nick, server, bufs, active, now, bi, from, chan)

def feed_part.pick(+cl: Client, +chan: String, +from: String, self: Bool, found: Maybe<&2, Nat>) -> Client:
  match self:
    case True{}:
      drop_buf.at(cl, found)
    case False{}:
      feed_part.on(cl, chan, from, found)

def feed_part.with(+cl: Client, +chan: String, +from: String, self: Bool) -> Client:
  feed_part.pick(cl, chan, from, self, buf_find(cl, chan))

def feed_part(+cl: Client, +m: Irc.Message, self: Bool) -> Client:
  feed_part.with(cl, Irc.msg_param(m, 0n), msg_nick(m), self)

def fmt_kick(+victim: String, +chan: String) -> String:
  "<- " ++ victim ++ " kicked from " ++ chan

def feed_kick.at.got(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat, +victim: String, +chan: String, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      +b2 = nick_del(b, victim)
      +b3 = buf_log_ts(b2, System{}, now, fmt_kick(victim, chan))
      Client{nick, server, set_nth_buf(bufs, bi, b3), active, now}

def feed_kick.at(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat, +victim: String, +chan: String) -> Client:
  feed_kick.at.got(nick, server, bufs, active, now, bi, victim, chan, nth_buf(bufs, bi))

def feed_kick.other(+cl: Client, +chan: String, +victim: String, found: Maybe<&2, Nat>) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      match found:
        case None{}:
          Client{nick, server, bufs, active, now}
        case Some{bi}:
          feed_kick.at(nick, server, bufs, active, now, bi, victim, chan)

def feed_kick.pick(+cl: Client, +chan: String, +victim: String, self: Bool, found: Maybe<&2, Nat>) -> Client:
  match self:
    case True{}:
      drop_buf.at(cl, found)
    case False{}:
      feed_kick.other(cl, chan, victim, found)

def is_channel_buf(+b: Buffer) -> Bool:
  match b:
    case Buffer{_, +ch, _, _, _, _}:
      ch

def feed_quit.one.on(+b: Buffer, +from: String, +reason: String, +ts: String, has: Bool) -> Buffer:
  match has:
    case True{}:
      buf_log_ts(nick_del(b, from), System{}, ts, fmt_quit(from, reason))
    case False{}:
      b

def feed_quit.one(+b: Buffer, +from: String, +reason: String, +ts: String) -> Buffer:
  feed_quit.one.on(b, from, reason, ts, nick_has(b, from))

def feed_quit.query.on(+h: Buffer, +from: String, +reason: String, +ts: String, hit: Bool) -> Buffer:
  match hit:
    case True{}:
      buf_log_ts(h, System{}, ts, fmt_quit(from, reason))
    case False{}:
      h

def feed_quit.query(+h: Buffer, +from: String, +reason: String, +ts: String) -> Buffer:
  match h:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      feed_quit.query.on(
        Buffer{name, ch, topic, lines, nicks, scroll},
        from,
        reason,
        ts,
        Irc.ieq(name, from)
      )

def feed_quit.apply.on(+h: Buffer, +from: String, +reason: String, +ts: String, ch: Bool) -> Buffer:
  match ch:
    case True{}:
      feed_quit.one(h, from, reason, ts)
    case False{}:
      feed_quit.query(h, from, reason, ts)

def feed_quit.apply(+h: Buffer, +from: String, +reason: String, +ts: String) -> Buffer:
  feed_quit.apply.on(h, from, reason, ts, is_channel_buf(h))

type QuitAcc is Data:
  QuitAcc{from: String, reason: String, ts: String, acc: List<&2, Buffer>}

def feed_quit.step(st: QuitAcc, h: Buffer) -> QuitAcc:
  match st:
    case QuitAcc{+from, +reason, +ts, acc}:
      QuitAcc{from, reason, ts, feed_quit.apply(h, from, reason, ts) <> acc}

def feed_quit.bufs(st: QuitAcc) -> List<&2, Buffer>:
  match st:
    case QuitAcc{_, _, _, acc}:
      List.reverse(&2, Buffer, acc)

def feed_quit.with(+cl: Client, +from: String, +reason: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      Client{nick, server, feed_quit.bufs(List.foldl(~&2, ~Buffer, ~QuitAcc, ~feed_quit.step, bufs, QuitAcc{from, reason, now, Nil{}})), active, now}

def feed_quit(+cl: Client, +m: Irc.Message) -> Client:
  feed_quit.with(cl, msg_nick(m), Irc.msg_param(m, 0n))

def feed_nick.one.on(+b: Buffer, +from: String, +to: String, +ts: String, has: Bool) -> Buffer:
  match has:
    case True{}:
      buf_log_ts(nick_rename(b, from, to), System{}, ts, fmt_nick_chg(from, to))
    case False{}:
      b

def feed_nick.one(+b: Buffer, +from: String, +to: String, +ts: String) -> Buffer:
  feed_nick.one.on(b, from, to, ts, nick_has(b, from))

def feed_nick.query.on(+h: Buffer, +from: String, +to: String, +ts: String, hit: Bool) -> Buffer:
  match hit:
    case True{}:
      buf_log_ts(set_buf_name(h, to), System{}, ts, fmt_nick_chg(from, to))
    case False{}:
      h

def feed_nick.query(+h: Buffer, +from: String, +to: String, +ts: String) -> Buffer:
  match h:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      feed_nick.query.on(
        Buffer{name, ch, topic, lines, nicks, scroll},
        from,
        to,
        ts,
        Irc.ieq(name, from)
      )

def feed_nick.apply.on(+h: Buffer, +from: String, +to: String, +ts: String, ch: Bool) -> Buffer:
  match ch:
    case True{}:
      feed_nick.one(h, from, to, ts)
    case False{}:
      feed_nick.query(h, from, to, ts)

def feed_nick.apply(+h: Buffer, +from: String, +to: String, +ts: String) -> Buffer:
  feed_nick.apply.on(h, from, to, ts, is_channel_buf(h))

type NickAcc is Data:
  NickAcc{from: String, to: String, ts: String, acc: List<&2, Buffer>}

def feed_nick.step(st: NickAcc, h: Buffer) -> NickAcc:
  match st:
    case NickAcc{+from, +to, +ts, acc}:
      NickAcc{from, to, ts, feed_nick.apply(h, from, to, ts) <> acc}

def feed_nick.bufs(st: NickAcc) -> List<&2, Buffer>:
  match st:
    case NickAcc{_, _, _, acc}:
      List.reverse(&2, Buffer, acc)

def feed_nick.fin(+cl: Client, +to: String, self: Bool) -> Client:
  match self:
    case True{}:
      set_nick(cl, to)
    case False{}:
      cl

def feed_nick.with(+cl: Client, +from: String, +to: String, self: Bool) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      feed_nick.fin(Client{nick, server, feed_nick.bufs(List.foldl(~&2, ~Buffer, ~NickAcc, ~feed_nick.step, bufs, NickAcc{from, to, now, Nil{}})), active, now}, to, self)

def feed_nick(+cl: Client, +m: Irc.Message, self: Bool) -> Client:
  feed_nick.with(cl, msg_nick(m), Irc.msg_param(m, 0n), self)

def feed_topic.apply.on(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat, +from: String, +topic: String, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      +b2 = buf_log_ts(set_topic(b, topic), System{}, now, fmt_topic_set(from, topic))
      Client{nick, server, set_nth_buf(bufs, bi, b2), active, now}

def feed_topic.from_cl(+cl2: Client, +bi: Nat, +from: String, +topic: String) -> Client:
  match cl2:
    case Client{+nick, +server, +bufs, +active, +now}:
      feed_topic.apply.on(nick, server, bufs, active, now, bi, from, topic, nth_buf(bufs, bi))

def feed_topic.from_pair(pair: Client & Maybe<&2, Nat>, +from: String, +topic: String) -> Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_topic.from_cl(cl2, bi, from, topic)

def feed_topic.with(+cl: Client, +chan: String, +topic: String, +from: String) -> Client:
  feed_topic.from_pair(buf_get(cl, chan, True{}, False{}), from, topic)

def feed_topic(+cl: Client, +m: Irc.Message) -> Client:
  feed_topic.with(cl, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), msg_nick(m))

# ---- names / numeric ----------------------------------------------------

def split_names.keep(s: String) -> Bool:
  Bool.not(String.is_empty(s))

def split_names(+s: String) -> List<&2, String>:
  List.filter(~String, ~split_names.keep, String.split(s, Chr{32}))

def nick_add_step(b: Buffer, h: String) -> Buffer:
  +bb = b
  nick_add(bb, h)

def nick_add_all(+b: Buffer, +ns: List<&2, String>) -> Buffer:
  List.foldl(~&2, ~String, ~Buffer, ~nick_add_step, ns, b)

def feed_num.topic.on(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat, +topic: String, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      Client{nick, server, set_nth_buf(bufs, bi, set_topic(b, topic)), active, now}

def feed_num.topic.cl(+cl2: Client, +bi: Nat, +topic: String) -> Client:
  match cl2:
    case Client{+nick, +server, +bufs, +active, +now}:
      feed_num.topic.on(nick, server, bufs, active, now, bi, topic, nth_buf(bufs, bi))

def feed_num.topic.pair(pair: Client & Maybe<&2, Nat>, +topic: String) -> Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_num.topic.cl(cl2, bi, topic)

def feed_num.topic(+cl: Client, +chan: String, +topic: String) -> Client:
  feed_num.topic.pair(buf_get(cl, chan, True{}, False{}), topic)

def feed_num.names.on(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +bi: Nat, +names: String, got: Maybe<&2, Buffer>) -> Client:
  match got:
    case None{}:
      Client{nick, server, bufs, active, now}
    case Some{b}:
      Client{nick, server, set_nth_buf(bufs, bi, nick_add_all(b, split_names(names))), active, now}

def feed_num.names.cl(+cl2: Client, +bi: Nat, +names: String) -> Client:
  match cl2:
    case Client{+nick, +server, +bufs, +active, +now}:
      feed_num.names.on(nick, server, bufs, active, now, bi, names, nth_buf(bufs, bi))

def feed_num.names.pair(pair: Client & Maybe<&2, Nat>, +names: String) -> Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_num.names.cl(cl2, bi, names)

def feed_num.names(+cl: Client, +chan: String, +names: String) -> Client:
  feed_num.names.pair(buf_get(cl, chan, True{}, False{}), names)

def feed_num.other(+cl: Client, +num: U32, +text: String, err: Bool) -> Client:
  match err:
    case True{}:
      client_log(cl, 0n, Error{}, fmt_num(num, text))
    case False{}:
      client_log(cl, 0n, System{}, fmt_num(num, text))

def feed_num.433.on(+cl: Client, +m: Irc.Message, +num: U32, +nick: String, retry: Bool) -> Client:
  match retry:
    case True{}:
      feed_num.other(set_nick(cl, nick ++ "_"), num, Irc.msg_last(m), True{})
    case False{}:
      feed_num.other(cl, num, Irc.msg_last(m), True{})

def feed_num.433.cl(+cl: Client, +m: Irc.Message, +num: U32) -> Client:
  match cl:
    case Client{+nick, _, _, _, _}:
      feed_num.433.on(cl, m, num, nick, Irc.nick433_retry(m, nick))

def feed_num.433(hit: Bool, +cl: Client, +m: Irc.Message, +num: U32) -> Client:
  match hit:
    case True{}:
      feed_num.433.cl(cl, m, num)
    case False{}:
      feed_num.other(cl, num, Irc.msg_last(m), U32.is_ge(num, 400))

def feed_num.tail(+cl: Client, +m: Irc.Message, +num: U32, is366: Bool) -> Client:
  match is366:
    case True{}:
      cl
    case False{}:
      feed_num.433(U32.is_eq(num, 433), cl, m, num)

def is_353_sym(+s: String) -> Bool:
  String.eq(s, "=") || String.eq(s, "*") || String.eq(s, "@")

def feed_num.353.body(+cl: Client, +m: Irc.Message, rfc2812: Bool) -> Client:
  match rfc2812:
    case True{}:
      feed_num.names(cl, Irc.msg_param(m, 2n), Irc.msg_param(m, 3n))
    case False{}:
      feed_num.names(cl, Irc.msg_param(m, 1n), Irc.msg_param(m, 2n))

def feed_num.353(+cl: Client, +m: Irc.Message, +num: U32, is353: Bool) -> Client:
  match is353:
    case True{}:
      feed_num.353.body(cl, m, is_353_sym(Irc.msg_param(m, 1n)))
    case False{}:
      feed_num.tail(cl, m, num, U32.is_eq(num, 366))

def feed_num.332(+cl: Client, +m: Irc.Message, +num: U32, is332: Bool) -> Client:
  match is332:
    case True{}:
      feed_num.topic(cl, Irc.msg_param(m, 1n), Irc.msg_param(m, 2n))
    case False{}:
      feed_num.353(cl, m, num, U32.is_eq(num, 353))

def feed_num.001(+cl: Client, +m: Irc.Message, +num: U32, is001: Bool) -> Client:
  match is001:
    case True{}:
      client_log(set_nick(cl, Irc.msg_param(m, 0n)), 0n, System{}, Irc.msg_param(m, 1n))
    case False{}:
      feed_num.332(cl, m, num, U32.is_eq(num, 332))

def feed_numeric(+cl: Client, +m: Irc.Message) -> Client:
  match m:
    case Irc.Message{_, _, +num, _}:
      feed_num.001(cl, m, num, U32.is_eq(num, 1))

def feed_self.empty(empty: Bool, +cl: Client, +from: String) -> Bool:
  match empty:
    case True{}:
      False{}
    case False{}:
      match cl:
        case Client{+nick, _, _, _, _}:
          Irc.ieq(from, nick)

def feed_self(+cl: Client, +from: String) -> Bool:
  feed_self.empty(String.is_empty(from), cl, from)

def feed_kick.with(+cl: Client, +chan: String, +victim: String) -> Client:
  feed_kick.pick(cl, chan, victim, feed_self(cl, victim), buf_find(cl, chan))

def feed_kick(+cl: Client, +m: Irc.Message) -> Client:
  feed_kick.with(cl, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n))

def feed_mode.got(+cl: Client, +from: String, +ps: List<&2, String>, found: Maybe<&2, Nat>) -> Client:
  match found:
    case None{}:
      cl
    case Some{+bi}:
      client_log(cl, bi, System{}, fmt_mode(from, ps))

def first_param(+ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{+h, _}:
      h

def feed_mode(+cl: Client, +m: Irc.Message) -> Client:
  match m:
    case Irc.Message{+nick, _, _, +ps}:
      feed_mode.got(cl, nick, ps, buf_find(cl, first_param(ps)))

def feed_unk(+cl: Client, +m: Irc.Message) -> Client:
  match m:
    case Irc.Message{_, +cmd, _, _}:
      client_log(cl, 0n, System{}, fmt_unk(cmd, Irc.msg_param(m, 0n)))

def feed_msg.cmd(+cl: Client, +m: Irc.Message, +from: String, self: Bool, c: Irc.Cmd) -> Client:
  match c:
    case Irc.Ping{}:
      feed_ping(cl)
    case Irc.Privmsg{}:
      feed_priv.route(cl, Irc.msg_param(m, 0n), from, False{}, Irc.msg_param(m, 1n))
    case Irc.Notice{}:
      feed_priv.route(cl, Irc.msg_param(m, 0n), from, True{}, Irc.msg_param(m, 1n))
    case Irc.Join{}:
      feed_join(cl, m, self)
    case Irc.Part{}:
      feed_part(cl, m, self)
    case Irc.Kick{}:
      feed_kick(cl, m)
    case Irc.Quit{}:
      feed_quit(cl, m)
    case Irc.Nick{}:
      feed_nick(cl, m, self)
    case Irc.Topic{}:
      feed_topic(cl, m)
    case Irc.Mode{}:
      feed_mode(cl, m)
    case Irc.Numeric{_}:
      feed_numeric(cl, m)
    case Irc.Error{}:
      client_log(cl, 0n, Error{}, fmt_err(Irc.msg_param(m, 0n)))
    case _:
      feed_unk(cl, m)

def feed_msg.with(+cl: Client, +m: Irc.Message, +from: String) -> Client:
  feed_msg.cmd(cl, m, from, feed_self(cl, from), Irc.classify(m))

def feed_msg(+cl: Client, +m: Irc.Message) -> Client:
  feed_msg.with(cl, m, msg_nick(m))

def feed.on(+cl: Client, m: Maybe<&2, Irc.Message>) -> Client:
  match m:
    case None{}:
      feed_none(cl)
    case Some{msg}:
      feed_msg(cl, msg)

def feed(+cl: Client, +line: String) -> Client:
  feed.on(cl, Irc.parse(line))

# ---- demo / show --------------------------------------------------------

def demo_lines() -> List<&2, String>:
  ":irc.birc.dev 001 me :Welcome to the birc IRC Network me"
    <> ":me!me@localhost JOIN #birc"
    <> ":irc.birc.dev 353 me = #birc :me @alice bob carol"
    <> ":irc.birc.dev 366 me #birc :End of /NAMES list."
    <> ":irc.birc.dev 332 me #birc :birc — Bend 2 + timui.h IRC"
    <> ":alice!a@host PRIVMSG #birc :hi everyone"
    <> ":bob!b@host PRIVMSG #birc :morning — *bold* _em_ and `code`"
    <> ":carol!c@host PRIVMSG #birc :see https://timui.dev docs"
    <> Nil{}

def feed_step(cl: Client, line: String) -> Client:
  feed(cl, line)

def feed_all(+cl: Client, +xs: List<&2, String>) -> Client:
  List.foldl(~&2, ~String, ~Client, ~feed_step, xs, cl)

def show_nicks.go(fuel: Nat, +ns: List<&2, String>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match ns:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_nicks.go(p, t, acc ++ h ++ " ")

def show_nicks(+ns: List<&2, String>) -> String:
  show_nicks.go(Nat.add(1n, nick_len(ns)), ns, "")

def show_buf.chan(+ch: Bool) -> String:
  match ch:
    case True{}:
      "#"
    case False{}:
      ""

def show_buf(+b: Buffer) -> String:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, _}:
      name
        ++ show_buf.chan(ch)
        ++ "{" ++ topic ++ "|"
        ++ Nat.show(List.length(&2, Line, lines)) ++ "|"
        ++ show_nicks(nicks) ++ "}"

def show_bufs.go(fuel: Nat, +xs: List<&2, Buffer>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_bufs.go(p, t, acc ++ show_buf(h) ++ ";")

def show_bufs(+xs: List<&2, Buffer>) -> String:
  show_bufs.go(Nat.add(1n, buf_count(xs)), xs, "")

def show_client(+cl: Client) -> String:
  match cl:
    case Client{+nick, +server, +bufs, +active, _}:
      nick ++ "@" ++ server ++ "[" ++ Nat.show(active) ++ "]:" ++ show_bufs(bufs)

def nbuf(+cl: Client) -> Nat:
  match cl:
    case Client{_, _, +bufs, _, _}:
      buf_count(bufs)

def buf_nlines.on(got: Maybe<&2, Buffer>) -> Nat:
  match got:
    case None{}:
      0n
    case Some{b}:
      match b:
        case Buffer{_, _, _, +lines, _, _}:
          List.length(&2, Line, lines)

def buf_nlines(+cl: Client, +i: Nat) -> Nat:
  match cl:
    case Client{_, _, +bufs, _, _}:
      buf_nlines.on(nth_buf(bufs, i))

def has_buf.on(found: Maybe<&2, Nat>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{_}:
      True{}

def has_buf(+cl: Client, +name: String) -> Bool:
  has_buf.on(buf_find(cl, name))

def buf_nicks.text(+b: Buffer) -> String:
  match b:
    case Buffer{_, _, _, _, +nicks, _}:
      show_nicks(nicks)

def buf_nicks.got(got: Maybe<&2, Buffer>) -> String:
  match got:
    case None{}:
      ""
    case Some{b}:
      buf_nicks.text(b)

def buf_nicks.idx(+cl: Client, +i: Nat) -> String:
  match cl:
    case Client{_, _, +bufs, _, _}:
      buf_nicks.got(nth_buf(bufs, i))

def buf_nicks.at(+cl: Client, found: Maybe<&2, Nat>) -> String:
  match found:
    case None{}:
      ""
    case Some{+i}:
      buf_nicks.idx(cl, i)

def buf_nicks(+cl: Client, +name: String) -> String:
  buf_nicks.at(cl, buf_find(cl, name))

# ---- law helpers (pure predicates) --------------------------------------

def feed_id(+cl: Client, +line: String) -> Bool:
  String.eq(show_client(cl), show_client(feed(cl, line)))

# M7.2 — flood JOIN past MAX_BUFFERS; buffer count stays capped.
def flood_join_line(+i: Nat) -> String:
  ":me!me@localhost JOIN #c" ++ Nat.show(i)

def flood_joins.go(fuel: Nat, +i: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+p:
      flood_joins.go(p, 1n+i, flood_join_line(i) <> acc)

def flood_joins(+n: Nat) -> List<&2, String>:
  flood_joins.go(n, 0n, Nil{})

# Extra self-JOINs past the cap log "buffer limit reached" on the server buffer.
def flood_server_clean() -> Bool:
  +one = feed(init("me", "s"), flood_join_line(0n))
  +many = feed_all(init("me", "s"), flood_joins(24n))
  Nat.is_gt(buf_nlines(many, 0n), buf_nlines(one, 0n))

def flood_buffers_capped() -> Bool:
  +many = feed_all(init("me", "s"), flood_joins(24n))
  Nat.is_le(nbuf(many), MAX_BUFFERS()) && flood_server_clean()

def notice_star_server() -> Bool:
  +cl = feed(init("me", "s"), ":irc.example.net NOTICE * :*** Looking up")
  Nat.is_eq(nbuf(cl), 1n) && Nat.is_eq(buf_nlines(cl, 0n), 1n)

def privmsg_query_opens() -> Bool:
  Nat.is_eq(nbuf(feed(init("me", "s"), ":alice!a@h PRIVMSG me :hi")), 2n)

def lines_pipe.go(fuel: Nat, +xs: List<&2, Line>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{Line{_, _, +text}, t}:
          lines_pipe.go(p, t, acc ++ text ++ "|")

def lines_pipe(+xs: List<&2, Line>) -> String:
  lines_pipe.go(Nat.add(1n, List.length(&2, Line, xs)), xs, "")

def buf_texts.on(got: Maybe<&2, Buffer>) -> String:
  match got:
    case None{}:
      ""
    case Some{b}:
      match b:
        case Buffer{_, _, _, +lines, _, _}:
          lines_pipe(lines)

def buf_texts(+cl: Client, +i: Nat) -> String:
  match cl:
    case Client{_, _, +bufs, _, _}:
      buf_texts.on(nth_buf(bufs, i))

# Self JOIN focuses #birc (index 1); next wraps to server (0), next again to 1.
def scroll_page_ok() -> Bool:
  +cl0 = set_active(feed(init("me", "s"), ":me!me@localhost JOIN #birc"), 1n)
  +cl1 = apply_active_scroll(cl0, 3n, 0n)
  Nat.is_eq(buf_scroll_of(cl1, 1n), 1n)

def nick_query_renames() -> Bool:
  +cl0 = feed(init("me", "s"), ":alice!a@h PRIVMSG me :hi")
  +cl = feed(cl0, ":alice!a@h NICK bob")
  has_buf(cl, "bob")
    && Bool.not(has_buf(cl, "alice"))
    && Nat.is_eq(nbuf(cl), 2n)

def quit_query_logs() -> Bool:
  +cl0 = feed(init("me", "s"), ":alice!a@h PRIVMSG me :hi")
  +cl = feed(cl0, ":alice!a@h QUIT :bye")
  Nat.is_eq(buf_nlines(cl, 1n), 2n)

def mode_channel_logs() -> Bool:
  +cl0 = feed(init("me", "s"), ":me!me@localhost JOIN #birc")
  +cl = feed(cl0, ":op!u@h MODE #birc +o alice")
  Nat.is_eq(buf_nlines(cl, 1n), 2n) && Nat.is_eq(buf_nlines(cl, 0n), 0n)

def part_nonmember_silent() -> Bool:
  +cl0 = feed(init("me", "s"), ":me!me@localhost JOIN #birc")
  +cl1 = feed(cl0, ":alice!a@h JOIN #birc")
  +cl = feed(cl1, ":bob!b@h PART #birc")
  Nat.is_eq(buf_nlines(cl, 1n), 2n)

def server_nick_query() -> Bool:
  +cl = feed(init("me", "s"), ":server!s@h PRIVMSG me :hi")
  Nat.is_eq(nbuf(cl), 2n) && has_buf(cl, "server") && Nat.is_eq(buf_nlines(cl, 0n), 0n)

def ieq_rfc1459_ok() -> Bool:
  Irc.ieq("foo[]", "foo{}") && Irc.ieq("A\\B", "a|b")

def self_priv_query() -> Bool:
  +cl = feed(init("me", "s"), ":me!me@h PRIVMSG alice :hi")
  has_buf(cl, "alice") && Bool.not(has_buf(cl, "me"))

def scroll_clamp_ok() -> Bool:
  +cl0 = set_active(feed(init("me", "s"), ":me!me@localhost JOIN #birc"), 1n)
  +cl1 = apply_active_scroll(cl0, 50n, 0n)
  Nat.is_eq(buf_scroll_of(cl1, 1n), buf_nlines(cl1, 1n))

def bare_join_ok() -> Bool:
  Nat.is_eq(nbuf(feed(init("me", "s"), ":me!me@localhost JOIN")), 1n)

def snap_ok() -> Bool:
  +clq = set_active(feed(init("me", "s"), ":alice!a@h PRIVMSG me :hi"), 1n)
  +cl1 = apply_active_scroll(clq, 2n, 0n)
  +cl2 = snap_active(cl1)
  Nat.is_eq(buf_scroll_of(cl1, 1n), 1n) && Nat.is_eq(buf_scroll_of(cl2, 1n), 0n)

def cycle_ok() -> Bool:
  +cl = feed(init("me", "s"), ":me!me@localhost JOIN #birc")
  +c1 = cycle_tab(cl, 1)
  +c2 = cycle_tab(c1, 1)
  Nat.is_eq(active_of(cl), 1n) && Nat.is_eq(active_of(c1), 0n) && Nat.is_eq(active_of(c2), 1n)

# Newest line is last. Two query messages stay chronological.
def log_chrono_ok() -> Bool:
  String.eq(
    buf_texts(
      feed(feed(init("me", "s"), ":a!a@h PRIVMSG me :one"), ":a!a@h PRIVMSG me :two"),
      1n
    ),
    "<a> one|<a> two|"
  )

def welcome_server_line() -> Bool:
  +cl = feed(init("me", "s"), ":irc.example.net 001 me :Welcome")
  Nat.is_eq(nbuf(cl), 1n) && Nat.is_eq(buf_nlines(cl, 0n), 1n)

def names_1459_ok() -> Bool:
  +cl = feed_all(
    init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":irc.birc.dev 353 me #birc :me alice" <> Nil{})
  Nat.is_eq(nbuf(cl), 2n) && has_buf(cl, "#birc") && Bool.not(has_buf(cl, "me alice")) && String.eq(buf_nicks(cl, "#birc"), "me alice ")

def statusmsg_ok() -> Bool:
  +cl = feed_all(
    init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":op!u@h PRIVMSG @#birc :ops" <> Nil{})
  Nat.is_eq(nbuf(cl), 2n) && has_buf(cl, "#birc") && Bool.not(has_buf(cl, "@#birc")) && Nat.is_eq(buf_nlines(cl, 1n), 2n)

def notice_auth_ok() -> Bool:
  +cl = feed(init("me", "s"), ":irc NOTICE AUTH :hi")
  Nat.is_eq(nbuf(cl), 1n) && Nat.is_eq(buf_nlines(cl, 0n), 1n)

def kick_self_drops() -> Bool:
  +cl = feed_all(
    init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":op!u@h KICK #birc me :bye" <> Nil{})
  Nat.is_eq(nbuf(cl), 1n) && Bool.not(has_buf(cl, "#birc"))

def self_part_drops() -> Bool:
  +cl = feed_all(
    init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":me!me@localhost PART #birc" <> Nil{})
  Nat.is_eq(nbuf(cl), 1n) && Bool.not(has_buf(cl, "#birc"))

def nick_of(+cl: Client) -> String:
  match cl:
    case Client{+nick, _, _, _, _}:
      nick

def numeric_last_ok() -> Bool:
  +cl = feed(init("me", "s"), ":irc.example.net 403 me #nope :No such channel")
  String.eq(buf_texts(cl, 0n), "[403] No such channel|")

# After registration, 433 me newnick is a rejected /nick: stay me, only log.
def nick433_ok() -> Bool:
  +cl = feed(init("me", "s"), ":irc.example.net 433 me newnick :Nickname is already in use")
  String.eq(nick_of(cl), "me") && String.eq(buf_texts(cl, 0n), "[433] Nickname is already in use|")

# Registration: 433 * me and 433 me me mean our nick is taken; retry as me_.
def nick433_star_ok() -> Bool:
  +cl = feed(init("me", "s"), ":irc.example.net 433 * me :Nickname is already in use")
  String.eq(nick_of(cl), "me_") && String.eq(buf_texts(cl, 0n), "[433] Nickname is already in use|")

def nick433_same_ok() -> Bool:
  +cl = feed(init("me", "s"), ":irc.example.net 433 me me :Nickname is already in use")
  String.eq(nick_of(cl), "me_") && String.eq(buf_texts(cl, 0n), "[433] Nickname is already in use|")

def log_ts_ok.pair(+ts0: String, rest: List<&2, Line>) -> Bool:
  match rest:
    case Con{Line{_, +ts1, _}, _}:
      String.eq(ts0, "01:02:03") && String.eq(ts1, "12:00:00")
    case _:
      False{}

def log_ts_ok.lines(+xs: List<&2, Line>) -> Bool:
  match xs:
    case Con{Line{_, +ts0, _}, rest}:
      log_ts_ok.pair(ts0, rest)
    case _:
      False{}

def log_ts_ok.buf(+b: Buffer) -> Bool:
  match b:
    case Buffer{_, _, _, +lines, _, _}:
      log_ts_ok.lines(lines)

def log_ts_ok.feed.got(got: Maybe<&2, Buffer>) -> Bool:
  match got:
    case Some{b}:
      match b:
        case Buffer{_, _, _, +lines, _, _}:
          match lines:
            case Con{Line{_, +ts, _}, _}:
              String.eq(ts, "12:00:00")
            case _:
              False{}
    case None{}:
      False{}

def log_ts_ok.feed.on(+cl: Client) -> Bool:
  match cl:
    case Client{_, _, +bufs, _, _}:
      log_ts_ok.feed.got(nth_buf(bufs, 0n))

def log_ts_ok.feed() -> Bool:
  log_ts_ok.feed.on(feed(set_now(init("me", "s"), "12:00:00"), ":irc.example.net NOTICE * :hi"))

def log_ts_ok() -> Bool:
  +b1 = buf_log_ts(server_buf(), Msg{}, "01:02:03", "old")
  log_ts_ok.buf(buf_log_ts(b1, Msg{}, "12:00:00", "new")) && log_ts_ok.feed()
