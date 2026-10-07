# Pure transient IRCv3 +typing state. Session supplies monotonic milliseconds.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl

def MAX_TYPERS() -> Nat:
  32n

def ACTIVE_MS() -> U32:
  6000

def PAUSED_MS() -> U32:
  30000

type Entry is Data:
  Entry{target: String, nick: String, status: Irc.TypingStatus, seen_ms: U32}

type State is Data:
  State{entries: List<&2, Entry>}

def empty() -> State:
  State{Nil{}}

def count(+state: State) -> Nat:
  match state:
    case State{+entries}:
      List.length(&2, Entry, entries)

def entry_is(+e: Entry, +target: String, +nick: String) -> Bool:
  match e:
    case Entry{+t, +n, _, _}:
      Irc.ieq(t, target) && Irc.ieq(n, nick)

def entry_is_cm(+cm: String, +e: Entry, +target: String, +nick: String) -> Bool:
  match e:
    case Entry{+t, +n, _, _}:
      Cl.buf_eq_cm(cm, t, target) && Cl.buf_eq_cm(cm, n, nick)

def has_entries(xs: List<&2, Entry>, +target: String, +nick: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+h, t}:
      entry_is(h, target, nick) || has_entries(t, target, nick)

def has_entries_cm(+cm: String, xs: List<&2, Entry>, +target: String, +nick: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+h, t}:
      entry_is_cm(cm, h, target, nick) || has_entries_cm(cm, t, target, nick)

def has(+state: State, +target: String, +nick: String) -> Bool:
  match state:
    case State{+entries}:
      has_entries(entries, target, nick)

def has_cm(+cm: String, +state: State, +target: String, +nick: String) -> Bool:
  match state:
    case State{+entries}:
      has_entries_cm(cm, entries, target, nick)

def remove_one.keep(+h: Entry, tail: List<&2, Entry>, remove: Bool) -> List<&2, Entry>:
  match remove:
    case True{}:
      tail
    case False{}:
      h <> tail

def remove_one(xs: List<&2, Entry>, +target: String, +nick: String) -> List<&2, Entry>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      remove_one.keep(h, remove_one(t, target, nick), entry_is(h, target, nick))

def remove_one_cm(+cm: String, xs: List<&2, Entry>, +target: String, +nick: String) -> List<&2, Entry>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      remove_one.keep(h, remove_one_cm(cm, t, target, nick), entry_is_cm(cm, h, target, nick))

def remove_all.pick(+h: Entry, tail: List<&2, Entry>, hit: Bool) -> List<&2, Entry>:
  match hit:
    case True{}: tail
    case False{}: h <> tail

def remove_all.keep(+h: Entry, tail: List<&2, Entry>, +nick: String) -> List<&2, Entry>:
  match h:
    case Entry{_, +n, _, _}:
      remove_all.pick(h, tail, Irc.ieq(n, nick))

def remove_all.keep_cm(+cm: String, +h: Entry, tail: List<&2, Entry>, +nick: String) -> List<&2, Entry>:
  match h:
    case Entry{_, +n, _, _}:
      remove_all.pick(h, tail, Cl.buf_eq_cm(cm, n, nick))

def remove_all(xs: List<&2, Entry>, +nick: String) -> List<&2, Entry>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      remove_all.keep(h, remove_all(t, nick), nick)

def remove_all_cm(+cm: String, xs: List<&2, Entry>, +nick: String) -> List<&2, Entry>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      remove_all.keep_cm(cm, h, remove_all_cm(cm, t, nick), nick)

def append_new(+xs: List<&2, Entry>, +e: Entry, room: Bool) -> List<&2, Entry>:
  match room:
    case True{}:
      List.append(&2, Entry, xs, e <> Nil{})
    case False{}:
      xs

