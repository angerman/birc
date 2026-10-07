# CLI flags for birc (IO.args). Pure. app.bend runs parse; tests assert it.
import Base
import ./buffer.bend as Cl
import ./auth.bend as Auth
import ./transport_policy.bend as Policy
import ./endpoint.bend as Ep
import ./channel_policy.bend as Channels

type AuthOptions is Data:
  AuthOptions{mode: Cl.AuthMode, prefix: String, success: String}

def auth_options0() -> AuthOptions:
  AuthOptions{Cl.SaslOnly{}, "", ""}

type Cfg is Data:
  Cfg{demo: Bool, frames: U32, host: String, port: U32, nick: String, chan: String, replay: String, sasl_user: String, sasl_pass: String, nick_explicit: Bool, auth: AuthOptions, tls: Bool, port_explicit: Bool, servers: List<&2, Ep.Endpoint>}

type Parsed is Data:
  Good{cfg: Cfg}
  Bad{msg: String}

type Num is Data:
  Num{ok: Bool, n: U32}

def cfg0() -> Cfg:
  Cfg{True{}, 0, "", Policy.TLS_PORT(), "birc", "#birc", "", "", "", False{}, auth_options0(), Policy.default_secure(), False{}, Nil{}}

def parse_u32.on(m: Maybe<&2, U32>) -> Num:
  match m:
    case None{}:
      Num{False{}, 0}
    case Some{n}:
      Num{True{}, n}

def parse_u32(+s: String) -> Num:
  parse_u32.on(U32.read(s))

def set_frames(+cfg: Cfg, n: U32) -> Cfg:
  match cfg:
    case Cfg{demo, _, +host, port, +nick, +chan, +replay, +su, +sp, explicit, auth, tls, port_explicit, +servers}:
      Cfg{demo, n, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, servers}

def set_host(+cfg: Cfg, +host: String) -> Cfg:
  match cfg:
    case Cfg{_, frames, _, port, +nick, +chan, +replay, +su, +sp, explicit, auth, tls, port_explicit, +servers}:
      Cfg{False{}, frames, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, servers}

def set_port(+cfg: Cfg, n: U32) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, _, +nick, +chan, +replay, +su, +sp, explicit, auth, tls, _, +servers}:
      Cfg{demo, frames, host, n, nick, chan, replay, su, sp, explicit, auth, tls, True{}, servers}

def set_nick(+cfg: Cfg, +nick: String) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, port, _, +chan, +replay, +su, +sp, _, auth, tls, port_explicit, +servers}:
      Cfg{demo, frames, host, port, nick, chan, replay, su, sp, True{}, auth, tls, port_explicit, servers}

def set_chan(+cfg: Cfg, +chan: String) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, port, +nick, _, +replay, +su, +sp, explicit, auth, tls, port_explicit, +servers}:
      Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, servers}

def set_replay(+cfg: Cfg, +replay: String) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, port, +nick, +chan, _, +su, +sp, explicit, auth, tls, port_explicit, +servers}:
      Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, servers}

def set_demo(+cfg: Cfg) -> Cfg:
  match cfg:
    case Cfg{_, frames, +host, port, +nick, +chan, +replay, +su, +sp, explicit, auth, tls, port_explicit, +servers}:
      Cfg{True{}, frames, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, servers}

def set_sasl_user(+cfg: Cfg, +user: String) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, port, +nick, +chan, +replay, _, +sp, explicit, auth, tls, port_explicit, +servers}:
      Cfg{demo, frames, host, port, nick, chan, replay, user, sp, explicit, auth, tls, port_explicit, servers}

def set_sasl_pass(+cfg: Cfg, +pass: String) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, port, +nick, +chan, +replay, +su, _, explicit, auth, tls, port_explicit, +servers}:
      Cfg{demo, frames, host, port, nick, chan, replay, su, pass, explicit, auth, tls, port_explicit, servers}

def set_auth(+cfg: Cfg, auth: AuthOptions) -> Cfg:
  match cfg:
    case Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, _, tls, port_explicit, +servers}:
      Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, servers}

