# IRCv3 SASL PLAIN. Only a parsed control event in its expected phase can
# produce credentials. The session keeps phase across receive chunks.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./endpoint.bend as Endpoint
import ./base64.bend as B64
import ./cap_notify.bend as CapNotify

type Notice is Data:
  Quiet{}
  Started{}
  Succeeded{}
  Failed{}
  Rejected{}
  Fallback{}
  NickProbing{}
  NickStarted{}
  NickSucceeded{}
  NickFailed{}

type Reply is Data:
  Reply{phase: Cl.AuthPhase, outs: List<&2, String>, notice: Notice}

def unchanged(phase: Cl.AuthPhase) -> Reply:
  Reply{phase, Nil{}, Quiet{}}

def step.hold.spot(phase: Cl.AuthPhase) -> Cl.AuthHold:
  match phase:
    case Cl.AuthChallenge{}: Cl.HoldChallenge{}
    case Cl.AuthResult{}: Cl.HoldResult{}
    case _: Cl.HoldCap{}

def step.hold(hold: Bool, phase: Cl.AuthPhase) -> Reply:
  match hold:
    case True{}: unchanged(Cl.AuthHeld{step.hold.spot(phase)})
    case False{}: unchanged(phase)

def step.cap(hold: Bool, e: Irc.SaslEvent) -> Reply:
  match e:
    case Irc.SaslAck{}:
      Reply{Cl.AuthChallenge{}, "AUTHENTICATE PLAIN" <> Nil{}, Started{}}
    case Irc.SaslNak{}:
      Reply{Cl.AuthDone{}, CapNotify.cap_end_for(Cl.AuthCap{}, Cl.AuthDone{}), Rejected{}}
    case Irc.SaslRegistered{}: step.hold(hold, Cl.AuthCap{})
    case _:
      unchanged(Cl.AuthCap{})

def step.challenge(hold: Bool, e: Irc.SaslEvent, +user: String, +pass: String) -> Reply:
  match e:
    case Irc.SaslPlus{}:
      Reply{Cl.AuthResult{}, B64.authenticate_chunks(B64.sasl_plain(user, pass)), Quiet{}}
    case Irc.SaslFailure{}:
      Reply{Cl.AuthDone{}, CapNotify.cap_end_for(Cl.AuthChallenge{}, Cl.AuthDone{}), Failed{}}
    case Irc.SaslRegistered{}: step.hold(hold, Cl.AuthChallenge{})
    case _:
      unchanged(Cl.AuthChallenge{})

def step.result(hold: Bool, e: Irc.SaslEvent) -> Reply:
  match e:
    case Irc.SaslSuccess{}:
      Reply{Cl.AuthDone{}, CapNotify.cap_end_for(Cl.AuthResult{}, Cl.AuthDone{}), Succeeded{}}
    case Irc.SaslFailure{}:
      Reply{Cl.AuthDone{}, CapNotify.cap_end_for(Cl.AuthResult{}, Cl.AuthDone{}), Failed{}}
    case Irc.SaslRegistered{}: step.hold(hold, Cl.AuthResult{})
    case _:
      unchanged(Cl.AuthResult{})

def phase_same.cap(b: Cl.AuthPhase) -> Bool:
  match b:
    case Cl.AuthCap{}: True{}
    case _: False{}

def phase_same.challenge(b: Cl.AuthPhase) -> Bool:
  match b:
    case Cl.AuthChallenge{}: True{}
    case _: False{}

def phase_same.result(b: Cl.AuthPhase) -> Bool:
  match b:
    case Cl.AuthResult{}: True{}
    case _: False{}

def phase_same(a: Cl.AuthPhase, b: Cl.AuthPhase) -> Bool:
  match a:
    case Cl.AuthCap{}: phase_same.cap(b)
    case Cl.AuthChallenge{}: phase_same.challenge(b)
    case Cl.AuthResult{}: phase_same.result(b)
    case _: False{}

def step.held.pack(same: Bool, phase: Cl.AuthPhase, hold: Cl.AuthHold, outs: List<&2, String>, notice: Notice) -> Reply:
  match same:
    case True{}: Reply{Cl.AuthHeld{hold}, outs, notice}
    case False{}: Reply{phase, outs, notice}

