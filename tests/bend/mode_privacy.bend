import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as Hist

def base() -> Cl.Client:
  Feed.feed(Cl.init("me", "irc"), ":me!u@h JOIN #room")

def private(+wire: String) -> Bool:
  +cl = Feed.feed(base(), wire)
  Bool.not(String.contains(CL.buf_texts(cl, 0n) ++ CL.buf_texts(cl, 1n), "opaque-secret"))
    && Bool.not(String.contains(Hist.extract_new_history_for("irc:6697", base(), cl), "opaque-secret"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("channel key mode never enters chat/history", private(":alice!u@h MODE #room +k opaque-secret"))
    Unit <- E.must("channel key unset never enters chat/history", private(":alice!u@h MODE #room -k opaque-secret"))
    Unit <- E.must("combined channel key modes are private", private(":alice!u@h MODE #room +ovk bob carol opaque-secret"))
    Unit <- E.must("numeric channel key reply never enters chat/history", private(":irc 324 me #room +k opaque-secret"))
    Unit <- E.must("unsigned key mode never enters chat/history", private(":alice!u@h MODE #room k opaque-secret"))
    Unit <- E.must("malformed signed key never enters chat/history", private(":alice!u@h MODE #room +k! opaque-secret"))
    Unit <- E.must("unsigned numeric key never enters chat/history", private(":irc 324 me #room k opaque-secret"))
    Unit <- E.must("ordinary mode still renders", String.contains(CL.buf_texts(Feed.feed(base(), ":alice!u@h MODE #room +o bob"), 1n), "alice MODE #room +o bob"))
    Unit <- E.must("unrelated text is not globally redacted", String.contains(CL.buf_texts(Feed.feed(base(), ":alice!u@h PRIVMSG #room :opaque-secret"), 1n), "opaque-secret"))
    IO.print("mode_privacy=ok")
