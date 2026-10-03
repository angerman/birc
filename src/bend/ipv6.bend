# SPDX-License-Identifier: Apache-2.0
# Pure IPv6 policy: bracketed literal endpoints, AAAA DNS, socket-family plan.
# No IO. Adapters reuse Endpoint (ports) and dns_wire (labels, names, records);
# Endpoint.parse itself keeps refusing IPv6, so existing laws stay green.
# v1 limits (fail closed): dotted tails (::ffff:1.2.3.4) and %zone ids are
# rejected by the hex-group rule; AAAA text uses uncompressed lowercase groups.
import Base
import ./endpoint.bend as Endpoint
import ./dns_wire.bend as Wire

# Bracketed input bound: 45 text bytes + brackets + ':' + five port digits.
def MAX_V6_INPUT() -> Nat:
  64n

def AAAA_QTYPE() -> U32:
  28

# ---- hex groups ------------------------------------------------------------

def hex_digit(+c: U32) -> Bool:
  (U32.is_ge(c, 48) && U32.is_le(c, 57))
    || (U32.is_ge(c, 97) && U32.is_le(c, 102))
    || (U32.is_ge(c, 65) && U32.is_le(c, 70))

def hex_go(s: String, +n: Nat) -> Bool:
  match s:
    case SNil{}:
      Nat.is_ge(n, 1n) && Nat.is_le(n, 4n)
    case SCon{+h, t}:
      hex_digit(Char.to_u32(h)) && hex_go(t, Nat.add(n, 1n))

def hex1_4(+s: String) -> Bool:
  hex_go(s, 0n)

# Token scan over ':'-separated groups. gap: '::' consumed; pend/pend2: a run
# of one/two empty tokens is open. No lookahead: a run of two is accepted
# tentatively and the end state decides (trailing "::" only).
def v6_tok(xs: List<&2, String>, +n: Nat, +gap: Bool, +pend: Bool, +pend2: Bool) -> Bool:
  match xs:
    case Nil{}:
      +c_trail = pend2 && Bool.not(gap) && Nat.is_ge(n, 1n) && Nat.is_le(n, 7n)
      +c_open = Bool.not(pend2) && Bool.not(pend)
      +c_gap = c_open && gap && Nat.is_le(n, 7n)
      +c_full = c_open && Bool.not(gap) && Nat.is_eq(n, 8n)
      c_trail || c_gap || c_full
    case Con{+h, +t}:
      +empty = String.is_empty(h)
      +hex = hex1_4(h)
      +lead = Nat.is_eq(n, 0n)
      +e_pair = empty && Bool.not(pend2) && pend
      +e_open = empty && Bool.not(pend2) && Bool.not(pend)
      +f_pair = Bool.not(empty) && hex && pend2 && lead && Bool.not(gap)
      +f_mid = Bool.not(empty) && hex && Bool.not(pend2) && pend && Bool.not(lead) && Bool.not(gap)
      +f_plain = Bool.not(empty) && hex && Bool.not(pend2) && Bool.not(pend)
      (e_pair && v6_tok(t, n, gap, False{}, True{}))
        || (e_open && v6_tok(t, n, gap, True{}, False{}))
        || (f_pair && v6_tok(t, 1n, True{}, False{}, False{}))
        || (f_mid && v6_tok(t, Nat.add(n, 1n), True{}, False{}, False{}))
        || (f_plain && v6_tok(t, Nat.add(n, 1n), gap, False{}, False{}))

def valid_inner(+s: String) -> Bool:
  +len = String.length(s)
  Nat.is_ge(len, 2n) && Nat.is_le(len, 45n)
    && (String.eq(s, "::") || v6_tok(String.split(s, Chr{58}), 0n, False{}, False{}, False{}))

# ---- bracketed endpoints ----------------------------------------------------

type Family is Data:
  V4{}
  V6{}

type EndpointV is Data:
  EndpointV{host: String, port: Maybe<&2, U32>, family: Family}

type Bracket is Data:
  Bracket{inner: String, rest: String}

def scan_bracket(s: String, +acc: String) -> Maybe<&2, Bracket>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{93}, t}: Some{Bracket{String.reverse(acc), t}}
    case SCon{Chr{91}, _}: None{}
    case SCon{+h, t}: scan_bracket(t, SCon{h, acc})

