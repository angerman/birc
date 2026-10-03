# SPDX-License-Identifier: Apache-2.0
# Cards worker glue (IO). Thin native-adjacent spawner over the pure
# session_cards.bend policy: helper resolution, one bounded worker, and
# completion admission. Never imported by LAWS.bend (foreign IO), exactly
# like net.bend.
#
# ADAPTER BOUNDARY (branch c8/session-adapter): Net-side half of the
# cards adapter. Parent owns merges; this file is new and disjoint by
# construction. FROZEN at parent HEAD (public signatures never edited
# here): cards.bend, cards.py.
#
# Integrator wiring (3 lines in net.bend after the Session-field merge):
# - after every event: cards_stage(ad, evt) to schedule plus spawn;
# - on Sess.CardFetched: on_card(SC.accept_result(...), ...) then paint
#   when it reports repaint;
# - at paint: append CardsView.overlay_ops to the ops (see cards_view).
# Until then the Sess.CardFetched case in on_msg_go passes through.
#
# Worker budgets mirror the media worker exactly (same worker class):
# the helper owns HTML bounds, the 8s self-alarm, verified HTTPS,
# public-destination checks, and shared-cache ownership; this side only
# bounds stdout/time and posts the exact completion.
import Base
import ./session.bend as Sess
import ./cards.bend as C
import ./session_cards.bend as SC
import ./links.bend as Links

def cards_program.fallback(got: Result<&1, &1, U32 & String, String>) -> String:
  match got:
    case Fail{_}: "birc-cards"
    case Done{+value}: Bool.pick(String, String.is_empty(value), "birc-cards", value)

def cards_program() -> IO(String):
  do IO<String>:
    got : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_CARDS_HELPER")
    return cards_program.fallback(got)

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

def cards_payload(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Fail{_}: ""
    case Done{(code, (out, _))}: Bool.pick(String, U32.is_zero(code), out, "")

# One bounded external worker; only its exact completion can release
# ownership (see SC.accept_result / SC.complete).
def cards_run(req: C.Request, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match req:
    case C.Request{_, +url, +generation, +ticket}:
      do IO<Unit>:
        program : String <- cards_program()
        result : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(program, cards_args(url), "", 2800000, 11000)
        _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.CardFetched{generation, ticket, url, cards_payload(result)})
        return Unit{}

def cards_spawn(job: Maybe<&2, C.Request>, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match job:
    case None{}: IO.pure(Unit, Unit{})
    case Some{req}: IO.spawn(Unit, cards_run(req, evt))

def cards_stage.go(pair: SC.AD & Maybe<&2, C.Request>, +evt: Chan(Sess.UiMsg)) -> IO(SC.AD & Maybe<&2, C.Request>):
  match pair:
    case (ad, +job):
      do IO<SC.AD & Maybe<&2, C.Request>>:
        Unit <- cards_spawn(job, evt)
        return (ad, job)

# Schedule bounded visible work, then spawn at most one worker. Scheduling
# alone changes nothing painted (the queue is invisible), so unlike the
# media stage there is no repaint signal here; completions report it.
def cards_stage(+ad: SC.AD, +evt: Chan(Sess.UiMsg)) -> IO(SC.AD & Maybe<&2, C.Request>):
  cards_stage.go(SC.take_job(SC.observe_visible(ad)), evt)

# Completion admission. The caller supplies SC.accept_result as accepted
# (mirroring on_msg_go for media); stale results release without storing
# and report no repaint, accepted ones land plus repaint.
def on_card.repaint(+ad: SC.AD, +generation: Nat, +ticket: Nat, +url: String, +payload: String) -> SC.AD & Bool:
  (SC.complete(ad, generation, ticket, url, payload), True{})

def on_card.stale(+ad: SC.AD, +generation: Nat, +ticket: Nat, +url: String) -> SC.AD & Bool:
  (SC.reject(ad, generation, ticket, url), False{})

def on_card(accepted: Bool, +ad: SC.AD, +generation: Nat, +ticket: Nat, +url: String, +payload: String) -> SC.AD & Bool:
  match accepted:
    case False{}: on_card.stale(ad, generation, ticket, url)
    case True{}: on_card.repaint(ad, generation, ticket, url, payload)
