# MSS stale real-callback qualification over the actual socket/Actor path.
#
# Once the old exchange reaches payload-observed (Cl.AuthResult) the hold
# arms: every subsequent old-gen callback is captured FIFO to peer EOF with
# no delivery and no redial yet, so the 903 flight (whole or split across
# TCP segments) lands intact without any byte detector. Only then does the
# same-endpoint redial bump part+actor generation 0 -> 1. The held set MUST
# be dropped by the generation fence, not by phase mismatch: the current
# gen-1 exchange is driven to payload-observed/Awaiting903 (Cl.AuthResult)
# BEFORE the stale set is released, with same endpoint/recipient/service/903
# shape, so the stale origin generation is the sole difference. Physical
# proof is the real AuthBridge event pipe: zero bytes + still open after the
# stale release, exactly one BIRC_AUTH_OK frame + EOF after the fresh
# 903/001, plus JOIN.
#
# Honesty rules (reviewer-verified failure modes this fixture must NOT repeat):
# - generations + bytes come ONLY from the socket: the real Actor reader
#   stamps FromNet via A.post; the fixture never calls A.post and never
#   builds a Chunk (no string_to_octets anywhere in this file).
# - held rms are the ACTUAL routed structs (net_fwd -> main -> heldq FIFO);
#   no wildcard-discard + literal rebuild anywhere.
# - NO byte detector anywhere: the hold arms on the OLD exchange reaching
#   AuthResult (payload-observed), which strictly precedes any 903 byte on
#   the wire (the peer sends 903 only after reading our payload). No stale
#   prefix can escape into the live framer; split/whole arrivals are one case.
# - redial goes through production W.live_step_keys (/connect typing) +
#   WsNet.ws_emit; Up/Eof/chunks fold through production WsNet.ws_on_net;
#   bridge observation is production W.auth_edge + AuthBridge.observed
#   (the ws_net_painted pair) with production W.auth_noticed state.
# - no workspace/Auth state is hand-built past the initial single_client;
#   every transition is a production call on actually received input.
#
# Choreography is PEER-CLOSE-FIRST (driver: tests/net/mss_stale_socket.py;
# one loopback listener, two accepts = same endpoint; pipes via env fds):
#   conn1: reg -> CAP ACK -> AUTHENTICATE -> + -> payload (old AuthResult:
#   ARM HOLD, no delivery, no redial yet) -> 903 flight (held; whole, or
#   split ':s ' + '903...' with a wire latch between) -> peer FIN -> Eof{0}
#   completes the held set -> production same-endpoint redial -> conn2 reg
#   -> Up{1} -> fresh CAP ACK -> AUTHENTICATE -> + -> payload (fresh
#   AuthResult) -> RELEASE STALE FIFO (edge False, code 0 each) ->
#   post-dispatch ACK (PRIVMSG on conn2) -> pipe ZERO (still open) ->
#   fresh 903+001 -> SUCCESS+EOF -> JOIN -> Eof{1} -> ok.
# Order proof: the Dial strictly follows the old EOF, so teardown can never
# truncate capture; the split tail goes out only after our wire latch proves
# the prefix callback was collected, so coalescing cannot fake the split;
# the driver reads the post-dispatch PRIVMSG (emitted after the FIFO
# release in program order) before zero-checking the pipe, so a fence break
# would deterministically land bytes before the check. The fresh 903 goes
# out only after the zero-check. Markers in stdout give the post-hoc order
# trail (asserted ordered by the driver).
#
# Bend shape: defs are strictly bottom-up (callees before callers); each
# loop is one self-recursive def whose helpers recurse only through an
# explicit continuation (production net_fwd/deferred_loop idiom).
import Base
import ./expect.bend as E
import ../../src/bend/actor.bend as Act
import ../../src/bend/session.bend as Sess
import ../../src/bend/workspace.bend as W
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/wsnet.bend as WsNet
import ../../src/bend/auth_bridge.bend as AuthBridge
import ../../src/bend/clock.bend as Clock
import ../../src/bend/frame.bend as Fr
import ../../src/bend/app.bend as App

def peer_host() -> String:
  "127.0.0.1"

def user_nick() -> String:
  "probe"

def sasl_user() -> String:
  "account"

def join_chan() -> String:
  "#t"

def s0() -> Key.ServerId:
  Key.first()

def sid_n(+s: Key.ServerId) -> String:
  match s:
    case Key.ServerId{+n}: Nat.show(n)

