# SPDX-License-Identifier: Apache-2.0
# Session <-> Drafts runtime adapter (pure).
#
# ADAPTER BOUNDARY (branch adapter/session-workspace-drafts-multiserver, from
# parent HEAD ca30774): threads one server-scoped per-buffer Drafts store
# through Session key steps. Parent owns merges; this file is new and disjoint
# by construction. FROZEN at parent HEAD (signatures never edited here):
# Drafts, server_key, server_id, ipv6. Session is consumed, never modified:
# every Session effect below delegates to Sess.step_keys, so
# control/query/server scoping, reconnect dividers, global IDs,
# unread/alerts, scroll anchors, the 512-byte wire cap, and SEND_CAP batching
# all keep Session's exact semantics. No copied pipelines.
#
# Wiring contract (D7/D8):
# - Non-enter frames stash the composer-final text under the active buffer
#   key (Drafts.set is fail-safe: a rejected stash keeps the old draft).
# - Tab/click/split-focus moves apply only when Drafts.focus_admits accepts
#   the outgoing stash; a rejected save strips the move keys, so the old
#   active buffer is kept and the composer keeps the typed text. The
#   /focus command is gated the same way with an explicit error echo.
# - An admitted move that changes the active buffer stashes under the old
#   key and reseeds the composer with the next buffer's draft (seed 1).
#   Submit-driven moves (e.g. /join switching active) behave the same.
# - Enter with accepted wire output clears the buffer draft (after_submit);
#   Dial applies replace_endpoint with Session's exact endpoint_same; a
#   rejected submit (a new Error line appears, detected by stable line IDs,
#   never by rendered text) stashes the typed text and reseeds the composer
#   instead of clearing. Accepted local commands clear; unreachable NetCmd
#   arms preserve (fail closed).
# - Enter on multiline chat (RouteMulti, no upload intent, no pending modal)
#   routes through Drafts.submit_lines atomically, then completes through
#   Session's production submit path, so nav/completion/history/plan behavior
#   matches the single-line path. Multiline with any slash-led line is
#   rejected as one unit with Session's reason echo and the draft preserved.
# - Upload-modal-blocked Enter stashes via Drafts.stash_modal; the warning
#   itself never replaces a draft.
# - Draft identity folds under the session's negotiated CASEMAPPING: every
#   store call below passes Sess.session_cm and focus movement compares
#   with Sess.session_cm_eq, so ascii-distinct rooms keep distinct drafts
#   and the composer reseeds across #a[/#a{. Default-map sessions behave
#   exactly as before.
#
# NICK-arrival draft renames on the live inbound path ride fold-carried
# NickRename effects applied in workspace on_routed_chunk (Drafts.rename_cm
# stays pure); out of scope here: Net/Actor IO threading of
# RoutedCmd/RoutedMsg (see workspace.bend for the pure routing side);
# native/PTY qualification.
#
# Layout is bottom-up: Bend forbids same-module forward references, so every
# helper precedes its callers and recursion recurs in the match arm.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client_laws.bend as CL
import ./submit.bend as Sub
import ./split.bend as Sp
import ./session.bend as Sess
import ./upload.bend as Up
import ./drafts.bend as Drafts
import ./server_key.bend as Key
import ./isupport.bend as Isupport

type AD is Data:
  AD{st: Sess.Session, drafts: Drafts.Drafts, server: Key.ServerId}

def wrap(+st: Sess.Session, +server: Key.ServerId) -> AD:
  AD{st, Drafts.empty(), server}

def with_drafts(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId) -> AD:
  AD{st, ds, server}

def ad_session(+ad: AD) -> Sess.Session:
  match ad:
    case AD{+st, _, _}: st

def ad_drafts(+ad: AD) -> Drafts.Drafts:
  match ad:
    case AD{_, +ds, _}: ds

# Canonical key of the active buffer: buffer 0 is the control buffer
# ("*server*", exactly like Split.name_at), every other buffer keeps its
# target name, so a peer query named "server" never collides with control.
def active_key(+cl: Cl.Client) -> String:
  Drafts.key_of(Nat.is_eq(Cl.active_of(cl), 0n), Cl.active_buf_name(cl))

def ad_active(+ad: AD) -> String:
  match ad:
    case AD{+st, _, _}: active_key(Sess.session_cl(st))

def ad_composer(+ad: AD) -> String:
  match ad:
    case AD{+st, _, _}: Sess.session_draft(st)

def ad_seed(+ad: AD) -> U32:
  match ad:
    case AD{+st, _, _}: Sess.session_seed(st)

# ---- move gating ------------------------------------------------------
# Tab-cycle, click-to-buffer, and split-focus (F6/Ctrl-W) keys all change the
# active buffer inside Session nav_after. Gate them as one unit.

def move_requested.click(+tab: Cl.TabDir, +click: Maybe<&2, Nat>, +focus: U32) -> Bool:
  match click:
    case None{}:
      Sess.tab_hot(tab) || Bool.not(U32.is_zero(focus))
    case Some{_}:
      True{}

def move_requested(+keys: Sess.Keys) -> Bool:
  match keys:
    case Sess.Keys{_, _, +tab, +click, _, _, _, _, +focus}:
      move_requested.click(tab, click, focus)

def strip_moves(+keys: Sess.Keys) -> Sess.Keys:
  match keys:
    case Sess.Keys{+typed, +enter, _, _, +up, +dn, +hdir, +comp, _}:
      Sess.Keys{typed, enter, Cl.TabStay{}, None{}, up, dn, hdir, comp, 0}