def parse_v6.ported(ok: Bool, +inner: String, +n: U32) -> Result<&2, &2, String, EndpointV>:
  match ok:
    case False{}: Fail{"bad endpoint"}
    case True{}: Done{EndpointV{inner, Some{n}, V6{}}}

# Port errors dominate, mirroring Endpoint.parse.parts on "host:badport".
def parse_v6.port(+inner: String, got: Maybe<&2, U32>) -> Result<&2, &2, String, EndpointV>:
  match got:
    case None{}: Fail{"bad port"}
    case Some{+n}: parse_v6.ported(valid_inner(inner), inner, n)

def parse_v6.naked(ok: Bool, +inner: String) -> Result<&2, &2, String, EndpointV>:
  match ok:
    case False{}: Fail{"bad endpoint"}
    case True{}: Done{EndpointV{inner, None{}, V6{}}}

def parse_v6.rest(+inner: String, rest: String) -> Result<&2, &2, String, EndpointV>:
  match rest:
    case SNil{}: parse_v6.naked(valid_inner(inner), inner)
    case SCon{Chr{58}, +p}:
      parse_v6.port(inner, Endpoint.port(p))
    case _: Fail{"bad endpoint"}

def parse_v6.nonempty(empty: Bool, +inner: String, rest: String) -> Result<&2, &2, String, EndpointV>:
  match empty:
    case True{}: Fail{"bad endpoint"}
    case False{}: parse_v6.rest(inner, rest)

def parse_v6.paired(+pair: Bracket) -> Result<&2, &2, String, EndpointV>:
  match pair:
    case Bracket{+inner, +rest}: parse_v6.nonempty(String.is_empty(inner), inner, rest)

def parse_v6.bracket(m: Maybe<&2, Bracket>) -> Result<&2, &2, String, EndpointV>:
  match m:
    case None{}: Fail{"bad endpoint"}
    case Some{+pair}: parse_v6.paired(pair)

def parse_v6.open(+text: String) -> Result<&2, &2, String, EndpointV>:
  match text:
    case SCon{Chr{91}, t}: parse_v6.bracket(scan_bracket(t, ""))
    case _: Fail{"bad endpoint"}

def parse_v6.len(ok: Bool, +text: String) -> Result<&2, &2, String, EndpointV>:
  match ok:
    case False{}: Fail{"bad endpoint"}
    case True{}: parse_v6.open(text)

# Bracketed literals only. A bare "::1" stays ambiguous with host:port and is
# refused here, exactly as Endpoint.parse refuses it.
def parse_v6(+text: String) -> Result<&2, &2, String, EndpointV>:
  parse_v6.len(Nat.is_le(String.length(text), MAX_V6_INPUT()), text)

def parse_any.fallback(r: Result<&2, &2, String, Endpoint.Endpoint>, +text: String) -> Result<&2, &2, String, EndpointV>:
  match r:
    case Done{e}:
      match e:
        case Endpoint.Endpoint{+host, +port}: Done{EndpointV{host, port, V4{}}}
    case Fail{_}: parse_v6(text)

# IPv4/DNS keeps Endpoint spelling and errors; brackets select IPv6.
def parse_any(+text: String) -> Result<&2, &2, String, EndpointV>:
  parse_any.fallback(Endpoint.parse(text), text)

type Resolved is Data:
  Resolved{host: String, port: U32, family: Family}

def resolve.selected(selected: Maybe<&2, U32>, +host: String, +family: Family) -> Maybe<&2, Resolved>:
  match selected:
    case None{}: None{}
    case Some{+n}: Some{Resolved{host, n, family}}

def resolve(ep: EndpointV, separate: Maybe<&2, U32>, fallback: U32) -> Maybe<&2, Resolved>:
  match ep:
    case EndpointV{+host, +port, +family}:
      resolve.selected(Endpoint.select_port(port, separate, fallback), host, family)

def family_of(+ep: EndpointV) -> Family:
  match ep:
    case EndpointV{_, _, +family}: family

def is_v6.go(fam: Family) -> Bool:
  match fam:
    case V6{}: True{}
    case V4{}: False{}

