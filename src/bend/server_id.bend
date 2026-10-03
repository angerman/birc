# SPDX-License-Identifier: Apache-2.0
# Pure multiserver policy: explicit ServerId + generation routing with
# per-server isolation of credentials, history, preferences, buffers, and
# reconnect intent. Adapter-only: wraps existing Session NetCmd/UiMsg guards
# and shares the IPv6 scope spelling; changes no shared Client/Buffer/Session
# types. The integrator threads RoutedCmd/RoutedMsg through Net/Actor and
# partitions per-server state; each partition keeps today's single-server
# bounds (16 buffers, bounded plans, private history files).
import Base
import ./irc.bend as Irc
import ./session.bend as Sess
import ./ipv6.bend as V6

# At most four simultaneous servers bound actor/channel fan-out. A next id at
# the bound is invalid; callers check valid, never wrap around.
def MAX_SERVERS() -> Nat:
  4n

type ServerId is Data:
  ServerId{id: Nat}

def first() -> ServerId:
  ServerId{0n}

def valid(+id: ServerId) -> Bool:
  match id:
    case ServerId{+n}: Nat.is_lt(n, MAX_SERVERS())

def slot(+id: ServerId) -> U32:
  match id:
    case ServerId{+n}: U32.from_nat(n)

def eq(+a: ServerId, +b: ServerId) -> Bool:
  match a:
    case ServerId{+x}:
      match b:
        case ServerId{+y}: Nat.is_eq(x, y)

def next(+id: ServerId) -> ServerId:
  match id:
    case ServerId{+n}: ServerId{Nat.add(n, 1n)}

# ---- generations ---------------------------------------------------------------
# Generations compare by equality only, like Sess.event_current. Wrap-around
# past 2^32 dials is accepted, matching existing single-server semantics.

def bump(+g: U32) -> U32:
  U32.add(g, 1)

def is_stale(+got: U32, +cur: U32) -> Bool:
  Bool.not(U32.is_eq(got, cur))

type Routed is Data:
  Routed{server: ServerId, gen: U32}

# Every routing/admission check fails closed on invalid ids: the carried id
# and the expected id must both be valid before comparison, so ID4+ and
# out-of-range slots never route even when they compare equal.
def current_id(+s: ServerId, +server: ServerId) -> Bool:
  valid(s) && valid(server) && eq(s, server)

def route_current(+r: Routed, +server: ServerId, +gen: U32) -> Bool:
  match r:
    case Routed{+s, +g}: current_id(s, server) && U32.is_eq(g, gen)

# ---- command / event routing ------------------------------------------------------
# Server identity gates every command. Generation gates only the variants that
# carry one; Cont/Drop/OpenUrl apply to the server's current connection, as
# today. Events compose the existing Session generation guards unchanged.

type RoutedCmd is Data:
  RoutedCmd{server: ServerId, cmd: Sess.NetCmd}

def cmd_gen_ok(cmd: Sess.NetCmd, +gen: U32) -> Bool:
  match cmd:
    case Sess.Dial{_, _, +g, _}: U32.is_eq(g, gen)
    case Sess.Pump{+g}: U32.is_eq(g, gen)
    case Sess.Begin{+g}: U32.is_eq(g, gen)
    case _: True{}

def cmd_current(+rc: RoutedCmd, +server: ServerId, +gen: U32) -> Bool:
  match rc:
    case RoutedCmd{+s, +cmd}: current_id(s, server) && cmd_gen_ok(cmd, gen)

type RoutedMsg is Data:
  RoutedMsg{server: ServerId, msg: Sess.UiMsg}

def evt_current(+rm: RoutedMsg, +server: ServerId, +gen: U32) -> Bool:
  match rm:
    case RoutedMsg{+s, +msg}: current_id(s, server) && Sess.event_current(msg, gen)

# Only the owning server's current writer acknowledges shutdown; reader EOF
# and other servers' completions cannot, mirroring Sess.writer_done_current.
def writer_done_current(+rm: RoutedMsg, +server: ServerId, +gen: U32) -> Bool:
  match rm:
    case RoutedMsg{+s, +msg}: current_id(s, server) && Sess.writer_done_current(msg, gen)

def dial_for(+server: ServerId, +host: String, +port: U32, +gen: U32, +nick: String) -> RoutedCmd:
  RoutedCmd{server, Sess.Dial{host, port, gen, nick}}

def cont_for(+server: ServerId, +outs: List<&2, String>) -> RoutedCmd:
  RoutedCmd{server, Sess.Cont{outs}}

def drop_for(+server: ServerId) -> RoutedCmd:
  RoutedCmd{server, Sess.Drop{}}

def begin_for(+server: ServerId, +gen: U32) -> RoutedCmd:
  RoutedCmd{server, Sess.Begin{gen}}

# ---- endpoint scopes ---------------------------------------------------------------
# One scope key isolates credentials, history, preferences, buffers, and
# reconnect intent. Host spelling (case, root dot, literal text) is preserved.
# History admission compares case-insensitively like the archive reader;
# credential and reconnect transitions compare exactly, never normalized.

type Scope is Data:
  Scope{host: String, port: U32, v6: Bool}

def bool_eq(+a: Bool, +b: Bool) -> Bool:
  match a:
    case True{}: b
    case False{}: Bool.not(b)

def host_of(+s: Scope) -> String:
  match s:
    case Scope{+host, _, _}: host

def port_of(+s: Scope) -> U32:
  match s:
    case Scope{_, +port, _}: port

def v6_of(+s: Scope) -> Bool:
  match s:
    case Scope{_, _, +v6}: v6

