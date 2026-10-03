# SPDX-License-Identifier: Apache-2.0
# Server 005 ISUPPORT policy (pure): channel/mode metadata and nick privileges.
#
# The server burst arrives as one or more `005` numerics; later tokens replace
# earlier ones. Unknown tokens are ignored so new server features cannot break
# the client. Malformed values keep the previous setting (fail closed).
#
# Defaults reproduce the long-standing fixed client behavior, so an absent
# burst changes nothing: channel types `#&+!`, STATUSMSG `@+`, prefix
# `(ov)@+` with the legacy extra roster sigils `~&%`, RFC 2812 NICKLEN 9, and
# the standard CHANMODES classes. A received PREFIX replaces the sigil set
# entirely: the server is authoritative once it speaks.
#
# A `-TOKEN` burst entry removes that token: the field returns to its default
# below, except `-STATUSMSG` which disables support entirely (the server
# offers no STATUSMSG). A removal takes no value: `-TOKEN=value` is
# malformed and keeps prior metadata. An empty `STATUSMSG=` instead clears
# the audience entirely. A bare `STATUSMSG` with no `=` keeps the previous
# value, like every other valueless token. A non-empty STATUSMSG must be a
# subset of the current PREFIX sigils; otherwise the previous value is kept.
#
# This module never stores channel keys. `redact_*` only decides which MODE
# arguments may render. Precise redaction needs every mode character
# classified and exact argument accounting; anything uncertain hides every
# argument, exactly like the client does today. `redact_wire`/`redact_line`
# dispatch MODE (target/flags/args at 0/1/2:) from numeric 324
# (recipient/target/flags/args at 0/1/2/3:); the 324 offsets stay correct
# because the leading recipient param is accounted for.
#
# Integrator: thread one State per endpoint, reset it on endpoint change, feed
# server lines through `feed` (source- and recipient-gated), gate JoinPlan
# admission through `join_admit`, route message audiences through
# `chan_target_cl` (exact resident first, STATUSMSG fallback second), and
# render MODE/324 arguments through `redact_wire`/`redact_line`. `apply_line`
# is parse-only and trusts its caller; use `feed` for wire input.
# Adopt `cm_eq`/`cm_fold` in Client/Buffer lookup, roster compare, draft
# identity, and View completion so every identity uses the negotiated
# CASEMAPPING; those shared modules are intentionally untouched here.
# `join_admit` reuses `Channels.valid` for every non-head check by swapping an
# advertised non-fixed head to `#` (one byte, same length); the original name
# must first pass `Cl.target_wire` and canonical equality, so a swapped check
# cannot admit reserved synthetics. If `valid` ever treats `#` specially,
# teach it the advertised set instead.
#
# Bend elaborates top-down here: every callee is defined before its caller,
# and only self-recursion is used.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./irc_commands.bend as Commands
import ./channel_policy.bend as Channels

type Chans is Data:
  Chans{types: String, status: String, list: String, arg: String, set: String, flag: String, per_line: U32, maxlist: String}

type Priv is Data:
  Priv{modes: String, sigils: String, extra: String}

type Limits is Data:
  Limits{nick: U32, channel: U32, topic: U32, kick: U32}

type State is Data:
  State{chans: Chans, priv: Priv, limits: Limits, network: String, casemapping: String, updated: Bool}

type KV is Data:
  KV{key: String, val: String, has_eq: Bool}

type Prefix is Data:
  Prefix{modes: String, sigils: String}

type ModeClass is Data:
  Unknown{}
  ListMode{}
  ArgMode{}
  SetMode{}
  FlagMode{}

type Walk is Data:
  Walk{adding: Bool, cursor: Nat, key: Maybe<&2, Nat>, ok: Bool}

type StripPh is Data:
  StripStr{}
  StripHit{h: Char, is_sig: Bool}

type RankPh is Data:
  RankStr{}
  RankHit{h: Char, is_sig: Bool}

# Granular defaults: `-TOKEN` removal restores exactly one of these.
def dflt_types() -> String:
  "#&+!"

def dflt_status() -> String:
  "@+"

def dflt_cm_a() -> String:
  "b"

def dflt_cm_b() -> String:
  "k"

def dflt_cm_c() -> String:
  "l"

def dflt_cm_d() -> String:
  "imnpst"

def dflt_mpl() -> U32:
  3

def dflt_maxlist() -> String:
  ""

def default_chans() -> Chans:
  Chans{dflt_types(), dflt_status(), dflt_cm_a(), dflt_cm_b(), dflt_cm_c(), dflt_cm_d(), dflt_mpl(), dflt_maxlist()}

def dflt_modes() -> String:
  "ov"

def dflt_sigils() -> String:
  "@+"

def dflt_extra() -> String:
  "~&%"

def default_priv() -> Priv:
  Priv{dflt_modes(), dflt_sigils(), dflt_extra()}

# RFC 2812 NICKLEN 9; the other lengths are common modern values and stay
# unenforced until a 005 burst arrives.
def dflt_nicklen() -> U32:
  9

def dflt_chanlen() -> U32:
  50

def dflt_topiclen() -> U32:
  390

def dflt_kicklen() -> U32:
  390

def default_limits() -> Limits:
  Limits{dflt_nicklen(), dflt_chanlen(), dflt_topiclen(), dflt_kicklen()}

def dflt_network() -> String:
  ""

def dflt_casemap() -> String:
  "rfc1459"

def defaults() -> State:
  State{default_chans(), default_priv(), default_limits(), dflt_network(), dflt_casemap(), False{}}

def HIDDEN() -> String:
  "[channel key hidden]"

# ---- character classes ----------------------------------------------------

def is_letter(+c: Char) -> Bool:
  match c:
    case Chr{+n}:
      (U32.is_ge(n, 65) && U32.is_le(n, 90)) || (U32.is_ge(n, 97) && U32.is_le(n, 122))

def all_letters(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, +t}: is_letter(h) && all_letters(t)

def is_symbol(+c: Char) -> Bool:
  match c:
    case Chr{+n}:
      U32.is_ge(n, 33) && U32.is_le(n, 126)
        && Bool.not((U32.is_ge(n, 48) && U32.is_le(n, 57)) || (U32.is_ge(n, 65) && U32.is_le(n, 90)) || (U32.is_ge(n, 97) && U32.is_le(n, 122)))
        && Bool.not(U32.is_eq(n, 44) || U32.is_eq(n, 58))

def all_symbols(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, +t}: is_symbol(h) && all_symbols(t)

def is_graphic(+c: Char) -> Bool:
  match c:
    case Chr{+n}: U32.is_ge(n, 33) && U32.is_le(n, 126)

def all_graphic(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, +t}: is_graphic(h) && all_graphic(t)

def decimal(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, t}: U32.is_ge(c, 48) && U32.is_le(c, 57) && decimal(t)

def has_char(+s: String, +c: Char) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{+h, +t}: Char.is_eq(h, c) || has_char(t, c)

# Truncated subtraction: a-b+b is a exactly when a outranks b.
def nat_max(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(Nat.add(Nat.sub(a, b), b), a), a, b)