def mk_client(+pa: U32, +secret: String) -> Cl.Client:
  +bare = Cl.client_set_auth(Cl.init(user_nick(), peer_host()), Cl.SaslOnly{}, peer_host(), pa, "", "", sasl_user(), secret)
  Cl.set_settings(bare, Cl.set_autoreconn(Cl.get_settings(bare), True{}))

def mk_ws(+pa: U32, +secret: String) -> W.Workspace:
  W.single_client(peer_host(), pa, False{}, mk_client(pa, secret), join_chan())

# Payload-observed/Awaiting903 predicate over production Auth state.
def phase_is_result(+ph: Cl.AuthPhase) -> Bool:
  match ph:
    case Cl.AuthResult{}: True{}
    case _: False{}

def cmd_show(+cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Dial{+h, +p, +g, +n}: "dial:" ++ h ++ ":" ++ U32.show(p) ++ "@" ++ U32.show(g) ++ "/" ++ n
    case Sess.Cont{+outs}: "cont:" ++ Nat.show(List.length(&2, String, outs))
    case Sess.Drop{}: "drop"
    case Sess.Hangup{}: "hangup"
    case Sess.Pump{+g}: "pump:" ++ U32.show(g)
    case Sess.Begin{+g}: "begin:" ++ U32.show(g)
    case Sess.OpenUrl{+u}: "open:" ++ u
    case Sess.Pong{_, _, _}: "pong"
    case Sess.Search{_, _, _, _, _, _, _, _, _}: "search"

def rc_show(+rc: Sid.RoutedCmd) -> String:
  match rc:
    case Sid.RoutedCmd{+s, +cmd}: sid_n(s) ++ ">" ++ cmd_show(cmd)

# ---- phase + byte inspectors (verification only; never delivered) ----

def phase_of.sess(+st: Sess.Session) -> Cl.AuthPhase:
  Cl.get_auth(Sess.session_cl(st))

def phase_of.got(got: Maybe<&2, W.Part>) -> Cl.AuthPhase:
  match got:
    case None{}: Cl.AuthIdle{}
    case Some{+p}: phase_of.sess(W.part_session(p))

def phase_of(+ws: W.Workspace) -> Cl.AuthPhase:
  phase_of.got(W.find_part(ws, s0()))

def cmd_is_dial.cmd(+cmd: Sess.NetCmd) -> Bool:
  match cmd:
    case Sess.Dial{_, _, _, _}: True{}
    case _: False{}

def cmd_is_dial(+rc: Sid.RoutedCmd) -> Bool:
  match rc:
    case Sid.RoutedCmd{_, +cmd}: cmd_is_dial.cmd(cmd)

# Production release: ws_on_net (Clock/framer/live_on_msg/send) followed by
# the ws_net_painted bridge pair (auth_edge + observed) and auth_noticed
# state. The continuation receives (ws, edge, code); phases assert on it.
def rel.edge(+ws2: W.Workspace, +before: W.Workspace, k: W.Workspace -> Bool -> U32 -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    +edge : Bool <- IO.pure(Bool, W.auth_edge(before, ws2))
    +code : U32 <- AuthBridge.observed(edge)
    k(W.auth_noticed(ws2, Key.first(), code))(edge)(code)

def rel.cont(pair: W.Workspace & U32, +before: W.Workspace, k: W.Workspace -> Bool -> U32 -> IO(Unit)) -> IO(Unit):
  match pair:
    case (+ws2, _): rel.edge(ws2, before, k)

def rel(+rm: Sid.RoutedMsg, +ws: W.Workspace, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, k: W.Workspace -> Bool -> U32 -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    +now : U32 <- Clock.millis()
    +ts : String <- Clock.hhmmss()
    WsNet.ws_on_net(ws, rm, now, ts, main, cmds, evts, pair => rel.cont(pair, ws, k))

# ---- finish: Eof{1} ends the run ----

def finish_edge(+edge: Bool, +code: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("eof1 no edge", Bool.not(edge))
    Unit <- E.must_eq("eof1 code zero", U32.show(code), "0")
    Unit <- IO.print("MARK EOF1")
    Unit <- IO.print("mss_stale_socket=ok")
    IO.die(Unit, 0, "")

def finish_got(+ws2: W.Workspace, +edge: Bool, +code: U32) -> IO(Unit):
  finish_edge(edge, code)

# ---- fresh phase: the live 903 must succeed exactly once ----

def fresh_upped(+ws2: W.Workspace, +edge: Bool, +code: U32, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  again(ws2)(fresh_bytes)

def fresh_done(+edge: Bool, +code: U32, +ws2: W.Workspace, +fresh2: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("fresh edge true", edge)
    Unit <- E.must_eq("fresh code zero", U32.show(code), "0")
    Unit <- E.must("fresh bytes exact", Fr.octets_eq(held_bytes, fresh2))
    Unit <- E.must("fresh bytes nonempty", Nat.is_lt(0n, List.length(&2, U32, fresh2)))
    Unit <- IO.print("MARK FRESH903")
    Unit <- IO.print("MARK BYTEEXACT " ++ Nat.show(List.length(&2, U32, fresh2)))
    again(ws2)(fresh2)

def fresh_res(+after: Cl.AuthPhase, +edge: Bool, +code: U32, +ws2: W.Workspace, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match after:
    case Cl.AuthDone{}: fresh_done(edge, code, ws2, List.append(&2, U32, fresh_bytes, xs), main, cmds, evts, pa, held_bytes, again)
    case Cl.AuthResult{}:
      do IO<Unit>:
        Unit <- E.must("no edge mid-fresh", Bool.not(edge))
        again(ws2)(List.append(&2, U32, fresh_bytes, xs))
    case _: IO.die(Unit, 1, "fresh phase regressed")

def fresh_post.ph(+before: Cl.AuthPhase, +after: Cl.AuthPhase, +edge: Bool, +code: U32, +ws2: W.Workspace, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match before:
    case Cl.AuthResult{}: fresh_res(after, edge, code, ws2, xs, main, cmds, evts, pa, held_bytes, fresh_bytes, again)
    case Cl.AuthDone{}:
      do IO<Unit>:
        Unit <- E.must("no edge post-903", Bool.not(edge))
        Unit <- IO.print("MARK POST001")
        again(ws2)(fresh_bytes)
    case _: IO.die(Unit, 1, "fresh phase unexpected")

def fresh_post(+ws2: W.Workspace, +edge: Bool, +code: U32, +before: Cl.AuthPhase, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  fresh_post.ph(before, phase_of(ws2), edge, code, ws2, xs, main, cmds, evts, pa, held_bytes, fresh_bytes, again)

def fresh_chunk(+rm: Sid.RoutedMsg, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  rel(rm, ws, main, cmds, evts, ws2 => edge => code => fresh_post(ws2, edge, code, phase_of(ws), xs, main, cmds, evts, pa, held_bytes, fresh_bytes, again))

def fresh_new(+e: Sess.NetEvt, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match e:
    case Sess.Chunk{+xs, _}: fresh_chunk(rm, xs, main, cmds, evts, ws, pa, held_bytes, fresh_bytes, again)
    case Sess.Up{}: rel(rm, ws, main, cmds, evts, ws2 => edge => code => fresh_upped(ws2, edge, code, main, cmds, evts, pa, held_bytes, fresh_bytes, again))
    case Sess.Eof{}: rel(rm, ws, main, cmds, evts, ws2 => edge => code => finish_got(ws2, edge, code))
    case _: IO.die(Unit, 1, "fresh gen1 failure")

def fresh_gen(+is1: Bool, +e: Sess.NetEvt, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match is1:
    case True{}: fresh_new(e, rm, main, cmds, evts, ws, pa, held_bytes, fresh_bytes, again)
    case False{}: IO.die(Unit, 1, "stale leak post-release")

def fresh_from(+got: U32, +e: Sess.NetEvt, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  fresh_gen(U32.is_eq(got, 1), e, rm, main, cmds, evts, ws, pa, held_bytes, fresh_bytes, again)

def fresh_m(+m: Sess.UiMsg, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case Sess.FromNet{+got, +e}: fresh_from(got, e, rm, main, cmds, evts, ws, pa, held_bytes, fresh_bytes, again)
    case _: IO.die(Unit, 1, "non-net uimsg in fresh")

def fresh_rm(+rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match rm:
    case Sid.RoutedMsg{_, +m}: fresh_m(m, rm, main, cmds, evts, ws, pa, held_bytes, fresh_bytes, again)

def fresh_msg(+m: WsNet.WsMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case WsNet.WsNet{+rm}: fresh_rm(rm, main, cmds, evts, ws, pa, held_bytes, fresh_bytes, again)
    case _: again(ws)(fresh_bytes)

def fresh_got(g: Maybe<&1, WsNet.WsMsg>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: IO.die(Unit, 1, "main closed in fresh")
    case Some{+m}: fresh_msg(m, main, cmds, evts, ws, pa, held_bytes, fresh_bytes, again)

def fresh(+fuel: Nat, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "fresh limit")
    case 1n+p:
      do IO<Unit>:
        g : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
        fresh_got(g, main, cmds, evts, ws, pa, held_bytes, fresh_bytes, ws2 => fb2 => fresh(p, main, cmds, evts, ws2, pa, held_bytes, fb2))

# Post-dispatch ACK: a production /msg whose wire PRIVMSG proves the FIFO
# release completed before the driver zero-checks the event pipe.
def dispatch_emit(+rc: Sid.RoutedCmd, +ws2: W.Workspace, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("dispatch ack is not dial", Bool.not(cmd_is_dial(rc)))
    Unit <- WsNet.ws_emit(rc, cmds, evts)
    Unit <- IO.print("MARK DISPATCHED")
    fresh(64n, main, cmds, evts, ws2, pa, held_bytes, fresh_bytes)

def dispatch_got(trip: W.Workspace & Sid.RoutedCmd & Bool, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>) -> IO(Unit):
  match trip:
    case (+ws2, +rc, _): dispatch_emit(rc, ws2, main, cmds, evts, pa, held_bytes, fresh_bytes)

def dispatch_ack(+ws: W.Workspace, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>) -> IO(Unit):
  dispatch_got(W.live_step_keys(ws, Sess.keys_enter("/msg ackprobe STALERELEASED")), main, cmds, evts, pa, held_bytes, fresh_bytes)

# ---- stale release: every held struct through production, FIFO ----

def release_checked(+edge: Bool, +code: U32, +ws2: W.Workspace, +rest: List<&2, Sid.RoutedMsg>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, more: W.Workspace -> List<&2, Sid.RoutedMsg> -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("stale edge false", Bool.not(edge))
    Unit <- E.must_eq("stale code zero", U32.show(code), "0")
    Unit <- IO.print("MARK STALERELEASE edge:False code:0")
    more(ws2)(rest)

def release_staled(+ws2: W.Workspace, +edge: Bool, +code: U32, +rest: List<&2, Sid.RoutedMsg>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, more: W.Workspace -> List<&2, Sid.RoutedMsg> -> IO(Unit)) -> IO(Unit):
  release_checked(edge, code, ws2, rest, main, cmds, evts, pa, held_bytes, fresh_bytes, more)

def release_next(+main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +rest: List<&2, Sid.RoutedMsg>, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, more: W.Workspace -> List<&2, Sid.RoutedMsg> -> IO(Unit)) -> IO(Unit):
  match rest:
    case Nil{}:
      do IO<Unit>:
        Unit <- IO.print("MARK STALERELEASED")
        dispatch_ack(ws, main, cmds, evts, pa, held_bytes, fresh_bytes)
    case Con{+rm, +more_rest}:
      rel(rm, ws, main, cmds, evts, ws2 => edge => code => release_staled(ws2, edge, code, more_rest, main, cmds, evts, pa, held_bytes, fresh_bytes, more))

def release_go(+fuel: Nat, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +rest: List<&2, Sid.RoutedMsg>, +pa: U32, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "release limit")
    case 1n+p: release_next(main, cmds, evts, ws, rest, pa, held_bytes, fresh_bytes, wsn => rst => release_go(p, main, cmds, evts, wsn, rst, pa, held_bytes, fresh_bytes))

def release_begin.go(+fifo: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32) -> IO(Unit):
  match fifo:
    case Nil{}: IO.die(Unit, 1, "empty held set")
    case Con{_, _}: release_go(64n, main, cmds, evts, ws, fifo, pa, held_bytes, fresh_bytes)

def release_begin(+held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32) -> IO(Unit):
  release_begin.go(List.reverse(&2, Sid.RoutedMsg, held_rev), held_bytes, fresh_bytes, main, cmds, evts, ws, pa)

# ---- hold phase: gen-1 releases live (held set already complete) ----
# The old EOF arrived before the redial by construction (collect phase),
# so the release gate is the fresh phase alone; no eof0 flag is threaded.

def hold_check.r(+is_result: Bool, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match is_result:
    case True{}: release_begin(held_rev, held_bytes, fresh_bytes, main, cmds, evts, ws, pa)
    case False{}: again(ws)(fresh_bytes)

def hold_check(+main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  hold_check.r(phase_is_result(phase_of(ws)), main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_new.other(+edge: Bool, +ws2: W.Workspace, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("no early edge", Bool.not(edge))
    hold_check(main, cmds, evts, ws2, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_new.plus(+after: Cl.AuthPhase, +edge: Bool, +ws2: W.Workspace, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match after:
    case Cl.AuthResult{}:
      do IO<Unit>:
        Unit <- E.must("no edge at authplus", Bool.not(edge))
        Unit <- IO.print("MARK AUTHPLUS")
        hold_check(main, cmds, evts, ws2, pa, held_rev, held_bytes, fresh_bytes, again)
    case _: hold_new.other(edge, ws2, main, cmds, evts, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_new.res(+after: Cl.AuthPhase, +edge: Bool, +ws2: W.Workspace, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match after:
    case Cl.AuthResult{}:
      do IO<Unit>:
        Unit <- E.must("no edge mid-result", Bool.not(edge))
        hold_check(main, cmds, evts, ws2, pa, held_rev, held_bytes, List.append(&2, U32, fresh_bytes, xs), again)
    case _: IO.die(Unit, 1, "fresh 903 arrived before stale release")

def hold_new.post.ph(+before: Cl.AuthPhase, +after: Cl.AuthPhase, +edge: Bool, +ws2: W.Workspace, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match before:
    case Cl.AuthChallenge{}: hold_new.plus(after, edge, ws2, main, cmds, evts, pa, held_rev, held_bytes, fresh_bytes, again)
    case Cl.AuthResult{}: hold_new.res(after, edge, ws2, xs, main, cmds, evts, pa, held_rev, held_bytes, fresh_bytes, again)
    case _: hold_new.other(edge, ws2, main, cmds, evts, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_new.post(+ws2: W.Workspace, +edge: Bool, +code: U32, +before: Cl.AuthPhase, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  hold_new.post.ph(before, phase_of(ws2), edge, ws2, xs, main, cmds, evts, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_new.upped(+ws2: W.Workspace, +edge: Bool, +code: U32, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  hold_new.other(edge, ws2, main, cmds, evts, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_new.chunk(+rm: Sid.RoutedMsg, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  rel(rm, ws, main, cmds, evts, ws2 => edge => code => hold_new.post(ws2, edge, code, phase_of(ws), xs, main, cmds, evts, pa, held_rev, held_bytes, fresh_bytes, again))

def hold_new.up(+rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  rel(rm, ws, main, cmds, evts, ws2 => edge => code => hold_new.upped(ws2, edge, code, main, cmds, evts, pa, held_rev, held_bytes, fresh_bytes, again))

def hold_new(+e: Sess.NetEvt, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match e:
    case Sess.Chunk{+xs, _}: hold_new.chunk(rm, xs, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)
    case Sess.Up{}: hold_new.up(rm, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)
    case Sess.Eof{}: IO.die(Unit, 1, "early eof1 in hold")
    case Sess.InitialFail{_}: IO.die(Unit, 1, "dial1 failed in hold")
    case Sess.NetFail{_}: IO.die(Unit, 1, "netfail1 in hold")
    case Sess.WriterDone{}: IO.die(Unit, 1, "writer done in hold")
    case _: IO.die(Unit, 1, "unknown gen1 evt in hold")

def hold_gen1(+is1: Bool, +e: Sess.NetEvt, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match is1:
    case True{}: hold_new(e, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)
    case False{}: IO.die(Unit, 1, "bad gen in hold")

def hold_gen0(+is0: Bool, +got: U32, +e: Sess.NetEvt, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match is0:
    case True{}: IO.die(Unit, 1, "stale arrival after redial")
    case False{}: hold_gen1(U32.is_eq(got, 1), e, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_from(+got: U32, +e: Sess.NetEvt, +s: Key.ServerId, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("hold server", sid_n(s), "0")
    hold_gen0(U32.is_eq(got, 0), got, e, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_m(+m: Sess.UiMsg, +s: Key.ServerId, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case Sess.FromNet{+got, +e}: hold_from(got, e, s, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)
    case _: IO.die(Unit, 1, "non-net uimsg in hold")

def hold_rm(+rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match rm:
    case Sid.RoutedMsg{+s, +m}: hold_m(m, s, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)

def hold_msg(+m: WsNet.WsMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case WsNet.WsNet{+rm}: hold_rm(rm, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)
    case _: again(ws)(fresh_bytes)

def hold_got(g: Maybe<&1, WsNet.WsMsg>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>, again: W.Workspace -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: IO.die(Unit, 1, "main closed in hold")
    case Some{+m}: hold_msg(m, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, again)

def hold(+fuel: Nat, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +fresh_bytes: List<&2, U32>) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "hold limit")
    case 1n+p:
      do IO<Unit>:
        g : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
        hold_got(g, main, cmds, evts, ws, pa, held_rev, held_bytes, fresh_bytes, ws2 => fb2 => hold(p, main, cmds, evts, ws2, pa, held_rev, held_bytes, fb2))

# ---- redial through production /connect typing ----

def redial_emit(+rc: Sid.RoutedCmd, +ws2: W.Workspace, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("redial is dial", cmd_is_dial(rc))
    Unit <- IO.print("MARK REDIAL " ++ rc_show(rc))
    Unit <- WsNet.ws_emit(rc, cmds, evts)
    hold(64n, main, cmds, evts, ws2, pa, held_rev, held_bytes, Nil{})

def redial_got(trip: W.Workspace & Sid.RoutedCmd & Bool, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>) -> IO(Unit):
  match trip:
    case (+ws2, +rc, _): redial_emit(rc, ws2, main, cmds, evts, pa, held_rev, held_bytes)

def redial_now(+ws: W.Workspace, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>) -> IO(Unit):
  redial_got(W.live_step_keys(ws, Sess.keys_enter("/connect " ++ peer_host() ++ ":" ++ U32.show(pa))), main, cmds, evts, pa, held_rev, held_bytes)

# ---- collect phase: old callbacks to EOF, no delivery, no redial yet ----
# Every held chunk prints its received length (boundary trail). In split
# mode the driver sends only ':s ' first and waits for the wire latch we
# emit after collecting the first chunk, so the tail provably lands in a
# later received callback: coalescing is impossible by construction.

def collect_term(+rm: Sid.RoutedMsg, +tag: String, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print(tag)
    Unit <- IO.print("MARK HELDBYTES " ++ Nat.show(List.length(&2, U32, held_bytes)))
    redial_now(ws, main, cmds, evts, pa, Con{rm, held_rev}, held_bytes)

def collect_latch_emit(+rc: Sid.RoutedCmd, +ws2: W.Workspace, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("latch is not dial", Bool.not(cmd_is_dial(rc)))
    Unit <- WsNet.ws_emit(rc, cmds, evts)
    Unit <- IO.print("MARK LATCHED")
    again(ws2)(held_rev)(held_bytes)

def collect_latched(trip: W.Workspace & Sid.RoutedCmd & Bool, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match trip:
    case (+ws2, +rc, _): collect_latch_emit(rc, ws2, main, cmds, evts, pa, held_rev, held_bytes, again)

def collect_split(+split: Bool, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match split:
    case True{}: collect_latched(W.live_step_keys(ws, Sess.keys_enter("/msg ackprobe SPLITLATCH")), main, cmds, evts, pa, held_rev, held_bytes, again)
    case False{}: again(ws)(held_rev)(held_bytes)

def collect_first(+first: Bool, +split: Bool, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match first:
    case True{}: collect_split(split, main, cmds, evts, ws, pa, held_rev, held_bytes, again)
    case False{}: again(ws)(held_rev)(held_bytes)

def collect_chunk(+rm: Sid.RoutedMsg, +xs: List<&2, U32>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print("MARK HELDCHUNK " ++ Nat.show(List.length(&2, U32, xs)))
    collect_first(List.is_empty(&2, Sid.RoutedMsg, held_rev), split, main, cmds, evts, ws, pa, Con{rm, held_rev}, List.append(&2, U32, held_bytes, xs), again)

def collect_old(+e: Sess.NetEvt, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match e:
    case Sess.Chunk{+xs, _}: collect_chunk(rm, xs, main, cmds, evts, ws, pa, held_rev, held_bytes, split, again)
    case Sess.Eof{}: collect_term(rm, "MARK EOF0", main, cmds, evts, ws, pa, held_rev, held_bytes)
    case Sess.NetFail{_}: collect_term(rm, "MARK FAIL0", main, cmds, evts, ws, pa, held_rev, held_bytes)
    case Sess.Up{}: IO.die(Unit, 1, "dup up0 in collect")
    case Sess.InitialFail{_}: IO.die(Unit, 1, "dial0 failed in collect")
    case Sess.WriterDone{}: IO.die(Unit, 1, "writer done in collect")
    case _: IO.die(Unit, 1, "unknown gen0 evt in collect")

def collect_gen0(+is0: Bool, +e: Sess.NetEvt, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match is0:
    case True{}: collect_old(e, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, split, again)
    case False{}: IO.die(Unit, 1, "gen1 before redial")

def collect_from(+got: U32, +e: Sess.NetEvt, +s: Key.ServerId, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("collect server", sid_n(s), "0")
    collect_gen0(U32.is_eq(got, 0), e, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, split, again)

def collect_m(+m: Sess.UiMsg, +s: Key.ServerId, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case Sess.FromNet{+got, +e}: collect_from(got, e, s, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, split, again)
    case _: IO.die(Unit, 1, "non-net uimsg in collect")

def collect_rm(+rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match rm:
    case Sid.RoutedMsg{+s, +m}: collect_m(m, s, rm, main, cmds, evts, ws, pa, held_rev, held_bytes, split, again)

def collect_msg(+m: WsNet.WsMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case WsNet.WsNet{+rm}: collect_rm(rm, main, cmds, evts, ws, pa, held_rev, held_bytes, split, again)
    case _: again(ws)(held_rev)(held_bytes)

def collect_got(g: Maybe<&1, WsNet.WsMsg>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool, again: W.Workspace -> List<&2, Sid.RoutedMsg> -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: IO.die(Unit, 1, "main closed in collect")
    case Some{+m}: collect_msg(m, main, cmds, evts, ws, pa, held_rev, held_bytes, split, again)

def collect(+fuel: Nat, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +held_rev: List<&2, Sid.RoutedMsg>, +held_bytes: List<&2, U32>, +split: Bool) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "collect limit")
    case 1n+p:
      do IO<Unit>:
        g : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
        collect_got(g, main, cmds, evts, ws, pa, held_rev, held_bytes, split, ws2 => rv2 => by2 => collect(p, main, cmds, evts, ws2, pa, rv2, by2, split))

def hold_begin(+main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print("MARK HELD armed")
    collect(64n, main, cmds, evts, ws, pa, Nil{}, Nil{}, split)

# LIVE phase (gen 0, pre-arm): release Up + SASL flights live so the
# lock-step peer advances. The hold arms when the OLD exchange reaches
# AuthResult (payload-observed): from that release on, every gen-0 callback
# is held to peer EOF. No byte scan, no shadow: the arm point strictly
# precedes any 903 byte, so no stale prefix can escape. Gen 0 only here.
# Split gates the collect-phase prefix latch; the fence path is identical.

def live_upped(+ws2: W.Workspace, +edge: Bool, +code: U32, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  again(ws2)

def live_gate(+is_result: Bool, +ws2: W.Workspace, +edge: Bool, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  match is_result:
    case True{}:
      do IO<Unit>:
        Unit <- E.must("no edge at old authplus", Bool.not(edge))
        hold_begin(main, cmds, evts, ws2, pa, split)
    case False{}: again(ws2)

def live_reld(+ws2: W.Workspace, +edge: Bool, +code: U32, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  live_gate(phase_is_result(phase_of(ws2)), ws2, edge, main, cmds, evts, pa, split, again)

def live_up(+got: U32, +s: Key.ServerId, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("live up gen0", U32.is_eq(got, 0))
    Unit <- E.must_eq("live up server", sid_n(s), "0")
    rel(rm, ws, main, cmds, evts, ws2 => edge => code => live_upped(ws2, edge, code, main, cmds, evts, pa, split, again))

def live_chunk(+xs: List<&2, U32>, +got: U32, +s: Key.ServerId, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("live chunk gen0", U32.is_eq(got, 0))
    Unit <- E.must_eq("live chunk server", sid_n(s), "0")
    Unit <- E.must("live chunk nonempty", Nat.is_lt(0n, List.length(&2, U32, xs)))
    rel(rm, ws, main, cmds, evts, ws2 => edge => code => live_reld(ws2, edge, code, main, cmds, evts, pa, split, again))

def live_evt(+e: Sess.NetEvt, +got: U32, +s: Key.ServerId, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  match e:
    case Sess.Chunk{+xs, _}: live_chunk(xs, got, s, rm, main, cmds, evts, ws, pa, split, again)
    case Sess.Up{}: live_up(got, s, rm, main, cmds, evts, ws, pa, split, again)
    case _: IO.die(Unit, 1, "unexpected netevt in live")

def live_from(+m: Sess.UiMsg, +s: Key.ServerId, +rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  match m:
    case Sess.FromNet{+got, +e}: live_evt(e, got, s, rm, main, cmds, evts, ws, pa, split, again)
    case _: IO.die(Unit, 1, "non-net uimsg in live")

def live_rm(+rm: Sid.RoutedMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  match rm:
    case Sid.RoutedMsg{+s, +m}: live_from(m, s, rm, main, cmds, evts, ws, pa, split, again)

def live_msg(+m: WsNet.WsMsg, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  match m:
    case WsNet.WsNet{+rm}: live_rm(rm, main, cmds, evts, ws, pa, split, again)
    case _: again(ws)

def live_got(g: Maybe<&1, WsNet.WsMsg>, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool, again: W.Workspace -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: IO.die(Unit, 1, "main closed in live")
    case Some{+m}: live_msg(m, main, cmds, evts, ws, pa, split, again)

def live(+fuel: Nat, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +ws: W.Workspace, +pa: U32, +split: Bool) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "live limit")
    case 1n+p:
      do IO<Unit>:
        g : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
        live_got(g, main, cmds, evts, ws, pa, split, ws2 => live(p, main, cmds, evts, ws2, pa, split))

# ---- entry: secret pipe, real actor, live loop ----

def boot(+pa: U32, +secret: String, +mode: String) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 16)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 8)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 2)
    +main : Chan(WsNet.WsMsg) <- Chan.new(WsNet.WsMsg, 16)
    +d1 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +d2 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +d3 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +cmds : WsNet.WsCmds <- IO.pure(WsNet.WsCmds, WsNet.WsCmds{cmd, d1, d2, d3})
    # Single-Sid0 fixture: all four event slots share the real evt
    # channel already observed by net_fwd and actor_boot; the unused
    # slots are unqualified.
    +evts : WsNet.WsEvts <- IO.pure(WsNet.WsEvts, WsNet.WsEvts{evt, evt, evt, evt})
    +ws : W.Workspace <- IO.pure(W.Workspace, mk_ws(pa, secret))
    Unit <- IO.spawn(Unit, WsNet.net_fwd(s0(), evt, main))
    Unit <- IO.spawn(Unit, WsNet.boot_fwd(s0(), 0, boot, main))
    Unit <- IO.spawn(Unit, WsNet.boot_fwd(s0(), 1, boot, main))
    Unit <- IO.spawn(Unit, Act.actor_boot(peer_host(), pa, user_nick(), 0, evt, cmd, boot, True{}, 0))
    Unit <- IO.print("MARK START " ++ mode)
    live(64n, main, cmds, evts, ws, pa, String.eq(mode, "split"))

def setup_secret(+empty: Bool, +pa: U32, +secret: String, +mode: String) -> IO(Unit):
  match empty:
    case True{}: IO.die(Unit, 1, "empty auth secret")
    case False{}: boot(pa, secret, mode)

def setup_code(+ok: Bool, +secret: String, +pa: U32, +mode: String) -> IO(Unit):
  match ok:
    case True{}: setup_secret(String.is_empty(secret), pa, secret, mode)
    case False{}: IO.die(Unit, 1, "auth setup failed")

def setup_got(pair: U32 & String, +pa: U32, +mode: String) -> IO(Unit):
  match pair:
    case (+code, secret): setup_code(U32.is_eq(code, 0), secret, pa, mode)

def run(+pa: U32, +mode: String) -> IO(Unit):
  do IO<Unit>:
    pair : U32 & String <- AuthBridge.setup()
    setup_got(pair, pa, mode)

def parsed(a: Maybe<&2, U32>, +mode: String) -> IO(Unit):
  match a:
    case Some{+pa}: run(pa, mode)
    case _: IO.die(Unit, 1, "invalid port")

def dispatch(p: String, +mode: String, app: Bool) -> IO(Unit):
  match app:
    # Preserve all production FFI IDs; the local guard does not run this arm.
    case True{}: App.main()
    case False{}: parsed(U32.read(p), mode)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+port, Con{+mode, Nil{}}}}: dispatch(port, mode, String.eq(mode, "app"))
    case _: IO.die(Unit, 1, "expected port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
