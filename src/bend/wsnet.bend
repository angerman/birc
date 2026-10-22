# SPDX-License-Identifier: Apache-2.0
# Multiserver live loop over Workspace. One actor per server posts to its
# own event channel; per-server forwarders retag traffic as Sid.RoutedMsg
# into one main channel. The loop paints the current part, steps keys
# through W.live_step_keys (focus-gated drafts + the Session-owned
# multiline seam), dispatches actor traffic through W.live_on_msg, fires
# reconnect watches through W.on_redial, and cycles servers on F7. The
# workspace owns every generation: Dial/Pump/Begin already carry it, so the
# loop adopts without re-bumping and stale traffic drops at each fence.
# A one-second tick expires typing on every part (repainting only on
# change), and routed inbound feeds the launcher auth bridge on the
# primary part's success edge. Full-baseline IO like the single-server
# loop: per-part settings prepare plus history import, a shared sole
# preferences lease (observe/start/drain over one dedicated channel),
# per-part history save with endpoint-change reload, current-part
# media/upload worker stages with routed completions, and helper-failure
# notify routed as UiError to the owning part.
# Baseline gates (all enforced here, never fixture-only):
# G1 every worker completion validates its origin (live part plus slot
# generation) BEFORE any live Session/worker IO effect. Absent or re-added
# origins have no fallback effects; exact physical completions still retire
# their worker ownership without admitting stale results.
# G2 one GLOBAL physical image lease across focus: the media stage takes
# a job only while the lease is free, so a blocked owner pins every
# other part until its exact completion releases the lease once. The lease
# carries its spawn-captured media envelope and is never pruned: absent
# parts and slot-generation changes keep it until the exact worker done.
# Native admission always carries the all-part retained-token union.
# G3 the preferences worker has a sole routed receiver: one dedicated
# channel, one owning part, ticket-fenced completions, and a bounded
# main-channel drain at shutdown (deadline plus elapsed cap) that also
# collects writer acknowledgements.
# G4 startup order is first input-bearing frame, then settings/archive,
# then exactly one deferred Begin. The first view uses the measured
# terminal size, not SIZE0. That frame still applies its keys before any
# load or boot (a first-frame quit halts before all of it). Each part
# then loads on its own fiber, so preference and archive reads overlap,
# while later frames keep that size and follow resize. A keyless wake is
# not replayed onto the import.
# The tty watcher is acked during the wait, so later keys still arrive.
# One settings prepare still resolves before each part history import,
# with the postimport client as the save checkpoint.
# Deferred actors boot at live generations only after that load and stay
# silent until the post-input Begin releases them once per part.
# BIRC_PREFERENCES=none keeps the direct path.
# Cards and notifications ride the actual union policy: per-part cards
# sidecars schedule over exact negotiated paint rows with ONE global worker
# across all parts (WsCardsAll lease, exact captured C.Request origin like
# the G2 image lease), admit exact completions (C/CNet), and paint ready
# inline rows plus the revalidated fullscreen overlay over the same row set.
# Desktop notifications seed per-scope
# high-water marks from history and fire once per live alert in loop
# order through the bounded helper (N/NIO). Helper-failure diagnostics
# route as UiError rows to the owning part, never as content.
import Base
import ./buffer.bend as Cl
import ./session.bend as Sess
import ./server_key.bend as Key
import ./server_id.bend as Sid
import ./workspace.bend as W
import ./actor.bend as Act
import ./net.bend as Net
import ./timui.bend as T
import ./auth_bridge.bend as AuthBridge
import ./clock.bend as Clock
import ./args.bend as Args
import ./submit.bend as Sub
import ./transport_policy.bend as Policy
import ./endpoint.bend as Ep
import ./history.bend as Hist
import ./history_io.bend as HistIO
import ./history_search.bend as Hs
import ./history_search_io.bend as HSIO
import ./media.bend as M
import ./upload.bend as Up
import ./upload_io.bend as UploadIO
import ./cards.bend as C
import ./cards_net.bend as CNet
import ./notify.bend as N
import ./notify_io.bend as NIO
import ./split.bend as Sp
import ./view.bend as V
import ./isupport.bend as Isupport
import ./live_context.bend as PrefLive
import ./preferences_worker.bend as PrefWorker
import ./preferences_live.bend as LoadedPrefs
import ./startup_headless.bend as Headless
import ./history_startup_io.bend as Archive

# Startup load bundle. A Data box (not a tuple): the pinned checker
# cannot match tuple types carrying Maybe past the second element.
type WsLoaded is Data:
  WsLoaded{ws: W.Workspace, lp: Maybe<&2, LoadedPrefs.Context>, known: Bool}

# Keys read while settings and history load. `have` is false until a
# later frame carries a real key, edit, click, or paste. A keyless wake
# (the tty watcher's first ready) only updates rows and cols. The first
# frame's keys are already in the load snapshot.
type WsHold is Data:
  WsHold{have: Bool, typed: String, enter: Bool, rows: U32, cols: U32, click: U32, key: U32, mods: U32, codepoint: U32, wheel: U32, url: String, clipboard: String}

# Display workspace while the loader runs. `scheduled` is the one pending
# UiContinue, same bound as the live loop.
type WsWait is Data:
  WsWait{ws: W.Workspace, hold: WsHold, scheduled: Bool}

type WsMsg is Data:
  WsUi{msg: Sess.UiMsg}
  WsNet{rm: Sid.RoutedMsg}
  WsPrefs{m: Sess.UiMsg}
  WsRedial{intent: Sid.Intent}
  WsTick{now_ms: U32}
  # History-worker append failure: *log* diagnostic only, never UiError/chat Error.
  # `base` is the pre-save log_seq; `seq` is the client seq the job covered.
  # `retry` is the blob to prepend when a newer hold is still outstanding.
  WsHistDiag{msg: String, sid: Nat, base: Nat, seq: Nat, retry: String}
  # Durable append of a marked job. seq 0 is an overflow/flush blob with no floor.
  WsHistAck{sid: Nat, seq: Nat}
  # History worker drained HistStop (or closed admission); shutdown may finish.
  WsHistDone{}
  # Startup settings/archive finished. The wait loop installs it, then boots.
  # The live loop only sees this if it arrives late; it does not load again.
  # `path` is the history file the worker already resolved.
  WsReady{loaded: WsLoaded, path: String}

type WsCmds is Data:
  WsCmds{c0: Chan(Sess.NetCmd), c1: Chan(Sess.NetCmd), c2: Chan(Sess.NetCmd), c3: Chan(Sess.NetCmd)}

# Per-server event channels. Actors post FromNet here; media/upload
# workers spawned for a part post completions here too, so net_fwd routes
# every completion to its owning server slot.
type WsEvts is Data:
  WsEvts{c0: Chan(Sess.UiMsg), c1: Chan(Sess.UiMsg), c2: Chan(Sess.UiMsg), c3: Chan(Sess.UiMsg)}

# G1/G2/G3: a worker origin binding. The generation fences live effects;
# the preferences binding itself follows its physical job until completion.
# Sid is Data here so leases compare without IO.
type WsLease is Data:
  WsLease{s: Key.ServerId, gen: U32}

# M2/G2: the one global image lease with its spawn-captured envelope.
# Sid/slot-gen alone cannot retire: after prune+reuse a fresh request
# may carry the same media generation/ticket/url as the dead worker, so
# the exact media Request is captured at spawn and a completion retires
# only on exact Sid plus generation/ticket/url match. Prune never frees;
# the lease persists across removed/stale/reused origins until the exact
# spawned worker completes. Live session effects additionally require a
# present same-slot-generation origin, never a current-part substitute.
type WsMedia is Data:
  WsMedia{s: Key.ServerId, gen: U32, req: M.Request}

# Per-part cards sidecar. The loop carries one entry per live part: the slot
# generation fences re-added slots, cards holds the bounded queue plus
# the part-local worker slot, and full the overlay state. Sidecar
# exactness comes from C.exact against the retained active request, but
# the PHYSICAL worker is global: one WsCardsLease across all parts, so a
# blocked owner pins every other part until its exact completion releases.
type WsCards is Data:
  WsCards{s: Key.ServerId, gen: U32, cards: C.State, full: C.Fullscreen}

# C2: the one global cards lease with its spawn-captured envelope. This
# reuses the accepted WsMedia/ws_mlease exact-physical-owner pattern:
# Sid/slot-gen alone cannot retire, because after prune+reuse a fresh
# request may carry the same generation/ticket/url as the dead worker. The
# exact C.Request is captured at spawn and a completion retires only on
# exact Sid plus generation/ticket/url match. Prune never frees; the lease
# persists across removed/stale/reused origins until the exact spawned
# worker completes. Live session effects additionally require a present
# same-slot-generation origin, never a current-part substitute.
type WsCardsLease is Data:
  WsCardsLease{s: Key.ServerId, gen: U32, req: C.Request}

# Loop-carried cards bundle: the per-part sidecars plus the one global
# physical lease. Only the current part stages, but the lease gates every
# part, so at most one cards helper runs across all parts.
# One ordered history writer. The UI chain enqueues the already-built
# record and keeps painting; the worker appends in order and posts a
# diagnostic only when the write fails.
type HistJob is Data:
  # sid/base/seq mark the part and the extract window. seq 0 does not move the floor.
  HistJob{path: String, data: String, sid: Nat, base: Nat, seq: Nat}
  HistStop{}
  # Ordered fence: the worker acks only after every job already queued.
  HistBarrier{ack: Chan(Unit)}

# One reload ticket per ServerId, plus the loop-wide monotonic counter.
# Slots are independent: a completion clears only its own part.
type WsTickets is Data:
  WsTickets{t0: Maybe<&2, Nat>, t1: Maybe<&2, Nat>, t2: Maybe<&2, Nat>, t3: Maybe<&2, Nat>, next: Nat}

# Overflow bytes keep the part that produced them. A later part must not
# relabel this blob with its own sid/base/seq.
type WsPend is Data:
  WsPend{bytes: String, sid: Nat, base: Nat, seq: Nat}

# Cached process facts and the last body paint. `on` is BIRC_CARDS, read
# once at startup. `warm` means `frame` is still the visible body.
# `reload` is the per-part archive tickets awaiting HistoryLoaded.
# `pending` holds same-path overflow bytes waiting for worker capacity (FIFO
# coalesce). Never UI-append while older HistJobs are still queued.
# `hold` is the newest queued log_seq. Extract skips ids at or below it
# until the worker acks or a failure clears it. 0 means no hold.
type WsHot is Data:
  WsHot{on: Bool, path: String, cap: U32, jobs: Maybe<&2, Chan(HistJob)>, warm: Bool, frame: List<&2, V.DrawOp>, ts: String, reload: WsTickets, pending: WsPend, hold: Nat}

type WsCardsAll is Data:
  WsCardsAll{parts: List<&2, WsCards>, lease: Maybe<&2, WsCardsLease>, hot: WsHot}

# Per-part notify sidecar: the slot generation fences re-added slots and the
# accepted N9 NotifyLive owns per-part logical state (marks, bounded queue,
# scan floor, durable archive claims). Each Sid stamps a disjoint 2^44 ID
# range, so each part needs its own floor; endpoint-only global marks would
# silence a same-endpoint sibling.
type WsNotifyPart is Data:
  WsNotifyPart{s: Key.ServerId, gen: U32, nl: Sess.NotifyLive}

# One global physical worker lease: the spawn-captured owner plus the ticket
# and origin endpoint the detached helper stamps on its completion. At most
# one helper child runs at a time across parts (single physical lease). The
# lease persists across part replacement until the exact completion releases
# it once, like the global image lease; gen is captured identity only, never
# a release gate.
type WsNotifyLease is Data:
  WsNotifyLease{s: Key.ServerId, gen: U32, ticket: Nat, endpoint: String}

# Global desktop-notification bundle: per-part logical NotifyLive entries
# plus ONE physical worker lease and the monotone ticket counter. Every
# handoff spawns on the handing part's own channel (captured in the lease),
# so a failed helper diagnoses to its owning part, never a sibling.
type WsNotify is Data:
  WsNotify{parts: List<&2, WsNotifyPart>, lease: Maybe<&2, WsNotifyLease>, next: Nat}

# Loop accumulator bundle (struct match keeps nesting shallow). The
# preferences lease context rides along; media holds the one global
# image lease with its spawn envelope, prefs the sole preferences
# owner, up the per-part upload spawn records, notify the global
# desktop-notification bundle (per-part NotifyLive entries + one worker
# lease), cards the cards bundle (per-part sidecars plus the one global
# cards lease with its spawn envelope). ws_start.live sends one Begin
# per part after load, then starts the loop already begun, so the frame
# path must not send another. The first paint and its keys still run
# before settings, archive load, and Begin (ws_start.keyed halts before
# boot). That order stays.
type WsLoop is Data:
  WsLoop{ws: W.Workspace, bell: U32, scheduled: Bool, ctx: PrefLive.Context, media: Maybe<&2, WsMedia>, prefs: Maybe<&2, WsLease>, up: List<&2, WsLease>, notify: WsNotify, cards: WsCardsAll, begun: Bool}

# Unified shutdown bundle: pending writer acknowledgements plus the
# bounded preferences drain over the main channel. `hist` is True while
# waiting for the history worker's WsHistDone under the same drain budget.
type WsShut is Data:
  WsShut{pending: List<&2, Key.ServerId>, ctx: PrefLive.Context, st: Sess.Session, id: Key.ServerId, owner: Maybe<&2, WsLease>, ok: Bool, started: U32, done: Bool, hist: Bool}

def rm_server(+rm: Sid.RoutedMsg) -> Key.ServerId:
  match rm:
    case Sid.RoutedMsg{+s, _}: s

def intent_server(+i: Sid.Intent) -> Key.ServerId:
  match i:
    case Sid.Intent{+s, _, _, _, _}: s

def ws_id_nat(+id: Key.ServerId) -> Nat:
  match id:
    case Key.ServerId{+n}: n

def ws_id_of(+n: Nat) -> Key.ServerId:
  Key.ServerId{n}

# ---- forwarders -----------------------------------------------------------
def net_fwd.got(g: Maybe<&1, Sess.UiMsg>, +s: Key.ServerId, +main: Chan(WsMsg), k: Unit -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+m}:
      do IO<Unit>:
        _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsNet{Sid.RoutedMsg{s, m}})
        k(Unit{})

@unsafe
def net_fwd(+s: Key.ServerId, +evt: Chan(Sess.UiMsg), +main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    net_fwd.got(g, s, main, _ => net_fwd(s, evt, main))

def ui_fwd.got(g: Maybe<&1, Sess.UiMsg>, +main: Chan(WsMsg), k: Unit -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+m}:
      do IO<Unit>:
        _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsUi{m})
        k(Unit{})

@unsafe
def ui_fwd(+ui_evt: Chan(Sess.UiMsg), +main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, ui_evt)
    ui_fwd.got(g, main, _ => ui_fwd(ui_evt, main))

# G3: the sole preferences receiver. One dedicated channel carries the
# single-flight worker, so completions never race actor traffic and the
# shutdown drain reads them from main with no second reader.
def prefs_fwd.got(g: Maybe<&1, Sess.UiMsg>, +main: Chan(WsMsg), k: Unit -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+m}:
      do IO<Unit>:
        _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsPrefs{m})
        k(Unit{})

@unsafe
def prefs_fwd(+pevts: Chan(Sess.UiMsg), +main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, pevts)
    prefs_fwd.got(g, main, _ => prefs_fwd(pevts, main))

# One-shot boot translation per server. Ready needs no post: the actor's
# reader posts Up itself. A failed dial quarantines only its own part via
# InitialFail; the spawn-time generation fences a boot that lost a race
# with a manual dial, exactly like the single-server boot watch.
def boot_fwd.got(g: Maybe<&1, Act.Boot>, +s: Key.ServerId, +gen: U32, +main: Chan(WsMsg)) -> IO(Unit):
  match g:
    case None{}: IO.pure(Unit, Unit{})
    case Some{e}:
      match e:
        case Act.Booted{}: IO.pure(Unit, Unit{})
        case Act.Down{+msg}:
          do IO<Unit>:
            _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsNet{Sid.RoutedMsg{s, Sess.FromNet{gen, Sess.InitialFail{msg}}}})
            return Unit{}

def boot_fwd(+s: Key.ServerId, +gen: U32, +boot: Chan(Act.Boot), +main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Act.Boot> <- Chan.recv(Act.Boot, boot)
    boot_fwd.got(g, s, gen, main)

@unsafe
def redial_watch(+main: Chan(WsMsg), +intent: Sid.Intent) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(2000)
    _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsRedial{intent})
    return Unit{}

@unsafe
def ws_typing_watch(+main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(1000)
    now_ms : U32 <- Clock.millis()
    _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsTick{now_ms})
    ws_typing_watch(main)

def ws_evt.pick(+c0: Chan(Sess.UiMsg), +c1: Chan(Sess.UiMsg), +c2: Chan(Sess.UiMsg), +c3: Chan(Sess.UiMsg), +n: Nat) -> Chan(Sess.UiMsg):
  match n:
    case 0n: c0
    case 1n: c1
    case 2n: c2
    case _: c3

def ws_evt.at(+evts: WsEvts, +n: Nat) -> Chan(Sess.UiMsg):
  match evts:
    case WsEvts{+c0, +c1, +c2, +c3}: ws_evt.pick(c0, c1, c2, c3, n)

def ws_evt.id(+evts: WsEvts, +id: Key.ServerId) -> Chan(Sess.UiMsg):
  match id:
    case Key.ServerId{+n}: ws_evt.at(evts, n)

# ---- emit -------------------------------------------------------------------
# No generation bump anywhere here: every RoutedCmd already carries the
# workspace generation, and the actor adopts the Dial's carried generation.
# OpenUrl failures notify the owning part via its event channel.
# Pong is quiet: the actor reader owns the single live wire PONG (gen-checked
# at the writer), so the loop never emits a duplicate socket reply.
# Search spawns the retained-fd worker through the shared Net owner with the
# captured part event channel, so completion routes back to its owner. The
# stamped part incarnation travels to the worker and back for the landed
# fence; the event channel alone cannot fence a re-added slot.
def ws_emit.to(+cmd: Sess.NetCmd, +c: Chan(Sess.NetCmd), +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match cmd:
    case Sess.Dial{+host, +port, gen, +nick}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, c, Sess.Dial{host, port, gen, nick})
        return Unit{}
    case Sess.Drop{}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, c, Sess.Drop{})
        return Unit{}
    case Sess.Hangup{}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, c, Sess.Hangup{})
        return Unit{}
    case Sess.Cont{+outs}:
      do IO<Unit>:
        _ : U32 <- Net.emit_outs(c, outs, 0, List.is_empty(&2, String, outs))
        return Unit{}
    case Sess.Pump{_}: IO.pure(Unit, Unit{})
    case Sess.Pong{_, _, _}: IO.pure(Unit, Unit{})
    case Sess.Begin{+gen}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, c, Sess.Begin{gen})
        return Unit{}
    case Sess.OpenUrl{+url}: Net.open_clicked(Some{evt}, url)
    case Sess.Search{+text, +target, +cursor, +orig, +endpoint, +history_on, +ticket, +sgen, +wgen}:
      do IO<Unit>:
        helper : String <- HSIO.program()
        Unit <- Net.search_spawn(String.eq(helper, "native"), endpoint, Hs.DiskQuery{text, target}, cursor, history_on, ticket, sgen, wgen, orig, evt)
        return Unit{}

