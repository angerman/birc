# Buffer container: types, nick lists, find/get/modify, scroll, take_last.
import Base
import ./irc.bend as Irc
import ./diagnostic.bend as Diagnostic

# Negotiated ISUPPORT sets (I2 dynamic): Session supplies chantypes/status
# sigils/casemapping Strings from its iso; fixed wrappers below delegate
# with the long-standing defaults so an absent burst changes nothing.
def has_ch(+s: String, +c: Char) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{+h, +t}: Char.is_eq(h, c) || has_ch(t, c)

def dflt_types() -> String:
  "#&+!"

def dflt_status() -> String:
  "@+"

def dflt_sigils() -> String:
  "@+"

def dflt_strip() -> String:
  "@+~&%"

def dflt_cm() -> String:
  "rfc1459"

# Negotiated identity carried as one value: casemapping, chantypes,
# STATUSMSG, PREFIX sigils, and the roster strip set. Callers used to
# thread those five strings positionally; they are always taken from the
# same ISUPPORT state.
type Iso is Data:
  Iso{cm: String, types: String, status: String, sigils: String, strip: String}

def Iso.defaults() -> Iso:
  Iso{dflt_cm(), dflt_types(), dflt_status(), dflt_sigils(), dflt_strip()}

def iso_cm(+isc: Iso) -> String:
  match isc:
    case Iso{+cm, _, _, _, _}: cm

def iso_types(+isc: Iso) -> String:
  match isc:
    case Iso{_, +types, _, _, _}: types

def iso_status(+isc: Iso) -> String:
  match isc:
    case Iso{_, _, +status, _, _}: status

def iso_sigils(+isc: Iso) -> String:
  match isc:
    case Iso{_, _, _, +sigils, _}: sigils

def iso_strip(+isc: Iso) -> String:
  match isc:
    case Iso{_, _, _, _, +strip}: strip

def buf_eq_cm(+cm: String, +a: String, +b: String) -> Bool:
  String.eq(Irc.fold_casemap(cm, a), Irc.fold_casemap(cm, b))

# Creation and wire/history routing normalize identity before policy checks
# and lookup. Generic local lookup compares the names actually stored.
def target_name.known(+name: String, key: String) -> String:
  match key:
    case "*LOG*": Diagnostic.name()
    case "*SEARCH*": "*search*"
    case "*PREVIEW*": "*preview*"
    case "*SETTINGS*": "*settings*"
    case "*SERVER*": "*server*"
    case _: name

def target_name(+raw: String) -> String:
  +clean = Irc.proto_atom(raw)
  target_name.known(clean, Irc.rfc1459(clean))

def target_channel_with.name(+types: String, +status: String, +sigils: String, +name: String) -> Bool:
  Irc.negotiated_channel(types, status, sigils, name)

def target_channel_with(+types: String, +status: String, +sigils: String, +raw: String) -> Bool:
  target_channel_with.name(types, status, sigils, target_name(raw))

def target_key_with.name(+types: String, +status: String, +sigils: String, +name: String) -> String:
  Irc.negotiated_key(types, status, sigils, name)

def target_key_with(+types: String, +status: String, +sigils: String, +raw: String) -> String:
  target_key_with.name(types, status, sigils, target_name(raw))

# STATUSMSG fallback for a message audience, never for a stored channel name.
# `message_key` first resolves ambiguous audiences against resident channels.
def target_key(+raw: String) -> String:
  target_key_with(dflt_types(), dflt_status(), dflt_sigils(), raw)

def target_is_synthetic(+raw: String) -> Bool:
  String.starts_with(target_name(raw), "*")

def target_channel(+raw: String) -> Bool:
  target_channel_with(dflt_types(), dflt_status(), dflt_sigils(), raw)

def target_wire(+raw: String) -> Bool:
  Bool.not(target_is_synthetic(raw))

# Client and split panes must accept the same normalized NICK event.
def nick_rename_allowed(+from: String, +to: String) -> Bool:
  +old = target_name(from)
  +new = target_name(to)
  Bool.not(String.is_empty(old) || String.is_empty(new)) && target_wire(old) && target_wire(new)

def MAX_BUFFERS() -> Nat:
  16n

# One slot remains available for diagnostics, even after normal buffer floods.
def NORMAL_BUFFERS() -> Nat:
  15n

def SCROLL_CAP() -> Nat:
  1024n

def MAX_NICKS() -> Nat:
  256n

type LineKind is Data:
  Msg{}
  Self{}
  System{}
  Action{}
  Notice{}
  Error{}
  Highlight{}
  Reconnect{}
  LinkResult{}
  Presence{}
  Nick{}
  Day{}
  Pending{inner: LineKind}

# Optimistic-send ledger entry. Lives in the Session (view overlay only);
# fabrication wraps kind in Pending{}. Never enters buffers or history, so
# inner is always a base send kind (Self/Action/Notice) by construction.
# buf/target route the overlay and FIFO fallback; label matches exact
# labeled echoes; wire matches echo bytes; body restores the draft on
# revert; disp renders verbatim; age counts TypingTicks.
type PendSend is Data:
  PendSend{buf: String, target: String, label: String, wire: String, body: String, disp: String, ts: String, kind: LineKind, age: Nat}

def PEND_MAX() -> Nat:
  32n

def PEND_TICKS() -> Nat:
  30n

type Line is Data:
  Line{kind: LineKind, ts: String, text: String, author: String, id: Nat}

# The viewport bottom is anchored to a message and rendered character.
# `after` counts newer logical messages; `tail` counts characters after that
# position within its message. Both zero means follow the live tail.
type Scroll is Data:
  ScrollAt{after: Nat, tail: Nat}

# `lines` stays oldest-first for history. `newest` is the same lines,
# newest-first, so paint and scroll start at the live edge. `count` is
# their length. Appends cons onto `newest`. Middle rewrites and trims
# rebuild both through buf_indexed.
type Buffer is Data:
  Buffer{
    name: String,
    is_channel: Bool,
    topic: String,
    lines: List<&2, Line>,
    nicks: List<&2, String>,
    scroll: Scroll,
    newest: List<&2, Line>,
    count: Nat
  }

def buf_indexed(+name: String, +is_channel: Bool, +topic: String, +lines: List<&2, Line>, +nicks: List<&2, String>, +scroll: Scroll) -> Buffer:
  Buffer{name, is_channel, topic, lines, nicks, scroll, List.reverse(&2, Line, lines), List.length(&2, Line, lines)}

# Scroll changes do not rebuild the line spine.
def buf_with_scroll(+name: String, +ch: Bool, +topic: String, +lines: List<&2, Line>, +nicks: List<&2, String>, +scroll: Scroll, +newest: List<&2, Line>, +count: Nat) -> Buffer:
  Buffer{name, ch, topic, lines, nicks, scroll, newest, count}

# Nick/topic/name edits keep both line spines and count untouched.
def buf_with_meta(+b: Buffer, +name: String, +ch: Bool, +topic: String, +nicks: List<&2, String>) -> Buffer:
  match b:
    case Buffer{_, _, _, +lines, _, +scroll, +newest, +count}:
      Buffer{name, ch, topic, lines, nicks, scroll, newest, count}

# Full LineKind equality, including nested Pending wrappers.
def kind_eq(a: LineKind, b: LineKind) -> Bool:
  match a b:
    case Msg{} Msg{}: True{}
    case Self{} Self{}: True{}
    case System{} System{}: True{}
    case Action{} Action{}: True{}
    case Notice{} Notice{}: True{}
    case Error{} Error{}: True{}
    case Highlight{} Highlight{}: True{}
    case Reconnect{} Reconnect{}: True{}
    case LinkResult{} LinkResult{}: True{}
    case Presence{} Presence{}: True{}
    case Nick{} Nick{}: True{}
    case Day{} Day{}: True{}
    case Pending{ia} Pending{ib}: kind_eq(ia, ib)
    case _ _: False{}

# Dual-spine identity: id, kind, author, text, and ts must all agree.
def line_eq(a: Line, b: Line) -> Bool:
  match a b:
    case Line{ka, tsa, texta, authora, ida} Line{kb, tsb, textb, authorb, idb}:
      Nat.is_eq(ida, idb)
        && kind_eq(ka, kb)
        && String.eq(authora, authorb)
        && String.eq(texta, textb)
        && String.eq(tsa, tsb)

def spine_lines_eq(+a: List<&2, Line>, +b: List<&2, Line>) -> Bool:
  match a:
    case Nil{}:
      match b:
        case Nil{}: True{}
        case _: False{}
    case Con{ha, ta}:
      match b:
        case Nil{}: False{}
        case Con{hb, tb}:
          line_eq(ha, hb) && spine_lines_eq(ta, tb)

# newest must be reverse(lines) and count must be their length.
def buf_spines_ok(+b: Buffer) -> Bool:
  match b:
    case Buffer{_, _, _, +lines, _, _, +newest, +count}:
      Nat.is_eq(count, List.length(&2, Line, lines))
        && Nat.is_eq(count, List.length(&2, Line, newest))
        && spine_lines_eq(newest, List.reverse(&2, Line, lines))

type AlertLevel is Data:
  Activity{}
  Mention{}

type Alert is Data:
  Alert{name: String, level: AlertLevel}

# Credentials stay bound to the initial host and port by the auth profile.
# They are a separate record so a display or alert update does not rebuild
# the password, and a password update does not rebuild the alert list.
type Credentials is Data:
  Credentials{user: String, pass: String}

type Alerts is Data:
  Alerts{unreads: List<&2, Alert>, bell: Bool, bell_seq: U32}

type Settings is Data:
  Settings{joins: Bool, ts: Bool, motd: Bool, history: Bool, hist_cap: U32, autoreconn: Bool, mutes: List<&2, String>, creds: Credentials, alerts: Alerts, lag: U32, nicks: Bool}

def settings0() -> Settings:
  Settings{True{}, True{}, True{}, True{}, 500, False{}, Nil{}, Credentials{"", ""}, Alerts{Nil{}, True{}, 0}, 0, True{}}

def settings_with_cap(cap: U32) -> Settings:
  Settings{True{}, True{}, True{}, True{}, cap, False{}, Nil{}, Credentials{"", ""}, Alerts{Nil{}, True{}, 0}, 0, True{}}

def settings_joins(+s: Settings) -> Bool:
  match s:
    case Settings{joins, _, _, _, _, _, _, Credentials{_, _}, Alerts{_, _, _}, _, _}:
      joins

def settings_nicks(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, _, _, _, _, _, Credentials{_, _}, Alerts{_, _, _}, _, nicks}:
      nicks

def settings_ts(+s: Settings) -> Bool:
  match s:
    case Settings{_, ts, _, _, _, _, _, Credentials{_, _}, Alerts{_, _, _}, _, _}:
      ts

def settings_motd(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, motd, _, _, _, _, Credentials{_, _}, Alerts{_, _, _}, _, _}:
      motd

def settings_history(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, _, history, _, _, _, Credentials{_, _}, Alerts{_, _, _}, _, _}:
      history

def settings_hist_cap(+s: Settings) -> U32:
  match s:
    case Settings{_, _, _, _, cap, _, _, Credentials{_, _}, Alerts{_, _, _}, _, _}:
      cap

def settings_autoreconn(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, _, _, _, auto, _, Credentials{_, _}, Alerts{_, _, _}, _, _}:
      auto

def settings_bell(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, _, _, _, _, _, Credentials{_, _}, Alerts{_, bell, _}, _, _}:
      bell

def settings_bell_seq(+s: Settings) -> U32:
  match s:
    case Settings{_, _, _, _, _, _, _, Credentials{_, _}, Alerts{_, _, seq}, _, _}:
      seq

def settings_mutes(+s: Settings) -> List<&2, String>:
  match s:
    case Settings{_, _, _, _, _, _, +mutes, Credentials{_, _}, Alerts{_, _, _}, _, _}:
      mutes

def settings_unreads(+s: Settings) -> List<&2, Alert>:
  match s:
    case Settings{_, _, _, _, _, _, _, Credentials{_, _}, Alerts{+unreads, _, _}, _, _}:
      unreads

def settings_sasl_user(+s: Settings) -> String:
  match s:
    case Settings{_, _, _, _, _, _, _, Credentials{+su, _}, Alerts{_, _, _}, _, _}:
      su

def settings_sasl_pass(+s: Settings) -> String:
  match s:
    case Settings{_, _, _, _, _, _, _, Credentials{_, +sp}, Alerts{_, _, _}, _, _}:
      sp

def settings_lag(+s: Settings) -> U32:
  match s:
    case Settings{_, _, _, _, _, _, _, Credentials{_, _}, Alerts{_, _, _}, lag, _}:
      lag

def set_joins(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{_, ts, motd, history, cap, auto, +mutes, +creds, +alerts, lag, +nicks}:
      Settings{val, ts, motd, history, cap, auto, mutes, creds, alerts, lag, nicks}

def set_nicks(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, +mutes, +creds, +alerts, lag, _}:
      Settings{joins, ts, motd, history, cap, auto, mutes, creds, alerts, lag, val}

def set_ts(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, _, motd, history, cap, auto, +mutes, +creds, +alerts, lag, +nicks}:
      Settings{joins, val, motd, history, cap, auto, mutes, creds, alerts, lag, nicks}

def set_motd(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, _, history, cap, auto, +mutes, +creds, +alerts, lag, +nicks}:
      Settings{joins, ts, val, history, cap, auto, mutes, creds, alerts, lag, nicks}

def set_history(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, motd, _, cap, auto, +mutes, +creds, +alerts, lag, +nicks}:
      Settings{joins, ts, motd, val, cap, auto, mutes, creds, alerts, lag, nicks}

def set_hist_cap(+s: Settings, val: U32) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, _, auto, +mutes, +creds, +alerts, lag, +nicks}:
      Settings{joins, ts, motd, history, val, auto, mutes, creds, alerts, lag, nicks}