def upsert.pick(+rest: List<&2, Entry>, +e: Entry, existed: Bool) -> List<&2, Entry>:
  match existed:
    case True{}:
      List.append(&2, Entry, rest, e <> Nil{})
    case False{}:
      append_new(rest, e, Nat.is_lt(List.length(&2, Entry, rest), MAX_TYPERS()))

def upsert(+xs: List<&2, Entry>, +target: String, +nick: String, status: Irc.TypingStatus, +now_ms: U32) -> List<&2, Entry>:
  +existed = has_entries(xs, target, nick)
  +rest = remove_one(xs, target, nick)
  upsert.pick(rest, Entry{target, nick, status, now_ms}, existed)

def upsert_cm(+cm: String, +xs: List<&2, Entry>, +target: String, +nick: String, status: Irc.TypingStatus, +now_ms: U32) -> List<&2, Entry>:
  +existed = has_entries_cm(cm, xs, target, nick)
  +rest = remove_one_cm(cm, xs, target, nick)
  upsert.pick(rest, Entry{target, nick, status, now_ms}, existed)

def apply_event(+state: State, e: Irc.TypingEvent, +now_ms: U32) -> State:
  match state:
    case State{+entries}:
      match e:
        case Irc.TypingSet{+nick, +target, status}:
          match status:
            case Irc.TypingDone{}:
              State{remove_one(entries, target, nick)}
            case Irc.TypingActive{}:
              State{upsert(entries, target, nick, Irc.TypingActive{}, now_ms)}
            case Irc.TypingPaused{}:
              State{upsert(entries, target, nick, Irc.TypingPaused{}, now_ms)}
        case Irc.TypingClear{+nick, +target}:
          State{remove_one(entries, target, nick)}
        case Irc.TypingClearAll{+nick}:
          State{remove_all(entries, nick)}

def apply_event_cm(+cm: String, +state: State, e: Irc.TypingEvent, +now_ms: U32) -> State:
  match state:
    case State{+entries}:
      match e:
        case Irc.TypingSet{+nick, +target, status}:
          match status:
            case Irc.TypingDone{}:
              State{remove_one_cm(cm, entries, target, nick)}
            case Irc.TypingActive{}:
              State{upsert_cm(cm, entries, target, nick, Irc.TypingActive{}, now_ms)}
            case Irc.TypingPaused{}:
              State{upsert_cm(cm, entries, target, nick, Irc.TypingPaused{}, now_ms)}
        case Irc.TypingClear{+nick, +target}:
          State{remove_one_cm(cm, entries, target, nick)}
        case Irc.TypingClearAll{+nick}:
          State{remove_all_cm(cm, entries, nick)}

def apply(+state: State, e: Irc.TypingEvent, +now_ms: U32) -> State:
  apply_event(state, e, now_ms)

def apply_cm(+cm: String, +state: State, e: Irc.TypingEvent, +now_ms: U32) -> State:
  apply_event_cm(cm, state, e, now_ms)

def apply_maybe(+state: State, e: Maybe<&2, Irc.TypingEvent>, +now_ms: U32) -> State:
  match e:
    case None{}:
      state
    case Some{event}:
      apply_event(state, event, now_ms)

def apply_maybe_cm(+cm: String, +state: State, e: Maybe<&2, Irc.TypingEvent>, +now_ms: U32) -> State:
  match e:
    case None{}:
      state
    case Some{event}:
      apply_event_cm(cm, state, event, now_ms)

def apply_line(+state: State, +line: String, +now_ms: U32) -> State:
  apply_maybe(state, Irc.typing_event(line), now_ms)

# Production targets need resident-channel context; the context-free parser
# stays available for protocol laws and callers without a Client.
def message_target(+cl: Cl.Client, +nick: String, +raw: String, channel: Bool) -> String:
  match channel:
    case True{}: Cl.message_key(cl, raw)
    case False{}: Irc.proto_atom(nick)

