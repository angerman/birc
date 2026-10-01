# SPDX-License-Identifier: Apache-2.0
# Only current-generation writer completion can release UI shutdown.
import Base
import ./expect.bend as E
import ../../src/bend/session.bend as Sess

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("writer completion", Sess.writer_done_current(Sess.FromNet{1, Sess.WriterDone{}}, 1))
    Unit <- E.must("idle actor completion", Sess.writer_done_current(Sess.FromNet{0, Sess.WriterDone{}}, 0))
    Unit <- E.must("stale completion", Bool.not(Sess.writer_done_current(Sess.FromNet{0, Sess.WriterDone{}}, 1)))
    Unit <- E.must("reader EOF is not writer completion", Bool.not(Sess.writer_done_current(Sess.FromNet{1, Sess.Eof{}}, 1)))
    Unit <- E.must("failure is not writer completion", Bool.not(Sess.writer_done_current(Sess.FromNet{1, Sess.NetFail{"failed"}}, 1)))
    Unit <- E.must("unrelated UI event", Bool.not(Sess.writer_done_current(Sess.UiKey{}, 1)))
    IO.print("shutdown_ack=ok")
