# wsnet G2/G4/M1-M3 gate guards: envelope exactness, all-part union with
# native-8 gate, and first-frame key application. The ordering properties
# (first input-bearing frame before settings/archive/Begin; Begin only
# after ws_act; media lease never pruned in ws_post) are structural and
# review-verified at src/bend/wsnet.bend (ws_first.frame, ws_start.keyed,
# ws_start.boot, ws_frame.begun_after, ws_post.prefs); these guards pin
# the pure seams those paths depend on. All synthetic, JS backend.
# Authored-but-NOT-run: source-only until the heavy lane is granted.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/media.bend as M
import ../../src/bend/cards.bend as C
import ../../src/bend/live_context.bend as PrefLive
import ../../src/bend/notify.bend as N
import ../../src/bend/preferences.bend as P
import ../../src/bend/theme.bend as Theme
import ../../src/bend/preferences_live.bend as LP
import ../../src/bend/preferences_runtime.bend as PR
import ../../src/bend/preferences_worker.bend as PrefWorker
import ../../src/bend/startup_headless.bend as Headless
import ../../src/bend/wsnet.bend as WsNet

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

def req_a() -> M.Request:
  M.Request{M.Manual{}, "https://x.test/a.png", 1n, 1n}

def req_a_ticket2() -> M.Request:
  M.Request{M.Manual{}, "https://x.test/a.png", 1n, 2n}

def lease_a0() -> WsNet.WsMedia:
  WsNet.WsMedia{s1(), 0, req_a()}

def show_u32s.go(+xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+h, +t}: show_u32s.go(t, acc ++ U32.show(h) ++ ",")

def show_u32s(+xs: List<&2, U32>) -> String:
  show_u32s.go(xs, "")

def ready1(+url: String, +token: U32) -> M.MediaReady:
  M.MediaReady{M.Manual{}, url, token}

def media_with(+ready: List<&2, M.MediaReady>) -> M.State:
  M.State{True{}, 1n, 1n, None{}, Nil{}, ready, M.Supported{}}

def st_with(+ready: List<&2, M.MediaReady>) -> Sess.Session:
  Sess.session_set_media(Sess.session_with_client_at(Cl.init("me", "h.example"), "#a", 6697), media_with(ready))

def set_media.got(+got: Maybe<&2, W.Part>, +ws: W.Workspace, +media: M.State) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, +st}:
          W.replace_part(ws, W.Part{id, gen, scope, Sess.session_set_media(st, media)})

def set_media(+ws: W.Workspace, +id: Key.ServerId, +media: M.State) -> W.Workspace:
  set_media.got(W.find_part(ws, id), ws, media)

def two_part_ws() -> W.Workspace:
  W.do_add(W.single_client("h.example", 6697, False{}, Cl.init("me", "h.example"), "#a"), "i.example", 6697, False{}, "me", "#b")

type FirstOut is Data:
  FirstOut{ws: W.Workspace, cmd: Sid.RoutedCmd, halt: Bool}

def FirstOut.from.r1(rest: Sid.RoutedCmd & Bool, +ws2: W.Workspace) -> FirstOut:
  match rest:
    case (+cmd, +halt): FirstOut{ws2, cmd, halt}

def FirstOut.from(trip: W.Workspace & Sid.RoutedCmd & Bool) -> FirstOut:
  match trip:
    case (+ws2, rest): FirstOut.from.r1(rest, ws2)

def trip_ws(trip: FirstOut) -> W.Workspace:
  match trip:
    case FirstOut{+ws2, _, _}: ws2

def trip_halt(trip: FirstOut) -> Bool:
  match trip:
    case FirstOut{_, _, halt}: halt

def trip_rc(trip: FirstOut) -> Sid.RoutedCmd:
  match trip:
    case FirstOut{_, +rc, _}: rc

def direct_ws0() -> W.Workspace:
  W.single_client("a.example", 6697, False{}, Cl.init("me", "a.example"), "#a")

def some_cards(+got: Maybe<&2, WsNet.WsCards>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def sidecar0() -> WsNet.WsCards:
  WsNet.WsCards{s0(), 0, C.initial(True{}), C.FullOff{}}

def sidecar_off() -> WsNet.WsCards:
  WsNet.WsCards{s0(), 0, C.State{False{}, 1n, 1n, None{}, Nil{}, Nil{}}, C.FullOff{}}

def fenced_cards(found: C.State & C.Fullscreen) -> Bool:
  match found:
    case (+cs, _): C.enabled(cs)

def seed_found(+got: Maybe<&2, WsNet.WsNotifyPart>) -> Sess.NotifyLive:
  match got:
    case None{}: Sess.notify_live_init(N.off(), 0n)
    case Some{+e}: WsNet.ws_npart.nl(e)

def seed_nl0(+nnot: WsNet.WsNotify) -> Sess.NotifyLive:
  seed_found(WsNet.ws_npart.find(WsNet.ws_notify.parts(nnot), s0()))

def seed_queue0(+nnot: WsNet.WsNotify) -> Nat:
  N.queue_len(Sess.notify_live_queue(seed_nl0(nnot)))

def obs_jobs(pair: WsNet.WsNotify & List<&2, N.Req>) -> Nat:
  match pair:
    case (_, +jobs): List.length(&2, N.Req, jobs)

# The same synthetic alert notifies below its ID, but startup's restored
# high-water seed must keep it silent. Neither path starts a helper.
def notify_before_restore() -> W.Workspace:
  W.single_client("restored.test", 6697, False{}, Cl.init("me", "restored.test"), "#restored")

def notify_restored() -> W.Workspace:
  +cl : Cl.Client = Cl.Client{"me", "restored.test", Cl.server_buf() <> Cl.buf_indexed("#restored", True{}, "", [Cl.Line{Cl.Highlight{}, "12:00:00", "me: synthetic restored alert", "alice", 17n}], Nil{}, Cl.ScrollAt{0n, 0n}) <> Nil{}, 1n, "", Cl.settings0(), Cl.AuthIdle{}, 17n, False{}}
  W.single_client("restored.test", 6697, False{}, cl, "#restored")

def load_opts() -> PrefWorker.Options:
  PrefWorker.Options{True{}, False{}, False{}, False{}}

def stored_on() -> P.Preferences:
  P.Preferences{False{}, False{}, False{}, False{}, 1, False{}, False{}, True{}, Nil{}, Nil{}, True{}, Theme.Dark{}, True{}}

def res_media_on(result: LP.Context & Sess.Session & Bool) -> Bool:
  match result:
    case (_, +st, _): M.enabled(Sess.session_media(st))

def job_hit(pair: M.State & Maybe<&2, M.Request>) -> Bool:
  match pair:
    case (_, +m):
      match m:
        case None{}: False{}
        case Some{_}: True{}

def stale_media() -> M.State:
  M.State{True{}, 2n, 3n, Some{req_a()}, M.Request{M.Manual{}, "https://x.test/new.png", 2n, 2n} <> Nil{}, Nil{}, M.Supported{}}

def stale_st() -> Sess.Session:
  Sess.session_set_media(Sess.session_with_client_at(Cl.init("me", "h.example"), "#a", 6697), stale_media())

def req_b() -> M.Request:
  M.Request{M.Manual{}, "https://x.test/b.png", 1n, 1n}

def st_active_b() -> Sess.Session:
  Sess.session_set_media(Sess.session_with_client_at(Cl.init("me", "h.example"), "#b", 6697), M.State{True{}, 1n, 2n, Some{req_b()}, Nil{}, Nil{}, M.Supported{}})

def b_url() -> String:
  "https://x.test/b.png"

def b_client() -> Cl.Client:
  Cl.Client{"me", "h.example", Cl.server_buf() <> Cl.buf_indexed("#b", True{}, "", [Cl.Line{Cl.Msg{}, "", b_url(), "alice", 1n}], Nil{}, Cl.ScrollAt{0n, 0n}) <> Nil{}, 1n, "", Cl.settings0(), Cl.AuthIdle{}, 1n, False{}}

def b_req() -> M.Request:
  M.Request{M.Inline{1n}, b_url(), 1n, 1n}

def b_active_media() -> M.State:
  M.State{True{}, 1n, 2n, Some{b_req()}, Nil{}, Nil{}, M.Supported{}}

def b_active_st() -> Sess.Session:
  Sess.session_set_media(Sess.session_with_client_at(b_client(), "#b", 6697), b_active_media())

def b_fresh_st() -> Sess.Session:
  Sess.session_with_client_at(b_client(), "#b", 6697)

def b_rejected_st() -> Sess.Session:
  Sess.session_set_media(b_active_st(), M.reject_full(b_active_media(), b_client(), 1n, 1n, b_url()))

def b_wrong_st() -> Sess.Session:
  Sess.session_set_media(b_active_st(), M.reject_full(b_active_media(), b_client(), 1n, 2n, b_url()))

def b_stale_media() -> M.State:
  M.State{True{}, 2n, 3n, Some{b_req()}, M.Request{M.Inline{1n}, "https://x.test/other.png", 2n, 2n} <> Nil{}, Nil{}, M.Supported{}}

def b_stale_st() -> Sess.Session:
  Sess.session_set_media(Sess.session_with_client_at(b_client(), "#b", 6697), b_stale_media())

def b_off_active_st() -> Sess.Session:
  Sess.session_set_media(b_active_st(), M.set_enabled(b_active_media(), False{}))

def b_off_fresh_st() -> Sess.Session:
  Sess.session_set_media(b_fresh_st(), M.set_enabled(Sess.session_media(b_fresh_st()), False{}))

def observed_pending(+st: Sess.Session) -> Nat:
  M.pending_count(Sess.session_media(Sess.session_observe_visible_media(st)))

def observed_job(+st: Sess.Session) -> Bool:
  job_hit(M.take_job(Sess.session_media(Sess.session_observe_visible_media(st))))

def ec_code_loop(+l: WsNet.WsLoop) -> U32:
  match l:
    case WsNet.WsLoop{_, +bell, +scheduled, _, _, _, _, _, _, +begun}:
      U32.add(U32.mul(bell, 4), U32.add(Bool.pick(U32, scheduled, 2, 0), Bool.pick(U32, begun, 1, 0)))

def ec_code(+box: List<&2, WsNet.WsLoop>) -> U32:
  match box:
    case Nil{}: 0
    case Con{+hd, _}: ec_code_loop(hd)

def ec_loop() -> WsNet.WsLoop:
  WsNet.ws_mkloop(two_part_ws(), 7, True{}, PrefLive.initial(PrefWorker.Options{False{},False{},False{},False{}}, W.current_session(two_part_ws()), 0, ""), Some{lease_a0()}, Some{WsNet.WsLease{s0(), 3}}, WsNet.WsLease{s1(), 5} <> Nil{}, WsNet.ws_notify.seed_all(two_part_ws()), WsNet.ws_cards_all.empty(), False{})

# Upload completion keeps the captured origin/generation and stamped Session.
def upload_lease_origin() -> W.Part:
  W.Part{s1(), 43, Sid.Scope{"upload.example", 6667, False{}},
    Sess.session_upload_draft(Sess.session_with_client_at(Cl.set_now(Cl.init("origin", "upload.example"), "origin-old"), "#upload", 6667), "keep upload draft", 17)}

def upload_lease_workspace() -> W.Workspace:
  +ws = W.single_client("decoy.example", 6697, False{}, Cl.set_now(Cl.init("decoy", "decoy.example"), "decoy-old"), "#decoy")
  +ws2 = WsNet.ws_replace(ws, s0(), Sess.session_upload_draft(W.current_session(ws), "decoy draft", 99))
  W.Workspace{upload_lease_origin() <> W.ws_parts(ws2), s0(), W.ws_drafts(ws2), W.ws_retired(ws2)}

def upload_lease_records() -> List<&2, WsNet.WsLease>:
  WsNet.WsLease{s1(), 43} <> Nil{}

def upload_lease_now(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, _, _, +now, _, _, _, _}: now

def upload_lease_stamped() -> Sess.Session:
  Sess.session_set_now(WsNet.ws_part.st(upload_lease_workspace(), s1()), "10:20:30")

# Actual pre-snapshot selector: distinct pre/post markers pin the retained
# Part and Session. These pure guards do not exercise notify or paint IO.
def np_pre() -> W.Part:
  W.Part{s0(), 3, Sid.Scope{"pre.test", 6697, False{}}, Sess.session_upload_draft(Sess.session_with_client_at(Cl.init("old", "pre.test"), "#p", 6697), "old draft", 17)}

def np_post() -> W.Part:
  W.Part{s0(), 7, Sid.Scope{"post.test", 7000, False{}}, Sess.session_upload_draft(Sess.session_with_client_at(Cl.init("new", "post.test"), "#q", 7000), "new draft", 23)}

def np_code(+xs: List<&2, W.Part>) -> String:
  match xs:
    case Nil{}: "nil"
    case Con{W.Part{Key.ServerId{+id}, +gen, Sid.Scope{+host, +port, +v6}, +st}, +tail}:
      Nat.show(id) ++ ":" ++ U32.show(gen) ++ ":" ++ host ++ ":" ++ U32.show(port) ++ ":" ++ Bool.pick(String, v6, "v6", "v4") ++ ":" ++ Cl.nick_of(Sess.session_cl(st)) ++ ":" ++ Cl.server_of(Sess.session_cl(st)) ++ ":" ++ Sess.session_draft(st) ++ ":" ++ U32.show(Sess.session_seed(st)) ++ ";" ++ np_code(tail)

# Preferences guards use the actual post-stage retention and rejection seams.
# No helper is spawned; Runtime's active ticket is an explicit synthetic state.
def prefs_mask() -> PR.Edits:
  PR.Edits{False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}}