# Negotiated routing (I2-dynamic2 F4): channel detection and audience
# resolution use the Session CHANTYPES/STATUSMSG/PREFIX sets, so $room and
# ^#room reach their channel buffer instead of retargeting to the sender.
def message_target_with(+cm: String, +types: String, +status: String, +sigils: String, +cl: Cl.Client, +nick: String, +raw: String, channel: Bool) -> String:
  match channel:
    case True{}: Cl.message_key_with(cl, cm, types, status, sigils, raw)
    case False{}: Irc.proto_atom(nick)

# Classification runs on the normalized protocol identity so a
# style-prefixed channel/STATUSMSG target still resolves to its
# channel instead of retargeting to the sender nick.
def event_target.rest(+cl: Cl.Client, +nick: String, +raw: String) -> String:
  +t = Irc.proto_atom(raw)
  message_target(cl, nick, t, Irc.starts_channel(t))

def event_target.raw(+cl: Cl.Client, +nick: String, +raw: String, c: Irc.Cmd) -> String:
  match c:
    case Irc.Part{}: Cl.target_name(raw)
    case Irc.Kick{}: Cl.target_name(raw)
    case _: event_target.rest(cl, nick, raw)

def event_target_with.rest(+cm: String, +types: String, +status: String, +sigils: String, +cl: Cl.Client, +nick: String, +raw: String) -> String:
  +t = Irc.proto_atom(raw)
  message_target_with(cm, types, status, sigils, cl, nick, t, Cl.target_channel_with(types, status, sigils, t))

def event_target_with.raw(+cm: String, +types: String, +status: String, +sigils: String, +cl: Cl.Client, +nick: String, +raw: String, c: Irc.Cmd) -> String:
  match c:
    case Irc.Part{}: Cl.target_name(raw)
    case Irc.Kick{}: Cl.target_name(raw)
    case _: event_target_with.rest(cm, types, status, sigils, cl, nick, raw)

def event_target(+cl: Cl.Client, +m: Irc.Message, c: Irc.Cmd) -> String:
  event_target.raw(cl, Irc.msg_nick(m), Irc.msg_param(m, 0n), c)

def event_target_with(+cm: String, +types: String, +status: String, +sigils: String, +cl: Cl.Client, +m: Irc.Message, c: Irc.Cmd) -> String:
  event_target_with.raw(cm, types, status, sigils, cl, Irc.msg_nick(m), Irc.msg_param(m, 0n), c)

def retarget_event(e: Irc.TypingEvent, +target: String) -> Irc.TypingEvent:
  match e:
    case Irc.TypingSet{nick, _, status}: Irc.TypingSet{nick, target, status}
    case Irc.TypingClear{nick, _}: Irc.TypingClear{nick, target}
    case Irc.TypingClearAll{nick}: Irc.TypingClearAll{nick}

def retarget_maybe(e: Maybe<&2, Irc.TypingEvent>, +target: String) -> Maybe<&2, Irc.TypingEvent>:
  match e:
    case None{}: None{}
    case Some{event}: Some{retarget_event(event, target)}

def event_for.cmd(+cl: Cl.Client, +m: Irc.Message, +c: Irc.Cmd, status: Maybe<&2, Irc.TypingStatus>) -> Maybe<&2, Irc.TypingEvent>:
  retarget_maybe(Irc.typing_event_cmd(m, status, c), event_target(cl, m, c))

def event_for_with.cmd(+cm: String, +types: String, +status: String, +sigils: String, +cl: Cl.Client, +m: Irc.Message, +c: Irc.Cmd, tstatus: Maybe<&2, Irc.TypingStatus>) -> Maybe<&2, Irc.TypingEvent>:
  retarget_maybe(Irc.typing_event_cmd(m, tstatus, c), event_target_with(cm, types, status, sigils, cl, m, c))

