# Desired channels and runtime-only keys for one endpoint. Registration and
# this connection's verified authentication must precede the recovery JOINs.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./auth.bend as Auth
import ./channel_policy.bend as Channels
import ./isupport.bend as Isupport

type Channel is Data:
  Channel{name: String, key: String}

type Report is Data:
  Unreported{}
  WaitingReported{}
  FailedReported{}

type Barrier is Data:
  NoAuth{}
  NeedAuth{baseline: Nat, report: Report}

type State is Data:
  State{desired: List<&2, Channel>, welcome: Bool, sent: Bool, barrier: Barrier, held: Bool, revision: Nat, motd_done: Bool}

type Notice is Data:
  Quiet{}
  Held{}
  Failed{}

type Flush is Data:
  Flush{state: State, outs: List<&2, String>, notice: Notice}

def channel_line(+name: String, +key: String) -> String:
  Channels.line(name, key)

def MAX_CHANNELS() -> Nat:
  Channels.MAX_CHANNELS()

def valid_channel(+name: String, +key: String) -> Bool:
  Channels.valid(name, key)

def has_cm(xs: List<&2, Channel>, +name: String, +cm: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Channel{stored, _}, rest}: Cl.buf_eq_cm(cm, stored, name) || has_cm(rest, name, cm)

def has(xs: List<&2, Channel>, +name: String) -> Bool:
  has_cm(xs, name, Cl.dflt_cm())

def has_exact(xs: List<&2, Channel>, +name: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Channel{stored, _}, rest}: String.eq(stored, name) || has_exact(rest, name)

def choose(on: Bool, yes: List<&2, Channel>, no: Unit -> List<&2, Channel>) -> List<&2, Channel>:
  match on:
    case True{}: yes
    case False{}: no(Unit{})

def put_cm(xs: List<&2, Channel>, +name: String, +key: String, +replace: Bool, +cm: String) -> List<&2, Channel>:
  match xs:
    case Nil{}: Channel{name, key} <> Nil{}
    case Con{Channel{+stored, +old_key}, +rest}:
      choose(Cl.buf_eq_cm(cm, stored, name), Channel{stored, Bool.pick(String, replace, key, old_key)} <> rest,
        _ => Channel{stored, old_key} <> put_cm(rest, name, key, replace, cm))

def put(xs: List<&2, Channel>, +name: String, +key: String, +replace: Bool) -> List<&2, Channel>:
  put_cm(xs, name, key, replace, Cl.dflt_cm())

def remember.allowed_cm(allowed: Bool, state: State, +name: String, +key: String, replace: Bool, +cm: String) -> State:
  match allowed:
    case False{}: state
    case True{}:
      match state:
        case State{desired, welcome, sent, barrier, held, revision, motd_done}: State{put_cm(desired, name, key, replace, cm), welcome, sent, barrier, held, revision, motd_done}

def remember.allowed(allowed: Bool, state: State, +name: String, +key: String, replace: Bool) -> State:
  remember.allowed_cm(allowed, state, name, key, replace, Cl.dflt_cm())

def remember(+state: State, +name: String, +key: String, replace: Bool) -> State:
  match state:
    case State{+desired, _, _, _, _, _, _}:
      remember.allowed(valid_channel(name, key)
        && (has(desired, name) || Nat.is_lt(List.length(&2, Channel, desired), MAX_CHANNELS())), state, name, key, replace)

def remember_iso(+state: State, +name: String, +key: String, replace: Bool, +iso: Isupport.State) -> State:
  match state:
    case State{+desired, _, _, _, _, _, _}:
      +cm = Isupport.casemapping(iso)
      remember.allowed_cm(Isupport.join_admit(iso, name, key)
        && (has_cm(desired, name, cm) || Nat.is_lt(List.length(&2, Channel, desired), MAX_CHANNELS())), state, name, key, replace, cm)

def remove_cm(xs: List<&2, Channel>, +name: String, +cm: String) -> List<&2, Channel>:
  match xs:
    case Nil{}: Nil{}
    case Con{Channel{+stored, key}, +rest}:
      choose(Cl.buf_eq_cm(cm, stored, name), rest, _ => Channel{stored, key} <> remove_cm(rest, name, cm))