def same_scope(+a: Scope, +b: Scope) -> Bool:
  U32.is_eq(port_of(a), port_of(b)) && bool_eq(v6_of(a), v6_of(b)) && Irc.ieq(host_of(a), host_of(b))

def scope_changed(+a: Scope, +b: Scope) -> Bool:
  Bool.not(same_scope(a, b))

def scope_key.go(v6: Bool, +host: String, +port: U32) -> String:
  match v6:
    case True{}: V6.scope_key(host, port, V6.V6{})
    case False{}: V6.scope_key(host, port, V6.V4{})

# Single source for scope text is the IPv6 formatter: V4 matches net.endpoint
# ("host:port"); V6 brackets the literal ("[::1]:6697").
def scope_key(+s: Scope) -> String:
  scope_key.go(v6_of(s), host_of(s), port_of(s))

# Credential binding mirrors Auth.step_for.config: exact host spelling plus a
# bounded config port. Any scope change permanently clears credentials.
def credential_scope_ok(+cfg_host: String, +cfg_port: U32, +host: String, +port: U32) -> Bool:
  String.eq(cfg_host, host) && U32.is_eq(cfg_port, port) && U32.is_ge(cfg_port, 1) && U32.is_le(cfg_port, 65535)

# History admission mirrors Hist.parse_line_for.valid: the stored BIRC2 server
# field must match this server's scope case-insensitively.
def history_admits(+stored: String, +s: Scope) -> Bool:
  Irc.ieq(stored, scope_key(s))

# ---- reconnect intent -----------------------------------------------------------------
# Intent is bound to one server and generation. Auto-redial additionally
# requires the same endpoint; a scope or generation change drops the intent.

type Intent is Data:
  Intent{server: ServerId, gen: U32, host: String, port: U32, v6: Bool}

def intent_current(+i: Intent, +server: ServerId, +gen: U32) -> Bool:
  match i:
    case Intent{+s, +g, _, _, _}: current_id(s, server) && U32.is_eq(g, gen)

def intent_scope(+i: Intent) -> Scope:
  match i:
    case Intent{_, _, +host, +port, +v6}: Scope{host, port, v6}

# Reconnect retains the Auth profile, which credential_scope_ok binds to exact
# host spelling: a case-folded match here would keep secrets across a
# credential-scope change, so the endpoint comparison is exact.
def endpoint_exact(+a: Scope, +b: Scope) -> Bool:
  U32.is_eq(port_of(a), port_of(b)) && bool_eq(v6_of(a), v6_of(b)) && String.eq(host_of(a), host_of(b))

def intent_same_endpoint(+i: Intent, +s: Scope) -> Bool:
  endpoint_exact(intent_scope(i), s)

def reconnect_ok(+i: Intent, +server: ServerId, +gen: U32, +s: Scope) -> Bool:
  intent_current(i, server, gen) && intent_same_endpoint(i, s)

# ---- proof-facing predicates ---------------------------------------------------------------

def routing_ok() -> Bool:
  route_current(Routed{ServerId{1n}, 7}, ServerId{1n}, 7)
    && Bool.not(route_current(Routed{ServerId{1n}, 7}, ServerId{2n}, 7))
    && Bool.not(route_current(Routed{ServerId{1n}, 7}, ServerId{1n}, 8))
    && cmd_current(dial_for(ServerId{0n}, "h", 6697, 3, "me"), ServerId{0n}, 3)
    && Bool.not(cmd_current(dial_for(ServerId{0n}, "h", 6697, 3, "me"), ServerId{0n}, 4))
    && Bool.not(cmd_current(dial_for(ServerId{0n}, "h", 6697, 3, "me"), ServerId{1n}, 3))
    && route_current(Routed{ServerId{3n}, 9}, ServerId{3n}, 9)
    && Bool.not(route_current(Routed{ServerId{3n}, 9}, ServerId{3n}, 10))
    && Bool.not(route_current(Routed{ServerId{4n}, 7}, ServerId{4n}, 7))
    && Bool.not(cmd_current(dial_for(ServerId{4n}, "h", 6697, 3, "me"), ServerId{4n}, 3))

def isolation_ok() -> Bool:
  same_scope(Scope{"irc.example", 6697, False{}}, Scope{"IRC.Example", 6697, False{}})
    && Bool.not(same_scope(Scope{"irc.example", 6697, False{}}, Scope{"irc.example", 7000, False{}}))
    && Bool.not(same_scope(Scope{"irc.example", 6697, False{}}, Scope{"other.example", 6697, False{}}))
    && credential_scope_ok("h", 6697, "h", 6697)
    && Bool.not(credential_scope_ok("h", 6697, "H", 6697))
    && history_admits("IRC.Example:6697", Scope{"irc.example", 6697, False{}})
    && Bool.not(history_admits("irc.example:7000", Scope{"irc.example", 6697, False{}}))
    && reconnect_ok(Intent{ServerId{0n}, 4, "h", 6697, False{}}, ServerId{0n}, 4, Scope{"h", 6697, False{}})
    && Bool.not(reconnect_ok(Intent{ServerId{0n}, 4, "h", 6697, False{}}, ServerId{0n}, 4, Scope{"H", 6697, False{}}))

def generation_ok() -> Bool:
  U32.is_eq(bump(7), 8) && is_stale(7, 8) && Bool.not(is_stale(8, 8))
    && valid(first()) && valid(next(next(next(first())))) && Bool.not(valid(next(next(next(next(first()))))))
    && eq(ServerId{3n}, ServerId{3n}) && Bool.not(eq(ServerId{0n}, ServerId{Nat.add(4294967295n, 1n)}))