def event_for.parsed(+cl: Cl.Client, m: Maybe<&2, Irc.Message>, status: Maybe<&2, Irc.TypingStatus>) -> Maybe<&2, Irc.TypingEvent>:
  match m:
    case None{}: None{}
    case Some{+msg}: event_for.cmd(cl, msg, Irc.classify(msg), status)

def event_for_with.parsed(+cm: String, +types: String, +status: String, +sigils: String, +cl: Cl.Client, m: Maybe<&2, Irc.Message>, tstatus: Maybe<&2, Irc.TypingStatus>) -> Maybe<&2, Irc.TypingEvent>:
  match m:
    case None{}: None{}
    case Some{+msg}: event_for_with.cmd(cm, types, status, sigils, cl, msg, Irc.classify(msg), tstatus)

def apply_line_for(+state: State, +cl: Cl.Client, +line: String, +now_ms: U32) -> State:
  +clean = Irc.strip_cr(line)
  apply_maybe(state, event_for.parsed(cl, Irc.parse(clean), Irc.typing_tag(Irc.raw_tags(clean))), now_ms)

def apply_line_for_with(+cm: String, +types: String, +status: String, +sigils: String, +state: State, +cl: Cl.Client, +line: String, +now_ms: U32) -> State:
  +clean = Irc.strip_cr(line)
  apply_maybe_cm(cm, state, event_for_with.parsed(cm, types, status, sigils, cl, Irc.parse(clean), Irc.typing_tag(Irc.raw_tags(clean))), now_ms)

def apply_lines.step(acc: State & U32, line: String) -> State & U32:
  match acc:
    case (+state, +now_ms):
      (apply_line(state, line, now_ms), now_ms)

def apply_lines.result(pair: State & U32) -> State:
  match pair:
    case (result, _):
      result

def apply_lines(+state: State, +lines: List<&2, String>, +now_ms: U32) -> State:
  apply_lines.result(List.foldl(~&2, ~String, ~(State & U32), ~apply_lines.step, lines, (state, now_ms)))

def lifetime(status: Irc.TypingStatus) -> U32:
  match status:
    case Irc.TypingActive{}: ACTIVE_MS()
    case Irc.TypingPaused{}: PAUSED_MS()
    case Irc.TypingDone{}: 0

def alive.elapsed(status: Irc.TypingStatus, +elapsed: U32, stale_tick: Bool) -> Bool:
  match stale_tick:
    case True{}:
      True{}
    case False{}:
      U32.is_lt(elapsed, lifetime(status))

def alive(+e: Entry, +now_ms: U32) -> Bool:
  match e:
    case Entry{_, _, status, seen_ms}:
      +elapsed = U32.sub(now_ms, seen_ms)
      alive.elapsed(status, elapsed, U32.is_ge(elapsed, 2147483648))

def expire.keep(+h: Entry, tail: List<&2, Entry>, keep: Bool) -> List<&2, Entry>:
  match keep:
    case True{}: h <> tail
    case False{}: tail

def expire_entries(xs: List<&2, Entry>, +now_ms: U32) -> List<&2, Entry>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      expire.keep(h, expire_entries(t, now_ms), alive(h, now_ms))

def expire(+state: State, +now_ms: U32) -> State:
  match state:
    case State{+entries}:
      State{expire_entries(entries, now_ms)}

def target_open.got(found: Maybe<&2, Nat>) -> Bool:
  match found:
    case None{}: False{}
    case Some{_}: True{}

def target_open(+cl: Cl.Client, +target: String) -> Bool:
  target_open.got(Cl.buf_find(cl, target))

def target_open_cm(+cm: String, +cl: Cl.Client, +target: String) -> Bool:
  target_open.got(Cl.buf_find_cm(cl, cm, target))

def retain_open.pick(+h: Entry, tail: List<&2, Entry>, keep: Bool) -> List<&2, Entry>:
  match keep:
    case True{}: h <> tail
    case False{}: tail

