# SPDX-License-Identifier: Apache-2.0
# G3 production-path traversal top-up: MODE/324, mentions, KICK via
# Fr->Session byte-framing; media via live observe/request visible-results
# plus /open agreement. Preserves all 38 g3_framed guards; proves path
# equivalence with the exact same pairs.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ./mode_view_guard.bend as ModeView
import ../../src/bend/history.bend as H
import ../../src/bend/frame.bend as F
import ../../src/bend/session.bend as S
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V
import ../../src/bend/submit.bend as Sub
import ../../src/bend/join_plan.bend as JP

def ctl(+n: U32, +s: String) -> String:
  SCon{Chr{n}, s}

def secret() -> String:
  "opaque-secret"

def img() -> String:
  "https://x.test/a.png"

# ---- traversal bases: JOIN via Fr->Session, then one wire via Fr->Session --
def mode_base() -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(
    S.session_online(S.session_with_client(Cl.init("me", "irc"), "#room")),
    F.string_to_octets(":me!u@h JOIN #room\r\n"), 1000))

def mention_base() -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(
    S.session_online(S.session_with_client(Cl.init("me", "s"), "#birc")),
    F.string_to_octets(":me!m@h JOIN #birc\r\n:me!m@h JOIN #other\r\n"), 1000))

def kick_base() -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(
    S.session_online(S.session_with_client(Cl.init("me", "s"), "#room")),
    F.string_to_octets(":me!m@h JOIN #room\r\n"), 1000))

def media_base() -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(
    S.session_online(S.session_with_client(Cl.init("me", "s"), "#room")),
    F.string_to_octets(":me!m@h JOIN #room\r\n"), 1000))

def mode_after(+wire: String) -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(mode_base(), F.string_to_octets(wire ++ "\r\n"), 1000))

def mention_after(+body: String) -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(mention_base(),
    F.string_to_octets(":alice!a@h PRIVMSG #birc :" ++ body ++ "\r\n"), 1000))

def kick_after(+wire: String) -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(kick_base(), F.string_to_octets(wire ++ "\r\n"), 1000))

def media_after(+body: String) -> S.Session:
  S.session_observe_visible_media(S.st_of_chunk(S.step_on_chunk_ms(media_base(),
    F.string_to_octets(":alice!a@h PRIVMSG #room :" ++ body ++ "\r\n"), 1000)))

# ---- (1) MODE / 324 via Session --------------------------------------------
def trav_mode_private(+wire: String) -> Bool:
  +before = S.session_cl(mode_base())
  +after = S.session_cl(mode_after(wire))
  Bool.not(String.contains(CL.buf_texts(after, 0n) ++ CL.buf_texts(after, 1n), secret()))
    && Bool.not(String.contains(H.extract_new_history_for("irc:6697", before, after), secret()))

def trav_mode_visible(+wire: String, +want: String) -> Bool:
  String.contains(CL.buf_texts(S.session_cl(mode_after(wire)), 1n), want)

# ---- (4) mentions via Session ----------------------------------------------
def trav_mention_hit(+body: String) -> Bool:
  U32.is_eq(Cl.client_bell_seq(S.session_cl(mention_after(body))), 1)

def trav_mention_miss(+body: String) -> Bool:
  U32.is_eq(Cl.client_bell_seq(S.session_cl(mention_after(body))), 0)

def trav_mention_bytes(+body: String) -> Bool:
  +before = S.session_cl(mention_base())
  +after = S.session_cl(mention_after(body))
  String.contains(CL.buf_texts(after, 1n), body)
    && String.contains(H.extract_new_history_for("s:6667", before, after), body)

# ---- (5) KICK via Session ---------------------------------------------------
def kick_after_cl(+wire: String) -> Cl.Client:
  S.session_cl(kick_after(wire))

def kick_after_intent(+wire: String) -> String:
  String.join(S.session_desired_channels(kick_after(wire)), ",")

def trav_self_kick_clears(+wire: String) -> Bool:
  +cl = kick_after_cl(wire)
  Bool.not(CL.has_buf(cl, "#room")) && Nat.is_eq(CL.nbuf(cl), 1n) && String.eq(kick_after_intent(wire), "")

