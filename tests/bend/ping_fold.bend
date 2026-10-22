# SPDX-License-Identifier: Apache-2.0
# Negotiated and live PING folds emit no outbound PONG. The reader owns the reply.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/isupport.bend as Is
import ../../src/bend/session.bend as Sess

def iso() -> Cl.Iso:
  Is.as_iso(Is.defaults())

def cl() -> Cl.Client:
  Cl.init("me", "s")

def outs(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, xs): String.concat(xs)

# 001 must take the feed arm (welcomed) and must not invent a PONG.
def welcome_shape(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (got, xs):
      Bool.show(Cl.welcomed_of(got)) ++ "|" ++ String.concat(xs)

def ping_with(+pongs: List<&2, String>, +line: String) -> Cl.Client & List<&2, String>:
  Sess.fold_fin(Sess.fold_step.got_at_with(iso(), cl(), pongs, 0, line, None{}, 6697))

def ping_live() -> Cl.Client & List<&2, String>:
  Sess.fold_fin(Sess.fold_step.got_at(cl(), Nil{}, 0, "PING :abc", None{}, 6697))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("negotiated ping emits nothing", outs(ping_with(Nil{}, "PING :abc")), "")
    Unit <- E.must_eq("live ping emits nothing", outs(ping_live()), "")
    Unit <- E.must_eq("welcome is not the ping arm", welcome_shape(ping_with(Nil{}, ":irc.example.net 001 me :Welcome")), "True|")
    Unit <- E.must_eq("existing outs survive ping", outs(ping_with("ALREADY" <> Nil{}, "PING :abc")), "ALREADY")
    IO.print("ping_fold=ok")