def set_autoreconn(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, _, +mutes, +creds, +alerts, lag, +nicks}:
      Settings{joins, ts, motd, history, cap, val, mutes, creds, alerts, lag, nicks}

def set_bell(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, +mutes, +creds, Alerts{+unreads, _, seq}, lag, +nicks}:
      Settings{joins, ts, motd, history, cap, auto, mutes, creds, Alerts{unreads, val, seq}, lag, nicks}

def advance_bell(+s: Settings) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, +mutes, +creds, Alerts{+unreads, bell, seq}, lag, +nicks}:
      Settings{joins, ts, motd, history, cap, auto, mutes, creds, Alerts{unreads, bell, U32.add(seq, 1)}, lag, nicks}

def set_mutes(+s: Settings, +val: List<&2, String>) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, _, +creds, +alerts, lag, +nicks}:
      Settings{joins, ts, motd, history, cap, auto, val, creds, alerts, lag, nicks}

def set_unreads(+s: Settings, +val: List<&2, Alert>) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, +mutes, +creds, Alerts{_, bell, seq}, lag, +nicks}:
      Settings{joins, ts, motd, history, cap, auto, mutes, creds, Alerts{val, bell, seq}, lag, nicks}

def set_sasl_user(+s: Settings, +val: String) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, +mutes, Credentials{_, +sp}, +alerts, lag, +nicks}:
      Settings{joins, ts, motd, history, cap, auto, mutes, Credentials{val, sp}, alerts, lag, nicks}

def set_sasl_pass(+s: Settings, +val: String) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, +mutes, Credentials{+su, _}, +alerts, lag, +nicks}:
      Settings{joins, ts, motd, history, cap, auto, mutes, Credentials{su, val}, alerts, lag, nicks}

def set_lag(+s: Settings, lag: U32) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, +mutes, +creds, +alerts, _, +nicks}:
      Settings{joins, ts, motd, history, cap, auto, mutes, creds, alerts, lag, nicks}

def set_bell_seq(+s: Settings, seq: U32) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, +mutes, +creds, Alerts{+unreads, bell, _}, lag, +nicks}:
      Settings{joins, ts, motd, history, cap, auto, mutes, creds, Alerts{unreads, bell, seq}, lag, nicks}

# Mute matching sole owner (I2-DRY): identity comparisons fold under the
# given CASEMAPPING; fixed wrappers delegate with the default mapping.
# Placed early: render filtering below needs it before is_muted_client.
def mute_match_cm(+cm: String, +m: String, +from: String, +chan: String, +server: String) -> Bool:
  buf_eq_cm(cm, m, from)
    || buf_eq_cm(cm, m, from ++ chan)
    || buf_eq_cm(cm, m, from ++ "@" ++ server)
    || buf_eq_cm(cm, m, from ++ chan ++ "@" ++ server)
    || buf_eq_cm(cm, m, from ++ "*@" ++ server)

def is_muted_list_cm(+cm: String, mutes: List<&2, String>, +from: String, +chan: String, +server: String) -> Bool:
  match mutes:
    case Nil{}: False{}
    case Con{+m, t}:
      mute_match_cm(cm, m, from, chan, server) || is_muted_list_cm(cm, t, from, chan, server)

def mute_match(+m: String, +from: String, +chan: String, +server: String) -> Bool:
  mute_match_cm(dflt_cm(), m, from, chan, server)

def is_muted_list(mutes: List<&2, String>, +from: String, +chan: String, +server: String) -> Bool:
  is_muted_list_cm(dflt_cm(), mutes, from, chan, server)

def add_mute_list(mutes: List<&2, String>, +pat: String) -> List<&2, String>:
  pat <> mutes

# Scoped patterns use the same channel types as IRC routing. Extract the nick
# once so restored-line filtering and /unmute agree on every supported scope.
def is_mute_sep_with(+types: String, +c: Char) -> Bool:
  has_ch(types, c) || Char.is_eq(c, '*') || Char.is_eq(c, '@')

def is_mute_sep(+c: Char) -> Bool:
  is_mute_sep_with(dflt_types(), c)

def mute_pat_nick.fin(+h: Char, r: String, is_sep: Bool) -> String:
  match is_sep:
    case True{}: ""
    case False{}: SCon{h, r}

def mute_pat_nick_with(+types: String, s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+h, +t}:
      mute_pat_nick.fin(h, mute_pat_nick_with(types, t), is_mute_sep_with(types, h))

def mute_pat_nick(s: String) -> String:
  mute_pat_nick_with(dflt_types(), s)

def del_mute_list.rest(tail: List<&2, String>, +m: String, hit: Bool) -> List<&2, String>:
  match hit:
    case True{}:
      tail
    case False{}:
      m <> tail

def del_mute_list_with(+types: String, mutes: List<&2, String>, +pat: String) -> List<&2, String>:
  match mutes:
    case Nil{}: Nil{}
    case Con{+m, t}:
      +hit = Irc.ieq(m, pat) || Irc.ieq(mute_pat_nick_with(types, m), pat)
      del_mute_list.rest(del_mute_list_with(types, t, pat), m, hit)

def del_mute_list(mutes: List<&2, String>, +pat: String) -> List<&2, String>:
  del_mute_list_with(dflt_types(), mutes, pat)

# Render filtering sole owner (I2-DRY): view mute checks fold the pattern,
# author, and channel under the given CASEMAPPING; fixed wrappers delegate
# with the default mapping.
def line_from_nick_kind_cm(+cm: String, kind: LineKind, +author: String, +nick: String) -> Bool:
  match kind:
    case Msg{}: buf_eq_cm(cm, author, nick)
    case Self{}: buf_eq_cm(cm, author, nick)
    case Action{}: buf_eq_cm(cm, author, nick)
    case Notice{}: buf_eq_cm(cm, author, nick)
    case Highlight{}: buf_eq_cm(cm, author, nick)
    case Pending{+inner}: line_from_nick_kind_cm(cm, inner, author, nick)
    case _: False{}

def line_from_nick_cm(+cm: String, +ln: Line, +nick: String) -> Bool:
  match ln:
    case Line{kind, _, _, +author, _}:
      line_from_nick_kind_cm(cm, kind, author, nick)

def is_line_muted_pat_with(+cm: String, +types: String, +m: String, +ln: Line, +chan: String, +server: String) -> Bool:
  +nick = mute_pat_nick_with(types, m)
  mute_match_cm(cm, m, nick, chan, server) && line_from_nick_cm(cm, ln, nick)

def is_line_muted_with(+cm: String, +types: String, mutes: List<&2, String>, +ln: Line, +chan: String, +server: String) -> Bool:
  match mutes:
    case Nil{}: False{}
    case Con{+m, t}:
      is_line_muted_pat_with(cm, types, m, ln, chan, server) || is_line_muted_with(cm, types, t, ln, chan, server)

def is_line_muted_pat_cm(+cm: String, +m: String, +ln: Line, +chan: String, +server: String) -> Bool:
  is_line_muted_pat_with(cm, dflt_types(), m, ln, chan, server)

def is_line_muted_cm(+cm: String, mutes: List<&2, String>, +ln: Line, +chan: String, +server: String) -> Bool:
  is_line_muted_with(cm, dflt_types(), mutes, ln, chan, server)

def line_from_nick(+ln: Line, +nick: String) -> Bool:
  line_from_nick_cm(dflt_cm(), ln, nick)

def is_line_muted_pat(+m: String, +ln: Line, +chan: String, +server: String) -> Bool:
  is_line_muted_pat_cm(dflt_cm(), m, ln, chan, server)

def is_line_muted(mutes: List<&2, String>, +ln: Line, +chan: String, +server: String) -> Bool:
  is_line_muted_cm(dflt_cm(), mutes, ln, chan, server)

def filter_muted_lines.rest(tail: List<&2, Line>, +ln: Line, muted: Bool) -> List<&2, Line>:
  match muted:
    case True{}: tail
    case False{}: ln <> tail

def filter_muted_lines_with(+cm: String, +types: String, lines: List<&2, Line>, +mutes: List<&2, String>, +chan: String, +server: String) -> List<&2, Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+ln, t}:
      filter_muted_lines.rest(filter_muted_lines_with(cm, types, t, mutes, chan, server), ln, is_line_muted_with(cm, types, mutes, ln, chan, server))

def filter_muted_lines_iso(+isc: Iso, lines: List<&2, Line>, +mutes: List<&2, String>, +chan: String, +server: String) -> List<&2, Line>:
  filter_muted_lines_with(iso_cm(isc), iso_types(isc), lines, mutes, chan, server)

def filter_muted_lines_cm(+cm: String, lines: List<&2, Line>, +mutes: List<&2, String>, +chan: String, +server: String) -> List<&2, Line>:
  filter_muted_lines_with(cm, dflt_types(), lines, mutes, chan, server)

def filter_muted_lines(lines: List<&2, Line>, +mutes: List<&2, String>, +chan: String, +server: String) -> List<&2, Line>:
  filter_muted_lines_cm(dflt_cm(), lines, mutes, chan, server)

# Retroactive presence filtering: joins/parts/quits log Presence rows and
# nick changes log Nick rows; the view cascade drops them when the matching
# setting is off. Mutes still apply first; every other kind always shows.
def is_presence(kind: LineKind) -> Bool:
  match kind:
    case Presence{}: True{}
    case Pending{+inner}: is_presence(inner)
    case _: False{}

def is_nick(kind: LineKind) -> Bool:
  match kind:
    case Nick{}: True{}
    case Pending{+inner}: is_nick(inner)
    case _: False{}

def kind_shown(+joins: Bool, +nicks: Bool, kind: LineKind) -> Bool:
  match kind:
    case Presence{}: joins
    case Nick{}: nicks
    case Pending{+inner}: kind_shown(joins, nicks, inner)
    case _: True{}

def line_shown(+joins: Bool, +nicks: Bool, +ln: Line) -> Bool:
  match ln:
    case Line{+kind, _, _, _, _}: kind_shown(joins, nicks, kind)

def filter_kinds.rest(tail: List<&2, Line>, +ln: Line, show: Bool) -> List<&2, Line>:
  match show:
    case True{}: ln <> tail
    case False{}: tail

def filter_kinds(lines: List<&2, Line>, +joins: Bool, +nicks: Bool) -> List<&2, Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+ln, t}:
      filter_kinds.rest(filter_kinds(t, joins, nicks), ln, line_shown(joins, nicks, ln))

def is_nick_char(+c: Char) -> Bool:
  match c:
    case Chr{n}:
      (U32.is_ge(n, 48) && U32.is_le(n, 57))
        || (U32.is_ge(n, 65) && U32.is_le(n, 90))
        || (U32.is_ge(n, 97) && U32.is_le(n, 122))
        || U32.is_eq(n, 45)
        || (U32.is_ge(n, 91) && U32.is_le(n, 96))
        || (U32.is_ge(n, 123) && U32.is_le(n, 125))

def mention_right_bound(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, _}: Bool.not(is_nick_char(h))

def str_mentions.hit(+s: String, +needle: String, left_ok: Bool) -> Bool:
  left_ok
    && String.starts_with(s, needle)
    && mention_right_bound(String.drop(s, String.length(needle)))

def str_mentions(s: String, +needle: String, left_ok: Bool) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{+h, +t}:
      str_mentions.hit(SCon{h, t}, needle, left_ok)
        || str_mentions(t, needle, Bool.not(is_nick_char(h)))

# Negotiated mention fold (I2-dynamic3 R3): body and nick compare under the
# Session CASEMAPPING through the shared fold owner, so a nick that only
# folds under the default mapping never highlights. Fixed is_mention keeps
# law behavior by delegating with the default mapping.
def is_mention_cm.on(empty: Bool, +cm: String, +body: String, +nick: String) -> Bool:
  match empty:
    case True{}: False{}
    case False{}:
      str_mentions(Irc.fold_casemap(cm, Irc.proto_atom(body)), Irc.fold_casemap(cm, nick), True{})

def is_mention_cm(+cm: String, +body: String, +nick: String) -> Bool:
  is_mention_cm.on(String.is_empty(nick), cm, body, nick)

def is_mention(+body: String, +nick: String) -> Bool:
  is_mention_cm(dflt_cm(), body, nick)

def alert_status(level: AlertLevel) -> U32:
  match level:
    case Activity{}: 1
    case Mention{}: 2

def buf_unread_status.item(hit: Bool, level: AlertLevel) -> U32:
  match hit:
    case True{}: alert_status(level)
    case False{}: 0

def buf_unread_status.pick(ge: Bool, +s1: U32, +s2: U32) -> U32:
  match ge:
    case True{}: s1
    case False{}: s2

def buf_unread_status.max(+s1: U32, +s2: U32) -> U32:
  buf_unread_status.pick(U32.is_ge(s1, s2), s1, s2)

def del_unread_items.hit(tail: List<&2, Alert>, +u: Alert, hit: Bool) -> List<&2, Alert>:
  match hit:
    case True{}: tail
    case False{}: u <> tail

def rename_unreads.put(has: Bool, unreads: List<&2, Alert>, name: String, level: AlertLevel) -> List<&2, Alert>:
  match has:
    case False{}: unreads
    case True{}: Alert{name, level} <> unreads