def prefs_snapshot() -> P.Preferences:
  P.capture(Cl.init("me", "prefs.test"), True{}, ["#a"])

def prefs_state(+read: Bool, +host: String, +queued: List<&2, PR.Job>) -> PR.State:
  +job : PR.Job = Bool.pick(PR.Job, read, PR.Read{41n, "prefs.test", 6697, 7n, Nil{}}, PR.Write{41n, "prefs.test", 6697, prefs_snapshot()})
  PR.State{host, 6697, 42n, Some{job}, PR.Queue{queued, 0, False{}}, Bool.not(read), False{}, False{}, prefs_snapshot(), prefs_mask(), 7n, False{}, False{}}

def prefs_ctx(state: PR.State) -> PrefLive.Context:
  PrefLive.wrap(PrefLive.Details{LP.wrap(state), PrefLive.Waiting{9, "prefs.test:6697"}, None{}, "synthetic.history", None{}, 73n})

def prefs_runtime.details(value: PrefLive.Details) -> PR.State:
  match value:
    case PrefLive.Details{prefs, _, _, _, _, _}: LP.state(prefs)

def prefs_runtime(ctx: PrefLive.Context) -> PR.State:
  prefs_runtime.details(PrefLive.details(ctx))

def prefs_metadata.details(value: PrefLive.Details) -> Bool:
  match value:
    case PrefLive.Details{_, PrefLive.Waiting{9, "prefs.test:6697"}, None{}, "synthetic.history", None{}, 73n}: True{}
    case _: False{}

def prefs_metadata(ctx: PrefLive.Context) -> Bool:
  prefs_metadata.details(PrefLive.details(ctx))

def prefs_owner(owner: Maybe<&2, WsNet.WsLease>) -> Bool:
  match owner:
    case Some{WsNet.WsLease{Key.ServerId{0n}, 3}}: True{}
    case _: False{}

def prefs_no_owner(owner: Maybe<&2, WsNet.WsLease>) -> Bool:
  match owner:
    case None{}: True{}
    case _: False{}

def prefs_result.ctx(pair: PrefLive.Context & Maybe<&2, WsNet.WsLease>) -> PrefLive.Context:
  match pair:
    case (ctx, _): ctx

def prefs_result.owner(pair: PrefLive.Context & Maybe<&2, WsNet.WsLease>) -> Maybe<&2, WsNet.WsLease>:
  match pair:
    case (_, owner): owner

# Affine result pairs cannot be reused, even when both fields are Data.
# Cache only their Data fields; each inspector consumes a fresh affine pair.
type PrefsResult is Data:
  PrefsResult{ctx: PrefLive.Context, owner: Maybe<&2, WsNet.WsLease>}

def prefs_cached(pair: PrefLive.Context & Maybe<&2, WsNet.WsLease>) -> PrefsResult:
  match pair:
    case (ctx, owner): PrefsResult{ctx, owner}

def prefs_pair(result: PrefsResult) -> PrefLive.Context & Maybe<&2, WsNet.WsLease>:
  match result:
    case PrefsResult{ctx, owner}: (ctx, owner)

def prefs_after_reconnect(m: Sess.UiMsg, +ctx: PrefLive.Context) -> PrefLive.Context & Maybe<&2, WsNet.WsLease>:
  +held = WsNet.ws_lease.prefs_next(Some{WsNet.WsLease{s0(), 3}}, True{}, True{}, s0(), 7)
  +kept = WsNet.ws_prefs.owner(ctx, held, W.Workspace{[np_post()], s0(), W.ws_drafts(direct_ws0()), Nil{}})
  WsNet.ws_prefs.rejected(m, ctx, kept)

def prefs_read_retired(+ctx: PrefLive.Context) -> Bool:
  Bool.not(PrefLive.active(ctx)) && PrefLive.waiting(ctx) && prefs_metadata(ctx)

def prefs_fresh_read(pair: PR.State & Maybe<&2, PR.Job>) -> Bool:
  match pair:
    case (_, Some{PR.Read{42n, "prefs.test", 6697, 7n, _}}): True{}
    case _: False{}

def prefs_next_write(pair: PR.State & Maybe<&2, PR.Job>) -> Bool:
  match pair:
    case (_, Some{PR.Write{42n, "prefs.test", 6697, _}}): True{}
    case _: False{}

def prefs_first_read.state(pair: PR.State & Maybe<&2, PR.Job>) -> PR.State:
  match pair:
    case (state, _): state

def prefs_first_read(+st: Sess.Session) -> PrefLive.Context:
  prefs_ctx(prefs_first_read.state(PR.take(PR.initial(True{}, "prefs.test", 6697, LP.capture(st, 7), Sess.session_channel_revision(st), False{}, False{}, False{}))))