# ---- token values ---------------------------------------------------------

def read_bounded.range(+n: U32, ok: Bool) -> Maybe<&2, U32>:
  match ok:
    case True{}: Some{n}
    case False{}: None{}

def read_bounded.num(+got: Maybe<&2, U32>, +lo: U32, +hi: U32) -> Maybe<&2, U32>:
  match got:
    case None{}: None{}
    case Some{+n}: read_bounded.range(n, U32.is_ge(n, lo) && U32.is_le(n, hi))

def read_bounded.checked(+val: String, ok: Bool, +lo: U32, +hi: U32) -> Maybe<&2, U32>:
  match ok:
    case False{}: None{}
    case True{}: read_bounded.num(U32.read(val), lo, hi)

def read_bounded(+val: String, +has_eq: Bool, +lo: U32, +hi: U32) -> Maybe<&2, U32>:
  read_bounded.checked(val, has_eq && Bool.not(String.is_empty(val)) && decimal(val), lo, hi)

def num_ok(+m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}: False{}
    case Some{_}: True{}

def split_eq.go(+s: String, +acc: String) -> KV:
  match s:
    case SNil{}: KV{String.reverse(acc), "", False{}}
    case SCon{Chr{61}, +t}: KV{String.reverse(acc), t, True{}}
    case SCon{+h, +t}: split_eq.go(t, SCon{h, acc})

def split_eq(+s: String) -> KV:
  split_eq.go(s, "")

def has_space(+s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{Chr{32}, _}: True{}
    case SCon{_, +t}: has_space(t)

# ---- single-token setters (invalid keeps the previous value) --------------

def chantypes_ok(+val: String) -> Bool:
  Bool.not(String.is_empty(val)) && Nat.is_le(String.length(val), 8n) && all_symbols(val)

def chantypes.set(+types: String, +status: String, +a: String, +b: String, +c: String, +d: String, +mpl: U32, +ml: String, +val: String, ok: Bool) -> Chans:
  match ok:
    case True{}: Chans{val, status, a, b, c, d, mpl, ml}
    case False{}: Chans{types, status, a, b, c, d, mpl, ml}

def chans_chantypes(+ch: Chans, +val: String, +has_eq: Bool) -> Chans:
  match ch:
    case Chans{+types, +status, +a, +b, +c, +d, +mpl, +ml}:
      chantypes.set(types, status, a, b, c, d, mpl, ml, val, has_eq && chantypes_ok(val))

def statusmsg.set(+types: String, +status: String, +a: String, +b: String, +c: String, +d: String, +mpl: U32, +ml: String, +val: String, ok: Bool) -> Chans:
  match ok:
    case True{}: Chans{types, val, a, b, c, d, mpl, ml}
    case False{}: Chans{types, status, a, b, c, d, mpl, ml}

# STATUSMSG must be a subset of the current PREFIX sigils: the server can
# only authorize audiences its prefix modes define. Empty clears regardless.
def statusmsg_subset.go(+val: String, +sigils: String) -> Bool:
  match val:
    case SNil{}: True{}
    case SCon{+h, +t}: has_char(sigils, h) && statusmsg_subset.go(t, sigils)

def statusmsg_subset(+val: String, +sigils: String) -> Bool:
  statusmsg_subset.go(val, sigils)

def priv_sigils_only(+pv: Priv) -> String:
  match pv:
    case Priv{_, +sig, _}: sig

def chans_statusmsg.sub(+ch: Chans, +sigils: String, +val: String, +has_eq: Bool) -> Chans:
  match ch:
    case Chans{+types, +status, +a, +b, +c, +d, +mpl, +ml}:
      statusmsg.set(types, status, a, b, c, d, mpl, ml, val, has_eq && (String.is_empty(val) || (chantypes_ok(val) && statusmsg_subset(val, sigils))))

def chans_statusmsg(+ch: Chans, +pv: Priv, +val: String, +has_eq: Bool) -> Chans:
  chans_statusmsg.sub(ch, priv_sigils_only(pv), val, has_eq)

def chanmodes.classes(+a: String, +b: String, +c: String, +d: String) -> Bool:
  all_letters(a) && all_letters(b) && all_letters(c) && all_letters(d)
    && Nat.is_le(String.length(a), 32n) && Nat.is_le(String.length(b), 32n)
    && Nat.is_le(String.length(c), 32n) && Nat.is_le(String.length(d), 32n)

def chans_chanmodes.keep(+types: String, +status: String, +oa: String, +ob: String, +oc: String, +od: String, +mpl: U32, +ml: String, +a: String, +b: String, +c: String, +d: String, ok: Bool) -> Chans:
  match ok:
    case True{}: Chans{types, status, a, b, c, d, mpl, ml}
    case False{}: Chans{types, status, oa, ob, oc, od, mpl, ml}

def chans_chanmodes.valid(+ch: Chans, +a: String, +b: String, +c: String, +d: String, ok: Bool) -> Chans:
  match ch:
    case Chans{+types, +status, +oa, +ob, +oc, +od, +mpl, +ml}:
      chans_chanmodes.keep(types, status, oa, ob, oc, od, mpl, ml, a, b, c, d, ok)

def chans_chanmodes.parts(+ch: Chans, +parts: List<&2, String>) -> Chans:
  match parts:
    case Con{+a, Con{+b, Con{+c, Con{+d, Nil{}}}}}:
      chans_chanmodes.valid(ch, a, b, c, d, chanmodes.classes(a, b, c, d))
    case _: ch

def chans_chanmodes(+ch: Chans, +val: String, +has_eq: Bool) -> Chans:
  match has_eq:
    case False{}: ch
    case True{}: chans_chanmodes.parts(ch, String.split(val, Chr{44}))

def chans_modes.got(+types: String, +status: String, +a: String, +b: String, +c: String, +d: String, +mpl: U32, +ml: String, +got: Maybe<&2, U32>) -> Chans:
  match got:
    case None{}: Chans{types, status, a, b, c, d, mpl, ml}
    case Some{+n}: Chans{types, status, a, b, c, d, n, ml}

def chans_modes(+ch: Chans, +val: String, +has_eq: Bool) -> Chans:
  match ch:
    case Chans{+types, +status, +a, +b, +c, +d, +mpl, +ml}:
      chans_modes.got(types, status, a, b, c, d, mpl, ml, read_bounded(val, has_eq, 1, 64))

def maxlist_parts(+parts: List<&2, String>) -> Bool:
  match parts:
    case Con{+modes, Con{+num, Nil{}}}:
      all_letters(modes) && Bool.not(String.is_empty(modes)) && Nat.is_le(String.length(modes), 8n)
        && num_ok(read_bounded(num, True{}, 1, 1000000))
    case _: False{}

def maxlist_item(+item: String) -> Bool:
  maxlist_parts(String.split(item, Chr{58}))

def maxlist_items.go(+xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, +t}: maxlist_item(h) && maxlist_items.go(t)

def maxlist_ok(+val: String) -> Bool:
  Bool.not(String.is_empty(val)) && Nat.is_le(String.length(val), 128n)
    && Nat.is_le(List.length(&2, String, String.split(val, Chr{44})), 16n)
    && maxlist_items.go(String.split(val, Chr{44}))

def chans_maxlist.set(+types: String, +status: String, +a: String, +b: String, +c: String, +d: String, +mpl: U32, +ml: String, +val: String, ok: Bool) -> Chans:
  match ok:
    case True{}: Chans{types, status, a, b, c, d, mpl, val}
    case False{}: Chans{types, status, a, b, c, d, mpl, ml}

def chans_maxlist(+ch: Chans, +val: String, +has_eq: Bool) -> Chans:
  match ch:
    case Chans{+types, +status, +a, +b, +c, +d, +mpl, +ml}:
      chans_maxlist.set(types, status, a, b, c, d, mpl, ml, val, has_eq && maxlist_ok(val))

def parse_prefix.valid(+modes: String, +sigils: String, ok: Bool) -> Maybe<&2, Prefix>:
  match ok:
    case True{}: Some{Prefix{modes, sigils}}
    case False{}: None{}

# Duplicate modes or sigils would make sigil_for/mode_for non-inverse
# (first match wins each way), so the whole PREFIX is rejected.
def nodup.go(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, +t}: Bool.not(has_char(t, h)) && nodup.go(t)

def parse_prefix.done(+modes: String, +sigils: String) -> Maybe<&2, Prefix>:
  parse_prefix.valid(modes, sigils, Bool.not(String.is_empty(modes)) && Nat.is_le(String.length(modes), 8n)
    && all_letters(modes) && all_symbols(sigils) && Nat.is_eq(String.length(modes), String.length(sigils))
    && nodup.go(modes) && nodup.go(sigils))

def parse_prefix.go(+s: String, +acc: String) -> Maybe<&2, Prefix>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{41}, +t}: parse_prefix.done(String.reverse(acc), t)
    case SCon{+h, +t}: parse_prefix.go(t, SCon{h, acc})