def trav_peer_keeps(+wire: String) -> Bool:
  CL.has_buf(kick_after_cl(wire), "#room")

# ---- (3) media via live observe/request visible-results + /open ------------
def cand_urls(xs: List<&2, M.Candidate>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{M.Candidate{_, +url}, t}: url <> cand_urls(t)

def has_job(pair: M.State & Maybe<&2, M.Request>) -> Bool:
  match pair:
    case (_, Some{_}): True{}
    case _: False{}

def visible_urls(+st: S.Session) -> List<&2, String>:
  cand_urls(V.visible_media_candidates(S.session_cl(st), 24, 80, S.session_split(st), S.session_media(st)))

def trav_media_glue(+body: String) -> Bool:
  +st = media_after(body)
  Nat.is_eq(M.pending_count(S.session_media(st)), 0n)
    && String.eq(String.join(visible_urls(st), ","), "")
    && String.eq(String.join(Sub.active_buf_urls(S.session_cl(st)), ","), "")
    && Bool.not(has_job(M.take_job(S.session_media(st))))

def trav_media_fetch(+body: String, +want: String) -> Bool:
  +st = media_after(body)
  Nat.is_eq(M.pending_count(S.session_media(st)), 1n)
    && String.eq(String.join(visible_urls(st), ","), want)
    && String.eq(String.join(Sub.active_buf_urls(S.session_cl(st)), ","), want)
    && has_job(M.take_job(S.session_media(st)))

# ---- closing guards: restore, request identity, alert, reconnect-outs -----
def buf_line_ids(+xs: List<&2, Cl.Line>) -> List<&2, Nat>:
  match xs:
    case Nil{}: Nil{}
    case Con{Cl.Line{_, _, _, _, +id}, t}: id <> buf_line_ids(t)

def buf_ids_on(got: Maybe<&2, Cl.Buffer>) -> List<&2, Nat>:
  match got:
    case None{}: Nil{}
    case Some{b}:
      match b:
        case Cl.Buffer{_, _, _, +lines, _, _, _, _}: buf_line_ids(lines)

def buf_ids(+cl: Cl.Client, +i: Nat) -> List<&2, Nat>:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _, _}: buf_ids_on(Cl.nth_buf(bufs, i))

def last_nat_of(m: Maybe<&2, Nat>, +dflt: Nat) -> Nat:
  match m:
    case None{}: dflt
    case Some{+x}: x

def last_nat(+xs: List<&2, Nat>, +dflt: Nat) -> Nat:
  last_nat_of(List.last(&2, Nat, xs), dflt)

def req_exact(pair: M.State & Maybe<&2, M.Request>, +want: String, +want_id: Nat) -> Bool:
  match pair:
    case (_, Some{M.Request{M.Inline{+id}, +url, +gen, +ticket}}):
      String.eq(url, want) && Nat.is_eq(id, want_id) && Nat.is_eq(gen, 1n) && Nat.is_eq(ticket, 1n)
    case _: False{}

def trav_req_exact(+body: String, +want: String) -> Bool:
  +st = media_after(body)
  +cl = S.session_cl(st)
  req_exact(M.take_job(S.session_media(st)), want, last_nat(buf_ids(cl, 1n), 999999n))

# Byte feeding maintains media state; visible ownership schedules separately.
def media_unobserved(+body: String) -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(media_base(),
    F.string_to_octets(":alice!a@h PRIVMSG #room :" ++ body ++ "\r\n"), 1000))

def trav_media_feed_only(+body: String, +want: String) -> Bool:
  +st = media_unobserved(body)
  Nat.is_eq(M.pending_count(S.session_media(st)), 0n)
    && String.eq(String.join(visible_urls(st), ","), want)
    && String.eq(String.join(Sub.active_buf_urls(S.session_cl(st)), ","), want)
    && Bool.not(has_job(M.take_job(S.session_media(st))))

