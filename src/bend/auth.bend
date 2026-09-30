# IRCv3 SASL PLAIN. Only a parsed control event in its expected phase can
# produce credentials. The session keeps phase across receive chunks.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./base64.bend as B64

type Notice is Data:
  Quiet{}
  Started{}
  Succeeded{}
  Failed{}
  Rejected{}

type Reply is Data:
  Reply{phase: Cl.AuthPhase, outs: List<&2, String>, notice: Notice}

def unchanged(phase: Cl.AuthPhase) -> Reply:
  Reply{phase, Nil{}, Quiet{}}

def step.cap(e: Irc.SaslEvent) -> Reply:
  match e:
    case Irc.SaslAck{}:
      Reply{Cl.AuthChallenge{}, "AUTHENTICATE PLAIN" <> Nil{}, Started{}}
    case Irc.SaslNak{}:
      Reply{Cl.AuthDone{}, "CAP END" <> Nil{}, Rejected{}}
    case _:
      unchanged(Cl.AuthCap{})

def step.challenge(e: Irc.SaslEvent, +user: String, +pass: String) -> Reply:
  match e:
    case Irc.SaslPlus{}:
      Reply{Cl.AuthResult{}, B64.authenticate_chunks(B64.sasl_plain(user, pass)), Quiet{}}
    case Irc.SaslFailure{}:
      Reply{Cl.AuthDone{}, "CAP END" <> Nil{}, Failed{}}
    case _:
      unchanged(Cl.AuthChallenge{})

def step.result(e: Irc.SaslEvent) -> Reply:
  match e:
    case Irc.SaslSuccess{}:
      Reply{Cl.AuthDone{}, "CAP END" <> Nil{}, Succeeded{}}
    case Irc.SaslFailure{}:
      Reply{Cl.AuthDone{}, "CAP END" <> Nil{}, Failed{}}
    case _:
      unchanged(Cl.AuthResult{})

def step(phase: Cl.AuthPhase, e: Irc.SaslEvent, +user: String, +pass: String) -> Reply:
  match phase:
    case Cl.AuthIdle{}: unchanged(Cl.AuthIdle{})
    case Cl.AuthCap{}: step.cap(e)
    case Cl.AuthChallenge{}: step.challenge(e, user, pass)
    case Cl.AuthResult{}: step.result(e)
    case Cl.AuthDone{}: unchanged(Cl.AuthDone{})

def log_notice(+cl: Cl.Client, notice: Notice) -> Cl.Client:
  match notice:
    case Quiet{}: cl
    case Started{}: Cl.client_log(cl, 0n, Cl.System{}, "SASL: authenticating with PLAIN...")
    case Succeeded{}: Cl.client_log(cl, 0n, Cl.System{}, "SASL: authentication successful")
    case Failed{}: Cl.client_log(cl, 0n, Cl.Error{}, "SASL: authentication failed")
    case Rejected{}: Cl.client_log(cl, 0n, Cl.Error{}, "SASL: capability rejected")
