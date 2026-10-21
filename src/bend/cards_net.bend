# SPDX-License-Identifier: Apache-2.0
# Cards worker glue (IO). Thin native-adjacent spawner over Session-retained
# cards state: helper resolution, one bounded worker, and completion
# admission. Never imported by LAWS.bend (foreign IO), exactly like net.bend.
#
# Live wiring: net.bend calls the Session variants below over the one
# Session-retained cards/full state:
# - after every event: cards_stage_session(st, evt) to schedule plus spawn;
# - on Sess.CardFetched: on_card_session(Sess.session_accept_card_result...),
#   then paint when it reports repaint;
# - at paint: append CardsView.overlay_ops to the ops (see cards_view).
# overlay_ops re-validates the stored token against live Media and Client
# on every paint. Cards have no terminal-support gate; only fullscreen does.
#
# Worker budgets mirror the media worker exactly (same worker class):
# the helper owns HTML bounds, the 8s self-alarm, verified HTTPS,
# public-destination checks, and shared-cache ownership; this side only
# bounds stdout/time and posts the exact completion.
import Base
import ./session.bend as Sess
import ./cards.bend as C
import ./links.bend as Links
import ./helper_io.bend as H
import ./media_io.bend as MediaIO

def spec() -> H.Spec:
  H.Spec{"BIRC_CARDS_HELPER", "native", 2800000, 11000}

def cards_enabled.got(result: Result<&1, &1, U32 & String, String>) -> Bool:
  match result:
    case Fail{_}: True{}
    case Done{value}: Bool.not(String.eq(value, "off"))

# Automatic cards stay opt-out, exactly like automatic image previews.
def cards_enabled() -> IO(Bool):
  do IO<Bool>:
    result : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_CARDS")
    return cards_enabled.got(result)

def cards_args.pick(remote: Bool, +source: String) -> List<&1, String>:
  match remote:
    case True{}: [source]
    case False{}: ["--local", source]

def cards_args(+source: String) -> List<&1, String>:
  cards_args.pick(Links.is_url_prefix(source), source)

def cards_payload_exit(code: U32, +out: String) -> String:
  Bool.pick(String, U32.is_zero(code), out, "")

def cards_payload_pair(pair: U32 & String) -> String:
  match pair:
    case (+code, +out): cards_payload_exit(code, out)

def cards_payload(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Fail{_}: ""
    case Done{(code, (out, _))}: cards_payload_exit(code, out)

def cards_run.native.local(remote: Bool, +source: String) -> IO(String):
  match remote:
    case True{}:
      do IO<String>:
        pair : U32 & String <- MediaIO.cards_load(0, source)
        return cards_payload_pair(pair)
    case False{}:
      do IO<String>:
        pair : U32 & String <- MediaIO.cards_load(1, source)
        return cards_payload_pair(pair)

def cards_run.native(+source: String) -> IO(String):
  cards_run.native.local(Links.is_url_prefix(source), source)

def cards_run.helper(+source: String) -> IO(String):
  do IO<String>:
    result : Result<&1, &1, U32 & String, U32 & (String & String)> <- H.run(spec(), cards_args(source), "")
    return cards_payload(result)

def cards_run.choose(native: Bool, +source: String) -> IO(String):
  match native:
    case True{}: cards_run.native(source)
    case False{}: cards_run.helper(source)

def cards_run.payload(+source: String) -> IO(String):
  do IO<String>:
    helper : String <- H.name(spec())
    cards_run.choose(String.eq(helper, "native"), source)

# One bounded worker; only its exact completion can release
# ownership (see C.accept / C.complete).
def cards_run(req: C.Request, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match req:
    case C.Request{_, +url, +generation, +ticket}:
      do IO<Unit>:
        payload : String <- cards_run.payload(url)
        _ : Result<&1, &1, Sess.UiMsg, Unit> <- Chan.send(Sess.UiMsg, evt, Sess.CardFetched{generation, ticket, url, payload})
        return Unit{}

def cards_spawn(job: Maybe<&2, C.Request>, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match job:
    case None{}: IO.pure(Unit, Unit{})
    case Some{req}: IO.spawn(Unit, cards_run(req, evt))

# Session production variants over the one retained cards/full state. The
# caller computes admission at completion time against the live client; stale
# results release without storing and report no repaint.
def on_card_session.repaint(+st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, +payload: String) -> Sess.Session & Bool:
  +done = Sess.session_set_cards(st, C.complete(Sess.session_cards(st), Sess.session_cl(st), generation, ticket, url, payload))
  (Sess.session_observe_cards(done), True{})

def on_card_session.stale(+st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String) -> Sess.Session & Bool:
  +done = Sess.session_set_cards(st, C.reject(Sess.session_cards(st), generation, ticket, url))
  (Sess.session_observe_cards(done), False{})

def on_card_session(accepted: Bool, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, +payload: String) -> Sess.Session & Bool:
  match accepted:
    case False{}: on_card_session.stale(st, generation, ticket, url)
    case True{}: on_card_session.repaint(st, generation, ticket, url, payload)

def cards_stage_session.go(pair: C.State & Maybe<&2, C.Request>, +st: Sess.Session, +evt: Chan(Sess.UiMsg)) -> IO(Sess.Session & Maybe<&2, C.Request>):
  match pair:
    case (+next, +job):
      do IO<Sess.Session & Maybe<&2, C.Request>>:
        Unit <- cards_spawn(job, evt)
        return (Sess.session_set_cards(st, next), job)

# Schedule bounded visible work over the exact painted rows, then spawn at most
# one worker. Scheduling alone changes nothing painted, so unlike the media
# stage there is no repaint signal here; completions report it.
def cards_stage_session(+st: Sess.Session, +evt: Chan(Sess.UiMsg)) -> IO(Sess.Session & Maybe<&2, C.Request>):
  +observed = Sess.session_observe_visible_cards(st)
  cards_stage_session.go(C.take_job_allowed(Sess.session_cards_job_allowed(observed),
    C.maintain(Sess.session_cards(observed), Sess.session_cl(observed))), observed, evt)