def split_focus_cmd(cmd: Sp.Command) -> Bool:
  match cmd:
    case Sp.SplitFocus{}: True{}
    case _: False{}

def split_focus_typed(+typed: String) -> Bool:
  split_focus_cmd(Sp.parse(typed))

def split_blocked_msg() -> String:
  "cannot switch buffer: draft exceeds limits"

def keys_typed(+keys: Sess.Keys) -> String:
  match keys:
    case Sess.Keys{+typed, _, _, _, _, _, _, _, _}: typed

def keys_enter(+keys: Sess.Keys) -> Bool:
  match keys:
    case Sess.Keys{_, +enter, _, _, _, _, _, _, _}: enter

# ---- rejection detection ----------------------------------------------
# Session reports submits as NetCmd without an accepted flag. A rejected
# submit always echoes exactly one new Error-kind line (echo_err to the
# active buffer or echo_err_server to buffer 0, including the join-capacity
# hook rewrite); accepted paths never append Error lines. Compare per-buffer
# last-line (id, is-error) by buffer name across the step, keyed on stable
# global line IDs, never on rendered text or timestamps. Cap eviction cannot
# hide a rejection: only the last line per buffer is compared.
# Runs only on enter frames that need the verdict, never on typing frames.

def kind_is_error(kind: Cl.LineKind) -> Bool:
  match kind:
    case Cl.Error{}: True{}
    case Cl.Pending{+inner}: kind_is_error(inner)
    case _: False{}

def line_sig(+line: Cl.Line) -> Nat & Bool:
  match line:
    case Cl.Line{+kind, _, _, _, +id}: (id, kind_is_error(kind))

def last_sig.go(+xs: List<&2, Cl.Line>, acc: Nat & Bool) -> Nat & Bool:
  match xs:
    case Nil{}: acc
    case Con{+h, +t}: last_sig.go(t, line_sig(h))

def last_sig(+xs: List<&2, Cl.Line>) -> Nat & Bool:
  last_sig.go(xs, (0n, False{}))

def find_sig.pick(hit: Bool, found: Nat & Bool, cont: Nat & Bool) -> Nat & Bool:
  match hit:
    case True{}: found
    case False{}: cont

def find_sig.buf(+h: Cl.Buffer, cont: Nat & Bool, +name: String) -> Nat & Bool:
  match h:
    case Cl.Buffer{+stored, _, _, +lines, _, _}:
      find_sig.pick(Irc.ieq(stored, name), last_sig(lines), cont)

def find_sig.go(+xs: List<&2, Cl.Buffer>, +name: String) -> Nat & Bool:
  match xs:
    case Nil{}: (0n, False{})
    case Con{+h, +t}:
      cont = find_sig.go(t, name)
      find_sig.buf(h, cont, name)

def sig_new_error(bsig: Nat & Bool, fsig: Nat & Bool) -> Bool:
  match bsig:
    case (nid, nerr):
      match fsig:
        case (oid, _):
          nerr && Bool.not(Nat.is_eq(nid, oid))

def new_error.go(+after: List<&2, Cl.Buffer>, +before: List<&2, Cl.Buffer>) -> Bool:
  match after:
    case Nil{}: False{}
    case Con{+h, +t}:
      match h:
        case Cl.Buffer{+name, _, _, +lines, _, _}:
          +tail = new_error.go(t, before)
          sig_new_error(last_sig(lines), find_sig.go(before, name)) || tail

def submit_had_error(+before: Cl.Client, +after: Cl.Client) -> Bool:
  new_error.go(Cl.client_bufs(after), Cl.client_bufs(before))

# ---- small predicates ---------------------------------------------------

def outs_empty(+outs: List<&2, String>) -> Bool:
  List.is_empty(&2, String, outs)

def modal_pending(+st: Sess.Session) -> Bool:
  Up.pending(Sess.session_upload(Sess.session_upload_maintain(st)))

# ---- post-step draft settlement (leaves first) ----------------------------

def step_keys.moved_loaded(+st2: Sess.Session, +fds: Drafts.Drafts, +loaded: String, +server: Key.ServerId, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, keep: Bool) -> AD & Sess.NetCmd & Bool:
  match keep:
    case True{}:
      (AD{Sess.session_upload_draft(st2, loaded, 1), fds, server}, cmd, halt)
    case False{}:
      (AD{Sess.session_upload_draft(st2, loaded, 1), Drafts.after_submit_cm(fds, server, cur, Sess.session_cm(st2)), server}, cmd, halt)

def step_keys.moved_load(+st2: Sess.Session, f: Drafts.Drafts & String, +server: Key.ServerId, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, keep: Bool) -> AD & Sess.NetCmd & Bool:
  match f:
    case (fds, loaded):
      step_keys.moved_loaded(st2, fds, loaded, server, cur, cmd, halt, keep)

def step_keys.moved_err(+st2: Sess.Session, f: Drafts.Drafts & String, +server: Key.ServerId, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, err: Bool) -> AD & Sess.NetCmd & Bool:
  match err:
    case True{}: step_keys.moved_load(st2, f, server, cur, cmd, halt, True{})
    case False{}: step_keys.moved_load(st2, f, server, cur, cmd, halt, False{})

