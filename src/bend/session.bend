# Pure IRC session: protocol fold, keys, and connection/reconnect transitions.
# No IO. net.bend owns Socket / Chan / TimUI.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./frame.bend as Fr
import ./submit.bend as Sub
import ./auth.bend as Auth
import ./cap_notify.bend as CapNotify
import ./split.bend as Sp
import ./typing.bend as Ty
import ./media.bend as M
import ./cards.bend as C
import ./upload.bend as Up
import ./view.bend as View
import ./transport_policy.bend as Transport
import ./join_plan.bend as JoinPlan
import ./preferences.bend as Prefs
import ./irc_commands.bend as Commands
import ./server_key.bend as Key
import ./drafts.bend as Drafts
import ./notify.bend as Notify
import ./isupport.bend as Isupport
import ./history_search.bend as Hs
import ./theme.bend as Theme
import ./endpoint.bend as Ep
import ./composer_ui.bend as Cu
import ./session_keys.bend as Sk

# The first welcome names the nickname actually assigned by the server. A
# requested nickname can differ because of server policy or length limits.
# Shape checks live in Feed.welcome_admit; Session adds the seen/CASEMAPPING
# barrier so later/forged welcomes never reach Auth, JoinPlan, or the feed.
def registration_nick(+nick: String) -> Bool:
  Feed.welcome_nick(nick)

def registration_client.accept(allowed: Bool, cl: Cl.Client, nick: String) -> Maybe<&2, Cl.Client>:
  match allowed:
    case False{}: None{}
    case True{}: Some{Cl.set_nick(cl, nick)}

def registration_client_iso.message(welcome: Bool, seen: Bool, +cl: Cl.Client, +line: String, +m: Irc.Message, +iso: Isupport.State) -> Maybe<&2, Cl.Client>:
  match welcome:
    case False{}: Some{cl}
    case True{}:
      # W3: framed style bytes normalize at every identity/policy
      # comparison via the shared proto_atom seam.
      +nick = Irc.proto_atom(Irc.msg_param(m, 0n))
      registration_client.accept(Feed.welcome_admit(Irc.source_prefix(line), m)
        && (Bool.not(seen) || Isupport.cm_eq(iso, nick, Cl.nick_of(cl))), cl, nick)

def registration_client_iso.parsed(parsed: Maybe<&2, Irc.Message>, seen: Bool, cl: Cl.Client, line: String, +iso: Isupport.State) -> Maybe<&2, Cl.Client>:
  match parsed:
    case None{}: Some{cl}
    case Some{+m}: registration_client_iso.message(U32.is_eq(Irc.msg_num(m), 1), seen, cl, line, m, iso)

def registration_client_iso(seen: Bool, cl: Cl.Client, +line: String, +iso: Isupport.State) -> Maybe<&2, Cl.Client>:
  registration_client_iso.parsed(Irc.parse(line), seen, cl, line, iso)

# Fixed-identity entry kept for laws: defaults fold exactly like Irc.ieq.
def registration_client(seen: Bool, cl: Cl.Client, +line: String) -> Maybe<&2, Cl.Client>:
  registration_client_iso(seen, cl, line, Isupport.defaults())

# Live admission sole owner (I2 SESSION-DRY): one auth-consume /
# credential-echo OR shared by the fixed fold chain, the negotiated fold
# chain, and the split-pane gate, so live_step and live_split_step admit
# each line identically. Prep (live_step.prep) and registration
# (registration_client_iso) are already single owners consumed by both.
def live_consumed(+cl: Cl.Client, +line: String) -> Bool:
  Auth.consume_line(cl, line) || Sub.credential_echo(cl, line)

def register_lines(+nick: String) -> List<&2, String>:
  Irc.format_nick(nick) <> Irc.format_user(nick) <> Nil{}

# Capability set and CAP END come from the single registration owner; the SASL
# path adds no CAP END here because auth completion emits it through the owner.
def handshake_lines(+nick: String, +has_sasl: Bool) -> List<&2, String>:
  List.append(&2, String, "CAP LS 302" <> Nil{}, List.append(&2, String, CapNotify.req_lines(has_sasl), List.append(&2, String, CapNotify.cap_end_handshake(has_sasl), Irc.format_nick(nick) <> Irc.format_user(nick) <> Nil{})))

type FoldAcc is Data:
  FoldAcc{cl: Cl.Client, pongs: List<&2, String>, now_ms: U32}

def fold_step.normal_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  +cl2 = Feed.feed_at(cl, h, stamp)
  FoldAcc{cl2, List.append(&2, String, Irc.nick433_for(h, Cl.nick_of(cl)), pongs), now_ms}

def fold_step.lag_rtt.on_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +sent: U32, ok: Bool, +stamp: Maybe<&2, String>) -> FoldAcc:
  match ok:
    case True{}:
      +rtt = U32.sub(now_ms, sent)
      +cl2 = Cl.client_set_lag(cl, rtt)
      FoldAcc{Feed.feed_at(cl2, h, stamp), pongs, now_ms}
    case False{}:
      FoldAcc{Feed.feed_at(cl, h, stamp), pongs, now_ms}

def fold_step.lag_rtt_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +sent: U32, +stamp: Maybe<&2, String>) -> FoldAcc:
  fold_step.lag_rtt.on_at(cl, pongs, now_ms, h, sent, U32.is_ge(now_ms, sent) && Bool.not(U32.is_zero(now_ms)), stamp)

def fold_step.lag_on_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, m: Maybe<&2, U32>, +stamp: Maybe<&2, String>) -> FoldAcc:
  match m:
    case None{}:
      fold_step.normal_at(cl, pongs, now_ms, h, stamp)
    case Some{sent}:
      fold_step.lag_rtt_at(cl, pongs, now_ms, h, sent, stamp)

def fold_step.lag_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  fold_step.lag_on_at(cl, pongs, now_ms, h, Irc.extract_pong_lag_line(h), stamp)

def fold_step.auth.fed(fed: FoldAcc, phase: Cl.AuthPhase, outs: List<&2, String>, notice: Auth.Notice) -> FoldAcc:
  match fed:
    case FoldAcc{+cl, pongs, +now_ms}:
      FoldAcc{Auth.apply_reply(cl, phase, notice), List.append(&2, String, List.reverse(&2, String, outs), pongs), now_ms}

def fold_step.auth.feed_at(consumed: Bool, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  match consumed:
    case True{}: FoldAcc{cl, pongs, now_ms}
    case False{}: fold_step.lag_at(cl, pongs, now_ms, h, stamp)

def fold_step.auth_at(reply: Auth.Reply, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  match reply:
    case Auth.Reply{phase, outs, notice}:
      fold_step.auth.fed(fold_step.auth.feed_at(live_consumed(cl, h), cl, pongs, now_ms, h, stamp), phase, outs, notice)

def fold_step.sasl_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>, +port: U32) -> FoldAcc:
  fold_step.auth_at(Auth.step_for(cl, h, port), cl, pongs, now_ms, h, stamp)

# The actor reader owns the single live wire PONG (a gen-tagged Sess.Pong
# answered ahead of UI paints). The feed still skips PING lines here so they
# never reach SASL/auth, but it emits no PONG outs of its own.
def fold_step.ping_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, ping: Bool, +stamp: Maybe<&2, String>, +port: U32) -> FoldAcc:
  match ping:
    case True{}:
      FoldAcc{cl, pongs, now_ms}
    case False{}:
      fold_step.sasl_at(cl, pongs, now_ms, h, stamp, port)

def fold_step.got_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>, +port: U32) -> FoldAcc:
  fold_step.ping_at(cl, pongs, now_ms, h, Irc.is_ping_line(h), stamp, port)

def fold_step.got.at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +port: U32) -> FoldAcc:
  fold_step.got_at(cl, pongs, now_ms, h, None{}, port)

def fold_step.got(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String) -> FoldAcc:
  +port = Auth.binding_port(cl)
  fold_step.got.at(cl, pongs, now_ms, h, port)