def prefs_stored_changed() -> P.Preferences:
  P.Preferences{False{}, False{}, False{}, False{}, 1, False{}, False{}, False{}, Nil{}, ["#loaded"], True{}, Theme.Dark{}, True{}}

# Split each affine tail while its exact parameter type is still available.
type PrefsCompletion is Data:
  PrefsCompletion{ctx: PrefLive.Context, st: Sess.Session, outs: List<&2, String>, paint: Bool}

def prefs_completion.tail(pair: List<&2, String> & Bool, ctx: PrefLive.Context, st: Sess.Session) -> PrefsCompletion:
  match pair:
    case (outs, paint): PrefsCompletion{ctx, st, outs, paint}

def prefs_completion.session(pair: Sess.Session & List<&2, String> & Bool, ctx: PrefLive.Context) -> PrefsCompletion:
  match pair:
    case (st, rest): prefs_completion.tail(rest, ctx, st)

def prefs_completion(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool) -> PrefsCompletion:
  match result:
    case (ctx, rest): prefs_completion.session(rest, ctx)

def prefs_live_read.got(result: PrefsCompletion) -> Bool:
  match result:
    case PrefsCompletion{+ctx, +st, Nil{}, paint}:
      Bool.not(PrefLive.active(ctx) || PrefLive.waiting(ctx) || M.enabled(Sess.session_media(st)) || Cl.settings_joins(Cl.get_settings(Sess.session_cl(st))))
        && List.contains(~String, ~String.eq, Sess.session_desired_channels(st), "#loaded")
        && Bool.not(List.contains(~String, ~String.eq, Sess.session_desired_channels(st), "#a")) && paint
    case _: False{}

def prefs_live_read(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool) -> Bool:
  prefs_live_read.got(prefs_completion(result))

def prefs_live_saved.got(result: PrefsCompletion) -> Bool:
  match result:
    case PrefsCompletion{ctx, st, Nil{}, paint}: Bool.not(PrefLive.active(ctx)) && String.eq(Sess.session_draft(st), "preserved draft") && paint
    case _: False{}

def prefs_live_saved(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool) -> Bool:
  prefs_live_saved.got(prefs_completion(result))

def prefs_live_wrong.got(result: PrefsCompletion) -> Bool:
  match result:
    case PrefsCompletion{ctx, st, Nil{}, paint}: PrefLive.active(ctx) && String.eq(Sess.session_draft(st), "preserved draft") && Bool.not(paint)
    case _: False{}

def prefs_live_wrong(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool) -> Bool:
  prefs_live_wrong.got(prefs_completion(result))

def prefs_shut_fields(+shut: WsNet.WsShut, wanted_active: Bool, wanted_done: Bool, wanted_owner: Bool) -> Bool:
  match shut:
    case WsNet.WsShut{[Key.ServerId{0n}, Key.ServerId{1n}], +ctx, +st, Key.ServerId{1n}, owner, True{}, 1234, done, _}:
      prefs_metadata(ctx) && String.eq(Sess.session_draft(st), "preserved draft") && U32.is_eq(Sess.session_seed(st), 19)
        && Bool.not(Bool.xor(PrefLive.active(ctx), wanted_active)) && Bool.not(Bool.xor(done, wanted_done))
        && Bool.not(Bool.xor(prefs_owner(owner), wanted_owner))
    case _: False{}

def prefs_shut(m: Sess.UiMsg, ctx: PrefLive.Context, st: Sess.Session, owner: Maybe<&2, WsNet.WsLease>) -> WsNet.WsShut:
  WsNet.ws_shut.reject(m, [s0(), s1()], ctx, st, s1(), owner, True{}, 1234, False{}, False{})

def prefs_shut_no_owner(shut: WsNet.WsShut) -> Bool:
  match shut:
    case WsNet.WsShut{_, _, _, _, None{}, _, _, _, _}: True{}
    case _: False{}

def prefs_shut_failed(shut: WsNet.WsShut) -> Bool:
  match shut:
    case WsNet.WsShut{[Key.ServerId{0n}, Key.ServerId{1n}], +ctx, st, Key.ServerId{1n}, None{}, False{}, 1234, True{}, _}:
      prefs_metadata(ctx) && Bool.not(PrefLive.active(ctx)) && String.eq(Sess.session_draft(st), "preserved draft")
    case _: False{}

def prefs_deadline_done(+shut: WsNet.WsShut) -> Bool:
  match shut:
    case WsNet.WsShut{_, _, _, _, _, _, _, +done, _}: done

def prefs_deadline_hist(+shut: WsNet.WsShut, wanted: Bool) -> Bool:
  Bool.not(Bool.xor(WsNet.ws_shut.deadline_kept(shut), wanted))

# Singleton-list boxes: a live Session/Workspace flattens past the pinned
# 247-word continuation cap after Client.welcomed growth. Boxing keeps bind
# captures narrow (media_history / ws_shutdown_pending idiom); use sites
# unbox transiently. Nil arms are unreachable by construction.
type SBox is Data:
  SBox{cell: List<&2, Sess.Session>}


type WBox is Data:
  WBox{cell: List<&2, W.Workspace>}


type FBox is Data:
  FBox{cell: List<&2, FirstOut>}


type LBox is Data:
  LBox{cell: List<&2, WsNet.WsLoop>}


def sbox(+st: Sess.Session) -> SBox:
  SBox{st <> Nil{}}


def sunbox.cell(+cell: List<&2, Sess.Session>) -> Sess.Session:
  match cell:
    case Con{+st, _}: st
    case Nil{}: Sess.session_with_client_at(Cl.init("me", "h.example"), "#a", 6697)


def sunbox(+b: SBox) -> Sess.Session:
  match b:
    case SBox{+cell}: sunbox.cell(cell)


def wbox(+ws: W.Workspace) -> WBox:
  WBox{ws <> Nil{}}


def wunbox.cell(+cell: List<&2, W.Workspace>) -> W.Workspace:
  match cell:
    case Con{+ws, _}: ws
    case Nil{}: direct_ws0()


def wunbox(+b: WBox) -> W.Workspace:
  match b:
    case WBox{+cell}: wunbox.cell(cell)


def fbox(+trip: FirstOut) -> FBox:
  FBox{trip <> Nil{}}


def funbox.cell(+cell: List<&2, FirstOut>) -> FirstOut:
  match cell:
    case Con{+trip, _}: trip
    case Nil{}: FirstOut{direct_ws0(), Sid.cont_for(s0(), Nil{}), False{}}


def funbox(+b: FBox) -> FirstOut:
  match b:
    case FBox{+cell}: funbox.cell(cell)


def lbox(+loop: WsNet.WsLoop) -> LBox:
  LBox{loop <> Nil{}}


def lunbox.cell(+cell: List<&2, WsNet.WsLoop>) -> List<&2, WsNet.WsLoop>:
  cell


def lunbox(+b: LBox) -> List<&2, WsNet.WsLoop>:
  match b:
    case LBox{+cell}: lunbox.cell(cell)


def prefs_draft_st() -> Sess.Session:
  Sess.session_upload_draft(Sess.session_with_client_at(Cl.init("me", "prefs.test"), "#a", 6697), "preserved draft", 19)

# Preferences guards: one-Part/Session phases so mixed prefs sets never hold
# many live fat binders in one flat environment (ws_shutdown_pending idiom).


# Preferences guards: one-Part/Session phases so mixed prefs sets never hold
# many live fat binders in one flat environment (ws_shutdown_pending idiom).
def prefs_ph_lease() -> IO(Unit):
  +write = prefs_ctx(prefs_state(False{}, "prefs.test", Nil{}))
  +held : Maybe<&2, WsNet.WsLease> = Some{WsNet.WsLease{s0(), 3}}
  +new_ws = wbox(W.Workspace{[np_post()], s0(), W.ws_drafts(direct_ws0()), Nil{}})
  +removed_ws = wbox(W.Workspace{Nil{}, s1(), W.ws_drafts(direct_ws0()), Nil{}})
  do IO<Unit>:
    Unit <- E.must("prefs physical lease survives reconnect", prefs_owner(WsNet.ws_prefs.owner(write, held, wunbox(new_ws))))
    Unit <- E.must("prefs physical lease survives removed origin", prefs_owner(WsNet.ws_prefs.owner(write, held, wunbox(removed_ws))))
    Unit <- E.must("inactive prefs clears physical owner", prefs_no_owner(WsNet.ws_prefs.owner(prefs_ctx(PR.Disabled{}), held, wunbox(new_ws))))
    IO.pure(Unit, Unit{})