# Submit-driven moves commit Session first, so gate atomically before the
# store: when the outgoing stash cannot be admitted, discard the speculative
# Session step and echo the shared gate reason on the old buffer instead of
# installing the command in the destination.
def step_keys.moved_reject(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String) -> AD & Sess.NetCmd & Bool:
  +err = Sess.session_error(st, split_blocked_msg())
  (AD{Sess.session_upload_draft(err, typed, 1), ds, server}, Sess.Cont{Nil{}}, False{})

# The pre-step Session stays in a recursive cell through settlement.
# Only scalar/client comparisons or the actual rollback leaf inspect it.
def step_keys.saved_error(+st: List<&2, Sess.Session>, +after: Cl.Client) -> Bool:
  match st:
    case Nil{}: True{}
    case Con{+before, _}: submit_had_error(Sess.session_cl(before), after)

def step_keys.saved_endpoint_same(+st: List<&2, Sess.Session>, +host: String, +port: U32) -> Bool:
  match st:
    case Nil{}: False{}
    case Con{+before, _}: Sess.endpoint_same(Sess.session_cl(before), host, Sess.session_port(before), port)

def step_keys.moved_reject_saved(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String) -> AD & Sess.NetCmd & Bool:
  match st:
    case Nil{}: (AD{st2, ds, server}, Sess.Cont{Nil{}}, True{})
    case Con{+before, _}: step_keys.moved_reject(before, ds, server, typed)

def step_keys.moved_enter(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +cur: String, +nxt: String, +cmd: Sess.NetCmd, +halt: Bool, admits: Bool) -> AD & Sess.NetCmd & Bool:
  match admits:
    case True{}:
      +err = step_keys.saved_error(st, Sess.session_cl(st2))
      step_keys.moved_err(st2, Drafts.focus_cm(ds, server, cur, typed, nxt, Sess.session_cm(st2)), server, cur, cmd, halt, err)
    case False{}:
      step_keys.moved_reject_saved(st, st2, ds, server, typed)

# The active buffer changed (admitted key move or submit-driven, e.g. /join):
# stash the outgoing text under the old key, then reseed the composer with
# the next buffer's draft. An accepted enter clears the old key; anything
# else keeps the stashed text.
def step_keys.moved_to(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +enter: Bool, +cur: String, +nxt: String, +cmd: Sess.NetCmd, +halt: Bool) -> AD & Sess.NetCmd & Bool:
  match enter:
    case False{}:
      step_keys.moved_load(st2, Drafts.focus_cm(ds, server, cur, typed, nxt, Sess.session_cm(st2)), server, cur, cmd, halt, True{})
    case True{}:
      step_keys.moved_enter(st, st2, ds, server, typed, cur, nxt, cmd, halt, Drafts.focus_admits_cm(ds, server, cur, typed, Sess.session_cm(st2)))

# Wire output means the send was accepted: clear the draft. Empty output is
# either an accepted local command (clear) or a rejected submit (stash the
# typed text and reseed it, so a later stash cannot wipe it with "").
def step_keys.cont_local(+st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, err: Bool) -> AD & Sess.NetCmd & Bool:
  match err:
    case True{}:
      (AD{Sess.session_upload_draft(st2, typed, 1), Drafts.set_cm(ds, server, cur, typed, Sess.session_cm(st2)), server}, cmd, halt)
    case False{}:
      (AD{st2, Drafts.after_submit_cm(ds, server, cur, Sess.session_cm(st2)), server}, cmd, halt)

def step_keys.cont_empty(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, empty: Bool) -> AD & Sess.NetCmd & Bool:
  match empty:
    case False{}:
      (AD{st2, Drafts.after_submit_cm(ds, server, cur, Sess.session_cm(st2)), server}, cmd, halt)
    case True{}:
      +err = step_keys.saved_error(st, Sess.session_cl(st2))
      step_keys.cont_local(st2, ds, server, typed, cur, cmd, halt, err)

def step_keys.cont_enter(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +cur: String, +outs: List<&2, String>, +cmd: Sess.NetCmd, +halt: Bool) -> AD & Sess.NetCmd & Bool:
  +empty = outs_empty(outs)
  step_keys.cont_empty(st, st2, ds, server, typed, cur, cmd, halt, empty)

# Typing (or modal-blocked enter): stash the composer-final text. The modal
# call site is explicit stash_modal; the warning itself never lands in the
# store.
def step_keys.stayed_type(+st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, modal: Bool) -> AD & Sess.NetCmd & Bool:
  match modal:
    case True{}:
      (AD{st2, Drafts.stash_modal_cm(ds, server, cur, Sess.session_draft(st2), Sess.session_cm(st2)), server}, cmd, halt)
    case False{}:
      (AD{st2, Drafts.set_cm(ds, server, cur, Sess.session_draft(st2), Sess.session_cm(st2)), server}, cmd, halt)

def step_keys.stayed_enter(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +cur: String, +cmd: Sess.NetCmd, +halt: Bool) -> AD & Sess.NetCmd & Bool:
  match cmd:
    case Sess.Cont{+outs}:
      step_keys.cont_enter(st, st2, ds, server, typed, cur, outs, cmd, halt)
    case Sess.OpenUrl{_}:
      (AD{st2, Drafts.after_submit_cm(ds, server, cur, Sess.session_cm(st2)), server}, cmd, halt)
    case _:
      (AD{Sess.session_upload_draft(st2, typed, 1), Drafts.set_cm(ds, server, cur, typed, Sess.session_cm(st2)), server}, cmd, halt)

