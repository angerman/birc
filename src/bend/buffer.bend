# Buffer container: types, nick lists, find/get/modify, scroll, take_last.
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

def buf_modify(xs: List<&2, Buffer>, n: Nat, f: Buffer -> Buffer) -> List<&2, Buffer>:
  match xs n:
    case Nil{} _:
      Nil{}
    case h <> t 0n:
      f(h) <> t
    case h <> t 1n+p:
      h <> buf_modify(t, p, f)

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

def cap_at(+now: String, b: Buffer) -> Buffer:
  cap_note(b, now)

def buf_get.full(got: Maybe<&2, Buffer>, +nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String) -> Client & Maybe<&2, Nat>:
  match got:
    case None{}:
      (Client{nick, server, bufs, active, now}, None{})
    case Some{_}:
      (Client{nick, server, buf_modify(bufs, 0n, cap_at(now)), active, now}, None{})

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

# Keep the last n lines in original order (oldest → newest).
def take_last(+xs: List<&2, Line>, n: Nat) -> List<&2, Line>:
  List.drop(&2, Line, xs, Nat.sub(List.length(&2, Line, xs), n))

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

def buf_log_at(kind: LineKind, +ts: String, +text: String, b: Buffer) -> Buffer:
  buf_log_ts(b, kind, ts, text)

def client_log(+cl: Client, +i: Nat, kind: LineKind, +text: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      Client{nick, server, buf_modify(bufs, i, buf_log_at(kind, now, text)), active, now}

def set_now(+cl: Client, +ts: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, _}:
      Client{nick, server, bufs, active, ts}

def replay_keep.cons(acc: List<&2, String>, +s: String, empty: Bool) -> List<&2, String>:
  match empty:
    case True{}:
      acc
    case False{}:
      s <> acc

def replay_step(acc: List<&2, String>, h: String) -> List<&2, String>:
  +s = Irc.strip_cr(h)
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
            nick_has(Buffer{name, ch, topic, lines, nicks, scroll}, nick) || Nat.is_ge(List.length(&2, String, nicks), MAX_NICKS()),
            nick)

def nick_add(+b: Buffer, +raw: String) -> Buffer:
  +n = nick_strip(raw)
  nick_add.body(b, n, String.is_empty(n))

def nick_add_who(+who: String, b: Buffer) -> Buffer:
  nick_add(b, who)

def nick_add_idx(+cl: Client, +i: Nat, +who: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      Client{nick, server, buf_modify(bufs, i, nick_add_who(who)), active, now}

def nick_add_step(b: Buffer, h: String) -> Buffer:
  +bb = b
  nick_add(bb, h)

def nick_add_all(+b: Buffer, +ns: List<&2, String>) -> Buffer:
  List.foldl(~&2, ~String, ~Buffer, ~nick_add_step, ns, b)

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

def scroll_zero(b: Buffer) -> Buffer:
  set_buf_scroll(b, 0n)

def snap_active(+cl: Client) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      Client{nick, server, buf_modify(bufs, active, scroll_zero), active, now}

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

def scroll_delta(+up: Nat, +dn: Nat, b: Buffer) -> Buffer:
  apply_buf_scroll.on(b, up, dn)

def apply_active_scroll(+cl: Client, +up: Nat, +dn: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now}:
      Client{nick, server, buf_modify(bufs, active, scroll_delta(up, dn)), active, now}

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


def nick_of(+cl: Client) -> String:
  match cl:
    case Client{+nick, _, _, _, _}:
      nick