def step.held.got(before: Cl.AuthPhase, hold: Cl.AuthHold, reply: Reply) -> Reply:
  match reply:
    case Reply{+phase, outs, notice}:
      step.held.pack(phase_same(before, phase), phase, hold, outs, notice)

def step.held(resume: Cl.AuthHold, e: Irc.SaslEvent, +user: String, +pass: String) -> Reply:
  match resume:
    case Cl.HoldCap{}: step.held.got(Cl.AuthCap{}, Cl.HoldCap{}, step.cap(False{}, e))
    case Cl.HoldChallenge{}: step.held.got(Cl.AuthChallenge{}, Cl.HoldChallenge{}, step.challenge(False{}, e, user, pass))
    case Cl.HoldResult{}: step.held.got(Cl.AuthResult{}, Cl.HoldResult{}, step.result(False{}, e))

def step(phase: Cl.AuthPhase, e: Irc.SaslEvent, +user: String, +pass: String) -> Reply:
  match phase:
    case Cl.AuthIdle{}: unchanged(Cl.AuthIdle{})
    case Cl.AuthCap{}: step.cap(True{}, e)
    case Cl.AuthChallenge{}: step.challenge(True{}, e, user, pass)
    case Cl.AuthResult{}: step.result(True{}, e)
    case Cl.AuthDone{}: unchanged(Cl.AuthDone{})
    case Cl.AuthHeld{resume}: step.held(resume, e, user, pass)
    case Cl.AuthNickWait{}: unchanged(Cl.AuthNickWait{})
    case Cl.AuthNickProbe{}: unchanged(Cl.AuthNickProbe{})
    case Cl.AuthNickResult{}: unchanged(Cl.AuthNickResult{})
    case Cl.AuthProfile{p, c, s}: unchanged(Cl.AuthProfile{p, c, s})

# NickServ is an explicit profile, never a prompt/text heuristic. The prefix
# names exactly one nick, user and host; wildcard masks and wire delimiters fail.
def word_clean(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}: U32.is_gt(Char.to_u32(h), 32) && Bool.not(Char.is_eq(h, Chr{127})) && word_clean(t)

def text_clean(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}: U32.is_ge(Char.to_u32(h), 32) && Bool.not(Char.is_eq(h, Chr{127})) && text_clean(t)

def secret_clean(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}: Bool.not(Char.is_eq(h, Chr{0}) || Char.is_eq(h, Chr{10}) || Char.is_eq(h, Chr{13})) && secret_clean(t)

def valid_prefix.host(parts: List<&2, String>) -> Bool:
  match parts:
    case Con{+user, Con{+host, Nil{}}}:
      Bool.not(String.is_empty(user) || String.is_empty(host)) && word_clean(user) && word_clean(host)
    case _: False{}

def valid_prefix.parts(parts: List<&2, String>) -> Bool:
  match parts:
    case Con{+nick, Con{userhost, Nil{}}}:
      Bool.not(String.is_empty(nick) || Irc.starts_channel(nick) || String.starts_with(nick, ":") || String.contains(nick, ",") || String.contains(nick, "@"))
        && word_clean(nick) && valid_prefix.host(String.split(userhost, Chr{64}))
    case _: False{}

def valid_prefix(+prefix: String) -> Bool:
  Bool.not(String.contains(prefix, "*")) && valid_prefix.parts(String.split(prefix, Chr{33}))

def valid_config(mode: Cl.AuthMode, +prefix: String, +success: String) -> Bool:
  match mode:
    case Cl.SaslOnly{}: True{}
    case _: valid_prefix(prefix) && Bool.not(String.is_empty(success)) && text_clean(success)

def credentials_valid(+cl: Cl.Client) -> Bool:
  Cl.client_has_credentials(cl) && secret_clean(Cl.client_sasl_user(cl)) && secret_clean(Cl.client_sasl_pass(cl))

# Credential scope is exact host spelling plus live port equality (AGENTS).
def binding_port.config(config: Cl.AuthConfig) -> U32:
  match config:
    case Cl.AuthDisabled{}: 0
    case Cl.AuthConfig{_, _, port, _, _}: port

def binding_port(+cl: Cl.Client) -> U32:
  binding_port.config(Cl.client_auth_config(cl))