def step_keys.stayed(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +enter: Bool, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, modal: Bool) -> AD & Sess.NetCmd & Bool:
  match enter:
    case False{}: step_keys.stayed_type(st2, ds, server, cur, cmd, halt, modal)
    case True{}: step_keys.stayed_enter(st, st2, ds, server, typed, cur, cmd, halt)

def step_keys.settled(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +enter: Bool, +cur: String, +nxt: String, +cmd: Sess.NetCmd, +halt: Bool, modal: Bool, moved: Bool) -> AD & Sess.NetCmd & Bool:
  match moved:
    case True{}: step_keys.moved_to(st, st2, ds, server, typed, enter, cur, nxt, cmd, halt)
    case False{}: step_keys.stayed(st, st2, ds, server, typed, enter, cur, cmd, halt, modal)

def step_keys.posted(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +enter: Bool, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, +modal: Bool) -> AD & Sess.NetCmd & Bool:
  +nxt = active_key(Sess.session_cl(st2))
  +moved = Bool.not(Sess.session_cm_eq(st2, cur, nxt))
  +eff = enter && Bool.not(modal)
  step_keys.settled(st, st2, ds, server, typed, eff, cur, nxt, cmd, halt, modal, moved)

# Dial carries the endpoint transition: Session already rebuilt the client
# via session_after; the store drops this server's drafts unless Session's
# own exact endpoint_same kept the endpoint (same-endpoint redial). Other
# servers' drafts are never touched.
def step_keys.post(+st: List<&2, Sess.Session>, +st2: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +enter: Bool, +cur: String, +cmd: Sess.NetCmd, +halt: Bool, modal: Bool) -> AD & Sess.NetCmd & Bool:
  match cmd:
    case Sess.Dial{+host, +port, _, _}:
      +same = step_keys.saved_endpoint_same(st, host, port)
      (AD{st2, Drafts.replace_endpoint(ds, server, same), server}, cmd, halt)
    case _:
      step_keys.posted(st, st2, ds, server, typed, enter, cur, cmd, halt, modal)

def step_keys.delegated(+st: List<&2, Sess.Session>, trip: Sess.Session & Sess.NetCmd & Bool, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String, +enter: Bool, +cur: String, modal: Bool) -> AD & Sess.NetCmd & Bool:
  match st:
    case Nil{}:
      match trip:
        case (st2, _, _): (AD{st2, ds, server}, Sess.Cont{Nil{}}, True{})
    case Con{_, _}:
      match trip:
        case (st2, cmd, halt):
          step_keys.post(st, st2, ds, server, typed, enter, cur, cmd, halt, modal)

# ---- key steps ------------------------------------------------------------

def step_keys.enter_route(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +applied: Sess.Keys, +typed: String, +cur: String, modal: Bool) -> AD & Sess.NetCmd & Bool:
  +saved: List<&2, Sess.Session> = [st]
  trip = Sess.step_keys(st, applied)
  step_keys.delegated(saved, trip, ds, server, typed, True{}, cur, modal)

# Route enter frames; typing frames delegate directly without paying for
# route/upload/modal classification.
def step_keys.route(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +applied: Sess.Keys, +typed: String, +enter: Bool, +cur: String) -> AD & Sess.NetCmd & Bool:
  match enter:
    case False{}:
      +saved: List<&2, Sess.Session> = [st]
      trip = Sess.step_keys(st, applied)
      step_keys.delegated(saved, trip, ds, server, typed, False{}, cur, False{})
    case True{}:
      step_keys.enter_route(st, ds, server, applied, typed, cur, modal_pending(st))

def step_keys.stripped(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +keys: Sess.Keys, +typed: String, +enter: Bool, +cur: String, strip: Bool) -> AD & Sess.NetCmd & Bool:
  match strip:
    case True{}: step_keys.route(st, ds, server, strip_moves(keys), typed, enter, cur)
    case False{}: step_keys.route(st, ds, server, keys, typed, enter, cur)

def step_keys.moves(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +keys: Sess.Keys, +typed: String, +enter: Bool, +cur: String) -> AD & Sess.NetCmd & Bool:
  +strip = move_requested(keys) && Bool.not(Drafts.focus_admits_cm(ds, server, cur, typed, Sess.session_cm(st)))
  step_keys.stripped(st, ds, server, keys, typed, enter, cur, strip)

# A /focus the store cannot accept keeps the old active buffer with an
# explicit error echo; drafts stay untouched and the composer keeps the
# typed text (reseeded: native Enter clears its editor).
def step_keys.split_blocked(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +typed: String) -> AD & Sess.NetCmd & Bool:
  +err = Sess.session_error(st, split_blocked_msg())
  (AD{Sess.session_upload_draft(err, typed, 1), ds, server}, Sess.Cont{Nil{}}, False{})

def step_keys.blocked(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +keys: Sess.Keys, +typed: String, +enter: Bool, +cur: String, blocked: Bool) -> AD & Sess.NetCmd & Bool:
  match blocked:
    case True{}: step_keys.split_blocked(st, ds, server, typed)
    case False{}: step_keys.moves(st, ds, server, keys, typed, enter, cur)

def step_keys.gate(+st: Sess.Session, +ds: Drafts.Drafts, +server: Key.ServerId, +keys: Sess.Keys) -> AD & Sess.NetCmd & Bool:
  +typed = keys_typed(keys)
  +enter = keys_enter(keys)
  +cur = active_key(Sess.session_cl(st))
  +blocked = enter && split_focus_typed(typed) && Bool.not(Drafts.focus_admits_cm(ds, server, cur, typed, Sess.session_cm(st)))
  step_keys.blocked(st, ds, server, keys, typed, enter, cur, blocked)