# Negotiated fold chain (I2 dynamic): identical ping/SASL/auth/credential/lag
# handling, but the feed leaves fold under the Session ISUPPORT parameters
# (CASEMAPPING/CHANTYPES/STATUSMSG/PREFIX/strip) instead of fixed defaults.
def fold_step.normal_at_with(+isc: Cl.Iso, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  +cl2 = Feed.feed_at_with(cl, isc, h, stamp)
  FoldAcc{cl2, List.append(&2, String, Irc.nick433_for(h, Cl.nick_of(cl)), pongs), now_ms}

def fold_step.lag_rtt.on_at_with(+isc: Cl.Iso, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +sent: U32, ok: Bool, +stamp: Maybe<&2, String>) -> FoldAcc:
  match ok:
    case True{}:
      +rtt = U32.sub(now_ms, sent)
      +cl2 = Cl.client_set_lag(cl, rtt)
      FoldAcc{Feed.feed_at_with(cl2, isc, h, stamp), pongs, now_ms}
    case False{}:
      FoldAcc{Feed.feed_at_with(cl, isc, h, stamp), pongs, now_ms}

def fold_step.lag_rtt_at_with(+isc: Cl.Iso, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +sent: U32, +stamp: Maybe<&2, String>) -> FoldAcc:
  fold_step.lag_rtt.on_at_with(isc, cl, pongs, now_ms, h, sent, U32.is_ge(now_ms, sent) && Bool.not(U32.is_zero(now_ms)), stamp)

def fold_step.lag_on_at_with(+isc: Cl.Iso, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, m: Maybe<&2, U32>, +stamp: Maybe<&2, String>) -> FoldAcc:
  match m:
    case None{}:
      fold_step.normal_at_with(isc, cl, pongs, now_ms, h, stamp)
    case Some{sent}:
      fold_step.lag_rtt_at_with(isc, cl, pongs, now_ms, h, sent, stamp)

def fold_step.lag_at_with(+isc: Cl.Iso, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  fold_step.lag_on_at_with(isc, cl, pongs, now_ms, h, Irc.extract_pong_lag_line(h), stamp)

def fold_step.auth.feed_at_with(+isc: Cl.Iso, consumed: Bool, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  match consumed:
    case True{}: FoldAcc{cl, pongs, now_ms}
    case False{}: fold_step.lag_at_with(isc, cl, pongs, now_ms, h, stamp)

def fold_step.auth_at_with(+isc: Cl.Iso, reply: Auth.Reply, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  match reply:
    case Auth.Reply{phase, outs, notice}:
      fold_step.auth.fed(fold_step.auth.feed_at_with(isc, live_consumed(cl, h), cl, pongs, now_ms, h, stamp), phase, outs, notice)

def fold_step.sasl_at_with(+isc: Cl.Iso, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>, +port: U32) -> FoldAcc:
  fold_step.auth_at_with(isc, Auth.step_for(cl, h, port), cl, pongs, now_ms, h, stamp)

def fold_step.ping_at_with(+isc: Cl.Iso, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, ping: Bool, +stamp: Maybe<&2, String>, +port: U32) -> FoldAcc:
  match ping:
    case True{}:
      FoldAcc{cl, Irc.pong_for(h) <> pongs, now_ms}
    case False{}:
      fold_step.sasl_at_with(isc, cl, pongs, now_ms, h, stamp, port)

def fold_step.got_at_with(+isc: Cl.Iso, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>, +port: U32) -> FoldAcc:
  fold_step.ping_at_with(isc, cl, pongs, now_ms, h, Irc.is_ping_line(h), stamp, port)

def fold_step(st: FoldAcc, h: String) -> FoldAcc:
  match st:
    case FoldAcc{+cl, pongs, +now_ms}:
      fold_step.got(cl, pongs, now_ms, h)

def fold_fin(st: FoldAcc) -> Cl.Client & List<&2, String>:
  match st:
    case FoldAcc{+cl, pongs, _}:
      (cl, List.reverse(&2, String, pongs))

def fold_lines_ms(+cl: Cl.Client, +xs: List<&2, String>, +now_ms: U32) -> Cl.Client & List<&2, String>:
  fold_fin(List.foldl(~&2, ~String, ~FoldAcc, ~fold_step, xs, FoldAcc{cl, Nil{}, now_ms}))

def fold_lines(+cl: Cl.Client, +xs: List<&2, String>) -> Cl.Client & List<&2, String>:
  fold_lines_ms(cl, xs, 0)

# Resolve each typing event against the Client at that wire position. A JOIN
# earlier in one chunk can establish an otherwise ambiguous +channel identity.
def fold_typing_step.fed(fed: FoldAcc, typing: Ty.State) -> FoldAcc & Ty.State:
  match fed:
    case FoldAcc{+cl, pongs, now_ms}:
      (FoldAcc{cl, pongs, now_ms}, Ty.retain_client(typing, cl))

def fold_typing_step.line(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, typing: Ty.State, +line: String) -> FoldAcc & Ty.State:
  fold_typing_step.fed(fold_step.got(cl, pongs, now_ms, line), Ty.apply_line_for(typing, cl, line, now_ms))

def fold_typing_step(st: FoldAcc & Ty.State, line: String) -> FoldAcc & Ty.State:
  match st:
    case (FoldAcc{+cl, pongs, +now_ms}, typing):
      fold_typing_step.line(cl, pongs, now_ms, typing, line)

def live_fuel(+frames: U32) -> Nat:
  U32.to_nat(frames)

def ticks_of(+frames: U32) -> Nat:
  live_fuel(frames)

def body_h(+rows: U32) -> Nat:
  Sp.page_height(rows, Sp.Off{})

# Body lines and PageUp/PageDown share this height. Bend applies it
# from the frame's row count (Sess.key_pol); C does not take a page.
def body_h_ok() -> Bool:
  Nat.is_eq(body_h(24), 20n) && Nat.is_eq(body_h(16), 12n) && Nat.is_eq(body_h(6), 2n) && Nat.is_eq(body_h(7), 3n)

# Constructors stay in this file so Sess.UiMsg / Sess.NetCmd remain the
# types net.bend, wsnet.bend, and actor.bend already match. A narrowed
# lockstep copy lives in net_msg.bend for importers that do not need Session.
# Bend cannot re-export a constructor into another file's namespace.
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


def show_netcmd(c: NetCmd) -> String:
  match c:
    case Cont{_}:
      "cont"
    case Dial{+host, port, _, _}:
      String.concat("dial:" <> host <> ":" <> U32.show(port) <> Nil{})
    case Drop{}:
      "drop"
    case Pump{_}:
      "pump"
    case Pong{gen, _, _}:
      "pong:" ++ U32.show(gen)
    case OpenUrl{+url}:
      "open:" ++ url
    case Begin{gen}: "begin:" ++ U32.show(gen)
    case Search{+text, +target, +cursor, _, _, _, _, _, _}:
      "search:" ++ text ++ "|" ++ target ++ "|" ++ Nat.show(cursor)

# Emit dispatch policy (pure mirror of the loop's Search-only Net owner):
# Search is the only NetCmd that spawns the retained-fd worker through
# Net.search_spawn with its captured fields and owning event channel
# (Net.emit_cmd stamps the loop generation as wgen; WsNet.ws_emit.to reuses
# the same owner with the stamped part incarnation). Pong stays quiet at
# every loop emit site because the actor reader owns the single live wire
# reply (gen-checked at the writer); the loop never forwards a Pong down
# the actor channel. Both IO arms must match this predicate.
def emit_spawns_search(cmd: NetCmd) -> Bool:
  match cmd:
    case Search{_, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def hold_cmd.outs(net: NetState, outs: List<&2, String>) -> NetCmd:
  match net:
    case Online{}:
      Cont{outs}
    case Connecting{}:
      Cont{Nil{}}
    case Reconnecting{}:
      Cont{Nil{}}
    case Demo{}:
      Cont{Nil{}}
    case Offline{}:
      Cont{Nil{}}
    case Stopping{_}: Cont{Nil{}}

def hold_cmd(net: NetState, cmd: NetCmd) -> NetCmd:
  match cmd:
    case Dial{+host, port, gen, +nick}:
      Dial{host, port, gen, nick}
    case Drop{}:
      Drop{}
    case Pump{gen}:
      Pump{gen}
    case Pong{gen, pongs, req}:
      Pong{gen, pongs, req}
    case Cont{outs}:
      hold_cmd.outs(net, outs)
    case OpenUrl{+url}:
      OpenUrl{url}
    case Begin{gen}: Begin{gen}
    case Search{+text, +target, +cursor, +orig, +endpoint, +history_on, +ticket, +gen, +wgen}:
      Search{text, target, cursor, orig, endpoint, history_on, ticket, gen, wgen}

def wrap_outs(pair: Cl.Client & List<&2, String>) -> Cl.Client & String & NetCmd:
  match pair:
    case (cl2, outs):
      (cl2, "", Cont{outs})

def can_send(net: NetState) -> Bool:
  match net:
    case Online{}:
      True{}
    case Demo{}:
      True{}
    case Connecting{}:
      False{}
    case Reconnecting{}:
      False{}
    case Offline{}:
      False{}
    case Stopping{_}: False{}

# Shared disconnected hold for single-line and adapter multiline submits.
# Both gate on can_send; when held, echo to the server buffer with no wire
# output and no Self echo. Session owns the text; adapters must call this.
def hold_offline(+cl: Cl.Client) -> Cl.Client & String & NetCmd:
  (Sub.echo_err_server(cl, "not connected"), "", Cont{Nil{}})

def connect_apply.busy(+cl: Cl.Client, online: Bool) -> Cl.Client & String & NetCmd:
  match online:
    case True{}:
      (Sub.echo_err_server(cl, "already connected"), "", Cont{Nil{}})
    case False{}:
      (Sub.echo_err_server(cl, "already connecting"), "", Cont{Nil{}})

def connect_apply.st(+cl: Cl.Client, +host: String, +port: U32, net: NetState) -> Cl.Client & String & NetCmd:
  match net:
    case Connecting{}:
      connect_apply.busy(cl, False{})
    case Reconnecting{}:
      connect_apply.busy(cl, False{})
    case _:
      (Sub.echo_sys(cl, "connecting to " ++ host ++ ":" ++ U32.show(port)), "", Dial{host, port, 0, Cl.nick_of(cl)})

def connect_apply.recon_ok(ok: Bool, +cl: Cl.Client, net: NetState, +server: String, +port: U32) -> Cl.Client & String & NetCmd:
  match ok:
    case True{}:
      connect_apply.st(cl, server, port, net)
    case False{}:
      (Sub.echo_err(cl, "cannot reconnect: no server configured"), "", Cont{Nil{}})

# Demo is a fixture state, not a hostname sentinel. A saved single-label
# endpoint (including "s" or "demo") is valid after an explicit connection.
def reconnect_configured(net: NetState, +server: String) -> Bool:
  match net:
    case Demo{}: False{}
    case _: Bool.not(String.is_empty(server))

def connect_apply.reconnect(+cl: Cl.Client, +net: NetState, +server: String, +port: U32) -> Cl.Client & String & NetCmd:
  connect_apply.recon_ok(reconnect_configured(net, server), cl, net, server, port)

def connect_apply(+cl: Cl.Client, net: NetState, +port: U32, c: Sub.Conn) -> Cl.Client & String & NetCmd:
  match c:
    case Sub.ConnBad{}:
      (Sub.echo_err(cl, "usage: /connect host[:port] [port]"), "", Cont{Nil{}})
    case Sub.ConnOk{+host, port}:
      connect_apply.st(cl, host, port, net)
    case Sub.ConnDefault{+host}:
      connect_apply.st(cl, host, port, net)
    case Sub.ConnReconnect{}:
      connect_apply.reconnect(cl, net, Cl.server_of(cl), port)

def open_apply.got(+cl: Cl.Client, mb: Maybe<&2, String>) -> Cl.Client & String & NetCmd:
  match mb:
    case None{}:
      (Sub.echo_err(cl, "no link found"), "", Cont{Nil{}})
    case Some{+url}:
      (Sub.echo_link_result(cl, "opening " ++ url), "", OpenUrl{url})

def wrap_local(pair: Cl.Client & List<&2, String>) -> Cl.Client & String & NetCmd:
  match pair:
    case (cl, _): (cl, "", Cont{Nil{}})

def submit_local(input: Sub.Input, +cl: Cl.Client) -> Cl.Client & String & NetCmd:
  match input:
    case Sub.CommandInput{Sub.Quit{}, +verb, +rest}:
      wrap_outs(Sub.submit_cmd.do(cl, verb, rest, Sub.Quit{}))
    case _:
      wrap_local(Sub.submit_parsed(cl, input))

def submit_local_with(+iso: Isupport.State, input: Sub.Input, +cl: Cl.Client) -> Cl.Client & String & NetCmd:
  match input:
    case Sub.CommandInput{Sub.Quit{}, +verb, +rest}:
      wrap_outs(Sub.submit_cmd_with.do(iso, cl, verb, rest, Sub.Quit{}))
    case _:
      wrap_local(Sub.submit_parsed_with(iso, cl, input))

def submit_offline.wire(+cl: Cl.Client, input: Sub.Input) -> Cl.Client & String & NetCmd:
  match input:
    # PART cancels desired membership even before registration or while offline.
    # Submission validates the target; this local path never emits its wire.
    case Sub.CommandInput{Sub.Part{}, verb, rest}: submit_local(Sub.CommandInput{Sub.Part{}, verb, rest}, cl)
    case _: hold_offline(cl)

def submit_offline(+cl: Cl.Client, +input: Sub.Input, needs_wire: Bool) -> Cl.Client & String & NetCmd:
  match needs_wire:
    case True{}: submit_offline.wire(cl, input)
    case False{}: submit_local(input, cl)

def submit_offline.wire_with(+iso: Isupport.State, +cl: Cl.Client, input: Sub.Input) -> Cl.Client & String & NetCmd:
  match input:
    case Sub.CommandInput{Sub.Part{}, verb, rest}: submit_local_with(iso, Sub.CommandInput{Sub.Part{}, verb, rest}, cl)
    case _: hold_offline(cl)

def submit_offline_with(+iso: Isupport.State, +cl: Cl.Client, +input: Sub.Input, needs_wire: Bool) -> Cl.Client & String & NetCmd:
  match needs_wire:
    case True{}: submit_offline.wire_with(iso, cl, input)
    case False{}: submit_local_with(iso, input, cl)

def submit_send_echo(+cl: Cl.Client, +input: Sub.Input, online: Bool, +echo_ok: Bool) -> Cl.Client & String & NetCmd:
  match online:
    case True{}: wrap_outs(Sub.submit_parsed_echo(cl, input, echo_ok))
    case False{}: submit_offline(cl, input, Sub.needs_connection(input))

def submit_send(+cl: Cl.Client, +input: Sub.Input, online: Bool) -> Cl.Client & String & NetCmd:
  submit_send_echo(cl, input, online, False{})

def submit_send_with_echo(+iso: Isupport.State, +cl: Cl.Client, +input: Sub.Input, online: Bool, +echo_ok: Bool) -> Cl.Client & String & NetCmd:
  match online:
    case True{}: wrap_outs(Sub.submit_parsed_with_echo(iso, cl, input, echo_ok))
    case False{}: submit_offline_with(iso, cl, input, Sub.needs_connection(input))

def submit_send_with(+iso: Isupport.State, +cl: Cl.Client, +input: Sub.Input, online: Bool) -> Cl.Client & String & NetCmd:
  submit_send_with_echo(iso, cl, input, online, False{})

# ---- /history interception ----------------------------------------------
# /history is a Session-owned catalog constructor (like connect), intercepted
# on the LIVE submit path: fetch subcommands need a connection and the
# negotiated chathistory flag, while search/page report live_only until the
# live loop runs search_file and history_import_search. The negotiated flag
# comes from the session's live history owner (shared CAP registry); the
# key loop threads it from Session into submit_or_split/apply_keys.
def history_apply.offline(offline: Bool, +cl: Cl.Client, +rest: String, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  match offline:
    case True{}: (Sub.echo_err_server(cl, "not connected"), "", Cont{Nil{}})
    case False{}: wrap_outs(Hs.submit_history(cl, rest, negotiated))

def history_apply(+cl: Cl.Client, +net: NetState, +rest: String, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  history_apply.offline(Hs.history_needs_connection(rest) && Bool.not(can_send(net)), cl, rest, negotiated)

def submit_send_ctx.iso(iso: Maybe<&2, Isupport.State>, +cl: Cl.Client, +input: Sub.Input, online: Bool, +echo_ok: Bool) -> Cl.Client & String & NetCmd:
  match iso:
    case None{}: submit_send_echo(cl, input, online, echo_ok)
    case Some{+s}: submit_send_with_echo(s, cl, input, online, echo_ok)

def submit_send_ctx(ctx: Sub.SubmitCtx, +cl: Cl.Client, +input: Sub.Input, online: Bool) -> Cl.Client & String & NetCmd:
  match ctx:
    case Sub.SubmitCtx{iso, +echo_ok}: submit_send_ctx.iso(iso, cl, input, online, echo_ok)

# Session verbs are catalog constructors. Connect and history never reach the
# wire submitter; open stays local even when the negotiated path is on.
def submit_input_ctx.cmd(ctx: Sub.SubmitCtx, cmd: Sub.Slash, +verb: String, +rest: String, +cl: Cl.Client, +net: NetState, +port: U32, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  match cmd:
    case Sub.History{}: history_apply(cl, net, rest, negotiated)
    case Sub.Connect{}: connect_apply(cl, net, port, Sub.connect_from_input.verb(False{}, rest))
    case Sub.Reconnect{}: connect_apply(cl, net, port, Sub.connect_from_input.verb(True{}, rest))
    case Sub.OpenCmd{}: open_apply.got(cl, Sub.open_resolve_target(cl, rest))
    case _: submit_send_ctx(ctx, cl, Sub.CommandInput{cmd, verb, rest}, can_send(net))

def submit_input_ctx(ctx: Sub.SubmitCtx, input: Sub.Input, +cl: Cl.Client, +net: NetState, +port: U32, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  match input:
    case Sub.CommandInput{+cmd, +verb, +rest}:
      submit_input_ctx.cmd(ctx, cmd, verb, rest, cl, net, port, negotiated)
    case _:
      submit_send_ctx(ctx, cl, input, can_send(net))

def submit_input_echo(input: Sub.Input, +cl: Cl.Client, +net: NetState, +port: U32, +negotiated: Bool, +echo_ok: Bool) -> Cl.Client & String & NetCmd:
  submit_input_ctx(Sub.submit_ctx_plain(echo_ok), input, cl, net, port, negotiated)

def submit_input(input: Sub.Input, +cl: Cl.Client, +net: NetState, +port: U32, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  submit_input_echo(input, cl, net, port, negotiated, False{})

def submit_input_with_echo(input: Sub.Input, +iso: Isupport.State, +cl: Cl.Client, +net: NetState, +port: U32, +negotiated: Bool, +echo_ok: Bool) -> Cl.Client & String & NetCmd:
  submit_input_ctx(Sub.submit_ctx_iso(iso, echo_ok), input, cl, net, port, negotiated)

def apply_keys_ctx.enter(enter: Bool, ctx: Sub.SubmitCtx, +cl: Cl.Client, net: NetState, +port: U32, +draft: String, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  match enter:
    case False{}: (cl, draft, Cont{Nil{}})
    case True{}: submit_input_ctx(ctx, Sub.parse_input(draft), cl, net, port, negotiated)

def apply_keys_ctx(ctx: Sub.SubmitCtx, +cl: Cl.Client, net: NetState, +port: U32, +draft: String, enter: Bool, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  apply_keys_ctx.enter(enter, ctx, cl, net, port, draft, negotiated)

def apply_keys_echo(+cl: Cl.Client, net: NetState, +port: U32, +draft: String, enter: Bool, +negotiated: Bool, +echo_ok: Bool) -> Cl.Client & String & NetCmd:
  apply_keys_ctx(Sub.submit_ctx_plain(echo_ok), cl, net, port, draft, enter, negotiated)

def apply_keys(+cl: Cl.Client, net: NetState, +port: U32, +draft: String, enter: Bool, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  apply_keys_echo(cl, net, port, draft, enter, negotiated, False{})

def apply_keys_with_echo(+iso: Isupport.State, +cl: Cl.Client, net: NetState, +port: U32, +draft: String, enter: Bool, +negotiated: Bool, +echo_ok: Bool) -> Cl.Client & String & NetCmd:
  apply_keys_ctx(Sub.submit_ctx_iso(iso, echo_ok), cl, net, port, draft, enter, negotiated)

# Compat alias over the live path (same entry the key loop calls).
def submit_input_hist(input: Sub.Input, +cl: Cl.Client, +net: NetState, +port: U32, +negotiated: Bool) -> Cl.Client & String & NetCmd:
  submit_input(input, cl, net, port, negotiated)

def cmd_connect.got(triple: Cl.Client & String & NetCmd) -> NetCmd:
  match triple:
    case (_, _, c):
      c

def cmd_connect(+net: NetState, +input: String) -> NetCmd:
  cmd_connect.got(connect_apply(Cl.init("me", "s"), net, Transport.TLS_PORT(), Sub.connect_from_input(input)))

def cmd_connect_ok() -> Bool:
  String.eq(show_netcmd(cmd_connect(Demo{}, "/connect irc.example.net 6668")), "dial:irc.example.net:6668")
    && String.eq(show_netcmd(cmd_connect(Online{}, "/connect irc.example.net")), "dial:irc.example.net:6697")
    && String.eq(show_netcmd(cmd_connect(Connecting{}, "/connect irc.example.net")), "cont")
    && String.eq(show_netcmd(cmd_connect(Demo{}, "/connect")), "cont")

# Input-recall ring, key frame, and completion stay in this file: Sess.Hist,
# Sess.Keys, and Sess.Comp are matched by workspace.bend and session_drafts.bend.
# Bend constructors are namespace-owned, so moving the types would fork them.
# Recall steps and composer key/panel decisions live in session_keys.bend.
type Hist is Data:
  Hist{lines: List<&2, String>, pos: Nat}

def hist0() -> Hist:
  Hist{Nil{}, 0n}

def HIST_CAP() -> Nat:
  64n

def take_last_str(+xs: List<&2, String>, n: Nat) -> List<&2, String>:
  List.drop(&2, String, xs, Nat.sub(List.length(&2, String, xs), n))

def hist_len(h: Hist) -> Nat:
  match h:
    case Hist{+lines, _}:
      List.length(&2, String, lines)

def hist_push.on(+line: String, empty: Bool, h: Hist) -> Hist:
  match empty:
    case True{}:
      h
    case False{}:
      match h:
        case Hist{+lines, _}:
          +xs = take_last_str(List.append(&2, String, lines, line <> Nil{}), HIST_CAP())
          Hist{xs, List.length(&2, String, xs)}

def hist_push(+h: Hist, +line: String) -> Hist:
  hist_push.on(line, String.is_empty(line), h)

def str_get(+xs: List<&2, String>, +i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, i), "")

type HistDir is Data:
  HistStay{}
  HistPrev{}
  HistNext{}

def hist_dir.on(+n: U32, prev: Bool, next: Bool) -> HistDir:
  match prev:
    case True{}:
      HistPrev{}
    case False{}:
      match next:
        case True{}:
          HistNext{}
        case False{}:
          HistStay{}

def hist_dir(+n: U32) -> HistDir:
  hist_dir.on(n, U32.is_eq(n, 1), U32.is_eq(n, 2))

def sk_dir(dir: HistDir) -> Sk.HistStep:
  match dir:
    case HistStay{}: Sk.StepStay{}
    case HistPrev{}: Sk.StepPrev{}
    case HistNext{}: Sk.StepNext{}

def hist_move.at(+lines: List<&2, String>, pair: Nat & String) -> Hist & String:
  match pair:
    case (+pos, +shown):
      (Hist{lines, pos}, shown)

def hist_move(+h: Hist, +draft: String, dir: HistDir) -> Hist & String:
  match h:
    case Hist{+lines, +pos}:
      hist_move.at(lines, Sk.hist_move(lines, pos, draft, sk_dir(dir)))

def click_of.on(+n: U32, z: Bool) -> Maybe<&2, Nat>:
  match z:
    case True{}:
      None{}
    case False{}:
      Some{U32.to_nat(U32.sub(n, 1))}

def click_of(+n: U32) -> Maybe<&2, Nat>:
  click_of.on(n, U32.is_eq(n, 0))

type Keys is Data:
  Keys{
    typed: String,
    enter: Bool,
    tab: Cl.TabDir,
    click: Maybe<&2, Nat>,
    up: Nat,
    dn: Nat,
    hist: HistDir,
    # 0 none, 1 tab-cycle, 2 accept the ghost suffix, 3 dismiss help or the menu.
    comp: U32,
    focus: U32
  }

def comp_on(+n: U32) -> Bool:
  U32.is_eq(n, 1)

def keys_enter(+line: String) -> Keys:
  Keys{line, True{}, Cl.TabStay{}, None{}, 0n, 0n, HistStay{}, 0, 0}

def keys_focus() -> Keys:
  Keys{"", False{}, Cl.TabStay{}, None{}, 0n, 0n, HistStay{}, 0, 1}

# TimUI key numbers (TimuiKey). Bend maps them; C only reports the raw key.
def KEY_ESCAPE() -> U32:
  1

def KEY_TAB() -> U32:
  3

def key_comp.on(tab: Bool) -> U32:
  match tab:
    case True{}:
      1
    case False{}:
      0

def key_comp(+key: U32) -> U32:
  key_comp.on(U32.is_eq(key, KEY_TAB()))


def KEY_UP() -> U32:
  7

def KEY_DOWN() -> U32:
  8

def KEY_LEFT() -> U32:
  9

def KEY_RIGHT() -> U32:
  10

def KEY_PAGE_UP() -> U32:
  13

def KEY_PAGE_DOWN() -> U32:
  14

def KEY_F10() -> U32:
  24

def KEY_F6() -> U32:
  20

def KEY_F7() -> U32:
  21

def KEY_F8() -> U32:
  22

def KEY_F9() -> U32:
  23

def MOD_SHIFT() -> U32:
  1

def MOD_CTRL() -> U32:
  4

def ctrl_on(+mods: U32) -> Bool:
  U32.is_eq(U32.and(mods, MOD_CTRL()), MOD_CTRL())

def key_focus.on(f6: Bool, ctrl_w: Bool) -> U32:
  match f6:
    case True{}: 1
    case False{}: Bool.pick(U32, ctrl_w, 1, 0)

def key_focus(+key: U32, +mods: U32, +codepoint: U32) -> U32:
  key_focus.on(U32.is_eq(key, KEY_F6()), ctrl_on(mods) && (U32.is_eq(codepoint, 119) || U32.is_eq(codepoint, 87)))

def WHEEL_SIGN() -> U32:
  2147483648

def shift_on(+mods: U32) -> Bool:
  U32.is_eq(U32.and(mods, MOD_SHIFT()), MOD_SHIFT())

def key_tab.on(shift: Bool, right: Bool, left: Bool) -> U32:
  match shift:
    case False{}:
      0
    case True{}:
      match right:
        case True{}:
          1
        case False{}:
          match left:
            case True{}:
              2
            case False{}:
              0

def key_tab(+key: U32, +mods: U32) -> U32:
  key_tab.on(shift_on(mods), U32.is_eq(key, KEY_RIGHT()), U32.is_eq(key, KEY_LEFT()))

def key_hist.on(shift: Bool, up: Bool, down: Bool) -> U32:
  match shift:
    case True{}:
      0
    case False{}:
      match up:
        case True{}:
          1
        case False{}:
          match down:
            case True{}:
              2
            case False{}:
              0

def key_hist(+key: U32, +mods: U32) -> U32:
  key_hist.on(shift_on(mods), U32.is_eq(key, KEY_UP()), U32.is_eq(key, KEY_DOWN()))

def key_quit.on(esc: Bool, f10: Bool) -> U32:
  match esc:
    case True{}:
      1
    case False{}:
      match f10:
        case True{}:
          1
        case False{}:
          0

def key_quit(+key: U32) -> U32:
  key_quit.on(U32.is_eq(key, KEY_ESCAPE()), U32.is_eq(key, KEY_F10()))

def wheel_neg(+w: U32) -> Bool:
  U32.is_ge(w, WHEEL_SIGN())

def wheel_up.on(+w: U32, neg: Bool) -> U32:
  match neg:
    case True{}:
      0
    case False{}:
      w

def wheel_up(+w: U32) -> U32:
  wheel_up.on(w, wheel_neg(w))

# A negative wheel is uint32 two's complement. Its magnitude is ~w+1.
# 2^32 does not fit in U32, so this is not a subtraction from 2^32.
def wheel_dn.on(+w: U32, neg: Bool) -> U32:
  match neg:
    case False{}:
      0
    case True{}:
      U32.add(U32.not(w), 1)

def wheel_dn(+w: U32) -> U32:
  wheel_dn.on(w, wheel_neg(w))

def page_amt(on: Bool, +page: Nat) -> U32:
  match on:
    case False{}:
      0
    case True{}:
      U32.from_nat(page)

def scroll_up(+key: U32, +wheel: U32, +page: Nat) -> U32:
  U32.add(wheel_up(wheel), page_amt(U32.is_eq(key, KEY_PAGE_UP()), page))

def scroll_dn(+key: U32, +wheel: U32, +page: Nat) -> U32:
  U32.add(wheel_dn(wheel), page_amt(U32.is_eq(key, KEY_PAGE_DOWN()), page))

type KeyPol is Data:
  KeyPol{tab: U32, up: U32, dn: U32, hist: U32, quit: U32, comp: U32, focus: U32}

def key_pol_raw(+key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +page: Nat) -> KeyPol:
  KeyPol{key_tab(key, mods), scroll_up(key, wheel, page), scroll_dn(key, wheel, page), key_hist(key, mods), key_quit(key), key_comp(key), key_focus(key, mods, codepoint)}

def key_pol(+key: U32, +mods: U32, +wheel: U32, +rows: U32) -> KeyPol:
  key_pol_raw(key, mods, 0, wheel, body_h(rows))

def pol_eq(p: KeyPol, +tab: U32, +up: U32, +dn: U32, +hist: U32, +quit: U32, +comp: U32, +focus: U32) -> Bool:
  match p:
    case KeyPol{t, u, d, h, q, c, f}:
      U32.is_eq(t, tab) && U32.is_eq(u, up) && U32.is_eq(d, dn) && U32.is_eq(h, hist) && U32.is_eq(q, quit) && U32.is_eq(c, comp) && U32.is_eq(f, focus)

def key_pol_ok() -> Bool:
  pol_eq(key_pol(KEY_RIGHT(), MOD_SHIFT(), 0, 24), 1, 0, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_LEFT(), MOD_SHIFT(), 0, 24), 2, 0, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_RIGHT(), 0, 0, 24), 0, 0, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_UP(), 0, 0, 24), 0, 0, 0, 1, 0, 0, 0)
    && pol_eq(key_pol(KEY_UP(), MOD_SHIFT(), 0, 24), 0, 0, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_DOWN(), 0, 0, 24), 0, 0, 0, 2, 0, 0, 0)
    && pol_eq(key_pol(KEY_ESCAPE(), 0, 0, 24), 0, 0, 0, 0, 1, 0, 0)
    && pol_eq(key_pol(KEY_F10(), 0, 0, 24), 0, 0, 0, 0, 1, 0, 0)
    && pol_eq(key_pol(KEY_PAGE_UP(), 0, 0, 24), 0, 20, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_PAGE_DOWN(), 0, 0, 24), 0, 0, 20, 0, 0, 0, 0)
    && pol_eq(key_pol(0, 0, 3, 24), 0, 3, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(0, 0, 4294967294, 24), 0, 0, 2, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_PAGE_UP(), 0, 2, 24), 0, 22, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_TAB(), 0, 0, 24), 0, 0, 0, 0, 0, 1, 0)
    && pol_eq(key_pol_raw(KEY_F6(), 0, 0, 0, 9n), 0, 0, 0, 0, 0, 0, 1)
    && pol_eq(key_pol_raw(0, MOD_CTRL(), 119, 0, 9n), 0, 0, 0, 0, 0, 0, 1)

def keys_of(+typed: String, enter: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32, +comp: U32, +focus: U32) -> Keys:
  Keys{typed, enter, Cl.tab_dir(tab), click_of(click), U32.to_nat(up), U32.to_nat(dn), hist_dir(hist), comp, focus}

def tab_hot(d: Cl.TabDir) -> Bool:
  match d:
    case Cl.TabStay{}:
      False{}
    case _:
      True{}

def hist_hot(d: HistDir) -> Bool:
  match d:
    case HistStay{}:
      False{}
    case _:
      True{}

def click_hot(c: Maybe<&2, Nat>) -> Bool:
  match c:
    case None{}:
      False{}
    case Some{_}:
      True{}

def nat_hot(+n: Nat) -> Bool:
  Bool.not(Nat.is_eq(n, 0n))

def hist_after_enter(+h: Hist, +line: String, enter: Bool) -> Hist:
  match enter:
    case True{}:
      hist_push(h, line)
    case False{}:
      h

def hist_cap_ok.go(n: Nat, h: Hist) -> Hist:
  match n:
    case 0n:
      h
    case 1n+p:
      hist_cap_ok.go(p, hist_push(h, "x"))

def hist_cap_ok() -> Bool:
  Nat.is_eq(hist_len(hist_cap_ok.go(70n, hist0())), 64n)

type Comp is Data:
  CompNone{}
  CompActive{pre: String, word: String, idx: Nat}
  CompUpload{state: Up.State, completion: Maybe<&2, CompWord>, presented: Bool}
  # /help stays up after Enter clears the draft, until Esc or an edit.
  CompHelp{topic: String}
  # Esc hid the slash menu; the next edit brings it back.
  CompHidden{}
  # Selected row in the slash menu. Up and down move it.
  CompPick{idx: Nat}

type CompWord is Data:
  CompWord{pre: String, word: String, idx: Nat}

def comp_from_word(word: Maybe<&2, CompWord>) -> Comp:
  match word:
    case None{}: CompNone{}
    case Some{CompWord{pre, word, idx}}: CompActive{pre, word, idx}

def comp_word(comp: Comp) -> Maybe<&2, CompWord>:
  match comp:
    case CompNone{}: None{}
    case CompActive{pre, word, idx}: Some{CompWord{pre, word, idx}}
    case CompUpload{_, completion, _}: completion
    case CompHelp{_}: None{}
    case CompHidden{}: None{}
    case CompPick{_}: None{}

def comp_ordinary(comp: Comp) -> Comp:
  match comp:
    case CompHelp{topic}: CompHelp{topic}
    case CompHidden{}: CompHidden{}
    case CompPick{idx}: CompPick{idx}
    case _: comp_from_word(comp_word(comp))

def comp0() -> Comp:
  CompNone{}

def view_of(comp: Comp) -> Sk.CView:
  match comp:
    case CompNone{}: Sk.CNone{}
    case CompActive{_, _, _}: Sk.CActive{}
    case CompUpload{_, _, _}: Sk.CUpload{}
    case CompHelp{+topic}: Sk.CHelp{topic}
    case CompHidden{}: Sk.CHidden{}
    case CompPick{+idx}: Sk.CPick{idx}

def comp_of(view: Sk.CView) -> Comp:
  match view:
    case Sk.CHelp{+topic}: CompHelp{topic}
    case Sk.CHidden{}: CompHidden{}
    case Sk.CPick{+idx}: CompPick{idx}
    case _: CompNone{}

# Endpoint transitions drop the interactive completion word so a stale
# pre/word pair cannot revive old-endpoint text on the next Tab frame. An
# upload keeps its worker state (Busy ownership is never dropped here; the
# next maintain retains or revokes it against the new scope) but loses the
# completion word and the presentation flag: consent never crosses endpoints.
def comp_reset(comp: Comp) -> Comp:
  match comp:
    case CompUpload{+state, _, _}: CompUpload{state, None{}, False{}}
    case _: CompNone{}

def is_all_spaces(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+h, t}:
      Bool.and(Irc.is_space(h), is_all_spaces(t))

def split_word.rev(pair: String & String) -> String & String:
  match pair:
    case (word_rev, pre_rev):
      (String.reverse(pre_rev), String.reverse(word_rev))

def split_word(+s: String) -> String & String:
  split_word.rev(Irc.take_until_space(String.reverse(s)))


def nick_match.ok(own: Bool, sw: Bool) -> Bool:
  match own:
    case True{}:
      False{}
    case False{}:
      sw

def match_nicks.keep(+cand: String, rest: List<&2, String>, hit: Bool) -> List<&2, String>:
  match hit:
    case True{}:
      cand <> rest
    case False{}:
      rest

def comp_next_idx.wrap(wrap: Bool, +p: Nat) -> Nat:
  match wrap:
    case True{}:
      0n
    case False{}:
      p

def comp_next_idx(+idx: Nat, +len: Nat) -> Nat:
  +p = Nat.add(idx, 1n)
  comp_next_idx.wrap(Nat.is_ge(p, len), p)

def comp_format.on(+pre: String, +nick: String, spaces: Bool) -> String:
  match spaces:
    case True{}:
      pre ++ nick ++ ": "
    case False{}:
      pre ++ nick ++ " "

def comp_format(+pre: String, +nick: String) -> String:
  comp_format.on(pre, nick, is_all_spaces(pre))

def slash_command_names(rows: List<&2, Sub.SlashRow>) -> List<&2, String>:
  match rows:
    case Nil{}: Nil{}
    case Con{Sub.SlashRow{name, _}, rest}: ("/" ++ name) <> slash_command_names(rest)

def slash_command_list() -> List<&2, String>:
  slash_command_names(Sub.slash_rows())

def is_slash_word(+w: String) -> Bool:
  String.starts_with(w, "/")

def match_slash.keep(+cand: String, rest: List<&2, String>, hit: Bool) -> List<&2, String>:
  match hit:
    case True{}:
      cand <> rest
    case False{}:
      rest

def match_slash.go(xs: List<&2, String>, +word: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, +t}:
      +rest = match_slash.go(t, word)
      match_slash.keep(h, rest, String.starts_with(Irc.rfc1459(h), Irc.rfc1459(word)))

def comp_format.choice(+pre: String, +item: String, slash: Bool) -> String:
  match slash:
    case True{}:
      pre ++ item ++ " "
    case False{}:
      comp_format(pre, item)

def comp_format_cand(+pre: String, +word: String, +item: String) -> String:
  comp_format.choice(pre, item, is_slash_word(word))

def comp_pick.on(
  +matches: List<&2, String>,
  +pre: String,
  +word: String,
  +typed: String,
  +idx: Nat,
  empty: Bool
) -> Comp & String & U32:
  match empty:
    case True{}:
      (CompNone{}, typed, 0)
    case False{}:
      +item = str_get(matches, idx)
      (CompActive{pre, word, idx}, comp_format_cand(pre, word, item), 1)

# ---- negotiated completion (I2 dynamic) -----------------------------------
# Nick completion folds under the Session CASEMAPPING (ascii/strict/rfc1459
# differ exactly on []\^~); slash commands stay fixed (ASCII-only, identical
# under every mapping).
def nick_match_iso(+iso: Isupport.State, +cand: String, +my_nick: String, +word: String) -> Bool:
  nick_match.ok(Isupport.cm_eq(iso, cand, my_nick), String.starts_with(Isupport.cm_fold(iso, cand), Isupport.cm_fold(iso, word)))

def match_nicks_iso.go(+iso: Isupport.State, xs: List<&2, String>, +my_nick: String, +word: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, +t}:
      +rest = match_nicks_iso.go(iso, t, my_nick, word)
      match_nicks.keep(h, rest, nick_match_iso(iso, h, my_nick, word))

def comp_candidates_iso.on(+iso: Isupport.State, +cl: Cl.Client, +word: String, slash: Bool) -> List<&2, String>:
  match slash:
    case True{}:
      match_slash.go(slash_command_list(), word)
    case False{}:
      match_nicks_iso.go(iso, Cl.active_nicks(cl), Cl.nick_of(cl), word)

def comp_candidates_iso(+iso: Isupport.State, +cl: Cl.Client, +word: String) -> List<&2, String>:
  comp_candidates_iso.on(iso, cl, word, is_slash_word(word))

def comp_step_iso.active(+iso: Isupport.State, +cl: Cl.Client, +pre: String, +word: String, +idx: Nat, +typed: String) -> Comp & String & U32:
  +matches = comp_candidates_iso(iso, cl, word)
  +len = List.length(&2, String, matches)
  comp_pick.on(matches, pre, word, typed, comp_next_idx(idx, len), Nat.is_eq(len, 0n))

def comp_step_iso.fresh(+iso: Isupport.State, +cl: Cl.Client, pair: String & String, +typed: String) -> Comp & String & U32:
  match pair:
    case (+pre, +word):
      +matches = comp_candidates_iso(iso, cl, word)
      comp_pick.on(matches, pre, word, typed, 0n, Nat.is_eq(List.length(&2, String, matches), 0n))

def comp_step_iso.upload(+iso: Isupport.State, word: Maybe<&2, CompWord>, +cl: Cl.Client, +typed: String) -> Comp & String & U32:
  match word:
    case None{}: comp_step_iso.fresh(iso, cl, split_word(typed), typed)
    case Some{CompWord{pre, word, idx}}: comp_step_iso.active(iso, cl, pre, word, idx, typed)

def comp_step_iso(+iso: Isupport.State, +cl: Cl.Client, comp: Comp, +typed: String) -> Comp & String & U32:
  match comp:
    case CompNone{}:
      comp_step_iso.fresh(iso, cl, split_word(typed), typed)
    case CompActive{+pre, +word, idx}:
      comp_step_iso.active(iso, cl, pre, word, idx, typed)
    case CompUpload{_, completion, _}:
      comp_step_iso.upload(iso, completion, cl, typed)
    case CompHelp{_}:
      comp_step_iso.fresh(iso, cl, split_word(typed), typed)
    case CompHidden{}:
      comp_step_iso.fresh(iso, cl, split_word(typed), typed)
    case CompPick{_}:
      comp_step_iso.fresh(iso, cl, split_word(typed), typed)

def comp_step_ok.check(c: Comp, +str: String, seed: U32) -> Bool:
  String.eq(str, "/join ") && U32.is_eq(seed, 1)

def comp_step_ok.got(trip: Comp & String & U32) -> Bool:
  match trip:
    case (c, str, seed):
      comp_step_ok.check(c, str, seed)

# Slash-command completion under defaults is identical to every CASEMAPPING
# (ASCII-only verbs). Laws and tests call the negotiated ladder.
def comp_step_ok() -> Bool:
  comp_step_ok.got(comp_step_iso(Isupport.defaults(), Cl.init("me", "s"), comp0(), "/j"))


type Size is Data:
  Size{rows: U32, cols: U32}

type Session is Data:
  Session{
    cl: Cl.Client,
    drop: Bool,
    rem: List<&2, U32>,
    draft: String,
    joined: Bool,
    chan: String,
    net: NetState,
    hist: Hist,
    size: Size,
    seed: U32,
    comp: Comp,
    split: Sp.State,
    typing: Ty.State,
    port: U32,
    # Boxed one-element cell (same idiom as cf): M.State is ~16 flattened
    # words; four live Sessions across an eight-assertion chain overflow the
    # pinned 247-word backend cap without it.
    media: List<&2, M.State>,
    plan: JoinPlan.State,
    preference_edits: List<&2, String>,
    # Boxed one-element cell (same idiom as media/cf/reg): the ISUPPORT
    # record no longer flattens into every live Session across IO waits.
    iso: List<&2, Isupport.State>,
    # Boxed one-element cell (same idiom as media/cf/reg): HistLive is ~27
    # flattened words; a live Part plus Session across one media bind
    # overflow the pinned 247-word backend cap without it.
    hist_live: List<&2, Hs.HistLive>,
    # One boxed one-element cell (live_context idiom): the pinned Bend backend
    # caps flattened continuation words (247), and four live Sessions across an
    # eight-assertion chain already overflow it. One field holding the retained
    # cards/full pair keeps base margins.
    cf: List<&2, C.Retained>,
    # G6 live: reg is the stored registration (negotiated caps plus outbound
    # typing). Live CAP lines update it in the line fold; TypingTick and composer
    # frames step it via session_tick_typing. Endpoint transitions reset it with
    # the other per-endpoint state (typing, media); all other paths preserve it.
    # Boxed one-element cell (same idiom as media/cf): Reg is ~11 flattened
    # words and law fixtures hold six live Sessions across one conjunction.
    reg: List<&2, CapNotify.Reg>,
    theme: Theme.Id,
    # Labeled-response outbound counter (next id suffix). Boxed one-element
    # cell (same idiom as reg): session_next_label mints "birc-<n>" and
    # increments. Preserved across endpoint transitions; fresh sessions start
    # at zero.
    labels: List<&2, Nat>,
    # Optimistic-send ledger (bounded PEND_MAX): unconfirmed echo-message
    # sends rendered as a view-only dimmed overlay. A List field stays a
    # narrow capture (same reason SBox works); entries age out on TypingTick.
    pends: List<&2, Cl.PendSend>
  }

def unbox_cards(+xs: List<&2, C.Retained>) -> C.State:
  match xs:
    case Con{C.Retained{+st, _}, _}: st
    case _: C.initial(True{})

def unbox_iso(+xs: List<&2, Isupport.State>) -> Isupport.State:
  match xs:
    case Con{+iso, _}: iso
    case _: Isupport.defaults()

def unbox_full(+xs: List<&2, C.Retained>) -> C.Fullscreen:
  match xs:
    case Con{C.Retained{_, +full}, _}: full
    case _: C.FullOff{}

def unbox_media(+xs: List<&2, M.State>) -> M.State:
  match xs:
    case Con{+media, _}: media
    case _: M.initial(True{})

def unbox_reg(+xs: List<&2, CapNotify.Reg>) -> CapNotify.Reg:
  match xs:
    case Con{+reg, _}: reg
    case _: CapNotify.reg0()

def unbox_labels(+xs: List<&2, Nat>) -> Nat:
  match xs:
    case Con{+n, _}: n
    case _: 0n

def SIZE0() -> Size:
  Size{24, 80}

# Live sessions scope the history owner to the exact startup host:port
# (gate H); demo/offline sessions stay unscoped (hist_live0).
def session_with_client_at(+cl: Cl.Client, +chan: String, +port: U32) -> Session:
  +plan = JoinPlan.reset(JoinPlan.initial(chan), cl, port)
  +hl = Hs.hist_live_sync(Hs.hist_live0(), 0n, Ep.endpoint(Cl.server_of(cl), port))
  Session{cl, False{}, Nil{}, "", JoinPlan.sent(plan), chan, Connecting{}, hist0(), SIZE0(), 0, comp0(), Sp.state0(), Ty.empty(), port, [M.initial(True{})], plan, Nil{}, [Isupport.defaults()], [hl], [C.Retained{C.initial(True{}), C.FullOff{}}], [CapNotify.reg0()], Theme.default(), [0n], Nil{}}

def session_with_client(+cl: Cl.Client, +chan: String) -> Session:
  session_with_client_at(cl, chan, Transport.TLS_PORT())

def session0(+nick: String, +host: String, +chan: String) -> Session:
  session_with_client(Cl.init(nick, host), chan)

def session_demo_at(+cl: Cl.Client, +chan: String, port: U32) -> Session:
  +plan = JoinPlan.demo(chan)
  Session{cl, False{}, Nil{}, "", JoinPlan.sent(plan), chan, Demo{}, hist0(), SIZE0(), 0, comp0(), Sp.state0(), Ty.empty(), port, [M.initial(True{})], plan, Nil{}, [Isupport.defaults()], [Hs.hist_live0()], [C.Retained{C.initial(True{}), C.FullOff{}}], [CapNotify.reg0()], Theme.default(), [0n], Nil{}}

def session_demo(+cl: Cl.Client, +chan: String) -> Session:
  session_demo_at(cl, chan, Transport.TLS_PORT())

# ---- ISUPPORT live runtime (I2) -------------------------------------------
# Session carries one Isupport.State per endpoint (the `iso` field, reusing
# the one canonical Isupport.State identity). Framed 005 lines feed it
# through Isupport.feed_state with server-only trust (per wire line in
# live_step.prep, gated against the pre-line client); a Dial to a new
# endpoint resets via Isupport.endpoint (session_after); session_admit and
# session_outs_admitted gate joins at submit/flush time; session_redact and
# friends drive live MODE/324 display (session_redact_wire rebuilds only
# key-bearing lines, preserving tag blocks); session_chan_target routes
# STATUSMSG audiences with exact-resident precedence; session_cm_eq
# compares identities under the negotiated CASEMAPPING (001 handling).
def session_iso(+st: Session) -> Isupport.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +isobox, _, _, _, _, labelsbox, +pends}: unbox_iso(isobox)

def session_cm(+st: Session) -> String:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +isobox, _, _, _, _, labelsbox, +pends}: Isupport.casemapping(unbox_iso(isobox))

def session_set_iso(st: Session, +iso: Isupport.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, _, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, [iso], hlbox, cf, regbox, theme, labelsbox, pends}

def session_admit(+s: Session, +name: String, +key: String) -> Bool:
  match s:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +isobox, _, _, _, _, labelsbox, +pends}: Isupport.join_admit(unbox_iso(isobox), name, key)

def session_redact(+s: Session, +target: String, +flags: String, +args: List<&2, String>) -> List<&2, String>:
  match s:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +isobox, _, _, _, _, labelsbox, +pends}: Isupport.redact_params(unbox_iso(isobox), target, flags, args)

def session_chan_target(+s: Session, +t: String) -> String:
  match s:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +isobox, _, _, _, _, labelsbox, +pends}: Isupport.chan_target_cl(unbox_iso(isobox), cl, t)

def session_cm_eq(+s: Session, +a: String, +b: String) -> Bool:
  match s:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +isobox, _, _, _, _, labelsbox, +pends}: Isupport.cm_eq(unbox_iso(isobox), a, b)

def session_redact_wire.tag_word(pair: String & String) -> String:
  match pair:
    case (tags, _): tags ++ " "

def session_redact_wire.tags(+line: String, tagged: Bool) -> String:
  match tagged:
    case False{}: ""
    case True{}: session_redact_wire.tag_word(Irc.take_until_space(Irc.drop_spaces(line)))

def session_redact_wire.prefix(+prefix: String, empty: Bool) -> String:
  match empty:
    case True{}: ""
    case False{}: ":" ++ prefix ++ " "

def session_redact_wire.rebuild(+line: String, +cmd: String, +ps: List<&2, String>) -> String:
  +prefix = Irc.source_prefix(line)
  session_redact_wire.tags(line, String.starts_with(Irc.drop_spaces(line), "@"))
    ++ session_redact_wire.prefix(prefix, String.is_empty(prefix))
    ++ cmd ++ " " ++ String.join(ps, " ")

def session_redact_wire.redact(+iso: Isupport.State, +line: String, +cmd: String, +head: List<&2, String>, +target: String, +flags: String, +args: List<&2, String>, bad: Bool) -> String:
  match bad:
    case False{}: line
    case True{}: session_redact_wire.rebuild(line, cmd, List.append(&2, String, head, Isupport.redact_params(iso, target, flags, args)))

def session_redact_wire.args(+iso: Isupport.State, +line: String, +cmd: String, +head: List<&2, String>, +target: String, +flags: String, +args: List<&2, String>) -> String:
  session_redact_wire.redact(iso, line, cmd, head, target, flags, args, Isupport.suspicious(iso, target, flags, args))

def session_redact_wire.num(+iso: Isupport.State, +line: String, +m: Irc.Message, is324: Bool) -> String:
  match is324:
    case False{}: line
    case True{}: session_redact_wire.args(iso, line, Irc.msg_command(m), List.take(&2, String, Irc.msg_params(m), 3n), Irc.msg_param(m, 1n), Irc.msg_param(m, 2n), List.drop(&2, String, Irc.msg_params(m), 3n))

def session_redact_wire.msg(+iso: Isupport.State, +line: String, +m: Irc.Message, mode: Bool) -> String:
  match mode:
    case True{}: session_redact_wire.args(iso, line, Irc.msg_command(m), List.take(&2, String, Irc.msg_params(m), 2n), Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), List.drop(&2, String, Irc.msg_params(m), 2n))
    case False{}: session_redact_wire.num(iso, line, m, U32.is_eq(Irc.msg_num(m), 324))

def session_redact_wire.parsed(+iso: Isupport.State, +line: String, parsed: Maybe<&2, Irc.Message>) -> String:
  match parsed:
    case None{}: line
    case Some{+m}: session_redact_wire.msg(iso, line, m, Irc.ieq(Irc.msg_command(m), "MODE"))

def session_redact_wire(+iso: Isupport.State, +line: String) -> String:
  session_redact_wire.parsed(iso, line, Irc.parse(line))

def session_admit_targets(+iso: Isupport.State, +targets: List<&2, String>, +keys: List<&2, String>) -> Bool:
  match targets:
    case Nil{}: True{}
    case Con{+target, rest}:
      match keys:
        case Nil{}: Isupport.join_admit(iso, target, "") && session_admit_targets(iso, rest, Nil{})
        case Con{+key, key_rest}: Isupport.join_admit(iso, target, key) && session_admit_targets(iso, rest, key_rest)

def session_admit_join(+iso: Isupport.State, +m: Irc.Message, zero: Bool) -> Bool:
  match zero:
    case True{}: True{}
    case False{}: session_admit_targets(iso, String.split(Irc.msg_param(m, 0n), Chr{44}), String.split(Irc.msg_param(m, 1n), Chr{44}))

def session_admit_msg(+iso: Isupport.State, +m: Irc.Message, join: Bool) -> Bool:
  match join:
    case False{}: True{}
    case True{}: session_admit_join(iso, m, String.eq(Irc.msg_param(m, 0n), "0"))

def session_admit_parsed(+iso: Isupport.State, parsed: Maybe<&2, Irc.Message>) -> Bool:
  match parsed:
    case None{}: True{}
    case Some{+m}: session_admit_msg(iso, m, Irc.ieq(Irc.msg_command(m), "JOIN"))

def session_outs_admitted.go(+iso: Isupport.State, +outs: List<&2, String>) -> Bool:
  match outs:
    case Nil{}: True{}
    case Con{+line, rest}: session_admit_parsed(iso, Irc.parse(line)) && session_outs_admitted.go(iso, rest)

def session_outs_admitted(+st: Session, +outs: List<&2, String>) -> Bool:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +isobox, _, _, _, _, labelsbox, +pends}: session_outs_admitted.go(unbox_iso(isobox), outs)

def session_cl(+st: Session) -> Cl.Client:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      cl

# Explicit accepted settings intent, not a value difference or a log-text guess.
# Only the eleven canonical durable names are inserted by the submission hook.

def session_pends(+st: Session) -> List<&2, Cl.PendSend>:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +pends}: pends

def session_set_pends(st: Session, +pends: List<&2, Cl.PendSend>) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, +theme, +labelsbox, _}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}


def session_preference_edits(st: Session) -> List<&2, String>:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, edits, _, _, _, _, _, labelsbox, +pends}: edits

def session_preference_record.on(known: Bool, st: Session, name: String) -> Session:
  match known:
    case True{}: st
    case False{}:
      match st:
        case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, +iso, +hlbox, cf, +regbox, +theme, labelsbox, +pends}:
          Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, List.append(&2, String, edits, name <> Nil{}), iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_preference_record(parsed: Maybe<&2, String>, +st: Session) -> Session:
  match parsed:
    case None{}: st
    case Some{+name}: session_preference_record.on(Prefs.has(session_preference_edits(st), name), st, name)

def session_net(+st: Session) -> NetState:
  match st:
    case Session{_, _, _, _, _, _, net, _, _, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      net

def session_stopping.net(net: NetState) -> Maybe<&2, Bool>:
  match net:
    case Stopping{wait}: Some{wait}
    case _: None{}

def session_stopping(st: Session) -> Maybe<&2, Bool>:
  session_stopping.net(session_net(st))

def session_plan(st: Session) -> JoinPlan.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, plan, +edits, _, _, _, _, _, labelsbox, +pends}: plan

def session_set_plan(st: Session, +plan: JoinPlan.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, _, chan, net, hist, size, seed, comp, split, typing, port, media, _, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_channel_revision(st: Session) -> Nat:
  JoinPlan.revision(session_plan(st))

def session_desired_channels(st: Session) -> List<&2, String>:
  JoinPlan.desired_names(session_plan(st))

def session_seed_channels(+st: Session, names: List<&2, String>) -> Session:
  session_set_plan(st, JoinPlan.seed_iso(session_plan(st), names, session_iso(st)))

def session_seed_channels_if.on(same: Bool, st: Session, names: List<&2, String>) -> Session:
  match same:
    case False{}: st
    case True{}: session_seed_channels(st, names)

def session_seed_channels_if(+st: Session, baseline: Nat, names: List<&2, String>) -> Session:
  session_seed_channels_if.on(Nat.is_eq(session_channel_revision(st), baseline), st, names)

def session_hold_joins(+st: Session) -> Session:
  session_set_plan(st, JoinPlan.set_held(session_plan(st), True{}))

# Install an IO-loaded client without changing connection or UI state.
def session_set_client(st: Session, +cl: Cl.Client) -> Session:
  match st:
    case Session{_, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

# ---- live history owner ---------------------------------------------------
# Session carries one Hs.HistLive: the chathistory batch collector, the
# outstanding/completed search stamps, the server-fetch cursor anchor, the
# live connection sync point, and the accumulated CAP registry. The live
# loop stamps a search with history_search_begin, records the finished
# scan/fetch with history_search_complete, and imports through the gated
# entries below. Stale tickets, wrong generations, and endpoint mismatches
# stay quiet; any live sync move resets the batch and negotiated caps.
def unbox_hist_live(+xs: List<&2, Hs.HistLive>) -> Hs.HistLive:
  match xs:
    case Con{+hl, _}: hl
    case _: Hs.hist_live0()

def session_hist_live(st: Session) -> Hs.HistLive:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +hlbox, _, _, _, labelsbox, +pends}: unbox_hist_live(hlbox)

def session_negotiated(+st: Session) -> Bool:
  Hs.hist_live_negotiated(session_hist_live(st))

def session_set_hist_live(st: Session, +hl: Hs.HistLive) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, +plan, edits, +iso, _, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, [hl], cf, regbox, theme, labelsbox, pends}