def endpoint_bound(+host: String, +port: U32, +cl: Cl.Client, +live_port: U32) -> Bool:
  String.eq(host, Cl.server_of(cl)) && U32.is_eq(port, live_port)
    && U32.is_gt(port, 0) && U32.is_le(port, 65535)

# A configured credential profile gates channel recovery, even when its current
# exchange fails. A past success must never stand in for this connection's one.
def join_required.config(config: Cl.AuthConfig, +cl: Cl.Client, +live_port: U32) -> Bool:
  match config:
    case Cl.AuthDisabled{}: False{}
    case Cl.AuthConfig{_, host, +port, _, _}:
      Cl.client_has_credentials(cl) && endpoint_bound(host, port, cl, live_port)

def join_required(+cl: Cl.Client, +live_port: U32) -> Bool:
  join_required.config(Cl.client_auth_config(cl), cl, live_port)

def identify_line(+cl: Cl.Client) -> String:
  "PRIVMSG " ++ Cl.client_auth_service(cl) ++ " :IDENTIFY " ++ Cl.client_sasl_user(cl) ++ " " ++ Cl.client_sasl_pass(cl)

def nick_start.fits(ok: Bool, line: String) -> Reply:
  match ok:
    case True{}: Reply{Cl.AuthNickResult{}, line <> Nil{}, NickStarted{}}
    case False{}: Reply{Cl.AuthDone{}, Nil{}, NickFailed{}}

def nick_start(+cl: Cl.Client) -> Reply:
  +line = identify_line(cl)
  nick_start.fits(word_clean(Cl.client_sasl_user(cl)) && word_clean(Cl.client_sasl_pass(cl)) && Irc.line_ok(line), line)

# Shared with CapNotify through Endpoint.server_source: empty prefixes fail
# closed. TLS/endpoint scope verifies the peer, not this name. A user prefix,
# URL, or another recipient still cannot advance control state.
def server_source(+prefix: String) -> Bool:
  Endpoint.server_source(prefix)