def step_keys(+ad: AD, +keys: Sess.Keys) -> AD & Sess.NetCmd & Bool:
  match ad:
    case AD{+st, +ds, +server}:
      step_keys.gate(st, ds, server, keys)

# ---- stepping helpers (shared with goldens) -----------------------------

def do_step.got(trip: AD & Sess.NetCmd & Bool) -> AD:
  match trip:
    case (ad2, _, _): ad2

def do_step(+ad: AD, +keys: Sess.Keys) -> AD:
  do_step.got(step_keys(ad, keys))

def do_enter(+ad: AD, +line: String) -> AD:
  do_step(ad, Sess.keys_enter(line))

def step_cmd.got(trip: AD & Sess.NetCmd & Bool) -> Sess.NetCmd:
  match trip:
    case (_, cmd, _): cmd

def step_cmd(+ad: AD, +keys: Sess.Keys) -> Sess.NetCmd:
  step_cmd.got(step_keys(ad, keys))

def step_halt.got(trip: AD & Sess.NetCmd & Bool) -> Bool:
  match trip:
    case (_, _, halt): halt

def step_halt(+ad: AD, +keys: Sess.Keys) -> Bool:
  step_halt.got(step_keys(ad, keys))

def typing_keys(+typed: String) -> Sess.Keys:
  Sess.Keys{typed, False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, False{}, 0}

def tab_keys(+typed: String, dir: Cl.TabDir) -> Sess.Keys:
  Sess.Keys{typed, False{}, dir, None{}, 0n, 0n, Sess.HistStay{}, False{}, 0}

def click_keys(+typed: String, +i: Nat) -> Sess.Keys:
  Sess.Keys{typed, False{}, Cl.TabStay{}, Some{i}, 0n, 0n, Sess.HistStay{}, False{}, 0}

def focus_keys(+typed: String) -> Sess.Keys:
  Sess.Keys{typed, False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, False{}, 1}

# ---- proof-facing fixtures and predicates -------------------------------
# Small fixed fixtures (two rooms, short texts) mirroring the golden
# assertions. Nullary like the sibling Drafts/Sid predicates.

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def fx_submitted.got(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl2, _): cl2

def fx_submitted(+cl: Cl.Client, +input: String) -> Cl.Client:
  fx_submitted.got(Sub.submit(cl, input))

def fx_rooms() -> Cl.Client:
  fx_submitted(fx_submitted(Cl.init("me", "irc.example"), "/join #a"), "/join #b")

def fx_demo() -> AD:
  wrap(Sess.session_demo(fx_rooms(), "#a"), s0())

def fx_online() -> Sess.Session:
  Sess.session_online(Sess.session_with_client(fx_rooms(), "#a"))

def fx_modal() -> AD:
  +st = fx_online()
  +scope = Sess.session_upload_scope(st)
  +offered = Up.offer(Up.empty(), scope, Sess.session_upload_online(st), "/tmp/a" <> Nil{})
  wrap(Sess.session_set_upload(st, offered), s0())

def fx_big() -> String:
  Irc.stars.go(4097n)

# Native lay_of boxes recursive Data; seg_open concatenates capture words.
# Keep proof fixture captures narrow without changing the public AD type.
# Every carrier owns an AD; the unused tail only makes its layout recursive.
type FxAD is Data:
  FxAD{value: AD, tail: List<&2, FxAD>}

def fx_ad_box(+ad: AD) -> FxAD:
  FxAD{ad, Nil{}}

def fx_ad_unbox(+boxed: FxAD) -> AD:
  match boxed:
    case FxAD{+ad, _}: ad

def focus_gate_ok() -> Bool:
  +ad = fx_ad_box(do_step(fx_demo(), typing_keys("bb")))
  +moved = fx_ad_box(do_step(fx_ad_unbox(ad), tab_keys("bb", Cl.TabPrev{})))
  +stuck = fx_ad_box(do_step(fx_ad_unbox(ad), tab_keys(fx_big(), Cl.TabPrev{})))
  String.eq(ad_active(fx_ad_unbox(moved)), "#a")
    && String.eq(Drafts.get(ad_drafts(fx_ad_unbox(moved)), s0(), "#b"), "bb")
    && String.eq(ad_composer(fx_ad_unbox(moved)), "")
    && U32.is_eq(ad_seed(fx_ad_unbox(moved)), 1)
    && String.eq(ad_active(fx_ad_unbox(stuck)), "#b")
    && String.eq(ad_composer(fx_ad_unbox(stuck)), fx_big())
    && String.eq(Drafts.get(ad_drafts(fx_ad_unbox(stuck)), s0(), "#b"), "bb")

def split_gate_ok() -> Bool:
  +ad = fx_ad_box(do_enter(fx_demo(), "/split #a"))
  +f6 = fx_ad_box(do_step(fx_ad_unbox(ad), focus_keys("")))
  +stuck = fx_ad_box(do_step(fx_ad_unbox(ad), focus_keys(fx_big())))
  +cmd = fx_ad_box(do_enter(fx_ad_unbox(ad), "/focus"))
  String.eq(ad_active(fx_ad_unbox(f6)), "#a")
    && String.eq(ad_active(fx_ad_unbox(stuck)), "#b")
    && String.eq(ad_composer(fx_ad_unbox(stuck)), fx_big())
    && String.eq(Drafts.get(ad_drafts(fx_ad_unbox(stuck)), s0(), "#b"), "")
    && String.eq(ad_active(fx_ad_unbox(cmd)), "#a")