def parse_prefix.open(+val: String, open: Bool) -> Maybe<&2, Prefix>:
  match open:
    case False{}: None{}
    case True{}: parse_prefix.go(String.drop(val, 1n), "")

def parse_prefix(+val: String) -> Maybe<&2, Prefix>:
  parse_prefix.open(val, String.starts_with(val, "("))

def priv_prefix.set(+pf: Prefix) -> Priv:
  match pf:
    case Prefix{+modes, +sigils}: Priv{modes, sigils, ""}

def priv_prefix.parsed(+pv: Priv, +parsed: Maybe<&2, Prefix>) -> Priv:
  match parsed:
    case None{}: pv
    case Some{+pf}: priv_prefix.set(pf)

def priv_prefix(+pv: Priv, +val: String, +has_eq: Bool) -> Priv:
  match has_eq:
    case False{}: pv
    case True{}: priv_prefix.parsed(pv, parse_prefix(val))

def limits_nick.got(+nick: U32, +ch: U32, +tp: U32, +kk: U32, +got: Maybe<&2, U32>) -> Limits:
  match got:
    case None{}: Limits{nick, ch, tp, kk}
    case Some{+n}: Limits{n, ch, tp, kk}

def limits_nick(+lim: Limits, +val: String, +has_eq: Bool) -> Limits:
  match lim:
    case Limits{+nick, +ch, +tp, +kk}:
      limits_nick.got(nick, ch, tp, kk, read_bounded(val, has_eq, 1, 512))

def limits_channel.got(+nick: U32, +ch: U32, +tp: U32, +kk: U32, +got: Maybe<&2, U32>) -> Limits:
  match got:
    case None{}: Limits{nick, ch, tp, kk}
    case Some{+n}: Limits{nick, n, tp, kk}

def limits_channel(+lim: Limits, +val: String, +has_eq: Bool) -> Limits:
  match lim:
    case Limits{+nick, +ch, +tp, +kk}:
      limits_channel.got(nick, ch, tp, kk, read_bounded(val, has_eq, 1, 512))

def limits_topic.got(+nick: U32, +ch: U32, +tp: U32, +kk: U32, +got: Maybe<&2, U32>) -> Limits:
  match got:
    case None{}: Limits{nick, ch, tp, kk}
    case Some{+n}: Limits{nick, ch, n, kk}

def limits_topic(+lim: Limits, +val: String, +has_eq: Bool) -> Limits:
  match lim:
    case Limits{+nick, +ch, +tp, +kk}:
      limits_topic.got(nick, ch, tp, kk, read_bounded(val, has_eq, 1, 512))

def limits_kick.got(+nick: U32, +ch: U32, +tp: U32, +kk: U32, +got: Maybe<&2, U32>) -> Limits:
  match got:
    case None{}: Limits{nick, ch, tp, kk}
    case Some{+n}: Limits{nick, ch, tp, n}

def limits_kick(+lim: Limits, +val: String, +has_eq: Bool) -> Limits:
  match lim:
    case Limits{+nick, +ch, +tp, +kk}:
      limits_kick.got(nick, ch, tp, kk, read_bounded(val, has_eq, 1, 512))

def network_ok(+val: String) -> Bool:
  Bool.not(String.is_empty(val)) && Nat.is_le(String.length(val), 64n) && all_graphic(val)

def network.keep(+net: String, +val: String, ok: Bool) -> String:
  match ok:
    case True{}: val
    case False{}: net

def network.set(+net: String, +val: String, +has_eq: Bool) -> String:
  network.keep(net, val, has_eq && network_ok(val))

def casemap_rfc(+val: String, rfc: Bool) -> String:
  match rfc:
    case True{}: "rfc1459"
    case False{}: ""

def casemap_strict(+val: String, strict: Bool) -> String:
  match strict:
    case True{}: "rfc1459-strict"
    case False{}: casemap_rfc(val, Irc.ieq(val, "rfc1459"))

def casemap_ascii(+val: String, ascii: Bool) -> String:
  match ascii:
    case True{}: "ascii"
    case False{}: casemap_strict(val, Irc.ieq(val, "rfc1459-strict"))

# The legacy `strict-rfc1459` spelling names the same mapping; accept it.
def casemap_legacy(+val: String, legacy: Bool) -> String:
  match legacy:
    case True{}: "rfc1459-strict"
    case False{}: casemap_ascii(val, Irc.ieq(val, "ascii"))

def casemap_value(+val: String) -> String:
  casemap_legacy(val, Irc.ieq(val, "strict-rfc1459"))

def casemap.gated(+cm: String, +canon: String, ok: Bool) -> String:
  match ok:
    case True{}: canon
    case False{}: cm

def casemap.keep(+cm: String, +canon: String, +has_eq: Bool) -> String:
  casemap.gated(cm, canon, has_eq && Bool.not(String.is_empty(canon)))

def casemap.set(+cm: String, +val: String, +has_eq: Bool) -> String:
  casemap.keep(cm, casemap_value(val), has_eq)

# ---- negotiated casemapping compare ---------------------------------------
# ascii folds A-Z only; rfc1459-strict adds []\ <-> {|} but not ^~;
# rfc1459 (the default) also folds ^ <-> ~ via Irc.rfc1459.