def prefs_ph_stale() -> IO(Unit):
  +read = prefs_ctx(prefs_state(True{}, "prefs.test", Nil{}))
  +write = prefs_ctx(prefs_state(False{}, "prefs.test", Nil{}))
  +saved = prefs_cached(prefs_after_reconnect(Sess.PreferencesSaved{41n, 0}, write))
  +loaded = prefs_cached(prefs_after_reconnect(Sess.PreferencesLoaded{41n, Some{stored_on()}, 0}, read))
  do IO<Unit>:
    Unit <- E.must("stale exact Saved retires active ticket", Bool.not(PrefLive.active(prefs_result.ctx(prefs_pair(saved)))) && prefs_no_owner(prefs_result.owner(prefs_pair(saved))) && prefs_metadata(prefs_result.ctx(prefs_pair(saved))))
    Unit <- E.must("stale exact Loaded retires without accepting settings", prefs_read_retired(prefs_result.ctx(prefs_pair(loaded))) && prefs_no_owner(prefs_result.owner(prefs_pair(loaded))))
    Unit <- E.must("stale exact Loaded permits fresh current read", prefs_fresh_read(PR.take(prefs_runtime(prefs_result.ctx(prefs_pair(loaded))))))
    Unit <- E.must("duplicate Saved failure cannot change settled clean state", PR.clean(prefs_runtime(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesSaved{41n, 408}, prefs_result.ctx(prefs_pair(saved)), None{})))))
    IO.pure(Unit, Unit{})


def prefs_ph_wrong() -> IO(Unit):
  +read = prefs_ctx(prefs_state(True{}, "prefs.test", Nil{}))
  +write = prefs_ctx(prefs_state(False{}, "prefs.test", Nil{}))
  +held : Maybe<&2, WsNet.WsLease> = Some{WsNet.WsLease{s0(), 3}}
  +wrong_write = prefs_cached(prefs_after_reconnect(Sess.PreferencesSaved{40n, 408}, write))
  +wrong_read = prefs_cached(prefs_after_reconnect(Sess.PreferencesLoaded{40n, Some{stored_on()}, 408}, read))
  +queued = prefs_ctx(prefs_state(False{}, "prefs.test", [PR.Write{0n, "prefs.test", 6697, prefs_snapshot()}]))
  do IO<Unit>:
    Unit <- E.must("wrong Saved keeps exact physical owner", PrefLive.active(prefs_result.ctx(prefs_pair(wrong_write))) && prefs_owner(prefs_result.owner(prefs_pair(wrong_write))) && PR.clean(prefs_runtime(prefs_result.ctx(prefs_pair(wrong_write)))))
    Unit <- E.must("wrong Loaded keeps exact physical owner", PrefLive.active(prefs_result.ctx(prefs_pair(wrong_read))) && prefs_owner(prefs_result.owner(prefs_pair(wrong_read))) && PR.clean(prefs_runtime(prefs_result.ctx(prefs_pair(wrong_read)))))
    Unit <- E.must("wrong Saved cannot overlap fresh helper", PR.no_job(PR.take(prefs_runtime(prefs_result.ctx(prefs_pair(wrong_write))))))
    Unit <- E.must("wrong Loaded cannot overlap fresh helper", PR.no_job(PR.take(prefs_runtime(prefs_result.ctx(prefs_pair(wrong_read))))))
    Unit <- E.must("wrong completion kind cannot retire Write", PrefLive.active(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesLoaded{41n, None{}, 0}, write, held))))
    Unit <- E.must("wrong completion kind cannot retire Read", PrefLive.active(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesSaved{41n, 0}, read, held))))
    Unit <- E.must("no owner exact Saved still retires physical ticket", Bool.not(PrefLive.active(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesSaved{41n, 0}, write, None{})))))
    Unit <- E.must("no owner exact Loaded still retires physical ticket", prefs_read_retired(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesLoaded{41n, Some{stored_on()}, 0}, read, None{}))))
    Unit <- E.must("retired write releases queued job only after exact completion", prefs_next_write(PR.take(prefs_runtime(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesSaved{41n, 0}, queued, held))))))
    Unit <- E.must("changed endpoint failure retains lost-save status", Bool.not(PR.clean(prefs_runtime(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesSaved{41n, 408}, prefs_ctx(prefs_state(False{}, "other.test", Nil{})), held))))))
    Unit <- E.must("disabled write completion stays inactive", Bool.not(PrefLive.busy(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesSaved{41n, 408}, prefs_ctx(PR.Disabled{}), None{})))))
    Unit <- E.must("disabled read completion stays inactive", Bool.not(PrefLive.busy(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesLoaded{41n, Some{stored_on()}, 408}, prefs_ctx(PR.Disabled{}), None{})))))
    Unit <- E.must("reset read completion cannot restore active job", Bool.not(PrefLive.active(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesLoaded{41n, Some{stored_on()}, 0}, prefs_ctx(PR.clear(prefs_state(True{}, "prefs.test", Nil{}))), None{})))))
    Unit <- E.must("exact stale Saved failure keeps lost-intent status", Bool.not(PR.clean(prefs_runtime(prefs_result.ctx(WsNet.ws_prefs.rejected(Sess.PreferencesSaved{41n, 408}, write, held))))))
    IO.pure(Unit, Unit{})


def prefs_ph_live() -> IO(Unit):
  +read = prefs_ctx(prefs_state(True{}, "prefs.test", Nil{}))
  +write = prefs_ctx(prefs_state(False{}, "prefs.test", Nil{}))
  +st = sbox(prefs_draft_st())
  do IO<Unit>:
    Unit <- E.must("valid first read still applies distinct settings and channels", prefs_live_read(PrefLive.loaded(prefs_first_read(sunbox(st)), sunbox(st), 7, 1n, Some{prefs_stored_changed()}, 0)))
    Unit <- E.must("valid live write failure still retains notice paint", prefs_live_saved(PrefLive.saved(write, sunbox(st), 41n, 408)))
    Unit <- E.must("wrong live read ticket cannot apply or retire", prefs_live_wrong(PrefLive.loaded(read, sunbox(st), 7, 40n, Some{stored_on()}, 408)))
    Unit <- E.must("wrong live write ticket cannot log or retire", prefs_live_wrong(PrefLive.saved(write, sunbox(st), 40n, 408)))
    IO.pure(Unit, Unit{})


def prefs_ph_shut() -> IO(Unit):
  +read = prefs_ctx(prefs_state(True{}, "prefs.test", Nil{}))
  +write = prefs_ctx(prefs_state(False{}, "prefs.test", Nil{}))
  +held : Maybe<&2, WsNet.WsLease> = Some{WsNet.WsLease{s0(), 3}}
  +st = sbox(prefs_draft_st())
  do IO<Unit>:
    Unit <- E.must("shutdown foreign exact Saved retires without changing fields", prefs_shut_fields(prefs_shut(Sess.PreferencesSaved{41n, 0}, write, sunbox(st), held), False{}, True{}, False{}))
    Unit <- E.must("shutdown no-owner exact Saved retires without changing fields", prefs_shut_fields(prefs_shut(Sess.PreferencesSaved{41n, 0}, write, sunbox(st), None{}), False{}, True{}, False{}))
    Unit <- E.must("shutdown foreign wrong Saved keeps active job and wait", prefs_shut_fields(prefs_shut(Sess.PreferencesSaved{40n, 408}, write, sunbox(st), held), True{}, False{}, True{}))
    Unit <- E.must("shutdown foreign exact Loaded retires but keeps fresh-read drain", prefs_shut_fields(prefs_shut(Sess.PreferencesLoaded{41n, Some{stored_on()}, 0}, read, sunbox(st), held), False{}, False{}, False{}))
    Unit <- E.must("shutdown no-owner exact Loaded retires but keeps fresh-read drain", prefs_shut_fields(prefs_shut(Sess.PreferencesLoaded{41n, Some{stored_on()}, 0}, read, sunbox(st), None{}), False{}, False{}, False{}))
    Unit <- E.must("shutdown foreign wrong Loaded keeps active job and wait", prefs_shut_fields(prefs_shut(Sess.PreferencesLoaded{40n, Some{stored_on()}, 408}, read, sunbox(st), held), True{}, False{}, True{}))
    Unit <- E.must("shutdown exact stale failure remains failed without Session effect", prefs_shut_failed(prefs_shut(Sess.PreferencesSaved{41n, 408}, write, sunbox(st), held)))
    Unit <- E.must("shutdown foreign exact Saved clears physical owner to None", prefs_shut_no_owner(prefs_shut(Sess.PreferencesSaved{41n, 0}, write, sunbox(st), held)))
    Unit <- E.must("shutdown no-owner exact Saved stays None", prefs_shut_no_owner(prefs_shut(Sess.PreferencesSaved{41n, 0}, write, sunbox(st), None{})))
    Unit <- E.must("shutdown foreign exact Loaded clears physical owner to None", prefs_shut_no_owner(prefs_shut(Sess.PreferencesLoaded{41n, Some{stored_on()}, 0}, read, sunbox(st), held)))
    Unit <- E.must("shutdown no-owner exact Loaded stays None", prefs_shut_no_owner(prefs_shut(Sess.PreferencesLoaded{41n, Some{stored_on()}, 0}, read, sunbox(st), None{})))
    IO.pure(Unit, Unit{})


