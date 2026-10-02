# SPDX-License-Identifier: Apache-2.0
# A failed success-pipe write is a fixed numeric diagnostic, not chat history.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/session.bend as Sess
import ../../src/bend/net.bend as Net
import ../../src/bend/history.bend as H

def main() -> IO(Unit):
  +base = Cl.client_set_auth(Cl.init("me", "irc.example"), Cl.SaslOnly{}, "irc.example", 6667, "", "", "account", "opaque-auth-secret")
  +st = Sess.session_with_client(base, "#t")
  +quiet = Sess.session_cl(Net.auth_notice(st, 0))
  +failed = Sess.session_cl(Net.auth_notice(st, 5))
  do IO<Unit>:
    Unit <- E.must("successful notification does not create a diagnostic", Bool.not(CL.has_buf(quiet, "*log*")))
    Unit <- E.must_eq("successful notification leaves server rows unchanged", CL.buf_texts(quiet, 0n), CL.buf_texts(base, 0n))
    Unit <- E.must("successful notification leaves event sequence unchanged", Nat.is_eq(Cl.log_seq_of(quiet), Cl.log_seq_of(base)))
    Unit <- E.must("failed notification creates app-session log", CL.has_buf(failed, "*log*"))
    Unit <- E.must_eq("failed notification uses only a fixed stage and numeric code", CL.buf_texts(failed, 1n), "authentication notification failed (code: 5)|")
    Unit <- E.must_eq("failed notification never changes chat rows", CL.buf_texts(failed, 0n), CL.buf_texts(base, 0n))
    Unit <- E.must_eq("failed notification does not steal focus", Cl.active_buf_name(failed), Cl.active_buf_name(base))
    Unit <- E.must_eq("failed notification is never persisted", H.extract_new_history_for("irc.example:6667", base, failed), "")
    Unit <- E.must_eq("failed notification preserves credentials", Cl.client_sasl_pass(failed), "opaque-auth-secret")
    Unit <- E.must("failed notification cannot confirm authentication", Nat.is_eq(Cl.auth_success_seq(failed), Cl.auth_success_seq(base)))
    IO.print("auth_notice=ok")