# Unread identity/mutation sole owner (I2-DRY): status, delete, add, and
# NICK rename all compare under the given CASEMAPPING; fixed wrappers
# delegate with the default mapping. Distinct fold-siblings retain separate
# alerts; repeat same-channel coalesces only itself.
def buf_unread_status_cm(+cm: String, unreads: List<&2, Alert>, +name: String) -> U32:
  match unreads:
    case Nil{}: 0
    case Con{Alert{+target, level}, t}:
      buf_unread_status.max(buf_unread_status.item(buf_eq_cm(cm, target, name), level), buf_unread_status_cm(cm, t, name))

def del_unread_items_cm(+cm: String, unreads: List<&2, Alert>, +name: String) -> List<&2, Alert>:
  match unreads:
    case Nil{}: Nil{}
    case Con{+u, t}:
      match u:
        case Alert{+target, _}:
          del_unread_items.hit(del_unread_items_cm(cm, t, name), u, buf_eq_cm(cm, target, name))

def add_unread_item_cm(+cm: String, +unreads: List<&2, Alert>, +name: String, level: AlertLevel) -> List<&2, Alert>:
  Alert{name, level} <> del_unread_items_cm(cm, unreads, name)

def rename_unreads_cm(+cm: String, +unreads: List<&2, Alert>, +from: String, +to: String) -> List<&2, Alert>:
  +level = buf_unread_status.max(buf_unread_status_cm(cm, unreads, from), buf_unread_status_cm(cm, unreads, to))
  rename_unreads.put(U32.is_gt(level, 0), del_unread_items_cm(cm, del_unread_items_cm(cm, unreads, from), to), to,
    Bool.pick(AlertLevel, U32.is_eq(level, 2), Mention{}, Activity{}))

def buf_unread_status(unreads: List<&2, Alert>, +name: String) -> U32:
  buf_unread_status_cm(dflt_cm(), unreads, name)

def del_unread_items(unreads: List<&2, Alert>, +name: String) -> List<&2, Alert>:
  del_unread_items_cm(dflt_cm(), unreads, name)

def add_unread_item(+unreads: List<&2, Alert>, +name: String, level: AlertLevel) -> List<&2, Alert>:
  add_unread_item_cm(dflt_cm(), unreads, name, level)

def rename_unreads(+unreads: List<&2, Alert>, +from: String, +to: String) -> List<&2, Alert>:
  rename_unreads_cm(dflt_cm(), unreads, from, to)

def purge_nick_lines.rest(tail: List<&2, Line>, +h: Line, hit: Bool) -> List<&2, Line>:
  match hit:
    case True{}:
      tail
    case False{}:
      h <> tail

def purge_nick_lines(lines: List<&2, Line>, +nick: String) -> List<&2, Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      purge_nick_lines.rest(purge_nick_lines(t, nick), h, line_from_nick(h, nick))

# Edits change the count of newer messages, not the identity of the retained
# viewport bottom. If that message is removed, use the nearest older message.
def reanchor_lines.id(lines: List<&2, Line>, index: Nat) -> Maybe<&2, Nat>:
  match lines:
    case Nil{}: None{}
    case Con{Line{_, _, _, _, id}, t}:
      match index:
        case 0n: Some{id}
        case 1n+p: reanchor_lines.id(t, p)

def reanchor_lines.find.hit(hit: Bool, +id: Nat, +target: Nat, tail: Nat, after: Nat, rest: Maybe<&2, Scroll>) -> Maybe<&2, Scroll>:
  match hit:
    case False{}: rest
    case True{}: Some{ScrollAt{after, Bool.pick(Nat, Nat.is_eq(id, target), tail, 0n)}}

def reanchor_lines.find(lines: List<&2, Line>, +target: Nat, +tail: Nat, +after: Nat) -> Maybe<&2, Scroll>:
  match lines:
    case Nil{}: None{}
    case Con{Line{_, _, _, _, +id}, t}:
      reanchor_lines.find.hit(Nat.is_gt(id, 0n) && Nat.is_le(id, target), id, target, tail, after,
        reanchor_lines.find(t, target, tail, Nat.add(after, 1n)))

def reanchor_lines.identified(zero: Bool, +lines: List<&2, Line>, id: Nat, +scroll: Scroll) -> Scroll:
  match zero:
    # Unassigned fixture lines have no stable identity yet.
    case True{}: scroll
    case False{}:
      match scroll:
        case ScrollAt{_, tail}:
          Maybe.default(&2, Scroll,
            reanchor_lines.find(List.reverse(&2, Line, lines), id, tail, 0n),
            ScrollAt{Nat.sub(List.length(&2, Line, lines), 1n), 0n})

def reanchor_lines.got(lines: List<&2, Line>, scroll: Scroll, got: Maybe<&2, Nat>) -> Scroll:
  match got:
    case None{}: ScrollAt{0n, 0n}
    case Some{+id}: reanchor_lines.identified(Nat.is_eq(id, 0n), lines, id, scroll)

def reanchor_lines(+old: List<&2, Line>, lines: List<&2, Line>, scroll: Scroll) -> Scroll:
  match scroll:
    case ScrollAt{0n, 0n}: ScrollAt{0n, 0n}
    case ScrollAt{+after, +tail}:
      +index = Nat.sub(List.length(&2, Line, old), Nat.add(1n, after))
      reanchor_lines.got(lines, ScrollAt{after, tail}, reanchor_lines.id(old, index))

def purge_nick_buf(b: Buffer, +nick: String) -> Buffer:
  match b:
    case Buffer{name, is_ch, topic, +lines, nicks, scroll, _, _}:
      +kept = purge_nick_lines(lines, nick)
      buf_indexed(name, is_ch, topic, kept, nicks, reanchor_lines(lines, kept, scroll))

type AuthMode is Data:
  SaslOnly{}
  NickServOnly{}
  SaslNickServ{}

type AuthConfig is Data:
  AuthDisabled{}
  AuthConfig{mode: AuthMode, host: String, port: U32, prefix: String, success: String}

# Flat SASL spot. Must not be AuthPhase: a phase inside a phase makes
# C codegen recurse until the process is killed.
type AuthHold is Data:
  HoldCap{}
  HoldChallenge{}
  HoldResult{}

type AuthPhase is Data:
  AuthIdle{}
  AuthCap{}
  AuthChallenge{}
  AuthResult{}
  AuthDone{}
  # Registration (001) before SASL completed: not success, not failure.
  # `resume` is the SASL spot that must still accept later controls.
  AuthHeld{resume: AuthHold}
  AuthNickWait{}
  AuthNickProbe{}
  AuthNickResult{}
  AuthProfile{phase: AuthPhase, config: AuthConfig, success_seq: Nat}

# The profile is one wrapper in production. Keep the old phase seam and all
# container arities, while configuration and success survive phase updates.
def auth_phase(phase: AuthPhase) -> AuthPhase:
  match phase:
    case AuthProfile{inner, _, _}: auth_phase(inner)
    case _: phase

def auth_config(phase: AuthPhase) -> AuthConfig:
  match phase:
    case AuthProfile{_, config, _}: config
    case _: AuthDisabled{}

def auth_seq(phase: AuthPhase) -> Nat:
  match phase:
    case AuthProfile{_, _, seq}: seq
    case _: 0n

def auth_phase_set(state: AuthPhase, phase: AuthPhase) -> AuthPhase:
  match state:
    case AuthProfile{_, config, seq}: AuthProfile{auth_phase(phase), config, seq}
    case _: auth_phase(phase)

def auth_seq_advance(state: AuthPhase) -> AuthPhase:
  match state:
    case AuthProfile{phase, config, seq}: AuthProfile{phase, config, Nat.add(seq, 1n)}
    case _: state

type Client is Data:
  Client{
    nick: String,
    server: String,
    bufs: List<&2, Buffer>,
    active: Nat,
    now: String,
    settings: Settings,
    auth: AuthPhase,
    log_seq: Nat
  }

def get_auth(+cl: Client) -> AuthPhase:
  match cl:
    case Client{_, _, _, _, _, _, auth, _}: auth_phase(auth)

def client_auth_config(+cl: Client) -> AuthConfig:
  match cl:
    case Client{_, _, _, _, _, _, auth, _}: auth_config(auth)

def auth_success_seq(+cl: Client) -> Nat:
  match cl:
    case Client{_, _, _, _, _, _, auth, _}: auth_seq(auth)

def auth_config_prefix(config: AuthConfig) -> String:
  match config:
    case AuthDisabled{}: ""
    case AuthConfig{_, _, _, prefix, _}: prefix

def client_auth_prefix(+cl: Client) -> String:
  auth_config_prefix(client_auth_config(cl))

def client_auth_service(+cl: Client) -> String:
  Irc.nick_of_prefix(client_auth_prefix(cl))

def set_auth_state(+cl: Client, state: AuthPhase) -> Client:
  match cl:
    case Client{nick, server, bufs, active, now, stg, _, seq}:
      Client{nick, server, bufs, active, now, stg, state, seq}

def set_auth(+cl: Client, phase: AuthPhase) -> Client:
  match cl:
    case Client{nick, server, bufs, active, now, stg, auth, seq}:
      Client{nick, server, bufs, active, now, stg, auth_phase_set(auth, phase), seq}

def advance_auth_success(+cl: Client) -> Client:
  match cl:
    case Client{nick, server, bufs, active, now, stg, auth, seq}:
      Client{nick, server, bufs, active, now, stg, auth_seq_advance(auth), seq}

def log_seq_of(+cl: Client) -> Nat:
  match cl:
    case Client{_, _, _, _, _, _, _, seq}: seq

def set_log_seq(+cl: Client, +seq: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, _}:
      Client{nick, server, bufs, active, now, stg, auth, seq}

def is_muted_client_cm(+cm: String, +cl: Client, +from: String, +chan: String) -> Bool:
  match cl:
    case Client{_, +server, _, _, _, +stg, +auth, +log_seq}:
      is_muted_list_cm(cm, settings_mutes(stg), from, chan, server)

def is_muted_client(+cl: Client, +from: String, +chan: String) -> Bool:
  is_muted_client_cm(dflt_cm(), cl, from, chan)

def add_mute_client(+cl: Client, +pat: String) -> Client:
  match cl:
    case Client{+nick, +server, bufs, active, now, +stg, +auth, +log_seq}:
      Client{nick, server, bufs, active, now, set_mutes(stg, add_mute_list(settings_mutes(stg), pat)), auth, log_seq}

def del_mute_client(+cl: Client, +pat: String) -> Client:
  match cl:
    case Client{+nick, +server, bufs, active, now, +stg, +auth, +log_seq}:
      Client{nick, server, bufs, active, now, set_mutes(stg, del_mute_list(settings_mutes(stg), pat)), auth, log_seq}

def del_mute_client_iso(+cl: Client, +isc: Iso, +pat: String) -> Client:
  match cl:
    case Client{+nick, +server, bufs, active, now, +stg, +auth, +log_seq}:
      Client{nick, server, bufs, active, now, set_mutes(stg, del_mute_list_with(iso_types(isc), settings_mutes(stg), pat)), auth, log_seq}

# ---- init ---------------------------------------------------------------

def server_buf() -> Buffer:
  buf_indexed("server", False{}, "", Nil{}, Nil{}, ScrollAt{0n, 0n})

def init(+nick: String, +server: String) -> Client:
  Client{nick, server, server_buf() <> Nil{}, 0n, "", settings0(), AuthIdle{}, 0n}

def init_with_cap(+nick: String, +server: String, cap: U32) -> Client:
  Client{nick, server, server_buf() <> Nil{}, 0n, "", settings_with_cap(cap), AuthIdle{}, 0n}

def get_settings(+cl: Client) -> Settings:
  match cl:
    case Client{_, _, _, _, _, +stg, +auth, +log_seq}:
      stg

def set_settings(+cl: Client, +stg: Settings) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, _, +auth, +log_seq}:
      Client{nick, server, bufs, active, now, stg, auth, log_seq}

def client_sasl_user(+cl: Client) -> String:
  settings_sasl_user(get_settings(cl))

def client_sasl_pass(+cl: Client) -> String:
  settings_sasl_pass(get_settings(cl))

def client_lag(+cl: Client) -> U32:
  settings_lag(get_settings(cl))

def client_bell_seq(+cl: Client) -> U32:
  settings_bell_seq(get_settings(cl))

def advance_client_bell(+cl: Client) -> Client:
  set_settings(cl, advance_bell(get_settings(cl)))

def client_set_lag(+cl: Client, lag: U32) -> Client:
  set_settings(cl, set_lag(get_settings(cl), lag))

def auth_mode_sasl(mode: AuthMode) -> Bool:
  match mode:
    case NickServOnly{}: False{}
    case _: True{}

def auth_initial_mode(mode: AuthMode) -> AuthPhase:
  match mode:
    case NickServOnly{}: AuthNickWait{}
    case _: AuthCap{}

def auth_initial_config(config: AuthConfig) -> AuthPhase:
  match config:
    case AuthDisabled{}: AuthIdle{}
    case AuthConfig{mode, _, _, _, _}: auth_initial_mode(mode)

def auth_initial(has: Bool, config: AuthConfig) -> AuthPhase:
  match has:
    case False{}: AuthIdle{}
    case True{}: auth_initial_config(config)

def client_credentials(+cl: Client, +u: String, +p: String) -> Client:
  set_settings(cl, set_sasl_pass(set_sasl_user(get_settings(cl), u), p))