def strict_code.rb(+n: U32, hit: Bool) -> U32:
  match hit:
    case True{}: 125
    case False{}: n

def strict_code.bs(+n: U32, hit: Bool) -> U32:
  match hit:
    case True{}: 124
    case False{}: strict_code.rb(n, U32.is_eq(n, 93))

def strict_code.lb(+n: U32, hit: Bool) -> U32:
  match hit:
    case True{}: 123
    case False{}: strict_code.bs(n, U32.is_eq(n, 92))

def strict_code(+n: U32) -> U32:
  strict_code.lb(n, U32.is_eq(n, 91))

def strict_char(+c: Char) -> Char:
  match c:
    case Chr{n}: Chr{strict_code(n)}

def strict.go(+s: String) -> String:
  match s:
    case SNil{}: SNil{}
    case SCon{+h, t}: SCon{strict_char(h), strict.go(t)}

def strict_fold(+s: String) -> String:
  strict.go(String.to_upper(s))

def cm_fold.cm(+cm: String, +s: String) -> String:
  match cm:
    case "ascii": String.to_upper(s)
    case "rfc1459-strict": strict_fold(s)
    case _: Irc.rfc1459(s)

def cm_fold(+st: State, +s: String) -> String:
  match st:
    case State{_, _, _, _, +cm, _}: cm_fold.cm(cm, s)

def cm_eq(+st: State, +a: String, +b: String) -> Bool:
  String.eq(cm_fold(st, a), cm_fold(st, b))

# ---- token application ----------------------------------------------------

# `-TOKEN` restores one field to its default, except `-STATUSMSG` which
# disables support (the server offers no STATUSMSG). Unknown removals
# change nothing.
def reset_chantypes(+ch: Chans) -> Chans:
  match ch:
    case Chans{_, +status, +a, +b, +c, +d, +mpl, +ml}:
      Chans{dflt_types(), status, a, b, c, d, mpl, ml}

def reset_statusmsg(+ch: Chans) -> Chans:
  match ch:
    case Chans{+types, _, +a, +b, +c, +d, +mpl, +ml}:
      Chans{types, "", a, b, c, d, mpl, ml}

def reset_chanmodes(+ch: Chans) -> Chans:
  match ch:
    case Chans{+types, +status, _, _, _, _, +mpl, +ml}:
      Chans{types, status, dflt_cm_a(), dflt_cm_b(), dflt_cm_c(), dflt_cm_d(), mpl, ml}

def reset_mpl(+ch: Chans) -> Chans:
  match ch:
    case Chans{+types, +status, +a, +b, +c, +d, _, +ml}:
      Chans{types, status, a, b, c, d, dflt_mpl(), ml}

def reset_maxlist(+ch: Chans) -> Chans:
  match ch:
    case Chans{+types, +status, +a, +b, +c, +d, +mpl, _}:
      Chans{types, status, a, b, c, d, mpl, dflt_maxlist()}

def reset_nicklen(+lim: Limits) -> Limits:
  match lim:
    case Limits{_, +ch, +tp, +kk}: Limits{dflt_nicklen(), ch, tp, kk}

def reset_chanlen(+lim: Limits) -> Limits:
  match lim:
    case Limits{+nick, _, +tp, +kk}: Limits{nick, dflt_chanlen(), tp, kk}

def reset_topiclen(+lim: Limits) -> Limits:
  match lim:
    case Limits{+nick, +ch, _, +kk}: Limits{nick, ch, dflt_topiclen(), kk}

def reset_kicklen(+lim: Limits) -> Limits:
  match lim:
    case Limits{+nick, +ch, +tp, _}: Limits{nick, ch, tp, dflt_kicklen()}

def reset_parts(+upper: String, +ch: Chans, +pv: Priv, +lim: Limits, +net: String, +cm: String, +upd: Bool) -> State:
  match upper:
    case "CHANTYPES": State{reset_chantypes(ch), pv, lim, net, cm, upd}
    case "PREFIX": State{ch, default_priv(), lim, net, cm, upd}
    case "CHANMODES": State{reset_chanmodes(ch), pv, lim, net, cm, upd}
    case "MODES": State{reset_mpl(ch), pv, lim, net, cm, upd}
    case "NICKLEN": State{ch, pv, reset_nicklen(lim), net, cm, upd}
    case "CHANNELLEN": State{ch, pv, reset_chanlen(lim), net, cm, upd}
    case "TOPICLEN": State{ch, pv, reset_topiclen(lim), net, cm, upd}
    case "KICKLEN": State{ch, pv, reset_kicklen(lim), net, cm, upd}
    case "STATUSMSG": State{reset_statusmsg(ch), pv, lim, net, cm, upd}
    case "NETWORK": State{ch, pv, lim, dflt_network(), cm, upd}
    case "CASEMAPPING": State{ch, pv, lim, net, dflt_casemap(), upd}
    case "MAXLIST": State{reset_maxlist(ch), pv, lim, net, cm, upd}
    case _: State{ch, pv, lim, net, cm, upd}

def reset_upper(+st: State, +upper: String) -> State:
  match st:
    case State{+ch, +pv, +lim, +net, +cm, +upd}:
      reset_parts(upper, ch, pv, lim, net, cm, upd)

def apply_parts(+upper: String, +val: String, +has_eq: Bool, +ch: Chans, +pv: Priv, +lim: Limits, +net: String, +cm: String, +upd: Bool) -> State:
  match upper:
    case "CHANTYPES": State{chans_chantypes(ch, val, has_eq), pv, lim, net, cm, upd}
    case "PREFIX": State{ch, priv_prefix(pv, val, has_eq), lim, net, cm, upd}
    case "CHANMODES": State{chans_chanmodes(ch, val, has_eq), pv, lim, net, cm, upd}
    case "MODES": State{chans_modes(ch, val, has_eq), pv, lim, net, cm, upd}
    case "NICKLEN": State{ch, pv, limits_nick(lim, val, has_eq), net, cm, upd}
    case "CHANNELLEN": State{ch, pv, limits_channel(lim, val, has_eq), net, cm, upd}
    case "TOPICLEN": State{ch, pv, limits_topic(lim, val, has_eq), net, cm, upd}
    case "KICKLEN": State{ch, pv, limits_kick(lim, val, has_eq), net, cm, upd}
    case "STATUSMSG": State{chans_statusmsg(ch, pv, val, has_eq), pv, lim, net, cm, upd}
    case "NETWORK": State{ch, pv, lim, network.set(net, val, has_eq), cm, upd}
    case "CASEMAPPING": State{ch, pv, lim, net, casemap.set(cm, val, has_eq), upd}
    case "MAXLIST": State{chans_maxlist(ch, val, has_eq), pv, lim, net, cm, upd}
    case _: State{ch, pv, lim, net, cm, upd}

def apply_upper(+st: State, +upper: String, +val: String, +has_eq: Bool) -> State:
  match st:
    case State{+ch, +pv, +lim, +net, +cm, +upd}:
      apply_parts(upper, val, has_eq, ch, pv, lim, net, cm, upd)