def history_note_endpoint(+st: Session, +gen: Nat, +endpoint: String) -> Session:
  session_set_hist_live(st, Hs.hist_live_sync(session_hist_live(st), gen, endpoint))

def history_search_begin.stamped(pair: Hs.HistLive & Nat, +st: Session) -> Session & Nat:
  match pair:
    case (+hl2, +ticket): (session_set_hist_live(st, hl2), ticket)

def history_search_begin(+st: Session) -> Session & Nat:
  history_search_begin.stamped(Hs.hist_live_begin(session_hist_live(st)), st)

# Fetch begin: an actually-issued CHATHISTORY request arms batch completion
# for its target. Search/page use history_search_begin (disk only).
def history_fetch_begin(+st: Session, +target: String) -> Session & Nat:
  history_search_begin.stamped(Hs.hist_live_begin_fetch(session_hist_live(st), target), st)

def history_search_complete(+st: Session, +ticket: Nat, +gen: Nat, +endpoint: String) -> Session:
  session_set_hist_live(st, Hs.hist_live_complete(session_hist_live(st), ticket, gen, endpoint))

def history_fetch_cursor(+st: Session, +oldest: String) -> Session:
  session_set_hist_live(st, Hs.hist_live_fetch_cursor(session_hist_live(st), oldest))

# Checkpoint-neutral *search* import for completed disk/server pages. The
# returned seed is the post-import log_seq: import mints no event IDs and
# *search* is synthetic, so the seed equals the pre-import log_seq and
# restored rows are never appended again. An admitted import consumes its
# exact ticket once. Rejected completions stay quiet: the session is
# returned unchanged with its current log_seq.
def history_import_search.gated(admitted: Bool, +st: Session, +orig: String, +page: Hs.DiskPage) -> Session & Nat:
  match admitted:
    case True{}:
      +cl2 = Hs.import_page(session_cl(st), orig, page)
      +st2 = session_set_client(st, cl2)
      (session_set_hist_live(st2, Hs.hist_live_consume(session_hist_live(st2))), Cl.log_seq_of(cl2))
    case False{}: (st, Cl.log_seq_of(session_cl(st)))

def history_import_search(+st: Session, +orig: String, +page: Hs.DiskPage) -> Session & Nat:
  history_import_search.gated(Hs.hist_live_search_ok(session_hist_live(st)), st, orig, page)

def history_import_server.gated(admitted: Bool, +st: Session, +target: String, +matches: List<&2, Hs.ServerMatch>, +overflow: Bool) -> Session & Nat:
  match admitted:
    case True{}:
      +cl2 = Hs.import_server_page(session_cl(st), target, matches, overflow)
      +st2 = session_set_client(st, cl2)
      (session_set_hist_live(st2, Hs.hist_live_consume(session_hist_live(st2))), Cl.log_seq_of(cl2))
    case False{}: (st, Cl.log_seq_of(session_cl(st)))

def history_import_server(+st: Session, +target: String, +matches: List<&2, Hs.ServerMatch>, +overflow: Bool) -> Session & Nat:
  history_import_server.gated(Hs.hist_live_page_ok(session_hist_live(st)), st, target, matches, overflow)

# Source-buffer backfill: admitted server matches import into their real
# target with stable accepted fresh IDs (media-admitted, id0 excluded).
# The seed is the post-import log_seq, captured as the history checkpoint.
# The import consumes its exact ticket and records fresh msgids in the
# seen ledger, so repeat and overlap pages mint no new IDs.
def history_import_source.done(pair: Cl.Client & List<&2, String>, +st: Session) -> Session & Nat:
  match pair:
    case (+cl2, +seen2):
      +st2 = session_set_client(st, cl2)
      +hl2 = Hs.hist_live_consume(session_hist_live(st2))
      (session_set_hist_live(st2, Hs.hist_live_note_seen(hl2, seen2)), Cl.log_seq_of(cl2))

def history_import_source.gated(admitted: Bool, +st: Session, +target: String, +matches: List<&2, Hs.ServerMatch>, +overflow: Bool) -> Session & Nat:
  match admitted:
    case True{}:
      history_import_source.done(Hs.import_source_page(session_cl(st), target, matches, overflow,
        Hs.hist_live_seen(session_hist_live(st))), st)
    case False{}: (st, Cl.log_seq_of(session_cl(st)))

def history_import_source(+st: Session, +target: String, +matches: List<&2, Hs.ServerMatch>, +overflow: Bool) -> Session & Nat:
  history_import_source.gated(Hs.hist_live_page_ok(session_hist_live(st)), st, target, matches, overflow)

# Completed-batch drain: a done chathistory batch imports through the real
# source entry when the fetch owner already admitted the page (begin +
# complete + known cursor). Unarmed sessions stay quiet with the batch kept
# for a later completion; admitted drains clear the batch so a second drain
# imports nothing, consume the exact ticket, and install the claimed-ID
# export (the history checkpoint exclusion and notify-bind input).
def history_drain_batch.done(pair: Cl.Client & List<&2, String>, +st: Session, +pre: Nat) -> Session & Nat:
  match pair:
    case (+cl2, +seen2):
      +st2 = session_set_client(st, cl2)
      +hl2 = Hs.hist_live_note_seen(Hs.hist_live_clear_batch(Hs.hist_live_consume(session_hist_live(st2))), seen2)
      (session_set_hist_live(st2, Hs.hist_live_note_archived(hl2, Hs.batch_claimed_ids(pre, Cl.log_seq_of(cl2)))), Cl.log_seq_of(cl2))

def history_drain_batch.gated(admitted: Bool, +st: Session, +target: String, +matches: List<&2, Hs.ServerMatch>, +overflow: Bool) -> Session & Nat:
  match admitted:
    case True{}:
      history_drain_batch.done(Hs.import_source_page(session_cl(st), target, matches, overflow,
        Hs.hist_live_seen(session_hist_live(st))), st, Cl.log_seq_of(session_cl(st)))
    case False{}: (st, Cl.log_seq_of(session_cl(st)))

def history_drain_batch.ticket(+hl: Hs.HistLive) -> Bool:
  Nat.is_eq(Hs.hist_live_batch_ticket(hl), Hs.hist_stamp_ticket(Hs.hist_live_want(hl)))

def history_drain_batch.target(+hl: Hs.HistLive, +btarget: String) -> Bool:
  Hs.request_target_ok(Hs.hist_live_want_target(hl), btarget)

def history_drain_batch(+st: Session) -> Session & Nat:
  +hl = session_hist_live(st)
  +batch = Hs.hist_live_batch(hl)
  +btarget = Hs.batch_import_target(batch)
  history_drain_batch.gated(Hs.batch_done(batch) && Hs.hist_live_page_ok(hl)
    && Bool.not(String.is_empty(btarget))
    && history_drain_batch.ticket(hl) && history_drain_batch.target(hl, btarget),
    st, btarget, Hs.batch_matches(batch), Hs.batch_overflow(batch))

# Ceiling-gated drain twin for multiserver parts: the live ceiling fold
# bounds live rows only, so the archive import runs against a temp client
# and installs atomically only when every minted ID lands below the part
# ceiling. A refused import returns the session untouched (no leaked IDs,
# no consume, no seen/archived ledger effects), keeping the batch armed
# for a later drain; the claimed export is then empty, so no checkpoint
# or notify effect escapes either.
def history_drain_batch_ceiling.fit(overflows: Bool, pair: Cl.Client & List<&2, String>, +st: Session, +pre: Nat) -> Session & Nat:
  match overflows:
    case True{}: (st, Cl.log_seq_of(session_cl(st)))
    case False{}: history_drain_batch.done(pair, st, pre)

def history_drain_batch_ceiling.done(pair: Cl.Client & List<&2, String>, +st: Session, +pre: Nat, +ceiling: Nat) -> Session & Nat:
  match pair:
    case (+cl2, +seen2):
      history_drain_batch_ceiling.fit(Nat.is_ge(Cl.log_seq_of(cl2), ceiling), (cl2, seen2), st, pre)

def history_drain_batch_ceiling.gated(admitted: Bool, +st: Session, +target: String, +matches: List<&2, Hs.ServerMatch>, +overflow: Bool, +ceiling: Nat) -> Session & Nat:
  match admitted:
    case True{}:
      history_drain_batch_ceiling.done(Hs.import_source_page(session_cl(st), target, matches, overflow,
        Hs.hist_live_seen(session_hist_live(st))), st, Cl.log_seq_of(session_cl(st)), ceiling)
    case False{}: (st, Cl.log_seq_of(session_cl(st)))

def history_drain_batch_ceiling(+st: Session, +ceiling: Nat) -> Session & Nat:
  +hl = session_hist_live(st)
  +batch = Hs.hist_live_batch(hl)
  +btarget = Hs.batch_import_target(batch)
  history_drain_batch_ceiling.gated(Hs.batch_done(batch) && Hs.hist_live_page_ok(hl)
    && Bool.not(String.is_empty(btarget))
    && history_drain_batch.ticket(hl) && history_drain_batch.target(hl, btarget),
    st, btarget, Hs.batch_matches(batch), Hs.batch_overflow(batch), ceiling)

# Completion-to-import convenience: records the finished fetch, derives the
# paging cursor from the real collected batch, and drains. Feed-through only.
def history_complete_batch.oldest(+st: Session, +ticket: Nat, +gen: Nat, +endpoint: String, +oldest: String) -> Session & Nat:
  history_drain_batch(history_fetch_cursor(history_search_complete(st, ticket, gen, endpoint), oldest))

def history_complete_oldest(+st: Session) -> String:
  Hs.server_oldest(Hs.batch_matches(Hs.hist_live_batch(session_hist_live(st))))

def history_complete_batch(+st: Session, +ticket: Nat, +gen: Nat, +endpoint: String) -> Session & Nat:
  history_complete_batch.oldest(st, ticket, gen, endpoint, history_complete_oldest(st))

def history_complete_batch_ceiling.oldest(+st: Session, +ticket: Nat, +gen: Nat, +endpoint: String, +oldest: String, +ceiling: Nat) -> Session & Nat:
  history_drain_batch_ceiling(history_fetch_cursor(history_search_complete(st, ticket, gen, endpoint), oldest), ceiling)

def history_complete_batch_ceiling(+st: Session, +ticket: Nat, +gen: Nat, +endpoint: String, +ceiling: Nat) -> Session & Nat:
  history_complete_batch_ceiling.oldest(st, ticket, gen, endpoint, history_complete_oldest(st), ceiling)

# Drain plus the batch-claimed ID export: exactly the fresh IDs the import
# minted, per-ID, so N9-full can exclude archived rows without a floor bump.
def history_drain_claimed.pre(+pre: Nat, pair: Session & Nat) -> Session & Nat & List<&2, Nat>:
  match pair:
    case (+st2, +seed): (st2, seed, Hs.batch_claimed_ids(pre, Cl.log_seq_of(session_cl(st2))))

def history_drain_claimed(+st: Session) -> Session & Nat & List<&2, Nat>:
  history_drain_claimed.pre(Cl.log_seq_of(session_cl(st)), history_drain_batch(st))

def history_complete_claimed.pre(+pre: Nat, pair: Session & Nat) -> Session & Nat & List<&2, Nat>:
  history_drain_claimed.pre(pre, pair)

def history_complete_claimed(+st: Session, +ticket: Nat, +gen: Nat, +endpoint: String) -> Session & Nat & List<&2, Nat>:
  history_complete_claimed.pre(Cl.log_seq_of(session_cl(st)), history_complete_batch(st, ticket, gen, endpoint))

def history_complete_claimed_ceiling(+st: Session, +ticket: Nat, +gen: Nat, +endpoint: String, +ceiling: Nat) -> Session & Nat & List<&2, Nat>:
  history_complete_claimed.pre(Cl.log_seq_of(session_cl(st)), history_complete_batch_ceiling(st, ticket, gen, endpoint, ceiling))

# Live completion trigger: a done batch that arrived under the CURRENT
# outstanding ticket completes itself with the live stamps and drains
# through the claimed export. Unsolicited, stale, and unarmed batches
# stay quiet with the session untouched.
def history_complete_self.go(ready: Bool, +st: Session) -> Session & Nat & List<&2, Nat>:
  match ready:
    case True{}:
      +hl = session_hist_live(st)
      history_complete_claimed(st, Hs.hist_stamp_ticket(Hs.hist_live_want(hl)), Hs.hist_live_gen(hl), Hs.hist_live_endpoint(hl))
    case False{}: (st, Cl.log_seq_of(session_cl(st)), Nil{})

def history_complete_self(+st: Session) -> Session & Nat & List<&2, Nat>:
  history_complete_self.go(Hs.hist_batch_self_complete(session_hist_live(st)), st)

def history_complete_self_ceiling.go(ready: Bool, +st: Session, +ceiling: Nat) -> Session & Nat & List<&2, Nat>:
  match ready:
    case True{}:
      +hl = session_hist_live(st)
      history_complete_claimed_ceiling(st, Hs.hist_stamp_ticket(Hs.hist_live_want(hl)), Hs.hist_live_gen(hl), Hs.hist_live_endpoint(hl), ceiling)
    case False{}: (st, Cl.log_seq_of(session_cl(st)), Nil{})

def history_complete_self_ceiling(+st: Session, +ceiling: Nat) -> Session & Nat & List<&2, Nat>:
  history_complete_self_ceiling.go(Hs.hist_batch_self_complete(session_hist_live(st)), st, ceiling)

# Async disk-search completion against the CURRENT session: records the
# worker's ticket and imports when the live owner admits (nonzero ticket,
# exact stamps, unconsumed). Returns whether a page landed so the loop
# repaints only for real imports. Refusals and stale completions stay
# quiet with the session unchanged.
def history_search_done.found(pair: Session & Nat, admitted: Bool) -> Session & Nat & Bool:
  match pair:
    case (+st2, +seed): (st2, seed, admitted)

def history_search_done.page(+page: Hs.DiskPage, +st: Session, +orig: String, admitted: Bool) -> Session & Nat & Bool:
  match admitted:
    case True{}: history_search_done.found(history_import_search(st, orig, page), True{})
    case False{}: (st, Cl.log_seq_of(session_cl(st)), False{})

def history_search_done.result(result: Hs.DiskResult, +st: Session, +orig: String, admitted: Bool) -> Session & Nat & Bool:
  match result:
    case Hs.DiskFound{+page}: history_search_done.page(page, st, orig, admitted)
    case Hs.DiskFailed{_}: (st, Cl.log_seq_of(session_cl(st)), False{})

def history_search_done(+st: Session, +ticket: Nat, +gen: Nat, +endpoint: String, +orig: String, +result: Hs.DiskResult) -> Session & Nat & Bool:
  +stc = history_search_complete(st, ticket, gen, endpoint)
  history_search_done.result(result, stc, orig, Hs.hist_live_done_ok(session_hist_live(stc)))

def join_notice(cl: Cl.Client, notice: JoinPlan.Notice) -> Cl.Client:
  match notice:
    case JoinPlan.Quiet{}: cl
    case JoinPlan.Held{}: Cl.diagnostic_notice(cl, Cl.System{}, "channel joins held: waiting for authentication")
    case JoinPlan.Failed{}: Cl.diagnostic_notice(cl, Cl.Error{}, "channel joins held: authentication failed; reconnect to retry")

def session_flush_joins.got(+st: Session, got: JoinPlan.Flush) -> Session & List<&2, String>:
  match got:
    case JoinPlan.Flush{plan, outs, notice}:
      (session_set_client(session_set_plan(st, plan), join_notice(session_cl(st), notice)), outs)

def session_flush_joins(+st: Session) -> Session & List<&2, String>:
  session_flush_joins.got(st, JoinPlan.flush_iso(session_plan(st), session_cl(st), session_iso(st)))

def session_resume_joins(+st: Session) -> Session & List<&2, String>:
  session_flush_joins(session_set_plan(st, JoinPlan.set_held(session_plan(st), False{})))

def session_split(+st: Session) -> Sp.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, split, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}: split

def split_key_ok() -> Bool:
  pol_eq(key_pol_raw(KEY_F6(), 0, 0, 0, 9n), 0, 0, 0, 0, 0, 0, 1)
    && pol_eq(key_pol_raw(0, MOD_CTRL(), 119, 0, 9n), 0, 0, 0, 0, 0, 0, 1)
    && pol_eq(key_pol_raw(0, MOD_CTRL(), 120, 0, 9n), 0, 0, 0, 0, 0, 0, 0)