def client_set_auth(+cl: Client, +mode: AuthMode, +host: String, +port: U32, +prefix: String, +success: String, +u: String, +p: String) -> Client:
  +config: AuthConfig = AuthConfig{mode, host, port, prefix, success}
  +ready = Bool.not(String.is_empty(u) || String.is_empty(p))
  set_auth_state(client_credentials(cl, u, p), AuthProfile{auth_initial(ready, config), config, 0n})

def client_set_sasl(+cl: Client, +u: String, +p: String) -> Client:
  match cl:
    case Client{_, +server, _, _, _, _, _, _}:
      client_set_auth(cl, SaslOnly{}, server, 6667, "", "", u, p)

def auth_config_sasl(config: AuthConfig) -> Bool:
  match config:
    case AuthDisabled{}: False{}
    case AuthConfig{mode, _, _, _, _}: auth_mode_sasl(mode)

def client_has_credentials(+cl: Client) -> Bool:
  Bool.not(String.is_empty(client_sasl_user(cl))) && Bool.not(String.is_empty(client_sasl_pass(cl)))

def client_has_sasl(+cl: Client) -> Bool:
  client_has_credentials(cl) && auth_config_sasl(client_auth_config(cl))

def reset_auth(+cl: Client) -> Client:
  set_auth(cl, auth_initial(client_has_credentials(cl), client_auth_config(cl)))

def clear_auth(+cl: Client) -> Client:
  set_auth_state(client_credentials(cl, "", ""), AuthProfile{AuthIdle{}, AuthDisabled{}, auth_success_seq(cl)})

def scope_auth_endpoint.allowed(same: Bool, +cl: Client) -> Client:
  match same:
    case True{}: cl
    case False{}: clear_auth(cl)

def scope_auth_endpoint.config(config: AuthConfig, +cl: Client, +host: String, +port: U32) -> Client:
  match config:
    case AuthDisabled{}: clear_auth(cl)
    case AuthConfig{_, wanted, p, _, _}:
      scope_auth_endpoint.allowed(String.eq(wanted, host) && U32.is_eq(p, port), cl)

def scope_auth_endpoint(+cl: Client, +host: String, +port: U32) -> Client:
  scope_auth_endpoint.config(client_auth_config(cl), cl, host, port)

# ---- list helpers -------------------------------------------------------

def nth_buf(+bufs: List<&2, Buffer>, +i: Nat) -> Maybe<&2, Buffer>:
  List.get(&2, Buffer, bufs, i)

def buf_modify(xs: List<&2, Buffer>, n: Nat, f: Buffer -> Buffer) -> List<&2, Buffer>:
  match xs n:
    case Nil{} _:
      Nil{}
    case h <> t 0n:
      f(h) <> t
    case h <> t 1n+p:
      h <> buf_modify(t, p, f)

def buf_count(+bufs: List<&2, Buffer>) -> Nat:
  List.length(&2, Buffer, bufs)

def buf_clear(b: Buffer) -> Buffer:
  match b:
    case Buffer{+name, is_channel, +topic, _, +nicks, _, _, _}:
      buf_indexed(name, is_channel, topic, Nil{}, nicks, ScrollAt{0n, 0n})

def buf_clear_at(+cl: Client, +i: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, buf_modify(bufs, i, buf_clear), active, now, stg, auth, log_seq}

def buf_set_lines(+lines: List<&2, Line>, b: Buffer) -> Buffer:
  match b:
    case Buffer{+name, is_channel, +topic, _, +nicks, _, _, _}:
      +kept = List.drop(
        &2,
        Line,
        lines,
        Nat.sub(List.length(&2, Line, lines), SCROLL_CAP())
      )
      buf_indexed(name, is_channel, topic, kept, nicks, ScrollAt{0n, 0n})

def buf_set_lines_fn(lines: List<&2, Line>, b: Buffer) -> Buffer:
  buf_set_lines(lines, b)

def buf_set_lines_at(+cl: Client, +i: Nat, lines: List<&2, Line>) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, buf_modify(bufs, i, buf_set_lines_fn(lines)), active, now, stg, auth, log_seq}

def mark_unread.level(is_hl: Bool) -> AlertLevel:
  match is_hl:
    case True{}: Mention{}
    case False{}: Activity{}

# Mark sole owner (I2-DRY): check/status/add all compare under the given
# CASEMAPPING through the shared _cm owners, so a plain message to one
# sibling never inherits its fold-sibling Mention and never deletes it.
# Repeat same-channel coalesces only itself. Fixed wrappers delegate with
# the default mapping; negotiated writes call mark_unread_idx_cm.
def mark_unread.check_cm(+cm: String, is_server: Bool, is_hl: Bool, +name: String, +stg: Settings) -> Settings:
  match is_server:
    case True{}: stg
    case False{}:
      +unreads = settings_unreads(stg)
      set_unreads(stg, add_unread_item_cm(cm, unreads, name, mark_unread.level(is_hl || U32.is_eq(buf_unread_status_cm(cm, unreads, name), 2))))

def mark_unread.buf_cm(+cm: String, got: Maybe<&2, Buffer>, is_hl: Bool, +stg: Settings) -> Settings:
  match got:
    case None{}: stg
    case Some{b}:
      match b:
        case Buffer{+name, _, _, _, _, _, _, _}:
          mark_unread.check_cm(cm, False{}, is_hl, name, stg)

def mark_unread_idx.on_cm(+cm: String, is_active: Bool, got: Maybe<&2, Buffer>, is_hl: Bool, +stg: Settings) -> Settings:
  match is_active:
    case True{}: stg
    case False{}: mark_unread.buf_cm(cm, got, is_hl, stg)

def mark_unread_idx_cm(+cm: String, +cl: Client, +i: Nat, is_hl: Bool) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +act, +now, +stg, +auth, +log_seq}:
      +stg2 = mark_unread_idx.on_cm(cm, Nat.is_eq(i, act) || Nat.is_eq(i, 0n), nth_buf(bufs, i), is_hl, stg)
      Client{nick, server, bufs, act, now, stg2, auth, log_seq}

def mark_unread.check(is_server: Bool, is_hl: Bool, +name: String, +stg: Settings) -> Settings:
  mark_unread.check_cm(dflt_cm(), is_server, is_hl, name, stg)

def mark_unread_idx(+cl: Client, +i: Nat, is_hl: Bool) -> Client:
  mark_unread_idx_cm(dflt_cm(), cl, i, is_hl)

# ---- buffer find/get ----------------------------------------------------

# Skip index 0 (the server buffer). First later match wins.
# One recursive call per step: Bool.pick evaluates both arms, so a recurse
# in each arm is exponential in the buffer count (X1 / I7).
def buf_find.rest(cont: Maybe<&2, Nat>, hit: Bool, +i: Nat) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      cont

def buf_find_cm.go(xs: List<&2, Buffer>, +cm: String, +name: String, +i: Nat) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case Con{h, +t}:
      match h:
        case Buffer{+n, _, _, _, _, _, _, _}:
          buf_find.rest(buf_find_cm.go(t, cm, name, 1n+i), buf_eq_cm(cm, n, name), i)

def buf_find_cm.skip0(xs: List<&2, Buffer>, +cm: String, +name: String) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case Con{_, t}:
      buf_find_cm.go(t, cm, name, 1n)

def buf_find_cm(+cl: Client, +cm: String, +name: String) -> Maybe<&2, Nat>:
  match cl:
    case Client{_, _, +bufs, _, _, _, +auth, +log_seq}:
      buf_find_cm.skip0(bufs, cm, name)

def buf_find(+cl: Client, +name: String) -> Maybe<&2, Nat>:
  buf_find_cm(cl, dflt_cm(), name)

# A + channel may itself be named +#room. At message boundaries, prefer an
# exact resident channel to interpreting its leading + as a STATUSMSG prefix.
# @ cannot begin a channel name, so @#room always remains an audience alias.
def message_key.resident(+name: String, got: Maybe<&2, Buffer>) -> String:
  match got:
    case Some{Buffer{_, channel, _, _, _, _, _, _}}: Bool.pick(String, channel, name, target_key(name))
    case None{}: target_key(name)

def message_key.found(+cl: Client, +name: String, found: Maybe<&2, Nat>) -> String:
  match cl:
    case Client{_, _, bufs, _, _, _, _, _}:
      match found:
        case None{}: target_key(name)
        case Some{i}: message_key.resident(name, nth_buf(bufs, i))

def message_key.head(+cl: Client, +name: String, actual_channel: Bool) -> String:
  match actual_channel:
    case False{}: target_key(name)
    case True{}: message_key.found(cl, name, buf_find(cl, name))

def message_key.name(+cl: Client, +name: String) -> String:
  match name:
    case SNil{}: ""
    case SCon{+h, +t}: message_key.head(cl, SCon{h, t}, Irc.is_chan_type(h))

def message_key(+cl: Client, +raw: String) -> String:
  message_key.name(cl, target_name(raw))

def message_key_with.resident(+types: String, +status: String, +sigils: String, +name: String, got: Maybe<&2, Buffer>) -> String:
  match got:
    case Some{Buffer{+bufname, channel, _, _, _, _, _, _}}:
      # Resident channels keep the stored buffer spelling so pending overlays
      # and casemap aliases paint on the open tab, not the typed wire form.
      Bool.pick(String, channel, bufname, target_key_with(types, status, sigils, name))
    case None{}: target_key_with(types, status, sigils, name)

def message_key_with.found(+cl: Client, +isc: Iso, +name: String, found: Maybe<&2, Nat>) -> String:
  match cl:
    case Client{_, _, bufs, _, _, _, _, _}:
      match found:
        case None{}: target_key_with(iso_types(isc), iso_status(isc), iso_sigils(isc), name)
        case Some{i}: message_key_with.resident(iso_types(isc), iso_status(isc), iso_sigils(isc), name, nth_buf(bufs, i))

def message_key_with.head(+cl: Client, +isc: Iso, +name: String, actual_channel: Bool) -> String:
  match actual_channel:
    case False{}: target_key_with(iso_types(isc), iso_status(isc), iso_sigils(isc), name)
    case True{}: message_key_with.found(cl, isc, name, buf_find_cm(cl, iso_cm(isc), name))

def message_key_with.name(+cl: Client, +isc: Iso, +name: String) -> String:
  match name:
    case SNil{}: ""
    case SCon{+h, +t}: message_key_with.head(cl, isc, SCon{h, t}, has_ch(iso_types(isc), h))

def message_key_with(+cl: Client, +isc: Iso, +raw: String) -> String:
  message_key_with.name(cl, isc, target_name(raw))

def empty_buf.nicks.server(is_srv: Bool, +name: String) -> List<&2, String>:
  match is_srv:
    case True{}: Nil{}
    case False{}: Irc.sanitize_in(name) <> Nil{}

def empty_buf.nicks(+name: String, is_channel: Bool) -> List<&2, String>:
  match is_channel:
    case True{}: Nil{}
    case False{}:
      empty_buf.nicks.server(String.starts_with(name, "*"), name)

def empty_buf(+name: String, +is_channel: Bool) -> Buffer:
  +canonical = target_name(name)
  +channel = is_channel || target_channel(canonical)
  buf_indexed(canonical, channel, "", Nil{}, empty_buf.nicks(canonical, channel), ScrollAt{0n, 0n})

# Keep the last n lines in original order (oldest → newest).
def take_last(+xs: List<&2, Line>, n: Nat) -> List<&2, Line>:
  List.drop(&2, Line, xs, Nat.sub(List.length(&2, Line, xs), n))

def buf_log.scroll.on(gt: Bool, +after: Nat, +tail: Nat) -> Scroll:
  match gt:
    case True{}:
      ScrollAt{1n+after, tail}
    case False{}:
      ScrollAt{0n, 0n}

def buf_log.scroll(scroll: Scroll) -> Scroll:
  match scroll:
    case ScrollAt{+after, +tail}:
      buf_log.scroll.on(Nat.is_gt(after, 0n) || Nat.is_gt(tail, 0n), after, tail)

# Under the cap, cons the new line onto the newest-first spine. At the cap,
# drop the oldest line and rebuild both orders once.
def buf_push.over(over: Bool, +name: String, +ch: Bool, +topic: String, +lines: List<&2, Line>, +nicks: List<&2, String>, +scroll: Scroll, +newest: List<&2, Line>, +count: Nat, +line: Line, +cap: Nat) -> Buffer:
  match over:
    case True{}:
      buf_indexed(name, ch, topic, take_last(List.append(&2, Line, lines, line <> Nil{}), cap), nicks, buf_log.scroll(scroll))
    case False{}:
      Buffer{name, ch, topic, List.append(&2, Line, lines, line <> Nil{}), nicks, buf_log.scroll(scroll), line <> newest, 1n+count}

def buf_push(+b: Buffer, +line: Line, +cap: Nat) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll, +newest, +count}:
      buf_push.over(Nat.is_ge(count, cap), name, ch, topic, lines, nicks, scroll, newest, count, line, cap)

def buf_append_line(+b: Buffer, +line: Line) -> Buffer:
  buf_push(b, line, SCROLL_CAP())

# Diagnostics have no author/nick payload and retain only bounded, private text.
# Mirror IDs are the original event IDs; copying does not create a new event.
def diagnostic_append(+line: Line, b: Buffer) -> Buffer:
  buf_push(b, line, Diagnostic.ROW_CAP())

def diagnostic_slot.make(full: Bool, cl: Client) -> Client & Maybe<&2, Nat>:
  match full:
    case True{}: (cl, None{})
    case False{}:
      match cl:
        case Client{nick, server, +bufs, active, now, stg, auth, seq}:
          (Client{nick, server, List.append(&2, Buffer, bufs, empty_buf(Diagnostic.name(), False{}) <> Nil{}), active, now, stg, auth, seq}, Some{buf_count(bufs)})