# A `-TOKEN` removal takes no value: `-NICKLEN` resets, but
# `-NICKLEN=garbage` (or `-NICKLEN=`) is malformed and keeps prior metadata.
def apply_key.reset(+st: State, +upper: String, +has_eq: Bool) -> State:
  match has_eq:
    case True{}: st
    case False{}: reset_upper(st, String.drop(upper, 1n))

def apply_key.neg(+st: State, +upper: String, +val: String, +has_eq: Bool, neg: Bool) -> State:
  match neg:
    case True{}: apply_key.reset(st, upper, has_eq)
    case False{}: apply_upper(st, upper, val, has_eq)

def apply_key(+st: State, +key: String, +val: String, +has_eq: Bool) -> State:
  apply_key.neg(st, String.to_upper(key), val, has_eq, String.starts_with(key, "-"))

def apply_kv(+st: State, kv: KV) -> State:
  match kv:
    case KV{+key, +val, +has_eq}: apply_key(st, key, val, has_eq)

def apply_checked(+st: State, +tok: String, skip: Bool) -> State:
  match skip:
    case True{}: st
    case False{}: apply_kv(st, split_eq(tok))

# Tokens never contain spaces, so this also drops the trailing human text
# ("are supported by this server") without matching its English wording.
def apply_token(+st: State, +tok: String) -> State:
  apply_checked(st, tok, has_space(tok))

def apply_step(st: State, tok: String) -> State:
  apply_token(st, tok)

def apply_tokens(+st: State, +toks: List<&2, String>) -> State:
  List.foldl(~&2, ~String, ~State, ~apply_step, toks, st)

def is_005(+m: Irc.Message) -> Bool:
  U32.is_eq(Irc.msg_num(m), 5)

def tokens_005(+m: Irc.Message) -> List<&2, String>:
  List.drop(&2, String, Irc.msg_params(m), 1n)

def mark_updated(+st: State) -> State:
  match st:
    case State{+ch, +pv, +lim, +net, +cm, _}: State{ch, pv, lim, net, cm, True{}}

def apply_msg.gated(+st: State, +m: Irc.Message, ok: Bool) -> State:
  match ok:
    case False{}: st
    case True{}: mark_updated(apply_tokens(st, tokens_005(m)))

def apply_msg(+st: State, +m: Irc.Message) -> State:
  apply_msg.gated(st, m, is_005(m))

def apply_parsed(+st: State, +parsed: Maybe<&2, Irc.Message>) -> State:
  match parsed:
    case None{}: st
    case Some{+m}: apply_msg(st, m)

def apply_line(+st: State, +line: String) -> State:
  apply_parsed(st, Irc.parse(line))

# ---- feed adapter (source- and recipient-gated) ---------------------------

# A 005 burst is addressed to one nick in its first param. A burst for
# another nick (misdirected or forged) must not alter our policy; compare
# with the negotiated casemapping. Non-005 lines are unaffected: apply_msg
# ignores them either way.
def recipient_ok.msg(+st: State, +me: String, +m: Irc.Message, is005: Bool) -> Bool:
  match is005:
    case False{}: True{}
    case True{}: cm_eq(st, Irc.msg_param(m, 0n), me)

def recipient_ok(+st: State, +me: String, +m: Irc.Message) -> Bool:
  recipient_ok.msg(st, me, m, is_005(m))

def feed.gated(+st: State, +cl: Cl.Client, +line: String, +m: Irc.Message, ok: Bool) -> State & Cl.Client:
  match ok:
    case True{}: (apply_msg(st, m), Feed.feed(cl, line))
    case False{}: (st, Feed.feed(cl, line))

def feed_parsed(+st: State, +cl: Cl.Client, +line: String, +parsed: Maybe<&2, Irc.Message>, source_ok: Bool) -> State & Cl.Client:
  match parsed:
    case None{}: (st, Feed.feed(cl, line))
    case Some{+m}: feed.gated(st, cl, line, m, source_ok && recipient_ok(st, Cl.nick_of(cl), m))

# Only the configured connection server may set metadata, and only through
# a burst addressed to our own nick. Anything else still logs to the server
# buffer exactly as today, but changes no state (not even `updated`).
def feed(+st: State, +cl: Cl.Client, +line: String) -> State & Cl.Client:
  feed_parsed(st, cl, line, Irc.parse(line), Irc.source_is_server(Irc.source_prefix(line), Cl.server_of(cl)))

def feed_state.pair(pair: State & Cl.Client) -> State:
  match pair:
    case (+st, _): st

def feed_state(+st: State, +cl: Cl.Client, +line: String) -> State:
  feed_state.pair(feed(st, cl, line))

def endpoint(+same: Bool, +st: State) -> State:
  match same:
    case True{}: st
    case False{}: defaults()

# ---- channel predicates ---------------------------------------------------

def head_in_types(+types: String, +t: String) -> Bool:
  match t:
    case SNil{}: False{}
    case SCon{+h2, _}: has_char(types, h2)

def is_channel.status(+types: String, +status: String, +t: String, pre: Bool) -> Bool:
  match pre:
    case False{}: False{}
    case True{}: head_in_types(types, t)

def is_channel.first(+types: String, +status: String, +h: Char, +t: String) -> Bool:
  has_char(types, h) || is_channel.status(types, status, t, has_char(status, h))

def is_channel.head(+types: String, +status: String, +name: String) -> Bool:
  match name:
    case SNil{}: False{}
    case SCon{+h, +t}: is_channel.first(types, status, h, t)

def is_channel.ch(+ch: Chans, +name: String) -> Bool:
  match ch:
    case Chans{+types, +status, _, _, _, _, _, _}: is_channel.head(types, status, name)

def is_channel(+st: State, +name: String) -> Bool:
  match st:
    case State{+ch, _, _, _, _, _}: is_channel.ch(ch, name)

