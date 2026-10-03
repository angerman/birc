# SPDX-License-Identifier: Apache-2.0
# Private fixture paths and fake helper effects are supplied by Python.
import Base
import ../../src/bend/startup_headless.bend as H
import ../../src/bend/preferences_live.bend as LP
import ../../src/bend/preferences_runtime.bend as R
import ../../src/bend/preferences_worker.bend as W
import ../../src/bend/session.bend as S
import ../../src/bend/buffer.bend as Cl

def session() -> S.Session:
  S.session_with_client_at(Cl.client_set_auth(Cl.init("me", "irc.example"), Cl.SaslOnly{}, "irc.example", 6697,
    "NickServ!service@services.example", "confirmed", "synthetic-account", "synthetic-secret"), "#initial", 6697)

def bit(on: Bool) -> String:
  Bool.pick(String, on, "1", "0")

def write_pending(pair: R.State & Maybe<&2, R.Job>) -> Bool:
  match pair:
    case (_, Some{R.Write{_, _, _, _}}): True{}
    case _: False{}

def row_text(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{Cl.Reconnect{}, _, _, _, _}, rest}: row_text(rest)
    case Con{Cl.Line{_, _, text, _, _}, rest}: text ++ "|" ++ row_text(rest)

def divider_count(lines: List<&2, Cl.Line>) -> Nat:
  match lines:
    case Nil{}: 0n
    case Con{Cl.Line{Cl.Reconnect{}, _, _, _, _}, rest}: 1n+divider_count(rest)
    case Con{_, rest}: divider_count(rest)

def server_rows(cl: Cl.Client) -> List<&2, Cl.Line>:
  match cl:
    case Cl.Client{_, _, Con{Cl.Buffer{_, _, _, lines, _, _}, _}, _, _, _, _, _}: lines
    case _: Nil{}

def show.ready(ctx: LP.Context, +st: S.Session, allowed: Bool) -> String:
  +cl = S.session_cl(st)
  +settings = Cl.get_settings(cl)
  "allowed=" ++ bit(allowed) ++ ";history=" ++ bit(Cl.settings_history(settings))
    ++ ";cap=" ++ U32.show(Cl.settings_hist_cap(settings)) ++ ";rows=" ++ row_text(server_rows(cl))
    ++ ";divider=" ++ Nat.show(divider_count(server_rows(cl)))
    ++ ";names=" ++ String.join(S.session_desired_channels(st), "|")
    ++ ";auth=" ++ bit(String.eq(Cl.client_sasl_user(cl), "synthetic-account") && String.eq(Cl.client_sasl_pass(cl), "synthetic-secret"))
    ++ ";pending=" ++ bit(write_pending(R.take(LP.state(ctx))))

def show(result: LP.Context & S.Session & Bool) -> String:
  match result:
    case (ctx, st, allowed): show.ready(ctx, st, allowed)

def mode(+name: String, path: String) -> IO(Unit):
  do IO<Unit>:
    prepared : LP.Context & S.Session & Bool <- H.prepare(W.Options{Bool.not(String.eq(name, "disabled")), String.eq(name, "explicit"), False{}, False{}}, session(), 1, path)
    IO.print(show(prepared))

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{name, Con{path, Nil{}}}}: mode(name, path)
    case _: IO.die(Unit, 1, "expected mode and private archive path")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