def diagnostic_slot.got(got: Maybe<&2, Nat>, +cl: Client) -> Client & Maybe<&2, Nat>:
  match got:
    case Some{i}: (cl, Some{i})
    case None{}:
      match cl:
        case Client{_, _, +bufs, _, _, _, _, _}:
          diagnostic_slot.make(Nat.is_ge(buf_count(bufs), MAX_BUFFERS()), cl)

def diagnostic_slot(+cl: Client) -> Client & Maybe<&2, Nat>:
  diagnostic_slot.got(buf_find(cl, Diagnostic.name()), cl)

def log_buffers.got(got: Maybe<&2, Buffer>) -> List<&2, Buffer>:
  match got:
    case None{}: Nil{}
    case Some{b}: b <> Nil{}

# Preserve only the app-session diagnostics across endpoint changes, not chats.
def log_buffers.index(cl: Client, i: Nat) -> List<&2, Buffer>:
  match cl:
    case Client{_, _, bufs, _, _, _, _, _}: log_buffers.got(nth_buf(bufs, i))

def log_buffers.at(cl: Client, got: Maybe<&2, Nat>) -> List<&2, Buffer>:
  match got:
    case None{}: Nil{}
    case Some{i}: log_buffers.index(cl, i)

def log_buffers(+cl: Client) -> List<&2, Buffer>:
  log_buffers.at(cl, buf_find(cl, Diagnostic.name()))

def diagnostic_line.at(cl: Client, i: Nat, kind: LineKind, ts: String, text: String, id: Nat) -> Client:
  match cl:
    case Client{nick, server, bufs, active, now, +stg, auth, seq}:
      +line: Line = Line{kind, String.take(Irc.sanitize_in(ts), 32n), Diagnostic.text(text, settings_sasl_user(stg), settings_sasl_pass(stg)), "", id}
      Client{nick, server, buf_modify(bufs, i, diagnostic_append(line)), active, now, stg, auth, seq}

def diagnostic_line.got(pair: Client & Maybe<&2, Nat>, kind: LineKind, ts: String, text: String, id: Nat) -> Client:
  match pair:
    case (cl, None{}): cl
    case (cl, Some{i}): diagnostic_line.at(cl, i, kind, ts, text, id)

def diagnostic_line(cl: Client, line: Line) -> Client:
  match line:
    case Line{kind, ts, text, _, id}:
      diagnostic_line.got(diagnostic_slot(cl), kind, ts, text, id)

# Useful stage notices use this same bounded buffer, without changing focus or
# the original error routes. The IO caller supplies only a safe stage label.
def diagnostic(cl: Client, kind: LineKind, msg: String) -> Client:
  match cl:
    case Client{nick, server, bufs, active, +now, stg, auth, +seq}:
      diagnostic_line(Client{nick, server, bufs, active, now, stg, auth, 1n+seq}, Line{kind, now, msg, "", 1n+seq})

# Ordinary stages do not create a tab. Once opened (or created by an error),
# the app-session log also records safe connection and authentication stages.
def diagnostic_notice.got(got: Maybe<&2, Nat>, cl: Client, kind: LineKind, msg: String) -> Client:
  match got:
    case None{}: cl
    case Some{_}: diagnostic(cl, kind, msg)

def diagnostic_notice(+cl: Client, kind: LineKind, msg: String) -> Client:
  diagnostic_notice.got(buf_find(cl, Diagnostic.name()), cl, kind, msg)

def diagnostic_error(kind: LineKind) -> Bool:
  match kind:
    case Error{}: True{}
    case Pending{+inner}: diagnostic_error(inner)
    case _: False{}

def diagnostic_mirror.on(mirror: Bool, cl: Client, line: Line) -> Client:
  match mirror:
    case False{}: cl
    case True{}: diagnostic_line(cl, line)

type DiagnosticFresh is Data:
  DiagnosticFresh{client: Client, cutoff: Nat}

def diagnostic_fresh_line.got(+cutoff: Nat, cl: Client, +line: Line) -> DiagnosticFresh:
  match line:
    case Line{+kind, _, _, _, +id}:
      DiagnosticFresh{diagnostic_mirror.on(diagnostic_error(kind) && Nat.is_gt(id, cutoff), cl, line), cutoff}

def diagnostic_fresh_line(acc: DiagnosticFresh, line: Line) -> DiagnosticFresh:
  match acc:
    case DiagnosticFresh{cl, cutoff}: diagnostic_fresh_line.got(cutoff, cl, line)

def diagnostic_fresh_buf.on(internal: Bool, acc: DiagnosticFresh, lines: List<&2, Line>) -> DiagnosticFresh:
  match internal:
    case True{}: acc
    case False{}:
      List.foldl(~&2, ~Line, ~DiagnosticFresh, ~diagnostic_fresh_line, lines, acc)

def diagnostic_fresh_buf(acc: DiagnosticFresh, b: Buffer) -> DiagnosticFresh:
  match b:
    case Buffer{name, _, _, lines, _, _, _, _}:
      diagnostic_fresh_buf.on(Irc.ieq(name, Diagnostic.name()), acc, lines)

def diagnostic_fresh.fin(acc: DiagnosticFresh) -> Client:
  match acc:
    case DiagnosticFresh{cl, _}: cl

def diagnostic_fresh(+cl: Client, cutoff: Nat) -> Client:
  match cl:
    case Client{_, _, +bufs, _, _, _, _, _}:
      diagnostic_fresh.fin(List.foldl(~&2, ~Buffer, ~DiagnosticFresh, ~diagnostic_fresh_buf, bufs, DiagnosticFresh{cl, cutoff}))

# Live Client.now is "YYYY-MM-DD (Weekday)\nHH:MM:SS". Tests and restored
# stamps stay a bare time. Line columns always store the time half.
def now_day.cut(mark: Bool, pair: String & String) -> String:
  match mark:
    case True{}:
      match pair:
        case (+day, _): day
    case False{}: ""

def now_hms.cut(mark: Bool, pair: String & String, +now: String) -> String:
  match mark:
    case True{}:
      match pair:
        case (_, +rest): String.drop(rest, 1n)
    case False{}: now

def now_mark.cons(+h: Char, r: String & String) -> String & String:
  match r:
    case (tok, rest): (SCon{h, tok}, rest)

def now_mark.fin(+h: Char, +t: String, r: String & String, mark: Bool) -> String & String:
  match mark:
    case True{}: ("", SCon{h, t})
    case False{}: now_mark.cons(h, r)

# Split "YYYY-MM-DD (Weekday)|HH:MM:SS". Bare HMS has no '|'.
def now_split(+now: String) -> String & String:
  match now:
    case SNil{}: ("", "")
    case SCon{+h, +t}: now_mark.fin(h, t, now_split(t), Char.is_eq(h, Chr{124}))

def now_day(+now: String) -> String:
  now_day.cut(String.contains(now, "|"), now_split(now))

def now_hms(+now: String) -> String:
  now_hms.cut(String.contains(now, "|"), now_split(now), now)

def stamp_wire(+ts: String) -> String:
  ts

def stamp_live(+ts: String) -> String:
  ts

# Keep the receipt local day when server-time supplies only HH:MM:SS so paint
# can still insert day dividers. A stamp that already carries a day wins.
def stamp_combine.day(empty: Bool, +day: String, +stamp: String) -> String:
  match empty:
    case True{}: stamp
    case False{}: day ++ "|" ++ now_hms(stamp)

def stamp_combine.dated(has_day: Bool, +now: String, +stamp: String) -> String:
  match has_day:
    case True{}: stamp
    case False{}:
      +day = now_day(now)
      stamp_combine.day(String.is_empty(day), day, stamp)

def stamp_combine.empty(empty: Bool, +now: String, +stamp: String) -> String:
  match empty:
    case True{}: now
    case False{}: stamp_combine.dated(Bool.not(String.is_empty(now_day(stamp))), now, stamp)

def stamp_combine(+now: String, +stamp: String) -> String:
  stamp_combine.empty(String.is_empty(stamp), now, stamp)

def buf_log_ts(+b: Buffer, kind: LineKind, +ts: String, +text: String) -> Buffer:
  buf_append_line(b, Line{kind, Irc.sanitize_in(ts), Irc.sanitize_keep_style(text), "", 0n})

def buf_reconnect.on(internal: Bool, b: Buffer, now: String) -> Buffer:
  match internal:
    case True{}: b
    case False{}: buf_log_ts(b, Reconnect{}, "", now_hms(now))

# App-session diagnostics are not chat history. Generic reconnect dividers
# must not bypass their smaller row cap; the session records a bounded stage.
def buf_reconnect(+b: Buffer, +now: String) -> Buffer:
  match b:
    case Buffer{+name, _, _, _, _, _, _, _}:
      buf_reconnect.on(Irc.ieq(name, Diagnostic.name()), b, now)

def is_reconnect(kind: LineKind) -> Bool:
  match kind:
    case Reconnect{}: True{}
    case Pending{+inner}: is_reconnect(inner)
    case _: False{}

def is_day(kind: LineKind) -> Bool:
  match kind:
    case Day{}: True{}
    case Pending{+inner}: is_day(inner)
    case _: False{}

def is_link_result(kind: LineKind) -> Bool:
  match kind:
    case LinkResult{}: True{}
    case Pending{+inner}: is_link_result(inner)
    case _: False{}

def kind_pending(kind: LineKind) -> Bool:
  match kind:
    case Pending{_}: True{}
    case _: False{}

# A zero ID is an unassigned buffer-local log. Feed maps may append to several
# buffers; stamp them once at the event boundary. IDs never change on moves,
# purges, clears, or query merges. The client sequence survives those edits.
def stamp_line.on(assign: Bool, kind: LineKind, +ts: String, +text: String, +author: String, +id: Nat, +seq: Nat) -> Line & Nat:
  match assign:
    case False{}: (Line{kind, ts, text, author, id}, seq)
    case True{}:
      +next: Nat = 1n+seq
      (Line{kind, ts, text, author, next}, next)

def stamp_line(line: Line, +seq: Nat) -> Line & Nat:
  match line:
    case Line{+kind, +ts, +text, +author, +id}:
      stamp_line.on(Nat.is_eq(id, 0n), kind, ts, text, author, id, seq)

type StampLines is Data:
  StampLines{rev: List<&2, Line>, seq: Nat}

def stamp_lines.step.got(pair: Line & Nat, rev: List<&2, Line>) -> StampLines:
  match pair:
    case (line, seq): StampLines{line <> rev, seq}

def stamp_lines.step(acc: StampLines, line: Line) -> StampLines:
  match acc:
    case StampLines{rev, seq}: stamp_lines.step.got(stamp_line(line, seq), rev)

def stamp_lines.fin(acc: StampLines) -> List<&2, Line> & Nat:
  match acc:
    case StampLines{rev, seq}: (List.reverse(&2, Line, rev), seq)

def stamp_lines(lines: List<&2, Line>, seq: Nat) -> List<&2, Line> & Nat:
  stamp_lines.fin(List.foldl(~&2, ~Line, ~StampLines, ~stamp_lines.step, lines, StampLines{Nil{}, seq}))

type StampBufs is Data:
  StampBufs{rev: List<&2, Buffer>, seq: Nat}

def stamp_bufs.step.lines(pair: List<&2, Line> & Nat, name: String, channel: Bool, topic: String, nicks: List<&2, String>, scroll: Scroll, rev: List<&2, Buffer>) -> StampBufs:
  match pair:
    case (lines, seq): StampBufs{buf_indexed(name, channel, topic, lines, nicks, scroll) <> rev, seq}

def stamp_bufs.step(acc: StampBufs, b: Buffer) -> StampBufs:
  match acc:
    case StampBufs{rev, seq}:
      match b:
        case Buffer{name, channel, topic, lines, nicks, scroll, _, _}:
          stamp_bufs.step.lines(stamp_lines(lines, seq), name, channel, topic, nicks, scroll, rev)

def stamp_bufs.fin(acc: StampBufs) -> List<&2, Buffer> & Nat:
  match acc:
    case StampBufs{rev, seq}: (List.reverse(&2, Buffer, rev), seq)

def stamp_bufs(bufs: List<&2, Buffer>, seq: Nat) -> List<&2, Buffer> & Nat:
  stamp_bufs.fin(List.foldl(~&2, ~Buffer, ~StampBufs, ~stamp_bufs.step, bufs, StampBufs{Nil{}, seq}))

def stamp_logs.got(pair: List<&2, Buffer> & Nat, nick: String, server: String, active: Nat, now: String, stg: Settings, auth: AuthPhase, cutoff: Nat) -> Client:
  match pair:
    case (bufs, seq): diagnostic_fresh(Client{nick, server, bufs, active, now, stg, auth, seq}, cutoff)

def stamp_logs(cl: Client) -> Client:
  match cl:
    case Client{nick, server, bufs, active, now, stg, auth, +seq}:
      stamp_logs.got(stamp_bufs(bufs, seq), nick, server, active, now, stg, auth, seq)

def buf_has_lines(b: Buffer) -> Bool:
  match b:
    case Buffer{_, _, _, Nil{}, _, _, _, _}: False{}
    case _: True{}

def reconnect_marker.has(has: Bool, b: Buffer, now: String) -> Buffer:
  match has:
    case False{}: b
    case True{}: buf_reconnect(b, now)

def reconnect_marker(+b: Buffer, now: String) -> Buffer:
  reconnect_marker.has(buf_has_lines(b), b, now)