def ws_emit.c0(+cmd: Sess.NetCmd, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match cmds:
    case WsCmds{+c, _, _, _}:
      match evts:
        case WsEvts{+e, _, _, _}: ws_emit.to(cmd, c, e)

def ws_emit.c1(+cmd: Sess.NetCmd, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match cmds:
    case WsCmds{_, +c, _, _}:
      match evts:
        case WsEvts{_, +e, _, _}: ws_emit.to(cmd, c, e)

def ws_emit.c2(+cmd: Sess.NetCmd, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match cmds:
    case WsCmds{_, _, +c, _}:
      match evts:
        case WsEvts{_, _, +e, _}: ws_emit.to(cmd, c, e)

def ws_emit.c3(+cmd: Sess.NetCmd, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match cmds:
    case WsCmds{_, _, _, +c}:
      match evts:
        case WsEvts{_, _, _, +e}: ws_emit.to(cmd, c, e)

def ws_emit.chan(+cmd: Sess.NetCmd, +cmds: WsCmds, +evts: WsEvts, +n: Nat) -> IO(Unit):
  match n:
    case 0n: ws_emit.c0(cmd, cmds, evts)
    case 1n: ws_emit.c1(cmd, cmds, evts)
    case 2n: ws_emit.c2(cmd, cmds, evts)
    case _: ws_emit.c3(cmd, cmds, evts)

def ws_emit.id(+cmd: Sess.NetCmd, +cmds: WsCmds, +evts: WsEvts, +id: Key.ServerId) -> IO(Unit):
  match id:
    case Key.ServerId{+n}: ws_emit.chan(cmd, cmds, evts, n)

def ws_emit(+rc: Sid.RoutedCmd, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match rc:
    case Sid.RoutedCmd{+s, +cmd}: ws_emit.id(cmd, cmds, evts, s)

# /quit only. The focused RoutedCmd is emitted by the caller; this sends
# the same QUIT lines to every other live part before shutdown closes
# command channels. Ordinary keys stay single-part.
def ws_emit_list(+rcs: List<&2, Sid.RoutedCmd>, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match rcs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{+h, +t}:
      do IO<Unit>:
        Unit <- ws_emit(h, cmds, evts)
        ws_emit_list(t, cmds, evts)

def ws_emit_quit(+ws: W.Workspace, +rc: Sid.RoutedCmd, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  ws_emit_list(W.quit_broadcast(ws, rc), cmds, evts)

def ws_emit_maybe(+mrc: Maybe<&2, Sid.RoutedCmd>, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match mrc:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+rc}: ws_emit(rc, cmds, evts)

def ws_emit_outs.go(empty: Bool, +s: Key.ServerId, +outs: List<&2, String>, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match empty:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: ws_emit(Sid.RoutedCmd{s, Sess.Cont{outs}}, cmds, evts)

def ws_emit_outs(+s: Key.ServerId, +outs: List<&2, String>, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  ws_emit_outs.go(List.is_empty(&2, String, outs), s, outs, cmds, evts)

def ws_schedule(+mi: Maybe<&2, Sid.Intent>, +main: Chan(WsMsg)) -> IO(Unit):
  match mi:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+i}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, redial_watch(main, i))
        return Unit{}
# ---- leases (G1/G2/G3 origin bindings) ---------------------------------------
# A lease records a worker's spawn origin (server plus generation).
# Upload records prune stale origins. Preferences retain their physical
# binding until the exact ticket completes, but fence Session effects by
# live origin. The global image lease uses the WsMedia envelope below.
def ws_lease.match(+lease: WsLease, +s: Key.ServerId, +gen: U32) -> Bool:
  match lease:
    case WsLease{+owner, +wanted}: Key.eq(owner, s) && U32.is_eq(wanted, gen)

def ws_lease.kept_at(+got: Maybe<&2, W.Part>, +s: Key.ServerId, +gen: U32) -> Maybe<&2, WsLease>:
  match got:
    case None{}: None{}
    case Some{+p}: Bool.pick(Maybe<&2, WsLease>, U32.is_eq(W.part_gen(p), gen), Some{WsLease{s, gen}}, None{})

def ws_lease.kept(+lease: Maybe<&2, WsLease>, +ws: W.Workspace) -> Maybe<&2, WsLease>:
  match lease:
    case None{}: None{}
    case Some{WsLease{+s, +gen}}: ws_lease.kept_at(W.find_part(ws, s), s, gen)

def ws_lease.up_drop_at(drop: Bool, +h: WsLease, +rest: List<&2, WsLease>) -> List<&2, WsLease>:
  match drop:
    case True{}: rest
    case False{}: h <> rest

def ws_lease.up_drop(+xs: List<&2, WsLease>, +id: Key.ServerId) -> List<&2, WsLease>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      match h:
        case WsLease{+s, _}: ws_lease.up_drop_at(Key.eq(s, id), h, ws_lease.up_drop(t, id))

def ws_lease.up_add(+xs: List<&2, WsLease>, +id: Key.ServerId, +gen: U32) -> List<&2, WsLease>:
  WsLease{id, gen} <> ws_lease.up_drop(xs, id)

def ws_lease.up_has(+xs: List<&2, WsLease>, +id: Key.ServerId, +gen: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, +t}: ws_lease.match(h, id, gen) || ws_lease.up_has(t, id, gen)

def ws_lease.up_took(+xs: List<&2, WsLease>, +job: Maybe<&2, Up.Request>, +id: Key.ServerId, +gen: U32) -> List<&2, WsLease>:
  match job:
    case None{}: xs
    case Some{_}: ws_lease.up_add(xs, id, gen)

def ws_lease.up_kept_hit(hit: Bool, +s: Key.ServerId, +gen: U32, +kept: List<&2, WsLease>) -> List<&2, WsLease>:
  match hit:
    case True{}: WsLease{s, gen} <> kept
    case False{}: kept

def ws_lease.up_kept_at(+got: Maybe<&2, W.Part>, +s: Key.ServerId, +gen: U32, +kept: List<&2, WsLease>) -> List<&2, WsLease>:
  match got:
    case None{}: kept
    case Some{+p}: ws_lease.up_kept_hit(U32.is_eq(W.part_gen(p), gen), s, gen, kept)

def ws_lease.up_kept.go(+xs: List<&2, WsLease>, +ws: W.Workspace) -> List<&2, WsLease>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      match h:
        case WsLease{+s, +gen}: ws_lease.up_kept_at(W.find_part(ws, s), s, gen, ws_lease.up_kept.go(t, ws))

def ws_lease.up_kept(+xs: List<&2, WsLease>, +ws: W.Workspace) -> List<&2, WsLease>:
  ws_lease.up_kept.go(xs, ws)

# G3: the sole preferences owner follows the single-flight worker.
# Only a fresh spawn (inactive before start, active after) moves the
# owner to the spawning stage's current part; a carried worker keeps
# its owner and a quiet channel clears it.
def ws_lease.prefs_next(+owner: Maybe<&2, WsLease>, was_active: Bool, is_active: Bool, +id: Key.ServerId, +gen: U32) -> Maybe<&2, WsLease>:
  match was_active:
    case True{}: Bool.pick(Maybe<&2, WsLease>, is_active, owner, None{})
    case False{}: Bool.pick(Maybe<&2, WsLease>, is_active, Some{WsLease{id, gen}}, None{})

# The preference lease follows the physical job, not the connection. Keep
# it across reconnect/removal until Runtime accepts its exact completion.
# Workspace is deliberately not a physical-ownership fence.
def ws_prefs.owner(ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ws: W.Workspace) -> Maybe<&2, WsLease>:
  Bool.pick(Maybe<&2, WsLease>, PrefLive.active(ctx), owner, None{})

# M2/G2: the global image lease moves only from free to taken and
# retires only on the exact spawned completion. There is deliberately
# no kept/prune helper here: absent parts and slot-generation changes
# never free the lease. Admission (lease free) is a spawn gate only,
# never permission to free another origin's outstanding worker.
def ws_mlease.free(+lease: Maybe<&2, WsMedia>) -> Bool:
  match lease:
    case None{}: True{}
    case Some{_}: False{}

def ws_mlease.req_match.fields(+generation: Nat, +ticket: Nat, +url: String, got: Maybe<&2, M.Work>) -> Bool:
  match got:
    case None{}: False{}
    case Some{M.Work{_, u, g, t}}: Nat.is_eq(g, generation) && Nat.is_eq(t, ticket) && String.eq(u, url)

def ws_mlease.req_match(+req: M.Request, +generation: Nat, +ticket: Nat, +url: String) -> Bool:
  ws_mlease.req_match.fields(generation, ticket, url, M.work_fields(req))

def ws_mlease.exact(+lease: Maybe<&2, WsMedia>, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String) -> Bool:
  match lease:
    case None{}: False{}
    case Some{+held}:
      match held:
        case WsMedia{+owner, _, +req}: Key.eq(owner, s) && ws_mlease.req_match(req, generation, ticket, url)

def ws_mlease.live(+lease: Maybe<&2, WsMedia>, +s: Key.ServerId, +gen: U32) -> Bool:
  match lease:
    case None{}: False{}
    case Some{+held}:
      match held:
        case WsMedia{+owner, +wanted, _}: Key.eq(owner, s) && U32.is_eq(wanted, gen)

# C2: the global cards lease moves only from free to taken and retires
# only on the exact spawned completion. Same shape as ws_mlease: there is
# deliberately no kept/prune helper here, absent parts and slot-generation
# changes never free the lease, and admission (lease free) is a spawn gate
# only, never permission to free another origin's outstanding worker.
def ws_clease.free(+lease: Maybe<&2, WsCardsLease>) -> Bool:
  match lease:
    case None{}: True{}
    case Some{_}: False{}

def ws_clease.req_match(+req: C.Request, +generation: Nat, +ticket: Nat, +url: String) -> Bool:
  match req:
    case C.Request{_, u, g, t}: Nat.is_eq(g, generation) && Nat.is_eq(t, ticket) && String.eq(u, url)

def ws_clease.exact(+lease: Maybe<&2, WsCardsLease>, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String) -> Bool:
  match lease:
    case None{}: False{}
    case Some{+held}:
      match held:
        case WsCardsLease{+owner, _, +req}: Key.eq(owner, s) && ws_clease.req_match(req, generation, ticket, url)

def ws_clease.live(+lease: Maybe<&2, WsCardsLease>, +s: Key.ServerId, +gen: U32) -> Bool:
  match lease:
    case None{}: False{}
    case Some{+held}:
      match held:
        case WsCardsLease{+owner, +wanted, _}: Key.eq(owner, s) && U32.is_eq(wanted, gen)

# ---- desktop notifications (per-part NotifyLive + one global lease) --------
# Each live part owns its logical NotifyLive (accepted N9 owner): per-part
# scan floor and marks in its own 2^44 ID range, bounded async queue, and
# durable per-ID archive claims. One global physical lease serializes helper
# children across parts. Startup seeds each part floor from its history;
# live part-bell advances collect per-event mention/DM rows above the part
# floor via Sess.notify_collect (actual dm/mention, never forced, never
# final-id-only), stage through Sess.notify_live_observe (marks-on-admit,
# scope/id sort), and hand to one detached worker (NIO.run_jobs_done) with
# ticket+origin completion binding (Sess.NotifyDone). No synchronous block
# on the loop path; failures post UiError via the handing part's own
# channel (lazy log), never as content.
def ws_notify.seed_part(+p: W.Part) -> WsNotifyPart:
  match p:
    case W.Part{+id, +gen, _, +sest}:
      WsNotifyPart{id, gen, Sess.notify_live_init_ep(N.on(), Cl.log_seq_of(Sess.session_cl(sest)), Sess.notify_scope_of(sest))}

def ws_notify.seed_go(+xs: List<&2, W.Part>) -> List<&2, WsNotifyPart>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}: ws_notify.seed_part(h) <> ws_notify.seed_go(t)

def ws_notify.seed_all(+ws: W.Workspace) -> WsNotify:
  WsNotify{ws_notify.seed_go(W.ws_parts(ws)), None{}, 1n}

def ws_notify.parts(+nnot: WsNotify) -> List<&2, WsNotifyPart>:
  match nnot:
    case WsNotify{+parts, _, _}: parts

def ws_notify.lease(+nnot: WsNotify) -> Maybe<&2, WsNotifyLease>:
  match nnot:
    case WsNotify{_, +lease, _}: lease

def ws_notify.next(+nnot: WsNotify) -> Nat:
  match nnot:
    case WsNotify{_, _, +next}: next

def ws_npart.sid(+e: WsNotifyPart) -> Key.ServerId:
  match e:
    case WsNotifyPart{+s, _, _}: s

def ws_npart.find_hit(hit: Bool, +h: WsNotifyPart, +rec: Maybe<&2, WsNotifyPart>) -> Maybe<&2, WsNotifyPart>:
  match hit:
    case True{}: Some{h}
    case False{}: rec

def ws_npart.find(+xs: List<&2, WsNotifyPart>, +id: Key.ServerId) -> Maybe<&2, WsNotifyPart>:
  match xs:
    case Nil{}: None{}
    case Con{+h, +t}: ws_npart.find_hit(Key.eq(ws_npart.sid(h), id), h, ws_npart.find(t, id))

def ws_npart.drop_hit(hit: Bool, +h: WsNotifyPart, +rec: List<&2, WsNotifyPart>) -> List<&2, WsNotifyPart>:
  match hit:
    case True{}: rec
    case False{}: h <> rec

def ws_npart.drop(+xs: List<&2, WsNotifyPart>, +id: Key.ServerId) -> List<&2, WsNotifyPart>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}: ws_npart.drop_hit(Key.eq(ws_npart.sid(h), id), h, ws_npart.drop(t, id))

def ws_npart.upsert(+xs: List<&2, WsNotifyPart>, +e: WsNotifyPart) -> List<&2, WsNotifyPart>:
  e <> ws_npart.drop(xs, ws_npart.sid(e))

def ws_npart.nl(+e: WsNotifyPart) -> Sess.NotifyLive:
  match e:
    case WsNotifyPart{_, _, +nl}: nl

# Tickets stay globally monotone: each observe/complete runs with the shared
# counter adopted into the part entry, and the loop adopts the result back.
def ws_notify.reticket(+nl: Sess.NotifyLive, +next: Nat) -> Sess.NotifyLive:
  match nl:
    case Sess.NotifyLive{+st, +q, +floor, +active, _, +endpoint, +origin, +claimed}:
      Sess.NotifyLive{st, q, floor, active, next, endpoint, origin, claimed}

def ws_notify.requeued(+nl: Sess.NotifyLive, +q: N.Queue) -> Sess.NotifyLive:
  match nl:
    case Sess.NotifyLive{+st, _, +floor, +active, +next, +endpoint, +origin, +claimed}:
      Sess.NotifyLive{st, q, floor, active, next, endpoint, origin, claimed}

def ws_notify.fresh_nl(+sess: Sess.Session) -> Sess.NotifyLive:
  Sess.notify_live_init_ep(N.on(), Cl.log_seq_of(Sess.session_cl(sess)), Sess.notify_scope_of(sess))

# Reconnect floor: a same-endpoint reconnect seeds the fresh entry at the
# PRE-accept sequence, so the burst that triggered the accept still stages
# (marks advance only for admitted rows; no floor jump past live rows). A
# changed endpoint keeps the post floor (quiet fresh start, never a stale
# pre floor that would silence the new connection or stage foreign rows).
def ws_notify.fresh_scope(same: Bool, +pre: Sess.Session, +post: Sess.Session) -> Sess.NotifyLive:
  match same:
    case True{}: Sess.notify_live_init_ep(N.on(), Cl.log_seq_of(Sess.session_cl(pre)), Sess.notify_scope_of(post))
    case False{}: ws_notify.fresh_nl(post)

def ws_notify.fresh_nl_pre(+pre: Sess.Session, +post: Sess.Session) -> Sess.NotifyLive:
  ws_notify.fresh_scope(String.eq(Sess.notify_scope_of(pre), Sess.notify_scope_of(post)), pre, post)

# Same-endpoint reconnect keeps logical state; a changed endpoint resets it
# through the accepted owner (physical worker retained, queued logical work
# cleared).
def ws_notify.reset_changed(changed: Bool, +nl: Sess.NotifyLive, +scope: String, +floor: Nat) -> Sess.NotifyLive:
  match changed:
    case True{}: Sess.notify_live_reset_endpoint(nl, scope, floor)
    case False{}: nl

def ws_notify.fenced_live(+nl: Sess.NotifyLive, +sess: Sess.Session) -> Sess.NotifyLive:
  +scope = Sess.notify_scope_of(sess)
  ws_notify.reset_changed(Bool.not(String.eq(Sess.notify_live_endpoint(nl), scope)), nl, scope, Cl.log_seq_of(Sess.session_cl(sess)))

# Slot-generation fence (mirrors WsCards): a re-added slot starts a fresh
# logical entry, dropping the replaced incarnation's queued work, while the
# global lease (if any) still releases exactly once on its own completion.
# Fresh entries reconcile through the shared pre/post owner: same-endpoint
# reconnects seed at the pre-accept floor, changed endpoints at post.
def ws_notify.fenced_entry(fenced: Bool, +nl: Sess.NotifyLive, +pre: Sess.Session, +post: Sess.Session) -> Sess.NotifyLive:
  match fenced:
    case True{}: ws_notify.fenced_live(nl, post)
    case False{}: ws_notify.fresh_nl_pre(pre, post)

def ws_notify.entry_found(+got: Maybe<&2, WsNotifyPart>, +gen: U32, +pre: Sess.Session, +post: Sess.Session) -> Sess.NotifyLive:
  match got:
    case None{}: ws_notify.fresh_nl_pre(pre, post)
    case Some{WsNotifyPart{_, +wanted, +nl}}: ws_notify.fenced_entry(U32.is_eq(wanted, gen), nl, pre, post)

def ws_notify.entry_nl(+parts: List<&2, WsNotifyPart>, +s: Key.ServerId, +gen: U32, +pre: Sess.Session, +post: Sess.Session) -> Sess.NotifyLive:
  ws_notify.entry_found(ws_npart.find(parts, s), gen, pre, post)

def ws_nlease.free(+lease: Maybe<&2, WsNotifyLease>) -> Bool:
  match lease:
    case None{}: True{}
    case Some{_}: False{}

# A completion releases only the exact outstanding worker: same owner slot
# (the notice channel captured at spawn), same ticket, same origin endpoint.
# Anything else drops with no state change (hardening; never a release).
def ws_nlease.hit(+lease: Maybe<&2, WsNotifyLease>, +s: Key.ServerId, +ticket: Nat, +endpoint: String) -> Bool:
  match lease:
    case None{}: False{}
    case Some{WsNotifyLease{+owner, _, +want_ticket, +want_ep}}:
      Key.eq(owner, s) && Nat.is_eq(want_ticket, ticket) && String.eq(want_ep, endpoint)

def ws_notify.lease_after(+active: Maybe<&2, Nat>, +parts2: List<&2, WsNotifyPart>, +nl2: Sess.NotifyLive, +s: Key.ServerId, +gen: U32, +lease: Maybe<&2, WsNotifyLease>, +jobs: List<&2, N.Req>) -> WsNotify & List<&2, N.Req>:
  match active:
    case None{}: (WsNotify{parts2, lease, Sess.notify_live_next(nl2)}, jobs)
    case Some{+ticket}: (WsNotify{parts2, Some{WsNotifyLease{s, gen, ticket, Sess.notify_live_endpoint(nl2)}}, Sess.notify_live_next(nl2)}, jobs)

def ws_notify.observed_live(pair: Sess.NotifyLive & List<&2, N.Req>, +parts: List<&2, WsNotifyPart>, +s: Key.ServerId, +gen: U32, +lease: Maybe<&2, WsNotifyLease>) -> WsNotify & List<&2, N.Req>:
  match pair:
    case (+nl2, +jobs):
      ws_notify.lease_after(Sess.notify_live_active(nl2), ws_npart.upsert(parts, WsNotifyPart{s, gen, nl2}), nl2, s, gen, lease, jobs)

# Fire path: observe one part through its accepted owner. The handoff spawns
# only while the global lease is free, so at most one helper child runs;
# otherwise the part quiet-stages into its own queue for a later completion.
# The pre/post form seeds reconnect-fresh entries at the pre-accept floor;
# the single-session form keeps the historical post-only behavior.
def ws_notify.observed_pre(+nnot: WsNotify, +s: Key.ServerId, +gen: U32, +pre: Sess.Session, +post: Sess.Session, +deliver: Bool) -> WsNotify & List<&2, N.Req>:
  match nnot:
    case WsNotify{+parts, +lease, +next}:
      +nl0 = ws_notify.reticket(ws_notify.entry_nl(parts, s, gen, pre, post), next)
      ws_notify.observed_live(Sess.notify_live_observe(nl0, post, deliver && ws_nlease.free(lease), Hs.hist_live_archived(Sess.session_hist_live(post))), parts, s, gen, lease)

def ws_notify.observed(+nnot: WsNotify, +s: Key.ServerId, +gen: U32, +pst: Sess.Session, +deliver: Bool) -> WsNotify & List<&2, N.Req>:
  ws_notify.observed_pre(nnot, s, gen, pst, pst, deliver)

# Done path: the exact outstanding worker releases the global lease once,
# then the owner rescans its live rows (rows that overflowed the bounded
# queue were never admitted, so only a rescan delivers them without a new
# chunk), and otherwise the first other part with retained work hands it.
# Every spawn below uses the handing part's own channel (attribution).
type StealDecision is Data:
  Continue{parts: List<&2, WsNotifyPart>, next: Nat}
  Handed{nnot: WsNotify, jobs: List<&2, N.Req>}

def ws_notify.steal_pick.active(+active: Maybe<&2, Nat>, +parts2: List<&2, WsNotifyPart>, +nl2: Sess.NotifyLive, +id: Key.ServerId, +gen: U32, +jobs: List<&2, N.Req>) -> StealDecision:
  match active:
    case None{}: Continue{parts2, Sess.notify_live_next(nl2)}
    case Some{+ticket}: Handed{WsNotify{parts2, Some{WsNotifyLease{id, gen, ticket, Sess.notify_live_endpoint(nl2)}}, Sess.notify_live_next(nl2)}, jobs}

def ws_notify.steal_pick.empty(empty: Bool, +active: Maybe<&2, Nat>, +parts2: List<&2, WsNotifyPart>, +nl2: Sess.NotifyLive, +id: Key.ServerId, +gen: U32, +jobs: List<&2, N.Req>) -> StealDecision:
  match empty:
    case True{}: Continue{parts2, Sess.notify_live_next(nl2)}
    case False{}: ws_notify.steal_pick.active(active, parts2, nl2, id, gen, jobs)

def ws_notify.steal_pick.observed(pair: Sess.NotifyLive & List<&2, N.Req>, +parts: List<&2, WsNotifyPart>, +id: Key.ServerId, +gen: U32) -> StealDecision:
  match pair:
    case (+nl2, +jobs):
      ws_notify.steal_pick.empty(List.is_empty(&2, N.Req, jobs), Sess.notify_live_active(nl2), ws_npart.upsert(parts, WsNotifyPart{id, gen, nl2}), nl2, id, gen, jobs)

def ws_notify.steal_pick.skip(skip_it: Bool, +parts: List<&2, WsNotifyPart>, +id: Key.ServerId, +gen: U32, +pst: Sess.Session, +next: Nat, +deliver: Bool) -> StealDecision:
  match skip_it:
    case True{}: Continue{parts, next}
    case False{}:
      +nl0 = ws_notify.reticket(ws_notify.entry_nl(parts, id, gen, pst, pst), next)
      ws_notify.steal_pick.observed(Sess.notify_live_observe(nl0, pst, deliver, Hs.hist_live_archived(Sess.session_hist_live(pst))), parts, id, gen)

def ws_notify.steal_go(+xs: List<&2, W.Part>, d: StealDecision, +skip: Key.ServerId, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match xs:
    case Nil{}:
      match d:
        case Handed{+nnot2, +jobs}: (nnot2, jobs, True{})
        case Continue{+parts, +next}: (WsNotify{parts, None{}, next}, Nil{}, True{})
    case Con{W.Part{+id, +gen, _, +pst}, +t}:
      match d:
        case Handed{+nnot2, +jobs}: (nnot2, jobs, True{})
        case Continue{+parts, +next}:
          ws_notify.steal_go(t, ws_notify.steal_pick.skip(Key.eq(id, skip), parts, id, gen, pst, next, deliver), skip, deliver)

def ws_notify.steal_round(+xs: List<&2, W.Part>, +nnot: WsNotify, +skip: Key.ServerId, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match nnot:
    case WsNotify{+parts, _, +next}: ws_notify.steal_go(xs, Continue{parts, next}, skip, deliver)

# Owner rescan after release: an empty drain rescans live (the overflowed
# ninth hands here with no new chunk); a nonempty drain merges a
# rescan-quiet admission into the same single spawn under its ticket.
def ws_notify.owner_claimed(+active: Maybe<&2, Nat>, +parts2: List<&2, WsNotifyPart>, +nl3: Sess.NotifyLive, +owner: Key.ServerId, +gen: U32, +handed: List<&2, N.Req>) -> WsNotify & List<&2, N.Req> & Bool:
  match active:
    case None{}: (WsNotify{parts2, None{}, Sess.notify_live_next(nl3)}, Nil{}, True{})
    case Some{+ticket}: (WsNotify{parts2, Some{WsNotifyLease{owner, gen, ticket, Sess.notify_live_endpoint(nl3)}}, Sess.notify_live_next(nl3)}, handed, True{})

def ws_notify.owner_idle(empty: Bool, +parts2: List<&2, WsNotifyPart>, +nl3: Sess.NotifyLive, +ws: W.Workspace, +owner: Key.ServerId, +gen: U32, +handed: List<&2, N.Req>, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match empty:
    case False{}:
      ws_notify.owner_claimed(Sess.notify_live_active(nl3), parts2, nl3, owner, gen, handed)
    case True{}:
      ws_notify.steal_round(W.ws_parts(ws), WsNotify{parts2, None{}, Sess.notify_live_next(nl3)}, owner, deliver)

def ws_notify.owner_handed(pair: Sess.NotifyLive & List<&2, N.Req>, +parts: List<&2, WsNotifyPart>, +ws: W.Workspace, +owner: Key.ServerId, +gen: U32, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match pair:
    case (+nl3, +handed):
      ws_notify.owner_idle(List.is_empty(&2, N.Req, handed), ws_npart.upsert(parts, WsNotifyPart{owner, gen, nl3}), nl3, ws, owner, gen, handed, deliver)

def ws_notify.owner_all(+active: Maybe<&2, Nat>, +parts2: List<&2, WsNotifyPart>, +nl4: Sess.NotifyLive, +ws: W.Workspace, +owner: Key.ServerId, +gen: U32, +all: List<&2, N.Req>, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match active:
    case None{}: ws_notify.steal_round(W.ws_parts(ws), WsNotify{parts2, None{}, Sess.notify_live_next(nl4)}, owner, deliver)
    case Some{+ticket}: (WsNotify{parts2, Some{WsNotifyLease{owner, gen, ticket, Sess.notify_live_endpoint(nl4)}}, Sess.notify_live_next(nl4)}, all, True{})

def ws_notify.owner_drained(drained: N.Queue & List<&2, N.Req>, +nl3: Sess.NotifyLive, +jobs: List<&2, N.Req>, +parts: List<&2, WsNotifyPart>, +ws: W.Workspace, +owner: Key.ServerId, +gen: U32, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match drained:
    case (+kept, +extra):
      +all = List.append(&2, N.Req, jobs, extra)
      +nl4 = ws_notify.requeued(nl3, kept)
      ws_notify.owner_all(Sess.notify_live_active(nl4), ws_npart.upsert(parts, WsNotifyPart{owner, gen, nl4}), nl4, ws, owner, gen, all, deliver)

def ws_notify.owner_merged(pair: Sess.NotifyLive & List<&2, N.Req>, +jobs: List<&2, N.Req>, +parts: List<&2, WsNotifyPart>, +ws: W.Workspace, +owner: Key.ServerId, +gen: U32, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match pair:
    case (+nl3, _):
      ws_notify.owner_drained(N.drain_all(Sess.notify_live_queue(nl3)), nl3, jobs, parts, ws, owner, gen, deliver)

def ws_notify.owner_jobs(empty: Bool, +nl2: Sess.NotifyLive, +jobs: List<&2, N.Req>, +parts: List<&2, WsNotifyPart>, +ws: W.Workspace, +owner: Key.ServerId, +gen: U32, +pst: Sess.Session, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match empty:
    case True{}: ws_notify.owner_handed(Sess.notify_live_observe(nl2, pst, deliver, Hs.hist_live_archived(Sess.session_hist_live(pst))), parts, ws, owner, gen, deliver)
    case False{}: ws_notify.owner_merged(Sess.notify_live_observe(nl2, pst, False{}, Hs.hist_live_archived(Sess.session_hist_live(pst))), jobs, parts, ws, owner, gen, deliver)

def ws_notify.owner_completed(triple: Sess.NotifyLive & List<&2, N.Req> & Bool, +parts: List<&2, WsNotifyPart>, +ws: W.Workspace, +owner: Key.ServerId, +gen: U32, +pst: Sess.Session, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match triple:
    case (+nl2, +jobs, _):
      ws_notify.owner_jobs(List.is_empty(&2, N.Req, jobs), nl2, jobs, parts, ws, owner, gen, pst, deliver)

def ws_notify.owner_round(+found: Maybe<&2, W.Part>, +parts: List<&2, WsNotifyPart>, +next: Nat, +ws: W.Workspace, +owner: Key.ServerId, +ticket: Nat, +endpoint: String, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match found:
    case None{}:
      ws_notify.steal_round(W.ws_parts(ws), WsNotify{parts, None{}, next}, owner, deliver)
    case Some{W.Part{_, +gen, _, +pst}}:
      +nl0 = ws_notify.reticket(ws_notify.entry_nl(parts, owner, gen, pst, pst), next)
      ws_notify.owner_completed(Sess.notify_live_complete(nl0, ticket, endpoint), parts, ws, owner, gen, pst, deliver)

def ws_notify.completed_hit(hit: Bool, +parts: List<&2, WsNotifyPart>, +lease: Maybe<&2, WsNotifyLease>, +next: Nat, +ws: W.Workspace, +s: Key.ServerId, +ticket: Nat, +endpoint: String, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match hit:
    case False{}: (WsNotify{parts, lease, next}, Nil{}, False{})
    case True{}: ws_notify.owner_round(W.find_part(ws, s), parts, next, ws, s, ticket, endpoint, deliver)

def ws_notify.completed_lease(+lease: Maybe<&2, WsNotifyLease>, +parts: List<&2, WsNotifyPart>, +next: Nat, +ws: W.Workspace, +s: Key.ServerId, +ticket: Nat, +endpoint: String, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  ws_notify.completed_hit(ws_nlease.hit(lease, s, ticket, endpoint), parts, lease, next, ws, s, ticket, endpoint, deliver)

def ws_notify.completed(+nnot: WsNotify, +ws: W.Workspace, +s: Key.ServerId, +ticket: Nat, +endpoint: String, +deliver: Bool) -> WsNotify & List<&2, N.Req> & Bool:
  match nnot:
    case WsNotify{+parts, +lease, +next}:
      ws_notify.completed_lease(lease, parts, next, ws, s, ticket, endpoint, deliver)

# History install: accepted archives merge their real per-ID claims (archive
# rows stay quiet while pending live rows still deliver); stale or refused
# installs leave notify state untouched.
def ws_notify.seeded_part(+got: Maybe<&2, W.Part>, +parts: List<&2, WsNotifyPart>, +lease: Maybe<&2, WsNotifyLease>, +next: Nat, +s: Key.ServerId, accepted: Bool, +installed: List<&2, Nat>) -> WsNotify:
  match got:
    case None{}: WsNotify{parts, lease, next}
    case Some{W.Part{_, +gen, _, +pst}}:
      +nl0 = ws_notify.entry_nl(parts, s, gen, pst, pst)
      WsNotify{ws_npart.upsert(parts, WsNotifyPart{s, gen, Sess.notify_live_seed_accepted(accepted, nl0, installed)}), lease, next}

def ws_notify.seeded(+nnot: WsNotify, +ws: W.Workspace, +s: Key.ServerId, accepted: Bool, +installed: List<&2, Nat>) -> WsNotify:
  match nnot:
    case WsNotify{+parts, +lease, +next}:
      ws_notify.seeded_part(W.find_part(ws, s), parts, lease, next, s, accepted, installed)

def ws_notify.spawn_ticket(+lease: Maybe<&2, WsNotifyLease>, +h: String, +jobs: List<&2, N.Req>, +evts: WsEvts, +nnot2: WsNotify, +ws: W.Workspace) -> IO(WsNotify & W.Workspace):
  match lease:
    case None{}: IO.pure(WsNotify & W.Workspace, (nnot2, ws))
    case Some{WsNotifyLease{+owner, _, +ticket, +endpoint}}:
      do IO<WsNotify & W.Workspace>:
        Unit <- IO.spawn(Unit, NIO.run_jobs_done(h, jobs, Some{ws_evt.id(evts, owner)}, ticket, endpoint))
        return (nnot2, ws)

def ws_notify.spawn_helper(helper: Maybe<&2, String>, +nnot2: WsNotify, +jobs: List<&2, N.Req>, +evts: WsEvts, +ws: W.Workspace) -> IO(WsNotify & W.Workspace):
  match helper:
    case None{}: IO.pure(WsNotify & W.Workspace, (nnot2, ws))
    case Some{+h}:
      ws_notify.spawn_ticket(ws_notify.lease(nnot2), h, jobs, evts, nnot2, ws)

def ws_notify.spawn_jobs(empty: Bool, +nnot2: WsNotify, +jobs: List<&2, N.Req>, +helper: Maybe<&2, String>, +evts: WsEvts, +ws: W.Workspace) -> IO(WsNotify & W.Workspace):
  match empty:
    case True{}: IO.pure(WsNotify & W.Workspace, (nnot2, ws))
    case False{}: ws_notify.spawn_helper(helper, nnot2, jobs, evts, ws)

def ws_notify.fired(pair: WsNotify & List<&2, N.Req>, +helper: Maybe<&2, String>, +evts: WsEvts, +ws: W.Workspace) -> IO(WsNotify & W.Workspace):
  match pair:
    case (+nnot2, +jobs):
      ws_notify.spawn_jobs(List.is_empty(&2, N.Req, jobs), nnot2, jobs, helper, evts, ws)

def ws_notify.fire(+nnot: WsNotify, +ws: W.Workspace, +s: Key.ServerId, +gen: U32, +pre: Sess.Session, +post: Sess.Session, +evts: WsEvts) -> IO(WsNotify & W.Workspace):
  do IO<WsNotify & W.Workspace>:
    +default : String <- T.Sys.notify_default()
    +helper : Maybe<&2, String> <- NIO.program_or_default(default)
    ws_notify.fired(ws_notify.observed_pre(nnot, s, gen, pre, post, NIO.can_deliver(helper)), helper, evts, ws)

def ws_notify.done_released(released: Bool, +nnot2: WsNotify, +jobs: List<&2, N.Req>, +helper: Maybe<&2, String>, +evts: WsEvts, +ws: W.Workspace) -> IO(WsNotify & W.Workspace):
  match released:
    case False{}: IO.pure(WsNotify & W.Workspace, (nnot2, ws))
    case True{}: ws_notify.spawn_jobs(List.is_empty(&2, N.Req, jobs), nnot2, jobs, helper, evts, ws)

def ws_notify.done_fired(triple: WsNotify & List<&2, N.Req> & Bool, +helper: Maybe<&2, String>, +evts: WsEvts, +ws: W.Workspace) -> IO(WsNotify & W.Workspace):
  match triple:
    case (+nnot2, +jobs, released):
      ws_notify.done_released(released, nnot2, jobs, helper, evts, ws)

def ws_notify.done(+nnot: WsNotify, +ticket: Nat, +endpoint: String, +ws: W.Workspace, +s: Key.ServerId, +evts: WsEvts) -> IO(WsNotify & W.Workspace):
  do IO<WsNotify & W.Workspace>:
    +default : String <- T.Sys.notify_default()
    +helper : Maybe<&2, String> <- NIO.program_or_default(default)
    ws_notify.done_fired(ws_notify.completed(nnot, ws, s, ticket, endpoint, NIO.can_deliver(helper)), helper, evts, ws)

# ---- per-part cards sidecars (actual C/CNet policy) ------------------------
# Scheduling runs the same pure C scheduling as single-server (painted
# visibility, mutes, media exclusion, exact completion) with one worker
# per live part. State lives here instead of a Session cf field.
def ws_cards.net_ok(+net: Sess.NetState) -> Bool:
  match net:
    case Sess.Stopping{_}: False{}
    case _: True{}

def ws_cards.sid(+e: WsCards) -> Key.ServerId:
  match e:
    case WsCards{+s, _, _, _}: s

def ws_cards.find_pick(hit: Bool, +h: WsCards, +rest: Maybe<&2, WsCards>) -> Maybe<&2, WsCards>:
  match hit:
    case True{}: Some{h}
    case False{}: rest

def ws_cards.find(+xs: List<&2, WsCards>, +id: Key.ServerId) -> Maybe<&2, WsCards>:
  match xs:
    case Nil{}: None{}
    case Con{+h, +t}: ws_cards.find_pick(Key.eq(ws_cards.sid(h), id), h, ws_cards.find(t, id))

def ws_cards.drop_pick(hit: Bool, +h: WsCards, +rest: List<&2, WsCards>) -> List<&2, WsCards>:
  match hit:
    case True{}: rest
    case False{}: h <> rest

def ws_cards.drop(+xs: List<&2, WsCards>, +id: Key.ServerId) -> List<&2, WsCards>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}: ws_cards.drop_pick(Key.eq(ws_cards.sid(h), id), h, ws_cards.drop(t, id))

def ws_cards.upsert(+xs: List<&2, WsCards>, +e: WsCards) -> List<&2, WsCards>:
  e <> ws_cards.drop(xs, ws_cards.sid(e))

# Slot fence for the sidecar queues: a generation mismatch resets (fresh
# queues, bumped generation) but RETAINS the sidecar active worker until
# its exact completion releases it, exactly like C.reset. Reinitializing
# would reset inner generation/ticket to 1/1 and let the old same-URL
# result collide with a new request. The physical single-flight itself is
# the global C2 lease, which the fence never frees. Fresh sidecars honor
# the BIRC_CARDS opt-out flag; the flag is process-constant, read live at
# each materialization point (stage, completion, paint, keys).
def ws_cards.fenced(fenced: Bool, +cs: C.State, +fl: C.Fullscreen, on: Bool) -> C.State & C.Fullscreen:
  match fenced:
    case True{}: (cs, fl)
    case False{}: (C.set_enabled(C.reset(cs), on), C.FullOff{})

def ws_cards.found(+got: Maybe<&2, WsCards>, +gen: U32, on: Bool) -> C.State & C.Fullscreen:
  match got:
    case None{}: (C.initial(on), C.FullOff{})
    case Some{+e}:
      match e:
        case WsCards{_, +wanted, +cs, +fl}: ws_cards.fenced(U32.is_eq(wanted, gen), cs, fl, on)

def ws_cards.sidecar(+xs: List<&2, WsCards>, +id: Key.ServerId, +gen: U32, on: Bool) -> C.State & C.Fullscreen:
  ws_cards.found(ws_cards.find(xs, id), gen, on)

# Bundle accessors: the lease rides with the sidecars through the loop so
# every stage and completion sees the same physical owner.
def ws_tickets.empty() -> WsTickets:
  WsTickets{None{}, None{}, None{}, None{}, 1n}

def ws_tickets.pick(slot0: Bool, slot1: Bool, slot2: Bool, +t0: Maybe<&2, Nat>, +t1: Maybe<&2, Nat>, +t2: Maybe<&2, Nat>, +t3: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match slot0:
    case True{}: t0
    case False{}:
      match slot1:
        case True{}: t1
        case False{}:
          match slot2:
            case True{}: t2
            case False{}: t3

def ws_tickets.get(+t: WsTickets, +n: Nat) -> Maybe<&2, Nat>:
  match t:
    case WsTickets{+t0, +t1, +t2, +t3, _}:
      ws_tickets.pick(Nat.is_eq(n, 0n), Nat.is_eq(n, 1n), Nat.is_eq(n, 2n), t0, t1, t2, t3)

def ws_tickets.put(slot0: Bool, slot1: Bool, slot2: Bool, +t0: Maybe<&2, Nat>, +t1: Maybe<&2, Nat>, +t2: Maybe<&2, Nat>, +t3: Maybe<&2, Nat>, +next: Nat, slot: Maybe<&2, Nat>) -> WsTickets:
  match slot0:
    case True{}: WsTickets{slot, t1, t2, t3, next}
    case False{}:
      match slot1:
        case True{}: WsTickets{t0, slot, t2, t3, next}
        case False{}:
          match slot2:
            case True{}: WsTickets{t0, t1, slot, t3, next}
            case False{}: WsTickets{t0, t1, t2, slot, next}

def ws_tickets.set(+t: WsTickets, +n: Nat, slot: Maybe<&2, Nat>) -> WsTickets:
  match t:
    case WsTickets{+t0, +t1, +t2, +t3, +next}:
      ws_tickets.put(Nat.is_eq(n, 0n), Nat.is_eq(n, 1n), Nat.is_eq(n, 2n), t0, t1, t2, t3, next, slot)

def ws_tickets.bump(+t: WsTickets, +ticket: Nat) -> WsTickets:
  match t:
    case WsTickets{+t0, +t1, +t2, +t3, _}:
      WsTickets{t0, t1, t2, t3, Nat.add(ticket, 1n)}

def ws_tickets.mint(+t: WsTickets, +n: Nat) -> WsTickets & Nat:
  match t:
    case WsTickets{_, _, _, _, +next}:
      (ws_tickets.bump(ws_tickets.set(t, n, Some{next}), next), next)

def ws_tickets.clear(+t: WsTickets, +n: Nat) -> WsTickets:
  ws_tickets.set(t, n, None{})

def ws_pend.empty() -> WsPend:
  WsPend{"", 0n, 0n, 0n}

def ws_pend.prepend(+retry: String, +p: WsPend) -> WsPend:
  match p:
    case WsPend{+bytes, +sid, +base, +seq}: WsPend{retry ++ bytes, sid, base, seq}

def ws_pend.bytes(+p: WsPend) -> String:
  match p:
    case WsPend{+bytes, _, _, _}: bytes

def ws_hot.empty() -> WsHot:
  WsHot{False{}, "", 0, None{}, False{}, Nil{}, "", ws_tickets.empty(), ws_pend.empty(), 0n}

def ws_hot.on(+hot: WsHot) -> Bool:
  match hot:
    case WsHot{+on, _, _, _, _, _, _, _, _, _}: on

def ws_hot.warm(+hot: WsHot) -> Bool:
  match hot:
    case WsHot{_, _, _, _, +warm, _, _, _, _, _}: warm

def ws_hot.frame(+hot: WsHot) -> List<&2, V.DrawOp>:
  match hot:
    case WsHot{_, _, _, _, _, +frame, _, _, _, _}: frame

def ws_hot.tickets_of(+hot: WsHot) -> WsTickets:
  match hot:
    case WsHot{_, _, _, _, _, _, _, +reload, _, _}: reload

def ws_hot.pending_of(+hot: WsHot) -> String:
  match hot:
    case WsHot{_, _, _, _, _, _, _, _, +pending, _}: ws_pend.bytes(pending)

def ws_hot.pend_of(+hot: WsHot) -> WsPend:
  match hot:
    case WsHot{_, _, _, _, _, _, _, _, +pending, _}: pending

def ws_hot.hold_of(+hot: WsHot) -> Nat:
  match hot:
    case WsHot{_, _, _, _, _, _, _, _, _, +hold}: hold

def ws_hot.jobs_of(+hot: WsHot) -> Maybe<&2, Chan(HistJob)>:
  match hot:
    case WsHot{_, _, _, +jobs, _, _, _, _, _, _}: jobs

def ws_hot.with_pending(+hot: WsHot, +pending: WsPend) -> WsHot:
  match hot:
    case WsHot{+on, +path, +cap, +jobs, +warm, +frame, +ts, +reload, _, +hold}:
      WsHot{on, path, cap, jobs, warm, frame, ts, reload, pending, hold}

def ws_hot.with_tickets(+hot: WsHot, +reload: WsTickets) -> WsHot:
  match hot:
    case WsHot{+on, +path, +cap, +jobs, +warm, +frame, +ts, _, +pending, +hold}:
      WsHot{on, path, cap, jobs, warm, frame, ts, reload, pending, hold}

def ws_hot.with_hold(+hot: WsHot, +hold: Nat) -> WsHot:
  match hot:
    case WsHot{+on, +path, +cap, +jobs, +warm, +frame, +ts, +reload, +pending, _}:
      WsHot{on, path, cap, jobs, warm, frame, ts, reload, pending, hold}

def ws_hot.hold_raise.on(raise: Bool, +hot: WsHot, +seq: Nat) -> WsHot:
  match raise:
    case True{}: ws_hot.with_hold(hot, seq)
    case False{}: hot

def ws_hot.hold_raise(+hot: WsHot, +seq: Nat) -> WsHot:
  ws_hot.hold_raise.on(Nat.is_gt(seq, ws_hot.hold_of(hot)), hot, seq)

def ws_hot.clear_ticket(+hot: WsHot, +id: Key.ServerId) -> WsHot:
  ws_hot.with_tickets(hot, ws_tickets.clear(ws_hot.tickets_of(hot), ws_id_nat(id)))

def ws_hot.cold(+all: WsCardsAll) -> WsCardsAll:
  match all:
    case WsCardsAll{+parts, +lease, WsHot{+on, +path, +cap, +jobs, _, _, +ts, +reload, +pending, +hold}}:
      WsCardsAll{parts, lease, WsHot{on, path, cap, jobs, False{}, Nil{}, ts, reload, pending, hold}}

def ws_hot.keep(+all: WsCardsAll, +frame: List<&2, V.DrawOp>, warm: Bool) -> WsCardsAll:
  match all:
    case WsCardsAll{+parts, +lease, WsHot{+on, +path, +cap, +jobs, _, _, +ts, +reload, +pending, +hold}}:
      WsCardsAll{parts, lease, WsHot{on, path, cap, jobs, warm, frame, ts, reload, pending, hold}}

def ws_cards_all.empty() -> WsCardsAll:
  WsCardsAll{Nil{}, None{}, ws_hot.empty()}

def ws_cards_all.live(on: Bool, +path: String, +cap: U32, +jobs: Chan(HistJob)) -> WsCardsAll:
  WsCardsAll{Nil{}, None{}, WsHot{on, path, cap, Some{jobs}, False{}, Nil{}, "", ws_tickets.empty(), ws_pend.empty(), 0n}}

def ws_cards_all.hot_set(+all: WsCardsAll, +hot: WsHot) -> WsCardsAll:
  match all:
    case WsCardsAll{+parts, +lease, _}: WsCardsAll{parts, lease, hot}

def ws_hot.path_got(+d: PrefLive.Details) -> String:
  match d:
    case PrefLive.Details{_, _, _, +path, _, _}: path

def ws_hot.path_of(+ctx: PrefLive.Context) -> String:
  ws_hot.path_got(PrefLive.details(ctx))

def ws_cards_all.parts(+all: WsCardsAll) -> List<&2, WsCards>:
  match all:
    case WsCardsAll{+parts, _, _}: parts

def ws_cards_all.lease(+all: WsCardsAll) -> Maybe<&2, WsCardsLease>:
  match all:
    case WsCardsAll{_, +lease, _}: lease

def ws_cards_all.hot(+all: WsCardsAll) -> WsHot:
  match all:
    case WsCardsAll{_, _, +hot}: hot

def ws_cards_all.upsert(+all: WsCardsAll, +e: WsCards) -> WsCardsAll:
  match all:
    case WsCardsAll{+parts, +lease, +hot}: WsCardsAll{ws_cards.upsert(parts, e), lease, hot}

def ws_cards_all.leased(+all: WsCardsAll, +lease: Maybe<&2, WsCardsLease>) -> WsCardsAll:
  match all:
    case WsCardsAll{+parts, _, +hot}: WsCardsAll{parts, lease, hot}

def ws_cards_all.retired(+all: WsCardsAll) -> WsCardsAll:
  match all:
    case WsCardsAll{+parts, _, +hot}: WsCardsAll{parts, None{}, hot}

def ws_cards_all.retired_if(exact: Bool, +all: WsCardsAll) -> WsCardsAll:
  match exact:
    case True{}: ws_cards_all.retired(all)
    case False{}: all

# (B) removed-origin release: the exact worker completed but its part is
# gone, so the captured request releases from the stored sidecar WITHOUT
# payload admission and the global lease retires. C.reject only releases
# on exact match, so wrong completions keep both; only the completing
# origin's own entry is touched, so an old payload can never land on the
# current part. Releasing before slot reuse lets a reused Sid start fresh.
def ws_cards.released_at(+got: Maybe<&2, WsCards>, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String, +parts: List<&2, WsCards>) -> List<&2, WsCards>:
  match got:
    case None{}: parts
    case Some{+e}:
      match e:
        case WsCards{_, +wanted, +cs, +fl}: ws_cards.upsert(parts, WsCards{s, wanted, C.reject(cs, generation, ticket, url), fl})

def ws_cards.released(+parts: List<&2, WsCards>, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String) -> List<&2, WsCards>:
  ws_cards.released_at(ws_cards.find(parts, s), s, generation, ticket, url, parts)

def ws_cards_all.released(+all: WsCardsAll, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String) -> WsCardsAll:
  match all:
    case WsCardsAll{+parts, _, +hot}: WsCardsAll{ws_cards.released(parts, s, generation, ticket, url), None{}, hot}

# (C) fullscreen visibility gate: the Net overlay covers the body while
# open, so hidden underlay rows schedule nothing. The already-running
# worker (if any) keeps its lease until its exact completion; closing the
# overlay resumes staging with freshly visible candidates.
def ws_cards.cands_open(open: Bool, +cands: List<&2, C.Candidate>) -> List<&2, C.Candidate>:
  match open:
    case True{}: Nil{}
    case False{}: cands

# The one spawn gate the stage runs: opt-out, part enable, net state,
# fullscreen visibility, and the global physical lease. A taken lease
# blocks every part (not just the owner) until the exact worker done.
def ws_cards.spawn_ok(on: Bool, +kept: C.State, +net: Sess.NetState, open: Bool, +lease: Maybe<&2, WsCardsLease>) -> Bool:
  on && C.enabled(kept) && ws_cards.net_ok(net) && Bool.not(open) && ws_clease.free(lease)

# ---- per-part session access (existing seams only) --------------------------
# History paths keep the checkpoint read fallback (current session) and
# write no-op for unknown ids; routing only ever addresses live parts.
# Worker completion routes never use this fallback: they match on
# find_part first and drop absent origins before any effect (G1).
def ws_part.st_got(+got: Maybe<&2, W.Part>, +ws: W.Workspace) -> Sess.Session:
  match got:
    case None{}: W.current_session(ws)
    case Some{+p}: W.part_session(p)

def ws_part.st(+ws: W.Workspace, +id: Key.ServerId) -> Sess.Session:
  ws_part.st_got(W.find_part(ws, id), ws)

def ws_part.gen_got(+got: Maybe<&2, W.Part>) -> U32:
  match got:
    case None{}: 0
    case Some{+p}: W.part_gen(p)

def ws_part.gen(+ws: W.Workspace, +id: Key.ServerId) -> U32:
  ws_part.gen_got(W.find_part(ws, id))

def ws_replace.got(+got: Maybe<&2, W.Part>, +ws: W.Workspace, +st: Sess.Session) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}: W.replace_part(ws, W.Part{W.part_id(p), W.part_gen(p), W.part_scope(p), W.clamp_part(st, W.part_id(p))})

def ws_replace(+ws: W.Workspace, +id: Key.ServerId, +st: Sess.Session) -> W.Workspace:
  ws_replace.got(W.find_part(ws, id), ws, st)

# ---- history save -----------------------------------------------------------
# Mirrors Net.live_step.next/save/reload per affected part: append new rows
# for the part endpoint, surface failures as non-persisted diagnostics,
# and reload on endpoint change. The extract client is the pre-step
# client raised to this part's queued hold, and a channel accept moves
# that floor immediately. The shared settings context gates every save
# (G4 settings-before-history).
# Imported archive rows (the drain's claimed IDs) become the next baseline
# instead of being appended again, matching the single-server checkpoint.
def ws_history.notice(+st: Sess.Session, notice: Maybe<&2, String>) -> Sess.Session & Bool:
  match notice:
    case None{}: (st, False{})
    case Some{+msg}:
      (Sess.session_set_client(st, Cl.diagnostic(Sess.session_cl(st), Cl.Error{}, msg)), True{})

# Append failure still surfaces *log*, but must not advance the extract
# baseline: keep live rows and rewind log_seq to the pre-save checkpoint so
# unsaved IDs remain visible to the next extract_new_history.
def ws_history.kept(+st: Sess.Session, failed: Bool, +ckpt: Sess.Session) -> Sess.Session:
  match failed:
    case False{}: st
    case True{}:
      Sess.session_set_client(st, Cl.set_log_seq(Sess.session_cl(st), Cl.log_seq_of(Sess.session_cl(ckpt))))

def ws_history.reloaded(+loaded: Cl.Client, +st: Sess.Session, +ws: W.Workspace, +id: Key.ServerId, failed: Bool) -> W.Workspace & Bool:
  +st2 = Sess.session_set_client(st, loaded)
  +ws2 = ws_replace(ws, id, st2)
  (ws2, failed)

def ws_history.saved(+st: Sess.Session, failed: Bool, +ws: W.Workspace, +id: Key.ServerId, +path: String, +new_ep: String, +cap: U32, changed: Bool) -> IO(W.Workspace & Bool):
  match changed:
    case False{}:
      +ws2 = ws_replace(ws, id, st)
      IO.pure(W.Workspace & Bool, (ws2, failed))
    case True{}:
      do IO<W.Workspace & Bool>:
        loaded : Cl.Client <- HistIO.history_load_client(path, new_ep, cap, Sess.session_cl(st))
        return ws_history.reloaded(loaded, st, ws, id, failed)

def ws_history.got(pair: Sess.Session & Bool, +ckpt: Sess.Session, +ws: W.Workspace, +id: Key.ServerId, +path: String, +old_ep: String, +new_ep: String, +cap: U32, allowed: Bool) -> IO(W.Workspace & Bool):
  match pair:
    case (+st, +failed):
      ws_history.saved(ws_history.kept(st, failed, ckpt), failed, ws, id, path, new_ep, cap, allowed && Bool.not(String.eq(old_ep, new_ep)))

# seq 0 jobs (overflow coalesce, shutdown drain) must not wake the loop:
# a spurious ack would be observed ahead of WsHistDone.
def hist_worker.ack(send: Bool, +main: Chan(WsMsg), +sid: Nat, +seq: Nat) -> IO(Unit):
  match send:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsHistAck{sid, seq})
        return Unit{}

# Only Ok advances the durable ack claim. Skip is no bytes written (no ack);
# Err surfaces *log* via Diag and retries through on_fail.
def hist_worker.claim(got: HistIO.Append, +main: Chan(WsMsg), +sid: Nat, +base: Nat, +seq: Nat, +data: String) -> IO(Unit):
  match got:
    case HistIO.Ok{}: hist_worker.ack(Bool.not(Nat.is_eq(seq, 0n)), main, sid, seq)
    case HistIO.Skip{}: IO.pure(Unit, Unit{})
    case HistIO.Err{+msg}:
      do IO<Unit>:
        _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsHistDiag{msg, sid, base, seq, data})
        return Unit{}

def hist_worker.done(+main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsHistDone{})
    return Unit{}

def hist_worker.got(job: HistJob, +main: Chan(WsMsg), k: Unit -> IO(Unit)) -> IO(Unit):
  match job:
    case HistStop{}: hist_worker.done(main)
    case HistBarrier{+ack}:
      do IO<Unit>:
        _ : Result<&1, &1, Unit, Unit> <- Chan.send(Unit, ack, Unit{})
        k(Unit{})
    case HistJob{+path, +data, +sid, +base, +seq}:
      do IO<Unit>:
        got : HistIO.Append <- HistIO.history_append_file.claim(path, data)
        Unit <- hist_worker.claim(got, main, sid, base, seq, data)
        k(Unit{})

def hist_worker.recv(g: Maybe<&1, HistJob>, +main: Chan(WsMsg), k: HistJob -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: hist_worker.done(main)
    case Some{+job}: k(job)

@unsafe
def hist_worker(+jobs: Chan(HistJob), +main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, HistJob> <- Chan.recv(HistJob, jobs)
    hist_worker.recv(g, main, job => hist_worker.got(job, main, _ => hist_worker(jobs, main)))

# try_send Ready means the channel owns the bytes; Wait/Fail means not accepted.
def ws_history.enqueue_ready(r: Result<&1, &1, HistJob, Unit>) -> Bool:
  match r:
    case Done{_}: True{}
    case Fail{_}: False{}

def ws_history.enqueue_poll(p: Poll<&1, &1, Result<&1, &1, HistJob, Unit>, HistJob>) -> Bool:
  match p:
    case Ready{r}: ws_history.enqueue_ready(r)
    case Wait{_}: False{}

# Non-blocking offer. True = worker channel accepted the job. False = full,
# closed, or missing channel. Never treat Wait as success: that permanently
# advances the save baseline while discarding the HistJob (BIRC2 gaps).
def ws_history.enqueue(have: Bool, +jobs: Maybe<&2, Chan(HistJob)>, +path: String, +data: String) -> IO(Bool):
  match have:
    case False{}: IO.pure(Bool, True{})
    case True{}:
      match jobs:
        case None{}: IO.pure(Bool, False{})
        case Some{+ch}:
          do IO<Bool>:
            p : Poll<&1, &1, Result<&1, &1, HistJob, Unit>, HistJob> <- Chan.try_send(HistJob, ch, HistJob{path, data, 0n, 0n, 0n}, 0)
            return ws_history.enqueue_poll(p)

# Characterization helper: True means the channel owns the bytes (no sync
# write). False still sync-appends for missing-channel tests only.
def ws_history.write_accepted(accepted: Bool, +path: String, +data: String) -> IO(Maybe<&2, String>):
  match accepted:
    case True{}: IO.pure(Maybe<&2, String>, None{})
    case False{}: HistIO.history_append_file(path, data)

# Overflow stays bounded. Past 64KiB the new bytes are not copied onto the
# UI string; the caller reports a save failure so the live checkpoint retries.
def ws_history.over_cap(+n: Nat) -> Bool:
  Nat.is_gt(n, 65536n)

def ws_history.blob.on(over: Bool, +pending: String, +data: String) -> String:
  match over:
    case True{}: pending
    case False{}: pending ++ data

def ws_history.blob(+pending: String, +data: String) -> String:
  ws_history.blob.on(ws_history.over_cap(Nat.add(String.length(pending), String.length(data))), pending, data)

# Channel accepted the coalesced blob: clear pending. Otherwise hold the
# blob on WsHot — never UI-append while older jobs remain queued.
def ws_history.write_held(accepted: Bool, +hot: WsHot, +pend: WsPend) -> WsHot:
  match accepted:
    case True{}: ws_hot.with_pending(hot, ws_pend.empty())
    case False{}: ws_hot.with_pending(hot, pend)

# Third component is durable: True only when this call's bytes are already
# in the file (Append Ok). A channel accept is not durable — the worker still
# has to append. The extract client is the pre-step client raised to this
# part's queued hold, and a channel accept moves that floor immediately.
# Skip must not count as durable success.
def ws_history.notice_ok(notice: Maybe<&2, String>) -> Bool:
  match notice:
    case None{}: True{}
    case Some{_}: False{}

def ws_history.write_chan.send(over: Bool, +ch: Chan(HistJob), +hot: WsHot, +path: String, +pend: WsPend) -> IO((Maybe<&2, String> & WsHot) & Bool):
  match over:
    case True{}: IO.pure((Maybe<&2, String> & WsHot) & Bool, ((Some{"history queue full"}, hot), False{}))
    case False{}:
      match pend:
        case WsPend{+bytes, +sid, +base, +seq}:
          do IO<(Maybe<&2, String> & WsHot) & Bool>:
            p : Poll<&1, &1, Result<&1, &1, HistJob, Unit>, HistJob> <- Chan.try_send(HistJob, ch, HistJob{path, bytes, sid, base, seq}, 0)
            return ((None{}, ws_history.write_held(ws_history.enqueue_poll(p), hot, WsPend{bytes, sid, base, seq})), False{})

def ws_history.write_chan.go(empty: Bool, +ch: Chan(HistJob), +hot: WsHot, +path: String, +pend: WsPend) -> IO((Maybe<&2, String> & WsHot) & Bool):
  match empty:
    case True{}: IO.pure((Maybe<&2, String> & WsHot) & Bool, ((None{}, hot), True{}))
    case False{}: ws_history.write_chan.send(ws_history.over_cap(String.length(ws_pend.bytes(pend))), ch, hot, path, pend)

def ws_history.write_chan(+ch: Chan(HistJob), +hot: WsHot, +path: String, +pend: WsPend) -> IO((Maybe<&2, String> & WsHot) & Bool):
  ws_history.write_chan.go(String.is_empty(ws_pend.bytes(pend)), ch, hot, path, pend)

def ws_history.write_sync.got(+got: HistIO.Append, +hot: WsHot) -> (Maybe<&2, String> & WsHot) & Bool:
  ((HistIO.append_notice(got), hot), HistIO.append_ok(got))

def ws_history.write_sync.go(empty: Bool, +path: String, +data: String, +hot: WsHot) -> IO((Maybe<&2, String> & WsHot) & Bool):
  match empty:
    case True{}: IO.pure((Maybe<&2, String> & WsHot) & Bool, ((None{}, hot), True{}))
    case False{}:
      do IO<(Maybe<&2, String> & WsHot) & Bool>:
        got : HistIO.Append <- HistIO.history_append_file.claim(path, data)
        return ws_history.write_sync.got(got, hot)

def ws_history.write_sync(+path: String, +data: String, +hot: WsHot) -> IO((Maybe<&2, String> & WsHot) & Bool):
  ws_history.write_sync.go(String.is_empty(data), path, data, hot)

def ws_pend.seq(gt: Bool, +cur: Nat, +seq: Nat) -> Nat:
  match gt:
    case True{}: seq
    case False{}: cur

def ws_pend.offer.go(fresh: Bool, same: Bool, +bytes: String, +osid: Nat, +obase: Nat, +oseq: Nat, +data: String, +sid: Nat, +base: Nat, +seq: Nat) -> WsPend & Bool:
  match fresh:
    case True{}: (WsPend{data, sid, base, seq}, True{})
    case False{}:
      match same:
        case True{}: (WsPend{bytes ++ data, osid, obase, ws_pend.seq(Nat.is_gt(seq, oseq), oseq, seq)}, True{})
        case False{}: (WsPend{bytes, osid, obase, oseq}, False{})

def ws_pend.offer(+p: WsPend, +data: String, +sid: Nat, +base: Nat, +seq: Nat) -> WsPend & Bool:
  match p:
    case WsPend{+bytes, +osid, +obase, +oseq}:
      ws_pend.offer.go(String.is_empty(bytes), Nat.is_eq(osid, sid), bytes, osid, obase, oseq, data, sid, base, seq)

def ws_history.write_mark.send(ok: Bool, +ch: Chan(HistJob), +hot: WsHot, +path: String, +pend: WsPend) -> IO((Maybe<&2, String> & WsHot) & Bool):
  match ok:
    case False{}: IO.pure((Maybe<&2, String> & WsHot) & Bool, ((Some{"history part pending"}, hot), False{}))
    case True{}: ws_history.write_chan(ch, hot, path, pend)

def ws_history.write_mark.got(pair: WsPend & Bool, +ch: Chan(HistJob), +hot: WsHot, +path: String) -> IO((Maybe<&2, String> & WsHot) & Bool):
  match pair:
    case (+pend, +ok): ws_history.write_mark.send(ok, ch, hot, path, pend)

def ws_history.write_mark(+hot: WsHot, +data: String, +sid: Nat, +base: Nat, +seq: Nat) -> IO((Maybe<&2, String> & WsHot) & Bool):
  match hot:
    case WsHot{_, +path, _, +jobs, _, _, _, _, +pending, _}:
      match jobs:
        case None{}: ws_history.write_sync(path, data, hot)
        case Some{+ch}: ws_history.write_mark.got(ws_pend.offer(pending, data, sid, base, seq), ch, hot, path)

def ws_history.write_drop.inner(inner: Maybe<&2, String> & WsHot) -> Maybe<&2, String> & WsHot:
  match inner:
    case (+notice, +hot): (notice, hot)

def ws_history.write_drop(pair: (Maybe<&2, String> & WsHot) & Bool) -> Maybe<&2, String> & WsHot:
  match pair:
    case (inner, _): ws_history.write_drop.inner(inner)

# Prefer channel admission; on overflow coalesce same-path bytes into
# WsHot.pending and retry when capacity returns. Missing channel still
# sync-appends (no older queued owner). Markers stay 0 on this helper;
# async_go uses write_mark so a later ack can advance the baseline.
def ws_history.write(+hot: WsHot, +data: String) -> IO(Maybe<&2, String> & WsHot):
  do IO<Maybe<&2, String> & WsHot>:
    pair : (Maybe<&2, String> & WsHot) & Bool <- ws_history.write_mark(hot, data, 0n, 0n, 0n)
    return ws_history.write_drop(pair)

def ws_history.have_jobs(jobs: Maybe<&2, Chan(HistJob)>) -> Bool:
  match jobs:
    case None{}: False{}
    case Some{_}: True{}

# Blocking flush of pending then HistStop, then close admission. Spawned
# at shutdown so the drain loop can still honor DRAIN_MS.
def ws_history.drain_pending(empty: Bool, +ch: Chan(HistJob), +path: String, +pend: WsPend) -> IO(Unit):
  match empty:
    case True{}: IO.pure(Unit, Unit{})
    case False{}:
      match pend:
        case WsPend{+bytes, +sid, +base, +seq}:
          do IO<Unit>:
            _ : Result<&1, &1, HistJob, Unit> <- Chan.send(HistJob, ch, HistJob{path, bytes, sid, base, seq})
            return Unit{}

def ws_history.drain_stop(+hot: WsHot) -> IO(Unit):
  match hot:
    case WsHot{_, +path, _, +jobs, _, _, _, _, +pending, _}:
      match jobs:
        case None{}: IO.pure(Unit, Unit{})
        case Some{+ch}:
          do IO<Unit>:
            Unit <- ws_history.drain_pending(String.is_empty(ws_pend.bytes(pending)), ch, path, pending)
            _ : Result<&1, &1, HistJob, Unit> <- Chan.send(HistJob, ch, HistStop{})
            Unit <- Chan.close(HistJob, ch)
            return Unit{}

def ws_history.drain_spawn(have: Bool, +hot: WsHot) -> IO(Unit):
  match have:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.spawn(Unit, ws_history.drain_stop(hot))

def ws_history.noted(pair: Sess.Session & Bool, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId) -> W.Workspace & Bool:
  match pair:
    case (+st, +failed): (ws_replace(new_ws, affected, ws_history.kept(st, failed, ckpt)), failed)

def ws_history.async_noted(pair: W.Workspace & Bool, +hot: WsHot) -> W.Workspace & Bool & WsHot:
  match pair:
    case (+ws, failed): (ws, (failed, hot))

# A channel accept is not a failed save. Leave the live log_seq alone so the
# next line keeps a fresh id; `hold` is the extract floor until WsHistAck.
# Rewind only when the append itself failed (a diagnostic notice).
def ws_history.unsaved.none(durable: Bool) -> Bool:
  Bool.and(durable, False{})

def ws_history.unsaved(durable: Bool, notice: Maybe<&2, String>) -> Bool:
  match notice:
    case Some{_}: True{}
    case None{}: ws_history.unsaved.none(durable)

def ws_history.hold_queued(durable: Bool, +hot: WsHot, +seq: Nat) -> WsHot:
  match durable:
    case True{}: hot
    case False{}: ws_hot.hold_raise(hot, seq)

def ws_history.hold_after(durable: Bool, notice: Maybe<&2, String>, +hot: WsHot, +seq: Nat) -> WsHot:
  match notice:
    case Some{_}: ws_hot.with_hold(hot, 0n)
    case None{}: ws_history.hold_queued(durable, hot, seq)

def ws_history.noted_failed(pair: Sess.Session & Bool, failed: Bool) -> Sess.Session & Bool:
  match pair:
    case (+st, _): (st, failed)

def ws_history.async_marked.inner(inner: Maybe<&2, String> & WsHot, +durable: Bool, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +seq: Nat) -> W.Workspace & Bool & WsHot:
  match inner:
    case (+notice, +hot2):
      +hot3 = ws_history.hold_after(durable, notice, hot2, seq)
      marked = ws_history.noted_failed(ws_history.notice(ws_part.st(new_ws, affected), notice), ws_history.unsaved(durable, notice))
      ws_history.async_noted(ws_history.noted(marked, ckpt, new_ws, affected), hot3)

def ws_history.async_marked(pair: (Maybe<&2, String> & WsHot) & Bool, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +seq: Nat) -> W.Workspace & Bool & WsHot:
  match pair:
    case (inner, +durable):
      ws_history.async_marked.inner(inner, durable, ckpt, new_ws, affected, seq)

def ws_history.async_go(queued: Bool, +data: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +hot: WsHot) -> IO(W.Workspace & Bool & WsHot):
  match queued:
    case True{}:
      +seq = Cl.log_seq_of(Sess.session_cl(ws_part.st(new_ws, affected)))
      +base = Cl.log_seq_of(Sess.session_cl(ckpt))
      do IO<W.Workspace & Bool & WsHot>:
        pair : (Maybe<&2, String> & WsHot) & Bool <- ws_history.write_mark(hot, data, ws_id_nat(affected), base, seq)
        return ws_history.async_marked(pair, ckpt, new_ws, affected, seq)
    case False{}:
      match hot:
        case WsHot{_, +path, _, _, _, _, _, _, _, _}:
          do IO<W.Workspace & Bool & WsHot>:
            got : HistIO.Append <- HistIO.history_append_file.claim(path, data)
            return ws_history.async_noted(ws_history.noted(ws_history.notice(ws_part.st(new_ws, affected), HistIO.append_notice(got)), ckpt, new_ws, affected), hot)

def ws_history.reload_nick(+cl: Cl.Client) -> String:
  Cl.nick_of(cl)

def ws_history.reload_host(+cl: Cl.Client) -> String:
  Cl.server_of(cl)

def ws_history.reload_now(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, _, _, +now, _, _, _, _}: now

def ws_history.reload_spawn(load: Bool, +ticket: Nat, +gen: U32, +path: String, +ep: String, +cap: U32, +cl: Cl.Client, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match load:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      Archive.start(ticket, gen, path, ep, cap, ws_history.reload_nick(cl), ws_history.reload_host(cl), ws_history.reload_now(cl), evt)

# A hold from another part's 2^44 id range must not lift this part.
def ws_history.hold_live(inside: Bool, +hold: Nat) -> Nat:
  match inside:
    case True{}: hold
    case False{}: 0n

def ws_history.hold_in(+hold: Nat, +id: Key.ServerId) -> Nat:
  ws_history.hold_live(Bool.not(Nat.is_lt(hold, W.id_base(id))) && Nat.is_lt(hold, W.id_ceiling(id)), hold)

def ws_history.floor_go(lift: Bool, +cl: Cl.Client, +hold: Nat) -> Cl.Client:
  match lift:
    case True{}: Cl.set_log_seq(cl, hold)
    case False{}: cl

def ws_history.floor_cl(+cl: Cl.Client, +hold: Nat) -> Cl.Client:
  ws_history.floor_go(Nat.is_gt(hold, Cl.log_seq_of(cl)), cl, hold)

def ws_history.seq_max.on(gt: Bool, +cur: Nat, +seq: Nat) -> Nat:
  match gt:
    case True{}: seq
    case False{}: cur

def ws_history.seq_max(+cur: Nat, +seq: Nat) -> Nat:
  ws_history.seq_max.on(Nat.is_gt(seq, cur), cur, seq)

def ws_history.rewind_go(rewind: Bool, +cur: Nat, +base: Nat) -> Nat:
  match rewind:
    case True{}: base
    case False{}: cur

def ws_history.rewind_seq(+cur: Nat, +base: Nat) -> Nat:
  ws_history.rewind_go(Bool.not(Nat.is_eq(base, 0n)) && Nat.is_gt(cur, base), cur, base)

def ws_history.hold_clear.on(keep: Bool, +hot: WsHot) -> WsHot:
  match keep:
    case True{}: hot
    case False{}: ws_hot.with_hold(hot, 0n)

def ws_history.hold_clear(+hot: WsHot, +seq: Nat, +id: Key.ServerId) -> WsHot:
  +mine = ws_history.hold_in(ws_hot.hold_of(hot), id)
  ws_history.hold_clear.on(Nat.is_eq(mine, 0n) || Nat.is_gt(mine, seq), hot)

def ws_history.on_ack(+ws: W.Workspace, +id: Key.ServerId, +seq: Nat, +hot: WsHot) -> W.Workspace & WsHot:
  +st = ws_part.st(ws, id)
  +cl = Sess.session_cl(st)
  +cl2 = Cl.set_log_seq(cl, ws_history.seq_max(Cl.log_seq_of(cl), seq))
  (ws_replace(ws, id, Sess.session_set_client(st, cl2)), ws_history.hold_clear(hot, seq, id))

def ws_history.on_fail.rewind(+ws: W.Workspace, +id: Key.ServerId, +base: Nat, +hot: WsHot) -> W.Workspace & WsHot:
  +st = ws_part.st(ws, id)
  +cl = Sess.session_cl(st)
  +cl2 = Cl.set_log_seq(cl, ws_history.rewind_seq(Cl.log_seq_of(cl), base))
  (ws_replace(ws, id, Sess.session_set_client(st, cl2)), ws_hot.with_hold(hot, 0n))

# A newer hold means a later job is already queued above `seq`. Keep that
# floor and prepend the failed blob so the next admission retries it first.
def ws_history.on_fail.go(newer: Bool, +ws: W.Workspace, +id: Key.ServerId, +base: Nat, +retry: String, +hot: WsHot) -> W.Workspace & WsHot:
  match newer:
    case True{}: (ws, ws_hot.with_pending(hot, ws_pend.prepend(retry, ws_hot.pend_of(hot))))
    case False{}: ws_history.on_fail.rewind(ws, id, base, hot)

def ws_history.on_fail(+ws: W.Workspace, +id: Key.ServerId, +base: Nat, +seq: Nat, +retry: String, +hot: WsHot) -> W.Workspace & WsHot:
  ws_history.on_fail.go(Nat.is_gt(ws_history.hold_in(ws_hot.hold_of(hot), id), seq), ws, id, base, retry, hot)

def ws_history.lift_ckpt(+ckpt: Sess.Session, +hold: Nat) -> Sess.Session:
  Sess.session_set_client(ckpt, ws_history.floor_cl(Sess.session_cl(ckpt), hold))

def ws_history.reload_arm.go(pair: WsTickets & Nat, +hot: WsHot) -> WsHot & Nat:
  match pair:
    case (+tickets, +ticket): (ws_hot.with_tickets(hot, tickets), ticket)

def ws_history.reload_arm(load: Bool, +hot: WsHot, +n: Nat) -> WsHot & Nat:
  match load:
    case False{}: (hot, 0n)
    case True{}: ws_history.reload_arm.go(ws_tickets.mint(ws_hot.tickets_of(hot), n), hot)

def ws_history.flush_pending(empty: Bool, +ch: Chan(HistJob), +path: String, +pend: WsPend) -> IO(Bool):
  match empty:
    case True{}: IO.pure(Bool, True{})
    case False{}:
      match pend:
        case WsPend{+bytes, +sid, +base, +seq}:
          do IO<Bool>:
            r : Result<&1, &1, HistJob, Unit> <- Chan.send(HistJob, ch, HistJob{path, bytes, sid, base, seq})
            return ws_history.enqueue_ready(r)

def ws_history.flush_sync_kept(ok: Bool, +hot: WsHot) -> WsHot & Bool:
  match ok:
    case True{}: (ws_hot.with_pending(hot, ws_pend.empty()), True{})
    case False{}: (hot, False{})

def ws_history.flush_sync(empty: Bool, +path: String, +pend: String, +hot: WsHot) -> IO(WsHot & Bool):
  match empty:
    case True{}: IO.pure(WsHot & Bool, (hot, True{}))
    case False{}:
      do IO<WsHot & Bool>:
        got : HistIO.Append <- HistIO.history_append_file.claim(path, pend)
        return ws_history.flush_sync_kept(HistIO.append_ok(got), hot)

def ws_history.flush_chan.kept(ok: Bool, +hot: WsHot) -> WsHot:
  match ok:
    case True{}: ws_hot.with_pending(hot, ws_pend.empty())
    case False{}: hot

def ws_history.fence.got(g: Maybe<&1, Unit>) -> Bool:
  match g:
    case None{}: False{}
    case Some{_}: True{}

def ws_history.fence.wait(sent: Bool, +ack: Chan(Unit)) -> IO(Bool):
  match sent:
    case False{}: IO.pure(Bool, False{})
    case True{}:
      do IO<Bool>:
        g : Maybe<&1, Unit> <- Chan.recv(Unit, ack)
        return ws_history.fence.got(g)

# `+ack` is a copyable parameter, so the worker and this wait can share it.
def ws_history.fence.go(+ack: Chan(Unit), +ch: Chan(HistJob)) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, HistJob, Unit> <- Chan.send(HistJob, ch, HistBarrier{ack})
    ws_history.fence.wait(ws_history.enqueue_ready(r), ack)

def ws_history.fence(+ch: Chan(HistJob)) -> IO(Bool):
  do IO<Bool>:
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    ws_history.fence.go(ack, ch)

def ws_history.flush_chan.done(+ok: Bool, +hot: WsHot) -> WsHot & Bool:
  (ws_history.flush_chan.kept(ok, hot), ok)

def ws_history.flush_chan.fenced(sent: Bool, +ch: Chan(HistJob), +hot: WsHot) -> IO(WsHot & Bool):
  match sent:
    case False{}: IO.pure(WsHot & Bool, (hot, False{}))
    case True{}:
      do IO<WsHot & Bool>:
        ok : Bool <- ws_history.fence(ch)
        return ws_history.flush_chan.done(ok, hot)

def ws_history.flush_chan(+ch: Chan(HistJob), +hot: WsHot, +path: String, +pending: WsPend) -> IO(WsHot & Bool):
  do IO<WsHot & Bool>:
    +sent : Bool <- ws_history.flush_pending(String.is_empty(ws_pend.bytes(pending)), ch, path, pending)
    ws_history.flush_chan.fenced(sent, ch, hot)

# Drain overflow and in-flight jobs before Archive.start. The barrier ack
# means those bytes are durable; the caller then sync-appends the transition.
def ws_history.flush_before(+hot: WsHot) -> IO(WsHot & Bool):
  match hot:
    case WsHot{_, +path, _, +jobs, _, _, _, _, +pending, _}:
      match jobs:
        case None{}: ws_history.flush_sync(String.is_empty(ws_pend.bytes(pending)), path, ws_pend.bytes(pending), hot)
        case Some{+ch}: ws_history.flush_chan(ch, hot, path, pending)

def ws_history.changed_fail(+ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +hot: WsHot) -> W.Workspace & Bool & WsHot:
  ws_history.async_noted(ws_history.noted(ws_history.notice(ws_part.st(new_ws, affected), Some{"history flush failed"}), ckpt, new_ws, affected), hot)

def ws_history.changed_store(pair: WsHot & Nat, notice: Maybe<&2, String>, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId) -> W.Workspace & Bool & WsHot:
  match pair:
    case (+hot, _):
      ws_history.async_noted(ws_history.noted(ws_history.notice(ws_part.st(new_ws, affected), notice), ckpt, new_ws, affected), hot)

# Intentional skip: history disabled or nothing new to write. Empty path with
# nonempty data is not a skip — claim attempts the write and fails closed.
def ws_history.changed_skip(enabled: Bool, +data: String) -> Bool:
  Bool.not(enabled) || String.is_empty(data)

def ws_history.changed_append.armed(pair: WsHot & Nat, notice: Maybe<&2, String>, spawn: Bool, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +path: String, +new_ep: String, +gen: U32, +evt: Chan(Sess.UiMsg), +cl: Cl.Client, +hold0: Nat) -> IO(W.Workspace & Bool & WsHot):
  match pair:
    case (+hot2, +ticket):
      do IO<W.Workspace & Bool & WsHot>:
        Unit <- ws_history.reload_spawn(spawn, ticket, gen, path, new_ep, cap, cl, evt)
        return ws_history.changed_store((hot2, ticket), notice, ws_history.lift_ckpt(ckpt, ws_history.hold_in(hold0, affected)), new_ws, affected)

# Archive reload may proceed on Ok or intentional Skip; only Err blocks it.
# Durable checkpoint advance still uses append_notice (Err → failed rewind).
def ws_history.changed_append.go(+got: HistIO.Append, +load: Bool, +path: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +new_ep: String, +gen: U32, +evt: Chan(Sess.UiMsg), +hot: WsHot, +cl: Cl.Client, +hold0: Nat) -> IO(W.Workspace & Bool & WsHot):
  +spawn = Bool.and(load, Bool.not(HistIO.append_err(got)))
  +notice = HistIO.append_notice(got)
  ws_history.changed_append.armed(ws_history.reload_arm(spawn, ws_hot.with_hold(hot, 0n), ws_id_nat(affected)), notice, spawn, ckpt, new_ws, affected, cap, path, new_ep, gen, evt, cl, hold0)

def ws_history.changed_append(enabled: Bool, +load: Bool, +path: String, +data: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +new_ep: String, +gen: U32, +evt: Chan(Sess.UiMsg), +hot: WsHot, +cl: Cl.Client, +hold0: Nat) -> IO(W.Workspace & Bool & WsHot):
  do IO<W.Workspace & Bool & WsHot>:
    got : HistIO.Append <- HistIO.history_append_file.outcome(ws_history.changed_skip(enabled, data), path, data)
    ws_history.changed_append.go(got, load, path, ckpt, new_ws, affected, cap, new_ep, gen, evt, hot, cl, hold0)

def ws_history.changed_flushed(ok: Bool, enabled: Bool, +load: Bool, +path: String, +data: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +new_ep: String, +gen: U32, +evt: Chan(Sess.UiMsg), +hot: WsHot, +cl: Cl.Client, +hold0: Nat) -> IO(W.Workspace & Bool & WsHot):
  match ok:
    case False{}: IO.pure(W.Workspace & Bool & WsHot, ws_history.changed_fail(ckpt, new_ws, affected, hot))
    case True{}: ws_history.changed_append(enabled, load, path, data, ckpt, new_ws, affected, cap, new_ep, gen, evt, hot, cl, hold0)

# Endpoint change waits until overflow and in-flight appends are durable,
# then sync-appends the transition and only then starts Archive.
def ws_history.changed_async.go(flushed: WsHot & Bool, enabled: Bool, +load: Bool, +path: String, +data: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +new_ep: String, +gen: U32, +evt: Chan(Sess.UiMsg), +cl: Cl.Client, +hold0: Nat) -> IO(W.Workspace & Bool & WsHot):
  match flushed:
    case (+hot1, +ok):
      ws_history.changed_flushed(ok, enabled, load, path, data, ckpt, new_ws, affected, cap, new_ep, gen, evt, hot1, cl, hold0)

def ws_history.changed_async(enabled: Bool, +load: Bool, +path: String, +data: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +new_ep: String, +gen: U32, +evt: Chan(Sess.UiMsg), +hot: WsHot, +cl: Cl.Client) -> IO(W.Workspace & Bool & WsHot):
  +hold0 = ws_hot.hold_of(hot)
  do IO<W.Workspace & Bool & WsHot>:
    flushed : WsHot & Bool <- ws_history.flush_before(hot)
    ws_history.changed_async.go(flushed, enabled, load, path, data, ckpt, new_ws, affected, cap, new_ep, gen, evt, cl, hold0)

def ws_history.changed_sync(+path: String, +data: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +old_ep: String, +new_ep: String, allowed: Bool, enabled: Bool, +hot: WsHot) -> IO(W.Workspace & Bool & WsHot):
  do IO<W.Workspace & Bool & WsHot>:
    got : HistIO.Append <- HistIO.history_append_file.outcome(ws_history.changed_skip(enabled, data), path, data)
    saved : W.Workspace & Bool <- ws_history.got(ws_history.notice(ws_part.st(new_ws, affected), HistIO.append_notice(got)), ckpt, new_ws, affected, path, old_ep, new_ep, cap, allowed)
    return ws_history.async_noted(saved, hot)

def ws_history_save.branch.changed(have: Bool, +path: String, +data: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +old_ep: String, +new_ep: String, allowed: Bool, enabled: Bool, +gen: U32, +evt: Chan(Sess.UiMsg), +hot: WsHot, +cl: Cl.Client) -> IO(W.Workspace & Bool & WsHot):
  match have:
    case True{}:
      ws_history.changed_async(enabled, allowed && Bool.not(String.is_empty(path)) && Cl.settings_history(Cl.get_settings(cl)), path, data, ckpt, new_ws, affected, cap, new_ep, gen, evt, hot, cl)
    case False{}:
      ws_history.changed_sync(path, data, ckpt, new_ws, affected, cap, old_ep, new_ep, allowed, enabled, hot)

def ws_history_save.branch(changed: Bool, +jobs: Maybe<&2, Chan(HistJob)>, +path: String, +data: String, +ckpt: Sess.Session, +new_ws: W.Workspace, +affected: Key.ServerId, +cap: U32, +old_ep: String, +new_ep: String, allowed: Bool, enabled: Bool, +gen: U32, +evt: Chan(Sess.UiMsg), +hot: WsHot, +cl: Cl.Client) -> IO(W.Workspace & Bool & WsHot):
  match changed:
    case True{}:
      ws_history_save.branch.changed(ws_history.have_jobs(jobs), path, data, ckpt, new_ws, affected, cap, old_ep, new_ep, allowed, enabled, gen, evt, hot, cl)
    case False{}: ws_history.async_go(Bool.and(enabled, ws_history.have_jobs(jobs)), data, ckpt, new_ws, affected, hot)

def ws_history_save.go(changed: Bool, +allowed: Bool, +old_st: Sess.Session, +new_st: Sess.Session, +old_ep: String, +new_ep: String, +old_ws: W.Workspace, +new_ws: W.Workspace, +affected: Key.ServerId, +hot: WsHot, +evt: Chan(Sess.UiMsg)) -> IO(W.Workspace & Bool & WsHot):
  match hot:
    case WsHot{_, +path, +cap, +jobs, _, _, _, _, _, _}:
      +old_cl = ws_history.floor_cl(Sess.session_cl(old_st), ws_history.hold_in(ws_hot.hold_of(hot), affected))
      +new_cl = Sess.session_cl(new_st)
      +enabled = allowed && Cl.settings_history(Cl.get_settings(new_cl))
      +data = Hist.extract_new_history_for_except(new_ep, old_cl, new_cl, Hs.hist_live_archived(Sess.session_hist_live(new_st)))
      ws_history_save.branch(changed, jobs, path, data, old_st, new_ws, affected, cap, old_ep, new_ep, allowed, enabled, ws_part.gen(new_ws, affected), evt, hot, new_cl)

def ws_history_save.run(run: Bool, +ctx: PrefLive.Context, +old_ws: W.Workspace, +new_ws: W.Workspace, +affected: Key.ServerId, +hot: WsHot, +evt: Chan(Sess.UiMsg)) -> IO(W.Workspace & Bool & WsHot):
  match run:
    case False{}: IO.pure(W.Workspace & Bool & WsHot, (new_ws, (False{}, hot)))
    case True{}:
      +old_st = ws_part.st(old_ws, affected)
      +new_st = ws_part.st(new_ws, affected)
      +old_ep = Net.session_endpoint(old_st)
      +new_ep = Net.session_endpoint(new_st)
      +allowed = PrefLive.history_allowed(ctx, new_st)
      ws_history_save.go(Bool.not(String.eq(old_ep, new_ep)), allowed, old_st, new_st, old_ep, new_ep, old_ws, new_ws, affected, hot, evt)

def ws_history_save(+ctx: PrefLive.Context, +old_ws: W.Workspace, +new_ws: W.Workspace, +affected: Key.ServerId, +hot: WsHot, +evt: Chan(Sess.UiMsg)) -> IO(W.Workspace & Bool & WsHot):
  +old_st = ws_part.st(old_ws, affected)
  +new_st = ws_part.st(new_ws, affected)
  +same = Bool.and(Nat.is_eq(Cl.log_seq_of(Sess.session_cl(old_st)), Cl.log_seq_of(Sess.session_cl(new_st))), String.eq(Net.session_endpoint(old_st), Net.session_endpoint(new_st)))
  ws_history_save.run(Bool.not(same), ctx, old_ws, new_ws, affected, hot, evt)

# ---- media/upload/preferences stages ----------------------------------------
# Current-part stages mirroring Net.media_stage/upload_stage/
# preferences_stage. Settings change only through keys on the current
# part, and only the current part paints, so observing the current part
# after each step is complete. The media stage additionally honors the
# one global physical image lease (G2).
def ws_media.applied(job: Maybe<&2, M.Request>, clear: Bool, repaint: Bool, +ws2: W.Workspace, ui: T.Ui, +id: Key.ServerId, +gen: U32, +evt: Chan(Sess.UiMsg), +lease: Maybe<&2, WsMedia>) -> IO(T.Ui & W.Workspace & Bool & Maybe<&2, WsMedia>):
  match job:
    case None{}:
      do IO<T.Ui & W.Workspace & Bool & Maybe<&2, WsMedia>>:
        ui2 : T.Ui <- Net.media_stage.effects(clear, None{}, ui, evt)
        return (ui2, ws2, repaint, lease)
    case Some{+req}:
      do IO<T.Ui & W.Workspace & Bool & Maybe<&2, WsMedia>>:
        ui2 : T.Ui <- Net.media_stage.effects(clear, Some{req}, ui, evt)
        return (ui2, ws2, repaint, Some{WsMedia{id, gen, req}})

def ws_media.job(job: Maybe<&2, M.Request>, +media: M.State, +observed: Sess.Session, +old_generation: Nat, +old_after: Nat, ui: T.Ui, +ws: W.Workspace, +id: Key.ServerId, +gen: U32, +evts: WsEvts, +lease: Maybe<&2, WsMedia>) -> IO(T.Ui & W.Workspace & Bool & Maybe<&2, WsMedia>):
  ws_media.applied(job, Bool.not(Nat.is_eq(old_generation, M.generation(media))), Nat.is_gt(Cl.log_seq_of(Sess.session_cl(observed)), old_after), ws_replace(ws, id, Sess.session_set_media(observed, media)), ui, id, gen, ws_evt.id(evts, id), lease)

def ws_media.jobs(pair: M.State & Maybe<&2, M.Request>, +observed: Sess.Session, +old_generation: Nat, +old_after: Nat, ui: T.Ui, +ws: W.Workspace, +id: Key.ServerId, +gen: U32, +evts: WsEvts, +lease: Maybe<&2, WsMedia>) -> IO(T.Ui & W.Workspace & Bool & Maybe<&2, WsMedia>):
  match pair:
    case (+media, job): ws_media.job(job, media, observed, old_generation, old_after, ui, ws, id, gen, evts, lease)

def ws_media_stage(ui: T.Ui, +ws: W.Workspace, +evts: WsEvts, +lease: Maybe<&2, WsMedia>) -> IO(T.Ui & W.Workspace & Bool & Maybe<&2, WsMedia>):
  +id = W.ws_current(ws)
  +st = ws_part.st(ws, id)
  old_generation = M.generation(Sess.session_media(st))
  old_after = Cl.log_seq_of(Sess.session_cl(st))
  +observed = Sess.session_observe_visible_media(st)
  ws_media.jobs(M.take_job_allowed(Sess.session_media_job_allowed(observed) && ws_mlease.free(lease), M.maintain(Sess.session_media(observed), Sess.session_cl(observed))), observed, old_generation, old_after, ui, ws, id, ws_part.gen(ws, id), evts, lease)

def ws_upload.job(job: Maybe<&2, Up.Request>, +st: Sess.Session, +ws: W.Workspace, +id: Key.ServerId, +gen: U32, +evts: WsEvts, +ups: List<&2, WsLease>) -> IO(W.Workspace & List<&2, WsLease>):
  match job:
    case None{}: IO.pure(W.Workspace & List<&2, WsLease>, (ws_replace(ws, id, st), ups))
    case Some{+req}:
      do IO<W.Workspace & List<&2, WsLease>>:
        Unit <- Net.upload_spawn(Some{req}, ws_evt.id(evts, id))
        return (ws_replace(ws, id, st), ws_lease.up_add(ups, id, gen))

def ws_upload.jobs(pair: Sess.Session & Maybe<&2, Up.Request>, +ws: W.Workspace, +id: Key.ServerId, +gen: U32, +evts: WsEvts, +ups: List<&2, WsLease>) -> IO(W.Workspace & List<&2, WsLease>):
  match pair:
    case (+st, job): ws_upload.job(job, st, ws, id, gen, evts, ups)

def ws_upload_stage(+ws: W.Workspace, +evts: WsEvts, +ups: List<&2, WsLease>) -> IO(W.Workspace & List<&2, WsLease>):
  +id = W.ws_current(ws)
  ws_upload.jobs(Sess.session_upload_take(ws_part.st(ws, id)), ws, id, ws_part.gen(ws, id), evts, ups)

# ---- upload consent (F8/present per Net.frame_result owner) ------------------
# Before-key authorizes only a pre-existing presented request (coalesced
# Enter+F8 cannot stage and approve a new public upload); post-completed-frame
# marks presentation only for a Confirm that survived the painted frame.
# Painted part is the pre-step current (OLD current); background parts never
# present without painting. Restore puts back native-cleared typed draft when
# handled Enter was suppressed. Mirrors Net.frame_result.keys/present exactly.
def ws_upload.keyed_at(pair: Sess.Session & Bool, +ws: W.Workspace, +id: Key.ServerId) -> W.Workspace & Bool:
  match pair:
    case (+st, +handled): (ws_replace(ws, id, st), handled)

def ws_upload.keyed(+ws: W.Workspace, +key: U32, +mods: U32) -> W.Workspace & Bool:
  +id = W.ws_current(ws)
  ws_upload.keyed_at(Sess.session_frame_key_admit(ws_part.st(ws, id), key, mods), ws, id)

# Fullscreen-first admission: a fullscreen-consumed key never reaches the
# upload consent step, so Escape with an open overlay closes the overlay
# instead of canceling an active upload. Fallthrough keys admit exactly
# like ws_upload.keyed.
def ws_upload.gated(fs: Bool, +ws: W.Workspace, +key: U32, +mods: U32) -> W.Workspace & Bool:
  match fs:
    case True{}: (ws, False{})
    case False{}: ws_upload.keyed(ws, key, mods)

def ws_upload.presented(+old_ws: W.Workspace, +new_ws: W.Workspace) -> W.Workspace:
  +painted = W.ws_current(old_ws)
  ws_replace(new_ws, painted, Sess.session_frame_key_seal(ws_part.st(old_ws, painted), ws_part.st(new_ws, painted)))

def ws_upload.restored_at(restore: Bool, +ws: W.Workspace, +id: Key.ServerId, +typed: String) -> W.Workspace:
  match restore:
    case False{}: ws
    case True{}: ws_replace(ws, id, Sess.session_upload_draft(ws_part.st(ws, id), typed, 1))

def ws_upload.restored(+ws: W.Workspace, +typed: String, +restore: Bool) -> W.Workspace:
  ws_upload.restored_at(restore, ws, W.ws_current(ws), typed)

# Cards stage: current-part scheduling over the exact negotiated paint
# rows (union C policy) through the ONE global physical lease. Completions
# route back per part; inline rows and the fullscreen overlay paint from
# the same sidecar over the same row set.
def ws_cards.sized(+isc: Cl.Iso, +size: Sess.Size, +cl: Cl.Client, +split: Sp.State, +media: M.State, +painted: List<&2, V.CardEntry>) -> List<&2, C.Candidate>:
  match size:
    case Sess.Size{+rows, +cols}: C.visible_candidates_cards_iso(isc, cl, rows, cols, split, media, painted)

# (A) a spawn takes the global lease with its captured request envelope;
# a quiet stage keeps the lease untouched. Only the exact completion
# releases it, so a second part can never start a second physical helper
# while the first is still owned.
def ws_cards.jobbed(+job: Maybe<&2, C.Request>, +ws: W.Workspace, +id: Key.ServerId, +gen: U32, +next: C.State, +fl: C.Fullscreen, +cards: WsCardsAll, +evts: WsEvts) -> IO(W.Workspace & WsCardsAll):
  match job:
    case None{}: IO.pure(W.Workspace & WsCardsAll, (ws, ws_cards_all.upsert(cards, WsCards{id, gen, next, fl})))
    case Some{+req}:
      do IO<W.Workspace & WsCardsAll>:
        Unit <- CNet.cards_spawn(Some{req}, ws_evt.id(evts, id))
        return (ws, ws_cards_all.leased(ws_cards_all.upsert(cards, WsCards{id, gen, next, fl}), Some{WsCardsLease{id, gen, req}}))

def ws_cards.jobs(pair: C.State & Maybe<&2, C.Request>, +ws: W.Workspace, +id: Key.ServerId, +gen: U32, +fl: C.Fullscreen, +cards: WsCardsAll, +evts: WsEvts) -> IO(W.Workspace & WsCardsAll):
  match pair:
    case (+next, +job): ws_cards.jobbed(job, ws, id, gen, next, fl, cards, evts)

def ws_cards.staged(found: C.State & C.Fullscreen, +ws: W.Workspace, +id: Key.ServerId, +gen: U32, +st: Sess.Session, +cards: WsCardsAll, +evts: WsEvts, on: Bool) -> IO(W.Workspace & WsCardsAll):
  match found:
    case (+cs, +fl):
      +kept = C.maintain(cs, Sess.session_cl(st))
      +full = C.maintain_full(fl, Sess.session_media(st), Sess.session_cl(st))
      +isc = Isupport.as_iso(Sess.session_iso(st))
      +open = C.is_open(full)
      +cands = ws_cards.cands_open(open, ws_cards.sized(isc, Sess.session_size(st), Sess.session_cl(st), Sess.session_split(st), Sess.session_media(st), C.paint_entries(kept)))
      ws_cards.jobs(C.take_job_allowed(ws_cards.spawn_ok(on, kept, Sess.session_net(st), open, ws_cards_all.lease(cards)), C.enqueue_candidates(cands, kept)), ws, id, gen, full, cards, evts)

def ws_cards_stage(+ws: W.Workspace, +evts: WsEvts, +cards: WsCardsAll) -> IO(W.Workspace & WsCardsAll):
  +id = W.ws_current(ws)
  +gen = ws_part.gen(ws, id)
  +on = ws_hot.on(ws_cards_all.hot(cards))
  ws_cards.staged(ws_cards.sidecar(ws_cards_all.parts(cards), id, gen, on), ws, id, gen, W.current_session(ws), cards, evts, on)

# Fullscreen entry/exit binding over the current part's cards sidecar
# (accepted painter dispatch): F9 toggles, Escape closes. Entry opens the
# newest ready alive image; the stored token revalidates on every paint
# and every step. The revalidated state writes back even when the key
# falls through. A handled key is zeroed by the caller before key
# dispatch, so a consumed Escape neither cancels an upload nor quits.
def ws_fullscreen.pick(pick: Maybe<&2, M.MediaReady>, +cs: C.State, +media: M.State) -> C.State & C.Fullscreen & Bool:
  match pick:
    case None{}: (cs, C.FullOff{}, True{})
    case Some{M.MediaReady{+target, +url, _}}: (cs, C.open(media, target, url), True{})

def ws_fullscreen.toggle(open: Bool, +pick: Maybe<&2, M.MediaReady>, +cs: C.State, +fl: C.Fullscreen, +media: M.State) -> C.State & C.Fullscreen & Bool:
  match open:
    case True{}: (cs, C.FullOff{}, True{})
    case False{}: ws_fullscreen.pick(pick, cs, media)

def ws_fullscreen.f9(f9: Bool, +cs: C.State, +fl: C.Fullscreen, +media: M.State, +cl: Cl.Client, +open: Bool) -> C.State & C.Fullscreen & Bool:
  match f9:
    case False{}: (cs, fl, False{})
    case True{}: ws_fullscreen.toggle(open, M.fullscreen_pick(media, cl), cs, fl, media)

def ws_fullscreen.go(esc: Bool, +f9: Bool, +cs: C.State, +fl: C.Fullscreen, +media: M.State, +cl: Cl.Client, +open: Bool) -> C.State & C.Fullscreen & Bool:
  match esc:
    case True{}: (cs, C.FullOff{}, True{})
    case False{}: ws_fullscreen.f9(f9, cs, fl, media, cl, open)

def ws_fullscreen.key(+cs: C.State, +fl: C.Fullscreen, +st: Sess.Session, +key: U32, mods: U32) -> C.State & C.Fullscreen & Bool:
  +cl = Sess.session_cl(st)
  +media = Sess.session_media(st)
  +kept = C.maintain_full(fl, media, cl)
  ws_fullscreen.go(U32.is_eq(key, Sess.KEY_ESCAPE()) && C.is_open(kept),
    U32.is_eq(key, Sess.KEY_F9()) && U32.is_zero(mods), cs, kept, media, cl, C.is_open(kept))

def ws_fullscreen.keyed(found: C.State & C.Fullscreen, +st: Sess.Session, +key: U32, mods: U32) -> C.State & C.Fullscreen & Bool:
  match found:
    case (+cs, +fl): ws_fullscreen.key(cs, fl, st, key, mods)

def ws_fullscreen.applied_go(cs: C.State, rest: C.Fullscreen & Bool, +cards: List<&2, WsCards>, +id: Key.ServerId, +gen: U32, +key: U32) -> List<&2, WsCards> & U32:
  match rest:
    case (+fl, +handled): (ws_cards.upsert(cards, WsCards{id, gen, cs, fl}), Bool.pick(U32, handled, 0, key))

def ws_fullscreen.applied(keyed: C.State & C.Fullscreen & Bool, +cards: List<&2, WsCards>, +id: Key.ServerId, +gen: U32, +key: U32) -> List<&2, WsCards> & U32:
  match keyed:
    case (+cs, rest): ws_fullscreen.applied_go(cs, rest, cards, id, gen, key)

def ws_prefs.started(+ws: W.Workspace, +st: Sess.Session, +id: Key.ServerId, +gen: U32, +ctx1: PrefLive.Context, was_active: Bool, +pevts: Chan(Sess.UiMsg), +owner: Maybe<&2, WsLease>) -> IO(W.Workspace & PrefLive.Context & Maybe<&2, WsLease>):
  do IO<W.Workspace & PrefLive.Context & Maybe<&2, WsLease>>:
    +ctx2 : PrefLive.Context <- PrefLive.start(ctx1, pevts)
    return (ws_replace(ws, id, st), ctx2, ws_lease.prefs_next(owner, was_active, PrefLive.active(ctx2), id, gen))

def ws_prefs.observed(pair: PrefLive.Context & Sess.Session, +ws: W.Workspace, +id: Key.ServerId, +gen: U32, +pevts: Chan(Sess.UiMsg), +owner: Maybe<&2, WsLease>) -> IO(W.Workspace & PrefLive.Context & Maybe<&2, WsLease>):
  match pair:
    case (+ctx1, +st): ws_prefs.started(ws, st, id, gen, ctx1, PrefLive.active(ctx1), pevts, owner)

def ws_prefs_stage(+ws: W.Workspace, +ctx: PrefLive.Context, +pevts: Chan(Sess.UiMsg), +owner: Maybe<&2, WsLease>) -> IO(W.Workspace & PrefLive.Context & Maybe<&2, WsLease>):
  +id = W.ws_current(ws)
  +gen = ws_part.gen(ws, id)
  ws_prefs.observed(PrefLive.observe(ctx, ws_part.st(ws, id), gen), ws, id, gen, pevts, owner)

# Post-step pipeline: history save for the affected part, then the
# current-part media/upload/preferences stages. Returns the repaint flag
# (save failure or media log advance) for continuation scheduling.
# G2: the global image lease passes through untouched. Absent parts and
# slot-generation changes never prune it; only the exact spawned media
# completion retires it. The preferences binding likewise follows its
# active physical job; only upload records prune stale origin bindings.
def ws_post.prefs(got: W.Workspace & PrefLive.Context & Maybe<&2, WsLease>, ui: T.Ui, +media: Maybe<&2, WsMedia>, +ups: List<&2, WsLease>, +cards: WsCardsAll, repaint: Bool) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match got:
    case (+ws, +ctx, owner):
      IO.pure(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool, (ui, ws, ctx, media, ws_prefs.owner(ctx, owner, ws), ws_lease.up_kept(ups, ws), cards, repaint))

def ws_post.carded(got: W.Workspace & WsCardsAll, ui: T.Ui, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, repaint: Bool) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match got:
    case (+ws, +cards):
      do IO<T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool>:
        staged : W.Workspace & PrefLive.Context & Maybe<&2, WsLease> <- ws_prefs_stage(ws, ctx, pevts, owner)
        ws_post.prefs(staged, ui, media, ups, cards, repaint)

def ws_post.uploaded(got: W.Workspace & List<&2, WsLease>, ui: T.Ui, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +cards: WsCardsAll, repaint: Bool) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match got:
    case (+ws, +ups):
      do IO<T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool>:
        staged : W.Workspace & WsCardsAll <- ws_cards_stage(ws, evts, cards)
        ws_post.carded(staged, ui, pevts, ctx, media, owner, ups, repaint)

def ws_post.staged(got: T.Ui & W.Workspace & Bool & Maybe<&2, WsMedia>, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, failed: Bool) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match got:
    case (ui, +ws, mrepaint, media):
      do IO<T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool>:
        staged : W.Workspace & List<&2, WsLease> <- ws_upload_stage(ws, evts, ups)
        ws_post.uploaded(staged, ui, evts, pevts, ctx, media, owner, cards, failed || mrepaint)

def ws_post.saved(got: W.Workspace & Bool, ui: T.Ui, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match got:
    case (+ws, failed):
      do IO<T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool>:
        staged : T.Ui & W.Workspace & Bool & Maybe<&2, WsMedia> <- ws_media_stage(ui, ws, evts, media)
        ws_post.staged(staged, evts, pevts, ctx, owner, ups, cards, failed)

def ws_size_eq(a: Sess.Size, b: Sess.Size) -> Bool:
  match a:
    case Sess.Size{+r1, +c1}:
      match b:
        case Sess.Size{+r2, +c2}: Bool.and(U32.is_eq(r1, r2), U32.is_eq(c1, c2))

def ws_axis_eq(a: Sp.Axis, b: Sp.Axis) -> Bool:
  match a:
    case Sp.SideBySide{}:
      match b:
        case Sp.SideBySide{}: True{}
        case Sp.Stacked{}: False{}
    case Sp.Stacked{}:
      match b:
        case Sp.SideBySide{}: False{}
        case Sp.Stacked{}: True{}

def ws_split_eq(a: Sp.State, b: Sp.State) -> Bool:
  match a:
    case Sp.Off{}:
      match b:
        case Sp.Off{}: True{}
        case Sp.On{_, _, _, _}: False{}
    case Sp.On{+axis, +first, +second, +focus}:
      match b:
        case Sp.Off{}: False{}
        case Sp.On{+axis2, +first2, +second2, +focus2}:
          Bool.and(Bool.and(ws_axis_eq(axis, axis2), String.eq(first, first2)), Bool.and(String.eq(second, second2), U32.is_eq(focus, focus2)))

def ws_view_quiet.cur(same: Bool, +old_ws: W.Workspace, +new_ws: W.Workspace) -> Bool:
  match same:
    case False{}: False{}
    case True{}:
      +id = W.ws_current(new_ws)
      +os = ws_part.st(old_ws, id)
      +ns = ws_part.st(new_ws, id)
      Bool.and(
        Bool.and(ws_size_eq(Sess.session_size(os), Sess.session_size(ns)), Cl.view_same(Sess.session_cl(os), Sess.session_cl(ns))),
        Bool.and(
          Bool.and(List.is_empty(&2, Cl.PendSend, Sess.session_pends(os)), List.is_empty(&2, Cl.PendSend, Sess.session_pends(ns))),
          ws_split_eq(Sess.session_split(os), Sess.session_split(ns))))

def ws_view_quiet(+old_ws: W.Workspace, +new_ws: W.Workspace) -> Bool:
  ws_view_quiet.cur(Key.eq(W.ws_current(old_ws), W.ws_current(new_ws)), old_ws, new_ws)

# Draft keys leave the log, scroll, size, split, and pending sends alone.
# Skip history, image admission, and card admission. Upload consent and
# preference drain still run.
def ws_post_fast.got(staged: W.Workspace & List<&2, WsLease>, ui: T.Ui, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +cards: WsCardsAll) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match staged:
    case (+ws, +ups2): ws_post.carded((ws, cards), ui, pevts, ctx, media, owner, ups2, False{})

def ws_post_fast(ui: T.Ui, +new_ws: W.Workspace, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  do IO<T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool>:
    staged : W.Workspace & List<&2, WsLease> <- ws_upload_stage(new_ws, evts, ups)
    ws_post_fast.got(staged, ui, pevts, ctx, media, owner, cards)

def ws_post.history.rest(rest: Bool & WsHot, +ws: W.Workspace, ui: T.Ui, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match rest:
    case (failed, +hot):
      ws_post.saved((ws, failed), ui, evts, pevts, ctx, media, owner, ups, ws_hot.cold(ws_cards_all.hot_set(cards, hot)))

def ws_post.history(got: W.Workspace & Bool & WsHot, ui: T.Ui, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match got:
    case (+ws, rest):
      ws_post.history.rest(rest, ws, ui, evts, pevts, ctx, media, owner, ups, cards)

def ws_post.skipped(skipped: Bool, ui: T.Ui, +old_ws: W.Workspace, +new_ws: W.Workspace, +affected: Key.ServerId, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match skipped:
    case True{}: ws_post.saved((new_ws, False{}), ui, evts, pevts, ctx, media, owner, ups, ws_hot.cold(cards))
    case False{}:
      do IO<T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool>:
        got : W.Workspace & Bool & WsHot <- ws_history_save(ctx, old_ws, new_ws, affected, ws_cards_all.hot(cards), ws_evt.at(evts, ws_id_nat(affected)))
        ws_post.history(got, ui, evts, pevts, ctx, media, owner, ups, cards)

def ws_post(ui: T.Ui, +old_ws: W.Workspace, +new_ws: W.Workspace, +affected: Key.ServerId, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, skipped: Bool) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  ws_post.skipped(skipped, ui, old_ws, new_ws, affected, evts, pevts, ctx, media, owner, ups, cards)
# ---- inbound dispatch -------------------------------------------------------
# Every actor message flows through W.live_on_msg (framed stamps for Chunk
# come from the addressed part's own session); the resulting outs route to
# the addressed server, the Drop (if any) routes likewise, and the Intent
# (if any) arms a reconnect watch.
def ws_apply.out(+ws2: W.Workspace, +rm: Sid.RoutedMsg, +outs: List<&2, String>, +cmd: Maybe<&2, Sid.RoutedCmd>, +intent: Maybe<&2, Sid.Intent>, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, k: (W.Workspace & U32) -> IO(Unit)) -> IO(Unit):
  match rm:
    case Sid.RoutedMsg{+s, _}:
      do IO<Unit>:
        Unit <- ws_emit_outs(s, outs, cmds, evts)
        Unit <- ws_emit_maybe(cmd, cmds, evts)
        Unit <- ws_schedule(intent, main)
        k((ws2, W.part_bell(ws2, s)))

def ws_apply(+out: W.LiveMsgOut, +rm: Sid.RoutedMsg, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, k: (W.Workspace & U32) -> IO(Unit)) -> IO(Unit):
  match out:
    case W.LiveMsgOut{+ws2, +outs, +cmd, +intent}:
      ws_apply.out(ws2, rm, outs, cmd, intent, main, cmds, evts, k)

def ws_chunk.framed(framed: List<&2, String> & List<&2, U32> & Bool, +ws: W.Workspace, +rm: Sid.RoutedMsg, +now_ms: U32, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, k: (W.Workspace & U32) -> IO(Unit)) -> IO(Unit):
  match framed:
    case (+lines, _, _):
      do IO<Unit>:
        stamps : List<&2, Maybe<&2, String>> <- Clock.line_stamps(lines)
        ws_apply(W.live_on_msg(ws, rm, stamps, now_ms, ts), rm, main, cmds, evts, k)

def ws_chunk.part(+ws: W.Workspace, +rm: Sid.RoutedMsg, +xs: List<&2, U32>, +now_ms: U32, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +got: Maybe<&2, W.Part>, k: (W.Workspace & U32) -> IO(Unit)) -> IO(Unit):
  match got:
    case None{}: ws_apply(W.live_on_msg(ws, rm, Nil{}, now_ms, ts), rm, main, cmds, evts, k)
    case Some{+p}: ws_chunk.framed(Sess.frame_chunk(W.part_session(p), xs), ws, rm, now_ms, ts, main, cmds, evts, k)

def ws_chunk(+ws: W.Workspace, +rm: Sid.RoutedMsg, +s: Key.ServerId, +xs: List<&2, U32>, +now_ms: U32, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, k: (W.Workspace & U32) -> IO(Unit)) -> IO(Unit):
  ws_chunk.part(ws, rm, xs, now_ms, ts, main, cmds, evts, W.find_part(ws, s), k)

def ws_on_net.evt(+ws: W.Workspace, +rm: Sid.RoutedMsg, +s: Key.ServerId, +got: U32, e: Sess.NetEvt, +now_ms: U32, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, k: (W.Workspace & U32) -> IO(Unit)) -> IO(Unit):
  match e:
    case Sess.Chunk{+xs, +req}:
      do IO<Unit>:
        Unit <- Clock.net_trace(2, req, 0)
        ws_chunk(ws, rm, s, xs, now_ms, ts, main, cmds, evts, k)
    case _: ws_apply(W.live_on_msg(ws, rm, Nil{}, now_ms, ts), rm, main, cmds, evts, k)

def ws_on_net.msg(+ws: W.Workspace, +rm: Sid.RoutedMsg, +s: Key.ServerId, m: Sess.UiMsg, +now_ms: U32, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, k: (W.Workspace & U32) -> IO(Unit)) -> IO(Unit):
  match m:
    case Sess.FromNet{+got, e}: ws_on_net.evt(ws, rm, s, got, e, now_ms, ts, main, cmds, evts, k)
    case _: ws_apply(W.live_on_msg(ws, rm, Nil{}, now_ms, ts), rm, main, cmds, evts, k)

def ws_on_net(+ws: W.Workspace, +rm: Sid.RoutedMsg, +now_ms: U32, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, k: (W.Workspace & U32) -> IO(Unit)) -> IO(Unit):
  match rm:
    case Sid.RoutedMsg{+s, m}: ws_on_net.msg(ws, rm, s, m, now_ms, ts, main, cmds, evts, k)

def ws_redial.got(pair: W.Workspace & Maybe<&2, Sid.RoutedCmd>, +cmds: WsCmds, +evts: WsEvts, k: W.Workspace -> IO(Unit)) -> IO(Unit):
  match pair:
    case (+ws2, +mrc):
      do IO<Unit>:
        Unit <- ws_emit_maybe(mrc, cmds, evts)
        k(ws2)

def ws_redial(+ws: W.Workspace, +intent: Sid.Intent, +cmds: WsCmds, +evts: WsEvts, k: W.Workspace -> IO(Unit)) -> IO(Unit):
  ws_redial.got(W.on_redial(ws, intent_server(intent), intent), cmds, evts, k)

# ---- frame --------------------------------------------------------------------
def ws_more_send(+main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsUi{Sess.UiContinue{}})
    return Unit{}

def ws_more.go(enqueue: Bool, +pending: Bool, +main: Chan(WsMsg)) -> IO(Bool):
  match enqueue:
    case True{}:
      do IO<Bool>:
        Unit <- IO.spawn(Unit, ws_more_send(main))
        return pending
    case False{}: IO.pure(Bool, pending)

def ws_more(+scheduled: Bool, +consumed: Bool, +more: Bool, +main: Chan(WsMsg)) -> IO(Bool):
  ws_more.go(more && (Bool.not(scheduled) || consumed), Net.more_pending(scheduled, consumed, more), main)

def ws_mkloop(+ws: W.Workspace, +bell: U32, +scheduled: Bool, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool) -> WsLoop:
  WsLoop{ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun}

def ws_done.posted(got: T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool, +quit: U32, +more: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32, +enter: Bool, +comp: U32, +focus: U32, halt: Bool, +main: Chan(WsMsg), +scheduled: Bool, +consumed: Bool, +bell: U32, +notify: WsNotify, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match got:
    case (ui, +ws, +ctx, media, owner, ups, cards, repaint):
      do IO<Unit>:
        scheduled2 : Bool <- ws_more(scheduled, consumed, more || Net.pol_hot(tab, click, up, dn, hist, enter, comp, focus) || repaint, main)
        k((ui, ws_mkloop(ws, bell, scheduled2, ctx, media, owner, ups, notify, cards, begun), halt || T.flag_on(quit)))

def ws_done.sized(+ws2: W.Workspace, +old: W.Workspace, +rows: U32, +cols: U32) -> W.Workspace:
  ws_upload.presented(old, W.set_current_size(ws2, rows, cols))

def ws_done.post(quiet: Bool, ui: T.Ui, +old: W.Workspace, +next: W.Workspace, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll) -> IO(T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool):
  match quiet:
    case True{}: ws_post_fast(ui, next, evts, pevts, ctx, media, owner, ups, cards)
    case False{}: ws_post(ui, old, next, W.ws_current(next), evts, pevts, ctx, media, owner, ups, cards, False{})

def ws_done(ui: T.Ui, trip: W.Workspace & Sid.RoutedCmd & Bool, +old: W.Workspace, +rows: U32, +cols: U32, +quit: U32, +more: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32, +enter: Bool, +comp: U32, +focus: U32, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +consumed: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match trip:
    case (+ws2, +rc, halt):
      +next = ws_done.sized(ws2, old, rows, cols)
      do IO<Unit>:
        Unit <- ws_emit(rc, cmds, evts)
        Unit <- ws_emit_quit(ws2, rc, cmds, evts)
        Unit <- Net.ack_key(is_key, ack)
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_done.post(ws_view_quiet(old, next), ui, old, next, evts, pevts, ctx, media, owner, ups, cards)
        ws_done.posted(got, quit, more, tab, click, up, dn, hist, enter, comp, focus, halt, main, scheduled, consumed, bell, notify, begun, k)

def ws_keys_halted.ms(+halt: Bool) -> IO(U32):
  match halt:
    case True{}: IO.pure(U32, 0)
    case False{}: Clock.millis()

def ws_keys_halted.go(+loop: WsLoop, +now_ms: U32, +halt: Bool, +rc: Sid.RoutedCmd, ui: T.Ui, +old: W.Workspace, +rows: U32, +cols: U32, +quit: U32, +more: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32, +enter: Bool, +comp: U32, +focus: U32, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws2, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      ws_done(ui, W.live_frame_tick.rc(ws2, rc, halt, now_ms), old, rows, cols, quit, more, tab, click, up, dn, hist, enter, comp, focus, is_key, main, cmds, evts, pevts, ack, scheduled, consumed, bell, ctx, media, owner, ups, notify, cards, begun, k)

def ws_keys_halted(+loop: WsLoop, +halt: Bool, +rc: Sid.RoutedCmd, ui: T.Ui, +old: W.Workspace, +rows: U32, +cols: U32, +quit: U32, +more: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32, +enter: Bool, +comp: U32, +focus: U32, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws2, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      do IO<Unit>:
        now_ms : U32 <- ws_keys_halted.ms(halt)
        ws_keys_halted.go(ws_mkloop(ws2, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), now_ms, halt, rc, ui, old, rows, cols, quit, more, tab, click, up, dn, hist, enter, comp, focus, is_key, main, cmds, evts, pevts, ack, consumed, k)

def ws_keys_ticked.go(trip: W.Workspace & Sid.RoutedCmd & Bool, ui: T.Ui, +old: W.Workspace, +rows: U32, +cols: U32, +quit: U32, +more: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32, +enter: Bool, +comp: U32, +focus: U32, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +consumed: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match trip:
    case (+ws2, +rc, halt): ws_keys_halted(ws_mkloop(ws2, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), halt, rc, ui, old, rows, cols, quit, more, tab, click, up, dn, hist, enter, comp, focus, is_key, main, cmds, evts, pevts, ack, consumed, k)

def ws_keys_done.tripped(trip: W.Workspace & Sid.RoutedCmd & Bool, +typed: String, +restore: Bool) -> W.Workspace & Sid.RoutedCmd & Bool:
  match trip:
    case (+ws2, +rc, halt): (ws_upload.restored(ws2, typed, restore), rc, halt)

def ws_keys_done(+loop: WsLoop, ui: T.Ui, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +tab: U32, +up: U32, +dn: U32, +hist: U32, +quit: U32, +comp: U32, +focus: U32, +more: Bool, +restore: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      ws_keys_ticked.go(ws_keys_done.tripped(W.live_step_keys(ws, Sess.keys_of(typed, enter, tab, click, up, dn, hist, comp, focus)), typed, restore), ui, ws, rows, cols, quit, more, tab, click, up, dn, hist, enter, comp, focus, is_key, main, cmds, evts, pevts, ack, scheduled, consumed, bell, ctx, media, owner, ups, notify, cards, begun, k)

def ws_pol.go(+loop: WsLoop, ui: T.Ui, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +more: Bool, +restore: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, +pol: Sess.KeyPol, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match pol:
        case Sess.KeyPol{+tab, +up, +dn, +hist, +quit, +comp, +focus}:
          ws_keys_done(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, typed, enter, rows, cols, click, tab, up, dn, hist, quit, comp, focus, more, restore, is_key, main, cmds, evts, pevts, ack, consumed, k)

def ws_pol(+loop: WsLoop, ui: T.Ui, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +more: Bool, +restore: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      ws_pol.go(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, typed, enter, rows, cols, click, key, mods, codepoint, wheel, more, restore, is_key, main, cmds, evts, pevts, ack, consumed, Sess.key_pol_for(W.current_session(ws), key, mods, codepoint, wheel, rows), k)

def ws_f7.rc(+ws2: W.Workspace) -> Sid.RoutedCmd:
  Sid.RoutedCmd{W.ws_current(ws2), Sess.Cont{Nil{}}}

def ws_f7.posted(got: T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool, +more: Bool, +moved: Bool, +main: Chan(WsMsg), +scheduled: Bool, +consumed: Bool, +bell: U32, +notify: WsNotify, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match got:
    case (ui, +ws, +ctx, media, owner, ups, cards, repaint):
      do IO<Unit>:
        scheduled2 : Bool <- ws_more(scheduled, consumed, more || moved || repaint, main)
        k((ui, ws_mkloop(ws, bell, scheduled2, ctx, media, owner, ups, notify, cards, begun), False{}))

def ws_f7(+loop: WsLoop, ui: T.Ui, +typed: String, +rows: U32, +cols: U32, +more: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      +sized = W.set_current_size(ws, rows, cols)
      +ws2 = W.cycle_ws(W.cycle_server(sized, typed))
      +moved = W.cycle_moved(W.cycle_server(sized, typed))
      do IO<Unit>:
        Unit <- ws_emit(ws_f7.rc(ws2), cmds, evts)
        Unit <- Net.ack_key(is_key, ack)
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, ws, ws_upload.presented(ws, ws2), W.ws_current(ws2), evts, pevts, ctx, media, owner, ups, cards, False{})
        ws_f7.posted(got, more, moved, main, scheduled, consumed, bell, notify, begun, k)

def ws_act.go(+loop: WsLoop, ui: T.Ui, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +more: Bool, +restore: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, f7: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match f7:
        case True{}: ws_f7(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, typed, rows, cols, more, is_key, main, cmds, evts, pevts, ack, consumed, k)
        case False{}: ws_pol(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, typed, enter, rows, cols, click, key, mods, codepoint, wheel, more, restore, is_key, main, cmds, evts, pevts, ack, consumed, k)

# Upload admission after the single fullscreen decision: the 810
# Enter/key/codepoint suppression, more coalescing, and draft restore
# apply to the post-fullscreen key, and the revalidated sidecar parts
# rejoin their lease for dispatch.
def ws_act.gated(pair: W.Workspace & Bool, ui: T.Ui, +typed: String, +enter_orig: Bool, +rows: U32, +cols: U32, +click: U32, +key2: U32, +mods: U32, +codepoint: U32, +wheel: U32, +more_orig: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +consumed: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +parts2: List<&2, WsCards>, +lease: Maybe<&2, WsCardsLease>, +hot: WsHot, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (+ws_keyed, +handled):
      +enter = enter_orig && Bool.not(handled)
      +key_sup = Bool.pick(U32, handled, 0, key2)
      +code_sup = Bool.pick(U32, handled, 0, codepoint)
      +more = more_orig || handled
      +restore = handled && enter_orig
      ws_act.go(ws_mkloop(ws_keyed, bell, scheduled, ctx, media, owner, ups, notify, WsCardsAll{parts2, lease, hot}, begun), ui, typed, enter, rows, cols, click, key_sup, mods, code_sup, wheel, more, restore, is_key, main, cmds, evts, pevts, ack, consumed, U32.is_eq(key_sup, Sess.KEY_F7()), k)

# Fullscreen pre-step (accepted painter dispatch order): F9/Escape reach
# the current part's sidecar before F7/key dispatch, and a handled key is
# zeroed so it neither cycles, cancels an upload, nor quits. The
# revalidated sidecar writes back on every key.
def ws_act.keyed(applied: List<&2, WsCards> & U32, ui: T.Ui, +ws: W.Workspace, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +more: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +consumed: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +lease: Maybe<&2, WsCardsLease>, +hot: WsHot, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match applied:
    case (+parts2, +key2):
      ws_act.gated(ws_upload.gated(Bool.not(U32.is_eq(key2, key)), ws, key2, mods), ui, typed, enter, rows, cols, click, key2, mods, codepoint, wheel, more, is_key, main, cmds, evts, pevts, ack, scheduled, consumed, bell, ctx, media, owner, ups, notify, parts2, lease, hot, begun, k)

def ws_act.on(+loop: WsLoop, on: Bool, ui: T.Ui, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +more: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      +id = W.ws_current(ws)
      +gen = ws_part.gen(ws, id)
      +lease = ws_cards_all.lease(cards)
      ws_act.keyed(ws_fullscreen.applied(ws_fullscreen.keyed(ws_cards.sidecar(ws_cards_all.parts(cards), id, gen, on), W.current_session(ws), key, mods), ws_cards_all.parts(cards), id, gen, key), ui, ws, typed, enter, rows, cols, click, key, mods, codepoint, wheel, more, is_key, main, cmds, evts, pevts, ack, scheduled, consumed, bell, ctx, media, owner, ups, notify, lease, ws_cards_all.hot(cards), begun, k)

def ws_act(+loop: WsLoop, ui: T.Ui, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +more: Bool, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      ws_act.on(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ws_hot.on(ws_cards_all.hot(cards)), ui, typed, enter, rows, cols, click, key, mods, codepoint, wheel, more, is_key, main, cmds, evts, pevts, ack, consumed, k)

def ws_cmd.pick(+c0: Chan(Sess.NetCmd), +c1: Chan(Sess.NetCmd), +c2: Chan(Sess.NetCmd), +c3: Chan(Sess.NetCmd), +n: Nat) -> Chan(Sess.NetCmd):
  match n:
    case 0n: c0
    case 1n: c1
    case 2n: c2
    case _: c3

def ws_cmd.at(+cmds: WsCmds, +n: Nat) -> Chan(Sess.NetCmd):
  match cmds:
    case WsCmds{+c0, +c1, +c2, +c3}: ws_cmd.pick(c0, c1, c2, c3, n)

# G4: one generation-scoped Begin per live part. ws_start.live sends
# one Begin per part after load, then starts the loop already begun, so
# the frame path must not send another. The first paint and its keys
# still run before settings, archive load, and Begin (ws_start.keyed
# halts before boot). That order stays.
def ws_begin_all.go(+xs: List<&2, W.Part>, +cmds: WsCmds) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{+h, +t}:
      match h:
        case W.Part{+id, +gen, _, _}:
          do IO<Unit>:
            _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, ws_cmd.at(cmds, ws_id_nat(id)), Sess.Begin{gen})
            ws_begin_all.go(t, cmds)

def ws_begin_all(+cmds: WsCmds, +ws: W.Workspace) -> IO(Unit):
  ws_begin_all.go(W.ws_parts(ws), cmds)

# ws_start.live sends one Begin per part after load, then starts the
# loop already begun, so the frame path must not send another. The
# first paint and its keys still run before settings, archive load,
# and Begin (ws_start.keyed halts before boot). That order stays.
def ws_frame.begun_after(acc: T.Ui & WsLoop & Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      match loop:
        case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, _}:
          k((ui, WsLoop{ws, bell, scheduled, ctx, media, owner, ups, notify, cards, True{}}, halt))

def ws_frame.keys(+loop: WsLoop, ui: T.Ui, keys: T.UiKeys, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match keys:
        case T.UiKeys{enter, +typed, +rows, cols, click, +key, +mods, codepoint, wheel, more, +url, +clipboard}:
          do IO<Unit>:
            Unit <- Net.open_clicked(Some{ws_evt.id(evts, W.ws_current(ws))}, url)
            Unit <- Net.frame_clipboard(clipboard, Some{ws_evt.id(evts, W.ws_current(ws))})
            ws_act(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, typed, T.flag_on(enter), rows, cols, click, key, mods, codepoint, wheel, T.flag_on(more), is_key, main, cmds, evts, pevts, ack, consumed, acc => ws_frame.begun_after(acc, k))

def ws_frame(+loop: WsLoop, got: T.Ui & T.UiKeys, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +consumed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match got:
        case (ui, keys): ws_frame.keys(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, keys, is_key, main, cmds, evts, pevts, ack, consumed, k)

def ws_paint.kept(painted: T.Ui & T.UiKeys & List<&2, V.DrawOp> & Bool, +ws: W.Workspace, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +consumed: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match painted:
    case (ui, keys, frame, warm):
      ws_frame(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, ws_hot.keep(cards, frame, warm), begun), (ui, keys), is_key, main, cmds, evts, pevts, ack, consumed, k)

def ws_paint(+ws: W.Workspace, ui: T.Ui, +is_key: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +consumed: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  +hot = ws_cards_all.hot(cards)
  +on = ws_hot.on(hot)
  do IO<Unit>:
    painted : T.Ui & T.UiKeys & List<&2, V.DrawOp> & Bool <- Net.paint_session_cards.hot(ws_hot.warm(hot), ws_hot.frame(hot), ui, W.paint_session(ws, bell), ws_cards.sidecar(ws_cards_all.parts(cards), W.ws_current(ws), ws_part.gen(ws, W.ws_current(ws)), on))
    ws_paint.kept(painted, ws, is_key, main, cmds, evts, pevts, ack, scheduled, consumed, bell, ctx, media, owner, ups, notify, cards, begun, k)
# ---- worker completion routes (G1 origin validation) -------------------------
# Media/upload workers post to their part slot channel, so completions
# arrive routed; the preferences worker posts to the dedicated channel
# and applies to the sole owning part. Every route validates its origin
# (live part plus slot generation) BEFORE any live effects; rejected
# preference completions only retire exact tickets, with no Session or paint.
def ws_drop(+loop: WsLoop, ui: T.Ui, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      k((ui, ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), False{}))

def ws_notify.done_cont(pair: WsNotify & W.Workspace, ui: T.Ui, +bell: U32, +scheduled: Bool, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (+nnot2, +ws2):
      k((ui, ws_mkloop(ws2, bell, scheduled, ctx, media, owner, ups, nnot2, cards, begun), False{}))

def ws_notify.done_loop(+nnot: WsNotify, +ticket: Nat, +endpoint: String, ui: T.Ui, +ws: W.Workspace, +s: Key.ServerId, +evts: WsEvts, +bell: U32, +scheduled: Bool, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    pair : WsNotify & W.Workspace <- ws_notify.done(nnot, ticket, endpoint, ws, s, evts)
    ws_notify.done_cont(pair, ui, bell, scheduled, ctx, media, owner, ups, cards, begun, k)

# M2: the exact worker completed but its origin is gone or stale, so the
# lease retires with no live session effects and no paint.
def ws_media.retired(ui: T.Ui, +ws: W.Workspace, +bell: U32, +scheduled: Bool, +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  k((ui, ws_mkloop(ws, bell, scheduled, ctx, None{}, owner, ups, notify, cards, begun), False{}))

def ws_media.gone(+loop: WsLoop, exact: Bool, ui: T.Ui, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match exact:
        case True{}: ws_media.retired(ui, ws, bell, scheduled, ctx, owner, ups, notify, cards, begun, k)
        case False{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)

def ws_post.painted(got: T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +notify: WsNotify, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match got:
    case (ui, +ws, +ctx, media, owner, ups, cards, _): ws_paint(ws, ui, False{}, main, cmds, evts, pevts, ack, scheduled, False{}, bell, ctx, media, owner, ups, notify, cards, begun, k)

def ws_cards.tokened(+loop: WsLoop, +cs2: C.State, +fl: C.Fullscreen, +s: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      do IO<Unit>:
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, ws, ws, s, evts, pevts, ctx, media, owner, ups, ws_cards_all.upsert(cards, WsCards{s, ws_part.gen(ws, s), cs2, fl}), True{})
        ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_cards.admitted(+loop: WsLoop, accepted: Bool, +s: Key.ServerId, +cs: C.State, +fl: C.Fullscreen, +cl: Cl.Client, +generation: Nat, +ticket: Nat, +url: String, +payload: String, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match accepted:
        case True{}: ws_cards.tokened(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), C.complete(cs, cl, generation, ticket, url, payload), fl, s, ui, main, cmds, evts, pevts, ack, k)
        case False{}: ws_cards.tokened(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), C.reject(cs, generation, ticket, url), fl, s, ui, main, cmds, evts, pevts, ack, k)

# Completion consumes only the stamped client projection of its origin part.
def ws_cards.stamped_cl(+p: W.Part, +ts: String) -> Cl.Client:
  Cl.set_now(Sess.session_cl(W.part_session(p)), ts)

def ws_cards.live(+loop: WsLoop, ok: Bool, found: C.State & C.Fullscreen, ui: T.Ui, +s: Key.ServerId, +cl: Cl.Client, +generation: Nat, +ticket: Nat, +url: String, +payload: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match found:
        case (+cs, +fl):
          ws_cards.admitted(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ok && C.accept(cs, cl, generation, ticket, url), s, cs, fl, cl, generation, ticket, url, payload, ui, main, cmds, evts, pevts, ack, k)

# Handoff: after an exact removed-origin retirement the freed lease must
# stage the current part through the shared ws_cards_stage (same gate the
# live path uses), so a queued visible URL starts without unrelated input.
# No old payload is applied and nothing paints here; the newly spawned
# worker's own completion wakes the loop. Wrong completions never reach
# this path (gone drops them with the lease intact).
def ws_cards.retired_handoff(staged: W.Workspace & WsCardsAll, ui: T.Ui, +bell: U32, +scheduled: Bool, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match staged:
    case (+ws2, +cards2):
      k((ui, ws_mkloop(ws2, bell, scheduled, ctx, media, owner, ups, notify, cards2, begun), False{}))

def ws_cards.retired(+loop: WsLoop, ui: T.Ui, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String, +evts: WsEvts, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      do IO<Unit>:
        staged : W.Workspace & WsCardsAll <- ws_cards_stage(ws, evts, ws_cards_all.released(cards, s, generation, ticket, url))
        ws_cards.retired_handoff(staged, ui, bell, scheduled, ctx, media, owner, ups, notify, begun, k)

# (B) the exact worker completed but its origin is gone, so the lease
# retires and the stored sidecar request releases with no live session
# effects and no paint. A wrong completion keeps everything untouched.
def ws_cards.gone(+loop: WsLoop, exact: Bool, ui: T.Ui, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String, +evts: WsEvts, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match exact:
        case True{}: ws_cards.retired(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, s, generation, ticket, url, evts, k)
        case False{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)

# C2: envelope exactness retires the lease; slot liveness gates effects.
# A completion matching the captured Sid plus generation/ticket/url is the
# exact spawned worker: an absent origin retires it and releases the stored
# sidecar request with no live effects, while a present same-generation
# origin additionally runs the cards admission path. Anything else keeps
# the lease untouched, so a wrong-ticket arrival cannot clear a worker
# C.reject still retains, and a replay after release admits nothing.
def ws_cards.got_on(+on: Bool, +got: Maybe<&2, W.Part>, ui: T.Ui, +ws: W.Workspace, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String, +payload: String, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match got:
    case None{}: ws_cards.gone(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ws_clease.exact(ws_cards_all.lease(cards), s, generation, ticket, url), ui, s, generation, ticket, url, evts, k)
    case Some{+p}:
      +gen = W.part_gen(p)
      +exact = ws_clease.exact(ws_cards_all.lease(cards), s, generation, ticket, url)
      +live = ws_clease.live(ws_cards_all.lease(cards), s, gen)
      +cl = ws_cards.stamped_cl(p, ts)
      ws_cards.live(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, ws_cards_all.retired_if(exact, cards), begun), exact && live, ws_cards.sidecar(ws_cards_all.parts(cards), s, gen, on), ui, s, cl, generation, ticket, url, payload, main, cmds, evts, pevts, ack, k)

def ws_cards.got(+loop: WsLoop, +got: Maybe<&2, W.Part>, ui: T.Ui, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String, +payload: String, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      do IO<Unit>:
        on : Bool <- CNet.cards_enabled()
        ws_cards.got_on(on, got, ui, ws, s, generation, ticket, url, payload, ts, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, notify, cards, begun, k)

def ws_media.tokened(+st: Sess.Session, +ws: W.Workspace, +old: W.Workspace, +id: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, old, ws_replace(ws, id, st), id, evts, pevts, ctx, None{}, owner, ups, cards, False{})
    ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_media.added(pair: T.Ui & U32, +ws: W.Workspace, +old: W.Workspace, +id: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (ui, +token):
      +media = M.complete(Sess.session_media(st), Sess.session_cl(st), generation, ticket, url, token)
      +next = Sess.session_set_media(st, media)
      ws_media.tokened(Bool.pick(Sess.Session, U32.is_zero(token), Sess.session_error(next, "image preview unavailable"), next), ws, old, id, ui, main, cmds, evts, pevts, ack, scheduled, bell, ctx, owner, ups, notify, cards, begun, k)

def ws_media.rejected(+ws: W.Workspace, +id: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  ws_media.tokened(Sess.session_set_media(st, M.reject(Sess.session_media(st), generation, ticket, url)), ws, ws, id, ui, main, cmds, evts, pevts, ack, scheduled, bell, ctx, owner, ups, notify, cards, begun, k)

# Full-budget rejection records a failed identity at the shared media owner,
# so the post-pipeline observe/enqueue/take does not immediately relaunch
# the same automatic helper while all eight native slots stay owned.
def ws_media.rejected_full(+ws: W.Workspace, +id: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  ws_media.tokened(Sess.session_set_media(st, M.reject_full(Sess.session_media(st), Sess.session_cl(st), generation, ticket, url)), ws, ws, id, ui, main, cmds, evts, pevts, ack, scheduled, bell, ctx, owner, ups, notify, cards, begun, k)

# M3: native admission carries every part's retained tokens, not just
# the completing part's, so a B completion cannot free A's owned
# payloads. The completing origin leads. The union is never truncated:
# native holds at most CAP payloads across ALL parts, so when every
# native slot is already owned the completion is rejected instead of
# evicting another part's token.
def ws_media.union_keep(keep: Bool, +st: Sess.Session, +acc: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{}: List.append(&2, U32, acc, M.retained_tokens(Sess.session_media(st)))
    case False{}: acc

def ws_media.union_other(+xs: List<&2, W.Part>, +skip: Key.ServerId, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case Con{+h, +t}:
      match h:
        case W.Part{+id, _, _, +st}:
          ws_media.union_other(t, skip, ws_media.union_keep(Bool.not(Key.eq(id, skip)), st, acc))

# Origin retain is current owners only. Speculative complete(..., 0) +
# List.take would FIFO-drop a live token Bend still owns when ready is
# already CAP nonzero — the hole reject_full was meant to close.
def ws_media.union_tokens(+ws: W.Workspace, +skip: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String) -> List<&2, U32>:
  +origin = M.admit_retained(Sess.session_media(st))
  List.append(&2, U32, origin, ws_media.union_other(W.ws_parts(ws), skip, Nil{}))

def ws_media.union_room(+ws: W.Workspace, +skip: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String) -> Bool:
  Nat.is_lt(List.length(&2, U32, ws_media.union_tokens(ws, skip, st, generation, ticket, url)), M.CAP())

def ws_media_complete.gated(room: Bool, ui: T.Ui, +ws: W.Workspace, +id: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, +payload: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match room:
    case False{}: ws_media.rejected_full(ws, id, st, generation, ticket, url, ui, main, cmds, evts, pevts, ack, scheduled, bell, ctx, owner, ups, notify, cards, begun, k)
    case True{}:
      do IO<Unit>:
        pair : T.Ui & U32 <- T.Timui.media_add(ui, payload, ws_media.union_tokens(ws, id, st, generation, ticket, url))
        ws_media.added(pair, ws, ws, id, st, generation, ticket, url, main, cmds, evts, pevts, ack, scheduled, bell, ctx, owner, ups, notify, cards, begun, k)

# Exact-worker policy decline (accept=false: stale/disabled/full visible cache)
# clears the worker only. Sticky reject_full is reserved for native CAP
# overflow in ws_media_complete.gated — a temporary full visible cache must
# not poison-pill an automatic URL after room returns.
def ws_media_complete(accepted: Bool, ui: T.Ui, +ws: W.Workspace, +id: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, +payload: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match accepted:
    case False{}: ws_media.rejected(ws, id, st, generation, ticket, url, ui, main, cmds, evts, pevts, ack, scheduled, bell, ctx, owner, ups, notify, cards, begun, k)
    case True{}: ws_media_complete.gated(ws_media.union_room(ws, id, st, generation, ticket, url), ui, ws, id, st, generation, ticket, url, payload, main, cmds, evts, pevts, ack, scheduled, bell, ctx, owner, ups, notify, cards, begun, k)

def ws_media.admitted(+loop: WsLoop, admitted: Bool, ui: T.Ui, +s: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, +payload: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match admitted:
        case False{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)
        case True{}: ws_media_complete(Sess.session_accept_media_result(st, generation, ticket, url), ui, ws, s, st, generation, ticket, url, payload, main, cmds, evts, pevts, ack, scheduled, bell, ctx, owner, ups, notify, cards, begun, k)

# M2: envelope exactness retires the lease; slot liveness gates effects.
# A completion matching the captured Sid plus generation/ticket/url is
# the exact spawned worker: absent origins retire it with no live
# effects, while a present same-generation origin additionally runs the
# media admission path. A present stale origin (exact envelope, bumped
# slot generation) retires the lease AND releases the surviving part's
# retained worker, so the stale active request cannot block every
# future take_job. Anything else keeps the lease untouched, so a
# wrong-ticket arrival cannot clear a worker M.reject still retains.
def ws_media.stale_released(+st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String) -> Sess.Session:
  Sess.session_set_media(st, M.reject(Sess.session_media(st), generation, ticket, url))

def ws_media.stale_ws(release: Bool, +ws: W.Workspace, +s: Key.ServerId, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String) -> W.Workspace:
  match release:
    case True{}: ws_replace(ws, s, ws_media.stale_released(st, generation, ticket, url))
    case False{}: ws

def ws_media.got(+loop: WsLoop, +got: Maybe<&2, W.Part>, ui: T.Ui, +s: Key.ServerId, +generation: Nat, +ticket: Nat, +url: String, +payload: String, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match got:
        case None{}: ws_media.gone(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ws_mlease.exact(media, s, generation, ticket, url), ui, k)
        case Some{+p}:
          +st = Sess.session_set_now(W.part_session(p), ts)
          +exact = ws_mlease.exact(media, s, generation, ticket, url)
          +live = ws_mlease.live(media, s, W.part_gen(p))
          +ws2 = ws_media.stale_ws(exact && Bool.not(live), ws, s, st, generation, ticket, url)
          ws_media.admitted(ws_mkloop(ws2, bell, scheduled, ctx, Bool.pick(Maybe<&2, WsMedia>, exact, None{}, media), owner, ups, notify, cards, begun), exact && live, ui, s, st, generation, ticket, url, payload, main, cmds, evts, pevts, ack, k)

def ws_upload.emit(ncmd: Sess.NetCmd, +id: Key.ServerId, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match ncmd:
    case Sess.Cont{+outs}: ws_emit_outs(id, outs, cmds, evts)
    case _: IO.pure(Unit, Unit{})

def ws_upload.sent(+loop: WsLoop, pair: Cl.Client & String & Sess.NetCmd, +old: W.Workspace, +id: Key.ServerId, +st: Sess.Session, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match pair:
        case (+cl, _, ncmd):
          +next = Sess.session_observe_media(Sess.session_set_client(st, cl), Cl.log_seq_of(Sess.session_cl(st)))
          do IO<Unit>:
            Unit <- ws_upload.emit(ncmd, id, cmds, evts)
            got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, old, ws_replace(ws, id, next), id, evts, pevts, ctx, media, owner, ups, cards, False{})
            ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_upload.erred(+loop: WsLoop, +old: W.Workspace, +id: Key.ServerId, +st: Sess.Session, +msg: String, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      do IO<Unit>:
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, old, ws_replace(ws, id, Sess.session_error(st, msg)), id, evts, pevts, ctx, media, owner, ups, cards, False{})
        ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_upload.url(+loop: WsLoop, fits: Bool, +old: W.Workspace, +id: Key.ServerId, +st: Sess.Session, +url: String, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match fits:
        case False{}: ws_upload.erred(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), old, id, st, "upload URL exceeds IRC message limit", ui, main, cmds, evts, pevts, ack, k)
        case True{}: ws_upload.sent(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), Sess.apply_keys_echo(Sess.session_cl(st), Sess.session_net(st), Sess.session_port(st), url, True{}, Sess.session_negotiated(st), Sess.session_echo_ok(st)), old, id, st, ui, main, cmds, evts, pevts, ack, k)

def ws_upload.completed(+loop: WsLoop, pair: Sess.Session & Maybe<&2, String>, +old: W.Workspace, +id: Key.ServerId, +request: Up.Request, +allowed: Bool, +error: U32, +http_status: U32, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match pair:
        case (+st, result):
          match result:
            case Some{+url}: ws_upload.url(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), Up.wire_fits(request, url), old, id, st, url, ui, main, cmds, evts, pevts, ack, k)
            case None{}:
              +msg = Bool.pick(String, Bool.not(allowed), "upload result discarded: canceled or destination changed", Bool.pick(String, U32.is_zero(error), "upload returned an invalid URL", UploadIO.error_text(error, http_status)))
              ws_upload.erred(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), old, id, st, msg, ui, main, cmds, evts, pevts, ack, k)

def ws_upload_complete(+loop: WsLoop, owned: Bool, ui: T.Ui, +id: Key.ServerId, +st: Sess.Session, +request: Up.Request, +result: String, +error: U32, +http_status: U32, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match owned:
        case False{}: ws_upload.erred(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ws_lease.up_drop(ups, id), notify, cards, begun), ws, id, st, "upload result discarded: canceled or destination changed", ui, main, cmds, evts, pevts, ack, k)
        case True{}:
          ws_upload.completed(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ws_lease.up_drop(ups, id), notify, cards, begun), Sess.session_upload_complete(st, request, result), ws, id, request, Up.eligible(Sess.session_upload(st), request, Sess.session_upload_scope(st), Sess.session_upload_online(st)), error, http_status, ui, main, cmds, evts, pevts, ack, k)

def ws_upload.admitted(+loop: WsLoop, admitted: Bool, ui: T.Ui, +s: Key.ServerId, +st: Sess.Session, +request: Up.Request, +result: String, +error: U32, +http_status: U32, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match admitted:
        case False{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)
        case True{}: ws_upload_complete(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), Net.upload_owned(Sess.session_upload(st), request), ui, s, st, request, result, error, http_status, main, cmds, evts, pevts, ack, k)

def ws_upload.got(+loop: WsLoop, +got: Maybe<&2, W.Part>, ui: T.Ui, +s: Key.ServerId, +request: Up.Request, +result: String, +error: U32, +http_status: U32, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match got:
        case None{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)
        case Some{+p}:
          +admitted = ws_lease.up_has(ups, s, W.part_gen(p))
          +st = Sess.session_set_now(W.part_session(p), ts)
          ws_upload.admitted(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), admitted, ui, s, st, request, result, error, http_status, main, cmds, evts, pevts, ack, k)

def ws_prefs.result(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool, +ws: W.Workspace, +old: W.Workspace, +id: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match result:
    case (+pctx, +st, outs, _):
      +owner2 = Bool.pick(Maybe<&2, WsLease>, PrefLive.busy(pctx), owner, None{})
      do IO<Unit>:
        Unit <- ws_emit_outs(id, outs, cmds, evts)
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, old, ws_replace(ws, id, st), id, evts, pevts, pctx, media, owner2, ups, cards, False{})
        ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_prefs.rejected(m: Sess.UiMsg, ctx: PrefLive.Context, owner: Maybe<&2, WsLease>) -> PrefLive.Context & Maybe<&2, WsLease>:
  +next = PrefLive.retire(ctx, m)
  (next, Bool.pick(Maybe<&2, WsLease>, PrefLive.active(next), owner, None{}))

def ws_prefs.reject(result: PrefLive.Context & Maybe<&2, WsLease>, ui: T.Ui, +ws: W.Workspace, +bell: U32, +scheduled: Bool, +media: Maybe<&2, WsMedia>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match result:
    case (+ctx, +owner): ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)

def ws_prefs.gen(+loop: WsLoop, current: Bool, m: Sess.UiMsg, ui: T.Ui, +s: Key.ServerId, +st: Sess.Session, +gen: U32, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match current:
        case False{}: ws_prefs.reject(ws_prefs.rejected(m, ctx, owner), ui, ws, bell, scheduled, media, ups, notify, cards, begun, k)
        case True{}:
          match m:
            case Sess.PreferencesLoaded{+ticket, +prefs, +code}: ws_prefs.result(PrefLive.loaded(ctx, st, gen, ticket, prefs, code), ws, ws, s, ui, main, cmds, evts, pevts, ack, scheduled, bell, media, owner, ups, notify, cards, begun, k)
            case Sess.PreferencesSaved{+ticket, +code}: ws_prefs.result(PrefLive.saved(ctx, st, ticket, code), ws, ws, s, ui, main, cmds, evts, pevts, ack, scheduled, bell, media, owner, ups, notify, cards, begun, k)
            case _: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)

def ws_prefs.got(+loop: WsLoop, +got: Maybe<&2, W.Part>, +held: WsLease, m: Sess.UiMsg, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +ts: String, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match got:
        case None{}: ws_prefs.reject(ws_prefs.rejected(m, ctx, owner), ui, ws, bell, scheduled, media, ups, notify, cards, begun, k)
        case Some{+p}:
          match held:
            case WsLease{+s, +wanted}:
              +st = Sess.session_set_now(W.part_session(p), ts)
              +gen = W.part_gen(p)
              ws_prefs.gen(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), U32.is_eq(wanted, gen), m, ui, s, st, gen, main, cmds, evts, pevts, ack, k)

def ws_prefs.owned(+loop: WsLoop, m: Sess.UiMsg, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +ts: String, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match owner:
        case None{}: ws_prefs.reject(ws_prefs.rejected(m, ctx, owner), ui, ws, bell, scheduled, media, ups, notify, cards, begun, k)
        case Some{+held}:
          match held:
            case WsLease{+s, _}: ws_prefs.got(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), W.find_part(ws, s), held, m, ui, main, cmds, evts, pevts, ack, ts, k)

def ws_prefs.msg(+loop: WsLoop, m: Sess.UiMsg, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      do IO<Unit>:
        ts : String <- Clock.stamp()
        ws_prefs.owned(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), m, ui, main, cmds, evts, pevts, ack, ts, k)

def ws_histload.installed(got: PrefLive.Context & Sess.Session, +before: PrefLive.Context, +before_seq: Nat, +ws: W.Workspace, +old: W.Workspace, +id: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match got:
    case (+pctx, +st):
      +accepted = PrefLive.history_accepted(before, pctx)
      +installed = Sess.notify_claims_installed(before_seq, Sess.session_cl(st))
      +ws_new = ws_replace(ws, id, st)
      +nnot2 = ws_notify.seeded(notify, ws_new, id, accepted, installed)
      do IO<Unit>:
        staged : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, old, ws_new, id, evts, pevts, pctx, media, owner, ups, ws_cards_all.hot_set(cards, ws_hot.clear_ticket(ws_cards_all.hot(cards), id)), True{})
        ws_post.painted(staged, main, cmds, evts, pevts, ack, scheduled, bell, nnot2, begun, k)

def ws_histload.reload_match(pending: Maybe<&2, Nat>, +ticket: Nat, +gen: U32, +got_gen: U32, +ep: String, +cur: String) -> Bool:
  match pending:
    case None{}: False{}
    case Some{+want}:
      Nat.is_eq(want, ticket) && U32.is_eq(gen, got_gen) && String.eq(ep, cur)

def ws_histload.mid(ok: Bool, +st: Sess.Session, +snapshot: Cl.Client, +snapshot_ep: String, +ws: W.Workspace, +id: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match ok:
    case False{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)
    case True{}:
      # current_ep from Session/Net; snapshot_ep from HistoryLoaded (got).
      +cl2 = PrefLive.history.merge(Sess.session_cl(st), st, snapshot, snapshot_ep)
      +ws_new = ws_replace(ws, id, Sess.session_set_client(st, cl2))
      +cards2 = ws_cards_all.hot_set(cards, ws_hot.clear_ticket(ws_cards_all.hot(cards), id))
      do IO<Unit>:
        staged : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, ws, ws_new, id, evts, pevts, ctx, media, owner, ups, cards2, True{})
        ws_post.painted(staged, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_histload.after(accepted: Bool, got: PrefLive.Context & Sess.Session, +before: PrefLive.Context, +before_seq: Nat, +st: Sess.Session, +snapshot: Cl.Client, +ticket: Nat, +got_gen: U32, +ep: String, +gen: U32, +ws: W.Workspace, +id: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match accepted:
    case True{}:
      ws_histload.installed(got, before, before_seq, ws, ws, id, ui, main, cmds, evts, pevts, ack, scheduled, bell, media, owner, ups, notify, cards, begun, k)
    case False{}:
      match got:
        case (+pctx, _):
          ws_histload.mid(ws_histload.reload_match(ws_tickets.get(ws_hot.tickets_of(ws_cards_all.hot(cards)), ws_id_nat(id)), ticket, gen, got_gen, ep, Net.session_endpoint(st)), st, snapshot, ep, ws, id, ui, main, cmds, evts, pevts, ack, scheduled, bell, pctx, media, owner, ups, notify, cards, begun, k)

def ws_histload.done(got: PrefLive.Context & Sess.Session, +before: PrefLive.Context, +before_seq: Nat, +st: Sess.Session, +snapshot: Cl.Client, +ticket: Nat, +got_gen: U32, +ep: String, +gen: U32, +ws: W.Workspace, +id: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match got:
    case (+pctx, _):
      ws_histload.after(PrefLive.history_accepted(before, pctx), got, before, before_seq, st, snapshot, ticket, got_gen, ep, gen, ws, id, ui, main, cmds, evts, pevts, ack, scheduled, bell, media, owner, ups, notify, cards, begun, k)

def ws_histload.got(+loop: WsLoop, +got: Maybe<&2, W.Part>, ui: T.Ui, +s: Key.ServerId, +ticket: Nat, +got_gen: U32, +ep: String, +snapshot: Cl.Client, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match got:
        case None{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)
        case Some{+p}:
          +st = Sess.session_set_now(W.part_session(p), ts)
          +before_seq = Cl.log_seq_of(Sess.session_cl(st))
          +gen = W.part_gen(p)
          # Distinct sources: session/Net current vs HistoryLoaded snapshot claim.
          +snapshot_ep = ep
          do IO<Unit>:
            installed : PrefLive.Context & Sess.Session <- PrefLive.history(ctx, st, gen, got_gen, ticket, snapshot_ep, snapshot, ws_cmd.at(cmds, ws_id_nat(s)))
            ws_histload.done(installed, ctx, before_seq, st, snapshot, ticket, got_gen, snapshot_ep, gen, ws, s, ui, main, cmds, evts, pevts, ack, scheduled, bell, media, owner, ups, notify, cards, begun, k)

def ws_search.landed(landed: Bool, +ws2: W.Workspace, +ws: W.Workspace, +s: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match landed:
    case False{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)
    case True{}:
      do IO<Unit>:
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, ws, ws2, s, evts, pevts, ctx, media, owner, ups, cards, False{})
        ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_search.done(+loop: WsLoop, pair: W.Workspace & Bool, +s: Key.ServerId, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match pair:
        case (+ws2, +landed): ws_search.landed(landed, ws2, ws, s, ui, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, notify, cards, begun, k)

def ws_search.got(+loop: WsLoop, +got: Maybe<&2, W.Part>, ui: T.Ui, +s: Key.ServerId, +ticket: Nat, +hgen: Nat, +wgen: U32, +endpoint: String, +orig: String, +result: Hs.DiskResult, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match got:
        case None{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)
        case Some{_}: ws_search.done(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), W.on_search_done(ws, s, ticket, hgen, wgen, endpoint, orig, result), s, ui, main, cmds, evts, pevts, ack, k)

def ws_routed_error.got(+loop: WsLoop, +got: Maybe<&2, W.Part>, ui: T.Ui, +s: Key.ServerId, +msg: String, +ts: String, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match got:
        case None{}: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)
        case Some{+p}:
          do IO<Unit>:
            got2 : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, ws, ws_replace(ws, s, Sess.session_error(Sess.session_set_now(W.part_session(p), ts), msg)), s, evts, pevts, ctx, media, owner, ups, cards, False{})
            ws_post.painted(got2, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)
# ---- dispatch ---------------------------------------------------------------
def ws_paint.ui_erred(got: T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +notify: WsNotify, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match got:
    case (ui, +ws, +ctx, media, owner, ups, cards, _): ws_paint(ws, ui, False{}, main, cmds, evts, pevts, ack, scheduled, False{}, bell, ctx, media, owner, ups, notify, cards, begun, k)

def ws_paint.ui_err(+loop: WsLoop, +msg: String, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      +id = W.ws_current(ws)
      do IO<Unit>:
        ts : String <- Clock.stamp()
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, ws, ws_replace(ws, id, Sess.session_error(Sess.session_set_now(ws_part.st(ws, id), ts), msg)), id, evts, pevts, ctx, media, owner, ups, cards, False{})
        ws_paint.ui_erred(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_hist_ack.done(pair: W.Workspace & WsHot, +bell: U32, +scheduled: Bool, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool) -> WsLoop:
  match pair:
    case (+ws, +hot): ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, ws_cards_all.hot_set(cards, hot), begun)

def ws_hist_ack.loop(+loop: WsLoop, +sid: Nat, +seq: Nat) -> WsLoop:
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      ws_hist_ack.done(ws_history.on_ack(ws, Key.ServerId{sid}, seq, ws_cards_all.hot(cards)), bell, scheduled, ctx, media, owner, ups, notify, cards, begun)

# Diagnostic consumes a log_seq id. Put that id back so the failed chat row
# stays above the extract baseline (the *log* line itself is not history).
def ws_hist_diag.client(+cl: Cl.Client, +msg: String) -> Cl.Client:
  +floor = Cl.log_seq_of(cl)
  Cl.set_log_seq(Cl.diagnostic(cl, Cl.Error{}, msg), floor)

def ws_hist_diag.failed(pair: W.Workspace & WsHot, +id: Key.ServerId, +msg: String, +cards: WsCardsAll) -> W.Workspace & WsCardsAll:
  match pair:
    case (+ws, +hot):
      +st = ws_part.st(ws, id)
      +st2 = Sess.session_set_client(st, ws_hist_diag.client(Sess.session_cl(st), msg))
      (ws_replace(ws, id, st2), ws_cards_all.hot_set(cards, hot))

# Append failures land in *log* only (Cl.diagnostic), never a chat Error row.
def ws_hist_diag.go(pair: W.Workspace & WsCardsAll, ui: T.Ui, +ws: W.Workspace, +id: Key.ServerId, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +main: Chan(WsMsg), +cmds: WsCmds, +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +notify: WsNotify, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (+ws2, +cards2):
      do IO<Unit>:
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, ws, ws2, id, evts, pevts, ctx, media, owner, ups, cards2, True{})
        ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_hist_diag(+loop: WsLoop, +msg: String, +sid: Nat, +base: Nat, +seq: Nat, +retry: String, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      +id = ws_id_of(sid)
      ws_hist_diag.go(ws_hist_diag.failed(ws_history.on_fail(ws, id, base, seq, retry, ws_cards_all.hot(cards)), id, msg, cards), ui, ws, id, evts, pevts, ctx, media, owner, ups, main, cmds, ack, scheduled, bell, notify, begun, k)

def ws_paint.ui(+loop: WsLoop, ui: T.Ui, m: Sess.UiMsg, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match m:
        case Sess.UiKey{}: ws_paint(ws, ui, True{}, main, cmds, evts, pevts, ack, scheduled, False{}, bell, ctx, media, owner, ups, notify, cards, begun, k)
        case Sess.UiContinue{}: ws_paint(ws, ui, False{}, main, cmds, evts, pevts, ack, scheduled, True{}, bell, ctx, media, owner, ups, notify, cards, begun, k)
        case Sess.UiError{+msg}: ws_paint.ui_err(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), msg, ui, main, cmds, evts, pevts, ack, k)
        case _: ws_paint(ws, ui, False{}, main, cmds, evts, pevts, ack, scheduled, False{}, bell, ctx, media, owner, ups, notify, cards, begun, k)

# The loop-global bell advances only across routed inbound, by the routed
# part's own alert delta when that part has bell enabled (event-origin
# opt-in, never the focused preference); worker completions, redial, UI,
# and key paths carry it unchanged. Routed inbound also feeds the launcher
# auth bridge: a primary-part success edge notifies once, and a failed
# notification lands as a primary-part diagnostic before the paint.
def ws_net_painted.posted(got: T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +notify: WsNotify, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

def ws_net_painted.coded(+loop: WsLoop, +next: W.Workspace, +after: U32, +code: U32, ui: T.Ui, +s: Key.ServerId, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      +noticed = W.auth_noticed(next, Key.first(), code)
      +after_bell = W.bell_after_on(W.part_bell(ws, s), after, bell, W.part_bell_on(ws, s))
      do IO<Unit>:
        got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, ws, noticed, s, evts, pevts, ctx, media, owner, ups, cards, False{})
        ws_net_painted.posted(got, main, cmds, evts, pevts, ack, scheduled, after_bell, notify, begun, k)

def ws_net_painted.fired(fired: WsNotify & W.Workspace, +after: U32, +code: U32, ui: T.Ui, +ws: W.Workspace, +s: Key.ServerId, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match fired:
    case (+nst2, +next2): ws_net_painted.coded(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, nst2, cards, begun), next2, after, code, ui, s, main, cmds, evts, pevts, ack, k)

# Pre-accept snapshot for the notify fire path: the part session from the
# pre-accept workspace seeds reconnect-fresh floors. A part missing pre
# falls back to post (historical post-only behavior, never a foreign row).
def ws_net_painted.pre_parts(+got: Maybe<&2, W.Part>, +post: List<&2, W.Part>) -> List<&2, W.Part>:
  match got:
    case None{}: post
    case Some{+p}: [p]

def ws_net_painted.fire(fire: Bool, +nst: WsNotify, +next: W.Workspace, +s: Key.ServerId, +gen: U32, +pre: Sess.Session, +pst: Sess.Session, ui: T.Ui, +ws: W.Workspace, +after: U32, +code: U32, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match fire:
    case False{}: ws_net_painted.coded(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, nst, cards, begun), next, after, code, ui, s, main, cmds, evts, pevts, ack, k)
    case True{}:
      do IO<Unit>:
        fired : WsNotify & W.Workspace <- ws_notify.fire(nst, next, s, gen, pre, pst, evts)
        ws_net_painted.fired(fired, after, code, ui, ws, s, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, cards, begun, k)

def ws_net_painted.part.cells(+pre: List<&2, W.Part>, +post: List<&2, W.Part>, +after: U32, +code: U32, +nst: WsNotify, +next: W.Workspace, +s: Key.ServerId, ui: T.Ui, +ws: W.Workspace, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match pre:
    case Nil{}: ws_net_painted.coded(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, nst, cards, begun), next, after, code, ui, s, main, cmds, evts, pevts, ack, k)
    case Con{+old, _}:
      match post:
        case Nil{}: ws_net_painted.coded(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, nst, cards, begun), next, after, code, ui, s, main, cmds, evts, pevts, ack, k)
        case Con{+p, _}: ws_net_painted.fire(True{}, nst, next, s, W.part_gen(p), W.part_session(old), W.part_session(p), ui, ws, after, code, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, cards, begun, k)

def ws_net_painted.part.changed(changed: Bool, +post: List<&2, W.Part>, +after: U32, +code: U32, +nst: WsNotify, +next: W.Workspace, +s: Key.ServerId, ui: T.Ui, +ws: W.Workspace, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match changed:
    case False{}: ws_net_painted.coded(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, nst, cards, begun), next, after, code, ui, s, main, cmds, evts, pevts, ack, k)
    case True{}: ws_net_painted.part.cells(ws_net_painted.pre_parts(W.find_part(ws, s), post), post, after, code, nst, next, s, ui, ws, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, cards, begun, k)

def ws_net_painted.part(+got: Maybe<&2, W.Part>, +before: U32, +after: U32, +code: U32, +nst: WsNotify, +next: W.Workspace, +s: Key.ServerId, ui: T.Ui, +ws: W.Workspace, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match got:
    case None{}: ws_net_painted.coded(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, nst, cards, begun), next, after, code, ui, s, main, cmds, evts, pevts, ack, k)
    case Some{+p}: ws_net_painted.part.changed(Bool.not(U32.is_eq(after, before)), [p], after, code, nst, next, s, ui, ws, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, cards, begun, k)

def ws_net_painted(+loop: WsLoop, both: W.Workspace & U32, ui: T.Ui, +s: Key.ServerId, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match both:
        case (+next, +after):
          do IO<Unit>:
            +code : U32 <- AuthBridge.observed(W.auth_edge(ws, next))
            ws_net_painted.part(W.find_part(next, s), W.part_bell(ws, s), after, code, notify, next, s, ui, ws, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, cards, begun, k)

def ws_routed.msg(+loop: WsLoop, +rm: Sid.RoutedMsg, +s: Key.ServerId, m: Sess.UiMsg, ui: T.Ui, +got: Maybe<&2, W.Part>, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +now_ms: U32, +ts: String, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match m:
        case Sess.FromNet{_, _}:
          ws_on_net(ws, rm, now_ms, ts, main, cmds, evts, both => ws_net_painted(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), both, ui, s, main, cmds, evts, pevts, ack, k))
        case Sess.MediaFetched{+generation, +ticket, +url, +payload}:
          ws_media.got(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), got, ui, s, generation, ticket, url, payload, ts, main, cmds, evts, pevts, ack, k)
        case Sess.CardFetched{+generation, +ticket, +url, +payload}:
          ws_cards.got(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), got, ui, s, generation, ticket, url, payload, ts, main, cmds, evts, pevts, ack, k)
        case Sess.UploadFetched{+request, +result, +error, +http_status}:
          ws_upload.got(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), got, ui, s, request, result, error, http_status, ts, main, cmds, evts, pevts, ack, k)
        case Sess.HistoryLoaded{+ticket, +gen, +ep, +snapshot}:
          ws_histload.got(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), got, ui, s, ticket, gen, ep, snapshot, ts, main, cmds, evts, pevts, ack, k)
        case Sess.SearchDone{+ticket, +gen, +wgen, +endpoint, +orig, +result}:
          ws_search.got(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), got, ui, s, ticket, gen, wgen, endpoint, orig, result, main, cmds, evts, pevts, ack, k)
        case Sess.NotifyDone{+ticket, +endpoint}:
          ws_notify.done_loop(notify, ticket, endpoint, ui, ws, s, evts, bell, scheduled, ctx, media, owner, ups, cards, begun, k)
        case Sess.UiError{+msg}: ws_routed_error.got(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), got, ui, s, msg, ts, main, cmds, evts, pevts, ack, k)
        case _: ws_drop(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, k)

# Keep the exact loop owner envelope boxed across both clock effects.
# Ui and the continuation remain outside the Data cell.
def ws_routed.stamped(+saved: List<&2, WsLoop>, +rm: Sid.RoutedMsg, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +now_ms: U32, +ts: String, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match saved:
    case Nil{}:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        T.Sys.exit_fail("birc: missing routed loop state")
    case Con{WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}, _}:
      match rm:
        case Sid.RoutedMsg{+s, m}: ws_routed.msg(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), rm, s, m, ui, W.find_part(ws, s), main, cmds, evts, pevts, ack, now_ms, ts, k)

def ws_routed.wait(+saved: List<&2, WsLoop>, +rm: Sid.RoutedMsg, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    now_ms : U32 <- Clock.millis()
    ts : String <- Clock.stamp()
    ws_routed.stamped(saved, rm, ui, main, cmds, evts, pevts, ack, now_ms, ts, k)

def ws_routed(+rm: Sid.RoutedMsg, +ws: W.Workspace, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  ws_routed.wait([ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun)], rm, ui, main, cmds, evts, pevts, ack, k)

def ws_tick.emit(+outs: List<&2, W.ServerOuts>, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match outs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{W.ServerOuts{+s, +o}, +t}:
      do IO<Unit>:
        Unit <- ws_emit_outs(s, o, cmds, evts)
        ws_tick.emit(t, cmds, evts)

def ws_tick.go(+loop: WsLoop, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), changed: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsLoop{+ws2, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match changed:
        case True{}: ws_paint(ws2, ui, False{}, main, cmds, evts, pevts, ack, scheduled, False{}, bell, ctx, media, owner, ups, notify, ws_hot.cold(cards), begun, k)
        case False{}: k((ui, ws_mkloop(ws2, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), False{}))

def ws_tick.painted(+pair: W.TickOut, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case W.TickOut{+ws2, changed, +outs}:
      do IO<Unit>:
        Unit <- ws_tick.emit(outs, cmds, evts)
        ws_tick.go(ws_mkloop(ws2, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, main, cmds, evts, pevts, ack, changed, k)

def ws_redial.painted(+next: W.Workspace, +old: W.Workspace, +intent: Sid.Intent, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +scheduled: Bool, +bell: U32, +ctx: PrefLive.Context, +media: Maybe<&2, WsMedia>, +owner: Maybe<&2, WsLease>, +ups: List<&2, WsLease>, +notify: WsNotify, +cards: WsCardsAll, +begun: Bool, k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & W.Workspace & PrefLive.Context & Maybe<&2, WsMedia> & Maybe<&2, WsLease> & List<&2, WsLease> & WsCardsAll & Bool <- ws_post(ui, old, next, intent_server(intent), evts, pevts, ctx, media, owner, ups, cards, False{})
    ws_post.painted(got, main, cmds, evts, pevts, ack, scheduled, bell, notify, begun, k)

# ---- shutdown ---------------------------------------------------------------
# G3: close every command channel so each writer flushes and posts
# WriterDone, then run one unified bounded wait over the main channel:
# it collects each present server's fenced acknowledgement AND drains
# the sole preferences owner (exact completion applies clean; deadline
# or elapsed cap bounds the wait). Only the addressed part's current
# generation releases its server; stale or foreign completions keep
# waiting. Preferences outs at shutdown are dropped: registration and
# joins are moot once every command channel is closed.
# Match single-server shutdown: a pending Dial must not delay teardown.
def ws_pending.waiting(wait: Bool, +p: W.Part, +rest: List<&2, Key.ServerId>) -> List<&2, Key.ServerId>:
  match wait:
    case False{}: rest
    case True{}: W.part_id(p) <> rest

def ws_pending.parts(+xs: List<&2, W.Part>) -> List<&2, Key.ServerId>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      ws_pending.waiting(Net.shutdown_waits(Sess.session_net(W.part_session(h))), h, ws_pending.parts(t))

def ws_pending(+ws: W.Workspace) -> List<&2, Key.ServerId>:
  match ws:
    case W.Workspace{+parts, _, _, _}: ws_pending.parts(parts)

def ws_pending.pick(hit: Bool, +h: Key.ServerId, +rest: List<&2, Key.ServerId>) -> List<&2, Key.ServerId>:
  match hit:
    case True{}: rest
    case False{}: h <> rest

def ws_pending.buf(+h: Key.ServerId, +rest: List<&2, Key.ServerId>, +id: Key.ServerId) -> List<&2, Key.ServerId>:
  ws_pending.pick(Key.eq(h, id), h, rest)

def ws_pending.go(+xs: List<&2, Key.ServerId>, +id: Key.ServerId) -> List<&2, Key.ServerId>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}: ws_pending.buf(h, ws_pending.go(t, id), id)

def ws_shutdown.drop(+ws: W.Workspace, +rm: Sid.RoutedMsg, +pending: List<&2, Key.ServerId>, acked: Bool) -> List<&2, Key.ServerId>:
  match acked:
    case False{}: pending
    case True{}: ws_pending.go(pending, rm_server(rm))

def ws_shut.owner_got(+got: Maybe<&2, W.Part>, +held: WsLease, +ws: W.Workspace) -> Key.ServerId:
  match got:
    case None{}: W.ws_current(ws)
    case Some{+p}:
      match held:
        case WsLease{+s, +wanted}: Bool.pick(Key.ServerId, U32.is_eq(W.part_gen(p), wanted), s, W.ws_current(ws))

def ws_shut.owner_id(+owner: Maybe<&2, WsLease>, +ws: W.Workspace) -> Key.ServerId:
  match owner:
    case None{}: W.ws_current(ws)
    case Some{+held}:
      match held:
        case WsLease{+s, _}: ws_shut.owner_got(W.find_part(ws, s), held, ws)

def ws_shut.need.or(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}: True{}
    case False{}: b

# Idle preferences must not leave a history or writer drain parked on main.
# The deadline is forwarded onto main by prefs_fwd and honored in ws_shut.fire.
def ws_shut.need(prefs: Bool, hist: Bool, writers: Bool) -> Bool:
  ws_shut.need.or(prefs, ws_shut.need.or(hist, writers))

def ws_shut.writers(pending: List<&2, Key.ServerId>) -> Bool:
  match pending:
    case Nil{}: False{}
    case Con{_, _}: True{}

def ws_shut.arm.go(busy: Bool, +pevts: Chan(Sess.UiMsg)) -> IO(Unit):
  match busy:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.spawn(Unit, PrefWorker.deadline(0n, pevts))

def ws_shut.arm(+need: Bool, +pevts: Chan(Sess.UiMsg)) -> IO(Unit):
  ws_shut.arm.go(need, pevts)

# Prefs settle is live !busy — never a sticky latch past a later PrefLive.start.
def ws_shut.settle(+ctx: PrefLive.Context) -> Bool:
  Bool.not(PrefLive.busy(ctx))

# Ready only when prefs, history, and writers are all clear (need inverted).
def ws_shut.ready(+done: Bool, +hist: Bool, +writers: Bool) -> Bool:
  Bool.not(ws_shut.need(Bool.not(done), hist, writers))

# Shared settle-gated blame with LoadedPrefs.expired (prefs-only drain uses
# the same helper). Idle quiet; busy still 408-blames.
def ws_shut.expired(+settled: Bool, +st: Sess.Session, +ok: Bool) -> Sess.Session & Bool:
  LoadedPrefs.expired(settled, st, ok)

def ws_shut.fire_state.go(result: Sess.Session & Bool, +ctx: PrefLive.Context, +id: Key.ServerId, +started: U32) -> WsShut:
  match result:
    case (+st2, +ok2): WsShut{Nil{}, ctx, st2, id, None{}, ok2, started, True{}, False{}}

def ws_shut.fire_state(+ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +ok: Bool, +started: U32) -> WsShut:
  ws_shut.fire_state.go(ws_shut.expired(ws_shut.settle(ctx), st, ok), ctx, id, started)

def ws_shut.fire(fire: Bool, ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, +hist: Bool, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match fire:
    case True{}: k((ui, ws_shut.fire_state(ctx, st, id, ok, started)))
    case False{}: k((ui, WsShut{pending, ctx, st, id, owner, ok, started, done, hist}))

def ws_shut.elapsed(+tnow: U32, ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, +hist: Bool, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  +elapsed = U32.sub(tnow, started)
  +fire = Bool.not(U32.is_lt(elapsed, PrefWorker.DRAIN_MS())) && Bool.not(ws_shut.ready(done, hist, ws_shut.writers(pending)))
  ws_shut.fire(fire, ui, pending, ctx, st, id, owner, ok, started, done, hist, k)

def ws_shut.timed(ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, +hist: Bool, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    tnow : U32 <- Clock.millis()
    ws_shut.elapsed(tnow, ui, pending, ctx, st, id, owner, ok, started, done, hist, k)

def ws_shut.applied(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool, +code: U32, ui: T.Ui, +pending: List<&2, Key.ServerId>, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, hist: Bool, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match result:
    case (+pctx, +st, _, _):
      +busy2 = PrefLive.busy(pctx)
      ws_shut.timed(ui, pending, pctx, st, id, Bool.pick(Maybe<&2, WsLease>, busy2, owner, None{}), ok && U32.is_zero(code), started, ws_shut.settle(pctx), hist, k)

def ws_shut.reject.got(result: PrefLive.Context & Maybe<&2, WsLease>, +pending: List<&2, Key.ServerId>, +st: Sess.Session, +id: Key.ServerId, +ok: Bool, +started: U32, +done: Bool, hist: Bool) -> WsShut:
  match result:
    case (+ctx, +owner): WsShut{pending, ctx, st, id, owner, ok && PrefLive.clean(ctx), started, ws_shut.settle(ctx), hist}

def ws_shut.reject(m: Sess.UiMsg, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, hist: Bool) -> WsShut:
  ws_shut.reject.got(ws_prefs.rejected(m, ctx, owner), pending, st, id, ok, started, done, hist)

def ws_shut.rejected(+shut: WsShut, ui: T.Ui, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match shut:
    case WsShut{+pending, +ctx, +st, +id, +owner, +ok, +started, +done, hist}: ws_shut.timed(ui, pending, ctx, st, id, owner, ok, started, done, hist, k)

def ws_shut.deadline_kept(+shut: WsShut) -> Bool:
  match shut:
    case WsShut{_, _, _, _, _, _, _, _, +hist}: hist

# PreferencesDeadline settles prefs only when still busy (!settle). History
# stays until WsHistDone or the shared drain budget in ws_shut.fire; never
# sticky-done past a still-busy PrefLive context, never sticky-blame prefs
# when the arm was only for hist/writers, and never revive ok after a failed
# Loaded/Saved (idle expired keeps the prior ok; busy still blames).
def ws_shut.deadline_state.go(result: Sess.Session & Bool, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +id: Key.ServerId, +started: U32, +settled: Bool, +hist: Bool) -> WsShut:
  match result:
    case (+st2, +ok): WsShut{pending, ctx, st2, id, None{}, ok, started, settled, hist}

def ws_shut.deadline_state(+pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +started: U32, +ok: Bool, +hist: Bool) -> WsShut:
  +settled = ws_shut.settle(ctx)
  ws_shut.deadline_state.go(ws_shut.expired(settled, st, ok), pending, ctx, id, started, settled, hist)

def ws_shut.deadline_go(+shut: WsShut, ui: T.Ui, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match shut:
    case WsShut{+pending, +ctx, +st, +id, +owner, +ok, +started, +done, _}:
      ws_shut.timed(ui, pending, ctx, st, id, owner, ok, started, done, ws_shut.deadline_kept(shut), k)

def ws_shut.prefs_match(current: Bool, m: Sess.UiMsg, ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +gen: U32, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, hist: Bool, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match current:
    case False{}: ws_shut.rejected(ws_shut.reject(m, pending, ctx, st, id, owner, ok, started, done, hist), ui, k)
    case True{}:
      match m:
        case Sess.PreferencesLoaded{+ticket, +prefs, +code}: ws_shut.applied(PrefLive.loaded(ctx, st, gen, ticket, prefs, code), code, ui, pending, id, owner, ok, started, done, hist, k)
        case Sess.PreferencesSaved{+ticket, +code}: ws_shut.applied(PrefLive.saved(ctx, st, ticket, code), code, ui, pending, id, owner, ok, started, done, hist, k)
        case Sess.PreferencesDeadline{_}: ws_shut.deadline_go(ws_shut.deadline_state(pending, ctx, st, id, started, ok, hist), ui, k)
        case _: ws_shut.timed(ui, pending, ctx, st, id, owner, ok, started, done, hist, k)

def ws_shut.prefs_owned(+owner: Maybe<&2, WsLease>, m: Sess.UiMsg, ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +ok: Bool, +started: U32, +done: Bool, hist: Bool, +ws: W.Workspace, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match owner:
    case None{}: ws_shut.rejected(ws_shut.reject(m, pending, ctx, st, id, owner, ok, started, done, hist), ui, k)
    case Some{+held}:
      match held:
        case WsLease{+s, +wanted}:
          +gen = ws_part.gen(ws, id)
          ws_shut.prefs_match(Key.eq(s, id) && U32.is_eq(wanted, gen), m, ui, pending, ctx, st, id, gen, owner, ok, started, done, hist, k)

def ws_shut.msg(wmsg: WsMsg, ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, hist: Bool, +ws: W.Workspace, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match wmsg:
    case WsNet{+rm}: ws_shut.timed(ui, ws_shutdown.drop(ws, rm, pending, W.writer_done_acked(ws, rm)), ctx, st, id, owner, ok, started, done, hist, k)
    case WsPrefs{m}: ws_shut.prefs_owned(owner, m, ui, pending, ctx, st, id, ok, started, done, hist, ws, k)
    case WsHistDone{}: ws_shut.timed(ui, pending, ctx, st, id, owner, ok, started, done, False{}, k)
    case _: ws_shut.timed(ui, pending, ctx, st, id, owner, ok, started, done, hist, k)

def ws_shut.got(g: Maybe<&1, WsMsg>, ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, hist: Bool, +ws: W.Workspace, k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: Net.shutdown_finish(ui, ok)
    case Some{wmsg}: ws_shut.msg(wmsg, ui, pending, ctx, st, id, owner, ok, started, done, hist, ws, k)

def ws_shut.owner(was_active: Bool, +ctx: PrefLive.Context, +owner: Maybe<&2, WsLease>, +id: Key.ServerId, +gen: U32) -> Maybe<&2, WsLease>:
  ws_lease.prefs_next(owner, was_active, PrefLive.active(ctx), id, gen)

def ws_shut.started(was_active: Bool, +ctx2: PrefLive.Context, ui: T.Ui, +pending: List<&2, Key.ServerId>, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, hist: Bool, +ws: W.Workspace, +main: Chan(WsMsg), k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  +owner2 = ws_shut.owner(was_active, ctx2, owner, id, ws_part.gen(ws, id))
  do IO<Unit>:
    g : Maybe<&1, WsMsg> <- Chan.recv(WsMsg, main)
    ws_shut.got(g, ui, pending, ctx2, st, id, owner2, ok, started, ws_shut.settle(ctx2), hist, ws, k)

def ws_shut.step(ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, hist: Bool, +ws: W.Workspace, +main: Chan(WsMsg), +pevts: Chan(Sess.UiMsg), k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    ctx2 : PrefLive.Context <- PrefLive.start(ctx, pevts)
    ws_shut.started(PrefLive.active(ctx), ctx2, ui, pending, st, id, owner, ok, started, done, hist, ws, main, k)

def ws_shut.drained.go(ready: Bool, +done: Bool, +hist: Bool, ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +ws: W.Workspace, +main: Chan(WsMsg), +pevts: Chan(Sess.UiMsg), k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match ready:
    case True{}: Net.shutdown_finish(ui, ok)
    case False{}: ws_shut.step(ui, pending, ctx, st, id, owner, ok, started, done, hist, ws, main, pevts, k)

def ws_shut.drained(+done: Bool, +hist: Bool, ui: T.Ui, +pending: List<&2, Key.ServerId>, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +ws: W.Workspace, +main: Chan(WsMsg), +pevts: Chan(Sess.UiMsg), k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  ws_shut.drained.go(ws_shut.ready(done, hist, ws_shut.writers(pending)), done, hist, ui, pending, ctx, st, id, owner, ok, started, ws, main, pevts, k)

def ws_shut.pending(+pending: List<&2, Key.ServerId>, ui: T.Ui, +ctx: PrefLive.Context, +st: Sess.Session, +id: Key.ServerId, +owner: Maybe<&2, WsLease>, +ok: Bool, +started: U32, +done: Bool, +hist: Bool, +ws: W.Workspace, +main: Chan(WsMsg), +pevts: Chan(Sess.UiMsg), k: T.Ui & WsShut -> IO(Unit)) -> IO(Unit):
  match pending:
    case Nil{}: ws_shut.drained(done, hist, ui, pending, ctx, st, id, owner, ok, started, ws, main, pevts, k)
    case Con{_, _}: ws_shut.step(ui, pending, ctx, st, id, owner, ok, started, done, hist, ws, main, pevts, k)

@unsafe
def ws_shutdown_wait(acc: T.Ui & WsShut, +ws: W.Workspace, +main: Chan(WsMsg), +evts: WsEvts, +pevts: Chan(Sess.UiMsg)) -> IO(Unit):
  match acc:
    case (ui, +shut):
      match shut:
        case WsShut{+pending, +ctx, +st, +id, +owner, +ok, +started, +done, hist}:
          ws_shut.pending(pending, ui, ctx, st, id, owner, ok, started, done, hist, ws, main, pevts, acc2 => ws_shutdown_wait(acc2, ws, main, evts, pevts))

def ws_shutdown.close(+cmds: WsCmds) -> IO(Unit):
  match cmds:
    case WsCmds{+c0, +c1, +c2, +c3}:
      do IO<Unit>:
        Unit <- Chan.close(Sess.NetCmd, c0)
        Unit <- Chan.close(Sess.NetCmd, c1)
        Unit <- Chan.close(Sess.NetCmd, c2)
        Unit <- Chan.close(Sess.NetCmd, c3)
        return Unit{}

def ws_shutdown(+loop: WsLoop, ui: T.Ui, +ws: W.Workspace, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg)) -> IO(Unit):
  match loop:
    case WsLoop{_, _, _, +ctx, _, +owner, _, _, +cards, _}:
      +id = ws_shut.owner_id(owner, ws)
      +hot = ws_cards_all.hot(cards)
      +hist = ws_history.have_jobs(ws_hot.jobs_of(hot))
      +pending = ws_pending(ws)
      do IO<Unit>:
        started : U32 <- Clock.millis()
        Unit <- ws_shut.arm(ws_shut.need(PrefLive.busy(ctx), hist, ws_shut.writers(pending)), pevts)
        Unit <- ws_shutdown.close(cmds)
        Unit <- ws_history.drain_spawn(hist, hot)
        ws_shutdown_wait((ui, WsShut{pending, ctx, ws_part.st(ws, id), id, owner, True{}, started, ws_shut.settle(ctx), hist}), ws, main, evts, pevts)

def ws_halt(halt: Bool, ui: T.Ui, +loop: WsLoop, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), k: (T.Ui & WsLoop) -> IO(Unit)) -> IO(Unit):
  match halt:
    case True{}:
      match loop:
        case WsLoop{+ws, _, _, _, _, _, _, _, _, _}: ws_shutdown(loop, ui, ws, main, cmds, evts, pevts)
    case False{}: k((ui, loop))

def ws_next(acc: T.Ui & WsLoop & Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop) -> IO(Unit)) -> IO(Unit):
  match acc:
    case (ui, rest):
      match rest:
        case (+loop, halt): ws_halt(halt, ui, loop, main, cmds, evts, pevts, k)

def ws_parked.missing(ui: T.Ui, +cmds: WsCmds) -> IO(Unit):
  do IO<Unit>:
    Unit <- ws_shutdown.close(cmds)
    Net.watch_die((1, "birc: loop envelope missing"), ui)

# Select the received event before opening its saved loop fields.
def ws_parked.msg(wmsg: WsMsg, +saved: List<&2, WsLoop>, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match wmsg:
    case WsNet{+rm}:
      match saved:
        case Con{_, _}: ws_routed.wait(saved, rm, ui, main, cmds, evts, pevts, ack, k)
        case Nil{}: ws_parked.missing(ui, cmds)
    case WsPrefs{m}:
      match saved:
        case Con{WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}, _}:
          ws_prefs.msg(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), m, ui, main, cmds, evts, pevts, ack, k)
        case Nil{}: ws_parked.missing(ui, cmds)
    case WsRedial{+intent}:
      match saved:
        case Con{WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}, _}:
          ws_redial(ws, intent, cmds, evts, next => ws_redial.painted(next, ws, intent, ui, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, notify, cards, begun, k))
        case Nil{}: ws_parked.missing(ui, cmds)
    case WsTick{now_ms}:
      match saved:
        case Con{WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}, _}:
          ws_tick.painted(W.tick_typing(ws, now_ms), ui, main, cmds, evts, pevts, ack, scheduled, bell, ctx, media, owner, ups, notify, cards, begun, k)
        case Nil{}: ws_parked.missing(ui, cmds)
    case WsUi{m}:
      match saved:
        case Con{WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}, _}:
          ws_paint.ui(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), ui, m, main, cmds, evts, pevts, ack, k)
        case Nil{}: ws_parked.missing(ui, cmds)
    case WsHistAck{+sid, +seq}:
      match saved:
        case Con{+loop, _}: k((ui, ws_hist_ack.loop(loop, sid, seq), False{}))
        case Nil{}: ws_parked.missing(ui, cmds)
    case WsHistDiag{+msg, +sid, +base, +seq, +retry}:
      match saved:
        case Con{WsLoop{+ws, +bell, +scheduled, +ctx, +media, +owner, +ups, +notify, +cards, +begun}, _}:
          ws_hist_diag(ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun), msg, sid, base, seq, retry, ui, main, cmds, evts, pevts, ack, k)
        case Nil{}: ws_parked.missing(ui, cmds)
    case WsHistDone{}:
      match saved:
        case Con{+loop, _}: k((ui, loop, False{}))
        case Nil{}: ws_parked.missing(ui, cmds)
    case WsReady{_, _}:
      match saved:
        case Con{+loop, _}: k((ui, loop, False{}))
        case Nil{}: ws_parked.missing(ui, cmds)

# Receive-carry: Ui/message/continuation remain outside Data. EOF forwards
# the exact envelope; network messages keep its recursive cell through the
# routed clocks. Other events open it only after their message is selected.
def ws_parked.recv(g: Maybe<&1, WsMsg>, +saved: List<&2, WsLoop>, ui: T.Ui, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), k: (T.Ui & WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}:
      match saved:
        case Con{+loop, _}: k((ui, loop, True{}))
        case Nil{}: ws_parked.missing(ui, cmds)
    case Some{wmsg}: ws_parked.msg(wmsg, saved, ui, main, cmds, evts, pevts, ack, k)

def ws_loop.empty(acc: T.Ui & WsLoop, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg)) -> IO(Unit):
  match acc:
    case (ui, +loop):
      match loop:
        case WsLoop{+ws, _, _, _, _, _, _, _, _, _}: ws_shutdown(loop, ui, ws, main, cmds, evts, pevts)

@unsafe
def ws_loop(+fuel: Nat, acc: T.Ui & WsLoop, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  match fuel:
    case 0n: ws_loop.empty(acc, main, cmds, evts, pevts)
    case 1n+p:
      match acc:
        case (ui, +loop):
          +saved: List<&2, WsLoop> = [loop]
          do IO<Unit>:
            g : Maybe<&1, WsMsg> <- Chan.recv(WsMsg, main)
            ws_parked.recv(g, saved, ui, main, cmds, evts, pevts, ack, acc2 => ws_next(acc2, main, cmds, evts, pevts, ack, nxt => ws_loop(p, nxt, main, cmds, evts, pevts, ack)))

@unsafe
def ws_idle(acc: T.Ui & WsLoop, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  match acc:
    case (ui, +loop):
      +saved: List<&2, WsLoop> = [loop]
      do IO<Unit>:
        g : Maybe<&1, WsMsg> <- Chan.recv(WsMsg, main)
        ws_parked.recv(g, saved, ui, main, cmds, evts, pevts, ack, acc2 => ws_next(acc2, main, cmds, evts, pevts, ack, nxt => ws_idle(nxt, main, cmds, evts, pevts, ack)))

# ---- boot ---------------------------------------------------------------------
def ws_port(+port: Maybe<&2, U32>, +force_tls: Bool) -> U32:
  match port:
    case Some{+p}: p
    case None{}: Bool.pick(U32, force_tls, Policy.TLS_PORT(), Policy.PLAIN_PORT())

def ws_boot.spawn(+s: Key.ServerId, +host: String, +port: U32, +nick: String, +gen: U32, +has_sasl: Bool, +frames: U32, +force_tls: Bool, +main: Chan(WsMsg), +cmd: Chan(Sess.NetCmd), +evt: Chan(Sess.UiMsg), +boot: Chan(Act.Boot), +deferred: Bool) -> IO(Unit):
  match deferred:
    case True{}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, Act.deferred_start_tls(host, port, nick, evt, cmd, boot, has_sasl, frames, force_tls))
        Unit <- IO.spawn(Unit, net_fwd(s, evt, main))
        Unit <- IO.spawn(Unit, Net.heartbeat(cmd))
        Unit <- IO.spawn(Unit, boot_fwd(s, gen, boot, main))
        return Unit{}
    case False{}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, Act.actor_boot_tls(host, port, nick, gen, evt, cmd, boot, has_sasl, frames, force_tls))
        Unit <- IO.spawn(Unit, net_fwd(s, evt, main))
        Unit <- IO.spawn(Unit, Net.heartbeat(cmd))
        Unit <- IO.spawn(Unit, boot_fwd(s, gen, boot, main))
        return Unit{}

def ws_boot.one(+s: Key.ServerId, +host: String, +port: U32, +nick: String, +gen: U32, +has_sasl: Bool, +frames: U32, +force_tls: Bool, +main: Chan(WsMsg), +cmd: Chan(Sess.NetCmd), +evt: Chan(Sess.UiMsg), +deferred: Bool) -> IO(Unit):
  do IO<Unit>:
    boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    ws_boot.spawn(s, host, port, nick, gen, has_sasl, frames, force_tls, main, cmd, evt, boot, deferred)

# Each actor's SASL request comes from its own part's client, never from a
# temporary credentialed copy: the primary part carries the launch profile
# and extras stay bare, so requests and Session exchanges always agree and
# the launch profile never reaches another endpoint.
# G4: actors boot at their part's live slot generation (post first-input),
# so a first-frame dial that bumped the part still meets its Begin fence.
# DIRECT-BOOT parity: first-frame keys may already have routed the workspace
# (a /connect switched the part endpoint and emitted its Dial), so boot from
# the POST-KEY part endpoints — mirroring ws_begin_all over W.ws_parts —
# never the stale CLI list. Only the keyed endpoint registers; no dropped
# Dial can admit foreign traffic into the new scope. Slots without a part
# boot nothing; per-part generation and SASL policy still come from the
# live part, so the deferred path and auth-scope fences are preserved.
def ws_boot.each_part(+ws: W.Workspace, +nick: String, +frames: U32, +force_tls: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +p: W.Part, +deferred: Bool) -> IO(Unit):
  match p:
    case W.Part{+id, +gen, +scope, _}:
      match scope:
        case Sid.Scope{+host, +port, _}:
          ws_boot.one(id, host, ws_port(Some{port}, force_tls), nick, gen, W.part_has_sasl(ws, id), frames, force_tls, main, ws_cmd.at(cmds, ws_id_nat(id)), ws_evt.at(evts, ws_id_nat(id)), deferred)

def ws_boot.each(+ws: W.Workspace, +nick: String, +frames: U32, +force_tls: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +parts: List<&2, W.Part>, +deferred: Bool) -> IO(Unit):
  match parts:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{+h, +t}:
      do IO<Unit>:
        Unit <- ws_boot.each_part(ws, nick, frames, force_tls, main, cmds, evts, h, deferred)
        ws_boot.each(ws, nick, frames, force_tls, main, cmds, evts, t, deferred)

def ws_build.go(+eps: List<&2, Ep.Endpoint>, +ws: W.Workspace, +nick: String, +chan: String, +force_tls: Bool) -> W.Workspace:
  match eps:
    case Nil{}: ws
    case Con{+ep, +t}:
      match ep:
        case Ep.Endpoint{+host, +port}:
          ws_build.go(t, W.do_add(ws, host, ws_port(port, force_tls), False{}, nick, chan), nick, chan, force_tls)

# G4: the deferred epoch. Fresh deferred actors start at generation 1
# (mirroring the single-server deferred start), so boot parts move from
# the direct epoch 0 to 1 before any Begin is scoped.
def ws_defer.go(+xs: List<&2, W.Part>) -> List<&2, W.Part>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      match h:
        case W.Part{+id, _, +scope, +st}: W.Part{id, 1, scope, st} <> ws_defer.go(t)

def ws_deferred(+ws: W.Workspace) -> W.Workspace:
  match ws:
    case W.Workspace{+parts, +cur, +ds, +rt}: W.Workspace{ws_defer.go(parts), cur, ds, rt}

def ws_epoch(+ws: W.Workspace, +deferred: Bool) -> W.Workspace:
  match deferred:
    case True{}: ws_deferred(ws)
    case False{}: ws

def ws_policy(+options: PrefWorker.Options) -> Bool:
  match options:
    case PrefWorker.Options{+on, _, _, _}: on

# G4: per-part settings prepare plus history import. One preference read
# resolves before each part history snapshot, exactly like the headless
# policy. The slot-order join keeps the lowest slot's prepared context,
# and the fail-closed conjunction of every part decision stays.
def ws_load.keep(+lp: LoadedPrefs.Context, +acc: Maybe<&2, LoadedPrefs.Context>) -> Maybe<&2, LoadedPrefs.Context>:
  match acc:
    case Some{+kept}: Some{kept}
    case None{}: Some{lp}

def ws_load.keep2(+a: Maybe<&2, LoadedPrefs.Context>, +b: Maybe<&2, LoadedPrefs.Context>) -> Maybe<&2, LoadedPrefs.Context>:
  match a:
    case Some{+kept}: Some{kept}
    case None{}: b

def ws_load.prepped(result: LoadedPrefs.Context & Sess.Session & Bool, +ws: W.Workspace, +id: Key.ServerId) -> IO(WsLoaded):
  match result:
    case (+lp, +st, known):
      IO.pure(WsLoaded, WsLoaded{ws_replace(ws, id, st), Some{lp}, known})

# G4/LP: the first frame runs before any settings/history load, so a
# first-key /images edit wins over the BIRC_IMAGES default. The load
# seed carries the keyed session's actual media setting when edited;
# LP.initial/LP.loaded then capture that true value instead of the
# stale pre-frame default.
def ws_load.images_edited(+st: Sess.Session) -> Bool:
  List.contains(~String, ~String.eq, Sess.session_preference_edits(st), "images")

def ws_load.images_pick(edited: Bool, +st: Sess.Session, on: Bool) -> Bool:
  match edited:
    case True{}: M.enabled(Sess.session_media(st))
    case False{}: on

def ws_load.images_on(+st: Sess.Session, on: Bool) -> Bool:
  ws_load.images_pick(ws_load.images_edited(st), st, on)

# The startup divider is "Reconnected: HMS" from Client.now. Init leaves
# that clock empty; stamp it before the archive import.
def ws_load.stamped(+st: Sess.Session, +ts: String, on: Bool) -> Sess.Session:
  Sess.session_set_now(Sess.session_set_media(st, M.initial(ws_load.images_on(st, on))), ts)

def ws_load.one_got(+got: Maybe<&2, W.Part>, +ws: W.Workspace, +id: Key.ServerId, +path: String, +options: PrefWorker.Options, +on: Bool) -> IO(WsLoaded):
  match got:
    case None{}: IO.pure(WsLoaded, WsLoaded{ws, None{}, True{}})
    case Some{+p}:
      do IO<WsLoaded>:
        ts : String <- Clock.stamp()
        result : LoadedPrefs.Context & Sess.Session & Bool <- Headless.prepare(options, ws_load.stamped(W.part_session(p), ts, on), W.part_gen(p), path)
        ws_load.prepped(result, ws, id)

def ws_load.one(+ws: W.Workspace, +id: Key.ServerId, +path: String, +options: PrefWorker.Options, +on: Bool) -> IO(WsLoaded):
  ws_load.one_got(W.find_part(ws, id), ws, id, path, options, on)

def ws_start.ctx(+lp_acc: Maybe<&2, LoadedPrefs.Context>, +options: PrefWorker.Options, +ws: W.Workspace, +path: String, +known: Bool) -> PrefLive.Context:
  match lp_acc:
    case Some{+lp}: PrefLive.prepared(lp, path, known)
    case None{}: PrefLive.initial(options, ws_part.st(ws, W.ws_current(ws)), ws_part.gen(ws, W.ws_current(ws)), path)

def ws_begin.zero(+frames: U32, ui: T.Ui, +ws: W.Workspace, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +ctx: PrefLive.Context, +cards: WsCardsAll, +begun: Bool, zero: Bool) -> IO(Unit):
  match zero:
    case True{}: ws_idle((ui, ws_mkloop(ws, 0, False{}, ctx, None{}, None{}, Nil{}, ws_notify.seed_all(ws), cards, begun)), main, cmds, evts, pevts, ack)
    case False{}: ws_loop(Sess.ticks_of(frames), (ui, ws_mkloop(ws, 0, False{}, ctx, None{}, None{}, Nil{}, ws_notify.seed_all(ws), cards, begun)), main, cmds, evts, pevts, ack)

def ws_begin.armed(+frames: U32, ui: T.Ui, +ws: W.Workspace, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +ctx: PrefLive.Context, +begun: Bool, on: Bool, +cap: U32, +jobs: Chan(HistJob)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.spawn(Unit, hist_worker(jobs, main))
    ws_begin.zero(frames, ui, ws, main, cmds, evts, pevts, ack, ctx, ws_cards_all.live(on, ws_hot.path_of(ctx), cap, jobs), begun, U32.is_eq(frames, 0))

def ws_begin(+frames: U32, ui: T.Ui, +ws: W.Workspace, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +ctx: PrefLive.Context, +begun: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.spawn(Unit, ws_more_send(main))
    on : Bool <- CNet.cards_enabled()
    cap : U32 <- Hist.resolve_history_cap()
    jobs : Chan(HistJob) <- Chan.new(HistJob, 8)
    ws_begin.armed(frames, ui, ws, main, cmds, evts, pevts, ack, ctx, begun, on, cap, jobs)

# G4: the startup first frame runs before any settings/history load. The
# frame paints the bare epoch workspace and applies its input keys bare
# (no history save, no worker stages, no actor emit): drafts and explicit
# settings edits survive the later import via install preservation and
# edit-wins loading, while a first-frame quit halts before any load, boot,
# or Begin. The captured RoutedCmd emits after boot; the single deferred
# Begin follows the emit, so registration never precedes input.
def ws_first.tripped(trip: W.Workspace & Sid.RoutedCmd & Bool, +old: W.Workspace, +rows: U32, +cols: U32, +quit: U32, +typed: String, +restore: Bool) -> W.Workspace & Sid.RoutedCmd & Bool:
  match trip:
    case (+ws2, +rc, halt):
      +sized = W.set_current_size(ws2, rows, cols)
      +restored = ws_upload.restored(sized, typed, restore)
      (ws_upload.presented(old, restored), rc, halt || T.flag_on(quit))

# Actors do not exist during this startup-only frame. A valid connection
# command may replace the pending launch endpoint, while ordinary live
# Connecting/Reconnecting commands must keep Session's busy rejection.
# Use the existing Workspace/Session/Drafts transition, then remove the
# temporary Offline permission: a first same-endpoint Dial stays Connecting,
# not a fabricated reconnect boundary. Non-Dials restore the prior net state.
def ws_first.connect_busy(net: Sess.NetState) -> Bool:
  match net:
    case Sess.Connecting{}: True{}
    case Sess.Reconnecting{}: True{}
    case _: False{}

def ws_first.connect_valid(conn: Sub.Conn, +st: Sess.Session) -> Bool:
  match conn:
    case Sub.ConnBad{}: False{}
    case Sub.ConnReconnect{}: Sess.reconnect_configured(Sess.session_net(st), Cl.server_of(Sess.session_cl(st)))
    case _: True{}

def ws_first.connect_input(+input: Sub.Input, +st: Sess.Session) -> Bool:
  Sub.submit_is_connect.parsed(input)
    && ws_first.connect_valid(Sub.connect_from_input.parsed(input), st)
    && ws_first.connect_busy(Sess.session_net(st))

def ws_first.connect_enter(enter: Bool, +ws: W.Workspace, +typed: String) -> Bool:
  match enter:
    case False{}: False{}
    case True{}: ws_first.connect_input(Sub.parse_input(typed), W.current_session(ws))

def ws_first.connect_net.cmd(cmd: Sess.NetCmd, +prior: Sess.Session) -> Sess.NetState:
  match cmd:
    case Sess.Dial{+host, +port, _, _}:
      Sess.dialing_state(Sess.endpoint_same(Sess.session_cl(prior), host, Sess.session_port(prior), port), Sess.session_net(prior))
    case _: Sess.session_net(prior)

def ws_first.connect_net(rc: Sid.RoutedCmd, +prior: Sess.Session) -> Sess.NetState:
  match rc:
    case Sid.RoutedCmd{_, cmd}: ws_first.connect_net.cmd(cmd, prior)

def ws_first.connect_done.r1(rest: Sid.RoutedCmd & Bool, +next: W.Workspace, +prior: W.Workspace) -> W.Workspace & Sid.RoutedCmd & Bool:
  match rest:
    case (+rc, +halt):
      +id = W.ws_current(prior)
      +net = ws_first.connect_net(rc, ws_part.st(prior, id))
      +fixed = ws_replace(next, id, Sess.session_set_net(ws_part.st(next, id), net))
      (fixed, rc, halt)

def ws_first.connect_done(trip: W.Workspace & Sid.RoutedCmd & Bool, +prior: W.Workspace) -> W.Workspace & Sid.RoutedCmd & Bool:
  match trip:
    case (+next, rest): ws_first.connect_done.r1(rest, next, prior)

def ws_first.connect_run(unlock: Bool, +ws: W.Workspace, +keys: Sess.Keys) -> W.Workspace & Sid.RoutedCmd & Bool:
  match unlock:
    case False{}: W.live_step_keys(ws, keys)
    case True{}:
      +id = W.ws_current(ws)
      +prepared = ws_replace(ws, id, Sess.session_set_net(ws_part.st(ws, id), Sess.Offline{}))
      ws_first.connect_done(W.live_step_keys(prepared, keys), ws)

def ws_first.pol(+ws: W.Workspace, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +tab: U32, +up: U32, +dn: U32, +hist: U32, +quit: U32, +comp: U32, +focus: U32, +restore: Bool) -> W.Workspace & Sid.RoutedCmd & Bool:
  +unlock = ws_first.connect_enter(enter && Bool.not(restore) && Bool.not(T.flag_on(quit)), ws, typed)
  ws_first.tripped(ws_first.connect_run(unlock, ws, Sess.keys_of(typed, enter, tab, click, up, dn, hist, comp, focus)), ws, rows, cols, quit, typed, restore)

def ws_first.polled_go(+ws: W.Workspace, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +pol: Sess.KeyPol, +restore: Bool) -> W.Workspace & Sid.RoutedCmd & Bool:
  match pol:
    case Sess.KeyPol{+tab, +up, +dn, +hist, +quit, +comp, +focus}:
      ws_first.pol(ws, typed, enter, rows, cols, click, tab, up, dn, hist, quit, comp, focus, restore)

def ws_first.f7(+ws: W.Workspace, +typed: String, +rows: U32, +cols: U32) -> W.Workspace & Sid.RoutedCmd & Bool:
  +ws2 = W.cycle_ws(W.cycle_server(W.set_current_size(ws, rows, cols), typed))
  +presented = ws_upload.presented(ws, ws2)
  (presented, ws_f7.rc(ws2), False{})

def ws_first.act(+ws: W.Workspace, +typed: String, +enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, f7: Bool, +restore: Bool) -> W.Workspace & Sid.RoutedCmd & Bool:
  match f7:
    case True{}: ws_first.f7(ws, typed, rows, cols)
    case False{}: ws_first.polled_go(ws, typed, enter, rows, cols, click, Sess.key_pol_for(W.current_session(ws), key, mods, codepoint, wheel, rows), restore)

def ws_first.combined(ui: T.Ui, trip: W.Workspace & Sid.RoutedCmd & Bool) -> T.Ui & W.Workspace & Sid.RoutedCmd & Bool:
  match trip:
    case (+ws2, +rc, halt):
      (ui, ws2, rc, halt)

def ws_first.keyed(pair: W.Workspace & Bool, +typed: String, +enter_orig: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32) -> W.Workspace & Sid.RoutedCmd & Bool:
  match pair:
    case (+ws_keyed, +handled):
      +enter = enter_orig && Bool.not(handled)
      +key_sup = Bool.pick(U32, handled, 0, key)
      +code_sup = Bool.pick(U32, handled, 0, codepoint)
      +restore = handled && enter_orig
      ws_first.act(ws_keyed, typed, enter, rows, cols, click, key_sup, mods, code_sup, wheel, U32.is_eq(key_sup, Sess.KEY_F7()), restore)

def ws_first.painted(got: T.Ui & T.UiKeys, +ws: W.Workspace, +evts: WsEvts) -> IO(T.Ui & W.Workspace & Sid.RoutedCmd & Bool):
  match got:
    case (ui, keys):
      match keys:
        case T.UiKeys{enter, +typed, +rows, cols, click, +key, +mods, codepoint, wheel, _, +url, +clipboard}:
          +enter_orig = T.flag_on(enter)
          do IO<T.Ui & W.Workspace & Sid.RoutedCmd & Bool>:
            Unit <- Net.open_clicked(Some{ws_evt.id(evts, W.ws_current(ws))}, url)
            Unit <- Net.frame_clipboard(clipboard, Some{ws_evt.id(evts, W.ws_current(ws))})
            return ws_first.combined(ui, ws_first.keyed(ws_upload.keyed(ws, key, mods), typed, enter_orig, rows, cols, click, key, mods, codepoint, wheel))

def ws_first.frame(ui: T.Ui, +ws: W.Workspace, +evts: WsEvts) -> IO(T.Ui & W.Workspace & Sid.RoutedCmd & Bool):
  do IO<T.Ui & W.Workspace & Sid.RoutedCmd & Bool>:
    got : T.Ui & T.UiKeys <- Net.paint_session(ui, W.paint_session(ws, 0))
    ws_first.painted(got, ws, evts)

# DIRECT-BOOT single owner: the direct actor already dialed each part's
# post-key endpoint/generation at boot, so a captured first-frame Dial for
# that same part/endpoint/generation must not emit again. Success hid the
# duplicate behind Act.dial_superseded (connected); failure left Writer
# None/gen, so the same-gen queued Dial was admitted as a silent retry
# behind W.live_initial's Offline quarantine. Boot owns the direct Dial;
# deferred boot stays silent until Begin, so deferred still emits.
# Equivalence is id/endpoint/generation only: boot uses the launch nick
# while the captured Dial carries the session nick, and the success path
# already dropped the duplicate (boot nick wins either way).
def ws_start.boot_dial_part(+got: Maybe<&2, W.Part>, +host: String, +port: U32, +gen: U32) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}:
      match p:
        case W.Part{_, +g, +scope, _}:
          match scope:
            case Sid.Scope{+shost, +sport, _}:
              U32.is_eq(gen, g) && U32.is_eq(port, sport) && String.eq(host, shost)

def ws_start.boot_dial_equivalent(+ws: W.Workspace, +rc: Sid.RoutedCmd) -> Bool:
  match rc:
    case Sid.RoutedCmd{+s, +cmd}:
      match cmd:
        case Sess.Dial{+host, +port, +gen, _}:
          ws_start.boot_dial_part(W.find_part(ws, s), host, port, gen)
        case _: False{}

def ws_start.drop_boot_dial(+deferred: Bool, +ws: W.Workspace, +rc: Sid.RoutedCmd) -> Bool:
  match deferred:
    case True{}: False{}
    case False{}: ws_start.boot_dial_equivalent(ws, rc)

def ws_start.emit_boot.go(drop: Bool, +rc: Sid.RoutedCmd, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match drop:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: ws_emit(rc, cmds, evts)

def ws_start.emit_boot(+deferred: Bool, +ws: W.Workspace, +rc: Sid.RoutedCmd, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  ws_start.emit_boot.go(ws_start.drop_boot_dial(deferred, ws, rc), rc, cmds, evts)

# The first frame's command stays captured across the load. A key during
# the wait adds its own command; an empty Cont from a draft or resize is
# a no-op emit, so both can go out in order.
def ws_start.emit_extra(+deferred: Bool, +ws: W.Workspace, +more: Maybe<&2, Sid.RoutedCmd>, +cmds: WsCmds, +evts: WsEvts) -> IO(Unit):
  match more:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+rc}: ws_start.emit_boot(deferred, ws, rc, cmds, evts)

# Watches are already running. Boot, emit the captured command, Begin,
# then enter the live loop. Do not open the tty again.
def ws_start.live(+loaded: WsLoaded, ui: T.Ui, +options: PrefWorker.Options, +path: String, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool, +rc: Sid.RoutedCmd, +extra_rc: Maybe<&2, Sid.RoutedCmd>) -> IO(Unit):
  match loaded:
    case WsLoaded{+ws2, +lp_acc, +known}:
      +ctx = ws_start.ctx(lp_acc, options, ws2, path, known)
      do IO<Unit>:
        Unit <- ws_boot.each(ws2, nick, frames, force_tls, main, cmds, evts, W.ws_parts(ws2), deferred)
        Unit <- ws_start.emit_boot(deferred, ws2, rc, cmds, evts)
        Unit <- ws_start.emit_extra(deferred, ws2, extra_rc, cmds, evts)
        Unit <- ws_begin_all(cmds, ws2)
        Unit <- IO.spawn(Unit, prefs_fwd(pevts, main))
        Unit <- IO.spawn(Unit, ws_typing_watch(main))
        ws_begin(frames, ui, ws2, main, cmds, evts, pevts, ack, ctx, True{})

# One part's prepared session. Parts run together; the join applies them
# in slot order so the first prepared context stays the lowest id.
type WsPartDone is Data:
  WsPartDone{id: Key.ServerId, st: Sess.Session, lp: Maybe<&2, LoadedPrefs.Context>, known: Bool}

def ws_load.done_of(+loaded: WsLoaded, +id: Key.ServerId) -> WsPartDone:
  match loaded:
    case WsLoaded{+ws, +lp, +known}: WsPartDone{id, ws_part.st(ws, id), lp, known}

def ws_load.part(+ws: W.Workspace, +id: Key.ServerId, +path: String, +options: PrefWorker.Options, +on: Bool, +out: Chan(WsPartDone)) -> IO(Unit):
  do IO<Unit>:
    loaded : WsLoaded <- ws_load.one(ws, id, path, options, on)
    _ : Result<&1, &1, WsPartDone, Unit> <- Chan.send(WsPartDone, out, ws_load.done_of(loaded, id))
    return Unit{}

def ws_load.done_id(+d: WsPartDone) -> Key.ServerId:
  match d:
    case WsPartDone{+id, _, _, _}: id

def ws_load.pick.hit(hit: Bool, +found: WsPartDone, +rest: Maybe<&2, WsPartDone>) -> Maybe<&2, WsPartDone>:
  match hit:
    case True{}: Some{found}
    case False{}: rest

def ws_load.pick(+id: Key.ServerId, +xs: List<&2, WsPartDone>) -> Maybe<&2, WsPartDone>:
  match xs:
    case Nil{}: None{}
    case Con{+h, +t}: ws_load.pick.hit(Key.eq(id, ws_load.done_id(h)), h, ws_load.pick(id, t))

def ws_load.use.base(+base: WsLoaded, +id: Key.ServerId, +st: Sess.Session, +lp: Maybe<&2, LoadedPrefs.Context>, known: Bool) -> WsLoaded:
  match base:
    case WsLoaded{+ws, +lp_acc, +known_acc}:
      WsLoaded{ws_replace(ws, id, st), ws_load.keep2(lp_acc, lp), known_acc && known}

def ws_load.use(+done: WsPartDone, +base: WsLoaded) -> WsLoaded:
  match done:
    case WsPartDone{+id, +st, +lp, +known}: ws_load.use.base(base, id, st, lp, known)

def ws_load.fold.got(+got: Maybe<&2, WsPartDone>, +base: WsLoaded) -> WsLoaded:
  match got:
    case None{}: base
    case Some{+done}: ws_load.use(done, base)

def ws_load.fold(fuel: Nat, +slot: Nat, +xs: List<&2, WsPartDone>, +base: WsLoaded) -> WsLoaded:
  match fuel:
    case 0n: base
    case 1n+p: ws_load.fold(p, Nat.add(slot, 1n), xs, ws_load.fold.got(ws_load.pick(Key.ServerId{slot}, xs), base))

# None means the part channel closed early. Stop with what already arrived.
# A value continues, and the self-call stays on the decreased fuel.
def ws_load.collect.acc(g: Maybe<&1, WsPartDone>, +xs: List<&2, WsPartDone>, k: List<&2, WsPartDone> -> IO(List<&2, WsPartDone>)) -> IO(List<&2, WsPartDone>):
  match g:
    case None{}: IO.pure(List<&2, WsPartDone>, xs)
    case Some{+done}: k(done <> xs)

def ws_load.collect(fuel: Nat, +box: Chan(WsPartDone), +acc: List<&2, WsPartDone>) -> IO(List<&2, WsPartDone>):
  match fuel:
    case 0n: IO.pure(List<&2, WsPartDone>, acc)
    case 1n+p:
      do IO<List<&2, WsPartDone>>:
        g : Maybe<&1, WsPartDone> <- Chan.recv(WsPartDone, box)
        ws_load.collect.acc(g, acc, ys => ws_load.collect(p, box, ys))

# Four part fibers share the post-frame snapshot. Each prepares its own
# settings before its own archive. The join is slot order, then one Begin.
def ws_load.worker(+ws: W.Workspace, +options: PrefWorker.Options, +main: Chan(WsMsg)) -> IO(Unit):
  do IO<Unit>:
    +path : String <- Hist.resolve_history_path()
    +on : Bool <- Net.images_enabled()
    +box : Chan(WsPartDone) <- Chan.new(WsPartDone, 4)
    Unit <- IO.spawn(Unit, ws_load.part(ws, Key.ServerId{0n}, path, options, on, box))
    Unit <- IO.spawn(Unit, ws_load.part(ws, Key.ServerId{1n}, path, options, on, box))
    Unit <- IO.spawn(Unit, ws_load.part(ws, Key.ServerId{2n}, path, options, on, box))
    Unit <- IO.spawn(Unit, ws_load.part(ws, Key.ServerId{3n}, path, options, on, box))
    xs : List<&2, WsPartDone> <- ws_load.collect(4n, box, Nil{})
    _ : Result<&1, &1, WsMsg, Unit> <- Chan.send(WsMsg, main, WsReady{ws_load.fold(4n, 0n, xs, WsLoaded{ws, None{}, True{}}), path})
    return Unit{}

def ws_hold0() -> WsHold:
  WsHold{False{}, "", False{}, 0, 0, 0, 0, 0, 0, 0, "", ""}

def ws_hold.nz(+n: U32) -> Bool:
  Bool.not(U32.is_zero(n))

# A frame is hot when it can change the session. The tty watcher's first
# ready is not: key, wheel, click, and composer all stay put.
def ws_hold.hot(enter: Bool, +key: U32, +codepoint: U32, +wheel: U32, +click: U32, +url: String, +clipboard: String, changed: Bool) -> Bool:
  enter || changed || ws_hold.nz(key) || ws_hold.nz(codepoint) || ws_hold.nz(wheel) || ws_hold.nz(click) || Bool.not(String.is_empty(url)) || Bool.not(String.is_empty(clipboard))

# A later resize must not drop the key that should be replayed, and must
# not invent one. Rows and cols always come from the newest frame.
def ws_hold.keep(hot: Bool, +prev: WsHold, +next: WsHold) -> WsHold:
  match hot:
    case True{}: next
    case False{}:
      match prev:
        case WsHold{have, +typed, enter, _, _, +click, +key, +mods, +codepoint, +wheel, +url, +clipboard}:
          match next:
            case WsHold{_, _, _, +rows, +cols, _, _, _, _, _, _, _}:
              WsHold{have, typed, enter, rows, cols, click, key, mods, codepoint, wheel, url, clipboard}

def ws_wait.quit_pol(pol: Sess.KeyPol) -> Bool:
  match pol:
    case Sess.KeyPol{_, _, _, _, +quit, _, _}: T.flag_on(quit)

def ws_wait.replayed(trip: W.Workspace & Sid.RoutedCmd & Bool, +rc: Sid.RoutedCmd, +lp: Maybe<&2, LoadedPrefs.Context>, known: Bool, ui: T.Ui, +options: PrefWorker.Options, +path: String, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool) -> IO(Unit):
  match trip:
    case (+ws2, +rc2, halt):
      match halt:
        case True{}: Net.shutdown_finish(ui, True{})
        case False{}: ws_start.live(WsLoaded{ws2, lp, known}, ui, options, path, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls, rc, Some{rc2})

def ws_wait.replay(+hold: WsHold, +ws: W.Workspace, +lp: Maybe<&2, LoadedPrefs.Context>, known: Bool, ui: T.Ui, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +path: String, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool) -> IO(Unit):
  match hold:
    case WsHold{_, +typed, enter, +rows, +cols, +click, +key, +mods, +codepoint, +wheel, +url, +clipboard}:
      do IO<Unit>:
        Unit <- Net.open_clicked(Some{ws_evt.id(evts, W.ws_current(ws))}, url)
        Unit <- Net.frame_clipboard(clipboard, Some{ws_evt.id(evts, W.ws_current(ws))})
        ws_wait.replayed(ws_first.keyed((ws, False{}), typed, enter, rows, cols, click, key, mods, codepoint, wheel), rc, lp, known, ui, options, path, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls)

# rows 0 is the untouched hold. A real frame is at least the measure floor.
def ws_wait.sized(zero: Bool, +ws: W.Workspace, +rows: U32, +cols: U32) -> W.Workspace:
  match zero:
    case True{}: ws
    case False{}: W.set_current_size(ws, rows, cols)

def ws_wait.live_cold(+rows: U32, +cols: U32, +ws: W.Workspace, +lp: Maybe<&2, LoadedPrefs.Context>, known: Bool, ui: T.Ui, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +path: String, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool) -> IO(Unit):
  ws_start.live(WsLoaded{ws_wait.sized(U32.is_zero(rows), ws, rows, cols), lp, known}, ui, options, path, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls, rc, None{})

def ws_wait.done_have(have: Bool, +typed: String, enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +url: String, +clipboard: String, +ws: W.Workspace, +lp: Maybe<&2, LoadedPrefs.Context>, known: Bool, ui: T.Ui, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +path: String, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool) -> IO(Unit):
  match have:
    case False{}: ws_wait.live_cold(rows, cols, ws, lp, known, ui, rc, options, path, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls)
    case True{}: ws_wait.replay(WsHold{True{}, typed, enter, rows, cols, click, key, mods, codepoint, wheel, url, clipboard}, ws, lp, known, ui, rc, options, path, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls)

def ws_wait.done_loaded(have: Bool, +typed: String, enter: Bool, +rows: U32, +cols: U32, +click: U32, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +url: String, +clipboard: String, +loaded: WsLoaded, ui: T.Ui, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +path: String, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool) -> IO(Unit):
  match loaded:
    case WsLoaded{+ws, +lp, +known}:
      ws_wait.done_have(have, typed, enter, rows, cols, click, key, mods, codepoint, wheel, url, clipboard, ws, lp, known, ui, rc, options, path, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls)

def ws_wait.done(+hold: WsHold, +loaded: WsLoaded, ui: T.Ui, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +path: String, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool) -> IO(Unit):
  match hold:
    case WsHold{have, +typed, enter, +rows, +cols, +click, +key, +mods, +codepoint, +wheel, +url, +clipboard}:
      ws_wait.done_loaded(have, typed, enter, rows, cols, click, key, mods, codepoint, wheel, url, clipboard, loaded, ui, rc, options, path, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls)

# `k` continues the wait. Quit leaves before boot. Resize updates the
# painted session immediately. One hot frame is replayed onto the loaded
# session before Begin; a keyless wake only contributes its size.
def ws_wait.step_key(halt: Bool, +hold: WsHold, ui: T.Ui, +ws: W.Workspace, +scheduled: Bool, +consumed: Bool, +more: Bool, +main: Chan(WsMsg), k: (T.Ui & WsWait) -> IO(Unit)) -> IO(Unit):
  match halt:
    case True{}: Net.shutdown_finish(ui, True{})
    case False{}:
      do IO<Unit>:
        scheduled2 : Bool <- ws_more(scheduled, consumed, more, main)
        k((ui, WsWait{ws, hold, scheduled2}))

def ws_wait.step(keys: T.UiKeys, ui: T.Ui, +ws: W.Workspace, +prev: WsHold, +scheduled: Bool, +consumed: Bool, +main: Chan(WsMsg), k: (T.Ui & WsWait) -> IO(Unit)) -> IO(Unit):
  match keys:
    case T.UiKeys{enter, +typed, +rows, +cols, +click, +key, +mods, +codepoint, +wheel, more, +url, +clipboard}:
      +enter_b = T.flag_on(enter)
      +changed = Bool.not(String.eq(typed, Sess.session_draft(W.current_session(ws))))
      +hot = ws_hold.hot(enter_b, key, codepoint, wheel, click, url, clipboard, changed)
      +next : WsHold = WsHold{hot, typed, enter_b, rows, cols, click, key, mods, codepoint, wheel, url, clipboard}
      +hold = ws_hold.keep(hot, prev, next)
      +sized = W.set_current_size(ws, rows, cols)
      ws_wait.step_key(ws_wait.quit_pol(Sess.key_pol_for(W.current_session(ws), key, mods, codepoint, wheel, rows)), hold, ui, sized, scheduled, consumed, T.flag_on(more), main, k)

def ws_wait.painted(got: T.Ui & T.UiKeys, +ws: W.Workspace, +prev: WsHold, +scheduled: Bool, +consumed: Bool, +main: Chan(WsMsg), k: (T.Ui & WsWait) -> IO(Unit)) -> IO(Unit):
  match got:
    case (ui, keys): ws_wait.step(keys, ui, ws, prev, scheduled, consumed, main, k)

def ws_wait.paint(is_key: Bool, ui: T.Ui, +ws: W.Workspace, +hold: WsHold, +scheduled: Bool, +consumed: Bool, +ack: Chan(Unit), +main: Chan(WsMsg), k: (T.Ui & WsWait) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- Net.paint_session(ui, W.paint_session(ws, 0))
    Unit <- Net.ack_key(is_key, ack)
    ws_wait.painted(got, ws, hold, scheduled, consumed, main, k)

def ws_wait.ui(m: Sess.UiMsg, ui: T.Ui, +ws: W.Workspace, +hold: WsHold, +scheduled: Bool, +ack: Chan(Unit), +main: Chan(WsMsg), k: (T.Ui & WsWait) -> IO(Unit)) -> IO(Unit):
  match m:
    case Sess.UiKey{}: ws_wait.paint(True{}, ui, ws, hold, scheduled, False{}, ack, main, k)
    case Sess.UiContinue{}: ws_wait.paint(False{}, ui, ws, hold, scheduled, True{}, ack, main, k)
    case _: ws_wait.paint(False{}, ui, ws, hold, scheduled, False{}, ack, main, k)

def ws_wait.msg(wmsg: WsMsg, ui: T.Ui, +ws: W.Workspace, +hold: WsHold, +scheduled: Bool, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool, k: (T.Ui & WsWait) -> IO(Unit)) -> IO(Unit):
  match wmsg:
    case WsReady{+loaded, +path}:
      ws_wait.done(hold, loaded, ui, rc, options, path, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls)
    case WsUi{m}:
      ws_wait.ui(m, ui, ws, hold, scheduled, ack, main, k)
    case _: k((ui, WsWait{ws, hold, scheduled}))

def ws_wait.got(g: Maybe<&1, WsMsg>, ui: T.Ui, +ws: W.Workspace, +hold: WsHold, +scheduled: Bool, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool, k: (T.Ui & WsWait) -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: Net.shutdown_finish(ui, True{})
    case Some{wmsg}: ws_wait.msg(wmsg, ui, ws, hold, scheduled, rc, options, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls, k)

@unsafe
def ws_wait(acc: T.Ui & WsWait, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +nick: String, +force_tls: Bool) -> IO(Unit):
  match acc:
    case (ui, +wait):
      match wait:
        case WsWait{+ws, +hold, +scheduled}:
          do IO<Unit>:
            g : Maybe<&1, WsMsg> <- Chan.recv(WsMsg, main)
            ws_wait.got(g, ui, ws, hold, scheduled, rc, options, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls, nxt => ws_wait(nxt, rc, options, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls))

def ws_start.arm_win(wr: Result<&1, &1, U32 & String, T.Winch>, tty: T.Tty, ui: T.Ui, +ws: W.Workspace, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +ui_evt: Chan(Sess.UiMsg), +nick: String, +force_tls: Bool) -> IO(Unit):
  match wr:
    case Fail{e}: Net.watch_die_tty(e, tty, ui)
    case Done{w}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, Net.tty_watch(tty, ui_evt, ack))
        Unit <- IO.spawn(Unit, Net.winch_watch(w, ui_evt))
        Unit <- IO.spawn(Unit, ui_fwd(ui_evt, main))
        Unit <- IO.spawn(Unit, ws_load.worker(ws, options, main))
        ws_wait((ui, WsWait{ws, ws_hold0(), False{}}), rc, options, deferred, main, cmds, evts, pevts, ack, frames, nick, force_tls)

def ws_start.arm_tty(pair: T.Ui & Result<&1, &1, U32 & String, T.Tty>, +ws: W.Workspace, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +ui_evt: Chan(Sess.UiMsg), +nick: String, +force_tls: Bool, wr: Result<&1, &1, U32 & String, T.Winch>) -> IO(Unit):
  match pair:
    case (ui, tr):
      match tr:
        case Fail{e}: Net.watch_die_win(wr, e, ui)
        case Done{tty}: ws_start.arm_win(wr, tty, ui, ws, rc, options, deferred, main, cmds, evts, pevts, ack, frames, ui_evt, nick, force_tls)

def ws_start.arm(ui: T.Ui, +ws: W.Workspace, +rc: Sid.RoutedCmd, +options: PrefWorker.Options, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +ui_evt: Chan(Sess.UiMsg), +nick: String, +force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    wr : Result<&1, &1, U32 & String, T.Winch> <- T.Winch.open()
    pair : T.Ui & Result<&1, &1, U32 & String, T.Tty> <- T.Timui.tty(ui)
    ws_start.arm_tty(pair, ws, rc, options, deferred, main, cmds, evts, pevts, ack, frames, ui_evt, nick, force_tls, wr)

def ws_start.keyed(first: T.Ui & W.Workspace & Sid.RoutedCmd & Bool, +options: PrefWorker.Options, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +ui_evt: Chan(Sess.UiMsg), +nick: String, +force_tls: Bool) -> IO(Unit):
  match first:
    case (ui, +ws_keyed, +rc, halt):
      match halt:
        case True{}: Net.shutdown_finish(ui, True{})
        case False{}: ws_start.arm(ui, ws_keyed, rc, options, deferred, main, cmds, evts, pevts, ack, frames, ui_evt, nick, force_tls)

def ws_measure.apply(got: T.Ui & U32 & U32, +ws: W.Workspace) -> T.Ui & W.Workspace:
  match got:
    case (ui, rc):
      match rc:
        case (+rows, cols): (ui, W.set_current_size(ws, rows, cols))

def ws_start.measured(got: T.Ui & W.Workspace, +options: PrefWorker.Options, +deferred: Bool, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +ui_evt: Chan(Sess.UiMsg), +nick: String, +force_tls: Bool) -> IO(Unit):
  match got:
    case (ui, +ws1):
      do IO<Unit>:
        first : T.Ui & W.Workspace & Sid.RoutedCmd & Bool <- ws_first.frame(ui, ws1, evts)
        ws_start.keyed(first, options, deferred, main, cmds, evts, pevts, ack, frames, ui_evt, nick, force_tls)

def ws_start.prepared(support: T.Ui & U32, +options: PrefWorker.Options, +ws0: W.Workspace, +main: Chan(WsMsg), +cmds: WsCmds, +evts: WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +frames: U32, +ui_evt: Chan(Sess.UiMsg), +host: String, +port: U32, +extra: List<&2, Ep.Endpoint>, +nick: String, +force_tls: Bool) -> IO(Unit):
  match support:
    case (ui, +flag):
      +deferred = ws_policy(options)
      +ws1 = W.set_media_supported(ws_epoch(ws0, deferred), T.flag_on(flag))
      do IO<Unit>:
        got : T.Ui & U32 & U32 <- T.Timui.measure(ui)
        ws_start.measured(ws_measure.apply(got, ws1), options, deferred, main, cmds, evts, pevts, ack, frames, ui_evt, nick, force_tls)

def ws_start.go(+main: Chan(WsMsg), ui_evt: Chan(Sess.UiMsg), ack: Chan(Unit), c0: Chan(Sess.NetCmd), c1: Chan(Sess.NetCmd), c2: Chan(Sess.NetCmd), c3: Chan(Sess.NetCmd), e0: Chan(Sess.UiMsg), e1: Chan(Sess.UiMsg), e2: Chan(Sess.UiMsg), e3: Chan(Sess.UiMsg), +pevts: Chan(Sess.UiMsg), +frames: U32, +host: String, +port: U32, +extra: List<&2, Ep.Endpoint>, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String, +auth: Args.AuthOptions, +force_tls: Bool) -> IO(Unit):
  +cmds : WsCmds = WsCmds{c0, c1, c2, c3}
  +evts : WsEvts = WsEvts{e0, e1, e2, e3}
  +ws0 : W.Workspace = ws_build.go(extra, W.single_client(host, port, False{}, Net.live_client(Cl.init(nick, host), host, port, sasl_user, sasl_pass, auth), chan), nick, chan, force_tls)
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    support : T.Ui & U32 <- T.Timui.image_supported(ui)
    options : PrefWorker.Options <- PrefWorker.options()
    ws_start.prepared(support, options, ws0, main, cmds, evts, pevts, ack, frames, ui_evt, host, port, extra, nick, force_tls)

def ws_start(+frames: U32, +host: String, +port: U32, +extra: List<&2, Ep.Endpoint>, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String, +auth: Args.AuthOptions, +force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    main : Chan(WsMsg) <- Chan.new(WsMsg, 64)
    ui_evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    c0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    c1 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    c2 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    c3 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    e0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    e1 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    e2 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    e3 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    pevts : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    ws_start.go(main, ui_evt, ack, c0, c1, c2, c3, e0, e1, e2, e3, pevts, frames, host, port, extra, nick, chan, sasl_user, sasl_pass, auth, force_tls)

def ws_tty.zero(+tty: U32, +frames: U32, +host: String, +port: U32, +extra: List<&2, Ep.Endpoint>, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String, +auth: Args.AuthOptions, +force_tls: Bool, headless: Bool) -> IO(Unit):
  match headless:
    case True{}: IO.die(Unit, 2, "birc: multiserver mode needs a tty")
    case False{}: ws_start(frames, host, port, extra, nick, chan, sasl_user, sasl_pass, auth, force_tls)

def run_ws.go(+tty: U32, +frames: U32, +host: String, +port: U32, +extra: List<&2, Ep.Endpoint>, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String, +auth: Args.AuthOptions, +force_tls: Bool) -> IO(Unit):
  ws_tty.zero(tty, frames, host, port, extra, nick, chan, sasl_user, sasl_pass, auth, force_tls, U32.is_zero(tty))

def run_ws(+frames: U32, +host: String, +port: U32, +extra: List<&2, Ep.Endpoint>, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String, +auth: Args.AuthOptions, +force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    tty : U32 <- T.Timui.isatty()
    run_ws.go(tty, frames, host, port, extra, nick, chan, sasl_user, sasl_pass, auth, force_tls)