def prefs_ph_deadline() -> IO(Unit):
  +write = prefs_ctx(prefs_state(False{}, "prefs.test", Nil{}))
  +st = sbox(prefs_draft_st())
  do IO<Unit>:
    Unit <- E.must("deadline while busy does not sticky-done", Bool.not(prefs_deadline_done(WsNet.ws_shut.deadline_state([s0(), s1()], write, sunbox(st), s1(), 1234, True{}))))
    Unit <- E.must("deadline while idle settles prefs done", prefs_deadline_done(WsNet.ws_shut.deadline_state([s0(), s1()], prefs_ctx(PR.Disabled{}), sunbox(st), s1(), 1234, True{})))
    Unit <- E.must("deadline keeps outstanding history", prefs_deadline_hist(WsNet.ws_shut.deadline_state([s0(), s1()], write, sunbox(st), s1(), 1234, True{}), True{}))
    Unit <- E.must("deadline keeps cleared history false", prefs_deadline_hist(WsNet.ws_shut.deadline_state([s0(), s1()], write, sunbox(st), s1(), 1234, False{}), False{}))
    Unit <- E.must("settle tracks live busy not sticky latch", WsNet.ws_shut.settle(prefs_ctx(PR.Disabled{})) && Bool.not(WsNet.ws_shut.settle(write)))
    IO.pure(Unit, Unit{})

# Preferences guards: sequence phases only after each prefs_ph_* is defined
# (Bend rejects unfilled forward names).


# Preferences guards: sequence phases only after each prefs_ph_* is defined
# (Bend rejects unfilled forward names).
def prefs_guards() -> IO(Unit):
  do IO<Unit>:
    Unit <- prefs_ph_lease()
    Unit <- prefs_ph_stale()
    Unit <- prefs_ph_wrong()
    Unit <- prefs_ph_live()
    Unit <- prefs_ph_shut()
    Unit <- prefs_ph_deadline()
    IO.pure(Unit, Unit{})


def prefs_notice_quiet.got(result: PrefsCompletion, wanted_clean: Bool) -> Bool:
  match result:
    case PrefsCompletion{+ctx, +st, Nil{}, paint}:
      Bool.not(PrefLive.active(ctx) || paint) && String.eq(Sess.session_draft(st), "preserved draft")
        && Nat.is_eq(List.length(&2, Cl.Buffer, Cl.log_buffers(Sess.session_cl(st))), 0n)
        && Bool.not(Bool.xor(PR.clean(prefs_runtime(ctx)), wanted_clean))
    case _: False{}


def prefs_notice_quiet(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool, wanted_clean: Bool) -> Bool:
  prefs_notice_quiet.got(prefs_completion(result), wanted_clean)


def prefs_notice_logged.got(result: PrefsCompletion) -> Bool:
  match result:
    case PrefsCompletion{+ctx, +st, Nil{}, paint}:
      Bool.not(PrefLive.active(ctx)) && String.eq(Sess.session_draft(st), "preserved draft")
        && Nat.is_eq(List.length(&2, Cl.Buffer, Cl.log_buffers(Sess.session_cl(st))), 1n) && paint
    case _: False{}


def prefs_notice_logged(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool) -> Bool:
  prefs_notice_logged.got(prefs_completion(result))


def prefs_global_state(+read: Bool, host: String, port: U32) -> PR.State:
  +snapshot = P.capture(Cl.init("me", "display.test"), True{}, Nil{})
  +job = Bool.pick(PR.Job, read, PR.Read{41n, "", 0, 0n, Nil{}}, PR.Write{41n, "", 0, snapshot})
  PR.State{host, port, 42n, Some{job}, PR.Queue{Nil{}, 0, False{}}, Bool.not(read), False{}, False{}, snapshot, prefs_mask(), 0n, False{}, False{}}


def prefs_fresh_owner(owner: Maybe<&2, WsNet.WsLease>) -> Bool:
  match owner:
    case Some{WsNet.WsLease{Key.ServerId{1n}, 7}}: True{}
    case _: False{}


def prefs_owner_ph_bind() -> IO(Unit):
  +read = prefs_ctx(prefs_state(True{}, "prefs.test", Nil{}))
  +write = prefs_ctx(prefs_state(False{}, "prefs.test", Nil{}))
  +held : Maybe<&2, WsNet.WsLease> = Some{WsNet.WsLease{s0(), 3}}
  +st = sbox(prefs_draft_st())
  do IO<Unit>:
    Unit <- E.must("foreign prefs binding is neither the old owner nor None", Bool.not(prefs_owner(Some{WsNet.WsLease{s1(), 7}})) && Bool.not(prefs_shut_no_owner(WsNet.WsShut{[s0(), s1()], write, sunbox(st), s1(), Some{WsNet.WsLease{s1(), 7}}, True{}, 1234, False{}, False{}})))
    Unit <- E.must("shutdown carried physical owner never retags to current", prefs_owner(WsNet.ws_shut.owner(True{}, write, held, s1(), 7)))
    Unit <- E.must("shutdown fresh physical job takes spawning origin", prefs_fresh_owner(WsNet.ws_shut.owner(False{}, write, held, s1(), 7)))
    Unit <- E.must("shutdown settled physical job clears old binding", prefs_no_owner(WsNet.ws_shut.owner(True{}, prefs_ctx(PR.Disabled{}), held, s1(), 7)))
    Unit <- E.must("shutdown absent carried binding is not invented", prefs_no_owner(WsNet.ws_shut.owner(True{}, write, None{}, s1(), 7)))
    Unit <- E.must("shutdown merely waiting state cannot claim unspawned owner", prefs_no_owner(WsNet.ws_shut.owner(False{}, prefs_ctx(PR.clear(prefs_state(True{}, "prefs.test", Nil{}))), held, s1(), 7)))
    Unit <- E.must("read current requires exact active ticket", PR.read_current(prefs_runtime(read), 41n) && Bool.not(PR.read_current(prefs_runtime(read), 40n)))
    Unit <- E.must("write actual scope requires exact ticket and endpoint", PR.write_at(prefs_runtime(write), 41n, "prefs.test", 6697) && Bool.not(PR.write_at(prefs_runtime(write), 40n, "prefs.test", 6697)) && Bool.not(PR.write_at(prefs_runtime(write), 41n, "other.test", 6697)))
    IO.pure(Unit, Unit{})


def prefs_owner_ph_notice() -> IO(Unit):
  +read = prefs_ctx(prefs_state(True{}, "prefs.test", Nil{}))
  +write = prefs_ctx(prefs_state(False{}, "prefs.test", Nil{}))
  +st = sbox(prefs_draft_st())
  +other = sbox(Sess.session_upload_draft(Sess.session_with_client_at(Cl.init("me", "other.test"), "#a", 6697), "preserved draft", 19))
  +wrong_port = sbox(Sess.session_upload_draft(Sess.session_with_client_at(Cl.init("me", "prefs.test"), "#a", 7000), "preserved draft", 19))
  do IO<Unit>:
    Unit <- E.must("foreign Saved error retires without Session notice", prefs_notice_quiet(PrefLive.saved(write, sunbox(other), 41n, 408), False{}))
    Unit <- E.must("wrong-port Saved error retires without Session notice", prefs_notice_quiet(PrefLive.saved(write, sunbox(wrong_port), 41n, 408), False{}))
    Unit <- E.must("foreign Loaded error retires without Session notice", prefs_notice_quiet(PrefLive.loaded(read, sunbox(other), 7, 41n, None{}, 408), True{}))
    Unit <- E.must("wrong-port Loaded error retires without Session notice", prefs_notice_quiet(PrefLive.loaded(read, sunbox(wrong_port), 7, 41n, None{}, 408), True{}))
    Unit <- E.must("valid original Saved scope retains notice after focus moves", prefs_notice_logged(PrefLive.saved(prefs_ctx(prefs_state(False{}, "other.test", Nil{})), sunbox(st), 41n, 408)))
    Unit <- E.must("valid current Saved error still logs", prefs_notice_logged(PrefLive.saved(write, sunbox(st), 41n, 408)))
    IO.pure(Unit, Unit{})


def prefs_owner_ph_global() -> IO(Unit):
  +global_read = prefs_ctx(prefs_global_state(True{}, "", 0))
  +global_write = prefs_ctx(prefs_global_state(False{}, "", 0))
  +st = sbox(prefs_draft_st())
  +shown_global = sbox(Sess.session_upload_draft(Sess.session_demo(Cl.init("me", "display.test"), "#a"), "preserved draft", 19))
  do IO<Unit>:
    Unit <- E.must("valid global Saved error still logs despite displayed host", prefs_notice_logged(PrefLive.saved(global_write, sunbox(shown_global), 41n, 408)))
    Unit <- E.must("valid gen-zero global Loaded error still logs", prefs_notice_logged(PrefLive.loaded(global_read, sunbox(shown_global), 0, 41n, None{}, 408)))
    Unit <- E.must("wrong global Saved ticket keeps active kind without notice", prefs_live_wrong(PrefLive.saved(global_write, sunbox(shown_global), 40n, 408)))
    Unit <- E.must("wrong global Loaded ticket keeps active kind without notice", prefs_live_wrong(PrefLive.loaded(global_read, sunbox(shown_global), 0, 40n, None{}, 408)))
    Unit <- E.must("wrong global completion kind cannot admit Saved notice", prefs_live_wrong(PrefLive.saved(global_read, sunbox(shown_global), 41n, 408)))
    Unit <- E.must("wrong global completion kind cannot admit Loaded notice", prefs_live_wrong(PrefLive.loaded(global_write, sunbox(shown_global), 0, 41n, None{}, 408)))
    Unit <- E.must("moved global Saved scope retires quietly but preserves loss", prefs_notice_quiet(PrefLive.saved(prefs_ctx(prefs_global_state(False{}, "prefs.test", 6697)), sunbox(st), 41n, 408), False{}))
    Unit <- E.must("moved global Loaded scope retires without current notice", prefs_notice_quiet(PrefLive.loaded(global_read, sunbox(st), 7, 41n, None{}, 408), True{}))
    IO.pure(Unit, Unit{})