def endpoint_replace_ok() -> Bool:
  +ad = fx_ad_box(do_step(fx_demo(), typing_keys("bb")))
  +moved = fx_ad_box(do_enter(fx_ad_unbox(ad), "/connect other.example 6697"))
  +same = fx_ad_box(do_enter(fx_ad_unbox(ad), "/connect irc.example 6697"))
  Bool.not(Drafts.has(ad_drafts(fx_ad_unbox(moved)), s0(), "#b"))
    && Drafts.has(ad_drafts(fx_ad_unbox(same)), s0(), "#b")

def submit_clear_ok() -> Bool:
  +ad = fx_ad_box(do_step(fx_demo(), typing_keys("hello")))
  +sent = fx_ad_box(do_enter(fx_ad_unbox(ad), "hello"))
  +rej = fx_ad_box(do_enter(fx_ad_unbox(ad), "/reconnect"))
  Bool.not(Drafts.has(ad_drafts(fx_ad_unbox(sent)), s0(), "#b"))
    && String.eq(ad_composer(fx_ad_unbox(sent)), "")
    && String.eq(Drafts.get(ad_drafts(fx_ad_unbox(rej)), s0(), "#b"), "/reconnect")
    && String.eq(ad_composer(fx_ad_unbox(rej)), "/reconnect")

def multiline_ok() -> Bool:
  +sent = fx_ad_box(do_enter(fx_demo(), "aa\nbb"))
  +bad = fx_ad_box(do_enter(fx_demo(), "hi\n/quit"))
  Bool.not(Drafts.has(ad_drafts(fx_ad_unbox(sent)), s0(), "#b"))
    && String.eq(ad_composer(fx_ad_unbox(sent)), "")
    && String.eq(Drafts.get(ad_drafts(fx_ad_unbox(bad)), s0(), "#b"), "hi\n/quit")
    && String.eq(ad_composer(fx_ad_unbox(bad)), "hi\n/quit")
    && Bool.not(step_halt(fx_demo(), Sess.keys_enter("hi\n/quit")))

def modal_stash_ok() -> Bool:
  +ad = fx_ad_box(do_enter(fx_modal(), "typed text"))
  String.eq(Drafts.get(ad_drafts(fx_ad_unbox(ad)), s0(), "#b"), "typed text")
    && String.eq(ad_composer(fx_ad_unbox(ad)), "typed text")

def s2_nouts(+cmd: Sess.NetCmd) -> Nat:
  match cmd:
    case Sess.Cont{+outs}: List.length(&2, String, outs)
    case _: 999n

