# SPDX-License-Identifier: Apache-2.0
# Leaf net/UI messages.
# session.bend keeps its own NetEvt/NetCmd/UiMsg/NetState constructors:
# Bend stores constructors in the declaring file's namespace, so Sess.Dial
# cannot be a re-export. This copy exists so a test that only needs the
# generation guards can import here and skip the Session closure.
# Keep the message types and stamp_current lockstep with session.bend.
import Base
import ./buffer.bend as Cl
import ./upload.bend as Up
import ./preferences.bend as Prefs
import ./history_search.bend as Hs

# Lockstep with session.bend NetEvt/NetCmd/UiMsg/NetState.
type NetEvt is Data:
  Chunk{xs: List<&2, U32>, req: U32}
  Eof{}
  WriterDone{}
  Up{}
  NetFail{msg: String}
  InitialFail{msg: String}

# gen is the connection the UI bumped on this Dial. Stale FromNet is dropped.
# req is the carried PONG request ID (Out.pong_first(gen) range): the reader
# mints one per PING-carrying read and the Chunk/Pong pair carries it from
# the reply through post/dequeue to the writer, so trace hops match by
# numeric identity across generations instead of by order.
# Search carries a stamped retained-fd scan: the loop spawns the worker and
# the worker posts SearchDone; the ticket/gen/endpoint must match the live
# owner or the completion stays quiet. The wgen incarnation is stamped by
# the loop's generation owner (the part slot generation in multiserver, the
# loop generation in single-server) and echoed by the worker, so a delayed
# completion from a retired incarnation cannot land on reused stamps.
type NetCmd is Data:
  Cont{outs: List<&2, String>}
  Pong{gen: U32, pongs: List<&2, String>, req: U32}
  Dial{host: String, port: U32, gen: U32, nick: String}
  Drop{}
  Pump{gen: U32}
  OpenUrl{url: String}
  Begin{gen: U32}
  Search{text: String, target: String, cursor: Nat, orig: String, endpoint: String, history_on: Bool, ticket: Nat, gen: Nat, wgen: U32}

# One UI channel. FromNet is ignored unless gen is the UI's current one.
type UiMsg is Data:
  FromNet{gen: U32, e: NetEvt}
  UiKey{}
  UiContinue{}
  Resize{}
  UiError{msg: String}
  TypingTick{now_ms: U32}
  MediaFetched{generation: Nat, ticket: Nat, url: String, payload: String}
  CardFetched{generation: Nat, ticket: Nat, url: String, payload: String}
  UploadFetched{request: Up.Request, result: String, error: U32, http_status: U32}
  PreferencesLoaded{ticket: Nat, snapshot: Maybe<&2, Prefs.Preferences>, code: U32}
  PreferencesSaved{ticket: Nat, code: U32}
  PreferencesDeadline{ticket: Nat}
  Reconnect{host: String, port: U32, gen: U32}
  HistoryLoaded{ticket: Nat, gen: U32, endpoint: String, client: Cl.Client}
  NotifyDone{ticket: Nat, endpoint: String}
  SearchDone{ticket: Nat, gen: Nat, wgen: U32, endpoint: String, orig: String, result: Hs.DiskResult}

# All socket events, including an initial dial failure, share this guard.
def event_current(m: UiMsg, +gen: U32) -> Bool:
  match m:
    case FromNet{got, _}: U32.is_eq(got, gen)
    case _: True{}

# Only the socket owner can acknowledge completed shutdown. Reader EOF is
# independent of the writer's pending queue and must not release the UI.
def writer_done_current(m: UiMsg, +gen: U32) -> Bool:
  match m:
    case FromNet{got, WriterDone{}}: U32.is_eq(got, gen)
    case _: False{}

type NetState is Data:
  Demo{}
  Connecting{}
  Reconnecting{}
  Online{}
  Offline{}
  Stopping{wait: Bool}

def net_label(st: NetState) -> String:
  match st:
    case Demo{}:
      "demo"
    case Connecting{}:
      "connecting"
    case Reconnecting{}:
      "connecting"
    case Online{}:
      "online"
    case Offline{}:
      "offline"
    case Stopping{_}: "stopping"

def net_label_lag.online(+lag: U32, is_zero: Bool) -> String:
  match is_zero:
    case True{}: "online"
    case False{}: "online · " ++ U32.show(lag) ++ "ms"

def net_label_lag(+st: NetState, +lag: U32) -> String:
  match st:
    case Online{}: net_label_lag.online(lag, U32.is_eq(lag, 0))
    case Demo{}: "demo"
    case Connecting{}: "connecting"
    case Reconnecting{}: "connecting"
    case Offline{}: "offline"
    case Stopping{_}: "stopping"

def net_demo_ok() -> Bool:
  String.eq(net_label(Demo{}), "demo") && String.eq(net_label(Online{}), "online")



# Completion identity for one-shot workers. ticket is the worker id, gen the
# connection generation, wgen the loop incarnation, endpoint the exact
# host:port scope (no case folding, no DNS-root stripping).
# NotifyDone stays endpoint-only: a generation match would misattribute a
# late completion. stamp_current is an extra predicate; it does not replace
# the per-variant checks already in the live loop.
type Stamp is Data:
  Stamp{ticket: Nat, gen: U32, wgen: U32, endpoint: String}

def stamp_current.go(+ticket: Nat, +gen: U32, +wgen: U32, +endpoint: String, +live_ticket: Nat, +live_gen: U32, +live_wgen: U32, +live_endpoint: String) -> Bool:
  Nat.is_eq(ticket, live_ticket) && U32.is_eq(gen, live_gen) && U32.is_eq(wgen, live_wgen) && String.eq(endpoint, live_endpoint)

def stamp_current.live(+ticket: Nat, +gen: U32, +wgen: U32, +endpoint: String, +live: Stamp) -> Bool:
  match live:
    case Stamp{live_ticket, live_gen, live_wgen, live_endpoint}:
      stamp_current.go(ticket, gen, wgen, endpoint, live_ticket, live_gen, live_wgen, live_endpoint)

def stamp_current(+stamp: Stamp, +live: Stamp) -> Bool:
  match stamp:
    case Stamp{ticket, gen, wgen, endpoint}:
      stamp_current.live(ticket, gen, wgen, endpoint, live)