# Owner guards: sequence after prefs_owner_ph_* defs.


# Owner guards: sequence after prefs_owner_ph_* defs.
def prefs_owner_guards() -> IO(Unit):
  do IO<Unit>:
    Unit <- prefs_owner_ph_bind()
    Unit <- prefs_owner_ph_notice()
    Unit <- prefs_owner_ph_global()
    IO.pure(Unit, Unit{})

# The pinned native backend permits at most 247 flattened capture words
# per continuation. One giant main holding many live Sessions/Workspaces
# breaches it after Client.welcomed growth; each phase below boxes fat
# captures and main only sequences phases (session_drafts_demo precedent).


# The pinned native backend permits at most 247 flattened capture words
# per continuation. One giant main holding many live Sessions/Workspaces
# breaches it after Client.welcomed growth; each phase below boxes fat
# captures and main only sequences phases (session_drafts_demo precedent).
def ph_upload() -> IO(Unit):
  +ws = wbox(upload_lease_workspace())
  +stamped = sbox(upload_lease_stamped())
  do IO<Unit>:
    Unit <- E.must("upload lease exact origin admitted", WsNet.ws_lease.up_has(upload_lease_records(), s1(), W.part_gen_of(wunbox(ws), s1())))
    Unit <- E.must("upload lease wrong origin refused", Bool.not(WsNet.ws_lease.up_has(upload_lease_records(), s0(), 43)))
    Unit <- E.must("upload lease stale generation refused", Bool.not(WsNet.ws_lease.up_has(upload_lease_records(), s1(), 42)))
    Unit <- E.must("upload lease wrong generation refused", Bool.not(WsNet.ws_lease.up_has(upload_lease_records(), s1(), 44)))
    Unit <- E.must("upload lease missing record refused", Bool.not(WsNet.ws_lease.up_has(Nil{}, s1(), 43)))
    Unit <- E.must("upload lease current decoy not admitted", Key.eq(W.ws_current(wunbox(ws)), s0()) && U32.is_eq(W.part_gen_of(wunbox(ws), s1()), 43) && Bool.not(WsNet.ws_lease.up_has(upload_lease_records(), W.ws_current(wunbox(ws)), W.part_gen_of(wunbox(ws), W.ws_current(wunbox(ws))))))
    Unit <- E.must_eq("upload original timestamp nondefault", upload_lease_now(Sess.session_cl(WsNet.ws_part.st(wunbox(ws), s1()))), "origin-old")
    Unit <- E.must_eq("upload stamped Session timestamp exact", upload_lease_now(Sess.session_cl(sunbox(stamped))), "10:20:30")
    Unit <- E.must_eq("upload stamped Session draft retained", Sess.session_draft(sunbox(stamped)), "keep upload draft")
    Unit <- E.must_eq("upload stamped Session seed retained", U32.show(Sess.session_seed(sunbox(stamped))), "17")
    Unit <- E.must_eq("upload stamped Session origin retained", Cl.server_of(Sess.session_cl(sunbox(stamped))), "upload.example")
    Unit <- E.must_eq("upload current decoy draft is distinct", Sess.session_draft(W.current_session(wunbox(ws))), "decoy draft")
    Unit <- E.must_eq("upload current decoy seed is distinct", U32.show(Sess.session_seed(W.current_session(wunbox(ws)))), "99")
    IO.pure(Unit, Unit{})


def ph_mlease() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("mlease free none", WsNet.ws_mlease.free(None{}))
    Unit <- E.must("mlease free some", Bool.not(WsNet.ws_mlease.free(Some{lease_a0()})))
    Unit <- E.must("req exact", WsNet.ws_mlease.req_match(req_a(), 1n, 1n, "https://x.test/a.png"))
    Unit <- E.must("req wrong ticket", Bool.not(WsNet.ws_mlease.req_match(req_a(), 1n, 2n, "https://x.test/a.png")))
    Unit <- E.must("req wrong url", Bool.not(WsNet.ws_mlease.req_match(req_a(), 1n, 1n, "https://x.test/other.png")))
    Unit <- E.must("req wrong gen", Bool.not(WsNet.ws_mlease.req_match(req_a(), 2n, 1n, "https://x.test/a.png")))
    Unit <- E.must("exact none", Bool.not(WsNet.ws_mlease.exact(None{}, s1(), 1n, 1n, "https://x.test/a.png")))
    Unit <- E.must("exact match", WsNet.ws_mlease.exact(Some{lease_a0()}, s1(), 1n, 1n, "https://x.test/a.png"))
    Unit <- E.must("exact wrong sid", Bool.not(WsNet.ws_mlease.exact(Some{lease_a0()}, s0(), 1n, 1n, "https://x.test/a.png")))
    Unit <- E.must("exact wrong ticket keeps", Bool.not(WsNet.ws_mlease.exact(Some{lease_a0()}, s1(), 1n, 2n, "https://x.test/a.png")))
    Unit <- E.must("live match", WsNet.ws_mlease.live(Some{lease_a0()}, s1(), 0))
    Unit <- E.must("live bumped gen stale", Bool.not(WsNet.ws_mlease.live(Some{lease_a0()}, s1(), 1)))
    Unit <- E.must("live wrong sid", Bool.not(WsNet.ws_mlease.live(Some{lease_a0()}, s0(), 0)))
    Unit <- E.must("live none", Bool.not(WsNet.ws_mlease.live(None{}, s1(), 0)))
    Unit <- E.must("reuse exact retires", WsNet.ws_mlease.exact(Some{lease_a0()}, s1(), 1n, 1n, "https://x.test/a.png"))
    Unit <- E.must("reuse stale no effects", Bool.not(WsNet.ws_mlease.live(Some{lease_a0()}, s1(), 1)))
    IO.pure(Unit, Unit{})


def ph_union() -> IO(Unit):
  +ws2 = wbox(two_part_ws())
  +ws_media = wbox(set_media(set_media(wunbox(ws2), s0(), media_with(ready1("https://x.test/a.png", 11) <> ready1("https://x.test/b.png", 12) <> Nil{})), s1(), media_with(ready1("https://x.test/c.png", 21) <> Nil{})))
  +st0 = sbox(st_with(ready1("https://x.test/a.png", 11) <> Nil{}))
  +big0 : List<&2, M.MediaReady> = ready1("u0", 1) <> ready1("u1", 2) <> ready1("u2", 3) <> ready1("u3", 4) <> ready1("u4", 5) <> Nil{}
  +big1 : List<&2, M.MediaReady> = ready1("v0", 6) <> ready1("v1", 7) <> ready1("v2", 8) <> ready1("v3", 9) <> ready1("v4", 10) <> Nil{}
  +ws_big = wbox(set_media(set_media(wunbox(ws2), s0(), media_with(big0)), s1(), media_with(big1)))
  +st_big0 = sbox(st_with(big0))
  +full8 : List<&2, M.MediaReady> = ready1("a0", 41) <> ready1("a1", 42) <> ready1("a2", 43) <> ready1("a3", 44) <> ready1("a4", 45) <> ready1("a5", 46) <> ready1("a6", 47) <> ready1("a7", 48) <> Nil{}
  +ws_full = wbox(set_media(set_media(wunbox(ws2), s0(), media_with(full8)), s1(), media_with(Nil{})))
  +full7 : List<&2, M.MediaReady> = ready1("b0", 51) <> ready1("b1", 52) <> ready1("b2", 53) <> ready1("b3", 54) <> ready1("b4", 55) <> ready1("b5", 56) <> ready1("b6", 57) <> Nil{}
  +ws_room7 = wbox(set_media(set_media(wunbox(ws2), s0(), media_with(full7)), s1(), media_with(Nil{})))
  +b_active = sbox(st_active_b())
  do IO<Unit>:
    Unit <- E.must_eq("union skip s0 keeps s1", show_u32s(WsNet.ws_media.union_other(W.ws_parts(wunbox(ws_media)), s0(), Nil{})), "21,")
    Unit <- E.must_eq("union skip s1 keeps s0", show_u32s(WsNet.ws_media.union_other(W.ws_parts(wunbox(ws_media)), s1(), Nil{})), "11,12,")
    Unit <- E.must_eq("union tokens origin leads", show_u32s(WsNet.ws_media.union_tokens(wunbox(ws_media), s0(), sunbox(st0), 1n, 1n, "https://x.test/a.png")), "11,21,")
    Unit <- E.must_eq("union full keeps every part", show_u32s(WsNet.ws_media.union_tokens(wunbox(ws_big), s0(), sunbox(st_big0), 1n, 1n, "https://x.test/a.png")), "1,2,3,4,5,6,7,8,9,10,")
    Unit <- E.must("union over native8 has no room", Bool.not(WsNet.ws_media.union_room(wunbox(ws_big), s0(), sunbox(st_big0), 1n, 1n, "https://x.test/a.png")))
    Unit <- E.must("full-native8-admission guard", Bool.not(WsNet.ws_media.union_room(wunbox(ws_full), s1(), sunbox(b_active), 1n, 1n, "https://x.test/b.png")))
    Unit <- E.must("seven owned leaves room", WsNet.ws_media.union_room(wunbox(ws_room7), s1(), sunbox(b_active), 1n, 1n, "https://x.test/b.png"))
    Unit <- E.must("room admits below native8", WsNet.ws_media.union_room(wunbox(ws_media), s0(), sunbox(st0), 1n, 1n, "https://x.test/a.png"))
    IO.pure(Unit, Unit{})