def reconnect_bufs(bufs: List<&2, Buffer>, +now: String) -> List<&2, Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{b, rest}: reconnect_marker(b, now) <> reconnect_bufs(rest, now)

# History and Session share the event-ID stamping boundary for dividers.
def reconnect_markers(cl: Client, now: String) -> Client:
  match cl:
    case Client{nick, server, bufs, active, old_now, stg, auth, seq}:
      stamp_logs(Client{nick, server, reconnect_bufs(bufs, now), active, old_now, stg, auth, seq})

# Roster and topic describe the current connection, unlike retained history.
def reset_channel_buf(b: Buffer) -> Buffer:
  match b:
    case Buffer{name, True{}, _, lines, _, scroll, _, _}:
      buf_indexed(name, True{}, "", lines, Nil{}, scroll)
    case _: b

def reset_channel_bufs(bufs: List<&2, Buffer>) -> List<&2, Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{b, rest}: reset_channel_buf(b) <> reset_channel_bufs(rest)

def reset_channel_state(cl: Client) -> Client:
  match cl:
    case Client{nick, server, bufs, active, now, stg, auth, seq}:
      Client{nick, server, reset_channel_bufs(bufs), active, now, stg, auth, seq}

def cap_note(+b: Buffer, +now: String) -> Buffer:
  buf_log_ts(b, Error{}, now, "buffer limit reached")

def cap_at(+now: String, b: Buffer) -> Buffer:
  cap_note(b, now)

def buf_get.full(got: Maybe<&2, Buffer>, +nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +auth: AuthPhase, +log_seq: Nat) -> Client & Maybe<&2, Nat>:
  match got:
    case None{}:
      (Client{nick, server, bufs, active, now, stg, auth, log_seq}, None{})
    case Some{_}:
      (stamp_logs(Client{nick, server, buf_modify(bufs, 0n, cap_at(now)), active, now, stg, auth, log_seq}), None{})

def buf_get.create.cap(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +auth: AuthPhase, +log_seq: Nat, +name: String, is_channel: Bool, full: Bool) -> Client & Maybe<&2, Nat>:
  match full:
    case True{}:
      buf_get.full(nth_buf(bufs, 0n), nick, server, bufs, active, now, stg, auth, log_seq)
    case False{}:
      +b = empty_buf(name, is_channel)
      +i = buf_count(bufs)
      +bufs2 = List.append(&2, Buffer, bufs, b <> Nil{})
      (Client{nick, server, bufs2, active, now, stg, auth, log_seq}, Some{i})

def normal_buffer_count.step(n: Nat, b: Buffer) -> Nat:
  match b:
    case Buffer{name, _, _, _, _, _, _, _}:
      Nat.add(n, Bool.pick(Nat, Irc.ieq(name, Diagnostic.name()), 0n, 1n))

def normal_buffer_count(bufs: List<&2, Buffer>) -> Nat:
  List.foldl(~&2, ~Buffer, ~Nat, ~normal_buffer_count.step, bufs, 0n)

def buf_get.create(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +auth: AuthPhase, +log_seq: Nat, +name: String, is_channel: Bool) -> Client & Maybe<&2, Nat>:
  buf_get.create.cap(nick, server, bufs, active, now, stg, auth, log_seq, name, is_channel,
    Nat.is_ge(buf_count(bufs), MAX_BUFFERS()) || (Bool.not(Irc.ieq(name, Diagnostic.name())) && Nat.is_ge(normal_buffer_count(bufs), NORMAL_BUFFERS())))

def buf_get.miss(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +auth: AuthPhase, +log_seq: Nat, +name: String, is_channel: Bool, create: Bool) -> Client & Maybe<&2, Nat>:
  match create:
    case False{}:
      (Client{nick, server, bufs, active, now, stg, auth, log_seq}, None{})
    case True{}:
      buf_get.create(nick, server, bufs, active, now, stg, auth, log_seq, name, is_channel)

# Older query-created channels retain their own name as the seed nick. Remove
# that exact seed when negotiated policy later promotes the existing buffer.
def drop_self_nicks.keep(keep: Bool, +nick: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}: nick <> rest
    case False{}: rest

def drop_self_nicks(xs: List<&2, String>, +name: String) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{+nick, rest}:
      drop_self_nicks.keep(Bool.not(String.eq(nick, name)), nick, drop_self_nicks(rest, name))

def promote_channel.on(promote: Bool, b: Buffer) -> Buffer:
  match promote:
    case False{}: b
    case True{}:
      match b:
        case Buffer{+name, _, topic, lines, nicks, scroll, _, _}:
          buf_indexed(name, True{}, topic, lines, drop_self_nicks(nicks, name), scroll)

def promote_channel(channel: Bool, b: Buffer) -> Buffer:
  match b:
    case Buffer{_, +was_channel, _, _, _, _, _, _}:
      promote_channel.on(channel && Bool.not(was_channel), b)

def buf_get.found(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +auth: AuthPhase, +log_seq: Nat, +name: String, is_channel: Bool, create: Bool, found: Maybe<&2, Nat>) -> Client & Maybe<&2, Nat>:
  match found:
    case Some{+i}:
      (Client{nick, server, buf_modify(bufs, i, promote_channel(is_channel)), active, now, stg, auth, log_seq}, Some{i})
    case None{}:
      buf_get.miss(nick, server, bufs, active, now, stg, auth, log_seq, name, is_channel, create)

def buf_get.fin(+cl: Client, +name: String, is_channel: Bool, create: Bool, found: Maybe<&2, Nat>) -> Client & Maybe<&2, Nat>:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      buf_get.found(nick, server, bufs, active, now, stg, auth, log_seq, name, is_channel, create, found)

def buf_get(+cl: Client, +name: String, is_channel: Bool, create: Bool) -> Client & Maybe<&2, Nat>:
  +canonical = target_name(name)
  buf_get.fin(cl, canonical, is_channel || target_channel(canonical), create, buf_find(cl, canonical))

def buf_get_with(+cl: Client, +isc: Iso, +name: String, is_channel: Bool, create: Bool) -> Client & Maybe<&2, Nat>:
  +canonical = target_name(name)
  buf_get.fin(cl, canonical, is_channel || target_channel_with(iso_types(isc), iso_status(isc), iso_sigils(isc), canonical), create, buf_find_cm(cl, iso_cm(isc), canonical))

# ---- scrollback ---------------------------------------------------------

# Tests pass ts="" (init.now is empty). Live/demo set Client.now at the IO
# edge before feed/submit so buf_log_ts stores HH:MM:SS at log time.
def buf_log(+b: Buffer, kind: LineKind, +text: String) -> Buffer:
  buf_log_ts(b, kind, "", text)

def client_log_ts.pick(empty: Bool, +ts: String, +now: String) -> String:
  match empty:
    case True{}:
      now
    case False{}:
      ts

def client_log.destination(got: Maybe<&2, Buffer>) -> Bool:
  match got:
    case None{}: False{}
    case Some{Buffer{name, _, _, _, _, _, _, _}}: Irc.ieq(name, Diagnostic.name())

def diagnostic_mirror(mirror: Bool, cl: Client, +line: Line) -> Client:
  match line:
    case Line{kind, _, _, _, _}: diagnostic_mirror.on(mirror && diagnostic_error(kind), cl, line)

def client_log.original(mirror: Bool, cl: Client, i: Nat, +line: Line) -> Client:
  match cl:
    case Client{nick, server, bufs, active, now, stg, auth, seq}:
      diagnostic_mirror(mirror,
        Client{nick, server, buf_modify(bufs, i, b => buf_append_line(b, line)), active, now, stg, auth, seq}, line)

def client_log.append(internal: Bool, mirror: Bool, cl: Client, i: Nat, line: Line) -> Client:
  match internal:
    case True{}: diagnostic_line(cl, line)
    case False{}: client_log.original(mirror, cl, i, line)

def client_log_author_ts.noted(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +auth: AuthPhase, +seq: Nat, +i: Nat, kind: LineKind, +ts: String, +text: String, +author: String, mirror: Bool) -> Client:
  +ts_use = client_log_ts.pick(String.is_empty(ts), ts, now)
  +next: Nat = 1n+seq
  +line: Line = Line{kind, Irc.sanitize_in(ts_use), Irc.sanitize_keep_style(text), Irc.sanitize_in(author), next}
  client_log.append(client_log.destination(nth_buf(bufs, i)), mirror, Client{nick, server, bufs, active, now, stg, auth, next}, i, line)

def client_log_author_ts.record(+mirror: Bool, +cl: Client, +i: Nat, +kind: LineKind, +ts: String, +text: String, +author: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      client_log_author_ts.noted(nick, server, bufs, active, now, stg, auth, log_seq, i, kind, ts, text, author, mirror)

def client_log_author_ts(+cl: Client, +i: Nat, kind: LineKind, +ts: String, +text: String, +author: String) -> Client:
  client_log_author_ts.record(True{}, cl, i, kind, ts, text, author)

# History imports receive fresh chat IDs but are not new diagnostic events.
# Reuse the same timestamp/sanitization/cap path without replaying error copies.
def client_restore_author_ts(+cl: Client, +i: Nat, kind: LineKind, +ts: String, +text: String, +author: String) -> Client:
  client_log_author_ts.record(False{}, cl, i, kind, ts, text, author)

def client_log_ts(+cl: Client, +i: Nat, kind: LineKind, +ts: String, +text: String) -> Client:
  client_log_author_ts(cl, i, kind, ts, text, "")

def client_log(+cl: Client, +i: Nat, kind: LineKind, +text: String) -> Client:
  client_log_ts(cl, i, kind, "", text)

def buf_modify_client(+cl: Client, +i: Nat, f: Buffer -> Buffer) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, buf_modify(bufs, i, f), active, now, stg, auth, log_seq}

def purge_nick_from_active_buf(+cl: Client, +nick: String) -> Client:
  match cl:
    case Client{_, _, _, +active, _, _, +auth, +log_seq}:
      buf_modify_client(cl, active, b => purge_nick_buf(b, nick))