def is_v6(+ep: EndpointV) -> Bool:
  is_v6.go(family_of(ep))

def format_port(m: Maybe<&2, U32>) -> String:
  match m:
    case None{}: ""
    case Some{+n}: ":" ++ U32.show(n)

def format.go(family: Family, +host: String, +port: Maybe<&2, U32>) -> String:
  match family:
    case V6{}: "[" ++ host ++ "]" ++ format_port(port)
    case V4{}: host ++ format_port(port)

def format(+ep: EndpointV) -> String:
  match ep:
    case EndpointV{+host, +port, +family}: format.go(family, host, port)

# Scope/history spelling. V4 matches net.endpoint ("host:port"); V6 brackets
# the literal so the port split stays unambiguous.
def scope_key(+host: String, +port: U32, family: Family) -> String:
  match family:
    case V6{}: "[" ++ host ++ "]:" ++ U32.show(port)
    case V4{}: host ++ ":" ++ U32.show(port)

# ---- dial plan ---------------------------------------------------------------

type DialPlan is Data:
  Direct{ip: String}
  Resolve{name: String}

def dial_plan.v4(lit: Bool, +host: String) -> DialPlan:
  match lit:
    case True{}: Direct{host}
    case False{}: Resolve{host}

def dial_plan(+host: String, family: Family) -> DialPlan:
  match family:
    case V6{}: Direct{host}
    case V4{}: dial_plan.v4(Wire.is_ipv4(host), host)

def prefer_v6() -> Bool:
  True{}

type QueryOrder is Data:
  QueryOrder{first: U32, second: U32}

# Names try AAAA before A. The IO actor keeps the existing per-query bounds,
# timeouts, and TCP fallback for each attempt.
def query_order() -> QueryOrder:
  QueryOrder{28, 1}

# ---- AAAA encode ---------------------------------------------------------------

def enc_suffix() -> List<&2, U32>:
  0 <> 0 <> 28 <> 0 <> 1 <> Wire.opt_rr()

# Validity threads through; bytes for an invalid name are built bounded and
# discarded, so no branch needs a recursive value.
def enc_go(xs: List<&2, String>, acc: List<&2, U32>, +nlen: U32, ok: Bool) -> List<&2, U32> & Bool:
  match xs:
    case Nil{}: (List.append(&2, U32, acc, enc_suffix()), ok)
    case Con{+h, t}:
      +n2 = U32.add(nlen, U32.add(1, U32.from_nat(String.length(h))))
      enc_go(t, List.append(&2, U32, acc, U32.from_nat(String.length(h)) <> Wire.lab_octets(h)), n2,
        ok && Wire.label_ok(h) && U32.is_le(n2, 255))

def enc_done.ok(ok: Bool, +xs: List<&2, U32>) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match ok:
    case True{}: Done{xs}
    case False{}: Wire.enc_err("bad name")

def enc_done(pair: List<&2, U32> & Bool) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match pair:
    case (+xs, ok): enc_done.ok(ok, xs)