def ph_first() -> IO(Unit):
  +ws2 = wbox(two_part_ws())
  do IO<Unit>:
    Unit <- E.must("tripped quit halts", trip_halt(FirstOut.from(WsNet.ws_first.tripped((wunbox(ws2), Sid.RoutedCmd{s0(), Sess.Cont{Nil{}}}, False{}), wunbox(ws2), 24, 80, 1, "", False{}))))
    Unit <- E.must("tripped quiet continues", Bool.not(trip_halt(FirstOut.from(WsNet.ws_first.tripped((wunbox(ws2), Sid.RoutedCmd{s0(), Sess.Cont{Nil{}}}, False{}), wunbox(ws2), 24, 80, 0, "", False{})))))
    Unit <- E.must("tripped live halt sticks", trip_halt(FirstOut.from(WsNet.ws_first.tripped((wunbox(ws2), Sid.RoutedCmd{s0(), Sess.Cont{Nil{}}}, True{}), wunbox(ws2), 24, 80, 0, "", False{}))))
    Unit <- E.must("first f10 quits", trip_halt(FirstOut.from(WsNet.ws_first.act(wunbox(ws2), "", False{}, 24, 80, 0, Sess.KEY_F10(), 0, 0, 0, False{}, False{}))))
    Unit <- E.must("first f7 cycles", Key.eq(W.ws_current(trip_ws(FirstOut.from(WsNet.ws_first.act(wunbox(ws2), "", False{}, 24, 80, 0, Sess.KEY_F7(), 0, 0, 0, True{}, False{})))), s1()))
    Unit <- E.must("first f7 no halt", Bool.not(trip_halt(FirstOut.from(WsNet.ws_first.act(wunbox(ws2), "", False{}, 24, 80, 0, Sess.KEY_F7(), 0, 0, 0, True{}, False{})))))
    Unit <- E.must("first typing no halt", Bool.not(trip_halt(FirstOut.from(WsNet.ws_first.act(wunbox(ws2), "hi", False{}, 24, 80, 0, 0, 0, 0, 0, False{}, False{})))))
    IO.pure(Unit, Unit{})


def ph_cards() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("sidecar find hit", some_cards(WsNet.ws_cards.find(sidecar0() <> Nil{}, s0())))
    Unit <- E.must("sidecar find miss", Bool.not(some_cards(WsNet.ws_cards.find(sidecar0() <> Nil{}, s1()))))
    Unit <- E.must("sidecar drop", Bool.not(some_cards(WsNet.ws_cards.find(WsNet.ws_cards.drop(sidecar0() <> Nil{}, s0()), s0()))))
    Unit <- E.must("sidecar upsert", some_cards(WsNet.ws_cards.find(WsNet.ws_cards.upsert(Nil{}, sidecar0()), s0())))
    Unit <- E.must("sidecar live keeps", Bool.not(fenced_cards(WsNet.ws_cards.sidecar(sidecar_off() <> Nil{}, s0(), 0, True{}))))
    Unit <- E.must("sidecar stale reset", fenced_cards(WsNet.ws_cards.sidecar(sidecar_off() <> Nil{}, s0(), 1, True{})))
    Unit <- E.must("cards net stopping closed", Bool.not(WsNet.ws_cards.net_ok(Sess.Stopping{False{}})))
    Unit <- E.must("cards net demo open", WsNet.ws_cards.net_ok(Sess.Demo{}))
    IO.pure(Unit, Unit{})


def ph_notify() -> IO(Unit):
  +ws2 = wbox(two_part_ws())
  +before = wbox(notify_before_restore())
  +restored = wbox(notify_restored())
  do IO<Unit>:
    Unit <- E.must_eq("notify seeded silent", Nat.show(obs_jobs(WsNet.ws_notify.observed(WsNet.ws_notify.seed_all(wunbox(ws2)), s0(), 0, WsNet.ws_part.st(wunbox(ws2), s0()), True{}))), "0")
    Unit <- E.must_eq("notify bundle queue empty", Nat.show(seed_queue0(WsNet.ws_notify.seed_all(wunbox(ws2)))), "0")
    Unit <- E.must("notify bundle idle", WsNet.ws_nlease.free(WsNet.ws_notify.lease(WsNet.ws_notify.seed_all(wunbox(ws2)))))
    Unit <- E.must_eq("notify nonempty restored alert notifies below its ID", Nat.show(obs_jobs(WsNet.ws_notify.observed(WsNet.ws_notify.seed_all(wunbox(before)), s0(), 0, W.current_session(wunbox(restored)), True{}))), "1")
    Unit <- E.must_eq("notify restored seed retains exact high-water mark", Nat.show(Sess.notify_live_scanned(seed_nl0(WsNet.ws_notify.seed_all(wunbox(restored))))), "17")
    Unit <- E.must_eq("notify nonempty restored alert stays silent after seeding", Nat.show(obs_jobs(WsNet.ws_notify.observed(WsNet.ws_notify.seed_all(wunbox(restored)), s0(), 0, W.current_session(wunbox(restored)), True{}))), "0")
    IO.pure(Unit, Unit{})


def ph_images_key() -> IO(Unit):
  +ws2 = wbox(two_part_ws())
  +trip_images = fbox(FirstOut.from(WsNet.ws_first.act(wunbox(ws2), "/images off", True{}, 24, 80, 0, 0, 0, 0, 0, False{}, False{})))
  +kst = sbox(W.current_session(trip_ws(funbox(trip_images))))
  +seed0 = sbox(Sess.session_set_media(sunbox(kst), M.initial(WsNet.ws_load.images_on(sunbox(kst), True{}))))
  do IO<Unit>:
    Unit <- E.must("first-key images no halt", Bool.not(trip_halt(funbox(trip_images))))
    Unit <- E.must("first-key images off applies", Bool.not(M.enabled(Sess.session_media(sunbox(kst)))))
    Unit <- E.must("first-key images edit recorded", List.contains(~String, ~String.eq, Sess.session_preference_edits(sunbox(kst)), "images"))
    Unit <- E.must("edited load keeps off over env on", Bool.not(WsNet.ws_load.images_on(sunbox(kst), True{})))
    Unit <- E.must("unedited load keeps env off", Bool.not(WsNet.ws_load.images_on(W.current_session(wunbox(ws2)), False{})))
    Unit <- E.must("unedited load keeps env on", WsNet.ws_load.images_on(W.current_session(wunbox(ws2)), True{}))
    Unit <- E.must("/images-off-survives-load", Bool.not(res_media_on(Headless.resolve(load_opts(), sunbox(seed0), 0, (Some{stored_on()}, 0)))))
    IO.pure(Unit, Unit{})


def ph_stale_m2() -> IO(Unit):
  +stale = sbox(stale_st())
  do IO<Unit>:
    Unit <- E.must("stale active blocks take_job", Bool.not(job_hit(M.take_job(Sess.session_media(sunbox(stale))))))
    Unit <- E.must("stale-done-frees-Part", job_hit(M.take_job(Sess.session_media(WsNet.ws_media.stale_released(sunbox(stale), 1n, 1n, "https://x.test/a.png")))))
    Unit <- E.must("stale release wrong ticket keeps block", Bool.not(job_hit(M.take_job(Sess.session_media(WsNet.ws_media.stale_released(sunbox(stale), 1n, 2n, "https://x.test/a.png"))))))
    IO.pure(Unit, Unit{})


