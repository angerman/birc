# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as Sess
import ../../src/bend/media.bend as M

def cmd(triple: Cl.Client & String & Sess.NetCmd) -> String:
  match triple:
    case (_, _, c): Sess.show_netcmd(c)

def step_cmd(triple: Sess.Session & Sess.NetCmd & Bool) -> String:
  match triple:
    case (_, c, _): Sess.show_netcmd(c)

def auto_cmd(pair: Sess.Session & Sess.NetCmd) -> String:
  match pair:
    case (_, c): Sess.show_netcmd(c)

def disconnected(+endpoint: String) -> Sess.Session:
  +dialed = Sess.st_of_keys(Sess.step_enter(Sess.session_demo(Cl.init("me", ""), ""), "/connect " ++ endpoint))
  Sess.session_fail(Sess.session_online(dialed), "fixture disconnect")

def enabled(+st: Sess.Session) -> Sess.Session:
  +cl = Sess.session_cl(st)
  Sess.session_set_client(st, Cl.set_settings(cl, Cl.set_autoreconn(Cl.get_settings(cl), True{})))

def endpoint(+name: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("explicit connect accepts " ++ name, cmd(Sess.connect_apply(Cl.init("me", ""), Sess.Demo{}, 6667, Sub.ConnOk{name, 6667})), "dial:" ++ name ++ ":6667")
    Unit <- E.must_eq("saved endpoint reconnect accepts " ++ name, cmd(Sess.connect_apply(Cl.init("me", name), Sess.Offline{}, 6667, Sub.ConnReconnect{})), "dial:" ++ name ++ ":6667")
    Unit <- E.must_eq("real manual flow reconnect accepts " ++ name, step_cmd(Sess.step_enter(disconnected(name), "/reconnect")), "dial:" ++ name ++ ":6667")
    Unit <- E.must_eq("real automatic flow reconnect accepts " ++ name, auto_cmd(Sess.session_autoreconnect(enabled(disconnected(name)))), "dial:" ++ name ++ ":6667")
    IO.pure(Unit, Unit{})

def images(+st: Sess.Session, +arg: String) -> Sess.Session:
  Sess.st_of_keys(Sess.step_enter(st, "/images " ++ arg))

def main() -> IO(Unit):
  +demo = Sess.session_demo(Cl.init("me", ""), "")
  +off = images(demo, "off")
  do IO<Unit>:
    Unit <- endpoint("s")
    Unit <- endpoint("demo")
    Unit <- endpoint("irc.example")
    Unit <- E.must_eq("unconfigured demo cannot reconnect", cmd(Sess.connect_apply(Cl.init("me", ""), Sess.Demo{}, 6667, Sub.ConnReconnect{})), "cont")
    Unit <- E.must_eq("demo fixture hostname is not connection intent", cmd(Sess.connect_apply(Cl.init("me", "s"), Sess.Demo{}, 6667, Sub.ConnReconnect{})), "cont")
    Unit <- E.must_eq("automatic reconnect remains opt-in", auto_cmd(Sess.session_autoreconnect(disconnected("s"))), "drop")
    Unit <- E.must("images off changes media state", Bool.not(M.enabled(Sess.session_media(off))))
    Unit <- E.must("images on changes media state", M.enabled(Sess.session_media(images(off, "on"))))
    Unit <- E.must("invalid images arg does not change state", Bool.not(M.enabled(Sess.session_media(images(off, "ON")))))
    IO.print("m21_session=ok")