def remove(xs: List<&2, Channel>, +name: String) -> List<&2, Channel>:
  remove_cm(xs, name, Cl.dflt_cm())

def forget(state: State, name: String) -> State:
  match state:
    case State{desired, welcome, sent, barrier, held, revision, motd_done}: State{remove(desired, name), welcome, sent, barrier, held, revision, motd_done}

def forget_cm(state: State, name: String, +cm: String) -> State:
  match state:
    case State{desired, welcome, sent, barrier, held, revision, motd_done}: State{remove_cm(desired, name, cm), welcome, sent, barrier, held, revision, motd_done}

def forget_all(state: State) -> State:
  match state:
    case State{_, welcome, sent, barrier, held, revision, motd_done}: State{Nil{}, welcome, sent, barrier, held, revision, motd_done}

def initial_iso.names(names: List<&2, String>, state: State, +iso: Isupport.State) -> State:
  match names:
    case Nil{}: state
    case Con{name, rest}: initial_iso.names(rest, remember_iso(state, name, "", True{}, iso), iso)

def initial_iso.parsed(parsed: Maybe<&2, List<&2, String>>, state: State, +iso: Isupport.State) -> State:
  match parsed:
    case None{}: state
    case Some{names}: initial_iso.names(names, state, iso)

def initial_iso(chan: String, +iso: Isupport.State) -> State:
  initial_iso.parsed(Channels.launch_names(chan), State{Nil{}, False{}, False{}, NoAuth{}, False{}, 0n, False{}}, iso)

def initial(chan: String) -> State:
  initial_iso(chan, Isupport.defaults())

def compat.state(+joined: Bool, state: State) -> State:
  match state:
    case State{desired, _, _, _, held, revision, motd_done}: State{desired, joined, joined, NoAuth{}, held, revision, motd_done}

def compat(+chan: String, joined: Bool) -> State:
  compat.state(joined, initial(chan))

def demo(chan: String) -> State:
  compat(chan, True{})

def sent(state: State) -> Bool:
  match state:
    case State{_, _, sent, _, _, _, _}: sent

def welcomed(state: State) -> Bool:
  match state:
    case State{_, welcome, _, _, _, _, _}: welcome

def reset.barrier(required: Bool, baseline: Nat) -> Barrier:
  match required:
    case False{}: NoAuth{}
    case True{}: NeedAuth{baseline, Unreported{}}

def reset(state: State, +cl: Cl.Client, +live_port: U32) -> State:
  match state:
    case State{desired, _, _, _, held, revision, _}:
      State{desired, False{}, False{}, reset.barrier(Auth.join_required(cl, live_port), Cl.auth_success_seq(cl)), held, revision, False{}}

def revision(state: State) -> Nat:
  match state:
    case State{_, _, _, _, _, revision, _}: revision

def bump(state: State) -> State:
  match state:
    case State{desired, welcome, sent, barrier, held, revision, motd_done}:
      State{desired, welcome, sent, barrier, held, Nat.add(revision, 1n), motd_done}

def endpoint.fresh(state: State, chan: String, cl: Cl.Client, +live_port: U32) -> State:
  match state:
    case State{_, _, _, _, held, revision, _}:
      reset(initial_iso.parsed(Channels.launch_names(chan), State{Nil{}, False{}, False{}, NoAuth{}, held, revision, False{}}, Isupport.defaults()), cl, live_port)

def endpoint(same: Bool, state: State, chan: String, cl: Cl.Client, +live_port: U32) -> State:
  match same:
    case True{}: reset(state, cl, live_port)
    case False{}: endpoint.fresh(state, chan, cl, live_port)

def desired_names.go(xs: List<&2, Channel>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Channel{name, _}, rest}: name <> desired_names.go(rest)

def desired_names(state: State) -> List<&2, String>:
  match state:
    case State{desired, _, _, _, _, _, _}: desired_names.go(desired)

def set_held(state: State, held: Bool) -> State:
  match state:
    case State{desired, welcome, sent, barrier, _, revision, motd_done}: State{desired, welcome, sent, barrier, held, revision, motd_done}