def ph_full8() -> IO(Unit):
  +ws2 = wbox(two_part_ws())
  +full8 : List<&2, M.MediaReady> = ready1("a0", 41) <> ready1("a1", 42) <> ready1("a2", 43) <> ready1("a3", 44) <> ready1("a4", 45) <> ready1("a5", 46) <> ready1("a6", 47) <> ready1("a7", 48) <> Nil{}
  +ws_full = wbox(set_media(set_media(wunbox(ws2), s0(), media_with(full8)), s1(), media_with(Nil{})))
  +b_active = sbox(b_active_st())
  +b_rejected = sbox(b_rejected_st())
  +b_wrong = sbox(b_wrong_st())
  +b_stale = sbox(b_stale_st())
  +b_off_active = sbox(b_off_active_st())
  do IO<Unit>:
    Unit <- E.must("full8-inline-accepts-production", Sess.session_accept_media_result(sunbox(b_active), 1n, 1n, b_url()))
    Unit <- E.must("full8-inline-no-room", Bool.not(WsNet.ws_media.union_room(wunbox(ws_full), s1(), sunbox(b_active), 1n, 1n, b_url())))
    Unit <- E.must_eq("full8-reject-records-failed-identity", Nat.show(M.ready_count(Sess.session_media(sunbox(b_rejected)))), "1")
    Unit <- E.must_eq("full8-reject-holds-no-native-token", Nat.show(List.length(&2, U32, M.retained_tokens(Sess.session_media(sunbox(b_rejected))))), "0")
    Unit <- E.must_eq("full8-observe-suppresses-requeue", Nat.show(observed_pending(sunbox(b_rejected))), "0")
    Unit <- E.must("full8-take-no-relaunch", Bool.not(observed_job(sunbox(b_rejected))))
    Unit <- E.must_eq("full8-wrong-ticket-records-nothing", Nat.show(M.ready_count(Sess.session_media(sunbox(b_wrong)))), "0")
    Unit <- E.must("full8-wrong-ticket-keeps-worker", M.accept(Sess.session_media(sunbox(b_wrong)), b_client(), 1n, 1n, b_url()))
    Unit <- E.must("full8-exact-clears-worker", Bool.not(M.accept(Sess.session_media(sunbox(b_rejected)), b_client(), 1n, 1n, b_url())))
    Unit <- E.must("full8-inline-stale-blocks", Bool.not(job_hit(M.take_job(Sess.session_media(sunbox(b_stale))))))
    Unit <- E.must("full8-inline-stale-frees", job_hit(M.take_job(Sess.session_media(WsNet.ws_media.stale_released(sunbox(b_stale), 1n, 1n, b_url())))))
    Unit <- E.must("full8-inline-stale-wrong-keeps", Bool.not(job_hit(M.take_job(Sess.session_media(WsNet.ws_media.stale_released(sunbox(b_stale), 1n, 2n, b_url()))))))
    Unit <- E.must("full8-images-off-rejects-production", Bool.not(Sess.session_accept_media_result(sunbox(b_off_active), 1n, 1n, b_url())))
    Unit <- E.must_eq("full8-images-off-no-queue", Nat.show(observed_pending(sunbox(b_off_active))), "0")
    Unit <- E.must("full8-images-off-no-launch", Bool.not(observed_job(sunbox(b_off_active))))
    IO.pure(Unit, Unit{})


def ph_seven() -> IO(Unit):
  +ws2 = wbox(two_part_ws())
  +full7 : List<&2, M.MediaReady> = ready1("b0", 51) <> ready1("b1", 52) <> ready1("b2", 53) <> ready1("b3", 54) <> ready1("b4", 55) <> ready1("b5", 56) <> ready1("b6", 57) <> Nil{}
  +ws_room7 = wbox(set_media(set_media(wunbox(ws2), s0(), media_with(full7)), s1(), media_with(Nil{})))
  +b_fresh = sbox(b_fresh_st())
  +b_stale = sbox(b_stale_st())
  +b_off_fresh = sbox(b_off_fresh_st())
  do IO<Unit>:
    Unit <- E.must("seven-inline-room", WsNet.ws_media.union_room(wunbox(ws_room7), s1(), sunbox(b_fresh), 1n, 1n, b_url()))
    Unit <- E.must_eq("seven-observe-enqueues", Nat.show(observed_pending(sunbox(b_fresh))), "1")
    Unit <- E.must("seven-take-launches", observed_job(sunbox(b_fresh)))
    Unit <- E.must("seven-inline-stale-frees", job_hit(M.take_job(Sess.session_media(WsNet.ws_media.stale_released(sunbox(b_stale), 1n, 1n, b_url())))))
    Unit <- E.must("seven-inline-stale-wrong-keeps", Bool.not(job_hit(M.take_job(Sess.session_media(WsNet.ws_media.stale_released(sunbox(b_stale), 1n, 2n, b_url()))))))
    Unit <- E.must_eq("seven-images-off-no-queue", Nat.show(observed_pending(sunbox(b_off_fresh))), "0")
    Unit <- E.must("seven-images-off-no-launch", Bool.not(observed_job(sunbox(b_off_fresh))))
    IO.pure(Unit, Unit{})


def ph_direct() -> IO(Unit):
  +trip_connect = fbox(FirstOut.from(WsNet.ws_first.act(direct_ws0(), "/connect b.example 6697", True{}, 24, 80, 0, 0, 0, 0, 0, False{}, False{})))
  +keyed_b = wbox(trip_ws(funbox(trip_connect)))
  +rc_b = trip_rc(funbox(trip_connect))
  +trip_type = fbox(FirstOut.from(WsNet.ws_first.act(direct_ws0(), "hi", False{}, 24, 80, 0, 0, 0, 0, 0, False{}, False{})))
  +keyed_type = wbox(trip_ws(funbox(trip_type)))
  +rc_type = trip_rc(funbox(trip_type))
  do IO<Unit>:
    Unit <- E.must("direct connect no halt", Bool.not(trip_halt(funbox(trip_connect))))
    Unit <- E.must("direct connect emits B gen1", W.routed_dial_exact(rc_b, s0(), "b.example", 6697, 1, "me"))
    Unit <- E.must("direct rc admitted at keyed part", W.cmd_admitted(wunbox(keyed_b), rc_b))
    Unit <- E.must("direct boot-equivalent holds", WsNet.ws_start.boot_dial_equivalent(wunbox(keyed_b), rc_b))
    Unit <- E.must("direct drops boot-equivalent dial", WsNet.ws_start.drop_boot_dial(False{}, wunbox(keyed_b), rc_b))
    Unit <- E.must("deferred keeps boot dial", Bool.not(WsNet.ws_start.drop_boot_dial(True{}, wunbox(keyed_b), rc_b)))
    Unit <- E.must("direct keeps non-dial", Bool.not(WsNet.ws_start.drop_boot_dial(False{}, wunbox(keyed_type), rc_type)))
    Unit <- E.must("direct keeps foreign dial", Bool.not(WsNet.ws_start.drop_boot_dial(False{}, wunbox(keyed_b), Sid.dial_for(s0(), "c.example", 6697, 1, "me"))))
    Unit <- E.must("direct keeps stale-gen dial", Bool.not(WsNet.ws_start.drop_boot_dial(False{}, wunbox(keyed_b), Sid.dial_for(s0(), "b.example", 6697, 2, "me"))))
    Unit <- E.must("direct keeps unknown-part dial", Bool.not(WsNet.ws_start.drop_boot_dial(False{}, wunbox(keyed_b), Sid.dial_for(s1(), "b.example", 6697, 1, "me"))))
    Unit <- E.must("direct keeps cont", Bool.not(WsNet.ws_start.drop_boot_dial(False{}, wunbox(keyed_b), Sid.cont_for(s0(), Nil{}))))
    Unit <- E.must("direct keeps begin", Bool.not(WsNet.ws_start.drop_boot_dial(False{}, wunbox(keyed_b), Sid.begin_for(s0(), 1))))
    IO.pure(Unit, Unit{})


def ph_env_pre() -> IO(Unit):
  +loop = lbox(ec_loop())
  do IO<Unit>:
    Unit <- E.must("env con roundtrip code", U32.is_eq(ec_code(lunbox(loop)), 30))
    Unit <- E.must("env nil fixed sentinel", U32.is_eq(ec_code(Nil{}), 0))
    Unit <- E.must("pre snapshot Some keeps old part", String.eq(np_code(WsNet.ws_net_painted.pre_parts(Some{np_pre()}, [np_post()])), "0:3:pre.test:6697:v4:old:pre.test:old draft:17;nil"))
    Unit <- E.must("pre snapshot Some is not post", Bool.not(String.eq(np_code(WsNet.ws_net_painted.pre_parts(Some{np_pre()}, [np_post()])), np_code([np_post()]))))
    Unit <- E.must("pre snapshot None exact post fallback", String.eq(np_code(WsNet.ws_net_painted.pre_parts(None{}, [np_post()])), "0:7:post.test:7000:v4:new:post.test:new draft:23;nil"))
    Unit <- E.must("pre snapshot None is not old", Bool.not(String.eq(np_code(WsNet.ws_net_painted.pre_parts(None{}, [np_post()])), np_code([np_pre()]))))
    Unit <- E.must("pre snapshot None keeps exact carrier tail", String.eq(np_code(WsNet.ws_net_painted.pre_parts(None{}, [np_post(), np_pre()])), "0:7:post.test:7000:v4:new:post.test:new draft:23;0:3:pre.test:6697:v4:old:pre.test:old draft:17;nil"))
    Unit <- E.must("pre snapshot Some drops fallback tail", String.eq(np_code(WsNet.ws_net_painted.pre_parts(Some{np_pre()}, [np_post(), np_post()])), np_code([np_pre()])))
    Unit <- E.must("pre snapshot None empty stays empty", String.eq(np_code(WsNet.ws_net_painted.pre_parts(None{}, Nil{})), "nil"))
    Unit <- E.must("pre snapshot Some empty retains old", String.eq(np_code(WsNet.ws_net_painted.pre_parts(Some{np_pre()}, Nil{})), np_code([np_pre()])))
    IO.pure(Unit, Unit{})


def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- ph_upload()
    Unit <- ph_mlease()
    Unit <- ph_union()
    Unit <- ph_first()
    Unit <- ph_cards()
    Unit <- ph_notify()
    Unit <- ph_images_key()
    Unit <- ph_stale_m2()
    Unit <- ph_full8()
    Unit <- ph_seven()
    Unit <- ph_direct()
    Unit <- ph_env_pre()
    Unit <- prefs_guards()
    Unit <- prefs_owner_guards()
    IO.print("wsnet_gates=ok")