def encode_aaaa_id(+id: U32, +host: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  enc_done(enc_go(String.split(Wire.without_root_dot(host), Chr{46}), Wire.header_edns(id), 1, True{}))

def encode_aaaa(+host: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  encode_aaaa_id(1, host)

# ---- AAAA text ------------------------------------------------------------------

def hex_dig.lo(lt: Bool, +v: U32) -> U32:
  match lt:
    case True{}: U32.add(v, 48)
    case False{}: U32.add(U32.sub(v, 10), 97)

def hex_dig(+v: U32) -> U32:
  hex_dig.lo(U32.is_lt(v, 10), v)

def hex_chr(+v: U32) -> String:
  SCon{Chr{hex_dig(v)}, ""}

def hex4.c(cz: Bool, +c: U32, +d: U32) -> String:
  match cz:
    case False{}: hex_chr(c) ++ hex_chr(d)
    case True{}: hex_chr(d)

def hex4.b(bz: Bool, +b: U32, +c: U32, +d: U32) -> String:
  match bz:
    case False{}: hex_chr(b) ++ hex_chr(c) ++ hex_chr(d)
    case True{}: hex4.c(U32.is_zero(c), c, d)

def hex4.a(az: Bool, +a: U32, +b: U32, +c: U32, +d: U32) -> String:
  match az:
    case False{}: hex_chr(a) ++ hex_chr(b) ++ hex_chr(c) ++ hex_chr(d)
    case True{}: hex4.b(U32.is_zero(b), b, c, d)

def hex4(+a: U32, +b: U32, +c: U32, +d: U32) -> String:
  hex4.a(U32.is_zero(a), a, b, c, d)

def hex_u16(+v: U32) -> String:
  hex4(U32.and(U32.shrn(v, 12n), 15), U32.and(U32.shrn(v, 8n), 15), U32.and(U32.shrn(v, 4n), 15), U32.and(v, 15))

def ip6_text(+a0: U32, +a1: U32, +a2: U32, +a3: U32, +a4: U32, +a5: U32, +a6: U32, +a7: U32) -> String:
  hex_u16(a0) ++ ":" ++ hex_u16(a1) ++ ":" ++ hex_u16(a2) ++ ":" ++ hex_u16(a3)
    ++ ":" ++ hex_u16(a4) ++ ":" ++ hex_u16(a5) ++ ":" ++ hex_u16(a6) ++ ":" ++ hex_u16(a7)

def ip6_at(+pkt: List<&2, U32>, +off: U32) -> Maybe<&2, String>:
  do Maybe<&2, String>:
    +g0 : Wire.Got <- Wire.take16(Wire.at_off(pkt, off))
    +g1 : Wire.Got <- Wire.take16(Wire.got_cur(g0))
    +g2 : Wire.Got <- Wire.take16(Wire.got_cur(g1))
    +g3 : Wire.Got <- Wire.take16(Wire.got_cur(g2))
    +g4 : Wire.Got <- Wire.take16(Wire.got_cur(g3))
    +g5 : Wire.Got <- Wire.take16(Wire.got_cur(g4))
    +g6 : Wire.Got <- Wire.take16(Wire.got_cur(g5))
    +g7 : Wire.Got <- Wire.take16(Wire.got_cur(g6))
    return ip6_text(Wire.got_v(g0), Wire.got_v(g1), Wire.got_v(g2), Wire.got_v(g3),
      Wire.got_v(g4), Wire.got_v(g5), Wire.got_v(g6), Wire.got_v(g7))

# ---- AAAA answer walk ------------------------------------------------------------

type Aw6 is Data:
  WNext{}
  WGot{}
  WCls{}
  WTyp{}
  WOwn{}
  WTake{}
  WTyCn{}
  WOwnCn{}
  WChase{}
  WLoop{}
  WLoop2{}

# Mirrors Wire.walk_an_go phases for type 28 / 16-octet answers with the same
# CNAME chase rules. At most eight chases; fuel covers every step.
def walk_aaaa_go(
  fuel: Nat,
  ph: Aw6,
  +pkt: List<&2, U32>,
  +base_off: U32,
  +an_total: U32,
  +off: U32,
  +left: U32,
  +sought: String,
  +rec: Wire.RR,
  mrr: Maybe<&2, Wire.RR>,
  mnm: Maybe<&2, Wire.Nm>,
  mip: Maybe<&2, String>,
  flag: Bool,
  +hops: U32
) -> Result<&1, &1, U32 & String, String>:
  match fuel:
    case 0n:
      Wire.err("bad dns")
    case 1n+p:
      match ph:
        case WNext{}:
          match flag:
            case True{}:
              Wire.err("no AAAA")
            case False{}:
              walk_aaaa_go(p, WGot{}, pkt, base_off, an_total, off, left, sought, rec, Wire.read_rr(pkt, off), None{}, None{}, False{}, hops)
        case WGot{}:
          match mrr:
            case None{}:
              Wire.err("bad dns")
            case Some{+r}:
              walk_aaaa_go(p, WCls{}, pkt, base_off, an_total, off, left, sought, r, None{}, None{}, None{}, U32.is_eq(Wire.rr_cls(r), 1), hops)
        case WCls{}:
          match flag:
            case False{}:
              +left2 = U32.sub(left, 1)
              walk_aaaa_go(p, WNext{}, pkt, base_off, an_total, Wire.rr_next(rec), left2, sought, rec, None{}, None{}, None{}, U32.is_zero(left2), hops)
            case True{}:
              walk_aaaa_go(p, WTyp{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{},
                U32.is_eq(Wire.rr_ty(rec), 28) && U32.is_eq(Wire.rr_rdlen(rec), 16), hops)
        case WTyp{}:
          match flag:
            case True{}:
              walk_aaaa_go(p, WOwn{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{},
                String.eq(Wire.rr_owner(rec), sought), hops)
            case False{}:
              walk_aaaa_go(p, WTyCn{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{},
                U32.is_eq(Wire.rr_ty(rec), 5), hops)
        case WOwn{}:
          match flag:
            case True{}:
              walk_aaaa_go(p, WTake{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, ip6_at(pkt, Wire.rr_rd(rec)), False{}, hops)
            case False{}:
              +left2 = U32.sub(left, 1)
              walk_aaaa_go(p, WNext{}, pkt, base_off, an_total, Wire.rr_next(rec), left2, sought, rec, None{}, None{}, None{}, U32.is_zero(left2), hops)
        case WTake{}:
          match mip:
            case None{}:
              Wire.err("bad dns")
            case Some{+addr}:
              Wire.ok(addr)
        case WTyCn{}:
          match flag:
            case True{}:
              walk_aaaa_go(p, WOwnCn{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{},
                String.eq(Wire.rr_owner(rec), sought), hops)
            case False{}:
              +left2 = U32.sub(left, 1)
              walk_aaaa_go(p, WNext{}, pkt, base_off, an_total, Wire.rr_next(rec), left2, sought, rec, None{}, None{}, None{}, U32.is_zero(left2), hops)
        case WOwnCn{}:
          match flag:
            case True{}:
              walk_aaaa_go(p, WChase{}, pkt, base_off, an_total, off, left, sought, rec, None{},
                Wire.cname_read(rec, Wire.read_name(pkt, Wire.rr_rd(rec))), None{}, False{}, hops)
            case False{}:
              +left2 = U32.sub(left, 1)
              walk_aaaa_go(p, WNext{}, pkt, base_off, an_total, Wire.rr_next(rec), left2, sought, rec, None{}, None{}, None{}, U32.is_zero(left2), hops)
        case WChase{}:
          match mnm:
            case None{}:
              Wire.err("bad dns")
            case Some{+tgt}:
              +new_sought = Wire.nm_name(tgt)
              walk_aaaa_go(p, WLoop{}, pkt, base_off, an_total, off, left, new_sought, rec, None{}, None{}, None{},
                String.eq(new_sought, sought), hops)
        case WLoop{}:
          match flag:
            case True{}:
              Wire.err("bad dns")
            case False{}:
              +hops2 = U32.add(hops, 1)
              walk_aaaa_go(p, WLoop2{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, U32.is_gt(hops2, 8), hops2)
        case WLoop2{}:
          match flag:
            case True{}:
              Wire.err("bad dns")
            case False{}:
              walk_aaaa_go(p, WNext{}, pkt, base_off, an_total, base_off, an_total, sought, rec, None{}, None{}, None{},
                U32.is_zero(an_total), hops)

def walk_aaaa(+pkt: List<&2, U32>, +off: U32, +an: U32, +sought: String) -> Result<&1, &1, U32 & String, String>:
  walk_aaaa_go(
    Nat.add(32n, Nat.mul(32n, List.length(&2, U32, pkt))),
    WNext{},
    pkt,
    off,
    an,
    off,
    an,
    sought,
    Wire.rr0(),
    None{},
    None{},
    None{},
    U32.is_zero(an),
    0
  )

# ---- AAAA response ---------------------------------------------------------------

def parse_aaaa_rcode(good: Bool, +host: String, +pkt: List<&2, U32>, +an: U32, +off: U32, tc: Bool) -> Result<&1, &1, U32 & String, String>:
  match good:
    case False{}: Wire.err("rcode")
    case True{}: Wire.parse_q_truncated(walk_aaaa(pkt, off, an, host), tc)

def parse_aaaa_ok(
  +host: String,
  +pkt: List<&2, U32>,
  +an: U32,
  +off: U32,
  tc: Bool,
  sb: U32,
  ok: Bool
) -> Result<&1, &1, U32 & String, String>:
  match ok:
    case False{}:
      Wire.err("bad dns")
    case True{}:
      parse_aaaa_rcode(Wire.rcode_ok(sb), host, pkt, an, off, tc)

def parse_aaaa_qs(+host: String, +an: U32, +pkt: List<&2, U32>, tc: Bool, sb: U32, m: Maybe<&2, Wire.Qsec>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      Wire.err("bad dns")
    case Some{q}:
      match q:
        case Wire.Qsec{qname, ty, cls, off}:
          parse_aaaa_ok(host, pkt, an, off, tc, sb, U32.is_eq(ty, 28) && U32.is_eq(cls, 1) && String.eq(qname, host))

def parse_aaaa_chk(fail: Maybe<&2, String>, +host: String, +h: Wire.Hdr) -> Result<&1, &1, U32 & String, String>:
  match fail:
    case Some{+msg}:
      Wire.err(msg)
    case None{}:
      parse_aaaa_qs(host, Wire.hdr_an(h), Wire.hdr_pkt(h), Bool.not(U32.is_zero(U32.and(Wire.hdr_fb(h), 2))), Wire.hdr_sb(h),
        Wire.read_qsec(Wire.hdr_pkt(h)))

def parse_aaaa_h(+want: U32, +host: String, m: Maybe<&2, Wire.Hdr>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      Wire.err("short")
    case Some{+h}:
      parse_aaaa_chk(Wire.first_fail(Wire.hdr_chks(want, h)), host, h)

def parse_aaaa(+want: U32, +host: String, +xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  parse_aaaa_h(want, Wire.name_lo(Wire.without_root_dot(host)), Wire.parse_hdr(xs))

def parse_aaaa_id(+want: U32, xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  parse_aaaa(want, "a", xs)

def take_parse_aaaa(r: Result<&1, &1, U32 & String, String>) -> Wire.Take:
  match r:
    case Fail{(_, +msg)}:
      Wire.take_id(msg, Wire.is_miss(msg))
    case Done{+ip}:
      Wire.HitOk{ip}

def take_on_aaaa(ok: Bool, +id: U32, +qhost: String, xs: List<&2, U32>) -> Wire.Take:
  match ok:
    case False{}:
      Wire.Miss{}
    case True{}:
      take_parse_aaaa(parse_aaaa(id, qhost, xs))

# Same peer/miss rules as Wire.take_pkt; TCP framing reuses Wire.tcp_packet.
def take_pkt_aaaa(
  +ns: String,
  +id: U32,
  +qhost: String,
  +phost: String,
  +port: U32,
  xs: List<&2, U32>
) -> Wire.Take:
  take_on_aaaa(Wire.peer_ok(ns, phost, port), id, qhost, xs)

# ---- proof-facing predicates ------------------------------------------------------

def literal_ok() -> Bool:
  valid_inner("::1") && valid_inner("2001:db8::1") && valid_inner("1:2:3:4:5:6:7:8") && valid_inner("::")
    && Bool.not(valid_inner("")) && Bool.not(valid_inner(":")) && Bool.not(valid_inner("1::2::3"))
    && Bool.not(valid_inner("12345::")) && Bool.not(valid_inner("1:2:3:4:5:6:7"))

def endpoint_ok() -> Bool:
  is_v6(EndpointV{"::1", Some{6697}, V6{}}) && Bool.not(is_v6(EndpointV{"h", None{}, V4{}}))
    && String.eq(scope_key("::1", 6697, V6{}), "[::1]:6697")
    && String.eq(scope_key("h", 6697, V4{}), "h:6697")

def dial_ok.direct(plan: DialPlan) -> Bool:
  match plan:
    case Direct{_}: True{}
    case _: False{}

def dial_ok.resolve(plan: DialPlan) -> Bool:
  match plan:
    case Resolve{_}: True{}
    case _: False{}

def dial_ok() -> Bool:
  prefer_v6() && dial_ok.direct(dial_plan("::1", V6{})) && dial_ok.resolve(dial_plan("example.com", V4{}))
    && dial_ok.direct(dial_plan("127.0.0.1", V4{}))