def set_now(+cl: Client, +ts: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      Client{nick, server, bufs, active, ts, stg, auth, log_seq}

def replay_keep.cons(acc: List<&2, String>, +s: String, empty: Bool) -> List<&2, String>:
  match empty:
    case True{}:
      acc
    case False{}:
      s <> acc

def replay_step(acc: List<&2, String>, h: String) -> List<&2, String>:
  +s = Irc.strip_cr(h)
  replay_keep.cons(acc, s, String.is_empty(s))

def replay_lines(+text: String) -> List<&2, String>:
  List.reverse(&2, String, List.foldl(~&2, ~String, ~List<&2, String>, ~replay_step, String.lines(text), Nil{}))

# ---- nicks --------------------------------------------------------------

def is_sigil_set(+sigils: String, +c: Char) -> Bool:
  has_ch(sigils, c)

# Two fuel steps per character: read the head, then act on the sigil test.
# Bool.pick would evaluate both arms eagerly; match on the test result only.
type NickStripPh is Data:
  NickStripStr{}
  NickStripHit{h: Char, is_sig: Bool}

def nick_strip_set.go(fuel: Nat, ph: NickStripPh, +sigils: String, s: String) -> String:
  match fuel:
    case 0n:
      SNil{}
    case 1n+p:
      match ph:
        case NickStripStr{}:
          match s:
            case SNil{}:
              SNil{}
            case SCon{+h, +t}:
              nick_strip_set.go(p, NickStripHit{h, is_sigil_set(sigils, h)}, sigils, t)
        case NickStripHit{h, is_sig}:
          match is_sig:
            case True{}:
              nick_strip_set.go(p, NickStripStr{}, sigils, s)
            case False{}:
              SCon{h, s}

def nick_strip_set(+sigils: String, +s: String) -> String:
  nick_strip_set.go(Nat.add(1n, Nat.mul(2n, String.length(s))), NickStripStr{}, sigils, s)

def nick_strip(+s: String) -> String:
  nick_strip_set(dflt_strip(), s)

def nick_eq(a: String, b: String) -> Bool:
  buf_eq_cm(dflt_cm(), a, b)

def nick_eq_cm(+cm: String, +a: String, +b: String) -> Bool:
  buf_eq_cm(cm, a, b)

def nick_has_cm.go(+cm: String, xs: List<&2, String>, +nick: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, +t}: buf_eq_cm(cm, h, nick) || nick_has_cm.go(cm, t, nick)

def nick_has_cm(+b: Buffer, +cm: String, +nick: String) -> Bool:
  match b:
    case Buffer{_, _, _, _, +nicks, _, _, _}:
      nick_has_cm.go(cm, nicks, nick)

def nick_has(+b: Buffer, +nick: String) -> Bool:
  match b:
    case Buffer{_, _, _, _, +nicks, _, _, _}:
      List.contains(~String, ~nick_eq, nicks, nick)

def nick_add.keep(+b: Buffer, skip: Bool, +nick: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, _, +nicks, _, _, _}:
      match skip:
        case True{}: b
        case False{}:
          buf_with_meta(b, name, ch, topic, List.append(&2, String, nicks, nick <> Nil{}))

def nick_del.on_head(+h: String, +t: List<&2, String>, +nick: String, drop: Bool, cont: List<&2, String> -> List<&2, String>) -> List<&2, String>:
  match drop:
    case True{}:
      t
    case False{}:
      h <> cont(t)

def nick_del.go(fuel: Nat, xs: List<&2, String>, +nick: String) -> List<&2, String>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      match xs:
        case Nil{}:
          Nil{}
        case Con{+h, +t}:
          nick_del.on_head(h, t, nick, buf_eq_cm(dflt_cm(), h, nick), tail => nick_del.go(p, tail, nick))

def nick_del(+b: Buffer, +raw: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, _, +nicks, _, _, _}:
      +stripped = nick_strip(raw)
      buf_with_meta(b, name, ch, topic, nick_del.go(Nat.add(1n, List.length(&2, String, nicks)), nicks, stripped))

def nick_rename.on_head(+h: String, +t: List<&2, String>, +from: String, +to: String, hit: Bool, cont: List<&2, String> -> List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      to <> t
    case False{}:
      h <> cont(t)

def nick_rename.go(fuel: Nat, xs: List<&2, String>, +from: String, +to: String) -> List<&2, String>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      match xs:
        case Nil{}:
          Nil{}
        case Con{+h, +t}:
          nick_rename.on_head(h, t, from, to, buf_eq_cm(dflt_cm(), h, from), tail => nick_rename.go(p, tail, from, to))

def nick_rename(+b: Buffer, +from: String, +to: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, _, +nicks, _, _, _}:
      +from_s = nick_strip(from)
      +to_s = nick_strip(to)
      buf_with_meta(b, name, ch, topic, nick_rename.go(Nat.add(1n, List.length(&2, String, nicks)), nicks, from_s, to_s))

def nick_del_cm.on_head(+h: String, +t: List<&2, String>, +cm: String, +nick: String, drop: Bool, cont: List<&2, String> -> List<&2, String>) -> List<&2, String>:
  match drop:
    case True{}:
      t
    case False{}:
      h <> cont(t)

def nick_del_cm.go(fuel: Nat, +cm: String, xs: List<&2, String>, +nick: String) -> List<&2, String>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      match xs:
        case Nil{}:
          Nil{}
        case Con{+h, +t}:
          nick_del_cm.on_head(h, t, cm, nick, buf_eq_cm(cm, h, nick), tail => nick_del_cm.go(p, cm, tail, nick))

def nick_del_cm(+b: Buffer, +cm: String, +sigils: String, +raw: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, _, +nicks, _, _, _}:
      +stripped = nick_strip_set(sigils, raw)
      buf_with_meta(b, name, ch, topic, nick_del_cm.go(Nat.add(1n, List.length(&2, String, nicks)), cm, nicks, stripped))

def nick_rename_cm.on_head(+h: String, +t: List<&2, String>, +cm: String, +from: String, +to: String, hit: Bool, cont: List<&2, String> -> List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      to <> t
    case False{}:
      h <> cont(t)

def nick_rename_cm.go(fuel: Nat, +cm: String, xs: List<&2, String>, +from: String, +to: String) -> List<&2, String>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      match xs:
        case Nil{}:
          Nil{}
        case Con{+h, +t}:
          nick_rename_cm.on_head(h, t, cm, from, to, buf_eq_cm(cm, h, from), tail => nick_rename_cm.go(p, cm, tail, from, to))

def nick_rename_cm(+b: Buffer, +cm: String, +sigils: String, +from: String, +to: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, _, +nicks, _, _, _}:
      +from_s = nick_strip_set(sigils, from)
      +to_s = nick_strip_set(sigils, to)
      buf_with_meta(b, name, ch, topic, nick_rename_cm.go(Nat.add(1n, List.length(&2, String, nicks)), cm, nicks, from_s, to_s))

def nick_add_cm.body(+cm: String, +b: Buffer, +nick: String, empty: Bool) -> Buffer:
  match b:
    case Buffer{_, _, _, _, +nicks, _, _, _}:
      match empty:
        case True{}: b
        case False{}:
          nick_add.keep(b, nick_has_cm(b, cm, nick) || Nat.is_ge(List.length(&2, String, nicks), MAX_NICKS()), nick)

def nick_add_cm(+b: Buffer, +cm: String, +sigils: String, +raw: String) -> Buffer:
  +n = nick_strip_set(sigils, raw)
  nick_add_cm.body(cm, b, n, String.is_empty(n))

def nick_add_all_cm.go(xs: List<&2, String>, +cm: String, +sigils: String, +b: Buffer) -> Buffer:
  match xs:
    case Nil{}: b
    case Con{+h, +t}: nick_add_all_cm.go(t, cm, sigils, nick_add_cm(b, cm, sigils, h))

def nick_add_all_cm(+b: Buffer, +cm: String, +sigils: String, +ns: List<&2, String>) -> Buffer:
  nick_add_all_cm.go(ns, cm, sigils, b)

def nick_add(+b: Buffer, +raw: String) -> Buffer:
  nick_add_cm(b, dflt_cm(), dflt_strip(), raw)

def nick_add_who(+who: String, b: Buffer) -> Buffer:
  nick_add(b, who)

def nick_add_idx(+cl: Client, +i: Nat, +who: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, buf_modify(bufs, i, nick_add_who(who)), active, now, stg, auth, log_seq}

def nick_add_step(b: Buffer, h: String) -> Buffer:
  +bb = b
  nick_add(bb, h)

def nick_add_all(+b: Buffer, +ns: List<&2, String>) -> Buffer:
  List.foldl(~&2, ~String, ~Buffer, ~nick_add_step, ns, b)

# ---- set topic / active / nick ------------------------------------------

def set_topic(+b: Buffer, +topic: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, _, _, +nicks, _, _, _}:
      buf_with_meta(b, name, ch, topic, nicks)

def set_topic_fn(topic: String, b: Buffer) -> Buffer:
  set_topic(b, topic)

def set_topic_at(+cl: Client, +i: Nat, +topic: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, buf_modify(bufs, i, set_topic_fn(topic)), active, now, stg, auth, log_seq}

def set_active.unread(+stg: Settings, got: Maybe<&2, Buffer>) -> Settings:
  match got:
    case None{}:
      stg
    case Some{b}:
      match b:
        case Buffer{+name, _, _, _, _, _, _, _}:
          set_unreads(stg, del_unread_items(settings_unreads(stg), name))

def set_active.unread_index(control: Bool, stg: Settings, got: Maybe<&2, Buffer>) -> Settings:
  match control:
    case True{}: stg
    case False{}: set_active.unread(stg, got)

def set_active(+cl: Client, +i: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, _, +now, +stg, +auth, +log_seq}:
      +stg2 = set_active.unread_index(Nat.is_eq(i, 0n), stg, nth_buf(bufs, i))
      Client{nick, server, bufs, i, now, stg2, auth, log_seq}

def set_active_clamp.on(+cl: Client, +i: Nat, ok: Bool) -> Client:
  match ok:
    case True{}:
      set_active(cl, i)
    case False{}:
      cl

def set_active_clamp(+cl: Client, +i: Nat) -> Client:
  match cl:
    case Client{_, _, +bufs, _, _, _, +auth, +log_seq}:
      set_active_clamp.on(cl, i, Nat.is_lt(i, buf_count(bufs)))

def set_buf_anchor(+b: Buffer, +sc: Scroll) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, _, +newest, +count}:
      buf_with_scroll(name, ch, topic, lines, nicks, sc, newest, count)

def set_buf_scroll(+b: Buffer, +sc: Nat) -> Buffer:
  set_buf_anchor(b, ScrollAt{sc, 0n})

def set_buf_name(+b: Buffer, +name: String) -> Buffer:
  match b:
    case Buffer{_, +ch, +topic, +lines, +nicks, +scroll, _, _}:
      buf_indexed(target_name(name), ch, topic, lines, nicks, scroll)

def is_query_name(+name: String) -> Bool:
  Bool.not(target_is_synthetic(name) || target_channel(name))

def query_target(+b: Buffer, +target: String) -> Bool:
  match b:
    case Buffer{+name, ch, _, _, _, _, _, _}:
      Bool.not(ch) && is_query_name(name) && Irc.ieq(name, target)

def query_target_cm(+cm: String, +b: Buffer, +target: String) -> Bool:
  match b:
    case Buffer{+name, ch, _, _, _, _, _, _}:
      Bool.not(ch) && is_query_name(name) && buf_eq_cm(cm, name, target)

def query_lines.keep(hit: Bool, b: Buffer, rest: List<&2, Line>) -> List<&2, Line>:
  match hit:
    case False{}: rest
    case True{}:
      match b:
        case Buffer{_, _, _, lines, _, _, _, _}: List.append(&2, Line, lines, rest)

def query_lines(bufs: List<&2, Buffer>, +target: String) -> List<&2, Line>:
  match bufs:
    case Nil{}: Nil{}
    case Con{+b, t}: query_lines.keep(query_target(b, target), b, query_lines(t, target))

def query_lines_cm(+cm: String, bufs: List<&2, Buffer>, +target: String) -> List<&2, Line>:
  match bufs:
    case Nil{}: Nil{}
    case Con{+b, t}: query_lines.keep(query_target_cm(cm, b, target), b, query_lines_cm(cm, t, target))

def line_id_le(a: Line, b: Line) -> Bool:
  match a:
    case Line{_, _, _, _, id_a}:
      match b:
        case Line{_, _, _, _, id_b}: Nat.is_le(id_a, id_b)

def coalesce_queries.choose(hit: Bool, preferred: Buffer, fallback: Buffer) -> Buffer:
  match hit:
    case True{}: preferred
    case False{}: fallback

def coalesce_queries.base(got: Maybe<&2, Buffer>, b: Buffer, +target: String) -> Buffer:
  match got:
    case None{}: b
    case Some{+preferred}: coalesce_queries.choose(query_target(preferred, target), preferred, b)

def coalesce_queries.base_cm(+cm: String, got: Maybe<&2, Buffer>, b: Buffer, +target: String) -> Buffer:
  match got:
    case None{}: b
    case Some{+preferred}: coalesce_queries.choose(query_target_cm(cm, preferred, target), preferred, b)

def coalesce_queries.buffer(b: Buffer, target: String, +merged: List<&2, Line>) -> Buffer:
  match b:
    case Buffer{_, channel, topic, lines, nicks, scroll, _, _}:
      buf_indexed(target, channel, topic, merged, nicks, reanchor_lines(lines, merged, scroll))

def coalesce_queries.keep(hit: Bool, seen: Bool, b: Buffer, +target: String, merged: List<&2, Line>, preferred: Maybe<&2, Buffer>, rest: List<&2, Buffer>) -> List<&2, Buffer>:
  match hit:
    case False{}: b <> rest
    case True{}:
      match seen:
        case True{}: rest
        case False{}:
          coalesce_queries.buffer(coalesce_queries.base(preferred, b, target), target, merged) <> rest

def coalesce_queries.step(+hit: Bool, +seen: Bool, b: Buffer, target: String, merged: List<&2, Line>, preferred: Maybe<&2, Buffer>, next: Bool -> List<&2, Buffer>) -> List<&2, Buffer>:
  coalesce_queries.keep(hit, seen, b, target, merged, preferred, next(seen || hit))

def coalesce_queries.keep_cm(+cm: String, hit: Bool, seen: Bool, b: Buffer, +target: String, merged: List<&2, Line>, preferred: Maybe<&2, Buffer>, rest: List<&2, Buffer>) -> List<&2, Buffer>:
  match hit:
    case False{}: b <> rest
    case True{}:
      match seen:
        case True{}: rest
        case False{}:
          coalesce_queries.buffer(coalesce_queries.base_cm(cm, preferred, b, target), target, merged) <> rest

def coalesce_queries.step_cm(+cm: String, +hit: Bool, +seen: Bool, b: Buffer, target: String, merged: List<&2, Line>, preferred: Maybe<&2, Buffer>, next: Bool -> List<&2, Buffer>) -> List<&2, Buffer>:
  coalesce_queries.keep_cm(cm, hit, seen, b, target, merged, preferred, next(seen || hit))

def coalesce_queries.go(bufs: List<&2, Buffer>, +target: String, +merged: List<&2, Line>, +preferred: Maybe<&2, Buffer>, seen: Bool) -> List<&2, Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{+b, t}:
      coalesce_queries.step(query_target(b, target), seen, b, target, merged, preferred,
        found => coalesce_queries.go(t, target, merged, preferred, found))

def coalesce_queries.go_cm(+cm: String, bufs: List<&2, Buffer>, +target: String, +merged: List<&2, Line>, +preferred: Maybe<&2, Buffer>, seen: Bool) -> List<&2, Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{+b, t}:
      coalesce_queries.step_cm(cm, query_target_cm(cm, b, target), seen, b, target, merged, preferred,
        found => coalesce_queries.go_cm(cm, t, target, merged, preferred, found))

# Global event IDs let query collisions merge in arrival order without
# renumbering old events (and therefore without saving them a second time).
def coalesce_queries.bufs(bufs: List<&2, Buffer>, +target: String, preferred: Maybe<&2, Buffer>) -> List<&2, Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{server, +tail}:
      +merged = take_last(List.sort(~Line, ~line_id_le, query_lines(tail, target)), SCROLL_CAP())
      server <> coalesce_queries.go(tail, target, merged, preferred, False{})

def coalesce_queries.preferred(control: Bool, got: Maybe<&2, Buffer>) -> Maybe<&2, Buffer>:
  match control:
    case True{}: None{}
    case False{}: got

def coalesce_queries(+cl: Client, target: String) -> Client:
  match cl:
    case Client{nick, server, +bufs, +active, now, stg, auth, seq}:
      +preferred = coalesce_queries.preferred(Nat.is_eq(active, 0n), nth_buf(bufs, active))
      Client{nick, server, coalesce_queries.bufs(bufs, target, preferred), active, now, stg, auth, seq}

def coalesce_queries.bufs_cm(+cm: String, bufs: List<&2, Buffer>, +target: String, preferred: Maybe<&2, Buffer>) -> List<&2, Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{server, +tail}:
      +merged = take_last(List.sort(~Line, ~line_id_le, query_lines_cm(cm, tail, target)), SCROLL_CAP())
      server <> coalesce_queries.go_cm(cm, tail, target, merged, preferred, False{})

def coalesce_queries_cm(+cm: String, +cl: Client, target: String) -> Client:
  match cl:
    case Client{nick, server, +bufs, +active, now, stg, auth, seq}:
      +preferred = coalesce_queries.preferred(Nat.is_eq(active, 0n), nth_buf(bufs, active))
      Client{nick, server, coalesce_queries.bufs_cm(cm, bufs, target, preferred), active, now, stg, auth, seq}

def scroll_zero(b: Buffer) -> Buffer:
  set_buf_scroll(b, 0n)

def snap_active(+cl: Client) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, buf_modify(bufs, active, scroll_zero), active, now, stg, auth, log_seq}

def scroll_add_nat(+scroll: Nat, +up: Nat, +dn: Nat) -> Nat:
  Nat.sub(Nat.add(scroll, up), dn)

def clamp_nat.on(+n: Nat, +maxs: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      maxs
    case False{}:
      n

def clamp_nat(+n: Nat, +maxs: Nat) -> Nat:
  clamp_nat.on(n, maxs, Nat.is_ge(n, maxs))

def apply_buf_scroll.on(+b: Buffer, +up: Nat, +dn: Nat) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, ScrollAt{+scroll, _}, +newest, +count}:
      buf_with_scroll(name, ch, topic, lines, nicks, ScrollAt{clamp_nat(scroll_add_nat(scroll, up, dn), count), 0n}, newest, count)

def scroll_delta(+up: Nat, +dn: Nat, b: Buffer) -> Buffer:
  apply_buf_scroll.on(b, up, dn)

def apply_active_scroll(+cl: Client, +up: Nat, +dn: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, buf_modify(bufs, active, scroll_delta(up, dn)), active, now, stg, auth, log_seq}

def buf_scroll_of.on(got: Maybe<&2, Buffer>) -> Nat:
  match got:
    case None{}:
      0n
    case Some{b}:
      match b:
        case Buffer{_, _, _, _, _, ScrollAt{+scroll, _}, _, _}:
          scroll

def buf_scroll_of(+cl: Client, +i: Nat) -> Nat:
  match cl:
    case Client{_, _, +bufs, _, _, _, +auth, +log_seq}:
      buf_scroll_of.on(nth_buf(bufs, i))

def log_open.got(pair: Client & Maybe<&2, Nat>) -> Client:
  match pair:
    case (cl, None{}): cl
    case (cl, Some{i}): set_active(cl, i)

def log_open(cl: Client) -> Client:
  log_open.got(diagnostic_slot(cl))

def active_of(+cl: Client) -> Nat:
  match cl:
    case Client{_, _, _, +active, _, _, +auth, +log_seq}:
      active

def scroll_eq(a: Scroll, b: Scroll) -> Bool:
  match a:
    case ScrollAt{+aa, +at}:
      match b:
        case ScrollAt{+ba, +bt}:
          Bool.and(Nat.is_eq(aa, ba), Nat.is_eq(at, bt))

def buf_scroll(b: Buffer) -> Scroll:
  match b:
    case Buffer{_, _, _, _, _, +scroll, _, _}:
      scroll

def active_scroll.got(b: Maybe<&2, Buffer>) -> Scroll:
  match b:
    case None{}: ScrollAt{0n, 0n}
    case Some{buf}: buf_scroll(buf)

def active_scroll(+cl: Client) -> Scroll:
  match cl:
    case Client{_, _, +bufs, +active, _, _, _, _}:
      active_scroll.got(nth_buf(bufs, active))

def view_name.on(got: Maybe<&2, Buffer>) -> String:
  match got:
    case None{}: "server"
    case Some{Buffer{+name, _, _, _, _, _, _, _}}: name

# Composer edits leave the visible history alone. Callers use this to skip
# image and card admission on those keys. Buffer count and active name catch
# structural tab changes (e.g. closing a query to the right of the active tab)
# that leave log_seq, active index, and scroll unchanged.
def view_same(+a: Client, +b: Client) -> Bool:
  match a:
    case Client{_, _, +abufs, +aact, _, _, _, +aseq}:
      match b:
        case Client{_, _, +bbufs, +bact, _, _, _, +bseq}:
          Bool.and(
            Bool.and(
              Bool.and(Nat.is_eq(aseq, bseq), Nat.is_eq(aact, bact)),
              scroll_eq(active_scroll.got(nth_buf(abufs, aact)), active_scroll.got(nth_buf(bbufs, bact)))),
            Bool.and(
              Nat.is_eq(buf_count(abufs), buf_count(bbufs)),
              String.eq(view_name.on(nth_buf(abufs, aact)), view_name.on(nth_buf(bbufs, bact)))))

def cycle_next.i.on(wrap: Bool, +active: Nat) -> Nat:
  match wrap:
    case True{}:
      0n
    case False{}:
      Nat.add(active, 1n)

def cycle_next.i(+active: Nat, +n: Nat) -> Nat:
  cycle_next.i.on(Nat.is_eq(Nat.add(active, 1n), n), active)

def cycle_prev.i.on(z: Bool, +active: Nat, +n: Nat) -> Nat:
  match z:
    case True{}:
      Nat.sub(n, 1n)
    case False{}:
      Nat.sub(active, 1n)

def cycle_prev.i(+active: Nat, +n: Nat) -> Nat:
  cycle_prev.i.on(Nat.is_eq(active, 0n), active, n)

def cycle_next(+cl: Client) -> Client:
  match cl:
    case Client{_, _, +bufs, +active, _, _, +auth, +log_seq}:
      set_active(cl, cycle_next.i(active, buf_count(bufs)))

def cycle_prev(+cl: Client) -> Client:
  match cl:
    case Client{_, _, +bufs, +active, _, _, +auth, +log_seq}:
      set_active(cl, cycle_prev.i(active, buf_count(bufs)))

type TabDir is Data:
  TabStay{}
  TabNext{}
  TabPrev{}

def tab_dir.on(+n: U32, next: Bool, prev: Bool) -> TabDir:
  match next:
    case True{}:
      TabNext{}
    case False{}:
      match prev:
        case True{}:
          TabPrev{}
        case False{}:
          TabStay{}

def tab_dir(+n: U32) -> TabDir:
  tab_dir.on(n, U32.is_eq(n, 1), U32.is_eq(n, 2))

def cycle_tab(+cl: Client, dir: TabDir) -> Client:
  match dir:
    case TabStay{}:
      cl
    case TabNext{}:
      cycle_next(cl)
    case TabPrev{}:
      cycle_prev(cl)

def set_nick(+cl: Client, +nick: String) -> Client:
  match cl:
    case Client{_, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, bufs, active, now, stg, auth, log_seq}

def set_server(+cl: Client, +server: String) -> Client:
  match cl:
    case Client{+nick, _, +bufs, +active, +now, +stg, +auth, +log_seq}:
      Client{nick, server, bufs, active, now, stg, auth, log_seq}

# ---- drop buffer (PART/KICK self) ---------------------------------------

def remove_buf(+bufs: List<&2, Buffer>, +i: Nat) -> List<&2, Buffer>:
  +xs = bufs
  List.append(&2, Buffer, List.take(&2, Buffer, xs, i), List.drop(&2, Buffer, xs, 1n+i))

def clamp_active.pick(+last: Nat, +active: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      last
    case False{}:
      active

def clamp_active.ge(+nbufs: Nat, +active: Nat, ge: Bool) -> Nat:
  match nbufs:
    case 0n:
      0n
    case 1n+p:
      clamp_active.pick(p, active, ge)

def clamp_active(+nbufs: Nat, +active: Nat) -> Nat:
  clamp_active.ge(nbufs, active, Nat.is_ge(active, nbufs))

def drop_buf.act(+active: Nat, +bi: Nat, +nbufs2: Nat, shift: Bool) -> Nat:
  match shift:
    case True{}:
      Nat.sub(active, 1n)
    case False{}:
      clamp_active(nbufs2, active)

def drop_buf.go(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +auth: AuthPhase, +log_seq: Nat, +bi: Nat) -> Client:
  +bufs2 = remove_buf(bufs, bi)
  +stg2 = set_active.unread(stg, nth_buf(bufs, bi))
  +next = drop_buf.act(active, bi, buf_count(bufs2), Nat.is_gt(active, bi))
  set_active(Client{nick, server, bufs2, next, now, stg2, auth, log_seq}, next)

def drop_buf.body(+cl: Client, +bi: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq}:
      drop_buf.go(nick, server, bufs, active, now, stg, auth, log_seq, bi)

def drop_buf.keep(+cl: Client, +bi: Nat, is_server: Bool) -> Client:
  match is_server:
    case True{}:
      cl
    case False{}:
      drop_buf.body(cl, bi)

def drop_buf(+cl: Client, +bi: Nat) -> Client:
  drop_buf.keep(cl, bi, Nat.is_eq(bi, 0n))

def drop_buf.at(+cl: Client, found: Maybe<&2, Nat>) -> Client:
  match found:
    case None{}:
      cl
    case Some{+bi}:
      drop_buf(cl, bi)


def nick_of(+cl: Client) -> String:
  match cl:
    case Client{+nick, _, _, _, _, _, +auth, +log_seq}:
      nick

def server_of(+cl: Client) -> String:
  match cl:
    case Client{_, +server, _, _, _, _, +auth, +log_seq}:
      server

def active_nicks.on(got: Maybe<&2, Buffer>) -> List<&2, String>:
  match got:
    case None{}:
      Nil{}
    case Some{b}:
      match b:
        case Buffer{_, _, _, _, +nicks, _, _, _}:
          nicks

def active_nicks(+cl: Client) -> List<&2, String>:
  match cl:
    case Client{_, _, +bufs, +active, _, _, +auth, +log_seq}:
      active_nicks.on(nth_buf(bufs, active))

def active_buf_name.on(got: Maybe<&2, Buffer>) -> String:
  match got:
    case None{}:
      "server"
    case Some{b}:
      match b:
        case Buffer{+name, _, _, _, _, _, _, _}:
          name

def active_buf_name(+cl: Client) -> String:
  match cl:
    case Client{_, _, +bufs, +active, _, _, +auth, +log_seq}:
      active_buf_name.on(nth_buf(bufs, active))

def active_buf_lines.on(got: Maybe<&2, Buffer>) -> List<&2, Line>:
  match got:
    case None{}:
      Nil{}
    case Some{b}:
      match b:
        case Buffer{_, _, _, +lines, _, _, _, _}:
          lines

def active_buf_lines(+cl: Client) -> List<&2, Line>:
  match cl:
    case Client{_, _, +bufs, +active, _, _, +auth, +log_seq}:
      active_buf_lines.on(nth_buf(bufs, active))

def client_bufs(+cl: Client) -> List<&2, Buffer>:
  match cl:
    case Client{_, _, +bufs, _, _, _, +auth, +log_seq}:
      bufs

# ---- per-Sid allocation ceiling -------------------------------------------
# Multiserver slices share one bound owner: lines with id >= ceiling never
# admit, and the sequence clamps to ceiling-1 on overflow. Existing IDs
# (< ceiling) are preserved; overflow suffixes drop. Single-server paths
# never call these (unbounded).
def ceil_lines.keep(kept: Bool, +h: Line, +rest: List<&2, Line>) -> List<&2, Line>:
  match kept:
    case True{}: h <> rest
    case False{}: rest

def ceil_lines.buf(+h: Line, +rest: List<&2, Line>, +ceiling: Nat) -> List<&2, Line>:
  match h:
    case Line{+kind, +ts, +text, +author, +id}:
      ceil_lines.keep(Nat.is_lt(id, ceiling), Line{kind, ts, text, author, id}, rest)

def ceil_lines.go(+xs: List<&2, Line>, +ceiling: Nat) -> List<&2, Line>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      +rest = ceil_lines.go(t, ceiling)
      ceil_lines.buf(h, rest, ceiling)

def ceil_bufs.buf(+h: Buffer, +rest: List<&2, Buffer>, +ceiling: Nat) -> List<&2, Buffer>:
  match h:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll, _, _}:
      buf_indexed(name, ch, topic, ceil_lines.go(lines, ceiling), nicks, scroll) <> rest

def ceil_bufs.go(+xs: List<&2, Buffer>, +ceiling: Nat) -> List<&2, Buffer>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      +rest = ceil_bufs.go(t, ceiling)
      ceil_bufs.buf(h, rest, ceiling)

def ceil_seq.kept(fits: Bool, +seq: Nat, +ceiling: Nat) -> Nat:
  match fits:
    case True{}: seq
    case False{}: Nat.sub(ceiling, 1n)

def ceil_seq(+seq: Nat, +ceiling: Nat) -> Nat:
  ceil_seq.kept(Nat.is_lt(seq, ceiling), seq, ceiling)

def clamp_client_ceiling(+cl: Client, +ceiling: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +seq}:
      Client{nick, server, ceil_bufs.go(bufs, ceiling), active, now, stg, auth, ceil_seq(seq, ceiling)}

def client_overflows.kept(fits: Bool) -> Bool:
  match fits:
    case True{}: False{}
    case False{}: True{}

def client_overflows(+cl: Client, +ceiling: Nat) -> Bool:
  match cl:
    case Client{_, _, _, _, _, _, _, +seq}:
      client_overflows.kept(Nat.is_lt(seq, ceiling))