def chan_target.tail(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{_, +t}: t

def chan_target.strip(+s: String, strip: Bool) -> String:
  match strip:
    case True{}: chan_target.tail(s)
    case False{}: s

def chan_target.head(+types: String, +status: String, +s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+h, +t}: chan_target.strip(SCon{h, t}, has_char(status, h) && head_in_types(types, t))

def chan_target.ch(+ch: Chans, +s: String) -> String:
  match ch:
    case Chans{+types, +status, _, _, _, _, _, _}: chan_target.head(types, status, s)

def chan_target(+st: State, +s: String) -> String:
  match st:
    case State{+ch, _, _, _, _, _}: chan_target.ch(ch, s)

# Resident-first audience routing (mirrors Cl.message_key): a `+` channel may
# itself be named `+#room`, so an exact resident buffer keeps its full name
# and only a non-resident audience falls back to STATUSMSG stripping.
def chan_target_cl.found(+st: State, +s: String, found: Maybe<&2, Nat>) -> String:
  match found:
    case Some{_}: s
    case None{}: chan_target(st, s)

def chan_target_cl(+st: State, +cl: Cl.Client, +s: String) -> String:
  chan_target_cl.found(st, s, Cl.buf_find(cl, s))

# ---- nick privileges ------------------------------------------------------

def priv_sigils(+pv: Priv) -> String:
  match pv:
    case Priv{_, +sig, +extra}: sig ++ extra

def strip_set(+st: State) -> String:
  match st:
    case State{_, +pv, _, _, _, _}: priv_sigils(pv)

# Two fuel steps per character: read the head, then act on the membership test.
# Only the leading sigil run is stripped; the first plain character keeps the
# whole untouched tail, so interior sigils (`a^b`) survive.
def strip.go(fuel: Nat, ph: StripPh, +sig: String, s: String) -> String:
  match fuel:
    case 0n: ""
    case 1n+p:
      match ph:
        case StripStr{}:
          match s:
            case SNil{}: ""
            case SCon{+h, +t}: strip.go(p, StripHit{h, has_char(sig, h)}, sig, t)
        case StripHit{h, is_sig}:
          match is_sig:
            case True{}: strip.go(p, StripStr{}, sig, s)
            case False{}: SCon{h, s}

def strip_go(+sig: String, +s: String) -> String:
  strip.go(Nat.add(1n, Nat.mul(2n, String.length(s))), StripStr{}, sig, s)

def strip(+st: State, +s: String) -> String:
  strip_go(strip_set(st), s)

def index_first(+parts: List<&2, String>) -> Nat:
  match parts:
    case Nil{}: 0n
    case Con{+h, _}: String.length(h)

def index_of.member(+s: String, +c: Char, member: Bool) -> Maybe<&2, Nat>:
  match member:
    case False{}: None{}
    case True{}: Some{index_first(String.split(s, c))}

def index_of(+s: String, +c: Char) -> Maybe<&2, Nat>:
  index_of.member(s, c, has_char(s, c))

def char_at(+s: String, +i: Nat) -> String:
  String.take(String.drop(s, i), 1n)

def sigil_at(+sig: String, +idx: Maybe<&2, Nat>) -> String:
  match idx:
    case None{}: ""
    case Some{+i}: char_at(sig, i)

def sigil_for.priv(+pv: Priv, +mode: Char) -> String:
  match pv:
    case Priv{+modes, +sig, _}: sigil_at(sig, index_of(modes, mode))

def sigil_for(+st: State, +mode: Char) -> String:
  match st:
    case State{_, +pv, _, _, _, _}: sigil_for.priv(pv, mode)

def mode_for.priv(+pv: Priv, +sigil: Char) -> String:
  match pv:
    case Priv{+modes, +sig, _}: sigil_at(modes, index_of(sig, sigil))

def mode_for(+st: State, +sigil: Char) -> String:
  match st:
    case State{_, +pv, _, _, _, _}: mode_for.priv(pv, sigil)

def rank_of.idx(+sig: String, +idx: Maybe<&2, Nat>) -> Nat:
  match idx:
    case None{}: 0n
    case Some{+i}: Nat.sub(String.length(sig), i)

def rank_of(+sig: String, +c: Char) -> Nat:
  rank_of.idx(sig, index_of(sig, c))

def rank.go(fuel: Nat, ph: RankPh, +strip_set: String, +ranked: String, s: String, +best: Nat) -> Nat:
  match fuel:
    case 0n: best
    case 1n+p:
      match ph:
        case RankStr{}:
          match s:
            case SNil{}: best
            case SCon{+h, +t}: rank.go(p, RankHit{h, has_char(strip_set, h)}, strip_set, ranked, t, best)
        case RankHit{h, is_sig}:
          match is_sig:
            case False{}: best
            case True{}: rank.go(p, RankStr{}, strip_set, ranked, s, nat_max(best, rank_of(ranked, h)))

def rank_go(+strip_set: String, +ranked: String, +s: String) -> Nat:
  rank.go(Nat.add(1n, Nat.mul(2n, String.length(s))), RankStr{}, strip_set, ranked, s, 0n)

def rank.priv(+pv: Priv, +s: String) -> Nat:
  match pv:
    case Priv{_, +sig, +extra}: rank_go(sig ++ extra, sig, s)

# Higher means more privilege; 0 means none. Unknown sigils strip for roster
# compatibility but rank lowest.
def rank(+st: State, +s: String) -> Nat:
  match st:
    case State{_, +pv, _, _, _, _}: rank.priv(pv, s)

def leading_run(+set: String, +s: String) -> String:
  String.take(s, Nat.sub(String.length(s), String.length(strip_go(set, s))))

def has_sigil.run(+run: String, +want: String) -> Bool:
  match want:
    case SNil{}: False{}
    case SCon{+w, _}: has_char(run, w)

def has_mode(+st: State, +raw: String, +mode: Char) -> Bool:
  has_sigil.run(leading_run(strip_set(st), raw), sigil_for(st, mode))

# ---- mode classes ---------------------------------------------------------

def mode_class.flag(hit: Bool) -> ModeClass:
  match hit:
    case True{}: FlagMode{}
    case False{}: Unknown{}

def mode_class.d(+d: String, +mode: Char, hit_c: Bool) -> ModeClass:
  match hit_c:
    case True{}: SetMode{}
    case False{}: mode_class.flag(has_char(d, mode))

def mode_class.c(+c: String, +d: String, +mode: Char, hit_b: Bool) -> ModeClass:
  match hit_b:
    case True{}: ArgMode{}
    case False{}: mode_class.d(d, mode, has_char(c, mode))

def mode_class.b(+b: String, +c: String, +d: String, +mode: Char, hit_a: Bool) -> ModeClass:
  match hit_a:
    case True{}: ListMode{}
    case False{}: mode_class.c(c, d, mode, has_char(b, mode))

def mode_class.chan(+a: String, +b: String, +c: String, +d: String, +mode: Char) -> ModeClass:
  mode_class.b(b, c, d, mode, has_char(a, mode))

def mode_class.pick(+a: String, +b: String, +c: String, +d: String, +mode: Char, is_priv: Bool) -> ModeClass:
  match is_priv:
    case True{}: ArgMode{}
    case False{}: mode_class.chan(a, b, c, d, mode)

def mode_class.priv(+a: String, +b: String, +c: String, +d: String, +pv: Priv, +mode: Char) -> ModeClass:
  match pv:
    case Priv{+modes, _, _}: mode_class.pick(a, b, c, d, mode, has_char(modes, mode))

def mode_class.in(+ch: Chans, +pv: Priv, +mode: Char) -> ModeClass:
  match ch:
    case Chans{_, _, +a, +b, +c, +d, _, _}: mode_class.priv(a, b, c, d, pv, mode)

# Prefix modes always take a nick argument. Unknown modes are Unknown.
def mode_class(+st: State, +mode: Char) -> ModeClass:
  match st:
    case State{+ch, +pv, _, _, _, _}: mode_class.in(ch, pv, mode)

def takes_arg.class(+cls: ModeClass, +adding: Bool) -> Bool:
  match cls:
    case Unknown{}: True{}
    case ListMode{}: True{}
    case ArgMode{}: True{}
    case SetMode{}: adding
    case FlagMode{}: False{}

# Unknown modes consume an argument slot (fail closed for accounting).
def takes_arg(+st: State, +mode: Char, +adding: Bool) -> Bool:
  takes_arg.class(mode_class(st, mode), adding)

# ---- secret-safe MODE redaction -------------------------------------------

def suspicious(+st: State, +target: String, +flags: String, +args: List<&2, String>) -> Bool:
  (is_channel(st, target) || Irc.starts_channel(target))
    && Commands.mode.sign(flags) && Commands.mode.flag_chars(flags)
    && String.contains(flags, "k")
    && Bool.not(List.is_empty(&2, String, args))

def walk_key.again(+adding: Bool, +next: Nat, +key: Maybe<&2, Nat>, +ok: Bool) -> Walk:
  match key:
    case None{}: Walk{adding, next, Some{Nat.sub(next, 1n)}, ok}
    case Some{_}: Walk{adding, next, key, False{}}

def walk_key(+adding: Bool, +next: Nat, +key: Maybe<&2, Nat>, +ok: Bool, is_k: Bool) -> Walk:
  match is_k:
    case True{}: walk_key.again(adding, next, key, ok)
    case False{}: Walk{adding, next, key, ok}

def walk_take(+h: Char, +adding: Bool, +cursor: Nat, +key: Maybe<&2, Nat>, +ok: Bool, take: Bool) -> Walk:
  match take:
    case False{}: Walk{adding, cursor, key, ok}
    case True{}: walk_key(adding, Nat.add(cursor, 1n), key, ok, Char.is_eq(h, Chr{107}))

def walk_class(+cls: ModeClass, +h: Char, +adding: Bool, +cursor: Nat, +key: Maybe<&2, Nat>, +ok: Bool) -> Walk:
  match cls:
    case Unknown{}: Walk{adding, cursor, key, False{}}
    case ListMode{}: walk_take(h, adding, cursor, key, ok, True{})
    case ArgMode{}: walk_take(h, adding, cursor, key, ok, True{})
    case SetMode{}: walk_take(h, adding, cursor, key, ok, adding)
    case FlagMode{}: Walk{adding, cursor, key, ok}

def walk_arg(+st: State, +h: Char, +adding: Bool, +cursor: Nat, +key: Maybe<&2, Nat>, +ok: Bool) -> Walk:
  walk_class(mode_class(st, h), h, adding, cursor, key, ok)

def walk_minus(+st: State, +h: Char, +adding: Bool, +cursor: Nat, +key: Maybe<&2, Nat>, +ok: Bool, minus: Bool) -> Walk:
  match minus:
    case True{}: Walk{False{}, cursor, key, ok}
    case False{}: walk_arg(st, h, adding, cursor, key, ok)

def walk_sign(+st: State, +h: Char, +adding: Bool, +cursor: Nat, +key: Maybe<&2, Nat>, +ok: Bool, plus: Bool, minus: Bool) -> Walk:
  match plus:
    case True{}: Walk{True{}, cursor, key, ok}
    case False{}: walk_minus(st, h, adding, cursor, key, ok, minus)

def walk_mode(+st: State, +h: Char, +adding: Bool, +cursor: Nat, +key: Maybe<&2, Nat>, +ok: Bool) -> Walk:
  walk_sign(st, h, adding, cursor, key, ok, Char.is_eq(h, Chr{43}), Char.is_eq(h, Chr{45}))

def walk_char(+st: State, +h: Char, +w: Walk) -> Walk:
  match w:
    case Walk{+adding, +cursor, +key, +ok}: walk_mode(st, h, adding, cursor, key, ok)

def walk_flags(+st: State, +flags: String, +w: Walk) -> Walk:
  match flags:
    case SNil{}: w
    case SCon{+h, +t}: walk_flags(st, t, walk_char(st, h, w))

def key_exact(+key: Maybe<&2, Nat>, exact: Bool) -> Maybe<&2, Nat>:
  match exact:
    case False{}: None{}
    case True{}: key

def key_done(+w: Walk, +nargs: Nat) -> Maybe<&2, Nat>:
  match w:
    case Walk{_, +cursor, +key, +ok}: key_exact(key, Nat.is_eq(cursor, nargs) && ok)

# The key argument index, when every mode character is classified, no key
# repeats, and consumed arguments exactly equal supplied arguments.
def key_index(+st: State, +flags: String, +args: List<&2, String>) -> Maybe<&2, Nat>:
  key_done(walk_flags(st, flags, Walk{True{}, 0n, None{}, True{}}), List.length(&2, String, args))

def replace_at(+xs: List<&2, String>, +i: Nat, +v: String) -> List<&2, String>:
  List.append(&2, String, List.take(&2, String, xs, i), v <> List.drop(&2, String, xs, Nat.add(i, 1n)))

def redact.known(+args: List<&2, String>, +idx: Maybe<&2, Nat>) -> List<&2, String>:
  match idx:
    case None{}: HIDDEN() <> Nil{}
    case Some{+i}: replace_at(args, i, HIDDEN())

def redact.suspicious(+st: State, +flags: String, +args: List<&2, String>, bad: Bool) -> List<&2, String>:
  match bad:
    case False{}: args
    case True{}: redact.known(args, key_index(st, flags, args))

def redact_params(+st: State, +target: String, +flags: String, +args: List<&2, String>) -> List<&2, String>:
  redact.suspicious(st, flags, args, suspicious(st, target, flags, args))

def redact_msg(+st: State, +m: Irc.Message) -> List<&2, String>:
  redact_params(st, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), List.drop(&2, String, Irc.msg_params(m), 2n))