def s2_outs(+cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Cont{+outs}: String.join(outs, "|")
    case _: "[noncont]"

def s2_with_net(net: Sess.NetState) -> AD:
  wrap(Sess.session_set_net(Sess.session_with_client(fx_rooms(), "#a"), net), s0())

def s2_cl(+ad: AD) -> Cl.Client:
  Sess.session_cl(ad_session(ad))

def s4_fill(n: Nat, +ds: Drafts.Drafts) -> Drafts.Drafts:
  match n:
    case 0n: ds
    case 1n+p: s4_fill(p, Drafts.set(ds, s0(), "b" ++ Irc.stars.go(Drafts.count(ds)), "x"))

def s4_full() -> AD:
  with_drafts(Sess.session_demo(fx_rooms(), "#a"), s4_fill(16n, Drafts.empty()), s0())

def s5_hist.hist(+hist: Sess.Hist) -> String:
  match hist:
    case Sess.Hist{lines, _}: String.join(lines, "|")

def s5_hist.st(+st: Sess.Session) -> String:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, hist, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: s5_hist.hist(hist)

def s5_hist(+ad: AD) -> String:
  s5_hist.st(ad_session(ad))

def s5_hist_len.hist(+hist: Sess.Hist) -> Nat:
  Sess.hist_len(hist)

def s5_hist_len.st(+st: Sess.Session) -> Nat:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, hist, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: s5_hist_len.hist(hist)

def s5_hist_len(+ad: AD) -> Nat:
  s5_hist_len.st(ad_session(ad))

def hist_prev_keys() -> Sess.Keys:
  Sess.Keys{"", False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistPrev{}, False{}, 0}

def disconnected_multiline_ok() -> Bool:
  +conn = do_enter(s2_with_net(Sess.Connecting{}), "aa\nbb")
  +recon = do_enter(s2_with_net(Sess.Reconnecting{}), "aa\nbb")
  +off = do_enter(s2_with_net(Sess.Offline{}), "aa\nbb")
  +stop = do_enter(s2_with_net(Sess.Stopping{True{}}), "aa\nbb")
  +on = do_enter(wrap(fx_online(), s0()), "aa\nbb")
  +demo = do_enter(fx_demo(), "aa\nbb")
  Nat.is_eq(s2_nouts(step_cmd(s2_with_net(Sess.Connecting{}), Sess.keys_enter("aa\nbb"))), 0n)
    && Bool.not(String.contains(CL.buf_texts(s2_cl(conn), 2n), "aa"))
    && Bool.not(String.contains(CL.buf_texts(s2_cl(conn), 2n), "bb"))
    && String.eq(Drafts.get(ad_drafts(conn), s0(), "#b"), "aa\nbb")
    && Nat.is_eq(s2_nouts(step_cmd(s2_with_net(Sess.Reconnecting{}), Sess.keys_enter("aa\nbb"))), 0n)
    && String.eq(Drafts.get(ad_drafts(recon), s0(), "#b"), "aa\nbb")
    && Nat.is_eq(s2_nouts(step_cmd(s2_with_net(Sess.Offline{}), Sess.keys_enter("aa\nbb"))), 0n)
    && String.eq(Drafts.get(ad_drafts(off), s0(), "#b"), "aa\nbb")
    && Nat.is_eq(s2_nouts(step_cmd(s2_with_net(Sess.Stopping{True{}}), Sess.keys_enter("aa\nbb"))), 0n)
    && String.eq(Drafts.get(ad_drafts(stop), s0(), "#b"), "aa\nbb")
    && Nat.is_eq(s2_nouts(step_cmd(wrap(fx_online(), s0()), Sess.keys_enter("aa\nbb"))), 2n)
    && String.eq(s2_outs(step_cmd(wrap(fx_online(), s0()), Sess.keys_enter("aa\nbb"))), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    && Bool.not(Drafts.has(ad_drafts(on), s0(), "#b"))
    && Nat.is_eq(s2_nouts(step_cmd(fx_demo(), Sess.keys_enter("aa\nbb"))), 2n)
    && String.eq(s2_outs(step_cmd(fx_demo(), Sess.keys_enter("aa\nbb"))), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    && String.eq(CL.buf_texts(s2_cl(demo), 2n), "<me> aa|<me> bb|")
    && Bool.not(Drafts.has(ad_drafts(demo), s0(), "#b"))

def submit_focus_atomic_ok() -> Bool:
  +full = s4_full()
  +rej = do_enter(full, "/query bob hello")
  +seeded = with_drafts(ad_session(fx_demo()), Drafts.set(ad_drafts(fx_demo()), s0(), "bob", "prior"), s0())
  +admit = do_enter(seeded, "/query bob")
  +bare = do_enter(full, "/query alice")
  +admit_bare = do_enter(fx_demo(), "/query carol")
  String.eq(ad_active(rej), "#b")
    && Bool.not(CL.has_buf(s2_cl(rej), "bob"))
    && Nat.is_eq(s2_nouts(step_cmd(full, Sess.keys_enter("/query bob hello"))), 0n)
    && String.contains(CL.buf_texts(s2_cl(rej), 2n), "cannot switch buffer")
    && String.eq(ad_active(admit), "bob")
    && Bool.not(Drafts.has(ad_drafts(admit), s0(), "#b"))
    && String.eq(ad_composer(admit), "prior")
    && String.eq(ad_active(bare), "#b")
    && String.eq(ad_composer(bare), "/query alice")
    && Nat.is_eq(s2_nouts(step_cmd(full, Sess.keys_enter("/query alice"))), 0n)
    && Bool.not(CL.has_buf(s2_cl(bare), "alice"))
    && String.eq(CL.buf_texts(s2_cl(bare), 2n), "cannot switch buffer: draft exceeds limits|")
    && String.eq(ad_active(admit_bare), "carol")
    && String.eq(ad_composer(admit_bare), "")
    && Bool.not(Drafts.has(ad_drafts(admit_bare), s0(), "#b"))

def multiline_privacy_ok() -> Bool:
  +q = do_enter(fx_demo(), "/query NickServ")
  +mixed = do_enter(q, "hello\nIDENTIFY hunter2")
  +login = do_enter(q, "hi\nLOGIN acc sekrit")
  +plain = do_enter(fx_demo(), "aa\nbb")
  +blank = do_enter(fx_demo(), "aa\n\nbb")
  +crlf = do_enter(fx_demo(), "aa\r\nbb")
  Nat.is_eq(s2_nouts(step_cmd(q, Sess.keys_enter("hello\nIDENTIFY hunter2"))), 2n)
    && Nat.is_eq(s5_hist_len(mixed), 1n)
    && String.eq(s5_hist(mixed), "/query NickServ")
    && String.eq(CL.buf_texts(s2_cl(mixed), 3n), "<me> hello|<me> [credential command sent]|")
    && String.eq(ad_composer(do_step(mixed, hist_prev_keys())), "/query NickServ")
    && Nat.is_eq(s5_hist_len(login), 1n)
    && String.eq(s5_hist(login), "/query NickServ")
    && String.eq(CL.buf_texts(s2_cl(login), 3n), "<me> hi|<me> [credential command sent]|")
    && Nat.is_eq(s5_hist_len(plain), 1n)
    && String.eq(s5_hist(plain), "aa\nbb")
    && String.eq(ad_composer(do_step(plain, hist_prev_keys())), "aa\nbb")
    && Nat.is_eq(s5_hist_len(blank), 1n)
    && String.eq(s5_hist(blank), "aa\n\nbb")
    && String.eq(ad_composer(do_step(blank, hist_prev_keys())), "aa\n\nbb")
    && Nat.is_eq(s5_hist_len(crlf), 1n)
    && String.eq(s5_hist(crlf), "aa\r\nbb")
    && String.eq(ad_composer(do_step(crlf, hist_prev_keys())), "aa\r\nbb")

def fx_negotiated_dollar() -> AD:
  wrap(Sess.session_set_iso(Sess.session_demo(fx_rooms(), "#a"), Isupport.apply_line(Isupport.defaults(), ":s 005 me CHANTYPES=$ :are supported")), s0())

# Negotiated multiline MODE privacy (7295 addendum): under CHANTYPES=$ a
# rejected multiline carrying a $room key stays out of HistPrev for both
# +k and -k through the actual AD key path, while an ordinary $room mode
# stays recallable. Mirrors the single-line dollar trio via do_enter.
def multiline_negotiated_mode_ok() -> Bool:
  +base = do_enter(fx_negotiated_dollar(), "seed")
  +plus = do_enter(base, "hello\n/mode $room +k s3cret")
  +minus = do_enter(base, "hello\n/mode $room -k s3cret")
  +ordinary = do_enter(base, "hello\n/mode $room +o bob")
  Nat.is_eq(s5_hist_len(base), 1n)
    && String.eq(s5_hist(base), "seed")
    && Nat.is_eq(s2_nouts(step_cmd(base, Sess.keys_enter("hello\n/mode $room +k s3cret"))), 0n)
    && Nat.is_eq(s5_hist_len(plus), 1n)
    && String.eq(s5_hist(plus), "seed")
    && String.eq(ad_composer(do_step(plus, hist_prev_keys())), "seed")
    && String.eq(Drafts.get(ad_drafts(plus), s0(), "#b"), "hello\n/mode $room +k s3cret")
    && String.eq(ad_composer(plus), "hello\n/mode $room +k s3cret")
    && Bool.not(step_halt(base, Sess.keys_enter("hello\n/mode $room +k s3cret")))
    && Nat.is_eq(s2_nouts(step_cmd(base, Sess.keys_enter("hello\n/mode $room -k s3cret"))), 0n)
    && Nat.is_eq(s5_hist_len(minus), 1n)
    && String.eq(s5_hist(minus), "seed")
    && String.eq(ad_composer(do_step(minus, hist_prev_keys())), "seed")
    && Nat.is_eq(s2_nouts(step_cmd(base, Sess.keys_enter("hello\n/mode $room +o bob"))), 0n)
    && Nat.is_eq(s5_hist_len(ordinary), 2n)
    && String.eq(s5_hist(ordinary), "seed|hello\n/mode $room +o bob")
    && String.eq(ad_composer(do_step(ordinary, hist_prev_keys())), "hello\n/mode $room +o bob")

def fx_dollar_active.got(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (cl, Some{i}): Cl.set_active(cl, i)
    case (cl, None{}): cl

def fx_dollar_cl() -> Cl.Client:
  fx_dollar_active.got(Cl.buf_get(fx_rooms(), "$room", True{}, True{}))

def fx_negotiated_active_dollar() -> AD:
  wrap(Sess.session_set_iso(Sess.session_demo(fx_dollar_cl(), "$room"), Isupport.apply_line(Isupport.defaults(), ":s 005 me CHANTYPES=$ :are supported")), s0())

# Negotiated multiline IMPLICIT MODE privacy: with $room resident and
# active, a rejected multiline carrying an implicit key line stays out of
# HistPrev for both +k and -k through the actual AD key path, while an
# implicit ordinary mode stays recallable. Unlike the explicit $room form
# (already caught by the old mode_key_tail fallback), the implicit form
# resolves the target from the active buffer, so only the negotiated iso
# handoff keeps it out: reverting the handoff turns this RED.
def multiline_negotiated_implicit_ok() -> Bool:
  +base = do_enter(fx_negotiated_active_dollar(), "seed")
  +plus = do_enter(base, "/mode +k synthetic-key\nhello")
  +minus = do_enter(base, "/mode -k synthetic-key\nhello")
  +ordinary = do_enter(base, "/mode +o bob\nhello")
  String.eq(Cl.active_buf_name(Sess.session_cl(ad_session(base))), "$room")
    && Nat.is_eq(s5_hist_len(base), 1n)
    && String.eq(s5_hist(base), "seed")
    && Nat.is_eq(s2_nouts(step_cmd(base, Sess.keys_enter("/mode +k synthetic-key\nhello"))), 0n)
    && Nat.is_eq(s5_hist_len(plus), 1n)
    && String.eq(s5_hist(plus), "seed")
    && String.eq(ad_composer(do_step(plus, hist_prev_keys())), "seed")
    && String.eq(Drafts.get(ad_drafts(plus), s0(), "$room"), "/mode +k synthetic-key\nhello")
    && String.eq(ad_composer(plus), "/mode +k synthetic-key\nhello")
    && Bool.not(step_halt(base, Sess.keys_enter("/mode +k synthetic-key\nhello")))
    && Nat.is_eq(s2_nouts(step_cmd(base, Sess.keys_enter("/mode -k synthetic-key\nhello"))), 0n)
    && Nat.is_eq(s5_hist_len(minus), 1n)
    && String.eq(s5_hist(minus), "seed")
    && String.eq(ad_composer(do_step(minus, hist_prev_keys())), "seed")
    && String.eq(Drafts.get(ad_drafts(minus), s0(), "$room"), "/mode -k synthetic-key\nhello")
    && String.eq(ad_composer(minus), "/mode -k synthetic-key\nhello")
    && Nat.is_eq(s2_nouts(step_cmd(base, Sess.keys_enter("/mode +o bob\nhello"))), 0n)
    && Nat.is_eq(s5_hist_len(ordinary), 2n)
    && String.eq(s5_hist(ordinary), "seed|/mode +o bob\nhello")
    && String.eq(ad_composer(do_step(ordinary, hist_prev_keys())), "/mode +o bob\nhello")