def retain_open.keep(+h: Entry, tail: List<&2, Entry>, +cl: Cl.Client) -> List<&2, Entry>:
  match h:
    case Entry{+target, _, _, _}:
      retain_open.pick(h, tail, target_open(cl, target))

def retain_open.keep_cm(+cm: String, +h: Entry, tail: List<&2, Entry>, +cl: Cl.Client) -> List<&2, Entry>:
  match h:
    case Entry{+target, _, _, _}:
      retain_open.pick(h, tail, target_open_cm(cm, cl, target))

def retain_open_entries(xs: List<&2, Entry>, +cl: Cl.Client) -> List<&2, Entry>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      retain_open.keep(h, retain_open_entries(t, cl), cl)

def retain_open_entries_cm(+cm: String, xs: List<&2, Entry>, +cl: Cl.Client) -> List<&2, Entry>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      retain_open.keep_cm(cm, h, retain_open_entries_cm(cm, t, cl), cl)

def retain_client(+state: State, +cl: Cl.Client) -> State:
  match state:
    case State{+entries}:
      State{retain_open_entries(entries, cl)}

def retain_client_cm(+cm: String, +state: State, +cl: Cl.Client) -> State:
  match state:
    case State{+entries}:
      State{retain_open_entries_cm(cm, entries, cl)}

def expire_changed(+state: State, +now_ms: U32) -> State & Bool:
  +before = count(state)
  +after = expire(state, now_ms)
  (after, Bool.not(Nat.is_eq(before, count(after))))

def names.pick(+nick: String, tail: List<&2, String>, hit: Bool) -> List<&2, String>:
  match hit:
    case True{}: nick <> tail
    case False{}: tail

def names.keep(+h: Entry, tail: List<&2, String>, +target: String) -> List<&2, String>:
  match h:
    case Entry{+t, +nick, _, _}:
      names.pick(nick, tail, Irc.ieq(t, target))

def names.keep_cm(+cm: String, +h: Entry, tail: List<&2, String>, +target: String) -> List<&2, String>:
  match h:
    case Entry{+t, +nick, _, _}:
      names.pick(nick, tail, Cl.buf_eq_cm(cm, t, target))

def names_entries(xs: List<&2, Entry>, +target: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      names.keep(h, names_entries(t, target), target)

def names_entries_cm(+cm: String, xs: List<&2, Entry>, +target: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      names.keep_cm(cm, h, names_entries_cm(cm, t, target), target)

def names(+state: State, +target: String) -> List<&2, String>:
  match state:
    case State{+entries}:
      names_entries(entries, target)

def names_cm(+cm: String, +state: State, +target: String) -> List<&2, String>:
  match state:
    case State{+entries}:
      names_entries_cm(cm, entries, target)

# Small concrete predicates used by LAWS.bend. General expiry behavior is
# exercised at both boundaries in tests/bend/typing_demo.bend.
def active_boundary_ok() -> Bool:
  +state = apply_line(empty(), "@+typing=active :alice!a@h TAGMSG #birc", 1000)
  has(expire(state, 6999), "#birc", "alice")
    && Bool.not(has(expire(state, 7000), "#birc", "alice"))

def message_clear_ok() -> Bool:
  +active = apply_line(empty(), "@+typing=active :alice!a@h TAGMSG #birc", 1000)
  +privmsg = apply_line(active, "@+typing=active :alice!a@h PRIVMSG #birc :hello", 1100)
  +paused = apply_line(empty(), "@+typing=paused :alice!a@h TAGMSG me", 1000)
  +notice = apply_line(paused, "@+typing=paused :alice!a@h NOTICE me :hello", 1100)
  Bool.not(has(privmsg, "#birc", "alice"))
    && Bool.not(has(notice, "alice", "alice"))

def stale_tick_ok() -> Bool:
  +state = apply_line(empty(), "@+typing=active :alice!a@h TAGMSG #birc", 1001)
  has(expire(state, 1000), "#birc", "alice")