def set_secure(+cfg: Cfg, tls: Bool) -> Cfg:
  match cfg:
    case Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, auth, _, port_explicit, +servers}:
      Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, servers}

# Extra multiserver endpoints (--server, repeatable). At most 3: the primary
# HOST plus extras must fit the 4 workspace slots.
def servers_full2(+xs: List<&2, Ep.Endpoint>) -> Bool:
  match xs:
    case Con{_, _}: True{}
    case _: False{}

def servers_full1(+xs: List<&2, Ep.Endpoint>) -> Bool:
  match xs:
    case Con{_, +t}: servers_full2(t)
    case _: False{}

def servers_full(+xs: List<&2, Ep.Endpoint>) -> Bool:
  match xs:
    case Con{_, +t}: servers_full1(t)
    case _: False{}

def add_server_endpoint(+cfg: Cfg, +ep: Ep.Endpoint) -> Cfg:
  match cfg:
    case Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, +servers}:
      Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, List.append(&2, Ep.Endpoint, servers, ep <> Nil{})}

# Resolve defaults once; a port never selects the transport.
def resolve_port(cfg: Cfg) -> Cfg:
  match cfg:
    case Cfg{demo, frames, host, port, nick, chan, replay, su, sp, explicit, auth, +tls, +port_explicit, +servers}:
      Cfg{demo, frames, host, Policy.default_port(tls, port_explicit, port), nick, chan, replay, su, sp, explicit, auth, tls, port_explicit, servers}

def auth_of(cfg: Cfg) -> AuthOptions:
  match cfg:
    case Cfg{_, _, _, _, _, _, _, _, _, _, auth, _, _, _}: auth

# Resolve once after the CLI/environment SASL user is known. Nicknames are
# values, not sentinels: explicit "birc" and "me" must remain unchanged.
def resolve_nick.pick(align: Bool, +nick: String, +user: String) -> String:
  match align:
    case True{}: user
    case False{}: nick

def resolve_nick(+nick: String, explicit: Bool, +user: String) -> String:
  resolve_nick.pick(Bool.not(explicit) && Bool.not(String.is_empty(user)), nick, user)

type Step is Data:
  Go{xs: List<&2, String>, cfg: Cfg}
  Mode{xs: List<&2, String>, cfg: Cfg, secure: Bool}
  Stop{got: Parsed}

def explicit_port(cfg: Cfg) -> Maybe<&2, U32>:
  match cfg:
    case Cfg{_, _, _, p, _, _, _, _, _, _, _, _, explicit, _}:
      Bool.pick(Maybe<&2, U32>, explicit, Some{p}, None{})

def args_port.selected(got: Maybe<&2, U32>, t: List<&2, String>, cfg: Cfg) -> Step:
  match got:
    case None{}: Stop{Bad{"birc: conflicting port values"}}
    case Some{n}: Go{t, set_port(cfg, n)}

def args_endpoint.port(inline: Maybe<&2, U32>, t: List<&2, String>, +cfg: Cfg, host: String) -> Step:
  match inline:
    case None{}: Go{t, set_host(cfg, host)}
    case Some{+n}:
      args_port.selected(Ep.select_port(Some{n}, explicit_port(cfg), n), t, set_host(cfg, host))

def args_endpoint(got: Result<&2, &2, String, Ep.Endpoint>, t: List<&2, String>, cfg: Cfg) -> Step:
  match got:
    case Fail{msg}: Stop{Bad{"birc: --connect " ++ msg}}
    case Done{Ep.Endpoint{host, port}}: args_endpoint.port(port, t, cfg, host)

def FRAMES_MAX() -> U32:
  65535

def args_num_frames(+t: List<&2, String>, +cfg: Cfg, n: U32, over: Bool) -> Step:
  match over:
    case True{}:
      Stop{Bad{"birc: --frames too large"}}
    case False{}:
      Go{ t, set_frames(cfg, n)}

def PORT_MAX() -> U32:
  65535

def args_num_port(+t: List<&2, String>, +cfg: Cfg, +n: U32, bad: Bool) -> Step:
  match bad:
    case True{}:
      Stop{Bad{"birc: --port out of range"}}
    case False{}:
      args_port.selected(Ep.select_port(Some{n}, explicit_port(cfg), n), t, cfg)