def session_needs_reconnect_marker(+st: Session) -> Bool:
  match st:
    case Session{_, _, _, _, _, _, net, _, _, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      match net:
        case Offline{}: True{}
        case Reconnecting{}: True{}
        case _: False{}

def session_reset_auth(st: Session) -> Session:
  match st:
    case Session{+cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, +port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      +fresh = Cl.reset_auth(cl)
      +next = JoinPlan.reset(plan, fresh, port)
      Session{fresh, drop, rem, draft, JoinPlan.sent(next), chan, net, hist, size, seed, comp, split, typing, port, media, next, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def comp_upload_state(comp: Comp) -> Up.State:
  match comp:
    case CompUpload{state, _, _}: state
    case _: Up.empty()

def session_upload(st: Session) -> Up.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, comp, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}: comp_upload_state(comp)

def session_upload_scope(st: Session) -> Up.Scope:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, port, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      Up.Scope{Cl.server_of(cl), port, Cl.active_buf_name(cl)}

def session_upload_online.net(net: NetState) -> Bool:
  match net:
    case Online{}: True{}
    case _: False{}

def session_upload_online(st: Session) -> Bool:
  match st:
    case Session{+cl, _, _, _, _, _, net, _, _, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      session_upload_online.net(net) && Bool.not(Nat.is_eq(Cl.active_of(cl), 0n) || Sub.active_is_synthetic(cl))

# Only an unchanged Confirm can cross the presentation barrier. In particular,
# Busy -> Confirm resets it even when two batch files have the same path.
def upload_confirmation_eq(before: Up.State, after: Up.State) -> Bool:
  match before:
    case Up.Confirm{request, _}:
      match after:
        case Up.Confirm{next, _}: Up.request_eq(request, next)
        case _: False{}
    case _: False{}

def comp_upload_presented(comp: Comp) -> Bool:
  match comp:
    case CompUpload{Up.Confirm{_, _}, _, presented}: presented
    case _: False{}

def session_upload_presented(st: Session) -> Bool:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, comp, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}: comp_upload_presented(comp)

def comp_set_upload(+state: Up.State, +comp: Comp) -> Comp:
  match state:
    case Up.Idle{}: comp_ordinary(comp)
    case _: CompUpload{state, comp_word(comp), comp_upload_presented(comp) && upload_confirmation_eq(comp_upload_state(comp), state)}

def session_set_upload(st: Session, state: Up.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp_set_upload(state, comp), split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

# Every connection/focus transition must call this, not only completion. Busy
# retains physical ownership but cannot regain permission after leaving scope.
def session_upload_maintain(+st: Session) -> Session:
  session_set_upload(st, Up.retain(session_upload(st), session_upload_scope(st), session_upload_online(st)))

# Net chokepoint: Offline/Connecting/Reconnecting/Stopping clear upload online;
# retain drops Confirm/Armed and cancels Busy permission without releasing ownership.
def session_set_net(st: Session, net: NetState) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, _, hist, size, seed, comp, split, typing, port, media, plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      session_upload_maintain(Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends})

def session_online(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      # JoinPlan.sent then Online via session_set_net so upload consent is maintained.
      session_set_net(Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, Offline{}, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}, Online{})

def session_reconnected.on(was_off: Bool, +st: Session, +now: String) -> Session:
  match was_off:
    case False{}:
      session_online(st)
    case True{}:
      match st:
        case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
          # Markers + JoinPlan.sent then Online via session_set_net (same chokepoint as session_online).
          session_set_net(Session{Cl.reconnect_markers(cl, now), drop, rem, draft, JoinPlan.sent(plan), chan, Offline{}, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}, Online{})

def session_reconnected(+st: Session, +now: String) -> Session:
  +reset = session_reset_auth(st)
  +fresh = session_set_client(reset, Cl.reset_channel_state(session_cl(reset)))
  +online = session_reconnected.on(session_needs_reconnect_marker(st), fresh, now)
  # Online must not revive Confirm/Armed that Offline cleared — retain again.
  session_upload_maintain(session_set_client(online, Cl.diagnostic_notice(Cl.set_now(session_cl(online), now), Cl.System{}, "IRC connection established")))

# ---- optimistic-send ledger ------------------------------------------------
# Enter records each echo-message chat wire here (after labeling, so exact
# labels ride along); the view overlays dimmed Pending rows until the server
# echo confirms (exact label match, FIFO target+bytes fallback) or the entry
# reverts (30-tick timeout, disconnect, cap eviction). Credential wires never
# record: their echo is consumed by the credential gate and must never
# resurface in the draft. NAK carries no parseable label today, so timeout
# covers server-side rejection.

def pend_label(+mb: Maybe<&2, String>) -> String:
  match mb:
    case None{}: ""
    case Some{+v}: v

def pend_kind.msg(action: Bool) -> Cl.LineKind:
  match action:
    case True{}: Cl.Action{}
    case False{}: Cl.Msg{}

def pend_kind.notice(notice: Bool, action: Bool) -> Cl.LineKind:
  match notice:
    case True{}: Cl.Notice{}
    case False{}: pend_kind.msg(action)

def pend_disp.msg(+nick: String, +body: String, action: Bool) -> String:
  match action:
    case True{}: Feed.fmt_action(nick, Feed.action_text(body))
    case False{}: Feed.fmt_msg(nick, body)

def pend_disp.notice(notice: Bool, +nick: String, +body: String, action: Bool) -> String:
  match notice:
    case True{}: Feed.fmt_msg(nick, body)
    case False{}: pend_disp.msg(nick, body, action)

def pend_body.msg(+body: String, action: Bool) -> String:
  match action:
    case True{}: Feed.action_text(body)
    case False{}: body

def pend_body.notice(notice: Bool, +body: String, action: Bool) -> String:
  match notice:
    case True{}: body
    case False{}: pend_body.msg(body, action)

def pend_from_out.sensitive(sensitive: Bool, +cl: Cl.Client, +isc: Cl.Iso, +out: String, +ts: String, +nick: String, +target: String, +body: String, +notice: Bool) -> Maybe<&2, Cl.PendSend>:
  match sensitive:
    case True{}: None{}
    case False{}:
      +action = Bool.not(notice) && Feed.is_action(body)
      Some{Cl.PendSend{Cl.message_key_with(cl, isc, target), target, pend_label(Irc.label_tag(Irc.raw_tags(out))), body, pend_body.notice(notice, body, action), pend_disp.notice(notice, nick, body, action), ts, pend_kind.notice(notice, action), 0n}}

def pend_from_out.gated(ok: Bool, +cl: Cl.Client, +isc: Cl.Iso, +out: String, +ts: String, +nick: String, +target: String, +body: String, +notice: Bool) -> Maybe<&2, Cl.PendSend>:
  match ok:
    case False{}: None{}
    case True{}: pend_from_out.sensitive(Sub.credential_message(cl, target, body), cl, isc, out, ts, nick, target, body, notice)

def pend_from_out.parsed(+cl: Cl.Client, +isc: Cl.Iso, +out: String, +ts: String, +nick: String, parsed: Maybe<&2, Irc.Message>) -> Maybe<&2, Cl.PendSend>:
  match parsed:
    case None{}: None{}
    case Some{+m}:
      +verb = Irc.msg_command(m)
      +notice = Irc.ieq(verb, "NOTICE")
      pend_from_out.gated((Irc.ieq(verb, "PRIVMSG") || notice) && Nat.is_eq(List.length(&2, String, Irc.msg_params(m)), 2n), cl, isc, out, ts, nick, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), notice)

def pend_from_out(+cl: Cl.Client, +isc: Cl.Iso, +out: String, +ts: String, +nick: String) -> Maybe<&2, Cl.PendSend>:
  pend_from_out.parsed(cl, isc, out, ts, nick, Irc.parse(out))

def pend_push.evict(+pends: List<&2, Cl.PendSend>, +entry: Cl.PendSend) -> List<&2, Cl.PendSend>:
  match pends:
    case Nil{}: entry <> Nil{}
    case Con{_, t}: List.append(&2, Cl.PendSend, t, entry <> Nil{})

def pend_push.capped(+pends: List<&2, Cl.PendSend>, +entry: Cl.PendSend, full: Bool) -> List<&2, Cl.PendSend>:
  match full:
    case True{}: pend_push.evict(pends, entry)
    case False{}: List.append(&2, Cl.PendSend, pends, entry <> Nil{})

def pend_push(+pends: List<&2, Cl.PendSend>, +entry: Cl.PendSend) -> List<&2, Cl.PendSend>:
  pend_push.capped(pends, entry, Nat.is_ge(List.length(&2, Cl.PendSend, pends), Cl.PEND_MAX()))

def pend_record_one(+pends: List<&2, Cl.PendSend>, +mb: Maybe<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  match mb:
    case None{}: pends
    case Some{+e}: pend_push(pends, e)

def pend_record_outs.go(fuel: Nat, +pends: List<&2, Cl.PendSend>, +cl: Cl.Client, +isc: Cl.Iso, outs: List<&2, String>, +ts: String, +nick: String) -> List<&2, Cl.PendSend>:
  match fuel:
    case 0n: pends
    case 1n+f:
      match outs:
        case Nil{}: pends
        case Con{+h, t}: pend_record_outs.go(f, pend_record_one(pends, pend_from_out(cl, isc, h, ts, nick)), cl, isc, t, ts, nick)

def pend_record_outs(+pends: List<&2, Cl.PendSend>, +cl: Cl.Client, +isc: Cl.Iso, +outs: List<&2, String>, +ts: String, +nick: String) -> List<&2, Cl.PendSend>:
  pend_record_outs.go(List.length(&2, String, outs), pends, cl, isc, outs, ts, nick)


def pend_match_label(+label: String, +p: Cl.PendSend) -> Bool:
  match p:
    case Cl.PendSend{_, _, +elabel, _, _, _, _, _, _}: String.eq(label, elabel)

def pend_drop_label.rest(hit: Bool, +h: Cl.PendSend, +t: List<&2, Cl.PendSend>, +rec: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  match hit:
    case True{}: t
    case False{}: h <> rec

def pend_drop_label(+pends: List<&2, Cl.PendSend>, +label: String) -> List<&2, Cl.PendSend>:
  match pends:
    case Nil{}: Nil{}
    case Con{+h, +t}: pend_drop_label.rest(pend_match_label(label, h), h, t, pend_drop_label(t, label))

def pend_match_fifo(+cm: String, +target: String, +wire: String, +p: Cl.PendSend) -> Bool:
  match p:
    case Cl.PendSend{_, ptarget, _, pwire, _, _, _, _, _}: Cl.buf_eq_cm(cm, target, ptarget) && String.eq(wire, pwire)

def pend_drop_fifo.rest(hit: Bool, +h: Cl.PendSend, +t: List<&2, Cl.PendSend>, +rec: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  match hit:
    case True{}: t
    case False{}: h <> rec

def pend_drop_fifo(+cm: String, +pends: List<&2, Cl.PendSend>, +target: String, +wire: String) -> List<&2, Cl.PendSend>:
  match pends:
    case Nil{}: Nil{}
    case Con{+h, +t}: pend_drop_fifo.rest(pend_match_fifo(cm, target, wire, h), h, t, pend_drop_fifo(cm, t, target, wire))

def pend_confirm_tagged(untagged: Bool, +cm: String, +pends: List<&2, Cl.PendSend>, +label: String, +target: String, +wire: String) -> List<&2, Cl.PendSend>:
  match untagged:
    case True{}: pend_drop_fifo(cm, pends, target, wire)
    case False{}: pend_drop_label(pends, label)

def pend_confirm_echo.gated(ok: Bool, +cm: String, +pends: List<&2, Cl.PendSend>, +label: String, +target: String, +wire: String) -> List<&2, Cl.PendSend>:
  match ok:
    case False{}: pends
    case True{}: pend_confirm_tagged(String.is_empty(label), cm, pends, label, target, wire)

def pend_confirm_line.chat(chat: Bool, +cm: String, +pends: List<&2, Cl.PendSend>, +nick: String, +line: String, +m: Irc.Message) -> List<&2, Cl.PendSend>:
  match chat:
    case False{}: pends
    case True{}:
      pend_confirm_echo.gated(Cl.nick_eq_cm(cm, Irc.msg_nick(m), nick) && Nat.is_ge(List.length(&2, String, Irc.msg_params(m)), 2n), cm, pends, pend_label(Irc.label_tag(Irc.raw_tags(line))), Irc.msg_param(m, 0n), Irc.msg_param(m, 1n))

def pend_confirm_line.parsed(+cm: String, +pends: List<&2, Cl.PendSend>, +nick: String, +line: String, parsed: Maybe<&2, Irc.Message>) -> List<&2, Cl.PendSend>:
  match parsed:
    case None{}: pends
    case Some{+m}:
      +verb = Irc.msg_command(m)
      pend_confirm_line.chat(Irc.ieq(verb, "PRIVMSG") || Irc.ieq(verb, "NOTICE"), cm, pends, nick, line, m)

def pend_confirm_line(+cm: String, +pends: List<&2, Cl.PendSend>, +nick: String, +line: String) -> List<&2, Cl.PendSend>:
  pend_confirm_line.parsed(cm, pends, nick, line, Irc.parse(line))

def pend_confirm_lines.go(fuel: Nat, +cm: String, +pends: List<&2, Cl.PendSend>, +nick: String, lines: List<&2, String>) -> List<&2, Cl.PendSend>:
  match fuel:
    case 0n: pends
    case 1n+f:
      match lines:
        case Nil{}: pends
        case Con{+h, t}: pend_confirm_lines.go(f, cm, pend_confirm_line(cm, pends, nick, h), nick, t)

def pend_confirm_lines(+cm: String, +pends: List<&2, Cl.PendSend>, +nick: String, +lines: List<&2, String>) -> List<&2, Cl.PendSend>:
  pend_confirm_lines.go(List.length(&2, String, lines), cm, pends, nick, lines)

def pend_age_one(+p: Cl.PendSend) -> Cl.PendSend:
  match p:
    case Cl.PendSend{+buf, +target, +label, +wire, +body, +disp, +ts, +kind, +age}: Cl.PendSend{buf, target, label, wire, body, disp, ts, kind, 1n+age}

def pend_age_all.go(fuel: Nat, +pends: List<&2, Cl.PendSend>, +aged: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  match fuel:
    case 0n: List.reverse(&2, Cl.PendSend, aged)
    case 1n+f:
      match pends:
        case Nil{}: List.reverse(&2, Cl.PendSend, aged)
        case Con{+h, t}: pend_age_all.go(f, t, pend_age_one(h) <> aged)

def pend_age_all(+pends: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  pend_age_all.go(List.length(&2, Cl.PendSend, pends), pends, Nil{})

def pend_age_of(+p: Cl.PendSend) -> Nat:
  match p:
    case Cl.PendSend{_, _, _, _, _, _, _, _, +age}: age

def pend_keep.rest(old: Bool, +h: Cl.PendSend, +rec: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  match old:
    case True{}: rec
    case False{}: h <> rec

def pend_keep.go(fuel: Nat, pends: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  match fuel:
    case 0n: Nil{}
    case 1n+f:
      match pends:
        case Nil{}: Nil{}
        case Con{+h, t}: pend_keep.rest(Nat.is_ge(pend_age_of(h), Cl.PEND_TICKS()), h, pend_keep.go(f, t))

def pend_drop.rest(old: Bool, +h: Cl.PendSend, +rec: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  match old:
    case True{}: h <> rec
    case False{}: rec

def pend_drop.go(fuel: Nat, pends: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend>:
  match fuel:
    case 0n: Nil{}
    case 1n+f:
      match pends:
        case Nil{}: Nil{}
        case Con{+h, t}: pend_drop.rest(Nat.is_ge(pend_age_of(h), Cl.PEND_TICKS()), h, pend_drop.go(f, t))

def pend_reaped.any(+reaped: List<&2, Cl.PendSend>) -> Bool:
  match reaped:
    case Nil{}: False{}
    case Con{_, _}: True{}

def pend_reap.split(+pends: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend> & List<&2, Cl.PendSend>:
  (pend_keep.go(List.length(&2, Cl.PendSend, pends), pends), pend_drop.go(List.length(&2, Cl.PendSend, pends), pends))

def pend_reap.rev(split: List<&2, Cl.PendSend> & List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend> & List<&2, Cl.PendSend>:
  match split:
    case (+kept, +reaped): (kept, List.reverse(&2, Cl.PendSend, reaped))

def pend_reap(+pends: List<&2, Cl.PendSend>) -> List<&2, Cl.PendSend> & List<&2, Cl.PendSend>:
  pend_reap.rev(pend_reap.split(pends))

def pend_restore.kind(+kind: Cl.LineKind, +target: String, +body: String) -> String:
  match kind:
    case Cl.Action{}: "/me " ++ body
    case Cl.Notice{}: "/notice " ++ target ++ " " ++ body
    case _: body

def pend_restore.one(+p: Cl.PendSend) -> String:
  match p:
    case Cl.PendSend{_, +target, _, _, +body, _, _, +kind, _}: pend_restore.kind(kind, target, body)

def pend_restore_text(+reaped: List<&2, Cl.PendSend>) -> String:
  match reaped:
    case Nil{}: ""
    case Con{+h, _}: pend_restore.one(h)

def pend_draft.empty(restore: Bool, +draft: String, +text: String) -> String:
  match restore:
    case True{}: text
    case False{}: draft

def pend_draft(+draft: String, +text: String) -> String:
  pend_draft.empty(String.is_empty(draft) && Bool.not(String.is_empty(text)), draft, text)

def pend_reap_all.some(+pends: List<&2, Cl.PendSend>) -> String & Bool:
  (pend_restore_text(List.reverse(&2, Cl.PendSend, pends)), True{})

def pend_reap_all(+pends: List<&2, Cl.PendSend>) -> String & Bool:
  match pends:
    case Nil{}: ("", False{})
    case Con{+h, +t}: pend_reap_all.some(h <> t)

def pend_count(+pends: List<&2, Cl.PendSend>) -> Nat:
  List.length(&2, Cl.PendSend, pends)


def session_pend_count(+st: Session) -> Nat:
  pend_count(session_pends(st))

def session_fail.reaped.got(reaped: String & Bool, +cl: Cl.Client, +draft: String, joined: Bool, +chan: String, +hist: Hist, +size: Size, +seed: U32, +comp: Comp, split: Sp.State, +port: U32, +media: List<&2, M.State>, +plan: JoinPlan.State, +edits: List<&2, String>, +iso: List<&2, Isupport.State>, +hlbox: List<&2, Hs.HistLive>, +cf: List<&2, C.Retained>, +theme: Theme.Id, +labelsbox: List<&2, Nat>) -> Session:
  match reaped:
    case (+text, _):
      # Offline via session_set_net (same upload chokepoint as dial/cancel/online).
      session_set_net(Session{cl, False{}, Nil{}, pend_draft(draft, text), JoinPlan.sent(plan), chan, Online{}, hist, size, seed, comp, split, Ty.empty(), port, media, plan, edits, iso, hlbox, cf, [CapNotify.reg0()], theme, labelsbox, Nil{}}, Offline{})

def session_fail.got(+msg: String, +st: Session) -> Session:
  match st:
    case Session{+cl, _, _, +draft, joined, +chan, _, +hist, size, seed, +comp, split, _, port, +media, +plan, +edits, +iso, +hlbox, +cf, _, +theme, labelsbox, +pends}:
      session_fail.reaped.got(pend_reap_all(pends), Sub.echo_err_server(cl, msg), draft, joined, chan, hist, size, seed, comp, split, port, media, plan, edits, iso, hlbox, cf, theme, labelsbox)

def session_fail(+st: Session, +msg: String) -> Session:
  # session_set_net Offline already runs session_upload_maintain.
  session_fail.got(msg, st)

# A failed local helper does not change the connection or framer state.
def session_error(+st: Session, +msg: String) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{Sub.echo_err(cl, msg), drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_autoreconnect.st(
  +cl: Cl.Client,
  +draft: String,
  +chan: String,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +server: String,
  +port: U32,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>,
  +iso: Isupport.State,
  +hl: Hs.HistLive,
  +cards: C.State,
  +full: C.Fullscreen,
  +theme: Theme.Id,
  +labelsbox: List<&2, Nat>
) -> Session:
  +cl2 = Sub.echo_sys(cl, "reconnecting in 2s to " ++ server ++ ":" ++ U32.show(port) ++ "...")
  +next = JoinPlan.reset(plan, cl2, port)
  +hl2 = Hs.hist_live_sync(hl, 1n+Hs.hist_live_gen(hl), Ep.endpoint(server, port))
  # Same-endpoint reconnect: Media resets, but text cards and their worker
  # generation survive; the overlay revalidates against the reset Media.
  # Reconnecting via session_set_net: Confirm/Armed cannot survive the dial.
  session_set_net(Session{Cl.diagnostic_notice(cl2, Cl.System{}, "IRC reconnect scheduled in 2s"), False{}, Nil{}, draft, JoinPlan.sent(next), chan, Offline{}, hist, size, seed, comp, split, Ty.empty(), port, [M.reset(media)], next, edits, [iso], [hl2], [C.Retained{cards, C.maintain_full(full, M.reset(media), cl2)}], [CapNotify.reg0()], theme, labelsbox, Nil{}}, Reconnecting{})

def session_autoreconnect.reaped(reaped: String & Bool, +draft: String) -> String:
  match reaped:
    case (+text, _): pend_draft(draft, text)

def session_autoreconnect.dial(ok: Bool, +st: Session, +server: String) -> Session & NetCmd:
  match ok:
    case False{}:
      (st, Drop{})
    case True{}:
      match st:
        case Session{+cl, drop, rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, _, port, +media, +plan, +edits, +iso, +hlbox, +cf, _, +theme, labelsbox, +pends}:
          (session_autoreconnect.st(cl, session_autoreconnect.reaped(pend_reap_all(pends), draft), chan, hist, size, seed, comp, split, server, port, unbox_media(media), plan, edits, unbox_iso(iso), unbox_hist_live(hlbox), unbox_cards(cf), unbox_full(cf), theme, labelsbox), Dial{server, port, 0, Cl.nick_of(cl)})

def session_autoreconnect.chk(auto: Bool, +st: Session, +server: String) -> Session & NetCmd:
  match auto:
    case False{}:
      (st, Drop{})
    case True{}:
      session_autoreconnect.dial(reconnect_configured(session_net(st), server), st, server)

def session_autoreconnect(+st: Session) -> Session & NetCmd:
  +cl = session_cl(st)
  +stg = Cl.get_settings(cl)
  session_autoreconnect.chk(Cl.settings_autoreconn(stg), st, Cl.server_of(cl))

def session_autoreconnect_on(+st: Session) -> Bool:
  Cl.settings_autoreconn(Cl.get_settings(session_cl(st)))

def session_cancel_reconnect(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      # JoinPlan.sent then Offline via session_set_net so upload consent clears.
      session_set_net(Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}, Offline{})

def session_set_now(+st: Session, +ts: String) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{Cl.set_now(cl, ts), drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_set_size(+st: Session, +rows: U32, +cols: U32) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, _, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, Size{rows, cols}, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_theme(st: Session) -> Theme.Id:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, theme, labelsbox, +pends}: theme

def session_set_theme(st: Session, +th: Theme.Id) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, _, labelsbox, +pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, th, labelsbox, pends}

def session_size(+st: Session) -> Size:
  match st:
    case Session{_, _, _, _, _, _, _, _, size, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      size

def size_eq(a: Size, b: Size) -> Bool:
  match a:
    case Size{ar, ac}:
      match b:
        case Size{br, bc}:
          U32.is_eq(ar, br) && U32.is_eq(ac, bc)

def session_port(+st: Session) -> U32:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, port, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}: port

def endpoint_client.same(same: Bool, +cl: Cl.Client, +host: String) -> Cl.Client:
  match same:
    case True{}: Cl.set_server(cl, host)
    case False{}:
      match cl:
        case Cl.Client{+nick, _, _, _, +now, +stg, +auth, +seq, _}:
          +clean = Cl.set_unreads(stg, Nil{})
          Cl.client_set_lag(Cl.Client{nick, host, Cl.server_buf() <> Cl.log_buffers(cl), 0n, now, clean, auth, seq, False{}}, 0)

def dns_ascii_lower.char(+n: U32, upper: Bool) -> U32:
  match upper:
    case True{}: U32.add(n, 32)
    case False{}: n

def dns_ascii_lower(+n: U32) -> U32:
  dns_ascii_lower.char(n, U32.is_ge(n, 65) && U32.is_le(n, 90))

def dns_host_eq.go(fuel: Nat, +a: String, +b: String) -> Bool:
  match fuel:
    case 0n: False{}
    case 1n+p:
      match a b:
        case SNil{} SNil{}: True{}
        case SCon{+ha, +ta} SCon{+hb, +tb}:
          U32.is_eq(dns_ascii_lower(Char.to_u32(ha)), dns_ascii_lower(Char.to_u32(hb))) && dns_host_eq.go(p, ta, tb)
        case _ _: False{}

def dns_host_eq(+a: String, +b: String) -> Bool:
  dns_host_eq.go(Nat.add(1n, Nat.add(String.length(a), String.length(b))), a, b)

def endpoint_same(+cl: Cl.Client, host: String, old_port: U32, new_port: U32) -> Bool:
  dns_host_eq(Cl.server_of(cl), host) && U32.is_eq(old_port, new_port)

def endpoint_client(+cl: Cl.Client, +host: String, +old_port: U32, +new_port: U32) -> Cl.Client:
  endpoint_client.same(endpoint_same(cl, host, old_port, new_port), Cl.scope_auth_endpoint(cl, host, new_port), host)

# A first connection and a changed endpoint have no reconnect boundary.
# Preserve the same-endpoint intent while the socket is being opened.
def dialing_state.prior(net: NetState) -> NetState:
  match net:
    case Online{}: Reconnecting{}
    case Offline{}: Reconnecting{}
    case Reconnecting{}: Reconnecting{}
    case _: Connecting{}

def dialing_state(same: Bool, net: NetState) -> NetState:
  match same:
    case True{}: dialing_state.prior(net)
    case False{}: Connecting{}

# Endpoint-gated cards reset (C8 live): only an exact host+port change bumps
# the cards generation and closes the overlay. Same-endpoint reconnects keep
# text cards and their worker generation even though Media resets; the overlay
# revalidates against the reset Media (a lost token closes it).
def dial_cards(same: Bool, +cards: C.State) -> C.State:
  match same:
    case True{}: cards
    case False{}: C.reset(cards)

def dial_full(same: Bool, +full: C.Fullscreen, +media: M.State, +cl: Cl.Client) -> C.Fullscreen:
  match same:
    case True{}: C.maintain_full(full, media, cl)
    case False{}: C.close(full)

def session_after.dial(
  +cl: Cl.Client,
  +draft: String,
  +chan: String,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +host: String,
  +port: U32,
  +old_port: U32,
  net: NetState,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>,
  +iso: Isupport.State,
  +hl: Hs.HistLive,
  +cards: C.State,
  +full: C.Fullscreen,
  +theme: Theme.Id,
  +labelsbox: List<&2, Nat>
) -> Session:
  +same = endpoint_same(cl, host, old_port, port)
  +next_net = dialing_state(same, net)
  +cl2 = endpoint_client(cl, host, old_port, port)
  +next = JoinPlan.endpoint(same, plan, chan, cl2, port)
  +iso2 = Isupport.endpoint(same, iso)
  +hl2 = Hs.hist_live_sync(hl, 1n+Hs.hist_live_gen(hl), Ep.endpoint(host, port))
  # Connecting/Reconnecting via session_set_net: connection transitions drop
  # Confirm/Armed so dial→online cannot F8 without a new warning frame.
  session_set_net(Session{cl2, False{}, Nil{}, draft, JoinPlan.sent(next), chan, Offline{}, hist, size, seed, comp, Sp.normalize(cl2, split), Ty.empty(), port, [M.reset(media)], next, edits, [iso2], [hl2], [C.Retained{dial_cards(same, cards), dial_full(same, full, M.reset(media), cl2)}], [CapNotify.reg0()], theme, labelsbox, Nil{}}, next_net)

def session_rebox(+st: Session) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, [unbox_media(media)], plan, edits, [unbox_iso(iso)], [unbox_hist_live(hlbox)], [C.Retained{unbox_cards(cf), unbox_full(cf)}], regbox, theme, labelsbox, pends}

def session_put_joined(+st: Session, joined: Bool) -> Session:
  match st:
    case Session{cl, drop, rem, draft, _, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_put_typing(+st: Session, +typing: Ty.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, _, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_put_finish(+st: Session, +cl: Cl.Client, +draft: String, +hist: Hist, +seed: U32, +comp: Comp, split: Sp.State) -> Session:
  match st:
    case Session{_, drop, rem, _, joined, chan, net, _, size, _, _, _, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_mark_sent(+st: Session) -> Session:
  session_put_joined(session_rebox(st), JoinPlan.sent(session_plan(st)))

# Non-dial commands keep the session and mark the join plan sent. Dial still
# goes through session_after.dial, whose arity workspace.bend matches.
# st is matched in its own def: Bend refuses a match on an earlier binder
# after a match on a later one.
def session_after.from(+st: Session, +host: String, +dial_port: U32) -> Session:
  match st:
    case Session{+cl, _, _, +draft, _, +chan, net, +hist, size, seed, +comp, split, _, port, +media, +plan, +edits, +iso, +hlbox, +cf, _, +theme, labelsbox, _}:
      session_after.dial(cl, draft, chan, hist, size, seed, comp, split, host, dial_port, port, net, unbox_media(media), plan, edits, unbox_iso(iso), unbox_hist_live(hlbox), unbox_cards(cf), unbox_full(cf), theme, labelsbox)

def session_after.on(+st: Session, cmd: NetCmd) -> Session:
  match cmd:
    case Dial{+host, dial_port, _, _}: session_after.from(st, host, dial_port)
    case _: session_mark_sent(st)

def session_after(+st: Session, cmd: NetCmd) -> Session:
  session_after.on(st, cmd)

def session_on_cmd(+st: Session, +cmd: NetCmd) -> Session:
  session_after(st, cmd)

def apply_click(+cl: Cl.Client, c: Maybe<&2, Nat>) -> Cl.Client:
  match c:
    case None{}:
      cl
    case Some{i}:
      Cl.set_active_clamp(cl, i)

def snap_if(enter: Bool, +cl: Cl.Client) -> Cl.Client:
  match enter:
    case True{}:
      Cl.snap_active(cl)
    case False{}:
      cl

def session_seed(+st: Session) -> U32:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, seed, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      seed

def session_draft(+st: Session) -> String:
  match st:
    case Session{_, _, _, draft, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      draft

def session_set_draft(st: Session, +draft: String) -> Session:
  match st:
    case Session{cl, drop, rem, _, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, +theme, +labelsbox, +pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_hist(+st: Session) -> Hist:
  match st:
    case Session{_, _, _, _, _, _, _, +hist, _, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      hist

def session_comp(+st: Session) -> Comp:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, +comp, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      comp

def panel_open(comp: Comp, +draft: String) -> Bool:
  Sk.panel_open(view_of(comp), draft)

def panel_esc.on(esc: Bool, +st: Session) -> Bool:
  match esc:
    case False{}: False{}
    case True{}: panel_open(session_comp(st), session_draft(st))

def panel_esc(+st: Session, +key: U32) -> Bool:
  panel_esc.on(U32.is_eq(key, KEY_ESCAPE()), st)

def comp_right(right: Bool, +comp: U32) -> U32:
  match right:
    case True{}: 2
    case False{}: comp

def key_pol_right(pol: KeyPol, right: Bool) -> KeyPol:
  match pol:
    case KeyPol{tab, up, dn, hist, quit, comp, focus}:
      KeyPol{tab, up, dn, hist, quit, comp_right(right, comp), focus}

def key_pol_esc.go(pol: KeyPol) -> KeyPol:
  match pol:
    case KeyPol{tab, up, dn, hist, _, _, focus}:
      KeyPol{tab, up, dn, hist, 0, 3, focus}

def key_pol_esc(pol: KeyPol, esc: Bool) -> KeyPol:
  match esc:
    case False{}: pol
    case True{}: key_pol_esc.go(pol)

def key_pol_for(+st: Session, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +rows: U32) -> KeyPol:
  key_pol_esc(
    key_pol_right(key_pol_raw(key, mods, codepoint, wheel, Sp.page_height(rows, session_split(st))), Bool.and(U32.is_eq(key, KEY_RIGHT()), U32.is_zero(mods))),
    panel_esc(st, key))

def comp_upload_mark(comp: Comp, presented: Bool) -> Comp:
  match comp:
    case CompUpload{+state, completion, _}:
      CompUpload{state, completion, presented && upload_confirmation_eq(state, state)}
    case _: comp

def session_upload_mark(st: Session, presented: Bool) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp_upload_mark(comp, presented), split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def upload_presentation_reset_ok() -> Bool:
  +request: Up.Request = Up.Request{Up.Scope{"s", 6667, "#c"}, "/tmp/a"}
  +pending: Up.State = Up.Confirm{request, Nil{}}
  +painted: Comp = CompUpload{pending, None{}, True{}}
  Bool.not(comp_upload_presented(comp_set_upload(pending, CompNone{})))
    && comp_upload_presented(comp_set_upload(pending, painted))
    && Bool.not(comp_upload_presented(comp_set_upload(Up.Busy{request, Nil{}, True{}}, painted)))
    && Bool.not(comp_upload_presented(comp_set_upload(pending, CompUpload{Up.Busy{request, Nil{}, True{}}, None{}, False{}})))

def session_upload_draft(st: Session, draft: String, seed: U32) -> Session:
  match st:
    case Session{cl, drop, rem, _, joined, chan, net, hist, size, _, comp, split, typing, port, media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_reset_completion(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp_reset(comp), split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def upload_basename(parts: List<&2, String>, previous: String) -> String:
  match parts:
    case Nil{}: previous
    case Con{part, rest}: upload_basename(rest, part)

def upload_hint(request: Up.Request, remaining: List<&2, String>) -> String:
  match request:
    case Up.Request{Up.Scope{_, _, target}, path}:
      "F8: upload publicly to 0x0.st; Esc: cancel | " ++ target ++ " | "
        ++ String.take(upload_basename(String.split(path, Chr{47}), "file"), 128n)
        ++ " (files=" ++ Nat.show(Nat.add(1n, List.length(&2, String, remaining))) ++ ")"

def session_upload_hint.state(state: Up.State) -> String:
  match state:
    case Up.Confirm{request, remaining}: upload_hint(request, remaining)
    case Up.Armed{request, remaining}: upload_hint(request, remaining)
    case _: ""

def session_upload_hint(+st: Session) -> String:
  session_upload_hint.state(session_upload(st))

# Call after a frame and its keys are processed. A newly staged or completed
# request must first survive a later warning frame; this frame cannot arm it.
def session_upload_present(before: Session, +after: Session) -> Session:
  session_upload_mark(after, upload_confirmation_eq(session_upload(before), session_upload(after)))

def session_upload_key.confirm(confirm: Bool, +st: Session) -> Session & Bool:
  match confirm:
    case False{}: (st, False{})
    case True{}:
      (session_set_upload(st, Up.confirm(session_upload(st), session_upload_scope(st), session_upload_online(st))), True{})

def session_upload_key.cancel(cancel: Bool, confirm: Bool, +st: Session) -> Session & Bool:
  match cancel:
    case False{}: session_upload_key.confirm(confirm, st)
    case True{}:
      (session_set_upload(st, Up.cancel(session_upload(st))), True{})

def session_upload_key(+st: Session, +key: U32, mods: U32) -> Session & Bool:
  session_upload_key.cancel(U32.is_eq(key, KEY_ESCAPE()) && Up.active(session_upload(st)),
    U32.is_eq(key, KEY_F8()) && U32.is_zero(mods) && Up.pending(session_upload(st)) && session_upload_presented(st), session_upload_maintain(st))

# Shared frame-key consent owner for Net.frame_result and WsNet ws_upload.*.
def session_frame_key_admit(+st: Session, +key: U32, mods: U32) -> Session & Bool:
  session_upload_key(st, key, mods)

def session_frame_key_seal(before: Session, +after: Session) -> Session:
  session_upload_present(before, after)

def session_upload_take.got(pair: Up.State & Maybe<&2, Up.Request>, st: Session) -> Session & Maybe<&2, Up.Request>:
  match pair:
    case (state, request): (session_set_upload(st, state), request)

def session_upload_take(+st: Session) -> Session & Maybe<&2, Up.Request>:
  +next = session_upload_maintain(st)
  session_upload_take.got(Up.take_job(session_upload(next)), next)

def session_upload_complete.got(pair: Up.State & Maybe<&2, String>, +st: Session) -> Session & Maybe<&2, String>:
  match pair:
    case (+state, result):
      (session_set_upload(st, state), result)

def session_upload_complete(+st: Session, request: Up.Request, result: String) -> Session & Maybe<&2, String>:
  session_upload_complete.got(Up.finish(session_upload(st), request, session_upload_scope(st), session_upload_online(st), result), st)

def split_apply.open.got(
  triple: Cl.Client & Sp.State & Bool,
  previous: Sp.State,
  axis: Sp.Axis,
  +target: String
) -> Cl.Client & String & NetCmd & Sp.State:
  match triple:
    case (cl2, split2, ok):
      match ok:
        case True{}:
          (Sub.echo_info(cl2, "split " ++ Sp.show_axis(axis)), "", Cont{Nil{}}, split2)
        case False{}:
          (Sub.echo_err(cl2, "split target must name another open buffer: " ++ target), "", Cont{Nil{}}, previous)

def split_apply.open(+cl: Cl.Client, previous: Sp.State, +axis: Sp.Axis, +target: String) -> Cl.Client & String & NetCmd & Sp.State:
  split_apply.open.got(Sp.activate(cl, axis, target), previous, axis, target)

def split_apply.focus.got(pair: Cl.Client & Sp.State) -> Cl.Client & String & NetCmd & Sp.State:
  match pair:
    case (cl2, split2):
      (Sub.echo_info(cl2, "split focus changed"), "", Cont{Nil{}}, split2)

def split_apply.focus.on(on: Bool, +cl: Cl.Client, split: Sp.State) -> Cl.Client & String & NetCmd & Sp.State:
  match on:
    case False{}:
      (Sub.echo_err(cl, "split view is not active"), "", Cont{Nil{}}, split)
    case True{}:
      split_apply.focus.got(Sp.toggle(cl, split))

def split_apply.focus(+cl: Cl.Client, +split: Sp.State) -> Cl.Client & String & NetCmd & Sp.State:
  split_apply.focus.on(Sp.is_on(split), cl, split)

def split_apply(+cl: Cl.Client, split: Sp.State, cmd: Sp.Command) -> Cl.Client & String & NetCmd & Sp.State:
  match cmd:
    case Sp.NotSplit{}:
      (cl, "", Cont{Nil{}}, split)
    case Sp.BadSplit{}:
      (Sub.echo_err(cl, "usage: /split [horizontal|vertical] [buffer]"), "", Cont{Nil{}}, split)
    case Sp.SplitOpen{axis, +target}:
      split_apply.open(cl, split, axis, target)
    case Sp.SplitClose{}:
      (Sub.echo_info(cl, "split view closed"), "", Cont{Nil{}}, Sp.Off{})
    case Sp.SplitFocus{}:
      split_apply.focus(cl, split)

def submit_follow.got(
  triple: Cl.Client & String & NetCmd,
  split: Sp.State
) -> Cl.Client & String & NetCmd & Sp.State:
  match triple:
    case (+cl2, draft2, cmd):
      (cl2, draft2, cmd, Sp.follow_active(cl2, split))

# Pane verbs are catalog constructors. Argument policy stays in Sp.parse_split_arg
# (protocol-style remainder); the verb itself is not scanned again.
def split_command(cmd: Sub.Slash, +rest: String) -> Sp.Command:
  match cmd:
    case Sub.Split{}: Sp.parse_split_arg(Irc.take_until_space(Irc.drop_spaces(rest)))
    case Sub.VSplit{}: Sp.SplitOpen{Sp.SideBySide{}, Irc.drop_spaces(rest)}
    case Sub.SplitOff{}: Sp.SplitClose{}
    case Sub.Unsplit{}: Sp.SplitClose{}
    case Sub.Focus{}: Sp.SplitFocus{}
    case _: Sp.NotSplit{}

def split_of_input(input: Sub.Input) -> Sp.Command:
  match input:
    case Sub.CommandInput{cmd, _, +rest}: split_command(cmd, rest)
    case _: Sp.NotSplit{}

def submit_or_split.cmd(
  ctx: Sub.SubmitCtx,
  cmd: Sp.Command,
  +cl: Cl.Client,
  split: Sp.State,
  net: NetState,
  +port: U32,
  input: Sub.Input,
  +negotiated: Bool
) -> Cl.Client & String & NetCmd & Sp.State:
  match cmd:
    case Sp.NotSplit{}:
      submit_follow.got(submit_input_ctx(ctx, input, cl, net, port, negotiated), split)
    case _:
      split_apply(cl, split, cmd)

def submit_or_split.enter(
  enter: Bool,
  ctx: Sub.SubmitCtx,
  +cl: Cl.Client,
  split: Sp.State,
  net: NetState,
  +port: U32,
  +typed: String,
  +negotiated: Bool,
  +input: Sub.Input
) -> Cl.Client & String & NetCmd & Sp.State:
  match enter:
    case False{}:
      (cl, typed, Cont{Nil{}}, split)
    case True{}:
      submit_or_split.cmd(ctx, split_of_input(input), cl, split, net, port, input, negotiated)

def submit_or_split(
  ctx: Sub.SubmitCtx,
  +cl: Cl.Client,
  split: Sp.State,
  net: NetState,
  +port: U32,
  +typed: String,
  enter: Bool,
  +negotiated: Bool,
  input: Sub.Input
) -> Cl.Client & String & NetCmd & Sp.State:
  submit_or_split.enter(enter, ctx, cl, split, net, port, typed, negotiated, input)

def session_typing(+st: Session) -> Ty.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, +typing, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      typing

def session_typers(+st: Session) -> List<&2, String>:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, +typing, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      Ty.names(typing, Cl.active_buf_name(cl))

def session_expire_typing.got(+st: Session, pair: Ty.State & Bool) -> Session & Bool:
  match pair:
    case (typing, changed):
      (session_put_typing(session_put_joined(session_rebox(st), JoinPlan.sent(session_plan(st))), typing), changed)

def session_expire_typing.merge(+kept: List<&2, Cl.PendSend>, +dropped: List<&2, Cl.PendSend>, pair: Session & Bool, +draft: String) -> Session & Bool:
  match pair:
    case (+st2, tchanged):
      (session_set_pends(session_set_draft(st2, pend_draft(draft, pend_restore_text(dropped))), kept), tchanged || pend_reaped.any(dropped))

def session_expire_typing.reaped(reaped: List<&2, Cl.PendSend> & List<&2, Cl.PendSend>, pair: Session & Bool, +draft: String) -> Session & Bool:
  match reaped:
    case (+kept, +dropped):
      session_expire_typing.merge(kept, dropped, pair, draft)

def session_expire_typing.inner(+st: Session, +now_ms: U32) -> Session & Bool:
  session_expire_typing.got(st, Ty.expire_changed(session_typing(st), now_ms))

def session_expire_typing(+st: Session, +now_ms: U32) -> Session & Bool:
  session_expire_typing.reaped(pend_reap(pend_age_all(session_pends(st))), session_expire_typing.inner(st, now_ms), session_draft(st))

# G6 live binding: outbound typing ticks. TypingTick calls this beside
# session_expire_typing, and composer frames call it after applying keys. The
# tick steps the stored Reg with live online state, the active target, and the
# composer text, and yields at most one TAGMSG wire for the bounded actor path.
# Untagged, offline, and mistargeted ticks are quiet by construction. The
# same/different-target decision folds under the negotiated Session
# CASEMAPPING (session_cm), so ascii-distinct aliases never merge spans.
def session_reg(+st: Session) -> CapNotify.Reg:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +regbox, _, labelsbox, +pends}: unbox_reg(regbox)

# echo-message send gate: the live submit chain suppresses local echoes
# while True; the server's wire echo is the single rendered confirmation.
def session_echo_ok(+st: Session) -> Bool:
  CapNotify.reg_echo_ok(session_reg(st))

def session_set_reg(st: Session, +reg: CapNotify.Reg) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, _, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, [reg], theme, labelsbox, pends}

# Labeled-response outbound counter: mint "birc-<n>" and increment. Pure
# Client-only send paths stay unlabeled; Session-owned sends attach via
# session_label_cmd, which mints once per PRIVMSG/NOTICE wire.
def session_labels(+st: Session) -> Nat:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +labelsbox, +pends}: unbox_labels(labelsbox)

def session_set_labels(st: Session, +n: Nat) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, +theme, _, +pends}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, [n], pends}

def session_next_label(+st: Session) -> Session & String:
  +n = session_labels(st)
  (session_set_labels(st, Nat.add(n, 1n)), "birc-" ++ Nat.show(n))

# Labeled-response live sends: Session-owned PRIVMSG/NOTICE wires carry a
# minted label while negotiated. Each candidate wire mints exactly one label
# (counter consumed per send, even when the gate downgrades); emission reuses
# Sub.message_wire_labeled, so the label rides only when negotiated AND
# well-formed AND inside the wire cap. Downgrades keep the original bytes and
# non-message wires pass through untouched without minting, so unnegotiated
# sessions emit byte-identical wires and never a malformed or overlong line.
def session_labeled_ok.reg(+reg: CapNotify.Reg) -> Bool:
  match reg:
    case CapNotify.Reg{+caps, _}: CapNotify.labeled_ok(caps)

def session_labeled_ok(+st: Session) -> Bool:
  session_labeled_ok.reg(session_reg(st))

def session_label_one.emit(+st: Session, +line: String, +target: String, +body: String, +notice: Bool, +label: String, +labeled: Bool, should_tag: Bool) -> Session & String:
  match should_tag:
    case True{}: (st, Sub.message_wire_labeled(target, body, notice, label, labeled))
    case False{}: (st, line)

def session_label_one.minted(pair: Session & String, +line: String, +target: String, +body: String, +notice: Bool, +labeled: Bool) -> Session & String:
  match pair:
    case (+st2, +label):
      tagged = Bool.pick(String, notice, Irc.format_notice_labeled(target, body, label), Irc.format_privmsg_labeled(target, body, label))
      session_label_one.emit(st2, line, target, body, notice, label, labeled, labeled && Irc.label_ok(label) && Irc.line_ok(tagged))

def session_label_one.arity(+st: Session, +line: String, +target: String, +body: String, +notice: Bool, +labeled: Bool, arity_ok: Bool) -> Session & String:
  match arity_ok:
    case False{}: (st, line)
    case True{}: session_label_one.minted(session_next_label(st), line, target, body, notice, labeled)

def session_label_one.verb(+st: Session, +line: String, +m: Irc.Message, +labeled: Bool, +notice: Bool, is_msg: Bool) -> Session & String:
  match is_msg:
    case False{}: (st, line)
    case True{}:
      session_label_one.arity(st, line, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), notice, labeled, Nat.is_eq(List.length(&2, String, Irc.msg_params(m)), 2n))

def session_label_one.parsed(+st: Session, +line: String, parsed: Maybe<&2, Irc.Message>, +labeled: Bool) -> Session & String:
  match parsed:
    case None{}: (st, line)
    case Some{+m}:
      +verb = Irc.msg_command(m)
      +notice = Irc.ieq(verb, "NOTICE")
      session_label_one.verb(st, line, m, labeled, notice, Irc.ieq(verb, "PRIVMSG") || notice)

def session_label_one.tagged(+st: Session, +line: String, tagged: Bool) -> Session & String:
  match tagged:
    case True{}: (st, line)
    case False{}: session_label_one.parsed(st, line, Irc.parse(line), session_labeled_ok(st))

def session_label_one(+st: Session, +line: String) -> Session & String:
  session_label_one.tagged(st, line, String.starts_with(Irc.drop_spaces(line), "@"))

def session_label_step.one(pair: Session & String, +rev: List<&2, String>) -> Session & List<&2, String>:
  match pair:
    case (+st2, +h2): (st2, h2 <> rev)

def session_label_step(pair: Session & List<&2, String>, line: String) -> Session & List<&2, String>:
  match pair:
    case (+st, +rev): session_label_step.one(session_label_one(st, line), rev)

def session_label_outs.rev(pair: Session & List<&2, String>) -> Session & List<&2, String>:
  match pair:
    case (+st2, +rev): (st2, List.reverse(&2, String, rev))

def session_label_outs(+st: Session, +outs: List<&2, String>) -> Session & List<&2, String>:
  session_label_outs.rev(List.foldl(~&2, ~String, ~(Session & List<&2, String>), ~session_label_step, outs, (st, Nil{})))

def session_label_cmd.cont(pair: Session & List<&2, String>) -> Session & NetCmd:
  match pair:
    case (+st2, +outs2): (st2, Cont{outs2})

def session_label_cmd(+st: Session, +cmd: NetCmd) -> Session & NetCmd:
  match cmd:
    case Cont{+outs}: session_label_cmd.cont(session_label_outs(st, outs))
    case _: (st, cmd)

# Outbound record + status compose (need session accessors above).

# Full Client.now so pending overlays share day bars with stamped history.
def pend_now(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, _, _, +now, _, _, _, _}: now

def pend_record_cont(+st: Session, +outs: List<&2, String>, echo_ok: Bool) -> Session:
  match echo_ok:
    case False{}: st
    case True{}: session_set_pends(st, pend_record_outs(session_pends(st), session_cl(st), Isupport.as_iso(session_iso(st)), outs, pend_now(session_cl(st)), Cl.nick_of(session_cl(st))))

def pend_record_cmd(+st: Session, +cmd: NetCmd) -> Session:
  match cmd:
    case Cont{+outs}: pend_record_cont(st, outs, CapNotify.reg_echo_ok(session_reg(st)))
    case _: st

def pend_sending.some(+n: Nat, none: Bool) -> String:
  match none:
    case True{}: ""
    case False{}: " · " ++ Nat.show(n) ++ " sending"

def pend_sending(+n: Nat) -> String:
  pend_sending.some(n, Nat.is_eq(n, 0n))

def net_label_lag_pend(+net: NetState, +lag: U32, +pendn: Nat) -> String:
  net_label_lag(net, lag) ++ pend_sending(pendn)

def session_label_trip.labeled(pair: Session & NetCmd, +halt: Bool) -> Session & NetCmd & Bool:
  match pair:
    case (+st2, +cmd2): (pend_record_cmd(st2, cmd2), cmd2, halt)

def session_label_trip(trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match trip:
    case (+st, cmd, halt): session_label_trip.labeled(session_label_cmd(st, cmd), halt)

def session_typing_online.net(net: NetState) -> Bool:
  match net:
    case Online{}: True{}
    case _: False{}

def session_typing_online(+st: Session) -> Bool:
  session_typing_online.net(session_net(st))

def session_tick_typing.ticked(pair: CapNotify.Reg & List<&2, String>, st: Session) -> Session & List<&2, String>:
  match pair:
    case (+reg, +outs): (session_set_reg(st, reg), outs)

def session_tick_typing(+st: Session, +now_ms: U32) -> Session & List<&2, String>:
  session_tick_typing.ticked(CapNotify.live_tick_cm(session_cm(st), session_reg(st), now_ms, session_typing_online(st), Cl.active_buf_name(session_cl(st)), session_draft(st)), st)

# Frame-path merge primitive: the typing wire piggybacks on the frame's Cont
# so the actor budgets it with the frame's other output. Only Cont reaches
# here from frames: frame_tick_typing below skips stepping entirely on halt
# and non-Cont commands (dial, drop, open, begin, pump, pong, search), so a
# live span is never committed and then dropped — the next TypingTick
# delivers the done.
def merge_typing_outs(cmd: NetCmd, +touts: List<&2, String>) -> NetCmd:
  match cmd:
    case Cont{+outs}: Cont{List.append(&2, String, outs, touts)}
    case Dial{+host, port, gen, +nick}: Dial{host, port, gen, nick}
    case Drop{}: Drop{}
    case Pump{gen}: Pump{gen}
    case Pong{+gen, +pongs, +req}: Pong{gen, pongs, req}
    case OpenUrl{+url}: OpenUrl{url}
    case Begin{gen}: Begin{gen}
    case Search{+text, +target, +cursor, +orig, +endpoint, +history_on, +ticket, +gen, +wgen}: Search{text, target, cursor, orig, endpoint, history_on, ticket, gen, wgen}

# Frame-path typing tick: the single owner of the frame tick+merge decision
# (net.bend frame_result calls this; TypingTick keeps session_tick_typing
# plus the bounded emit path). Halt frames and non-Cont commands return the
# session and command untouched — no stepping, no commit, no wire — so a
# live span survives for the next TypingTick. Cont frames step the stored
# Reg and append at most one TAGMSG wire to the frame's own output.
def frame_tick_typing.skip(cmd: NetCmd, +st: Session) -> Session & NetCmd:
  (st, cmd)

def frame_tick_typing.cont(ticked: Session & List<&2, String>, +outs: List<&2, String>) -> Session & NetCmd:
  match ticked:
    case (+st3, +touts): (st3, merge_typing_outs(Cont{outs}, touts))

def frame_tick_typing.cmd(cmd: NetCmd, +st: Session, +now_ms: U32) -> Session & NetCmd:
  match cmd:
    case Cont{+outs}: frame_tick_typing.cont(session_tick_typing(st, now_ms), outs)
    case Dial{+host, port, gen, +nick}: frame_tick_typing.skip(Dial{host, port, gen, nick}, st)
    case Drop{}: frame_tick_typing.skip(Drop{}, st)
    case Pump{gen}: frame_tick_typing.skip(Pump{gen}, st)
    case Pong{+gen, +pongs, +req}: frame_tick_typing.skip(Pong{gen, pongs, req}, st)
    case OpenUrl{+url}: frame_tick_typing.skip(OpenUrl{url}, st)
    case Begin{gen}: frame_tick_typing.skip(Begin{gen}, st)
    case Search{+text, +target, +cursor, +orig, +endpoint, +history_on, +ticket, +gen, +wgen}: frame_tick_typing.skip(Search{text, target, cursor, orig, endpoint, history_on, ticket, gen, wgen}, st)

def frame_tick_typing(cmd: NetCmd, +st: Session, +now_ms: U32, halt: Bool) -> Session & NetCmd:
  match halt:
    case True{}: frame_tick_typing.skip(cmd, st)
    case False{}: frame_tick_typing.cmd(cmd, st, now_ms)

# Key-frame deltas on top of Session. The rest of the record stays boxed
# inside Session so a key step does not flatten media, iso, hist_live, cards,
# reg, labels, and pends into the call.
type KeyCtx is Data:
  KeyCtx{keys: Keys, hist: Hist, cl: Cl.Client, draft: String, cmd: NetCmd, split: Sp.State}

def finish_hist(+st: Session, +cl: Cl.Client, +cmd: NetCmd, halt: Bool, +seed: U32, +comp: Comp, split: Sp.State, pair: Hist & String) -> Session & NetCmd & Bool:
  match pair:
    case (h2, draft3):
      (session_after(session_put_finish(st, cl, draft3, h2, seed, comp, split), cmd), cmd, halt)

def finish_comp(+st: Session, +cl: Cl.Client, +cmd: NetCmd, +hist: Hist, split: Sp.State, trip: Comp & String & U32) -> Session & NetCmd & Bool:
  match trip:
    case (comp2, draft3, seed):
      (session_after(session_put_finish(st, cl, draft3, hist, seed, comp2, split), cmd), cmd, False{})

def focus_after(on: Bool, +cl: Cl.Client, split: Sp.State) -> Cl.Client & Sp.State:
  match on:
    case True{}: Sp.toggle(cl, split)
    case False{}: (cl, split)

def nav_after(
  +cl: Cl.Client,
  split: Sp.State,
  size: Size,
  enter: Bool,
  tab: Cl.TabDir,
  click: Maybe<&2, Nat>,
  +up: Nat,
  +dn: Nat,
  +focus: U32,
  +media: M.State,
  +iso: Isupport.State,
  +cards: C.State,
  +pends: List<&2, Cl.PendSend>
) -> Cl.Client & Sp.State:
  match size:
    case Size{rows, cols}:
      +cl2 = apply_click(Cl.cycle_tab(cl, tab), click)
      +split2 = Sp.follow_active(cl2, split)
      +cl3 = snap_if(enter, View.scroll_active_media_cards_iso(Isupport.as_iso(iso), cl2, rows, cols, split2, up, dn, media, C.paint_entries(cards), pends))
      focus_after(U32.is_eq(focus, 1), cl3, split2)

def panel_keep(comp: Comp, +typed: String, +draft: String) -> Comp:
  comp_of(Sk.panel_keep(view_of(comp), typed, draft))

def panel_dismiss(comp: Comp) -> Comp:
  comp_of(Sk.panel_dismiss(view_of(comp)))

def pick_idx(comp: Comp) -> Nat:
  Sk.pick_idx(view_of(comp))

def key_plan.placed(+lines: List<&2, String>, +pos: Nat, +draft: String) -> Hist & String:
  (Hist{lines, pos}, draft)

def key_plan.use_hist(+st: Session, +cl: Cl.Client, +cmd: NetCmd, +hist: Hist, halt: Bool, +seed: U32, +comp: Comp, split: Sp.State, +pos: Nat, +draft: String) -> Session & NetCmd & Bool:
  match hist:
    case Hist{+lines, _}:
      finish_hist(st, cl, cmd, halt, seed, comp, split, key_plan.placed(lines, pos, draft))

# Wire/history keep raw shortcodes. Explicit Tab/Right accept commits glyphs
# via compose_accept; ordinary typed frames must not auto-rewrite the draft.
# Nick CompActive keeps Tab cycling (KeyCycle). A slash/emoji picker or unique
# ghost finishes the selected candidate instead.
def key_plan.use(+st: Session, +cl: Cl.Client, +cmd: NetCmd, +hist: Hist, +comp: Comp, split: Sp.State, +typed: String, plan: Sk.KeyPlan) -> Session & NetCmd & Bool:
  match plan:
    case Sk.KeyCycle{}:
      finish_comp(st, cl, cmd, hist, split, comp_step_iso(session_iso(st), cl, comp, typed))
    case Sk.KeyApply{halt, +seed, view, +pos, +draft}:
      key_plan.use_hist(st, cl, cmd, hist, halt, seed, comp_of(view), split, pos, draft)

def finish_keys.comp.at(+lines: List<&2, String>, +pos: Nat, +st: Session, +code: U32, +cl: Cl.Client, +cmd: NetCmd, +comp: Comp, split: Sp.State, +typed: String, +draft: String, +prev: String, hdir: HistDir, enter: Bool) -> Session & NetCmd & Bool:
  key_plan.use(st, cl, cmd, Hist{lines, pos}, comp, split, typed, Sk.finish_keys.comp(code, lines, pos, view_of(comp), typed, draft, prev, sk_dir(hdir), enter))

def finish_keys.comp(+st: Session, +code: U32, +cl: Cl.Client, +cmd: NetCmd, +hist: Hist, +comp: Comp, split: Sp.State, +typed: String, +draft: String, +prev: String, +hdir: HistDir, +enter: Bool) -> Session & NetCmd & Bool:
  match hist:
    case Hist{+lines, +pos}:
      finish_keys.comp.at(lines, pos, st, code, cl, cmd, comp, split, typed, draft, prev, hdir, enter)

def finish_keys.nav(+st: Session, pair: Cl.Client & Sp.State, +code: U32, +cmd: NetCmd, +hist: Hist, +comp: Comp, +typed: String, +draft: String, +prev: String, +hdir: HistDir, +enter: Bool) -> Session & NetCmd & Bool:
  match pair:
    case (cl3, split3):
      finish_keys.comp(st, code, cl3, cmd, hist, comp, split3, typed, draft, prev, hdir, enter)

def finish_keys.open(+st: Session) -> Size & M.State & Isupport.State & C.State & List<&2, Cl.PendSend> & Comp:
  match st:
    case Session{_, _, _, _, _, _, _, _, size, _, +comp, _, _, _, +media, _, _, +iso, _, +cf, _, _, labelsbox, +pends}:
      (size, unbox_media(media), unbox_iso(iso), unbox_cards(cf), pends, comp)

def finish_keys.keyed(size: Size, +media: M.State, +iso: Isupport.State, +cards: C.State, +pends: List<&2, Cl.PendSend>, +comp: Comp, +st: Session, keys: Keys, +hist: Hist, +cl2: Cl.Client, +draft2: String, +cmd: NetCmd, split2: Sp.State) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, +enter, +tab, +click, +up, +dn, +hdir, is_comp, focus}:
      finish_keys.nav(st, nav_after(cl2, split2, size, enter, tab, click, up, dn, focus, media, iso, cards, pends), is_comp, cmd, hist, comp, typed, draft2, session_draft(st), hdir, enter)

def finish_keys.opened(opened: Size & M.State & Isupport.State & C.State & List<&2, Cl.PendSend> & Comp, +st: Session, keys: Keys, +hist: Hist, +cl2: Cl.Client, +draft2: String, +cmd: NetCmd, split2: Sp.State) -> Session & NetCmd & Bool:
  match opened:
    case (size, media, iso, cards, pends, comp):
      finish_keys.keyed(size, media, iso, cards, pends, comp, st, keys, hist, cl2, draft2, cmd, split2)

def finish_keys.apply(+st: Session, keys: Keys, +hist: Hist, +cl2: Cl.Client, +draft2: String, +cmd: NetCmd, split2: Sp.State) -> Session & NetCmd & Bool:
  finish_keys.opened(finish_keys.open(st), st, keys, hist, cl2, draft2, cmd, split2)

def finish_keys(+st: Session, +ctx: KeyCtx) -> Session & NetCmd & Bool:
  match ctx:
    case KeyCtx{keys, hist, cl, draft, cmd, split}:
      finish_keys.apply(st, keys, hist, cl, draft, cmd, split)

def finish_keys.quad(+st: Session, keys: Keys, +hist: Hist, quad: Cl.Client & String & NetCmd & Sp.State) -> Session & NetCmd & Bool:
  match quad:
    case (cl, draft, cmd, split):
      finish_keys(st, KeyCtx{keys, hist, cl, draft, cmd, split})

def session_submit_target.msg_pair(pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (+who, _): Some{who}

def session_submit_target.msg(+rest: String) -> Maybe<&2, String>:
  session_submit_target.msg_pair(Sub.take_word(rest))

def session_submit_target.query(+rest: String) -> Maybe<&2, String>:
  session_submit_target.msg_pair(Sub.take_word(Irc.drop_spaces(rest)))

def session_submit_target.cmd(cmd: Sub.Slash, +rest: String) -> Maybe<&2, String>:
  match cmd:
    case Sub.Msg{}: session_submit_target.msg(rest)
    case Sub.QueryCmd{}: session_submit_target.query(rest)
    case Sub.NoticeCmd{}: session_submit_target.msg(rest)
    case _: None{}

def session_submit_target.parsed(input: Sub.Input) -> Maybe<&2, String>:
  match input:
    case Sub.CommandInput{cmd, _, +rest}: session_submit_target.cmd(cmd, rest)
    case _: None{}

def session_submit_target(+typed: String) -> Maybe<&2, String>:
  session_submit_target.parsed(Sub.parse_input(typed))

def session_submit_stored.got(+st: Session, +target: String, got: Maybe<&2, Cl.Buffer>) -> Bool:
  match got:
    case None{}: False{}
    case Some{Cl.Buffer{+name, _, _, _, _, _, _, _}}: Bool.not(session_cm_eq(st, target, name))

def session_submit_stored.bufs(+st: Session, +target: String, +bufs: List<&2, Cl.Buffer>, +i: Nat) -> Bool:
  session_submit_stored.got(st, target, Cl.nth_buf(bufs, i))

def session_submit_stored.cl(+st: Session, +target: String, +cl: Cl.Client, +i: Nat) -> Bool:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _, _}:
      session_submit_stored.bufs(st, target, bufs, i)

def session_submit_stored(+st: Session, +target: String, found: Maybe<&2, Nat>) -> Bool:
  match found:
    case None{}: False{}
    case Some{+i}:
      session_submit_stored.cl(st, target, session_cl(st), i)

def session_submit_needs_dynamic_for_target(+st: Session, +target: String) -> Bool:
  +neg = session_chan_target(st, target)
  +fix = Cl.message_key_with(session_cl(st), Isupport.as_iso(session_iso(st)), target)
  Bool.not(String.eq(neg, fix)) || session_submit_stored(st, target, Cl.buf_find_cm(session_cl(st), session_cm(st), target))

def session_submit_needs_dynamic.some(+st: Session, got: Maybe<&2, String>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+t}: session_submit_needs_dynamic_for_target(st, t)

def session_submit_needs_dynamic(+st: Session, +typed: String) -> Bool:
  session_submit_needs_dynamic.some(st, session_submit_target(typed))

def session_submit_command_iso.cmd(cmd: Sub.Slash) -> Bool:
  match cmd:
    case Sub.Join{}: True{}
    case Sub.Part{}: True{}
    case Sub.CloseCmd{}: True{}
    case Sub.Msg{}: True{}
    case Sub.QueryCmd{}: True{}
    case Sub.MuteCmd{}: True{}
    case Sub.UnmuteCmd{}: True{}
    case Sub.WhoCmd{}: True{}
    case Sub.NamesCmd{}: True{}
    case Sub.TopicCmd{}: True{}
    case Sub.ModeCmd{}: True{}
    case Sub.KickCmd{}: True{}
    case Sub.InviteCmd{}: True{}
    case Sub.NoticeCmd{}: True{}
    case _: False{}

def step_keys.base.dyn.input(+st: Session, input: Sub.Input) -> Bool:
  match input:
    case Sub.CommandInput{+cmd, _, +rest}:
      session_submit_command_iso.cmd(cmd)
        || session_submit_needs_dynamic.some(st, session_submit_target.cmd(cmd, rest))
    case _: False{}

def step_keys.parsed(enter: Bool, +typed: String) -> Sub.Input:
  match enter:
    case False{}: Sub.EmptyInput{}
    case True{}: Sub.parse_input(typed)

def step_keys.base.ctx(dyn: Bool, +iso: Isupport.State, +echo_ok: Bool) -> Sub.SubmitCtx:
  match dyn:
    case True{}: Sub.submit_ctx_iso(iso, echo_ok)
    case False{}: Sub.submit_ctx_plain(echo_ok)

def step_keys.base.keep(enter: Bool, +iso: Isupport.State, +cl: Cl.Client, input: Sub.Input) -> Bool:
  match enter:
    case False{}: False{}
    case True{}: Bool.not(Sub.input_sensitive_iso.parsed(iso, cl, input))

def step_keys.base.dyn(enter: Bool, +st: Session, input: Sub.Input) -> Bool:
  match enter:
    case False{}: False{}
    case True{}: step_keys.base.dyn.input(st, input)

def step_keys.base.submit(+st: Session, +keys: Keys, +hist2: Hist, dyn: Bool, input: Sub.Input) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, enter, _, _, _, _, _, _, _}:
      +negotiated = session_negotiated(st)
      +echo_ok = session_echo_ok(st)
      finish_keys.quad(st, keys, hist2, submit_or_split(step_keys.base.ctx(dyn, session_iso(st), echo_ok), session_cl(st), session_split(st), session_net(st), session_port(st), typed, enter, negotiated, input))

def step_keys.base(+st: Session, +keys: Keys, +input: Sub.Input) -> Session & NetCmd & Bool:
  match st:
    case Session{+cl, drop, +rem, _, joined, +chan, net, +hist, size, _, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, _, _, _, labelsbox, +pends}:
      match keys:
        case Keys{+typed, enter, _, _, _, _, _, _, _}:
          +hist2 = hist_after_enter(hist, typed, step_keys.base.keep(enter, unbox_iso(iso), cl, input))
          step_keys.base.submit(st, keys, hist2, step_keys.base.dyn(enter, st, input), input)

def session_media(st: Session) -> M.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, media, +plan, +edits, _, _, _, _, _, labelsbox, +pends}: unbox_media(media)

def media_diagnostic(report: Bool, cl: Cl.Client) -> Cl.Client:
  match report:
    case False{}: cl
    case True{}: Cl.diagnostic(cl, Cl.System{}, M.unsupported_text())

def session_set_media(st: Session, +media: M.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, before, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{media_diagnostic(Bool.not(M.reported(unbox_media(before))) && M.reported(media), cl), drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, [media], plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def session_full(st: Session) -> C.Fullscreen:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +cf, _, _, labelsbox, +pends}: unbox_full(cf)

def session_set_full(st: Session, +full: C.Fullscreen) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, [C.Retained{unbox_cards(cf), full}], regbox, theme, labelsbox, pends}

def visible_media_net(net: NetState) -> Bool:
  match net:
    case Demo{}: False{}
    case Stopping{_}: False{}
    case _: True{}

# ---- C8 live: Session-retained cards (setters before shared observe) ----

def session_cards(st: Session) -> C.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +cf, _, _, labelsbox, +pends}: unbox_cards(cf)

def session_set_cards(st: Session, +cards: C.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, [C.Retained{cards, unbox_full(cf)}], regbox, theme, labelsbox, pends}

# Shared ScrollAt window for media+cards admission. Media observe (runs first
# on the live stage) also feeds cards when both are enabled so the same
# anchored rows are not rebuilt for that path.
def session_observe_visible_share_cards(do_cards: Bool, +st: Session, +kept: C.State, +anchored: List<&2, View.AnchoredRow>) -> Session:
  match do_cards:
    case False{}: st
    case True{}: session_set_cards(st, C.enqueue_candidates(C.visible_candidates_from_rows(anchored), kept))

def session_observe_visible_media.gated(+isc: Cl.Iso, open: Bool, +st: Session, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: C.State) -> Session:
  match open:
    case True{}: st
    case False{}:
      +current = M.maintain(media, cl)
      +kept = C.maintain(cards, cl)
      +anchored = View.visible_anchored_panes_media_cards_iso(isc, cl, rows, cols, split, current, C.paint_entries(kept))
      +st1 = session_set_media(st, M.enqueue_candidates(View.visible_media_candidates_from_rows(anchored, current), current))
      session_observe_visible_share_cards(C.enabled(kept), st1, kept, anchored)

def session_observe_visible_media.allowed(allowed: Bool, +st: Session) -> Session:
  match allowed:
    case False{}: st
    case True{}:
      match st:
        case Session{+cl, _, _, _, _, _, _, _, Size{rows, cols}, _, _, split, _, _, +media, _, _, +iso, _, +cf, _, _, labelsbox, +pends}:
          +full_kept = C.maintain_full(unbox_full(cf), unbox_media(media), cl)
          +st1 = session_set_full(st, full_kept)
          session_observe_visible_media.gated(Isupport.as_iso(unbox_iso(iso)), C.is_open(full_kept), st1, cl, rows, cols, split, unbox_media(media), unbox_cards(cf))

def session_observe_visible_media(+st: Session) -> Session:
  session_observe_visible_media.allowed(visible_media_net(session_net(st)) && M.enabled(session_media(st)), st)

def session_accept_media_result(+st: Session, +generation: Nat, +ticket: Nat, +url: String) -> Bool:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, Size{rows, cols}, _, _, split, _, _, +media, _, _, +iso, _, +cf, _, _, labelsbox, +pends}:
      M.accept(unbox_media(media), cl, generation, ticket, url)
        && M.visible_result_allowed(unbox_media(media), View.visible_media_candidates_cards_iso(Isupport.as_iso(unbox_iso(iso)), cl, rows, cols, split, unbox_media(media), C.paint_entries(C.maintain(unbox_cards(cf), cl))))

def media_job_net(net: NetState) -> Bool:
  match net:
    case Stopping{_}: False{}
    case _: True{}

def session_media_job_allowed.open(open: Bool, net: NetState) -> Bool:
  match open:
    case True{}: False{}
    case False{}: media_job_net(net)

def session_media_job_allowed(+st: Session) -> Bool:
  session_media_job_allowed.open(C.is_open(C.maintain_full(session_full(st), session_media(st), session_cl(st))), session_net(st))

def session_observe_media.after(+after: Nat, +st: Session) -> Session:
  session_set_media(st, M.maintain(session_media(st), session_cl(st)))

def session_observe_media(+st: Session, +after: Nat) -> Session:
  session_observe_media.after(after, st)

# ---- C8 live: Session-retained cards and fullscreen (one canonical path) ----
# Scheduling consumes bounded visible candidates over the exact painted rows;
# step paths only settle dead state (never schedule). The physical cards
# worker stays owned until its exact completion, even across disable/reset.

def session_observe_visible_cards.gated(+isc: Cl.Iso, open: Bool, +st: Session, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: C.State) -> Session:
  match open:
    case True{}: st
    case False{}:
      +kept = C.maintain(cards, cl)
      +anchored = View.visible_anchored_panes_media_cards_iso(isc, cl, rows, cols, split, media, C.paint_entries(kept))
      session_set_cards(st, C.enqueue_candidates(C.visible_candidates_from_rows(anchored), kept))

def session_observe_visible_cards.allowed(allowed: Bool, +st: Session) -> Session:
  match allowed:
    case False{}: st
    case True{}:
      match st:
        case Session{+cl, _, _, _, _, _, _, _, Size{rows, cols}, _, _, split, _, _, +media, _, _, +iso, _, +cf, _, _, labelsbox, +pends}:
          +full_kept = C.maintain_full(unbox_full(cf), unbox_media(media), cl)
          +st1 = session_set_full(st, full_kept)
          session_observe_visible_cards.gated(Isupport.as_iso(unbox_iso(iso)), C.is_open(full_kept), st1, cl, rows, cols, split, unbox_media(media), unbox_cards(cf))

def session_observe_visible_cards(+st: Session) -> Session:
  session_observe_visible_cards.allowed(visible_media_net(session_net(st)) && C.enabled(session_cards(st)), st)

def session_observe_cards(+st: Session) -> Session:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _, +media, _, _, _, _, +cf, _, _, labelsbox, +pends}:
      session_set_full(session_set_cards(st, C.maintain(unbox_cards(cf), cl)), C.maintain_full(unbox_full(cf), unbox_media(media), cl))

# Admission is computed at completion time against the live client: exact
# worker identity, enabled generation, and a live target. No visible-partition
# gate: a hidden-but-live text completion still lands in the bounded cache.
def session_accept_card_result(+st: Session, +generation: Nat, +ticket: Nat, +url: String) -> Bool:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +cf, _, _, labelsbox, +pends}:
      C.accept(unbox_cards(cf), cl, generation, ticket, url)

def cards_job_net(net: NetState) -> Bool:
  media_job_net(net)

def session_cards_job_allowed.open(open: Bool, net: NetState) -> Bool:
  match open:
    case True{}: False{}
    case False{}: cards_job_net(net)

def session_cards_job_allowed(+st: Session) -> Bool:
  session_cards_job_allowed.open(C.is_open(C.maintain_full(session_full(st), session_media(st), session_cl(st))), session_net(st))

# Fullscreen entry/exit binding: F9 toggles, Escape closes. Entry opens the
# newest ready alive image; the stored token revalidates on every paint and
# every step, so disable/reset/eviction/endpoint/source loss closes it. The
# revalidated state writes back even when the key falls through.
def session_fullscreen_key.pick(pick: Maybe<&2, M.MediaReady>, +st: Session, +media: M.State) -> Session & Bool:
  match pick:
    case None{}: (st, True{})
    case Some{M.MediaReady{+target, +url, _}}: (session_set_full(st, C.open(media, target, url)), True{})

def session_fullscreen_key.toggle(open: Bool, +st: Session, +media: M.State, +cl: Cl.Client) -> Session & Bool:
  match open:
    case True{}: (session_set_full(st, C.FullOff{}), True{})
    case False{}: session_fullscreen_key.pick(M.fullscreen_pick(media, cl), st, media)

def session_fullscreen_key.f9(f9: Bool, +st: Session, +media: M.State, +cl: Cl.Client, +open: Bool) -> Session & Bool:
  match f9:
    case False{}: (st, False{})
    case True{}: session_fullscreen_key.toggle(open, st, media, cl)

def session_fullscreen_key.go(esc: Bool, f9: Bool, +st: Session, +media: M.State, +cl: Cl.Client, +open: Bool) -> Session & Bool:
  match esc:
    case True{}: (session_set_full(st, C.FullOff{}), True{})
    case False{}: session_fullscreen_key.f9(f9, st, media, cl, open)

def session_fullscreen_key(+st: Session, +key: U32, mods: U32) -> Session & Bool:
  +cl = session_cl(st)
  +media = session_media(st)
  +kept = C.maintain_full(session_full(st), media, cl)
  +st1 = session_set_full(st, kept)
  session_fullscreen_key.go(U32.is_eq(key, KEY_ESCAPE()) && C.is_open(kept),
    U32.is_eq(key, KEY_F9()) && U32.is_zero(mods), st1, media, cl, C.is_open(kept))

def images_intent.parsed(+st: Session, intent: Maybe<&2, Bool>) -> Session:
  match intent:
    case None{}: st
    case Some{on}: session_set_media(st, M.set_enabled(session_media(st), on))

def images_intent(+st: Session, +arg: String) -> Session:
  images_intent.parsed(st, Sub.images_arg(arg))

def preview_intent.accepted(accepted: Bool, +st: Session, +source: String) -> Session:
  match accepted:
    case False{}: st
    case True{}:
      +current = M.maintain(session_media(st), session_cl(st))
      +full = M.manual_saturated(current, source)
      +media = M.enqueue(current, M.Manual{}, source)
      +next = session_set_media(st, M.maintain(media, session_cl(st)))
      Bool.pick(Session, full, session_error(next, "image preview queue is full; try again"), next)

def media_intent.parsed(+st: Session, input: Sub.Input) -> Session:
  match input:
    case Sub.CommandInput{Sub.ImagesCmd{}, _, rest}: images_intent(st, Irc.drop_spaces(rest))
    case Sub.CommandInput{Sub.PreviewCmd{}, _, +rest}:
      +arg = Irc.drop_spaces(rest)
      +source = Bool.pick(String, Sub.is_http_pfx(arg), arg, Sub.preview_local_path(arg))
      preview_intent.accepted(Bool.not(String.is_empty(source)) && M.alive(session_cl(st), M.Manual{}, source), st, source)
    case _: st

def media_intent(enter: Bool, +st: Session, input: Sub.Input) -> Session:
  match enter:
    case False{}: st
    case True{}: media_intent.parsed(st, input)

def theme_intent.parsed(+st: Session, got: Maybe<&2, Theme.Id>) -> Session:
  match got:
    case None{}: st
    case Some{+th}: session_set_theme(st, th)

def theme_intent(+st: Session, +arg: String) -> Session:
  theme_intent.parsed(st, Sub.theme_arg(arg))

def theme_session.parsed(+st: Session, input: Sub.Input) -> Session:
  match input:
    case Sub.CommandInput{Sub.ThemeCmd{}, _, rest}: theme_intent(st, Irc.drop_spaces(rest))
    case _: st

def theme_session(enter: Bool, +st: Session, input: Sub.Input) -> Session:
  match enter:
    case False{}: st
    case True{}: theme_session.parsed(st, input)

def session_paint_vm(+st: Session) -> View.ViewModel:
  match st:
    case Session{+cl, _, _, +draft, _, _, +net, _, Size{+rows, +cols}, _, _, split, +typing, _, +media, _, _, +iso, _, _, _, +theme, labelsbox, +pends}:
      View.view_draft.state_typing_media_iso_themed(Isupport.as_iso(unbox_iso(iso)), cl, rows, cols, draft, net_label_lag_pend(net, Cl.client_lag(cl), List.length(&2, Cl.PendSend, pends)), Ty.names(typing, Cl.active_buf_name(cl)), split, unbox_media(media), theme, pends)

def step_keys.intent(keys: Keys, +after: Nat, +input: Sub.Input, trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match keys:
    case Keys{_, +enter, _, _, _, _, _, _, _}:
      match trip:
        case (st, cmd, halt): (theme_session(enter, session_observe_cards(session_observe_media(media_intent(enter, st, input), after)), input), cmd, halt)

def step_keys.plan.got(pair: JoinPlan.State & List<&2, String>, st: Session, halt: Bool) -> Session & NetCmd & Bool:
  match pair:
    case (plan, outs): (session_set_plan(st, plan), Cont{outs}, halt)

# Only accepted submission outputs change desired membership. Recovery emits
# bypass this seam, so it cannot turn a reset into an explicit settings edit.
def local_plan.got(pair: JoinPlan.State & List<&2, String>, st: Session) -> Session:
  match pair:
    case (plan, _): session_set_plan(st, plan)

def local_plan.validated(pair: Cl.Client & List<&2, String>, +st: Session) -> Session:
  match pair:
    case (_, outs): local_plan.got(JoinPlan.outbound_iso(session_plan(st), outs, session_iso(st)), st)

def local_plan.input(input: Sub.Input, cl: Cl.Client, +st: Session) -> Session:
  match input:
    case Sub.CommandInput{Sub.Part{}, verb, rest}: local_plan.validated(Sub.submit_parsed_with(session_iso(st), cl, Sub.CommandInput{Sub.Part{}, verb, rest}), st)
    case Sub.CommandInput{Sub.CloseCmd{}, verb, rest}: local_plan.validated(Sub.submit_parsed_with(session_iso(st), cl, Sub.CommandInput{Sub.CloseCmd{}, verb, rest}), st)
    case _: st

# Local submission drops wire output. Reuse its validator against the prior
# client to recover only accepted PART/close intent, never a guessed target.
def local_plan.enter(local: Bool, +before: Session, st: Session, input: Sub.Input) -> Session:
  match local:
    case False{}: st
    case True{}: local_plan.input(input, session_cl(before), st)

def local_plan.keys(keys: Keys, +before: Session, st: Session, input: Sub.Input) -> Session:
  match keys:
    case Keys{_, enter, _, _, _, _, _, _, _}:
      local_plan.enter(enter && Bool.not(can_send(session_net(before))), before, st, input)

def step_keys.plan.admit(allowed: Bool, +before: Session, +st: Session, outs: List<&2, String>, halt: Bool) -> Session & NetCmd & Bool:
  match allowed:
    case True{}: step_keys.plan.got(JoinPlan.outbound_iso(session_plan(st), outs, session_iso(st)), st, halt)
    case False{}:
      # The rejected JOIN has no accepted membership. Discard its staged
      # tab/roster changes as well as the wire and runtime-only key update.
      (session_set_client(session_set_plan(st, session_plan(before)),
        Sub.echo_err_server(session_cl(before), "channel limit reached (14 desired channels)")), Cont{Nil{}}, halt)

def step_keys.plan.admit_iso(iso_ok: Bool, +before: Session, +st: Session, outs: List<&2, String>, halt: Bool) -> Session & NetCmd & Bool:
  match iso_ok:
    case True{}: step_keys.plan.got(JoinPlan.outbound_iso(session_plan(st), outs, session_iso(st)), st, halt)
    case False{}:
      # The server-narrowed JOIN has no accepted membership. Discard its
      # staged tab/roster changes as well as the wire and key update.
      (session_set_client(session_set_plan(st, session_plan(before)),
        Sub.echo_err_server(session_cl(before), "channel refused by server policy (CHANTYPES/CHANNELLEN)")), Cont{Nil{}}, halt)

def step_keys.plan.gated(cap_ok: Bool, +before: Session, +st: Session, +outs: List<&2, String>, halt: Bool) -> Session & NetCmd & Bool:
  match cap_ok:
    case False{}: step_keys.plan.admit(False{}, before, st, outs, halt)
    case True{}: step_keys.plan.admit_iso(session_outs_admitted(st, outs), before, st, outs, halt)

def step_keys.plan(+before: Session, keys: Keys, trip: Session & NetCmd & Bool, input: Sub.Input) -> Session & NetCmd & Bool:
  match trip:
    case (+st, cmd, halt):
      match cmd:
        case Cont{+outs}:
          +next = local_plan.keys(keys, before, st, input)
          step_keys.plan.gated(JoinPlan.capacity_ok_iso(outs, session_plan(next), session_iso(next)), before, next, outs, halt)
        case _: (st, cmd, halt)

def preference_enter(enter: Bool, st: Session, input: Sub.Input) -> Session:
  match enter:
    case False{}: st
    case True{}: session_preference_record(Sub.preference_intent(input), st)

def step_keys.preferences(keys: Keys, input: Sub.Input, trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match keys:
    case Keys{_, enter, _, _, _, _, _, _, _}:
      match trip:
        case (st, cmd, halt): (preference_enter(enter, st, input), cmd, halt)

# Session-owned multiline submit/history policy. The production key path
# uses multiline_quad + hist_after_typed for RouteMulti; the supplied seam
# completes an explicit quad/history through the same finish and hooks.

# One exact history entry per multiline enter: the raw typed text is pushed
# whole (blanks and CRLF separators preserved for HistPrev recall) unless
# any wired line is credential-sensitive, in which case the whole entry is
# suppressed exactly like a sensitive single-line submit. Per-line echo
# masking stays in Drafts.submit_lines via the shared Sub rule.
# Each line is judged by the negotiated single-line rule (per-line planned
# targets for /msg, /query, /notice, join/mode keys, /raw) plus the
# current-target message rule, so a rejected command paste carrying a
# secret never leaves its raw block in HistPrev recall. The joined whole
# is judged too: the single-line rule strips CR/LF before parsing, so a
# credential verb fractured across a line break (IDEN\rTIFY) reads
# sensitive whole but benign per fragment (fail closed).
def multiline_sensitive.line(+iso: Isupport.State, +cl: Cl.Client, +target: String, +line: String) -> Bool:
  Sub.input_sensitive_iso(iso, cl, line) || Sub.message_sensitive(cl, target, line, False{})

def multiline_sensitive.any(+tail: Bool, sensitive: Bool) -> Bool:
  match sensitive:
    case True{}: True{}
    case False{}: tail

def multiline_sensitive.go(+iso: Isupport.State, +lines: List<&2, String>, +cl: Cl.Client, +target: String) -> Bool:
  match lines:
    case Nil{}: False{}
    case Con{+h, +t}: multiline_sensitive.any(multiline_sensitive.go(iso, t, cl, target), multiline_sensitive.line(iso, cl, target, h))

def hist_after_typed(+hist: Hist, +cl: Cl.Client, +target: String, +typed: String, +iso: Isupport.State) -> Hist:
  hist_after_enter(hist, typed, Bool.not(multiline_sensitive.go(iso, Drafts.nonempty(Drafts.split_lines(typed)), cl, target) || Sub.input_sensitive_iso(iso, cl, typed)))

def multiline_held.triple.r1(rest: String & NetCmd, +cl_err: Cl.Client, split: Sp.State, +typed: String) -> Cl.Client & String & NetCmd & Sp.State:
  match rest:
    case (_, _): (cl_err, typed, Cont{Nil{}}, Sp.follow_active(cl_err, split))

def multiline_held.triple(triple: Cl.Client & String & NetCmd, split: Sp.State, +typed: String) -> Cl.Client & String & NetCmd & Sp.State:
  match triple:
    case (+cl_err, rest): multiline_held.triple.r1(rest, cl_err, split, typed)

def multiline_held(+cl: Cl.Client, split: Sp.State, +typed: String) -> Cl.Client & String & NetCmd & Sp.State:
  multiline_held.triple(hold_offline(cl), split, typed)

def multiline_quad.empty(+cl2: Cl.Client, +outs: List<&2, String>, split: Sp.State, +typed: String, empty: Bool) -> Cl.Client & String & NetCmd & Sp.State:
  match empty:
    case True{}: (cl2, typed, Cont{outs}, Sp.follow_active(cl2, split))
    case False{}: (cl2, "", Cont{outs}, Sp.follow_active(cl2, split))

def multiline_quad.outs(+cl2: Cl.Client, +outs: List<&2, String>, split: Sp.State, +typed: String) -> Cl.Client & String & NetCmd & Sp.State:
  +empty = List.is_empty(&2, String, outs)
  multiline_quad.empty(cl2, outs, split, typed, empty)

def multiline_quad.pair(pair: Cl.Client & List<&2, String>, split: Sp.State, +typed: String) -> Cl.Client & String & NetCmd & Sp.State:
  match pair:
    case (cl2, outs):
      multiline_quad.outs(cl2, outs, split, typed)

def multiline_quad_echo.gated(+cl: Cl.Client, split: Sp.State, +typed: String, +net: NetState, admits: Bool, +echo_ok: Bool) -> Cl.Client & String & NetCmd & Sp.State:
  match admits:
    case True{}:
      +bi = Cl.active_of(cl)
      multiline_quad.pair(Drafts.submit_lines_echo(cl, bi, Sp.name_at(cl, bi), typed, False{}, echo_ok), split, typed)
    case False{}:
      multiline_held(cl, split, typed)

def multiline_quad.gated(+cl: Cl.Client, split: Sp.State, +typed: String, +net: NetState, admits: Bool) -> Cl.Client & String & NetCmd & Sp.State:
  multiline_quad_echo.gated(cl, split, typed, net, admits, False{})

def multiline_quad_echo(+cl: Cl.Client, split: Sp.State, +typed: String, +net: NetState, +echo_ok: Bool) -> Cl.Client & String & NetCmd & Sp.State:
  multiline_quad_echo.gated(cl, split, typed, net, can_send(net), echo_ok)

def multiline_quad(+cl: Cl.Client, split: Sp.State, +typed: String, +net: NetState) -> Cl.Client & String & NetCmd & Sp.State:
  multiline_quad_echo(cl, split, typed, net, False{})

# Shared completion for explicitly supplied history + submit quads.
# Separate frame finishing from command hooks so multiline production can
# retain the real frame keys without reparsing a rejected command block.
def step_keys.supplied_finish(+st: Session, +keys: Keys, +hist2: Hist, quad: Cl.Client & String & NetCmd & Sp.State) -> Session & NetCmd & Bool:
  finish_keys.quad(st, keys, hist2, quad)

def step_keys.supplied_hooks(+st: Session, +keys: Keys, trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, enter, _, _, _, _, _, _, _}:
      +input = step_keys.parsed(enter, typed)
      step_keys.preferences(keys, input, step_keys.intent(keys, Cl.log_seq_of(session_cl(st)), input, step_keys.plan(st, keys, trip, input)))

def step_keys.supplied_normal(+st: Session, +keys: Keys, +hist2: Hist, quad: Cl.Client & String & NetCmd & Sp.State) -> Session & NetCmd & Bool:
  step_keys.supplied_hooks(st, keys, step_keys.supplied_finish(st, keys, hist2, quad))

# Session-level /history trigger: the Client submit path only echoes and
# emits wire lines, so this seam stamps the live history owner. Search/page
# begin a search ticket and return a stamped Search command for the loop's
# async worker (disabled history passes through: submit already echoed); an
# actually-issued fetch (nonempty outs) arms a fetch ticket bound to its
# target while gated, offline, and usage inputs never arm. The wgen
# incarnation stays a placeholder here like Dial's gen: the loop's
# generation owner stamps it at emit (with_gen/emit_cmd).
def step_keys.history_search_begin(pair: Session & Nat, +halt: Bool, +text: String, +target: String, +cursor: Nat, +rest: String) -> Session & NetCmd & Bool:
  match pair:
    case (+st2, +ticket):
      +hl = session_hist_live(st2)
      (st2, Search{text, target, cursor, rest, Hs.hist_live_endpoint(hl), True{}, ticket, Hs.hist_live_gen(hl), 0}, halt)

def step_keys.history_search_on(on: Bool, +st: Session, +cmd: NetCmd, +halt: Bool, +text: String, +target: String, +cursor: Nat, +rest: String) -> Session & NetCmd & Bool:
  match on:
    case True{}: step_keys.history_search_begin(history_search_begin(st), halt, text, target, cursor, rest)
    case False{}: (st, cmd, halt)

def step_keys.history_armed(pair: Session & Nat, +cmd: NetCmd, +halt: Bool) -> Session & NetCmd & Bool:
  match pair:
    case (+st2, _): (st2, cmd, halt)

def step_keys.history_issued(issued: Bool, +st: Session, +cmd: NetCmd, +halt: Bool, +target: String) -> Session & NetCmd & Bool:
  match issued:
    case True{}: step_keys.history_armed(history_fetch_begin(st, target), cmd, halt)
    case False{}: (st, cmd, halt)

def step_keys.history_fetch(cmd: NetCmd, +st: Session, +halt: Bool, +target: String) -> Session & NetCmd & Bool:
  match cmd:
    case Cont{+outs}: step_keys.history_issued(Bool.not(List.is_empty(&2, String, outs)), st, cmd, halt, target)
    case _: (st, cmd, halt)

def step_keys.history_req(req: Hs.HistoryRequest, +st: Session, +cmd: NetCmd, +halt: Bool) -> Session & NetCmd & Bool:
  match req:
    case Hs.ReqSearch{+text, +target, +rest}:
      step_keys.history_search_on(Cl.settings_history(Cl.get_settings(session_cl(st))), st, cmd, halt, text, target, Hs.SEARCH_CURSOR_FRESH(), rest)
    case Hs.ReqPage{+cursor, +text, +target, +rest}:
      step_keys.history_search_on(Cl.settings_history(Cl.get_settings(session_cl(st))), st, cmd, halt, text, target, cursor, rest)
    case Hs.ReqUsage{}: (st, cmd, halt)
    case Hs.ReqLatest{+target, _}: step_keys.history_fetch(cmd, st, halt, target)
    case Hs.ReqBefore{+target, _, _}: step_keys.history_fetch(cmd, st, halt, target)
    case Hs.ReqAfter{+target, _, _}: step_keys.history_fetch(cmd, st, halt, target)
    case Hs.ReqAround{+target, _, _}: step_keys.history_fetch(cmd, st, halt, target)
    case Hs.ReqBetween{+target, _, _, _}: step_keys.history_fetch(cmd, st, halt, target)

def step_keys.history_typed(+st: Session, +cmd: NetCmd, +halt: Bool, input: Sub.Input) -> Session & NetCmd & Bool:
  match input:
    case Sub.CommandInput{Sub.History{}, _, +rest}: step_keys.history_req(Hs.parse_request(rest), st, cmd, halt)
    case _: (st, cmd, halt)

def step_keys.history_enter(enter: Bool, +st: Session, +cmd: NetCmd, +halt: Bool, input: Sub.Input) -> Session & NetCmd & Bool:
  match enter:
    case True{}: step_keys.history_typed(st, cmd, halt, input)
    case False{}: (st, cmd, halt)

def step_keys.history(keys: Keys, input: Sub.Input, trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match keys:
    case Keys{_, +enter, _, _, _, _, _, _, _}:
      match trip:
        case (st, cmd, halt): step_keys.history_enter(enter, st, cmd, halt, input)

# Key-hook order, outer hook last. Composer Enter is parsed once into
# Sub.Input and threaded through every hook; hooks must not parse again.
#   1. step_keys.base         submit, navigation, completion
#   2. step_keys.plan         join-plan admission of outbound lines
#   3. step_keys.history      /history search or fetch arming
#   4. step_keys.intent       preview intent after the line is accepted
#   5. step_keys.preferences  settings verbs
# step_keys.supplied_hooks is the multiline entry: it skips base and history
# (the quad is already submitted) and runs plan, intent, preferences.
# It reparses only when Enter is still set; the multiline route clears Enter
# before calling it.
def step_keys.chain(+st: Session, +keys: Keys, +input: Sub.Input) -> Session & NetCmd & Bool:
  step_keys.preferences(keys, input, step_keys.intent(keys, Cl.log_seq_of(session_cl(st)), input, step_keys.history(keys, input, step_keys.plan(st, keys, step_keys.base(st, keys, input), input))))

def step_keys.normal(+st: Session, +keys: Keys, +input: Sub.Input) -> Session & NetCmd & Bool:
  step_keys.chain(st, keys, input)

def step_keys.upload_restore(trip: Session & NetCmd & Bool, state: Up.State, presented: Bool) -> Session & NetCmd & Bool:
  match trip:
    case (st, cmd, halt): (session_upload_maintain(session_upload_mark(session_set_upload(st, state), presented)), cmd, halt)

# Completion and worker state have distinct nonrecursive payloads. Ordinary
# editing/history/completion can proceed while Busy without dropping its owner.
def step_keys.multiline_done(trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match trip:
    case (st, cmd, _): (st, cmd, False{})

# Clear only Enter; preserve every other frame field.
def keys_without_enter(keys: Keys) -> Keys:
  match keys:
    case Keys{typed, _, tab, click, up, dn, hist, comp, focus}:
      Keys{typed, False{}, tab, click, up, dn, hist, comp, focus}

# Finish with the original keys so navigation/completion see the real frame.
# Command hooks must not reinterpret a rejected multiline block as a single
# slash command. Accepted chat wires still update the plan through outbound.
def step_keys.ordinary_route(route: Drafts.Route, +st: Session, +keys: Keys, +typed: String, input: Sub.Input) -> Session & NetCmd & Bool:
  match route:
    case Drafts.RouteMulti{_}:
      +cl = session_cl(st)
      +bi = Cl.active_of(cl)
      +hist2 = hist_after_typed(session_hist(st), cl, Sp.name_at(cl, bi), typed, session_iso(st))
      trip = step_keys.supplied_finish(st, keys, hist2, multiline_quad_echo(cl, session_split(st), typed, session_net(st), session_echo_ok(st)))
      step_keys.supplied_hooks(st, keys_without_enter(keys), step_keys.multiline_done(trip))
    case _: step_keys.normal(st, keys, input)

def step_keys.ordinary_enter(enter: Bool, +st: Session, +keys: Keys, +typed: String, input: Sub.Input) -> Session & NetCmd & Bool:
  match enter:
    case False{}: step_keys.normal(st, keys, Sub.EmptyInput{})
    case True{}: step_keys.ordinary_route(Drafts.route(typed), st, keys, typed, input)

def step_keys.ordinary_keys(+st: Session, +keys: Keys, input: Sub.Input) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, enter, _, _, _, _, _, _, _}:
      step_keys.ordinary_enter(enter, st, keys, typed, input)

def step_keys.ordinary(+st: Session, keys: Keys, input: Sub.Input) -> Session & NetCmd & Bool:
  step_keys.upload_restore(step_keys.ordinary_keys(session_set_upload(st, Up.empty()), keys, input), session_upload(st), session_upload_presented(st))

# Supplied-submit seam: complete an explicit history + submit quad while
# clearing/restoring upload ownership across the step. Production key callers
# use ordinary dispatch; this seam shares its finish and hooks.
def step_keys.supplied(+st: Session, +keys: Keys, +hist2: Hist, quad: Cl.Client & String & NetCmd & Sp.State) -> Session & NetCmd & Bool:
  # Keep only the original upload payload across the supplied step, not st.
  state = session_upload(st)
  presented = session_upload_presented(st)
  cleared = session_set_upload(st, Up.empty())
  session_label_trip(step_keys.upload_restore(step_keys.supplied_normal(cleared, keys, hist2, quad), state, presented))

def seam_submitted.got(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl2, _): cl2

def seam_submitted(+cl: Cl.Client, +input: String) -> Cl.Client:
  seam_submitted.got(Sub.submit(cl, input))

def seam_outs(+cmd: NetCmd) -> String:
  match cmd:
    case Cont{+outs}: String.join(outs, "|")
    case _: "[noncont]"

def seam_hist(+hist: Hist) -> String:
  match hist:
    case Hist{+lines, _}: String.join(lines, "|")

def seam_quad(+cl: Cl.Client, split: Sp.State) -> Cl.Client & String & NetCmd & Sp.State:
  (cl, "", Cont{"PRIVMSG #b :aa" <> "PRIVMSG #b :bb" <> Nil{}}, split)

def supplied_seam_ok.summary.r1(rest: NetCmd & Bool, +st2: Session) -> String:
  match rest:
    case (+cmd, +halt):
      seam_outs(cmd) ++ ";" ++ session_draft(st2) ++ ";" ++ seam_hist(session_hist(st2))
        ++ ";" ++ Bool.show(halt) ++ ";" ++ Cl.active_buf_name(session_cl(st2))
        ++ ";" ++ U32.show(session_seed(st2))

def supplied_seam_ok.summary(trip: Session & NetCmd & Bool) -> String:
  match trip:
    case (+st2, rest): supplied_seam_ok.summary.r1(rest, st2)

def supplied_seam_ok() -> Bool:
  +st = session_demo(seam_submitted(seam_submitted(Cl.init("me", "irc.example"), "/join #a"), "/join #b"), "#a")
  +hist2 = hist_after_enter(session_hist(st), "aa\nbb", True{})
  quad = seam_quad(session_cl(st), session_split(st))
  String.eq(supplied_seam_ok.summary(step_keys.supplied(st, keys_enter("aa\nbb"), hist2, quad)), "PRIVMSG #b :aa|PRIVMSG #b :bb;;aa\nbb;False;#b;0")

def upload_modal_keys(keys: Keys) -> Keys:
  keys_without_enter(keys)

def step_keys.upload_blocked.r1(rest: NetCmd & Bool, +st: Session, enter: Bool) -> Session & NetCmd & Bool:
  match rest:
    case (+cmd, +halt):
      # Native Enter clears its editor; restore the same unsent draft once.
      (Bool.pick(Session, enter, session_upload_draft(st, session_draft(st), 1), st), cmd, halt)

def step_keys.upload_blocked(trip: Session & NetCmd & Bool, enter: Bool) -> Session & NetCmd & Bool:
  match trip:
    case (+st, rest): step_keys.upload_blocked.r1(rest, st, enter)

type UploadInput is Data:
  NotUpload{}
  UploadPaths{paths: List<&2, String>}
  UploadBad{}

def upload_input.paths(got: Maybe<&2, List<&2, String>>, explicit: Bool, raw: String) -> UploadInput:
  match got:
    case None{}: Bool.pick(UploadInput, explicit || Up.looks_local_drop(raw), UploadBad{}, NotUpload{})
    case Some{paths}: UploadPaths{paths}

# Bare /name is a command, not an ambiguous root-level file. A second slash
# or literal path quoting/escaping in the verb marks a drop; later arguments
# cannot supply that intent. Explicit /upload remains the root-file escape hatch.
def upload_input.path_verb(+verb: String) -> Bool:
  Bool.not(String.contains(verb, "://"))
    && (String.contains(verb, "/") || String.contains(verb, "\\")
      || String.contains(verb, "'") || String.contains(verb, "\""))

def upload_input.unknown(command: Bool, +raw: String) -> UploadInput:
  match command:
    case True{}: NotUpload{}
    case False{}: upload_input.paths(Up.parse_paths(raw, True{}), False{}, raw)

def upload_input.parsed(input: Sub.Input, +raw: String) -> UploadInput:
  match input:
    case Sub.CommandInput{Sub.UploadCmd{}, _, rest}: upload_input.paths(Up.parse_paths(rest, False{}), True{}, raw)
    # Unknown is only a verb absent from the catalog, so it is not a command alias.
    case Sub.CommandInput{Sub.Unknown{}, +verb, _}: upload_input.unknown(Bool.not(upload_input.path_verb(verb)), raw)
    case Sub.PlainInput{_}: upload_input.paths(Up.parse_paths(raw, True{}), False{}, raw)
    case _: NotUpload{}

def upload_input.enter(enter: Bool, input: Sub.Input, +raw: String) -> UploadInput:
  match enter:
    case False{}: NotUpload{}
    case True{}: upload_input.parsed(input, raw)

def step_keys.upload_offer.busy(busy: Bool, +st: Session, paths: List<&2, String>) -> Session & NetCmd & Bool:
  match busy:
    case True{}: (session_error(session_upload_draft(st, "", 1), "upload already in progress"), Cont{Nil{}}, False{})
    case False{}:
      +state = Up.offer(Up.empty(), session_upload_scope(st), session_upload_online(st), paths)
      +next = session_upload_draft(session_set_upload(st, state), "", 1)
      (Bool.pick(Session, Up.pending(state), next, session_error(next, "upload requires an online chat target")), Cont{Nil{}}, False{})

def step_keys.upload_input(input: UploadInput, +st: Session, keys: Keys, parsed: Sub.Input) -> Session & NetCmd & Bool:
  match input:
    case NotUpload{}: step_keys.ordinary(st, keys, parsed)
    case UploadBad{}: (session_error(session_upload_draft(st, "", 1), "usage: /upload <local-path>"), Cont{Nil{}}, False{})
    case UploadPaths{paths}: step_keys.upload_offer.busy(Up.active(session_upload(st)), st, paths)

def step_keys.upload_modal.go(enter: Bool, +st: Session, +keys: Keys, +typed: String) -> Session & NetCmd & Bool:
  match enter:
    case False{}: step_keys.ordinary(st, keys, Sub.EmptyInput{})
    case True{}:
      +parsed = Sub.parse_input(typed)
      step_keys.upload_input(upload_input.enter(True{}, parsed, typed), st, keys, parsed)

def step_keys.upload_modal(pending: Bool, +st: Session, +keys: Keys) -> Session & NetCmd & Bool:
  match pending:
    case True{}:
      match keys:
        case Keys{_, enter, _, _, _, _, _, _, _}:
          step_keys.upload_blocked(step_keys.ordinary(st, upload_modal_keys(keys), Sub.EmptyInput{}), enter)
    case False{}:
      match keys:
        case Keys{+typed, enter, _, _, _, _, _, _, _}:
          step_keys.upload_modal.go(enter, st, keys, typed)

def help_open(+st: Session, +topic: String) -> Session & NetCmd & Bool:
  +opened = session_put_finish(st, session_cl(st), "", session_hist(st), 1, CompHelp{topic}, session_split(st))
  (session_after(opened, Cont{Nil{}}), Cont{Nil{}}, False{})

def step_keys.help_on(is_help: Bool, +st: Session, keys: Keys, +typed: String) -> Session & NetCmd & Bool:
  match is_help:
    case False{}: session_label_trip(step_keys.upload_modal(False{}, st, keys))
    case True{}: session_label_trip(help_open(st, Cu.help_arg(typed)))

def step_keys.help.typed(enter: Bool, +st: Session, keys: Keys, +typed: String) -> Session & NetCmd & Bool:
  match enter:
    case False{}: session_label_trip(step_keys.upload_modal(False{}, st, keys))
    case True{}: step_keys.help_on(Cu.is_help(typed), st, keys, typed)

def step_keys.help(enter: Bool, +st: Session, keys: Keys) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, _, _, _, _, _, _, _, _}:
      step_keys.help.typed(enter, st, keys, typed)

def step_keys.open(st: Session, keys: Keys) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, +enter, +tab, +click, +up, +dn, +hist, +comp, +focus}:
      step_keys.help.typed(enter, st, Keys{typed, enter, tab, click, up, dn, hist, comp, focus}, typed)

def step_keys.start(pending: Bool, +st: Session, keys: Keys) -> Session & NetCmd & Bool:
  match pending:
    case True{}: session_label_trip(step_keys.upload_modal(True{}, st, keys))
    case False{}: step_keys.open(st, keys)

def step_keys(+st: Session, keys: Keys) -> Session & NetCmd & Bool:
  +next = session_upload_maintain(st)
  step_keys.start(Up.pending(session_upload(next)), next, keys)

# Hidden wins over a draft that still reads /help, so Esc can dismiss the
# catalog and the next Esc is free to quit.
def panel_menu(xs: List<&2, String>, typers: List<&2, String>) -> List<&2, String>:
  Sk.panel_menu(xs, typers)

def panel_lines(comp: Comp, +draft: String, +hint: String, typers: List<&2, String>) -> List<&2, String>:
  Sk.panel_lines(view_of(comp), draft, hint, typers)

def step_enter(+st: Session, +line: String) -> Session & NetCmd & Bool:
  step_keys(st, keys_enter(line))

type StampedLine is Data:
  StampedLine{wire: String, stamp: Maybe<&2, String>}

def stamped_lines(lines: List<&2, String>, stamps: List<&2, Maybe<&2, String>>) -> List<&2, StampedLine>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}:
      match stamps:
        case Nil{}: StampedLine{line, None{}} <> stamped_lines(rest, Nil{})
        case Con{stamp, tail}: StampedLine{line, stamp} <> stamped_lines(rest, tail)

# G6 live: the line fold carries the stored registration beside the protocol
# fold. Each wire line updates caps via reg_on_line with the server and nick
# from the Client at that position plus the pre-line registration phase
# (JoinPlan.welcomed). Rejected welcomes leave the accumulator untouched.
type LiveAcc is Data:
  LiveAcc{fold: FoldAcc, typing: Ty.State, plan: JoinPlan.State, iso: Isupport.State, hl: Hs.HistLive, reg: CapNotify.Reg, renames: List<&2, Drafts.NickRename>}

def live_step.flushed(fed: FoldAcc, typing: Ty.State, flushed: JoinPlan.Flush, +iso: Isupport.State, +hl: Hs.HistLive, +reg: CapNotify.Reg, +renames: List<&2, Drafts.NickRename>) -> LiveAcc:
  match fed:
    case FoldAcc{+cl, reversed, now_ms}:
      match flushed:
        case JoinPlan.Flush{plan, outs, notice}:
          LiveAcc{FoldAcc{join_notice(cl, notice), List.append(&2, String, List.reverse(&2, String, outs), reversed), now_ms}, Ty.retain_client(typing, cl), plan, iso, hl, reg, renames}

def live_step.fed(+fed: FoldAcc, typing: Ty.State, plan: JoinPlan.State, +iso: Isupport.State, +hl: Hs.HistLive, +reg: CapNotify.Reg, +renames: List<&2, Drafts.NickRename>) -> LiveAcc:
  match fed:
    case FoldAcc{+cl, _, _}: live_step.flushed(fed, typing, JoinPlan.flush_iso(plan, cl, iso), iso, hl, reg, renames)

def live_step.flushed_with(+cm: String, fed: FoldAcc, typing: Ty.State, flushed: JoinPlan.Flush, +iso: Isupport.State, +hl: Hs.HistLive, +reg: CapNotify.Reg, +renames: List<&2, Drafts.NickRename>) -> LiveAcc:
  match fed:
    case FoldAcc{+cl, reversed, now_ms}:
      match flushed:
        case JoinPlan.Flush{plan, outs, notice}:
          LiveAcc{FoldAcc{join_notice(cl, notice), List.append(&2, String, List.reverse(&2, String, outs), reversed), now_ms}, Ty.retain_client_cm(cm, typing, cl), plan, iso, hl, reg, renames}

def live_step.fed_with(+cm: String, +fed: FoldAcc, typing: Ty.State, plan: JoinPlan.State, +iso: Isupport.State, +hl: Hs.HistLive, +reg: CapNotify.Reg, +renames: List<&2, Drafts.NickRename>) -> LiveAcc:
  match fed:
    case FoldAcc{+cl, _, _}: live_step.flushed_with(cm, fed, typing, JoinPlan.flush_iso(plan, cl, iso), iso, hl, reg, renames)

# Keep the original wire text for protocol/authentication/membership policy.
# A local timestamp override affects only the display/history feed.
# Admitted live lines rename split panes in the fold, exactly once and in
# arrival order; archived (claimed) lines never reach this arm, so batch
# NICKs leave Client, split, and drafts unchanged. No raw prepass exists.
def live_step.registered(registered: Maybe<&2, Cl.Client>, acc: LiveAcc, +line: String, stamp: Maybe<&2, String>, welcomed: Bool, +port: U32) -> LiveAcc:
  match registered:
    case None{}: acc
    case Some{+cl}:
      match acc:
        case LiveAcc{FoldAcc{_, reversed, +now_ms}, typing, plan, +iso, +hl, +reg, +renames}:
          live_step.fed(fold_step.got_at(cl, reversed, now_ms, line, stamp, port),
            Ty.apply_line_for(typing, cl, line, now_ms), JoinPlan.received(plan, cl, line), iso, hl,
            CapNotify.reg_on_line(reg, Cl.server_of(cl), Cl.nick_of(cl), line, welcomed), renames)

# Each wire line first updates the negotiated 005 state (gated against the
# pre-line client, so a 001+005 same-chunk nick change gates correctly),
# then folds with live MODE/324 redaction under the current map. A burst
# and its dependent 001/ flush therefore order correctly within one chunk.
def live_step.prep(+iso: Isupport.State, +cl: Cl.Client, +line: String) -> Isupport.State & String:
  +iso2 = Isupport.feed_state(iso, cl, line)
  (iso2, session_redact_wire(iso2, line))

def live_is_dynamic.cmd(c: Irc.Cmd, +m: Irc.Message) -> Bool:
  match c:
    case Irc.Join{}: True{}
    case Irc.Part{}: True{}
    case Irc.Kick{}: True{}
    case Irc.Quit{}: True{}
    case Irc.Nick{}: True{}
    case Irc.Privmsg{}: True{}
    case Irc.Notice{}: True{}
    case Irc.Tagmsg{}: True{}
    case Irc.Topic{}: True{}
    case Irc.Mode{}: True{}
    case Irc.Numeric{_}:
      U32.is_eq(Irc.msg_num(m), 353) || U32.is_eq(Irc.msg_num(m), 332) || JoinPlan.motd_num(Irc.msg_num(m))
    case _: False{}

def live_is_dynamic.parsed(parsed: Maybe<&2, Irc.Message>) -> Bool:
  match parsed:
    case None{}: False{}
    case Some{+m}: live_is_dynamic.cmd(Irc.classify(m), m)

def live_is_dynamic(+line: String) -> Bool:
  live_is_dynamic.parsed(Irc.parse(line))

def live_step.registered_with(registered: Maybe<&2, Cl.Client>, acc: LiveAcc, +line: String, stamp: Maybe<&2, String>, +isc: Cl.Iso, welcomed: Bool, +port: U32) -> LiveAcc:
  match registered:
    case None{}: acc
    case Some{+cl}:
      match acc:
        case LiveAcc{FoldAcc{_, reversed, +now_ms}, typing, plan, +iso, +hl, +reg, +renames}:
          live_step.fed_with(Cl.iso_cm(isc), fold_step.got_at_with(isc, cl, reversed, now_ms, line, stamp, port),
            Ty.apply_line_for_with(isc, typing, cl, line, now_ms), JoinPlan.received_with(Cl.iso_cm(isc), plan, cl, line), iso, hl,
            CapNotify.reg_on_line(reg, Cl.server_of(cl), Cl.nick_of(cl), line, welcomed), renames)

# Admitted per-line split rename (I2-dynamic4 G1C): the raw chunk prepass
# sampled the initial iso once, so a same-chunk 005+NICK matched under the
# old mapping while Client (per-line negotiated) retained the pane. Thread
# split through the live fold with the evolving iso cm, gated by the same
# registration + auth/credential admission as the Client feed. Reuses the
# negotiated rename_query.line_cm owner per line; no raw prepass remains.
def live_split_admitted.consumed(consumed: Bool, +cm2: String, split: Sp.State, +line2: String) -> Sp.State:
  match consumed:
    case True{}: split
    case False{}: Sp.rename_query.line_cm(cm2, split, line2)

def live_split_admitted.some(+cl_reg: Cl.Client, +cm2: String, split: Sp.State, +line2: String) -> Sp.State:
  +consumed = live_consumed(cl_reg, line2)
  live_split_admitted.consumed(consumed, cm2, split, line2)

def live_split_admitted(registered: Maybe<&2, Cl.Client>, +cm2: String, split: Sp.State, +line2: String) -> Sp.State:
  match registered:
    case None{}: split
    case Some{+cl_reg}: live_split_admitted.some(cl_reg, cm2, split, line2)

# Sole preparation/admission owner (I2 Final): one Isupport/redact prep plus
# one registration admission per wire line, shared by the Client feed and
# the split-pane gate. live_split_step.pair is the single live entry; both
# halves consume the same LiveAdmitted exactly once. Prep and registration
# are pure functions of (iso, cl, line), so sharing the deterministic
# result is behavior-identical to the former dual paths. No signature or
# behavior change elsewhere; live_consumed stays the shared consume gate.
# Admitted per-line draft-rename effect (CM-NICK fold owner): lines reaching
# this arm passed H5-claim, registration, and consume gates under the
# evolving per-line cm; batch-tagged, unregistered, consumed, and invalid
# lines emit nothing. Validity mirrors split's accepted gate; the drafts
# application rechecks query shape. Ceiling revert restores the pre-line
# LiveAcc, so refused lines leave no effect.
def live_drafts_note.allowed(allowed: Bool, +live: LiveAcc, +cm: String, +m: Irc.Message) -> LiveAcc:
  match allowed:
    case False{}: live
    case True{}:
      match live:
        case LiveAcc{+fold, +typing, +plan, +iso, +hl, +reg, +renames}:
          LiveAcc{fold, typing, plan, iso, hl, reg, Drafts.NickRename{Cl.target_name(Irc.msg_nick(m)), Cl.target_name(Irc.msg_param(m, 0n)), cm} <> renames}

def live_drafts_note.nick(nick: Bool, +live: LiveAcc, +cm: String, +m: Irc.Message) -> LiveAcc:
  match nick:
    case False{}: live
    case True{}: live_drafts_note.allowed(Cl.nick_rename_allowed(Irc.msg_nick(m), Irc.msg_param(m, 0n)), live, cm, m)

def live_drafts_note.parsed(+live: LiveAcc, +cm: String, m: Maybe<&2, Irc.Message>) -> LiveAcc:
  match m:
    case None{}: live
    case Some{+msg}: live_drafts_note.nick(Irc.ieq(Irc.msg_command(msg), "NICK"), live, cm, msg)

def live_drafts_note.some(+live: LiveAcc, +cm: String, +line2: String, consumed: Bool) -> LiveAcc:
  match consumed:
    case True{}: live
    case False{}: live_drafts_note.parsed(live, cm, Irc.parse(line2))

def live_drafts_note.consumed(+live: LiveAcc, +cl_reg: Cl.Client, +cm: String, +line2: String) -> LiveAcc:
  live_drafts_note.some(live, cm, line2, live_consumed(cl_reg, line2))

def live_drafts_note(+live: LiveAcc, registered: Maybe<&2, Cl.Client>, +cm: String, +line2: String) -> LiveAcc:
  match registered:
    case None{}: live
    case Some{+cl_reg}: live_drafts_note.consumed(live, cl_reg, cm, line2)

type LiveAdmitted is Data:
  LiveAdmitted{iso2: Isupport.State, line2: String, reg: Maybe<&2, Cl.Client>}

def live_prepare.reg(prepped: Isupport.State & String, +cl: Cl.Client, welcomed: Bool) -> LiveAdmitted:
  match prepped:
    case (+iso2, +line2):
      LiveAdmitted{iso2, line2, registration_client_iso(welcomed, cl, line2, iso2)}

def live_prepare(+iso: Isupport.State, +cl: Cl.Client, welcomed: Bool, +line: String) -> LiveAdmitted:
  live_prepare.reg(live_step.prep(iso, cl, line), cl, welcomed)

def live_split_step.ready_branch(+reg: Maybe<&2, Cl.Client>, +isc: Cl.Iso, +line2: String, acc: LiveAcc, split: Sp.State, stamp: Maybe<&2, String>, dynamic: Bool, welcomed: Bool, +port: U32) -> LiveAcc & Sp.State:
  match dynamic:
    case True{}:
      +live2 = live_step.registered_with(reg, acc, line2, stamp, isc, welcomed, port)
      +split2 = live_split_admitted(reg, Cl.iso_cm(isc), split, line2)
      (live_drafts_note(live2, reg, Cl.iso_cm(isc), line2), split2)
    case False{}:
      +live2 = live_step.registered(reg, acc, line2, stamp, welcomed, port)
      +split2 = live_split_admitted(reg, Cl.iso_cm(isc), split, line2)
      (live_drafts_note(live2, reg, Cl.iso_cm(isc), line2), split2)

def live_split_step.ready(ready: LiveAdmitted, +cl: Cl.Client, reversed: List<&2, String>, +now_ms: U32, typing: Ty.State, +plan: JoinPlan.State, split: Sp.State, stamp: Maybe<&2, String>, +hl: Hs.HistLive, +lreg: CapNotify.Reg, +renames: List<&2, Drafts.NickRename>, +port: U32) -> LiveAcc & Sp.State:
  match ready:
    case LiveAdmitted{+iso2, +line2, +reg}:
      live_split_step.ready_branch(reg, Isupport.as_iso(iso2), line2, LiveAcc{FoldAcc{cl, reversed, now_ms}, typing, plan, iso2, hl, lreg, renames}, split, stamp, live_is_dynamic(line2), JoinPlan.welcomed(plan), port)

# Combined live interceptor (H5+I2): every framed wire line first steps the
# real H5 history owner. Claimed (batch-tagged archive) lines reach the batch
# collector only: no iso prep, registration, feed, unread, CAP, typing,
# split, or join-recovery effects. Unclaimed lines continue through the
# single I2 preparation/admission owner (one live_prepare per line, shared
# by the Client feed and the split-pane gate). No raw prepass exists.
def live_split_step.unclaimed(claimed: Bool, +hl2: Hs.HistLive, +iso: Isupport.State, +cl: Cl.Client, reversed: List<&2, String>, +now_ms: U32, typing: Ty.State, +plan: JoinPlan.State, split: Sp.State, +line: String, stamp: Maybe<&2, String>, +lreg: CapNotify.Reg, +renames: List<&2, Drafts.NickRename>, +port: U32) -> LiveAcc & Sp.State:
  match claimed:
    case True{}: (LiveAcc{FoldAcc{cl, reversed, now_ms}, typing, plan, iso, hl2, lreg, renames}, split)
    case False{}:
      live_split_step.ready(live_prepare(iso, cl, JoinPlan.welcomed(plan), line), cl, reversed, now_ms, typing, plan, split, stamp, hl2, lreg, renames, port)

def live_split_step.hist(pair: Hs.HistLive & Bool, +iso: Isupport.State, +cl: Cl.Client, reversed: List<&2, String>, +now_ms: U32, typing: Ty.State, +plan: JoinPlan.State, split: Sp.State, +line: String, stamp: Maybe<&2, String>, +lreg: CapNotify.Reg, +renames: List<&2, Drafts.NickRename>, +port: U32) -> LiveAcc & Sp.State:
  match pair:
    case (+hl2, +claimed): live_split_step.unclaimed(claimed, hl2, iso, cl, reversed, now_ms, typing, plan, split, line, stamp, lreg, renames, port)

def live_split_step.pair(+live: LiveAcc, split: Sp.State, +item: StampedLine, +port: U32) -> LiveAcc & Sp.State:
  match live:
    case LiveAcc{FoldAcc{+cl, reversed, now_ms}, typing, +plan, +iso, +hl, +lreg, +renames}:
      match item:
        case StampedLine{+line, stamp}:
          live_split_step.hist(Hs.hist_live_step(hl, Isupport.as_iso(iso), Cl.nick_of(cl), Cl.server_of(cl), line, JoinPlan.welcomed(plan)),
            iso, cl, reversed, now_ms, typing, plan, split, line, stamp, lreg, renames, port)

def live_split_step(+port: U32, acc: LiveAcc & Sp.State, item: StampedLine) -> LiveAcc & Sp.State:
  match acc:
    case (+live, +split):
      live_split_step.pair(live, split, item, port)

def fold_split.go(+fuel: Nat, +port: U32, acc: LiveAcc & Sp.State, +xs: List<&2, StampedLine>) -> LiveAcc & Sp.State:
  match fuel:
    case 0n: acc
    case 1n+f:
      match xs:
        case Nil{}: acc
        case Con{+h, +t}: fold_split.go(f, port, live_split_step(port, acc, h), t)

def fold_split(+port: U32, acc: LiveAcc & Sp.State, +xs: List<&2, StampedLine>) -> LiveAcc & Sp.State:
  fold_split.go(List.length(&2, StampedLine, xs), port, acc, xs)

# Ceiling admission over the (LiveAcc & Sp.State) pair: step one line
# through the single live entry, then revert the whole line (the entire
# extended LiveAcc plus the split rename) when its allocation would reach
# the ceiling, so a rejected NICK preserves pane, query, and IDs together.
# Non-allocating lines (PING, consumed auth) never overflow and stay
# admitted. Existing IDs are preserved; overflow suffixes drop with no
# side effects.
def live_split_ceiling.pick(overflows: Bool, +prev_live: LiveAcc, +prev_split: Sp.State, +cl: Cl.Client, +reversed: List<&2, String>, +now_ms: U32, +typing: Ty.State, +plan: JoinPlan.State, +iso: Isupport.State, +hl: Hs.HistLive, +reg: CapNotify.Reg, +split2: Sp.State, +renames: List<&2, Drafts.NickRename>) -> LiveAcc & Sp.State:
  match overflows:
    case True{}: (prev_live, prev_split)
    case False{}: (LiveAcc{FoldAcc{cl, reversed, now_ms}, typing, plan, iso, hl, reg, renames}, split2)

def live_split_ceiling.check(+prev_live: LiveAcc, +prev_split: Sp.State, +cl: Cl.Client, +reversed: List<&2, String>, +now_ms: U32, +typing: Ty.State, +plan: JoinPlan.State, +iso: Isupport.State, +hl: Hs.HistLive, +reg: CapNotify.Reg, +split2: Sp.State, +ceiling: Nat, +renames: List<&2, Drafts.NickRename>) -> LiveAcc & Sp.State:
  live_split_ceiling.pick(Bool.not(Nat.is_lt(Cl.log_seq_of(cl), ceiling)), prev_live, prev_split, cl, reversed, now_ms, typing, plan, iso, hl, reg, split2, renames)

def live_split_ceiling.next(+prev_live: LiveAcc, +prev_split: Sp.State, +nlive: LiveAcc, +split2: Sp.State, +ceiling: Nat) -> LiveAcc & Sp.State:
  match nlive:
    case LiveAcc{FoldAcc{+cl, +reversed, +now_ms}, +typing, +plan, +iso, +hl, +reg, +renames}:
      live_split_ceiling.check(prev_live, prev_split, cl, reversed, now_ms, typing, plan, iso, hl, reg, split2, ceiling, renames)

def live_split_ceiling.go(+prev_live: LiveAcc, +prev_split: Sp.State, next: LiveAcc & Sp.State, +ceiling: Nat) -> LiveAcc & Sp.State:
  match next:
    case (+nlive, +split2):
      live_split_ceiling.next(prev_live, prev_split, nlive, split2, ceiling)

def live_split_ceiling.step(+live: LiveAcc, +split: Sp.State, +item: StampedLine, +ceiling: Nat, +port: U32) -> LiveAcc & Sp.State:
  live_split_ceiling.go(live, split, live_split_step.pair(live, split, item, port), ceiling)

def live_split_ceiling(prev: LiveAcc & Sp.State, +item: StampedLine, +ceiling: Nat, +port: U32) -> LiveAcc & Sp.State:
  match prev:
    case (+live, +split):
      live_split_ceiling.step(live, split, item, ceiling, port)

def fold_split_ceiling.go(+fuel: Nat, acc: LiveAcc & Sp.State, +xs: List<&2, StampedLine>, +ceiling: Nat, +port: U32) -> LiveAcc & Sp.State:
  match fuel:
    case 0n: acc
    case 1n+f:
      match xs:
        case Nil{}: acc
        case Con{+h, +t}: fold_split_ceiling.go(f, live_split_ceiling(acc, h, ceiling, port), t, ceiling, port)

def fold_split_ceiling(+port: U32, acc: LiveAcc & Sp.State, +xs: List<&2, StampedLine>, +ceiling: Nat) -> LiveAcc & Sp.State:
  fold_split_ceiling.go(List.length(&2, StampedLine, xs), acc, xs, ceiling, port)

def step_chunk_got(
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +port: U32,
  rem: List<&2, U32>,
  drop: Bool,
  got: LiveAcc,
  +media: M.State,
  +edits: List<&2, String>,
  +cards: C.State,
  +full: C.Fullscreen,
  +theme: Theme.Id,
  +labelsbox: List<&2, Nat>,
  +pends: List<&2, Cl.PendSend>
) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match got:
    case LiveAcc{FoldAcc{+cl2, reversed, _}, typing, +plan, +iso, +hl, +reg, +renames}:
      +typing2 = Ty.retain_client(typing, cl2)
      (Session{cl2, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, Sp.normalize(cl2, split), typing2, port, [media], plan, edits, [iso], [hl], [C.Retained{cards, full}], [reg], theme, labelsbox, pends}, List.reverse(&2, String, reversed), List.reverse(&2, Drafts.NickRename, renames))

def step_chunk_got.folded(
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  +port: U32,
  rem: List<&2, U32>,
  drop: Bool,
  pair: LiveAcc & Sp.State,
  +media: M.State,
  +edits: List<&2, String>,
  +cards: C.State,
  +full: C.Fullscreen,
  +theme: Theme.Id,
  +labelsbox: List<&2, Nat>,
  +pends: List<&2, Cl.PendSend>
) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match pair:
    case (+got, +split2):
      step_chunk_got(draft, chan, net, hist, size, seed, comp, split2, port, rem, drop, got, media, edits, cards, full, theme, labelsbox, pends)


def step_on_chunk_pair(
  +cl: Cl.Client,
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +typing: Ty.State,
  +port: U32,
  +now_ms: U32,
  got: List<&2, String> & List<&2, U32> & Bool,
  stamps: List<&2, Maybe<&2, String>>,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>,
  +iso: Isupport.State,
  +hl: Hs.HistLive,
  +cards: C.State,
  +full: C.Fullscreen,
  +regbox: List<&2, CapNotify.Reg>,
  +theme: Theme.Id,
  +labelsbox: List<&2, Nat>,
  +pends: List<&2, Cl.PendSend>
) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match got:
    case (lines, rem2, drop2):
      step_chunk_got.folded(
        draft, chan, net, hist, size, seed, comp, port, rem2, drop2,
        fold_split(port, (LiveAcc{FoldAcc{cl, Nil{}, now_ms}, typing, plan, iso, hl, unbox_reg(regbox), Nil{}}, split), stamped_lines(lines, stamps)), media, edits, cards, full, theme, labelsbox, pends)

def step_on_chunk_pair_ceiling(+st: Session, +now_ms: U32, got: List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +ceiling: Nat) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match st:
    case Session{+cl, _, _, +draft, _, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      match got:
        case (lines, rem2, drop2):
          step_chunk_got.folded(
            draft, chan, net, hist, size, seed, comp, port, rem2, drop2,
            fold_split_ceiling(port, (LiveAcc{FoldAcc{cl, Nil{}, now_ms}, typing, plan, unbox_iso(iso), unbox_hist_live(hlbox), unbox_reg(regbox), Nil{}}, split), stamped_lines(lines, stamps), ceiling), unbox_media(media), edits, unbox_cards(cf), unbox_full(cf), theme, labelsbox, pends)

# NICK-arrival draft rename (I2 CM rename across the live path): the Client

def frame_chunk(st: Session, chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32> & Bool:
  match st:
    case Session{_, drop, rem, _, _, _, _, _, _, _, _, _, _, _, _, _, +edits, _, _, _, _, _, labelsbox, +pends}: Fr.push_ex(drop, rem, chunk)

def step_on_framed_ms.base.dropped(trip: Session & List<&2, String> & List<&2, Drafts.NickRename>) -> Session & List<&2, String>:
  match trip:
    case (st, outs, _): (st, outs)

def step_on_framed_ms.base(+st: Session, framed: List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Session & List<&2, String>:
  match st:
    case Session{+cl, drop, rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      step_on_framed_ms.base.dropped(step_on_chunk_pair(cl, draft, chan, net, hist, size, seed, comp, split, typing, port, now_ms, framed, stamps, unbox_media(media), plan, edits, unbox_iso(iso), unbox_hist_live(hlbox), unbox_cards(cf), unbox_full(cf), regbox, theme, labelsbox, pends))

def step_on_framed_ms_ceiling.base(+st: Session, framed: List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32, +ceiling: Nat) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  step_on_chunk_pair_ceiling(st, now_ms, framed, stamps, ceiling)

def step_on_chunk_ms.observed(after: Nat, trip: Session & List<&2, String>) -> Session & List<&2, String>:
  match trip:
    case (st, outs): (session_observe_cards(session_observe_media(st, after)), outs)

# Pieces variant of observed: rebuilding a pair literal from matched pieces
# as a bare call argument cannot infer gens, so the ceiling triple threads
# Session/outs separately and builds only in declared-return position.
def step_on_chunk_ms.observed_st(+after: Nat, +st: Session, +outs: List<&2, String>) -> Session & List<&2, String>:
  (session_observe_cards(session_observe_media(st, after)), outs)

def step_on_framed_ms.confirmed(pair: Session & List<&2, String>, +st: Session, +lines: List<&2, String>) -> Session & List<&2, String>:
  match pair:
    case (+st2, +outs): (session_set_pends(st2, pend_confirm_lines(session_cm(st), session_pends(st), Cl.nick_of(session_cl(st)), lines)), outs)

def step_on_framed_ms.split(+lines: List<&2, String>, +rem: List<&2, U32>, +drop: Bool, +st: Session, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Session & List<&2, String>:
  step_on_framed_ms.confirmed(step_on_chunk_ms.observed(Cl.log_seq_of(session_cl(st)), step_on_framed_ms.base(st, (lines, rem, drop), stamps, now_ms)), st, lines)

def step_on_framed_ms(+st: Session, framed: List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Session & List<&2, String>:
  match framed:
    case (lines, rem, drop): step_on_framed_ms.split(lines, rem, drop, st, stamps, now_ms)

def step_on_framed_ms_ceiling.observed3.go(pair: Session & List<&2, String>, +renames: List<&2, Drafts.NickRename>) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match pair:
    case (+st2, +outs2): (st2, outs2, renames)

def step_on_framed_ms_ceiling.observed3.rest(rest: List<&2, String> & List<&2, Drafts.NickRename>, +after: Nat, +st: Session) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match rest:
    case (+outs, +renames): step_on_framed_ms_ceiling.observed3.go(step_on_chunk_ms.observed_st(after, st, outs), renames)

def step_on_framed_ms_ceiling.observed3(+after: Nat, trip: Session & List<&2, String> & List<&2, Drafts.NickRename>) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match trip:
    case (+st, rest): step_on_framed_ms_ceiling.observed3.rest(rest, after, st)

def step_on_framed_ms_ceiling.confirmed(trip: Session & List<&2, String> & List<&2, Drafts.NickRename>, +st: Session, +lines: List<&2, String>) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match trip:
    case (st2, outs, renames): (session_set_pends(st2, pend_confirm_lines(session_cm(st), session_pends(st), Cl.nick_of(session_cl(st)), lines)), outs, renames)

def step_on_framed_ms_ceiling.split(+lines: List<&2, String>, +rem: List<&2, U32>, +drop: Bool, +st: Session, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32, +ceiling: Nat) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  step_on_framed_ms_ceiling.confirmed(step_on_framed_ms_ceiling.observed3(Cl.log_seq_of(session_cl(st)), step_on_framed_ms_ceiling.base(st, (lines, rem, drop), stamps, now_ms, ceiling)), st, lines)

def step_on_framed_ms_ceiling(+st: Session, framed:
 List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32, +ceiling: Nat) -> Session & List<&2, String> & List<&2, Drafts.NickRename>:
  match framed:
    case (lines, rem, drop): step_on_framed_ms_ceiling.split(lines, rem, drop, st, stamps, now_ms, ceiling)

# Live chunk entry with source backfill: steps the framed lines, then drains
# a completed chathistory batch through the gated source import. Quiet unless
# a fetch armed the page owner, so ordinary traffic is unchanged.
def step_on_framed_drained.rest(rest: Nat & List<&2, Nat>, +st3: Session, +outs: List<&2, String>) -> Session & List<&2, String> & Nat & List<&2, Nat>:
  match rest:
    case (+seed, +claimed): (st3, outs, seed, claimed)

def step_on_framed_drained.outs(pair: Session & Nat & List<&2, Nat>, +outs: List<&2, String>) -> Session & List<&2, String> & Nat & List<&2, Nat>:
  match pair:
    case (+st3, rest): step_on_framed_drained.rest(rest, st3, outs)

def step_on_framed_drained.fed(+st2: Session, +outs: List<&2, String>) -> Session & List<&2, String> & Nat & List<&2, Nat>:
  step_on_framed_drained.outs(history_complete_self(st2), outs)

def step_on_framed_drained.go(pair: Session & List<&2, String>) -> Session & List<&2, String> & Nat & List<&2, Nat>:
  match pair:
    case (+st2, +outs): step_on_framed_drained.fed(st2, outs)

def step_on_framed_drained(+st: Session, framed: List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Session & List<&2, String> & Nat & List<&2, Nat>:
  step_on_framed_drained.go(step_on_framed_ms(st, framed, stamps, now_ms))

# Ceiling-aware drained entry for multiserver parts: steps the framed lines
# through the ceiling fold (whole LiveAcc/split rollback per line) then drains
# a completed chathistory batch once through the ceiling-gated completion
# owner. Quiet unless a fetch armed the page owner, so ordinary traffic is
# unchanged. The drain installs the claimed set once; history save excludes
# it once. A drain that would mint at/above the ceiling refuses atomically
# with the live-fold state and wire outs kept, so the batch stays armed.
def step_on_framed_drained_ceiling.fed_renames(quad: Session & List<&2, String> & Nat & List<&2, Nat>, +renames: List<&2, Drafts.NickRename>) -> Session & List<&2, String> & Nat & List<&2, Nat> & List<&2, Drafts.NickRename>:
  match quad:
    case (st3, outs2, seed, claimed): (st3, outs2, seed, claimed, renames)

def step_on_framed_drained_ceiling.fed(+st2: Session, +outs: List<&2, String>, +ceiling: Nat, +renames: List<&2, Drafts.NickRename>) -> Session & List<&2, String> & Nat & List<&2, Nat> & List<&2, Drafts.NickRename>:
  step_on_framed_drained_ceiling.fed_renames(step_on_framed_drained.outs(history_complete_self_ceiling(st2, ceiling), outs), renames)

def step_on_framed_drained_ceiling.go.rest(rest: List<&2, String> & List<&2, Drafts.NickRename>, +st2: Session, +ceiling: Nat) -> Session & List<&2, String> & Nat & List<&2, Nat> & List<&2, Drafts.NickRename>:
  match rest:
    case (+outs, +renames): step_on_framed_drained_ceiling.fed(st2, outs, ceiling, renames)

def step_on_framed_drained_ceiling.go(trip: Session & List<&2, String> & List<&2, Drafts.NickRename>, +ceiling: Nat) -> Session & List<&2, String> & Nat & List<&2, Nat> & List<&2, Drafts.NickRename>:
  match trip:
    case (+st2, rest): step_on_framed_drained_ceiling.go.rest(rest, st2, ceiling)

def step_on_framed_drained_ceiling(+st: Session, framed: List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32, +ceiling: Nat) -> Session & List<&2, String> & Nat & List<&2, Nat> & List<&2, Drafts.NickRename>:
  step_on_framed_drained_ceiling.go(step_on_framed_ms_ceiling(st, framed, stamps, now_ms, ceiling), ceiling)

def step_on_chunk_ms(+st: Session, chunk: List<&2, U32>, +now_ms: U32) -> Session & List<&2, String>:
  step_on_framed_ms(st, frame_chunk(st, chunk), Nil{}, now_ms)

# ---- desktop-notification dispatch (N9 runtime) -------------------------------
# Pure Session seam. The parent loop threads Notify.State, stages returned Reqs
# into the bounded async queue, and owns delivery; these helpers only build
# exact-spelling scoped events and fold them through Notify.decide. No
# Session/UiMsg type change here; parent owns that merge.
#
# Scope is the exact endpoint spelling (host:port), never case-folded, so
# per-scope high-water marks cannot collide across servers or spellings.
def notify_scope(+server: String, +port: U32) -> String:
  Ep.endpoint(server, port)

def notify_scope_of(+st: Session) -> String:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, +port, _, _, _, _, _, _, _, _, labelsbox, +pends}:
      notify_scope(Cl.server_of(cl), port)

# Classification is pure and lives in notify.bend so the notify laws can
# see it. Wrappers keep the Sess.notify_* names wsnet and the tests call.

def notify_is_highlight(k: Cl.LineKind) -> Bool:
  Notify.notify_is_highlight(k)

def notify_is_action(k: Cl.LineKind) -> Bool:
  Notify.notify_is_action(k)

def notify_is_dm_kind(k: Cl.LineKind) -> Bool:
  Notify.notify_is_dm_kind(k)

def notify_is_mention(+author: String, +text: String, +nick: String, +k: Cl.LineKind) -> Bool:
  Notify.notify_is_mention(author, text, nick, k)

def notify_is_query(+name: String, is_channel: Bool, index: Nat) -> Bool:
  Notify.notify_is_query(name, is_channel, index)

def notify_line_dm(query: Bool, +author: String, +nick: String, k: Cl.LineKind) -> Bool:
  Notify.notify_line_dm(query, author, nick, k)

def notify_line_hits(query: Bool, +author: String, +text: String, +nick: String, +k: Cl.LineKind) -> Bool:
  Notify.notify_line_hits(query, author, text, nick, k)

def notify_collect_line.keep(keep: Bool, +scope: String, +author: String, +target: String, +text: String, +id: Nat, +dm: Bool, +mention: Bool, tail: List<&2, Notify.NotifyEvent>) -> List<&2, Notify.NotifyEvent>:
  Notify.notify_collect_line.keep(keep, scope, author, target, text, id, dm, mention, tail)

def notify_collect_lines(lines: List<&2, Cl.Line>, +scope: String, +target: String, +nick: String, +cutoff: Nat, +query: Bool) -> List<&2, Notify.NotifyEvent>:
  Notify.notify_collect_lines(lines, scope, target, nick, cutoff, query)

def notify_collect_bufs(bufs: List<&2, Cl.Buffer>, +scope: String, +nick: String, +cutoff: Nat, +index: Nat) -> List<&2, Notify.NotifyEvent>:
  Notify.notify_collect_bufs(bufs, scope, nick, cutoff, index)

def notify_collect(+cl: Cl.Client, +scope: String, +cutoff: Nat) -> List<&2, Notify.NotifyEvent>:
  Notify.notify_collect(cl, scope, cutoff)


type NotifyFold is Data:
  NotifyFold{st: Notify.State, reqs: List<&2, Notify.Req>, user: String, pass: String}

def notify_fold_pushed(got: Maybe<&2, Notify.Req>, reqs: List<&2, Notify.Req>) -> List<&2, Notify.Req>:
  match got:
    case None{}: reqs
    case Some{+r}: List.append(&2, Notify.Req, reqs, r <> Nil{})

def notify_fold_applied(pair: Notify.State & Maybe<&2, Notify.Req>, reqs: List<&2, Notify.Req>, +user: String, +pass: String) -> NotifyFold:
  match pair:
    case (+st, got): NotifyFold{st, notify_fold_pushed(got, reqs), user, pass}

def notify_fold_step(acc: NotifyFold, ev: Notify.NotifyEvent) -> NotifyFold:
  match acc:
    case NotifyFold{+st, +reqs, +user, +pass}:
      notify_fold_applied(Notify.decide(st, ev, user, pass), reqs, user, pass)

def notify_fold_fin(acc: NotifyFold) -> Notify.State & List<&2, Notify.Req>:
  match acc:
    case NotifyFold{+st, +reqs, _, _}: (st, reqs)

# Events sort by (scope, id) before the fold: collection order is buffer
# order, but marks are per-scope hi-watermarks, so an unsorted fold lets a
# higher id in an earlier buffer shadow lower fresh ids later. The sorted
# fold notifies every fresh event exactly once in ascending id order however
# the buffers are ordered, and replays at or below the mark stay silent.
def notify_dispatch(+st: Notify.State, +events: List<&2, Notify.NotifyEvent>, +user: String, +pass: String) -> Notify.State & List<&2, Notify.Req>:
  notify_fold_fin(List.foldl(~&2, ~Notify.NotifyEvent, ~NotifyFold, ~notify_fold_step, Notify.sort_events(events), NotifyFold{st, Nil{}, user, pass}))

# Collect every mention/DM row above the cutoff and fold it through
# Notify.decide. Marks (not the cutoff) own at-most-once: replays stay silent
# even with a stale cutoff.
def notify_observe(+st: Notify.State, +cl: Cl.Client, +scope: String, +cutoff: Nat, +user: String, +pass: String) -> Notify.State & List<&2, Notify.Req>:
  notify_dispatch(st, notify_collect(cl, scope, cutoff), user, pass)

# History cutoff without notifying: mark restored rows as seen before live dispatch.
# Post-restore seed: MUST take the final imported client. Import assigns fresh
# ids after all current local events (plus dividers), so only the final
# log_seq covers every restored row. Seeding with the pre-import or snapshot
# sequence re-notifies restored mentions on first live dispatch.
def notify_seed_postrestore(+st: Notify.State, +scope: String, +imported: Cl.Client) -> Notify.State:
  Notify.seed(st, scope, Cl.log_seq_of(imported))

# ---- live dispatch package (N9 full) -----------------------------------------
# The per-chunk entry the parent loop calls after each live chunk. It feeds
# the chunk through the same step_on_chunk_ms every other live path uses,
# observes the fed Session with the tracked scan floor (seeded from the
# pre-chunk/history log_seq), stages admitted reqs into the bounded queue,
# and reports the handed jobs for the single worker. Even an undeliverable
# step stages into the queue (marks on admit) and advances the floor past
# admitted rows only, so nothing is lost: admitted reqs are retained for the
# next deliverable step, and rows past a full queue keep their marks and
# floor for retry. The notify path never changes outs or the fed Session:
# chat is unaffected by helper presence.
type NotifyLive is Data:
  NotifyLive{st: Notify.State, queue: Notify.Queue, scanned: Nat, active: Maybe<&2, Nat>, next: Nat, endpoint: String, origin: String, claimed: List<&2, Nat>}

def notify_live_st(+nl: NotifyLive) -> Notify.State:
  match nl:
    case NotifyLive{+st, _, _, _, _, _, _, _}: st

def notify_live_queue(+nl: NotifyLive) -> Notify.Queue:
  match nl:
    case NotifyLive{_, +q, _, _, _, _, _, _}: q

def notify_live_scanned(+nl: NotifyLive) -> Nat:
  match nl:
    case NotifyLive{_, _, +scanned, _, _, _, _, _}: scanned

def notify_live_active(+nl: NotifyLive) -> Maybe<&2, Nat>:
  match nl:
    case NotifyLive{_, _, _, +active, _, _, _, _}: active

def notify_live_next(+nl: NotifyLive) -> Nat:
  match nl:
    case NotifyLive{_, _, _, _, +next, _, _, _}: next

def notify_live_endpoint(+nl: NotifyLive) -> String:
  match nl:
    case NotifyLive{_, _, _, _, _, +endpoint, _, _}: endpoint

# origin is the endpoint the active physical ticket was handed for; "" while
# idle. Logical reset/off/cancel keep (active, origin) until the EXACT
# completion arrives, so the detached worker is never duplicated.
def notify_live_origin(+nl: NotifyLive) -> String:
  match nl:
    case NotifyLive{_, _, _, _, _, _, +origin, _}: origin

# claimed is the durable per-ID archive-exclusion set, retained until scanned
# past (R2). Chunk-level claims merge here; the scan floor never bumps for
# archive rows, so interleaved live rows stay eligible.
def notify_live_claimed(+nl: NotifyLive) -> List<&2, Nat>:
  match nl:
    case NotifyLive{_, _, _, _, _, _, _, +claimed}: claimed

def notify_busy_of(+active: Maybe<&2, Nat>) -> Bool:
  match active:
    case None{}: False{}
    case Some{_}: True{}

def notify_live_busy(+nl: NotifyLive) -> Bool:
  match nl:
    case NotifyLive{_, _, _, +active, _, _, _, _}: notify_busy_of(active)

def notify_live_init(+st: Notify.State, +scanned: Nat) -> NotifyLive:
  NotifyLive{st, Notify.queue_empty(), scanned, None{}, 1n, "", "", Nil{}}

def notify_live_init_ep(+st: Notify.State, +scanned: Nat, +endpoint: String) -> NotifyLive:
  NotifyLive{st, Notify.queue_empty(), scanned, None{}, 1n, endpoint, "", Nil{}}

# Live session seam: exact-spelling scope, client credentials, and cutoff
# floor. Marks advance only for reqs admitted to the bounded queue so a full
# queue can retry without consuming at-most-once for dropped rows.
def notify_observe_session_staged(+st: Notify.State, +sess: Session, +floor: Nat, +q: Notify.Queue) -> Notify.Stage:
  match sess:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, labelsbox, +pends}:
      Notify.stage(st, notify_collect(cl, notify_scope_of(sess), floor), Cl.client_sasl_user(cl), Cl.client_sasl_pass(cl), q, floor)

# Real archive-claim producer (gate a, lossless owner): after an install, every
# NOTIFY-WORTHY row (mention or DM, same predicates as notify_collect) above
# the pre-import sequence becomes the per-ID exclusion set, with NO
# truncation here: installed ids are fresh, sequential, and bounded (at most
# MAX_BUFFERS * SCROLL_CAP rows per import), so every qualifying installed id
# is claimed and the bounded union below enforces the cap. Chatter never
# notifies, so it is never claimed. Buffer order, line order, oldest first.
def notify_claims_lines.keep(fresh: Bool, +id: Nat, +tail: List<&2, Nat>) -> List<&2, Nat>:
  match fresh:
    case True{}: id <> tail
    case False{}: tail

def notify_claims_lines(lines: List<&2, Cl.Line>, +nick: String, +query: Bool, +before: Nat) -> List<&2, Nat>:
  match lines:
    case Nil{}: Nil{}
    case Con{Cl.Line{+k, _, +text, +author, +id}, t}:
      notify_claims_lines.keep(Nat.is_gt(id, before) && notify_line_hits(query, author, text, nick, k), id, notify_claims_lines(t, nick, query, before))

def notify_claims_bufs(bufs: List<&2, Cl.Buffer>, +nick: String, +before: Nat, +index: Nat) -> List<&2, Nat>:
  match bufs:
    case Nil{}: Nil{}
    case Con{Cl.Buffer{+name, is_channel, _, +lines, _, _, _, _}, t}:
      List.append(&2, Nat, notify_claims_lines(lines, nick, notify_is_query(name, is_channel, index), before), notify_claims_bufs(t, nick, before, Nat.add(index, 1n)))

def notify_claims_installed(+before: Nat, +after: Cl.Client) -> List<&2, Nat>:
  match after:
    case Cl.Client{+nick, _, +bufs, _, _, _, _, _, _}:
      notify_claims_bufs(bufs, nick, before, 0n)

def notify_observe_session_staged_claimed(+st: Notify.State, +sess: Session, +floor: Nat, +q: Notify.Queue, +claimed: List<&2, Nat>) -> Notify.Stage:
  match sess:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, labelsbox, +pends}:
      Notify.stage_claimed(st, notify_collect(cl, notify_scope_of(sess), floor), Cl.client_sasl_user(cl), Cl.client_sasl_pass(cl), q, floor, claimed)

# Every step/observe exit stores the effective exclusion set pruned at the new
# floor: exclusions persist across chunks until scanned past, and the floor
# itself never bumps for archive rows.
def notify_live_quiet(s: Notify.Stage, +sess2: Session, +outs: List<&2, String>, +active: Maybe<&2, Nat>, +next: Nat, +endpoint: String, +origin: String, +eff: List<&2, Nat>) -> NotifyLive & Session & List<&2, String> & List<&2, Notify.Req>:
  match s:
    case Notify.Stage{+st2, +q2, _, +hi, _, _}:
      (NotifyLive{st2, q2, hi, active, next, endpoint, origin, Notify.claim_prune(eff, hi)}, sess2, outs, Nil{})

def notify_live_handoff.empty(empty: Bool, +st2: Notify.State, +hi: Nat, +sess2: Session, +outs: List<&2, String>, +handed: List<&2, Notify.Req>, +next: Nat, +endpoint: String, +eff: List<&2, Nat>) -> NotifyLive & Session & List<&2, String> & List<&2, Notify.Req>:
  match empty:
    case True{}: (NotifyLive{st2, Notify.queue_empty(), hi, None{}, next, endpoint, "", Notify.claim_prune(eff, hi)}, sess2, outs, Nil{})
    case False{}: (NotifyLive{st2, Notify.queue_empty(), hi, Some{next}, Nat.add(next, 1n), endpoint, endpoint, Notify.claim_prune(eff, hi)}, sess2, outs, handed)

def notify_live_fed(s: Notify.Stage, +sess2: Session, +outs: List<&2, String>, +retained: List<&2, Notify.Req>, +next: Nat, +endpoint: String, +eff: List<&2, Nat>) -> NotifyLive & Session & List<&2, String> & List<&2, Notify.Req>:
  match s:
    case Notify.Stage{+st2, _, +admitted, +hi, _, _}:
      +handed = List.append(&2, Notify.Req, retained, admitted)
      notify_live_handoff.empty(List.is_empty(&2, Notify.Req, handed), st2, hi, sess2, outs, handed, next, endpoint, eff)

def notify_ticket_hit(+active: Maybe<&2, Nat>, +ticket: Nat) -> Bool:
  match active:
    case None{}: False{}
    case Some{+a}: Nat.is_eq(a, ticket)

# Exact means the ticket matches the retained physical worker AND the endpoint
# matches its origin (the endpoint at handoff). A logical reset may move
# `endpoint` while the detached worker still runs; only (ticket, origin)
# releases it, and a release rebinds the next ticket to the current endpoint.
def notify_live_complete.jobs(empty: Bool, +st: Notify.State, +qf: Notify.Queue, +scanned: Nat, +jobs: List<&2, Notify.Req>, +next: Nat, +stored: String, +claimed: List<&2, Nat>) -> NotifyLive & List<&2, Notify.Req> & Bool:
  match empty:
    case True{}: (NotifyLive{st, qf, scanned, None{}, next, stored, "", claimed}, Nil{}, True{})
    case False{}: (NotifyLive{st, qf, scanned, Some{next}, Nat.add(next, 1n), stored, stored, claimed}, jobs, True{})

def notify_live_complete.release(+st: Notify.State, +scanned: Nat, +next: Nat, +stored: String, +claimed: List<&2, Nat>, drained: Notify.Queue & List<&2, Notify.Req>) -> NotifyLive & List<&2, Notify.Req> & Bool:
  match drained:
    case (+qf, +jobs):
      +empty = List.is_empty(&2, Notify.Req, jobs)
      notify_live_complete.jobs(empty, st, qf, scanned, jobs, next, stored, claimed)

def notify_live_complete.go(exact: Bool, +st: Notify.State, +q: Notify.Queue, +scanned: Nat, +active: Maybe<&2, Nat>, +next: Nat, +stored: String, +origin: String, +claimed: List<&2, Nat>) -> NotifyLive & List<&2, Notify.Req> & Bool:
  match exact:
    case False{}: (NotifyLive{st, q, scanned, active, next, stored, origin, claimed}, Nil{}, False{})
    case True{}: notify_live_complete.release(st, scanned, next, stored, claimed, Notify.drain_all(q))

def notify_live_complete(+nl: NotifyLive, +ticket: Nat, +endpoint: String) -> NotifyLive & List<&2, Notify.Req> & Bool:
  match nl:
    case NotifyLive{+st, +q, +scanned, +active, +next, +stored, +origin, +claimed}:
      +hit = notify_ticket_hit(active, ticket) && String.eq(endpoint, origin)
      notify_live_complete.go(hit, st, q, scanned, active, next, stored, origin, claimed)

def notify_live_drained_claimed(drained: Notify.Queue & List<&2, Notify.Req>, +nst: Notify.State, +floor: Nat, +sess2: Session, +outs: List<&2, String>, +next: Nat, +endpoint: String, +eff: List<&2, Nat>) -> NotifyLive & Session & List<&2, String> & List<&2, Notify.Req>:
  match drained:
    case (+qf, +retained):
      notify_live_fed(notify_observe_session_staged_claimed(nst, sess2, floor, qf, eff), sess2, outs, retained, next, endpoint, eff)

def notify_live_step.idle_claimed(busy: Bool, +nst: Notify.State, +q: Notify.Queue, +floor: Nat, +active: Maybe<&2, Nat>, +next: Nat, +endpoint: String, +origin: String, +eff: List<&2, Nat>, +sess2: Session, +outs: List<&2, String>) -> NotifyLive & Session & List<&2, String> & List<&2, Notify.Req>:
  match busy:
    case True{}: notify_live_quiet(notify_observe_session_staged_claimed(nst, sess2, floor, q, eff), sess2, outs, active, next, endpoint, origin, eff)
    case False{}: notify_live_drained_claimed(Notify.drain_all(q), nst, floor, sess2, outs, next, endpoint, eff)

def notify_live_step.go_claimed(deliver: Bool, busy: Bool, +nst: Notify.State, +q: Notify.Queue, +floor: Nat, +active: Maybe<&2, Nat>, +next: Nat, +endpoint: String, +origin: String, +eff: List<&2, Nat>, pair: Session & List<&2, String>) -> NotifyLive & Session & List<&2, String> & List<&2, Notify.Req>:
  match deliver:
    case True{}:
      match pair:
        case (+sess2, +outs): notify_live_step.idle_claimed(busy, nst, q, floor, active, next, endpoint, origin, eff, sess2, outs)
    case False{}:
      match pair:
        case (+sess2, +outs): notify_live_quiet(notify_observe_session_staged_claimed(nst, sess2, floor, q, eff), sess2, outs, active, next, endpoint, origin, eff)

# Fresh chunk claims union with the durable stored set; the union filters this
# scan and persists (pruned) for later chunks. The union is floor-tied:
# stored ids at/below the floor are pruned with proof before capping, so
# stale exclusions never consume capacity or evict fresh ones.
def notify_live_step_claimed(+nl: NotifyLive, +sess: Session, +chunk: List<&2, U32>, +now_ms: U32, deliver: Bool, +claimed: List<&2, Nat>) -> NotifyLive & Session & List<&2, String> & List<&2, Notify.Req>:
  match nl:
    case NotifyLive{+nst, +q, +floor, +active, +next, +endpoint, +origin, +stored}:
      +busy = notify_busy_of(active)
      +eff = Notify.claim_union_floor(stored, claimed, floor)
      notify_live_step.go_claimed(deliver, busy, nst, q, floor, active, next, endpoint, origin, eff, step_on_chunk_ms(sess, chunk, now_ms))

# Plain steps carry no fresh claims; the durable stored set still applies.
def notify_live_step(+nl: NotifyLive, +sess: Session, +chunk: List<&2, U32>, +now_ms: U32, deliver: Bool) -> NotifyLive & Session & List<&2, String> & List<&2, Notify.Req>:
  notify_live_step_claimed(nl, sess, chunk, now_ms, deliver, Nil{})

def notify_live_reset.enabled(enabled: Bool) -> Notify.State:
  match enabled:
    case True{}: Notify.on()
    case False{}: Notify.off()

# Logical teardown keeps the physical worker: reset/off/cancel clear the queue
# (and reset/off clear marks and stored claims) but retain (active, origin)
# until the EXACT completion, so a blocked ticket never spawns a second
# worker and the old completion still runs the current FIFO exactly once.
# Cancel keeps marks and stored claims (position preserved, pending dropped).
def notify_live_reset_endpoint(+nl: NotifyLive, +new_endpoint: String, +new_floor: Nat) -> NotifyLive:
  match nl:
    case NotifyLive{+st, _, _, +active, +next, _, +origin, _}:
      +en = Notify.enabled(st)
      NotifyLive{notify_live_reset.enabled(en), Notify.queue_empty(), new_floor, active, next, new_endpoint, origin, Nil{}}

def notify_live_off(+nl: NotifyLive) -> NotifyLive:
  match nl:
    case NotifyLive{_, _, +scanned, +active, +next, +endpoint, +origin, _}:
      NotifyLive{Notify.off(), Notify.queue_empty(), scanned, active, next, endpoint, origin, Nil{}}

def notify_live_seed_postrestore(+nl: NotifyLive, +sess: Session) -> NotifyLive:
  match nl:
    case NotifyLive{+st, +q, _, +active, +next, _, +origin, +claimed}:
      +scope = notify_scope_of(sess)
      +imported = session_cl(sess)
      NotifyLive{notify_seed_postrestore(st, scope, imported), q, Cl.log_seq_of(imported), active, next, scope, origin, Notify.claim_prune(claimed, Cl.log_seq_of(imported))}

# Merge produced/installed claims into the durable set, keeping only IDs
# above the current floor. Rejected installs produce Nil: a no-op merge.
# Floor-tied: stale stored ids are pruned with proof before capping, so a
# merge never evicts live exclusions for stale ones.
def notify_live_merge_claims(+nl: NotifyLive, +fresh: List<&2, Nat>) -> NotifyLive:
  match nl:
    case NotifyLive{+st, +q, +floor, +active, +next, +endpoint, +origin, +stored}:
      NotifyLive{st, q, floor, active, next, endpoint, origin, Notify.claim_prune(Notify.claim_union_floor(stored, fresh, floor), floor)}

# Per-ID accepted-archive quieting (no blanket floor jump): accepted installs
# merge their real per-ID claims (archives quiet via claims, floor/marks kept
# so pending live9 still delivers); stale/rejected keep notify state. The
# direct seed_postrestore (floor jump, no claims) stays for initial restore
# with no pending live; the live history path must use this per-ID seed.
def notify_live_seed_accepted.go(accepted: Bool, +nl: NotifyLive, +installed: List<&2, Nat>) -> NotifyLive:
  match accepted:
    case True{}: notify_live_merge_claims(nl, installed)
    case False{}: nl

def notify_live_seed_accepted(accepted: Bool, +nl: NotifyLive, +installed: List<&2, Nat>) -> NotifyLive:
  notify_live_seed_accepted.go(accepted, nl, installed)

def notify_live_cancel.go(hit: Bool, +st: Notify.State, +scanned: Nat, +next: Nat, +stored: String, +q: Notify.Queue, +active: Maybe<&2, Nat>, +origin: String, +claimed: List<&2, Nat>) -> NotifyLive & Bool:
  match hit:
    case True{}: (NotifyLive{st, Notify.queue_empty(), scanned, active, next, stored, origin, claimed}, True{})
    case False{}: (NotifyLive{st, q, scanned, active, next, stored, origin, claimed}, False{})

def notify_live_cancel(+nl: NotifyLive, +endpoint: String) -> NotifyLive & Bool:
  match nl:
    case NotifyLive{+st, +q, +scanned, +active, +next, +stored, +origin, +claimed}:
      +hit = String.eq(endpoint, stored)
      notify_live_cancel.go(hit, st, scanned, next, stored, q, active, origin, claimed)

def notify_live_observe_quiet(s: Notify.Stage, +active: Maybe<&2, Nat>, +next: Nat, +endpoint: String, +origin: String, +eff: List<&2, Nat>) -> NotifyLive & List<&2, Notify.Req>:
  match s:
    case Notify.Stage{+st2, +q2, _, +hi, _, _}:
      (NotifyLive{st2, q2, hi, active, next, endpoint, origin, Notify.claim_prune(eff, hi)}, Nil{})

def notify_live_observe_handoff(empty: Bool, +st2: Notify.State, +hi: Nat, +handed: List<&2, Notify.Req>, +next: Nat, +endpoint: String, +eff: List<&2, Nat>) -> NotifyLive & List<&2, Notify.Req>:
  match empty:
    case True{}: (NotifyLive{st2, Notify.queue_empty(), hi, None{}, next, endpoint, "", Notify.claim_prune(eff, hi)}, Nil{})
    case False{}: (NotifyLive{st2, Notify.queue_empty(), hi, Some{next}, Nat.add(next, 1n), endpoint, endpoint, Notify.claim_prune(eff, hi)}, handed)

def notify_live_observe_fed(s: Notify.Stage, +retained: List<&2, Notify.Req>, +next: Nat, +endpoint: String, +eff: List<&2, Nat>) -> NotifyLive & List<&2, Notify.Req>:
  match s:
    case Notify.Stage{+st2, _, +admitted, +hi, _, _}:
      +handed = List.append(&2, Notify.Req, retained, admitted)
      notify_live_observe_handoff(List.is_empty(&2, Notify.Req, handed), st2, hi, handed, next, endpoint, eff)

def notify_live_observe_drained(drained: Notify.Queue & List<&2, Notify.Req>, +nst: Notify.State, +floor: Nat, +sess: Session, +next: Nat, +endpoint: String, +eff: List<&2, Nat>) -> NotifyLive & List<&2, Notify.Req>:
  match drained:
    case (+qf, +retained):
      notify_live_observe_fed(notify_observe_session_staged_claimed(nst, sess, floor, qf, eff), retained, next, endpoint, eff)

def notify_live_observe.idle(busy: Bool, +nst: Notify.State, +q: Notify.Queue, +floor: Nat, +active: Maybe<&2, Nat>, +next: Nat, +endpoint: String, +origin: String, +eff: List<&2, Nat>, +sess: Session) -> NotifyLive & List<&2, Notify.Req>:
  match busy:
    case True{}: notify_live_observe_quiet(notify_observe_session_staged_claimed(nst, sess, floor, q, eff), active, next, endpoint, origin, eff)
    case False{}: notify_live_observe_drained(Notify.drain_all(q), nst, floor, sess, next, endpoint, eff)

def notify_live_observe.go(deliver: Bool, busy: Bool, +nst: Notify.State, +q: Notify.Queue, +floor: Nat, +active: Maybe<&2, Nat>, +next: Nat, +endpoint: String, +origin: String, +eff: List<&2, Nat>, +sess: Session) -> NotifyLive & List<&2, Notify.Req>:
  match deliver:
    case True{}: notify_live_observe.idle(busy, nst, q, floor, active, next, endpoint, origin, eff, sess)
    case False{}: notify_live_observe_quiet(notify_observe_session_staged_claimed(nst, sess, floor, q, eff), active, next, endpoint, origin, eff)

def notify_live_observe(+nl: NotifyLive, +sess: Session, deliver: Bool, +claimed: List<&2, Nat>) -> NotifyLive & List<&2, Notify.Req>:
  match nl:
    case NotifyLive{+nst, +q, +floor, +active, +next, +endpoint, +origin, +stored}:
      +busy = notify_busy_of(active)
      +eff = Notify.claim_union_floor(stored, claimed, floor)
      notify_live_observe.go(deliver, busy, nst, q, floor, active, next, endpoint, origin, eff, sess)


def step_on_chunk(+st: Session, chunk: List<&2, U32>) -> Session & List<&2, String>:
  step_on_chunk_ms(st, chunk, 0)

def sess_drop(+st: Session) -> Bool:
  match st:
    case Session{_, drop, _, _, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      drop

def sess_rem_nil.of(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case _:
      False{}

def sess_rem_nil(+st: Session) -> Bool:
  match st:
    case Session{_, _, rem, _, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits, _, _, _, _, _, labelsbox, +pends}:
      sess_rem_nil.of(rem)

def st_of_chunk(p: Session & List<&2, String>) -> Session:
  match p:
    case (+st, _):
      st

def st_of_keys(t: Session & NetCmd & Bool) -> Session:
  match t:
    case (+st, rest):
      match rest:
        case (_, _):
          st

def reconnect_endpoint.got(pair: Session & NetCmd) -> Bool:
  match pair:
    case (_, Dial{+host, port, _, _}):
      String.eq(host, "127.0.0.1") && U32.is_eq(port, 16668)
    case _:
      False{}

def reconnect_endpoint_ok() -> Bool:
  +cl0 = Cl.init("me", "old.example")
  +cl1 = Cl.set_settings(cl0, Cl.set_autoreconn(Cl.get_settings(cl0), True{}))
  +s0 = session_fail(session_with_client(cl1, "#t"), "initial")
  +s1 = st_of_keys(step_enter(s0, "/connect 127.0.0.1 16668"))
  +s2 = session_fail(session_online(s1), "lost")
  reconnect_endpoint.got(session_autoreconnect(s2))

def disconnect_drop.got(pair: Session & NetCmd) -> Bool:
  match pair:
    case (_, Drop{}): True{}
    case _: False{}

def disconnect_drop_ok() -> Bool:
  +st = session_fail(session_with_client(Cl.init("me", "irc.example"), "#t"), "lost")
  disconnect_drop.got(session_autoreconnect(st))

# G6 live law fixtures: an online session on #a, before and after a live CAP
# ACK. Self-JOIN activates the channel, so the composer target is #a.
def live_reg_fixture() -> Session:
  st_of_chunk(step_on_chunk_ms(session_online(session0("me", "s", "#a")), Fr.string_to_octets(":me!u@h JOIN #a\r\n"), 0))

def live_reg_tagged() -> Session:
  st_of_chunk(step_on_chunk_ms(live_reg_fixture(), Fr.string_to_octets(":s CAP me ACK :message-tags\r\n"), 0))

def live_reg_keyed(+st: Session, +text: String) -> Session:
  st_of_keys(step_keys(st, keys_of(text, False{}, 0, 0, 0, 0, 0, 0, 0)))

def live_reg_tags(reg: CapNotify.Reg) -> Bool:
  match reg:
    case CapNotify.Reg{+caps, _}: CapNotify.tags_ok(caps)

def live_tick_text.got(pair: Session & List<&2, String>) -> String:
  match pair:
    case (_, +xs): String.concat(xs)

def live_tick_text(+st: Session, +now_ms: U32) -> String:
  live_tick_text.got(session_tick_typing(st, now_ms))

def live_tick_st(pair: Session & List<&2, String>) -> Session:
  match pair:
    case (+st, _): st

def live_tick_bounded(pair: Session & List<&2, String>) -> Bool:
  match pair:
    case (_, +xs): CapNotify.outs_bounded(xs)

# Live CAP lines update the stored registration: quiet at reg0, enabled
# after a live ACK, hostile lines shut, endpoint change resets, and a
# registered '*' line leaves caps unchanged.
def live_reg_ok() -> Bool:
  +fresh = live_reg_fixture()
  +tagged = live_reg_tagged()
  +spoof = st_of_chunk(step_on_chunk_ms(fresh, Fr.string_to_octets(":alice!u@h CAP me ACK :message-tags\r\n"), 0))
  +moved = st_of_keys(step_enter(tagged, "/connect other.example 6667"))
  +welcomed = st_of_chunk(step_on_chunk_ms(fresh, Fr.string_to_octets(":s 001 me :welcome\r\n"), 0))
  +star_reg = st_of_chunk(step_on_chunk_ms(welcomed, Fr.string_to_octets(":s CAP * ACK :message-tags\r\n"), 0))
  Bool.not(live_reg_tags(session_reg(fresh)))
    && String.is_empty(live_tick_text(live_reg_keyed(fresh, "hi"), 1000))
    && live_reg_tags(session_reg(tagged))
    && String.eq(live_tick_text(live_reg_keyed(tagged, "hi"), 1000), "@+typing=active TAGMSG #a")
    && Bool.not(live_reg_tags(session_reg(spoof)))
    && Bool.not(live_reg_tags(session_reg(moved)))
    && String.eq(CapNotify.reg_target(session_reg(moved)), "")
    && live_reg_tags(session_reg(tagged))
    && JoinPlan.welcomed(session_plan(welcomed))
    && Bool.not(live_reg_tags(session_reg(star_reg)))

# Live outbound typing runs active, single done, quiet; stale ticks stay
# quiet and preserve the span; offline ticks reset; at most one wire per tick.
def live_tick_ok.cleared(+t2: Session, p3: Session & List<&2, String>) -> Bool:
  match p3:
    case (+stale, +xs):
      String.eq(live_tick_text(t2, 1100), "@+typing=done TAGMSG #a")
        && String.is_empty(live_tick_text(live_tick_st(session_tick_typing(t2, 1100)), 1200))
        && String.is_empty(String.concat(xs))
        && String.eq(live_tick_text(live_reg_keyed(stale, ""), 2000), "@+typing=done TAGMSG #a")

def live_tick_ok() -> Bool:
  +t1 = live_tick_st(session_tick_typing(live_reg_keyed(live_reg_tagged(), "hi"), 1000))
  String.eq(live_tick_text(live_reg_keyed(live_reg_tagged(), "hi"), 1000), "@+typing=active TAGMSG #a")
    && live_tick_ok.cleared(live_reg_keyed(t1, ""), session_tick_typing(t1, 999))
    && String.is_empty(live_tick_text(session_fail(live_reg_tagged(), "x"), 2000))
    && live_tick_bounded(session_tick_typing(live_reg_keyed(live_reg_tagged(), "hi"), 1000))
    && live_tick_bounded(session_tick_typing(live_reg_keyed(live_reg_tagged(), ""), 1000))

# Typing target comparison follows the negotiated Session CASEMAPPING (the
# cards/message `_cm` threading through Cl.buf_eq_cm): under ascii, a[b and
# a{b are distinct queries, so an alias-focus change emits done(old exact
# target) then active(new exact target) instead of staying quiet and silently
# retargeting; same-target ticks stay rate-limited with the span preserved.
def typing_cm_ascii_iso() -> Isupport.State:
  Isupport.apply_line(Isupport.defaults(), ":s 005 me CASEMAPPING=ascii :are supported")

def typing_cm_client() -> Cl.Client:
  Cl.Client{"me", "s", Cl.server_buf() <> Cl.empty_buf("a[b", False{}) <> Cl.empty_buf("a{b", False{}) <> Nil{}, 1n, "", Cl.settings0(), Cl.AuthIdle{}, 0n, False{}}

def typing_cm_tagged() -> Session:
  st_of_chunk(step_on_chunk_ms(session_online(session_with_client(typing_cm_client(), "#a")), Fr.string_to_octets(":s CAP me ACK :message-tags\r\n"), 0))

def typing_cm_keyed(+st: Session, +text: String) -> Session:
  st_of_keys(step_keys(st, keys_of(text, False{}, 0, 0, 0, 0, 0, 0, 0)))

def typing_cm_focus(+st: Session, +i: Nat) -> Session:
  session_set_client(st, Cl.set_active(session_cl(st), i))

def live_tick_cm_alias_ok() -> Bool:
  +base = typing_cm_focus(session_set_iso(typing_cm_tagged(), typing_cm_ascii_iso()), 1n)
  +k1 = typing_cm_keyed(base, "hi")
  +t1 = live_tick_st(session_tick_typing(k1, 1000))
  +moved = typing_cm_focus(t1, 2n)
  +t2 = live_tick_st(session_tick_typing(moved, 1100))
  String.eq(session_cm(base), "ascii")
    && String.eq(Cl.active_buf_name(session_cl(k1)), "a[b")
    && String.eq(live_tick_text(k1, 1000), "@+typing=active TAGMSG a[b")
    && String.eq(Cl.active_buf_name(session_cl(moved)), "a{b")
    && String.eq(live_tick_text(moved, 1100), "@+typing=done TAGMSG a[b")
    && String.eq(live_tick_text(t2, 1200), "@+typing=active TAGMSG a{b")

def live_tick_cm_throttle_ok() -> Bool:
  +base = typing_cm_focus(session_set_iso(typing_cm_tagged(), typing_cm_ascii_iso()), 1n)
  +k1 = typing_cm_keyed(base, "hi")
  +t1 = live_tick_st(session_tick_typing(k1, 1000))
  String.eq(live_tick_text(k1, 1000), "@+typing=active TAGMSG a[b")
    && String.is_empty(live_tick_text(t1, 1100))
    && String.eq(CapNotify.reg_target(session_reg(live_tick_st(session_tick_typing(t1, 1100)))), "a[b")

def live_cont_text(cmd: NetCmd) -> String:
  match cmd:
    case Cont{+outs}: String.join(outs, "|")
    case _: "other"

def live_count_end.add(hit: Bool, rest: Nat) -> Nat:
  match hit:
    case True{}: Nat.add(1n, rest)
    case False{}: rest

def live_count_end.go(fuel: Nat, xs: List<&2, String>) -> Nat:
  match fuel:
    case 0n: 0n
    case 1n+p:
      match xs:
        case Nil{}: 0n
        case Con{+h, t}: live_count_end.add(String.eq(h, "CAP END"), live_count_end.go(p, t))

def live_count_end(+xs: List<&2, String>) -> Nat:
  live_count_end.go(List.length(&2, String, xs), xs)

def live_chunk_outs.got(pair: Session & List<&2, String>) -> List<&2, String>:
  match pair:
    case (_, +xs): xs

def live_chunk_outs(+st: Session, +text: String) -> List<&2, String>:
  live_chunk_outs.got(step_on_chunk_ms(st, Fr.string_to_octets(text), 0))

# The frame merge appends the typing wire to Cont, leaves other commands
# alone, and the live path keeps a single CAP-END owner (exactly one from a
# SASL exchange, none from a chathistory ACK).
def live_merge_ok() -> Bool:
  +line: String = "@+typing=active TAGMSG #a"
  +sasl = session_online(session_with_client_at(Cl.client_set_sasl(Cl.init("me", "s"), "user", "pass"), "#a", Transport.PLAIN_PORT()))
  +outs = live_chunk_outs(sasl, ":s CAP me LS :sasl message-tags\r\n:s CAP me ACK :sasl\r\nAUTHENTICATE +\r\n:s 903 me :ok\r\n")
  String.eq(live_cont_text(merge_typing_outs(Cont{"PRIVMSG #a :hi" <> Nil{}}, line <> Nil{})), "PRIVMSG #a :hi|@+typing=active TAGMSG #a")
    && String.eq(show_netcmd(merge_typing_outs(Dial{"h", 6697, 0, "me"}, line <> Nil{})), "dial:h:6697")
    && Nat.is_eq(live_count_end(outs), 1n)
    && Nat.is_eq(live_count_end(live_chunk_outs(live_reg_fixture(), ":s CAP me ACK :draft/chathistory\r\n")), 0n)