def server_control(+cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Bool:
  server_source(prefix) && Irc.ieq(Irc.proto_atom(Irc.msg_param(m, 0n)), Cl.nick_of(cl))

def trusted_notice(config: Cl.AuthConfig, +cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Bool:
  match config:
    case Cl.AuthDisabled{}: False{}
    case Cl.AuthConfig{_, _, _, wanted, _}:
      String.eq(prefix, wanted) && Irc.ieq(Irc.msg_command(m), "NOTICE")
        && Irc.ieq(Irc.proto_atom(Irc.msg_param(m, 0n)), Cl.nick_of(cl))

def nick_confirm.config(config: Cl.AuthConfig, +cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Bool:
  match config:
    case Cl.AuthDisabled{}: False{}
    case Cl.AuthConfig{mode, host, port, wanted, +success}:
      trusted_notice(Cl.AuthConfig{mode, host, port, wanted, success}, cl, prefix, m) && String.eq(Irc.sanitize_in(Irc.msg_param(m, 1n)), success)

def nick_confirm(ok: Bool) -> Reply:
  match ok:
    case True{}: Reply{Cl.AuthDone{}, Nil{}, NickSucceeded{}}
    case False{}: unchanged(Cl.AuthNickResult{})

def nick_probe.fits(ok: Bool, line: String) -> Reply:
  match ok:
    case True{}: Reply{Cl.AuthNickProbe{}, line <> Nil{}, NickProbing{}}
    case False{}: Reply{Cl.AuthDone{}, Nil{}, NickFailed{}}

def nick_probe(+cl: Cl.Client) -> Reply:
  +line = "PRIVMSG " ++ Cl.client_auth_service(cl) ++ " :HELP"
  nick_probe.fits(Irc.line_ok(line), line)

def nick_registered(ok: Bool, +cl: Cl.Client) -> Reply:
  match ok:
    case True{}: nick_probe(cl)
    case False{}: unchanged(Cl.AuthNickWait{})

def nick_probed(ok: Bool, +cl: Cl.Client) -> Reply:
  match ok:
    case True{}: nick_start(cl)
    case False{}: unchanged(Cl.AuthNickProbe{})

# AUTHENTICATE + commonly omits a prefix (connection origin). Other SASL
# controls use the shared fail-closed server_source. Numerics must name our
# current nickname; CAP also allows its established broadcast recipient '*'.
def sasl_trusted(event: Irc.SaslEvent, +cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Bool:
  match event:
    case Irc.SaslPlus{}: String.is_empty(prefix) || server_source(prefix)
    case Irc.SaslAck{}: server_source(prefix) && (Irc.ieq(Irc.proto_atom(Irc.msg_param(m, 0n)), Cl.nick_of(cl)) || String.eq(Irc.proto_atom(Irc.msg_param(m, 0n)), "*"))
    case Irc.SaslNak{}: server_source(prefix) && (Irc.ieq(Irc.proto_atom(Irc.msg_param(m, 0n)), Cl.nick_of(cl)) || String.eq(Irc.proto_atom(Irc.msg_param(m, 0n)), "*"))
    case Irc.SaslOther{}: False{}
    case _: server_control(cl, prefix, m)

def sasl_mode.cap(mode: Cl.AuthMode, +event: Irc.SaslEvent, +cl: Cl.Client) -> Reply:
  match mode event:
    case Cl.SaslNickServ{} Irc.SaslNak{}: Reply{Cl.AuthNickWait{}, CapNotify.cap_end_for(Cl.AuthCap{}, Cl.AuthNickWait{}), Fallback{}}
    case _ _: step(Cl.AuthCap{}, event, Cl.client_sasl_user(cl), Cl.client_sasl_pass(cl))

def sasl_mode(phase: Cl.AuthPhase, mode: Cl.AuthMode, event: Irc.SaslEvent, +cl: Cl.Client) -> Reply:
  match phase:
    case Cl.AuthCap{}: sasl_mode.cap(mode, event, cl)
    case _: step(phase, event, Cl.client_sasl_user(cl), Cl.client_sasl_pass(cl))

def sasl_checked(ok: Bool, phase: Cl.AuthPhase, mode: Cl.AuthMode, event: Irc.SaslEvent, +cl: Cl.Client) -> Reply:
  match ok:
    case False{}: unchanged(phase)
    case True{}: sasl_mode(phase, mode, event, cl)

def cap_unavailable.mode(mode: Cl.AuthMode, +cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Bool:
  match mode:
    case Cl.SaslNickServ{}: U32.is_eq(Irc.msg_num(m), 421) && Irc.ieq(Irc.msg_param(m, 1n), "CAP") && server_control(cl, prefix, m)
    case _: False{}

def cap_unavailable(phase: Cl.AuthPhase, mode: Cl.AuthMode, +cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Bool:
  match phase:
    case Cl.AuthCap{}: cap_unavailable.mode(mode, cl, prefix, m)
    case _: False{}

def step_for.sasl(unavailable: Bool, phase: Cl.AuthPhase, mode: Cl.AuthMode, +cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Reply:
  match unavailable:
    case True{}: Reply{Cl.AuthNickWait{}, CapNotify.cap_end_for(Cl.AuthCap{}, Cl.AuthNickWait{}), Fallback{}}
    case False{}:
      +event = Irc.sasl_event(m)
      sasl_checked(sasl_trusted(event, cl, prefix, m), phase, mode, event, cl)

def step_for.phase(+phase: Cl.AuthPhase, +config: Cl.AuthConfig, +mode: Cl.AuthMode, +cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Reply:
  match phase:
    case Cl.AuthNickWait{}: nick_registered(U32.is_eq(Irc.msg_num(m), 1) && server_control(cl, prefix, m), cl)
    case Cl.AuthNickProbe{}: nick_probed(trusted_notice(config, cl, prefix, m), cl)
    case Cl.AuthNickResult{}: nick_confirm(nick_confirm.config(config, cl, prefix, m))
    case _: step_for.sasl(cap_unavailable(phase, mode, cl, prefix, m), phase, mode, cl, prefix, m)

def step_for.allowed(ok: Bool, +cl: Cl.Client, config: Cl.AuthConfig, mode: Cl.AuthMode, prefix: String, m: Irc.Message) -> Reply:
  match ok:
    case False{}: unchanged(Cl.get_auth(cl))
    case True{}: step_for.phase(Cl.get_auth(cl), config, mode, cl, prefix, m)

def step_for.config(config: Cl.AuthConfig, +cl: Cl.Client, +live_port: U32, prefix: String, m: Irc.Message) -> Reply:
  match config:
    case Cl.AuthDisabled{}: unchanged(Cl.get_auth(cl))
    case Cl.AuthConfig{+mode, +host, +port, +wanted, +success}:
      step_for.allowed(endpoint_bound(host, port, cl, live_port)
        && valid_config(mode, wanted, success) && credentials_valid(cl), cl, Cl.AuthConfig{mode, host, port, wanted, success}, mode, prefix, m)

def step_for.parsed(+cl: Cl.Client, +live_port: U32, prefix: String, m: Maybe<&2, Irc.Message>) -> Reply:
  match m:
    case None{}: unchanged(Cl.get_auth(cl))
    case Some{msg}: step_for.config(Cl.client_auth_config(cl), cl, live_port, prefix, msg)

def step_for(+cl: Cl.Client, +line: String, +live_port: U32) -> Reply:
  step_for.parsed(cl, live_port, Irc.source_prefix(line), Irc.parse(line))

# Suppress only the trusted identity probe and exact confirmation controls.
# Submit owns the shared automatic/manual credential self-echo classifier.
def consume_line.phase(phase: Cl.AuthPhase, +cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Bool:
  match phase:
    case Cl.AuthNickProbe{}: trusted_notice(Cl.client_auth_config(cl), cl, prefix, m)
    case Cl.AuthNickResult{}: nick_confirm.config(Cl.client_auth_config(cl), cl, prefix, m)
    case _: False{}

def consume_line.parsed(+cl: Cl.Client, +prefix: String, m: Maybe<&2, Irc.Message>) -> Bool:
  match m:
    case None{}: False{}
    case Some{msg}: consume_line.phase(Cl.get_auth(cl), cl, prefix, msg)

def consume_line(+cl: Cl.Client, +line: String) -> Bool:
  consume_line.parsed(cl, Irc.source_prefix(line), Irc.parse(line))

def log_notice(+cl: Cl.Client, notice: Notice) -> Cl.Client:
  match notice:
    case Quiet{}: cl
    case Started{}: Cl.diagnostic_notice(Cl.client_log(cl, 0n, Cl.System{}, "SASL: authenticating with PLAIN..."), Cl.System{}, "SASL: authenticating with PLAIN...")
    case Succeeded{}: Cl.diagnostic_notice(Cl.client_log(cl, 0n, Cl.System{}, "SASL: authentication successful"), Cl.System{}, "SASL: authentication successful")
    case Failed{}: Cl.client_log(cl, 0n, Cl.Error{}, "SASL: authentication failed")
    case Rejected{}: Cl.client_log(cl, 0n, Cl.Error{}, "SASL: capability rejected")
    case Fallback{}: Cl.client_log(cl, 0n, Cl.System{}, "SASL: unavailable; waiting for NickServ")
    case NickProbing{}: Cl.client_log(cl, 0n, Cl.System{}, "NickServ: checking service identity...")
    case NickStarted{}: Cl.client_log(cl, 0n, Cl.System{}, "NickServ: identifying...")
    case NickSucceeded{}: Cl.diagnostic_notice(Cl.client_log(cl, 0n, Cl.System{}, "NickServ: authentication successful"), Cl.System{}, "NickServ: authentication successful")
    case NickFailed{}: Cl.client_log(cl, 0n, Cl.Error{}, "NickServ: invalid credential or message length")

def notice_success(notice: Notice) -> Bool:
  match notice:
    case Succeeded{}: True{}
    case NickSucceeded{}: True{}
    case _: False{}

def apply_reply.success(ok: Bool, +cl: Cl.Client, notice: Notice) -> Cl.Client:
  match ok:
    case False{}: log_notice(cl, notice)
    case True{}: log_notice(Cl.advance_auth_success(cl), notice)

def apply_reply(+cl: Cl.Client, phase: Cl.AuthPhase, +notice: Notice) -> Cl.Client:
  apply_reply.success(notice_success(notice), Cl.set_auth(cl, phase), notice)