def args_num_which(+t: List<&2, String>, +cfg: Cfg, +n: U32, frames: Bool) -> Step:
  match frames:
    case True{}:
      args_num_frames(t, cfg, n, U32.is_gt(n, FRAMES_MAX()))
    case False{}:
      args_num_port(t, cfg, n, U32.is_eq(n, 0) || U32.is_gt(n, PORT_MAX()))

def args_num_ok(+t: List<&2, String>, +cfg: Cfg, n: U32, ok: Bool, frames: Bool) -> Step:
  match ok:
    case False{}:
      Stop{Bad{"birc: expected a number"}}
    case True{}:
      args_num_which(t, cfg, n, frames)

def args_num_on(+t: List<&2, String>, +cfg: Cfg, got: Num, frames: Bool) -> Step:
  match got:
    case Num{ok, n}:
      args_num_ok(t, cfg, n, ok, frames)

def args_num(+t: List<&2, String>, +cfg: Cfg, +tok: String, frames: Bool) -> Step:
  args_num_on(t, cfg, parse_u32(tok), frames)

def args_take_con(+xs: List<&2, String>, +cfg: Cfg, frames: Bool) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      args_num(t, cfg, h, frames)

def args_take(+xs: List<&2, String>, +cfg: Cfg, frames: Bool) -> Step:
  args_take_con(xs, cfg, frames)

def args_word_set(+t: List<&2, String>, +cfg: Cfg, +h: String, host: Bool) -> Step:
  match host:
    case True{}:
      args_endpoint(Ep.parse(h), t, cfg)
    case False{}:
      Go{ t, set_nick(cfg, h)}

def args_word_con(+xs: List<&2, String>, +cfg: Cfg, host: Bool) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      args_word_set(t, cfg, h, host)

def args_word(+xs: List<&2, String>, +cfg: Cfg, host: Bool) -> Step:
  args_word_con(xs, cfg, host)

def args_chan.valid(parsed: Maybe<&2, List<&2, String>>, xs: List<&2, String>, cfg: Cfg, chan: String) -> Step:
  match parsed:
    case None{}: Stop{Bad{"birc: invalid channel list"}}
    case Some{_}: Go{xs, set_chan(cfg, chan)}