# Preserve overlapping keys when a names-only startup snapshot is installed.
# Revision is checked by Session; configuration never receives these keys.
def choose_key(found: Bool, secret: String, otherwise: Unit -> String) -> String:
  match found:
    case True{}: secret
    case False{}: otherwise(Unit{})

def key_cm(xs: List<&2, Channel>, +name: String, +cm: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{Channel{+stored, secret}, rest}: choose_key(Cl.buf_eq_cm(cm, stored, name), secret, _ => key_cm(rest, name, cm))

def key(xs: List<&2, Channel>, +name: String) -> String:
  key_cm(xs, name, Cl.dflt_cm())

def key_exact(xs: List<&2, Channel>, +name: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{Channel{stored, secret}, rest}:
      choose_key(String.eq(stored, name), secret, _ => key_exact(rest, name))

def put_exact(xs: List<&2, Channel>, +name: String, +key: String) -> List<&2, Channel>:
  match xs:
    case Nil{}: Channel{name, key} <> Nil{}
    case Con{Channel{+stored, +old_key}, +rest}:
      choose(String.eq(stored, name), Channel{stored, key} <> rest,
        _ => Channel{stored, old_key} <> put_exact(rest, name, key))

def seed_candidate.allowed(allowed: Bool, state: State, +name: String, +key: String) -> State:
  match allowed:
    case False{}: state
    case True{}:
      match state:
        case State{desired, welcome, sent, barrier, held, revision, motd_done}:
          State{put_exact(desired, name, key), welcome, sent, barrier, held, revision, motd_done}

def seed_candidate.head(+h: Char, +tail: String, +name: String, +key: String) -> Bool:
  +c = Char.to_u32(h)
  U32.is_ge(c, 33) && U32.is_le(c, 126)
    && Bool.not((U32.is_ge(c, 48) && U32.is_le(c, 57))
      || (U32.is_ge(c, 65) && U32.is_le(c, 90))
      || (U32.is_ge(c, 97) && U32.is_le(c, 122)))
    && Bool.not(U32.is_eq(c, 44) || U32.is_eq(c, 58))
    && Cl.target_wire(name) && String.eq(name, Cl.target_name(name))
    && Channels.valid("#" ++ tail, key)

def seed_candidate.valid(+name: String, +key: String) -> Bool:
  match name:
    case SNil{}: False{}
    case SCon{+h, +tail}: seed_candidate.head(h, tail, name, key)

def seed_candidate(+state: State, +name: String, +key: String) -> State:
  match state:
    case State{+desired, _, _, _, _, _, _}:
      seed_candidate.allowed((has_exact(desired, name) || Nat.is_lt(List.length(&2, Channel, desired), MAX_CHANNELS()))
        && seed_candidate.valid(name, key), state, name, key)

def seed_channels_iso(names: List<&2, String>, +prior: List<&2, Channel>, state: State, +iso: Isupport.State) -> State:
  match names:
    case Nil{}: state
    case Con{+name, rest}:
      seed_channels_iso(rest, prior, seed_candidate(state, name, key_exact(prior, name)), iso)

def seed_iso.ready(+state: State, names: List<&2, String>, +iso: Isupport.State) -> State:
  match state:
    case State{+desired, welcome, sent, barrier, held, revision, motd_done}:
      seed_channels_iso(names, desired, State{Nil{}, welcome, sent, barrier, held, revision, motd_done}, iso)

def seed_iso(+state: State, names: List<&2, String>, +iso: Isupport.State) -> State:
  seed_iso.ready(state, names, iso)

def seed(+state: State, names: List<&2, String>) -> State:
  seed_iso(state, names, Isupport.defaults())

def editing_open(state: State) -> Bool:
  match state:
    case State{_, _, sent, _, held, _, _}: sent && Bool.not(held)

def join_targets(targets: List<&2, String>, keys: List<&2, String>, state: State) -> State:
  match targets:
    case Nil{}: state
    case Con{+target, rest}:
      match keys:
        case Nil{}: join_targets(rest, Nil{}, remember(state, target, "", True{}))
        case Con{key, key_rest}: join_targets(rest, key_rest, remember(state, target, key, True{}))

def join_targets_iso(targets: List<&2, String>, keys: List<&2, String>, state: State, +iso: Isupport.State) -> State:
  match targets:
    case Nil{}: state
    case Con{+target, rest}:
      match keys:
        case Nil{}: join_targets_iso(rest, Nil{}, remember_iso(state, target, "", True{}, iso), iso)
        case Con{key, key_rest}: join_targets_iso(rest, key_rest, remember_iso(state, target, key, True{}, iso), iso)

def part_targets(targets: List<&2, String>, state: State) -> State:
  match targets:
    case Nil{}: state
    case Con{target, rest}: part_targets(rest, forget(state, target))

def part_targets_cm(targets: List<&2, String>, state: State, +cm: String) -> State:
  match targets:
    case Nil{}: state
    case Con{target, rest}: part_targets_cm(rest, forget_cm(state, target, cm), cm)

def outbound_join(zero: Bool, +state: State, +m: Irc.Message) -> State:
  match zero:
    case True{}: forget_all(state)
    case False{}: join_targets(String.split(Irc.msg_param(m, 0n), Chr{44}), String.split(Irc.msg_param(m, 1n), Chr{44}), state)

def outbound_join_iso(zero: Bool, +state: State, +m: Irc.Message, +iso: Isupport.State) -> State:
  match zero:
    case True{}: forget_all(state)
    case False{}: join_targets_iso(String.split(Irc.msg_param(m, 0n), Chr{44}), String.split(Irc.msg_param(m, 1n), Chr{44}), state, iso)

# Count the complete distinct union before changing any key or membership.
# An existing channel consumes no new slot; malformed raw targets remain the
# server's concern and cannot create desired channel intent.
def join_capacity.add_cm(new: Bool, room: Bool, +desired: List<&2, Channel>, name: String, +cm: String, k: List<&2, Channel> -> Bool) -> Bool:
  match new:
    case False{}: k(desired)
    case True{}:
      match room:
        case False{}: False{}
        case True{}: k(put_cm(desired, name, "", False{}, cm))

def join_capacity.add(new: Bool, room: Bool, +desired: List<&2, Channel>, name: String, k: List<&2, Channel> -> Bool) -> Bool:
  join_capacity.add_cm(new, room, desired, name, Cl.dflt_cm(), k)

def join_capacity.targets(targets: List<&2, String>, +desired: List<&2, Channel>) -> Bool:
  match targets:
    case Nil{}: True{}
    case Con{+name, rest}:
      join_capacity.add(valid_channel(name, "") && Bool.not(has(desired, name)),
        Nat.is_lt(List.length(&2, Channel, desired), MAX_CHANNELS()), desired, name,
        next => join_capacity.targets(rest, next))

def join_capacity(state: State, m: Irc.Message) -> Bool:
  match state:
    case State{desired, _, _, _, _, _, _}:
      join_capacity.targets(String.split(Irc.msg_param(m, 0n), Chr{44}), desired)

def join_capacity.targets_iso(targets: List<&2, String>, +desired: List<&2, Channel>, +iso: Isupport.State) -> Bool:
  match targets:
    case Nil{}: True{}
    case Con{+name, rest}:
      +cm = Isupport.casemapping(iso)
      join_capacity.add_cm(Isupport.join_admit(iso, name, "") && Bool.not(has_cm(desired, name, cm)),
        Nat.is_lt(List.length(&2, Channel, desired), MAX_CHANNELS()), desired, name, cm,
        next => join_capacity.targets_iso(rest, next, iso))

def join_capacity_iso(state: State, m: Irc.Message, +iso: Isupport.State) -> Bool:
  match state:
    case State{desired, _, _, _, _, _, _}:
      join_capacity.targets_iso(String.split(Irc.msg_param(m, 0n), Chr{44}), desired, iso)

def capacity_command(state: State, +m: Irc.Message, cmd: Irc.Cmd) -> State:
  match cmd:
    case Irc.Join{}: outbound_join(String.eq(Irc.msg_param(m, 0n), "0"), state, m)
    case Irc.Part{}: part_targets(String.split(Irc.msg_param(m, 0n), Chr{44}), state)
    case _: state

def capacity_step(allowed: Bool, state: State, m: Irc.Message, cmd: Irc.Cmd, k: State -> Bool) -> Bool:
  match allowed:
    case False{}: False{}
    case True{}: k(capacity_command(state, m, cmd))

def capacity_line(parsed: Maybe<&2, Irc.Message>, +state: State, k: State -> Bool) -> Bool:
  match parsed:
    case None{}: k(state)
    case Some{+m}:
      capacity_step(Bool.not(Irc.ieq(Irc.msg_command(m), "JOIN")) || join_capacity(state, m),
        state, m, Irc.classify(m), k)

# Submission may stage local buffers. Preflight its whole batch against the
# same admission rule before Session keeps those local changes.
def capacity_ok(outs: List<&2, String>, state: State) -> Bool:
  match outs:
    case Nil{}: True{}
    case Con{line, rest}: capacity_line(Irc.parse(line), state, next => capacity_ok(rest, next))

def capacity_command_iso(state: State, +m: Irc.Message, cmd: Irc.Cmd, +iso: Isupport.State) -> State:
  match cmd:
    case Irc.Join{}: outbound_join_iso(String.eq(Irc.msg_param(m, 0n), "0"), state, m, iso)
    case Irc.Part{}: part_targets_cm(String.split(Irc.msg_param(m, 0n), Chr{44}), state, Isupport.casemapping(iso))
    case _: state

def capacity_line_iso.step(allowed: Bool, state: State, m: Irc.Message, cmd: Irc.Cmd, +iso: Isupport.State, k: State -> Bool) -> Bool:
  match allowed:
    case False{}: False{}
    case True{}: k(capacity_command_iso(state, m, cmd, iso))

def capacity_line_iso(parsed: Maybe<&2, Irc.Message>, +state: State, +iso: Isupport.State, k: State -> Bool) -> Bool:
  match parsed:
    case None{}: k(state)
    case Some{+m}:
      capacity_line_iso.step(Bool.not(Irc.ieq(Irc.msg_command(m), "JOIN")) || join_capacity_iso(state, m, iso),
        state, m, Irc.classify(m), iso, k)

def capacity_ok_iso(outs: List<&2, String>, state: State, +iso: Isupport.State) -> Bool:
  match outs:
    case Nil{}: True{}
    case Con{line, rest}: capacity_line_iso(Irc.parse(line), state, iso, next => capacity_ok_iso(rest, next, iso))

type OutAcc is Data:
  OutAcc{state: State, reversed: List<&2, String>}

def outbound.pass(allowed: Bool, state: State, reversed: List<&2, String>, line: String) -> OutAcc:
  match allowed:
    case False{}: OutAcc{state, reversed}
    case True{}: OutAcc{state, line <> reversed}

def outbound.join(allowed: Bool, +state: State, reversed: List<&2, String>, +line: String, +m: Irc.Message) -> OutAcc:
  match allowed:
    case False{}: OutAcc{state, reversed}
    case True{}:
      +zero = String.eq(Irc.msg_param(m, 0n), "0")
      outbound.pass(editing_open(state) || zero, bump(outbound_join(zero, state, m)), reversed, line)

def outbound.command(+state: State, reversed: List<&2, String>, +line: String, +m: Irc.Message, cmd: Irc.Cmd) -> OutAcc:
  match cmd:
    case Irc.Join{}:
      outbound.join(join_capacity(state, m), state, reversed, line, m)
    case Irc.Part{}: OutAcc{bump(part_targets(String.split(Irc.msg_param(m, 0n), Chr{44}), state)), line <> reversed}
    case _: OutAcc{state, line <> reversed}

def outbound.parsed(+state: State, reversed: List<&2, String>, +line: String, parsed: Maybe<&2, Irc.Message>) -> OutAcc:
  match parsed:
    case None{}: OutAcc{state, line <> reversed}
    case Some{+m}: outbound.command(state, reversed, line, m, Irc.classify(m))

def outbound.step(acc: OutAcc, line: String) -> OutAcc:
  match acc:
    case OutAcc{state, reversed}:
      +wire = line
      outbound.parsed(state, reversed, wire, Irc.parse(wire))

def outbound.finish(acc: OutAcc) -> State & List<&2, String>:
  match acc:
    case OutAcc{state, reversed}: (state, List.reverse(&2, String, reversed))

def outbound(state: State, outs: List<&2, String>) -> State & List<&2, String>:
  outbound.finish(List.foldl(~&2, ~String, ~OutAcc, ~outbound.step, outs, OutAcc{state, Nil{}}))

def outbound.join_iso(allowed: Bool, +state: State, reversed: List<&2, String>, +line: String, +m: Irc.Message, +iso: Isupport.State) -> OutAcc:
  match allowed:
    case False{}: OutAcc{state, reversed}
    case True{}:
      +zero = String.eq(Irc.msg_param(m, 0n), "0")
      outbound.pass(editing_open(state) || zero, bump(outbound_join_iso(zero, state, m, iso)), reversed, line)

def outbound.command_iso(+state: State, reversed: List<&2, String>, +line: String, +m: Irc.Message, cmd: Irc.Cmd, +iso: Isupport.State) -> OutAcc:
  match cmd:
    case Irc.Join{}:
      outbound.join_iso(join_capacity_iso(state, m, iso), state, reversed, line, m, iso)
    case Irc.Part{}: OutAcc{bump(part_targets_cm(String.split(Irc.msg_param(m, 0n), Chr{44}), state, Isupport.casemapping(iso))), line <> reversed}
    case _: OutAcc{state, line <> reversed}

def outbound.parsed_iso(+state: State, reversed: List<&2, String>, +line: String, parsed: Maybe<&2, Irc.Message>, +iso: Isupport.State) -> OutAcc:
  match parsed:
    case None{}: OutAcc{state, line <> reversed}
    case Some{+m}: outbound.command_iso(state, reversed, line, m, Irc.classify(m), iso)

def outbound.step_iso(+iso: Isupport.State, acc: OutAcc, line: String) -> OutAcc:
  match acc:
    case OutAcc{state, reversed}:
      +wire = line
      outbound.parsed_iso(state, reversed, wire, Irc.parse(wire), iso)

def outbound.go_iso(outs: List<&2, String>, acc: OutAcc, +iso: Isupport.State) -> OutAcc:
  match outs:
    case Nil{}: acc
    case Con{line, rest}: outbound.go_iso(rest, outbound.step_iso(iso, acc, line), iso)

def outbound_iso(state: State, outs: List<&2, String>, +iso: Isupport.State) -> State & List<&2, String>:
  outbound.finish(outbound.go_iso(outs, OutAcc{state, Nil{}}, iso))

def forget_present.on(present: Bool, state: State, name: String) -> State:
  match present:
    case False{}: state
    case True{}: bump(forget(state, name))

def forget_present(+state: State, +name: String) -> State:
  match state:
    case State{+desired, _, _, _, _, _, _}: forget_present.on(has(desired, name), state, name)

def forget_present_cm.on(present: Bool, state: State, name: String, cm: String) -> State:
  match present:
    case False{}: state
    case True{}: bump(forget_cm(state, name, cm))

def forget_present_cm(+state: State, +name: String, +cm: String) -> State:
  match state:
    case State{+desired, _, _, _, _, _, _}: forget_present_cm.on(has_cm(desired, name, cm), state, name, cm)

def received.kick(self: Bool, state: State, name: String) -> State:
  match self:
    case False{}: state
    case True{}: forget_present(state, name)

# Accepted local/raw JOIN/PART commands already own desired membership.
# Their delayed server echoes must not revive a PART or erase a newer key.
# Client still consumes those events for roster/history; a self KICK is a
# distinct server-side refusal and cancels intent until an explicit JOIN.
def received.command(+state: State, +cl: Cl.Client, +m: Irc.Message, cmd: Irc.Cmd) -> State:
  match cmd:
    case Irc.Kick{}: received.kick(Irc.ieq(Irc.proto_atom(Irc.msg_param(m, 1n)), Cl.nick_of(cl)), state, Irc.proto_atom(Irc.msg_param(m, 0n)))
    case _: state

def motd_num(+num: U32) -> Bool:
  U32.is_eq(num, 376) || U32.is_eq(num, 422)

def motd_control_with(+cm: String, +cl: Cl.Client, +line: String, +m: Irc.Message) -> Bool:
  motd_num(Irc.msg_num(m))
    && Irc.source_is_server(Irc.source_prefix(line), Cl.server_of(cl))
    && Cl.buf_eq_cm(cm, Irc.proto_atom(Irc.msg_param(m, 0n)), Cl.nick_of(cl))

def received.control(welcome: Bool, motd: Bool, state: State, cl: Cl.Client, +m: Irc.Message) -> State:
  match welcome motd:
    case True{} _:
      match state:
        case State{desired, _, sent, barrier, held, revision, motd_done}: State{desired, True{}, sent, barrier, held, revision, motd_done}
    case False{} True{}:
      match state:
        case State{desired, +was_welcome, sent, barrier, held, revision, _}: State{desired, was_welcome, sent, barrier, held, revision, was_welcome}
    case False{} False{}: received.command(state, cl, m, Irc.classify(m))

def received.parsed(state: State, +cl: Cl.Client, +line: String, parsed: Maybe<&2, Irc.Message>) -> State:
  match parsed:
    case None{}: state
    case Some{+m}:
      received.control(U32.is_eq(Irc.msg_num(m), 1) && Auth.server_control(cl, Irc.source_prefix(line), m),
        motd_control_with(Cl.dflt_cm(), cl, line, m), state, cl, m)

def received(state: State, +cl: Cl.Client, +line: String) -> State:
  received.parsed(state, cl, line, Irc.parse(line))

# Negotiated KICK victim (I2-dynamic2 F1): the self-KICK refusal that cancels
# desired membership compares the victim under the Session CASEMAPPING.
# Welcome detection keeps the fixed auth control (never forked).
def received.kick_with(self: Bool, state: State, name: String, cm: String) -> State:
  match self:
    case False{}: state
    case True{}: forget_present_cm(state, name, cm)

def received.command_with(+cm: String, +state: State, +cl: Cl.Client, +m: Irc.Message, cmd: Irc.Cmd) -> State:
  match cmd:
    case Irc.Kick{}: received.kick_with(Cl.buf_eq_cm(cm, Irc.proto_atom(Irc.msg_param(m, 1n)), Cl.nick_of(cl)), state, Irc.proto_atom(Irc.msg_param(m, 0n)), cm)
    case _: state

def received.control_with(+cm: String, welcome: Bool, motd: Bool, state: State, cl: Cl.Client, +m: Irc.Message) -> State:
  match welcome motd:
    case True{} _:
      match state:
        case State{desired, _, sent, barrier, held, revision, motd_done}: State{desired, True{}, sent, barrier, held, revision, motd_done}
    case False{} True{}:
      match state:
        case State{desired, +was_welcome, sent, barrier, held, revision, _}: State{desired, was_welcome, sent, barrier, held, revision, was_welcome}
    case False{} False{}: received.command_with(cm, state, cl, m, Irc.classify(m))

def received.parsed_with(+cm: String, state: State, +cl: Cl.Client, +line: String, parsed: Maybe<&2, Irc.Message>) -> State:
  match parsed:
    case None{}: state
    case Some{+m}:
      received.control_with(cm, U32.is_eq(Irc.msg_num(m), 1) && Auth.server_control(cl, Irc.source_prefix(line), m),
        motd_control_with(cm, cl, line, m), state, cl, m)

def received_with(+cm: String, state: State, +cl: Cl.Client, +line: String) -> State:
  received.parsed_with(cm, state, cl, line, Irc.parse(line))

def ready(barrier: Barrier, +cl: Cl.Client) -> Bool:
  match barrier:
    case NoAuth{}: True{}
    case NeedAuth{baseline, _}: Nat.is_gt(Cl.auth_success_seq(cl), baseline)

def lines(desired: List<&2, Channel>) -> List<&2, String>:
  match desired:
    case Nil{}: Nil{}
    case Con{Channel{name, key}, rest}: channel_line(name, key) <> lines(rest)

# Explicit outcomes: AuthHeld is registration-before-SASL-completion (still
# waiting). AuthDone without a success_seq advance is terminal failure
# (904/NAK/NickFailed). Success advances success_seq past the barrier baseline.
def failed(phase: Cl.AuthPhase, +baseline: Nat, +seq: Nat) -> Bool:
  match phase:
    case Cl.AuthDone{}: Bool.not(Nat.is_gt(seq, baseline))
    case Cl.AuthHeld{_}: False{}
    case _: False{}

def hold.report(report: Report, failed: Bool) -> Report & Notice:
  match report failed:
    case FailedReported{} _: (FailedReported{}, Quiet{})
    case _ True{}: (FailedReported{}, Failed{})
    case Unreported{} False{}: (WaitingReported{}, Held{})
    case WaitingReported{} False{}: (WaitingReported{}, Quiet{})

def hold.done(pair: Report & Notice, desired: List<&2, Channel>, welcome: Bool, baseline: Nat, held: Bool, revision: Nat, motd_done: Bool) -> Flush:
  match pair:
    case (report, notice): Flush{State{desired, welcome, False{}, NeedAuth{baseline, report}, held, revision, motd_done}, Nil{}, notice}

def hold(state: State, +cl: Cl.Client) -> Flush:
  match state:
    case State{+desired, welcome, sent, barrier, held, revision, motd_done}:
      match barrier:
        case NoAuth{}: Flush{State{desired, welcome, sent, NoAuth{}, held, revision, motd_done}, Nil{}, Quiet{}}
        case NeedAuth{+baseline, report}:
          hold.done(hold.report(report, failed(Cl.get_auth(cl), baseline, Cl.auth_success_seq(cl))), desired, welcome, baseline, held, revision, motd_done)

# Recovery flush applies every trusted pre-MOTD 005 bound and casemap exactly
# once. Preference candidates stay exact until 376/422, so provisional or
# partial bursts neither drop negotiated-only names nor fold ASCII identities.
def admitted.keep(keep: Bool, kept: List<&2, Channel>, +name: String, +key: String) -> List<&2, Channel>:
  match keep:
    case True{}: List.append(&2, Channel, kept, Channel{name, key} <> Nil{})
    case False{}: kept

def admitted.go(+xs: List<&2, Channel>, +kept: List<&2, Channel>, +cm: String, +iso: Isupport.State) -> List<&2, Channel>:
  match xs:
    case Nil{}: kept
    case Con{Channel{+name, +key}, +rest}:
      admitted.go(rest, admitted.keep(Isupport.join_admit(iso, name, key) && Bool.not(has_cm(kept, name, cm)), kept, name, key), cm, iso)

def admitted(+xs: List<&2, Channel>, +iso: Isupport.State) -> List<&2, Channel>:
  admitted.go(xs, Nil{}, Isupport.casemapping(iso), iso)

def flush_iso.ready(ready: Bool, state: State, +cl: Cl.Client, +iso: Isupport.State) -> Flush:
  match ready:
    case False{}: hold(state, cl)
    case True{}:
      match state:
        case State{+desired, welcome, sent, barrier, held, revision, motd_done}:
          match motd_done:
            case False{}: Flush{State{desired, welcome, sent, barrier, held, revision, False{}}, Nil{}, Quiet{}}
            case True{}:
              +kept = admitted(desired, iso)
              Flush{State{kept, welcome, True{}, barrier, held, revision, True{}}, lines(kept), Quiet{}}

def flush_iso(+state: State, +cl: Cl.Client, +iso: Isupport.State) -> Flush:
  match state:
    case State{_, welcome, sent, +barrier, held, _, _}:
      match welcome sent held:
        case True{} False{} False{}:
          flush_iso.ready(ready(barrier, cl), state, cl, iso)
        case _ _ _: Flush{state, Nil{}, Quiet{}}

def flush(+state: State, +cl: Cl.Client) -> Flush:
  flush_iso(state, cl, Isupport.defaults())