def trav_media_stage(+body: String, +want: String) -> Bool:
  +raw = media_unobserved(body)
  +st = S.session_observe_visible_media(raw)
  M.enabled(S.session_media(st)) && M.supported(S.session_media(st))
    && Nat.is_eq(M.pending_count(S.session_media(st)), 1n)
    && String.eq(String.join(visible_urls(st), ","), want)
    && String.eq(String.join(Sub.active_buf_urls(S.session_cl(st)), ","), want)
    && req_exact(M.take_job(S.session_media(st)), want, last_nat(buf_ids(S.session_cl(raw), 1n), 999999n))
    && String.eq(CL.buf_texts(S.session_cl(raw), 1n), CL.buf_texts(S.session_cl(st), 1n))

def trav_media_stage_disabled(+body: String, +want: String) -> Bool:
  +raw = media_unobserved(body)
  +off = S.session_set_media(raw, M.set_enabled(S.session_media(raw), False{}))
  +st = S.session_observe_visible_media(off)
  Bool.not(M.enabled(S.session_media(st)))
    && Nat.is_eq(M.pending_count(S.session_media(st)), 0n)
    && Bool.not(has_job(M.take_job(S.session_media(st))))
    && String.eq(String.join(Sub.active_buf_urls(S.session_cl(st)), ","), want)
    && String.eq(CL.buf_texts(S.session_cl(raw), 1n), CL.buf_texts(S.session_cl(st), 1n))

def alert_level_at(level: Cl.AlertLevel) -> U32:
  match level:
    case Cl.Mention{}: 2
    case Cl.Activity{}: 1

def alert_level_pick(+here: U32, +there: U32, hit: Bool) -> U32:
  match hit:
    case True{}: here
    case False{}: there

def alert_level(+xs: List<&2, Cl.Alert>, +name: String) -> U32:
  match xs:
    case Nil{}: 0
    case Con{Cl.Alert{+target, level}, t}:
      alert_level_pick(alert_level_at(level), alert_level(t, name), String.eq(target, name))

def trav_mention_alert(+body: String, +want: U32) -> Bool:
  +cl = S.session_cl(mention_after(body))
  +unreads = Cl.settings_unreads(Cl.get_settings(cl))
  U32.is_eq(alert_level(unreads, "#birc"), want)
    && U32.is_eq(Cl.buf_unread_status(unreads, "#birc"), want)

def flush_outs_of(f: JP.Flush) -> List<&2, String>:
  match f:
    case JP.Flush{_, +outs, _}: outs

def flush_outs(+st: S.Session) -> List<&2, String>:
  +cl = S.session_cl(st)
  +re = JP.received(JP.reset(S.session_plan(st), cl, S.session_port(st)), cl, ":s 001 me :welcome")
  +done = JP.received(re, cl, ":s 376 me :end of MOTD")
  flush_outs_of(JP.flush(done, cl))

def outs_has(+xs: List<&2, String>, +want: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}: String.eq(h, want) || outs_has(t, want)

def trav_kick_reconnect_omits(+wire: String) -> Bool:
  Bool.not(outs_has(flush_outs(kick_after(wire)), "JOIN #room"))

def trav_kick_reconnect_keeps(+wire: String) -> Bool:
  outs_has(flush_outs(kick_after(wire)), "JOIN #room")

def restored_text(+before: Cl.Client, +after: Cl.Client, +endpoint: String) -> String:
  +text = H.extract_new_history_for(endpoint, before, after)
  +restored = H.apply_history(Cl.init("me", "s"), H.parse_history_text(text), "12:00:00", 100)
  CL.buf_texts(restored, 0n) ++ CL.buf_texts(restored, 1n)

def trav_mode_restore_private(+wire: String) -> Bool:
  +text = restored_text(S.session_cl(mode_base()), S.session_cl(mode_after(wire)), "irc:6697")
  Bool.not(String.contains(text, secret())) && String.contains(text, "[channel key hidden]")