def args_chan_con(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      args_chan.valid(Channels.launch_names(h), t, cfg, h)

def args_chan(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  args_chan_con(xs, cfg)

def args_replay_con(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      Go{ t, set_replay(cfg, h)}

def args_replay(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  args_replay_con(xs, cfg)

def args_sasl_user_con(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      Go{ t, set_sasl_user(cfg, h)}

def args_sasl_user(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  args_sasl_user_con(xs, cfg)

def args_sasl_pass_con(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      Go{ t, set_sasl_pass(cfg, h)}

def args_sasl_pass(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  args_sasl_pass_con(xs, cfg)

def auth_mode(+value: String) -> Maybe<&2, Cl.AuthMode>:
  Bool.pick(Maybe<&2, Cl.AuthMode>, String.eq(value, "sasl"), Some{Cl.SaslOnly{}},
    Bool.pick(Maybe<&2, Cl.AuthMode>, String.eq(value, "nickserv"), Some{Cl.NickServOnly{}},
      Bool.pick(Maybe<&2, Cl.AuthMode>, String.eq(value, "sasl-nickserv"), Some{Cl.SaslNickServ{}}, None{})))

def args_auth.mode(got: Maybe<&2, Cl.AuthMode>, t: List<&2, String>, +cfg: Cfg, prefix: String, success: String) -> Step:
  match got:
    case None{}: Stop{Bad{"birc: --auth expects sasl, nickserv, or sasl-nickserv"}}
    case Some{mode}: Go{t, set_auth(cfg, AuthOptions{mode, prefix, success})}

def args_auth.options(options: AuthOptions, t: List<&2, String>, +cfg: Cfg, +value: String, which: U32) -> Step:
  match options:
    case AuthOptions{mode, prefix, success}:
      match which:
        case 0: args_auth.mode(auth_mode(value), t, cfg, prefix, success)
        case 1: Go{t, set_auth(cfg, AuthOptions{mode, value, success})}
        case _: Go{t, set_auth(cfg, AuthOptions{mode, prefix, value})}

def args_auth(xs: List<&2, String>, +cfg: Cfg, which: U32) -> Step:
  match xs:
    case Nil{}: Stop{Bad{"birc: missing value"}}
    case Con{value, t}: args_auth.options(auth_of(cfg), t, cfg, value, which)

def auth_options_valid(options: AuthOptions) -> Bool:
  match options:
    case AuthOptions{mode, +prefix, +success}:
      Auth.valid_config(mode, prefix, success)

def args_finish.ws(+cfg: Cfg, +demo: Bool, +replay: String, +servers: List<&2, Ep.Endpoint>, ws: Bool) -> Step:
  match ws:
    case False{}: Stop{Good{resolve_port(cfg)}}
    case True{}: Stop{Bad{"birc: --server needs a live connection (not --demo or --replay)"}}

def args_finish.live(+cfg: Cfg) -> Step:
  match cfg:
    case Cfg{+demo, _, _, _, _, _, +replay, _, _, _, _, _, _, +servers}:
      args_finish.ws(cfg, demo, replay, servers, Bool.not(List.is_empty(&2, Ep.Endpoint, servers)) && (demo || Bool.not(String.is_empty(replay))))

def args_finish(valid: Bool, cfg: Cfg) -> Step:
  match valid:
    case True{}: args_finish.live(cfg)
    case False{}: Stop{Bad{"birc: NickServ authentication requires an exact --nickserv-prefix and control-free --nickserv-success"}}

def USAGE() -> String:
  "usage: birc [--frames N] [--connect HOST[:PORT]] [--port N] [--nick N] [--channel #c] [--replay FILE] [--sasl-user USER] [--sasl-pass PASS] [--auth sasl|nickserv|sasl-nickserv] [--nickserv-prefix nick!user@host] [--nickserv-success TEXT] [--server HOST[:PORT]] [--demo] [--help-irc] [--tls|--plain]"

type Flag is Data:
  FDemo{}
  FFrames{}
  FConnect{}
  FPort{}
  FNick{}
  FChan{}
  FReplay{}
  FSaslUser{}
  FSaslPass{}
  FAuth{}
  FNickServPrefix{}
  FNickServSuccess{}
  FHelp{}
  FTls{}
  FPlain{}
  FServer{}
  FUnknown{}

type FlagRow is Data:
  FlagRow{name: String, f: Flag}

def flag_rows() -> List<&2, FlagRow>:
  FlagRow{"--demo", FDemo{}} <> FlagRow{"--frames", FFrames{}} <> FlagRow{"--connect", FConnect{}} <> FlagRow{"--port", FPort{}} <> FlagRow{"--nick", FNick{}} <> FlagRow{"--channel", FChan{}} <> FlagRow{"--replay", FReplay{}} <> FlagRow{"--sasl-user", FSaslUser{}} <> FlagRow{"--sasl-pass", FSaslPass{}} <> FlagRow{"--auth", FAuth{}} <> FlagRow{"--nickserv-prefix", FNickServPrefix{}} <> FlagRow{"--nickserv-success", FNickServSuccess{}} <> FlagRow{"--help-irc", FHelp{}} <> FlagRow{"--tls", FTls{}} <> FlagRow{"--plain", FPlain{}} <> FlagRow{"--server", FServer{}} <> Nil{}

def flag_of(xs: List<&2, FlagRow>, +h: String) -> Flag:
  match xs:
    case Nil{}:
      FUnknown{}
    case Con{row, t}:
      match row:
        case FlagRow{+name, +f}:
          Bool.pick(Flag, String.eq(name, h), f, flag_of(t, h))

def servers_of(cfg: Cfg) -> List<&2, Ep.Endpoint>:
  match cfg:
    case Cfg{_, _, _, _, _, _, _, _, _, _, _, _, _, +servers}: servers

def args_server.append(+t: List<&2, String>, +cfg: Cfg, +ep: Ep.Endpoint, full: Bool) -> Step:
  match full:
    case True{}: Stop{Bad{"birc: too many --server flags (at most 4 servers total)"}}
    case False{}: Go{t, add_server_endpoint(cfg, ep)}

def args_server.parsed(got: Result<&2, &2, String, Ep.Endpoint>, +t: List<&2, String>, +cfg: Cfg) -> Step:
  match got:
    case Fail{msg}: Stop{Bad{"birc: --server " ++ msg}}
    case Done{+ep}: args_server.append(t, cfg, ep, servers_full(servers_of(cfg)))

def args_server(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}: Stop{Bad{"birc: --server expects HOST[:PORT]"}}
    case Con{+h, +t}: args_server.parsed(Ep.parse(h), t, cfg)

def args_opt.do(+t: List<&2, String>, +cfg: Cfg, +h: String, f: Flag) -> Step:
  match f:
    case FDemo{}:
      Go{ t, set_demo(cfg)}
    case FFrames{}:
      args_take(t, cfg, True{})
    case FConnect{}:
      args_word(t, cfg, True{})
    case FPort{}:
      args_take(t, cfg, False{})
    case FNick{}:
      args_word(t, cfg, False{})
    case FChan{}:
      args_chan(t, cfg)
    case FReplay{}:
      args_replay(t, cfg)
    case FSaslUser{}:
      args_sasl_user(t, cfg)
    case FSaslPass{}:
      args_sasl_pass(t, cfg)
    case FAuth{}:
      args_auth(t, cfg, 0)
    case FNickServPrefix{}:
      args_auth(t, cfg, 1)
    case FNickServSuccess{}:
      args_auth(t, cfg, 2)
    case FTls{}:
      Mode{t, set_secure(cfg, True{}), True{}}
    case FPlain{}:
      Mode{t, set_secure(cfg, False{}), False{}}
    case FServer{}:
      args_server(t, cfg)
    case FHelp{}:
      Stop{Bad{USAGE()}}
    case FUnknown{}:
      Stop{Bad{"birc: unknown option " ++ h}}

def args_flag(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      args_finish(auth_options_valid(auth_of(cfg)), cfg)
    case Con{+h, t}:
      args_opt.do(t, cfg, h, flag_of(flag_rows(), h))

def mode_conflict.seen(seen: Maybe<&2, Bool>, secure: Bool) -> Bool:
  match seen:
    case None{}: False{}
    case Some{True{}}: Bool.not(secure)
    case Some{False{}}: secure

def args_mode(t: List<&2, String>, cfg: Cfg, conflict: Bool) -> Step:
  match conflict:
    case False{}: args_flag(t, cfg)
    case True{}: Stop{Bad{"birc: --tls and --plain conflict"}}

# Explicit mode selection is parser-local, not an extra persistent Cfg field.
# Mode consumes the next flag directly, keeping the existing fuel accounting.
def args_go(fuel: Nat, st: Step, +seen: Maybe<&2, Bool>) -> Parsed:
  match fuel:
    case 0n:
      Bad{"birc: too many arguments"}
    case 1n+p:
      match st:
        case Stop{got}:
          got
        case Go{+xs, +cfg}:
          args_go(p, args_flag(xs, cfg), seen)
        case Mode{xs, cfg, +secure}:
          args_go(p, args_mode(xs, cfg, mode_conflict.seen(seen, secure)), Some{secure})

def parse(+xs: List<&2, String>) -> Parsed:
  args_go(64n, Go{ xs, cfg0()}, None{})

def copy_args(src: List<&1, String>, acc: List<&2, String>) -> List<&2, String>:
  match src:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{+h, t}:
      copy_args(t, h <> acc)

def drop_prog.on(h: String, t: List<&1, String>, is_flag: Bool) -> List<&1, String>:
  match is_flag:
    case True{}:
      h <> t
    case False{}:
      t

def drop_prog(xs: List<&1, String>) -> List<&1, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      drop_prog.on(h, t, String.starts_with(h, "-"))

def parse_raw(raw: List<&1, String>) -> Parsed:
  parse(copy_args(drop_prog(raw), Nil{}))