def is_324(+m: Irc.Message) -> Bool:
  U32.is_eq(Irc.msg_num(m), 324)

# Numeric 324 carries a leading recipient param (`324 me #c +k secret`), so
# its target/flags/args sit one slot later than a MODE command's.
def redact_324(+st: State, +m: Irc.Message) -> List<&2, String>:
  redact_params(st, Irc.msg_param(m, 1n), Irc.msg_param(m, 2n), List.drop(&2, String, Irc.msg_params(m), 3n))

def redact_wire.num(+st: State, +m: Irc.Message, is324: Bool) -> List<&2, String>:
  match is324:
    case True{}: redact_324(st, m)
    case False{}: Irc.msg_params(m)

def redact_wire.mode(+st: State, +m: Irc.Message, mode: Bool) -> List<&2, String>:
  match mode:
    case True{}: redact_msg(st, m)
    case False{}: redact_wire.num(st, m, is_324(m))

# Wire entry: MODE and 324 return the redacted argument tail; any other
# message returns its params unchanged (nothing mode-shaped to redact).
def redact_wire(+st: State, +m: Irc.Message) -> List<&2, String>:
  redact_wire.mode(st, m, String.eq(Irc.msg_command(m), "MODE"))

def redact_line.parsed(+st: State, +parsed: Maybe<&2, Irc.Message>) -> List<&2, String>:
  match parsed:
    case None{}: Nil{}
    case Some{+m}: redact_wire(st, m)

def redact_line(+st: State, +line: String) -> List<&2, String>:
  redact_line.parsed(st, Irc.parse(line))

# ---- join admission adapter -----------------------------------------------

