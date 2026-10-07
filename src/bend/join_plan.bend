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
  State{desired: List<&2, Channel>, welcome: Bool, sent: Bool, barrier: Barrier, held: Bool, revision: Nat}

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

def has(xs: List<&2, Channel>, +name: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Channel{stored, _}, rest}: Irc.ieq(stored, name) || has(rest, name)

def choose(on: Bool, yes: List<&2, Channel>, no: Unit -> List<&2, Channel>) -> List<&2, Channel>:
  match on:
    case True{}: yes
    case False{}: no(Unit{})

def put(xs: List<&2, Channel>, +name: String, +key: String, +replace: Bool) -> List<&2, Channel>:
  match xs:
    case Nil{}: Channel{name, key} <> Nil{}
    case Con{Channel{+stored, +old_key}, +rest}:
      choose(Irc.ieq(stored, name), Channel{stored, Bool.pick(String, replace, key, old_key)} <> rest,
        _ => Channel{stored, old_key} <> put(rest, name, key, replace))

def remember.allowed(allowed: Bool, state: State, +name: String, +key: String, replace: Bool) -> State:
  match allowed:
    case False{}: state
    case True{}:
      match state:
        case State{desired, welcome, sent, barrier, held, revision}: State{put(desired, name, key, replace), welcome, sent, barrier, held, revision}

def remember(+state: State, +name: String, +key: String, replace: Bool) -> State:
  match state:
    case State{+desired, _, _, _, _, _}:
      remember.allowed(valid_channel(name, key)
        && (has(desired, name) || Nat.is_lt(List.length(&2, Channel, desired), MAX_CHANNELS())), state, name, key, replace)

def remember_iso(+state: State, +name: String, +key: String, replace: Bool, +iso: Isupport.State) -> State:
  match state:
    case State{+desired, _, _, _, _, _}:
      remember.allowed(valid_channel(name, key) && Isupport.join_admit(iso, name, key)
        && (has(desired, name) || Nat.is_lt(List.length(&2, Channel, desired), MAX_CHANNELS())), state, name, key, replace)

def remove(xs: List<&2, Channel>, +name: String) -> List<&2, Channel>:
  match xs:
    case Nil{}: Nil{}
    case Con{Channel{+stored, key}, +rest}:
      choose(Irc.ieq(stored, name), rest, _ => Channel{stored, key} <> remove(rest, name))

def forget(state: State, name: String) -> State:
  match state:
    case State{desired, welcome, sent, barrier, held, revision}: State{remove(desired, name), welcome, sent, barrier, held, revision}

def forget_all(state: State) -> State:
  match state:
    case State{_, welcome, sent, barrier, held, revision}: State{Nil{}, welcome, sent, barrier, held, revision}

def initial_iso.names(names: List<&2, String>, state: State, +iso: Isupport.State) -> State:
  match names:
    case Nil{}: state
    case Con{name, rest}: initial_iso.names(rest, remember_iso(state, name, "", True{}, iso), iso)

def initial_iso.parsed(parsed: Maybe<&2, List<&2, String>>, state: State, +iso: Isupport.State) -> State:
  match parsed:
    case None{}: state
    case Some{names}: initial_iso.names(names, state, iso)

def initial_iso(chan: String, +iso: Isupport.State) -> State:
  initial_iso.parsed(Channels.launch_names(chan), State{Nil{}, False{}, False{}, NoAuth{}, False{}, 0n}, iso)

def initial(chan: String) -> State:
  initial_iso(chan, Isupport.defaults())

def compat.state(+joined: Bool, state: State) -> State:
  match state:
    case State{desired, _, _, _, held, revision}: State{desired, joined, joined, NoAuth{}, held, revision}

def compat(+chan: String, joined: Bool) -> State:
  compat.state(joined, initial(chan))

def demo(chan: String) -> State:
  compat(chan, True{})

def sent(state: State) -> Bool:
  match state:
    case State{_, _, sent, _, _, _}: sent

def welcomed(state: State) -> Bool:
  match state:
    case State{_, welcome, _, _, _, _}: welcome

def reset.barrier(required: Bool, baseline: Nat) -> Barrier:
  match required:
    case False{}: NoAuth{}
    case True{}: NeedAuth{baseline, Unreported{}}

def reset(state: State, +cl: Cl.Client) -> State:
  match state:
    case State{desired, _, _, _, held, revision}:
      State{desired, False{}, False{}, reset.barrier(Auth.join_required(cl), Cl.auth_success_seq(cl)), held, revision}

def revision(state: State) -> Nat:
  match state:
    case State{_, _, _, _, _, revision}: revision

def bump(state: State) -> State:
  match state:
    case State{desired, welcome, sent, barrier, held, revision}:
      State{desired, welcome, sent, barrier, held, Nat.add(revision, 1n)}