def trav_mode_restore_visible(+wire: String, +want: String) -> Bool:
  String.contains(restored_text(S.session_cl(mode_base()), S.session_cl(mode_after(wire)), "irc:6697"), want)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("trav byte feed keeps visible nonempty URL but schedules no job", trav_media_feed_only("pic " ++ img() ++ " end", img()))
    Unit <- E.must("trav visible owner schedules exact source request without changing bytes", trav_media_stage("pic " ++ img() ++ " end", img()))
    Unit <- E.must("trav disabled visible owner rejects same valid URL without changing bytes", trav_media_stage_disabled("pic " ++ img() ++ " end", img()))
    Unit <- E.must("trav styled mode flags never persist a key", trav_mode_private(":alice!u@h MODE #room +" ++ ctl(2, "k") ++ " " ++ secret()))
    Unit <- E.must("trav styled mode channel never persists a key", trav_mode_private(":alice!u@h MODE #ro" ++ ctl(2, "om") ++ " +k " ++ secret()))
    Unit <- E.must("trav soh-framed mode channel never persists a key", trav_mode_private(":alice!u@h MODE #ro" ++ ctl(1, "om") ++ " +k " ++ secret()))
    Unit <- E.must("trav styled 324 flags never persist a key", trav_mode_private(":irc 324 me #room +" ++ ctl(2, "k") ++ " " ++ secret()))
    Unit <- E.must("trav styled 324 channel never persists a key", trav_mode_private(":irc 324 me #ro" ++ ctl(2, "om") ++ " +k " ++ secret()))
    Unit <- E.must_eq("trav MODE styled source preserves bold byte", ModeView.stored(S.session_cl(mode_after(":alice!u@h MODE #ro" ++ ctl(2, "om") ++ " +o bob"))), "alice MODE #ro" ++ ctl(2, "om") ++ " +o bob")
    Unit <- E.must_eq("trav MODE styled View keeps visible text", ModeView.visible(S.session_cl(mode_after(":alice!u@h MODE #ro" ++ ctl(2, "om") ++ " +o bob"))), "alice MODE #room +o bob")
    Unit <- E.must_eq("trav MODE ordinary View keeps visible text", ModeView.visible(S.session_cl(mode_after(":alice!u@h MODE #room +o bob"))), "alice MODE #room +o bob")
    Unit <- E.must_eq("trav MODE hostile ESC does not enter stored source", ModeView.stored(S.session_cl(mode_after(":alice!u@h MODE #ro" ++ ctl(27, "om") ++ " +o bob"))), "alice MODE #room +o bob")
    Unit <- E.must_eq("trav MODE hostile ESC does not enter View text", ModeView.visible(S.session_cl(mode_after(":alice!u@h MODE #ro" ++ ctl(27, "om") ++ " +o bob"))), "alice MODE #room +o bob")
    Unit <- E.must("trav ordinary mode key stays redacted", trav_mode_private(":alice!u@h MODE #room +k " ++ secret()))
    Unit <- E.must("trav ordinary mode still renders", trav_mode_visible(":alice!u@h MODE #room +o bob", "alice MODE #room +o bob"))
    Unit <- E.must("trav styled non-key mode still renders", trav_mode_visible(":alice!u@h MODE #ro" ++ ctl(2, "om") ++ " +o bob", "alice MODE #ro" ++ ctl(2, "om") ++ " +o bob"))
    Unit <- E.must("trav styled nick mention hits", trav_mention_hit("hi m" ++ ctl(2, "e")))
    Unit <- E.must("trav styled continuation is not a mention", trav_mention_miss("me" ++ ctl(2, "ow")))
    Unit <- E.must("trav color-split nick mention hits", trav_mention_hit("hi m" ++ ctl(3, "04e")))
    Unit <- E.must("trav color-split continuation is not a mention", trav_mention_miss("me" ++ ctl(3, "04ow")))
    Unit <- E.must("trav reset-split nick mention hits", trav_mention_hit("hi m" ++ ctl(15, "e")))
    Unit <- E.must("trav reset-split continuation is not a mention", trav_mention_miss("me" ++ ctl(15, "ow")))
    Unit <- E.must("trav ordinary mention still hits", trav_mention_hit("hi me"))
    Unit <- E.must("trav ordinary continuation still misses", trav_mention_miss("hi meow"))
    Unit <- E.must("trav styled mention source stays byte-identical", trav_mention_bytes("hi m" ++ ctl(2, "e")))
    Unit <- E.must("trav styled self-kick victim clears membership and intent", trav_self_kick_clears(":op!u@h KICK #room me" ++ ctl(2, "") ++ " :bye"))
    Unit <- E.must("trav soh self-kick victim clears membership and intent", trav_self_kick_clears(":op!u@h KICK #room me" ++ ctl(1, "") ++ " :bye"))
    Unit <- E.must("trav styled self-kick channel clears membership and intent", trav_self_kick_clears(":op!u@h KICK #ro" ++ ctl(2, "om") ++ " me :bye"))
    Unit <- E.must("trav soh self-kick channel clears membership and intent", trav_self_kick_clears(":op!u@h KICK #ro" ++ ctl(1, "om") ++ " me :bye"))
    Unit <- E.must("trav ordinary self-kick still clears", trav_self_kick_clears(":op!u@h KICK #room me :bye"))
    Unit <- E.must("trav peer kick keeps membership", trav_peer_keeps(":op!u@h KICK #room alice :bye"))
    Unit <- E.must_eq("trav peer kick preserves intent", kick_after_intent(":op!u@h KICK #room alice :bye"), "#room")
    Unit <- E.must_eq("trav styled peer kick preserves intent", kick_after_intent(":op!u@h KICK #room alice" ++ ctl(2, "") ++ " :bye"), "#room")
    Unit <- E.must("trav live soh-scheme glue never queues/requests/opens", trav_media_glue("htt" ++ ctl(1, "ps://x.test/a.png")))
    Unit <- E.must("trav live style-infixed url never queues/requests/opens", trav_media_glue("https://x.test/a" ++ ctl(2, ".png")))
    Unit <- E.must("trav live genuine styled image queues/requests/opens", trav_media_fetch("pic " ++ ctl(2, img()) ++ " end", img()))
    Unit <- E.must("trav live ordinary image queues/requests/opens", trav_media_fetch("pic " ++ img() ++ " end", img()))
    Unit <- E.must("trav live color-wrapped image queues/requests/opens", trav_media_fetch("see " ++ ctl(3, "04" ++ img()) ++ " end", img()))
    Unit <- E.must("trav styled mode key restores redacted", trav_mode_restore_private(":alice!u@h MODE #room +" ++ ctl(2, "k") ++ " " ++ secret()))
    Unit <- E.must("trav styled 324 key restores redacted", trav_mode_restore_private(":irc 324 me #room +" ++ ctl(2, "k") ++ " " ++ secret()))
    Unit <- E.must("trav nonkey mode restores visible", trav_mode_restore_visible(":alice!u@h MODE #room +o bob", "alice MODE #room +o bob"))
    Unit <- E.must("trav request pins exact url and source id", trav_req_exact("pic " ++ ctl(2, img()) ++ " end", img()))
    Unit <- E.must("trav request pins styled query fragment url", trav_req_exact("see " ++ ctl(2, "https://x.test/a.png?x=1#f") ++ " end", "https://x.test/a.png?x=1#f"))
    Unit <- E.must("trav styled mention raises alert", trav_mention_alert("hi m" ++ ctl(2, "e"), 2))
    Unit <- E.must("trav styled continuation raises activity not mention", trav_mention_alert("me" ++ ctl(2, "ow"), 1))
    Unit <- E.must("trav ordinary mention raises alert", trav_mention_alert("hi me", 2))
    Unit <- E.must("trav styled self-kick reconnect omits room", trav_kick_reconnect_omits(":op!u@h KICK #ro" ++ ctl(2, "om") ++ " me :bye"))
    Unit <- E.must("trav peer kick reconnect keeps room", trav_kick_reconnect_keeps(":op!u@h KICK #room alice :bye"))
    IO.print("g3_traversal=ok")