def first_in_types(+types: String, +name: String) -> Bool:
  match name:
    case SNil{}: False{}
    case SCon{+h, _}: has_char(types, h)

def join_len.types(+types: String, +lim: Limits, +name: String) -> Bool:
  match lim:
    case Limits{_, +maxlen, _, _}: first_in_types(types, name) && Nat.is_le(Irc.utf8_len(name), U32.to_nat(maxlen))

def join_len.check(+ch: Chans, +lim: Limits, +name: String) -> Bool:
  match ch:
    case Chans{+types, _, _, _, _, _, _, _}: join_len.types(types, lim, name)

def join_len.lim(+ch: Chans, +lim: Limits, +name: String, upd: Bool) -> Bool:
  match upd:
    case False{}: True{}
    case True{}: join_len.check(ch, lim, name)

def join_len(+st: State, +name: String) -> Bool:
  match st:
    case State{+ch, _, +lim, _, _, +upd}: join_len.lim(ch, lim, name, upd)

# A server may advertise channel types outside the fixed `#&+!` set (for
# example `CHANTYPES=$`). The base check rejects those heads, so retry with
# the advertised head swapped to `#`: one ASCII byte either way, which keeps
# every other base rule (length, commas, word bounds, wire envelope) intact.
# The swap validates the tail only; the original identity must first pass
# the reserved/synthetic policy and canonical equality, so CHANTYPES=*
# cannot admit *log*/*LOG* through a swapped #log* check.
def join_swap.check(+st: State, +name: String, +key: String, +t: String, adv: Bool) -> Bool:
  match adv:
    case False{}: False{}
    case True{}: Cl.target_wire(name) && String.eq(name, Cl.target_name(name)) && Channels.valid("#" ++ t, key) && join_len(st, name)

def join_swap.head(+st: State, +name: String, +key: String, +types: String) -> Bool:
  match name:
    case SNil{}: False{}
    case SCon{+h, +t}: join_swap.check(st, name, key, t, has_char(types, h))

def join_swap.types(+st: State, +ch: Chans, +name: String, +key: String) -> Bool:
  match ch:
    case Chans{+types, _, _, _, _, _, _, _}: join_swap.head(st, name, key, types)

def join_swap.upd(+st: State, +ch: Chans, +name: String, +key: String, upd: Bool) -> Bool:
  match upd:
    case False{}: False{}
    case True{}: join_swap.types(st, ch, name, key)

def join_swap(+st: State, +name: String, +key: String) -> Bool:
  match st:
    case State{+ch, _, _, _, _, +upd}: join_swap.upd(st, ch, name, key, upd)

def join_admit.base(+st: State, +name: String, +key: String, base: Bool) -> Bool:
  match base:
    case False{}: join_swap(st, name, key)
    case True{}: join_len(st, name)

# Base channel policy applies first; server bounds (types, CHANNELLEN) add
# on only after a 005 burst, so an absent burst changes nothing. A base
# rejection retries through the advertised-type swap above, so `is_channel`
# and `join_admit` agree on every advertised type.
def join_admit(+st: State, +name: String, +key: String) -> Bool:
  join_admit.base(st, name, key, Channels.valid(name, key))

# ---- accessors ------------------------------------------------------------

def limits.nick(+lim: Limits) -> U32:
  match lim:
    case Limits{+nick, _, _, _}: nick

def nicklen(+st: State) -> U32:
  match st:
    case State{_, _, +lim, _, _, _}: limits.nick(lim)

def limits.channel(+lim: Limits) -> U32:
  match lim:
    case Limits{_, +ch, _, _}: ch

def channellen(+st: State) -> U32:
  match st:
    case State{_, _, +lim, _, _, _}: limits.channel(lim)

def limits.topic(+lim: Limits) -> U32:
  match lim:
    case Limits{_, _, +tp, _}: tp

def topiclen(+st: State) -> U32:
  match st:
    case State{_, _, +lim, _, _, _}: limits.topic(lim)

def limits.kick(+lim: Limits) -> U32:
  match lim:
    case Limits{_, _, _, +kk}: kk

def kicklen(+st: State) -> U32:
  match st:
    case State{_, _, +lim, _, _, _}: limits.kick(lim)

def chans.per_line(+ch: Chans) -> U32:
  match ch:
    case Chans{_, _, _, _, _, _, +mpl, _}: mpl

def modes_per_line(+st: State) -> U32:
  match st:
    case State{+ch, _, _, _, _, _}: chans.per_line(ch)

def chans.maxlist(+ch: Chans) -> String:
  match ch:
    case Chans{_, _, _, _, _, _, _, +ml}: ml

def maxlist(+st: State) -> String:
  match st:
    case State{+ch, _, _, _, _, _}: chans.maxlist(ch)

def updated(+st: State) -> Bool:
  match st:
    case State{_, _, _, _, _, +upd}: upd

def network(+st: State) -> String:
  match st:
    case State{_, _, _, +net, _, _}: net

def casemapping(+st: State) -> String:
  match st:
    case State{_, _, _, _, +cm, _}: cm

# ---- canonical rendering (goldens) ----------------------------------------

def show_bool(+b: Bool) -> String:
  match b:
    case True{}: "true"
    case False{}: "false"

def show.limits(+types: String, +status: String, +a: String, +b: String, +c: String, +d: String, +mpl: U32, +ml: String, +modes: String, +sig: String, +extra: String, +lim: Limits, +net: String, +cm: String, +upd: Bool) -> String:
  match lim:
    case Limits{+nick, +chan, +topic, +kick}:
      "isupport chantypes=" ++ types ++ " status=" ++ status
        ++ " chanmodes=" ++ a ++ "," ++ b ++ "," ++ c ++ "," ++ d
        ++ " modes=" ++ U32.show(mpl)
        ++ " prefix=(" ++ modes ++ ")" ++ sig
        ++ " extra=" ++ extra
        ++ " nicklen=" ++ U32.show(nick)
        ++ " channellen=" ++ U32.show(chan)
        ++ " topiclen=" ++ U32.show(topic)
        ++ " kicklen=" ++ U32.show(kick)
        ++ " network=" ++ net ++ " casemapping=" ++ cm
        ++ " maxlist=" ++ ml ++ " updated=" ++ show_bool(upd)

def show.priv(+types: String, +status: String, +a: String, +b: String, +c: String, +d: String, +mpl: U32, +ml: String, +pv: Priv, +lim: Limits, +net: String, +cm: String, +upd: Bool) -> String:
  match pv:
    case Priv{+modes, +sig, +extra}:
      show.limits(types, status, a, b, c, d, mpl, ml, modes, sig, extra, lim, net, cm, upd)

def show.chans(+ch: Chans, +pv: Priv, +lim: Limits, +net: String, +cm: String, +upd: Bool) -> String:
  match ch:
    case Chans{+types, +status, +a, +b, +c, +d, +mpl, +ml}:
      show.priv(types, status, a, b, c, d, mpl, ml, pv, lim, net, cm, upd)

def show(+st: State) -> String:
  match st:
    case State{+ch, +pv, +lim, +net, +cm, +upd}:
      show.chans(ch, pv, lim, net, cm, upd)