def endpoint.fresh(state: State, chan: String, cl: Cl.Client) -> State:
  match state:
    case State{_, _, _, _, held, revision}:
      reset(initial_iso.parsed(Channels.launch_names(chan), State{Nil{}, False{}, False{}, NoAuth{}, held, revision}, Isupport.defaults()), cl)

def endpoint(same: Bool, state: State, chan: String, cl: Cl.Client) -> State:
  match same:
    case True{}: reset(state, cl)
    case False{}: endpoint.fresh(state, chan, cl)

def desired_names.go(xs: List<&2, Channel>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Channel{name, _}, rest}: name <> desired_names.go(rest)

def desired_names(state: State) -> List<&2, String>:
  match state:
    case State{desired, _, _, _, _, _}: desired_names.go(desired)

def set_held(state: State, held: Bool) -> State:
  match state:
    case State{desired, welcome, sent, barrier, _, revision}: State{desired, welcome, sent, barrier, held, revision}

# Preserve overlapping keys when a names-only startup snapshot is installed.
# Revision is checked by Session; configuration never receives these keys.
def choose_key(found: Bool, secret: String, otherwise: Unit -> String) -> String:
  match found:
    case True{}: secret
    case False{}: otherwise(Unit{})

def key(xs: List<&2, Channel>, +name: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{Channel{+stored, secret}, rest}: choose_key(Irc.ieq(stored, name), secret, _ => key(rest, name))

def seed_channels(names: List<&2, String>, +prior: List<&2, Channel>, state: State) -> State:
  match names:
    case Nil{}: state
    case Con{+name, rest}: seed_channels(rest, prior, remember(state, name, key(prior, name), True{}))

def seed(+state: State, names: List<&2, String>) -> State:
  match state:
    case State{+desired, _, _, _, _, _}: seed_channels(names, desired, forget_all(state))

def editing_open(state: State) -> Bool:
  match state:
    case State{_, _, sent, _, held, _}: sent && Bool.not(held)

def join_targets(targets: List<&2, String>, keys: List<&2, String>, state: State) -> State:
  match targets:
    case Nil{}: state
    case Con{+target, rest}:
      match keys:
        case Nil{}: join_targets(rest, Nil{}, remember(state, target, "", True{}))
        case Con{key, key_rest}: join_targets(rest, key_rest, remember(state, target, key, True{}))

def part_targets(targets: List<&2, String>, state: State) -> State:
  match targets:
    case Nil{}: state
    case Con{target, rest}: part_targets(rest, forget(state, target))

def outbound_join(zero: Bool, +state: State, +m: Irc.Message) -> State:
  match zero:
    case True{}: forget_all(state)
    case False{}: join_targets(String.split(Irc.msg_param(m, 0n), Chr{44}), String.split(Irc.msg_param(m, 1n), Chr{44}), state)

# Count the complete distinct union before changing any key or membership.
# An existing channel consumes no new slot; malformed raw targets remain the
# server's concern and cannot create desired channel intent.
def join_capacity.add(new: Bool, room: Bool, +desired: List<&2, Channel>, name: String, k: List<&2, Channel> -> Bool) -> Bool:
  match new:
    case False{}: k(desired)
    case True{}:
      match room:
        case False{}: False{}
        case True{}: k(put(desired, name, "", False{}))

def join_capacity.targets(targets: List<&2, String>, +desired: List<&2, Channel>) -> Bool:
  match targets:
    case Nil{}: True{}
    case Con{+name, rest}:
      join_capacity.add(valid_channel(name, "") && Bool.not(has(desired, name)),
        Nat.is_lt(List.length(&2, Channel, desired), MAX_CHANNELS()), desired, name,
        next => join_capacity.targets(rest, next))

def join_capacity(state: State, m: Irc.Message) -> Bool:
  match state:
    case State{desired, _, _, _, _, _}:
      join_capacity.targets(String.split(Irc.msg_param(m, 0n), Chr{44}), desired)

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

def forget_present.on(present: Bool, state: State, name: String) -> State:
  match present:
    case False{}: state
    case True{}: bump(forget(state, name))

def forget_present(+state: State, +name: String) -> State:
  match state:
    case State{+desired, _, _, _, _, _}: forget_present.on(has(desired, name), state, name)

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

def received.welcome(welcome: Bool, state: State, cl: Cl.Client, +m: Irc.Message) -> State:
  match welcome:
    case False{}: received.command(state, cl, m, Irc.classify(m))
    case True{}:
      match state:
        case State{desired, _, sent, barrier, held, revision}: State{desired, True{}, sent, barrier, held, revision}

def received.parsed(state: State, +cl: Cl.Client, +line: String, parsed: Maybe<&2, Irc.Message>) -> State:
  match parsed:
    case None{}: state
    case Some{+m}: received.welcome(U32.is_eq(Irc.msg_num(m), 1) && Auth.server_control(cl, Irc.source_prefix(line), m), state, cl, m)

def received(state: State, +cl: Cl.Client, +line: String) -> State:
  received.parsed(state, cl, line, Irc.parse(line))

# Negotiated KICK victim (I2-dynamic2 F1): the self-KICK refusal that cancels
# desired membership compares the victim under the Session CASEMAPPING.
# Welcome detection keeps the fixed auth control (never forked).
def received.command_with(+cm: String, +state: State, +cl: Cl.Client, +m: Irc.Message, cmd: Irc.Cmd) -> State:
  match cmd:
    case Irc.Kick{}: received.kick(Cl.buf_eq_cm(cm, Irc.proto_atom(Irc.msg_param(m, 1n)), Cl.nick_of(cl)), state, Irc.proto_atom(Irc.msg_param(m, 0n)))
    case _: state

def received.welcome_with(+cm: String, welcome: Bool, state: State, cl: Cl.Client, +m: Irc.Message) -> State:
  match welcome:
    case False{}: received.command_with(cm, state, cl, m, Irc.classify(m))
    case True{}:
      match state:
        case State{desired, _, sent, barrier, held, revision}: State{desired, True{}, sent, barrier, held, revision}

def received.parsed_with(+cm: String, state: State, +cl: Cl.Client, +line: String, parsed: Maybe<&2, Irc.Message>) -> State:
  match parsed:
    case None{}: state
    case Some{+m}: received.welcome_with(cm, U32.is_eq(Irc.msg_num(m), 1) && Auth.server_control(cl, Irc.source_prefix(line), m), state, cl, m)

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

def failed(phase: Cl.AuthPhase) -> Bool:
  match phase:
    case Cl.AuthDone{}: True{}
    case _: False{}

def hold.report(report: Report, failed: Bool) -> Report & Notice:
  match report failed:
    case FailedReported{} _: (FailedReported{}, Quiet{})
    case _ True{}: (FailedReported{}, Failed{})
    case Unreported{} False{}: (WaitingReported{}, Held{})
    case WaitingReported{} False{}: (WaitingReported{}, Quiet{})

def hold.done(pair: Report & Notice, desired: List<&2, Channel>, welcome: Bool, baseline: Nat, held: Bool, revision: Nat) -> Flush:
  match pair:
    case (report, notice): Flush{State{desired, welcome, False{}, NeedAuth{baseline, report}, held, revision}, Nil{}, notice}

def hold(state: State, cl: Cl.Client) -> Flush:
  match state:
    case State{+desired, welcome, sent, barrier, held, revision}:
      match barrier:
        case NoAuth{}: Flush{State{desired, welcome, sent, NoAuth{}, held, revision}, Nil{}, Quiet{}}
        case NeedAuth{baseline, report}: hold.done(hold.report(report, failed(Cl.get_auth(cl))), desired, welcome, baseline, held, revision)

# Recovery flush drops desired channels the negotiated 005 bounds refuse
# (narrowed CHANTYPES/CHANNELLEN); the rest emit exactly as before. With
# defaults (no burst yet) admission equals base validity, so every
# remembered channel is kept and flush behaves exactly as before.
def admitted.keep(keep: Bool, +name: String, +key: String, rest: List<&2, Channel>) -> List<&2, Channel>:
  match keep:
    case True{}: Channel{name, key} <> rest
    case False{}: rest

def admitted.go(+xs: List<&2, Channel>, +iso: Isupport.State) -> List<&2, Channel>:
  match xs:
    case Nil{}: Nil{}
    case Con{Channel{+name, +key}, +rest}: admitted.keep(Isupport.join_admit(iso, name, key), name, key, admitted.go(rest, iso))

def admitted(+xs: List<&2, Channel>, +iso: Isupport.State) -> List<&2, Channel>:
  admitted.go(xs, iso)

def flush_iso.ready(ready: Bool, state: State, cl: Cl.Client, +iso: Isupport.State) -> Flush:
  match ready:
    case False{}: hold(state, cl)
    case True{}:
      match state:
        case State{+desired, welcome, _, barrier, held, revision}:
          +kept = admitted(desired, iso)
          Flush{State{kept, welcome, True{}, barrier, held, revision}, lines(kept), Quiet{}}

def flush_iso(+state: State, +cl: Cl.Client, +iso: Isupport.State) -> Flush:
  match state:
    case State{_, welcome, sent, +barrier, held, revision}:
      match welcome sent held:
        case True{} False{} False{}: flush_iso.ready(ready(barrier, cl), state, cl, iso)
        case _ _ _: Flush{state, Nil{}, Quiet{}}

def flush(+state: State, +cl: Cl.Client) -> Flush:
  flush_iso(state, cl, Isupport.defaults())
