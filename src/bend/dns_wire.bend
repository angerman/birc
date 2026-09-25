# Pure DNS A wire encode/parse. No IO. dns.bend owns UDP.
# Query encode is List U32 (send_octets). Live recv is recv_octets.
# Cursor is a Data record so a do Maybe block can bind more than once.
import Base

def byte(+n: U32) -> String:
  SCon{Chr{n}, ""}

def err(+msg: String) -> Result<&1, &1, U32 & String, String>:
  Fail{(1, msg)}

def ok(+ip: String) -> Result<&1, &1, U32 & String, String>:
  Done{ip}

def u16_of(+hi: U32, +lo: U32) -> U32:
  U32.add(U32.mul(hi, 256), lo)

def rcode_ok(+b: U32) -> Bool:
  U32.is_eq(U32.and(b, 15), 0)

# ---- dotted IPv4 (no leading zeros; inet_pton rejects those) -----------

def starts_zero(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+h, _}:
      U32.is_eq(Char.to_u32(h), 48)

def lead_ok_z(+s: String, z: Bool) -> Bool:
  match z:
    case False{}:
      True{}
    case True{}:
      Nat.is_eq(String.length(s), 1n)

def lead_ok(+s: String) -> Bool:
  lead_ok_z(s, starts_zero(s))

def octet_val(m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{v}:
      U32.is_le(v, 255)

def octet_both(+s: String, v_ok: Bool) -> Bool:
  match v_ok:
    case False{}:
      False{}
    case True{}:
      lead_ok(s)

def octet_ok(+s: String) -> Bool:
  octet_both(s, octet_val(U32.read(s)))

def ipv4_go(xs: List<&2, String>, +n: U32) -> Bool:
  match xs:
    case Nil{}:
      U32.is_eq(n, 4)
    case Con{+h, t}:
      Bool.pick(Bool, octet_ok(h), ipv4_go(t, U32.add(n, 1)), False{})

def is_ipv4_xs(+xs: List<&2, String>) -> Bool:
  ipv4_go(xs, 0)

def is_ipv4(+host: String) -> Bool:
  is_ipv4_xs(String.split(host, Chr{46}))

# IPv4-only resolver. A colon means an IPv6 literal (or garbage); reject
# it rather than sending a DNS query for the string.
def is_ipv6(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+h, t}:
      U32.is_eq(Char.to_u32(h), 58) || is_ipv6(t)

# First IPv4 `nameserver` in resolv.conf text. Fails closed if missing.

def ns_ip(+ip: String, good: Bool) -> Maybe<&2, String>:
  match good:
    case False{}:
      None{}
    case True{}:
      Some{ip}

# TAB/space runs become empty String.split tokens; skip them. First
# non-empty word must be nameserver, then the next non-empty IPv4.
type NsW is Data:
  NsRead{}
  NsGot{}
  NsKw{}
  NsTail{}
  NsIp{}

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed ns_words_go
def ns_words_go(
  fuel: Nat,
  ph: NsW,
  xs: List<&2, String>,
  +w: String,
  empty: Bool,
  hit: Bool
) -> Maybe<&2, String>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match ph:
        case NsRead{}:
          match xs:
            case Nil{}:
              None{}
            case Con{+h, t}:
              ns_words_go(p, NsGot{}, t, h, String.is_empty(h), False{})
        case NsGot{}:
          match empty:
            case True{}:
              ns_words_go(p, NsRead{}, xs, w, False{}, False{})
            case False{}:
              ns_words_go(p, NsKw{}, xs, w, False{}, String.eq(w, "nameserver"))
        case NsKw{}:
          match hit:
            case False{}:
              None{}
            case True{}:
              ns_words_go(p, NsTail{}, xs, w, False{}, False{})
        case NsTail{}:
          match xs:
            case Nil{}:
              None{}
            case Con{+h, t}:
              ns_words_go(p, NsIp{}, t, h, String.is_empty(h), False{})
        case NsIp{}:
          match empty:
            case True{}:
              ns_words_go(p, NsTail{}, xs, w, False{}, False{})
            case False{}:
              ns_ip(w, is_ipv4(w))

def ns_words(+xs: List<&2, String>) -> Maybe<&2, String>:
  ns_words_go(Nat.add(1n, Nat.mul(3n, List.length(&2, String, xs))), NsRead{}, xs, "", False{}, False{})

# Drop CR; map TAB to space so split on SP sees indent and nameserver\tip.
def ns_norm.ch(+h: Char, r: String, cr: Bool, tab: Bool) -> String:
  match cr:
    case True{}:
      r
    case False{}:
      match tab:
        case True{}:
          SCon{Chr{32}, r}
        case False{}:
          SCon{h, r}

def ns_norm(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      +n = Char.to_u32(h)
      ns_norm.ch(h, ns_norm(t), U32.is_eq(n, 13), U32.is_eq(n, 9))

def nameserver_line(+line: String) -> Maybe<&2, String>:
  ns_words(String.split(line, Chr{32}))

def ns_go(xs: List<&2, String>, m: Maybe<&2, String>) -> Result<&1, &1, U32 & String, String>:
  match xs:
    case Nil{}:
      match m:
        case Some{ip}:
          ok(ip)
        case None{}:
          err("no nameserver")
    case Con{+h, t}:
      match m:
        case Some{ip}:
          ok(ip)
        case None{}:
          ns_go(t, nameserver_line(h))

def nameserver_of(+text: String) -> Result<&1, &1, U32 & String, String>:
  ns_go(String.split(ns_norm(text), Chr{10}), None{})

# ---- query encoder ------------------------------------------------------

def ascii_go(s: String, ok: Bool) -> Bool:
  match s:
    case SNil{}:
      ok
    case SCon{+h, t}:
      ascii_go(t, ok && U32.is_lt(Char.to_u32(h), 128))

def len_ok(+n: Nat) -> Bool:
  Nat.is_ge(n, 1n) && Nat.is_le(n, 63n)

def label_ok_len(+lab: String, ok: Bool) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      ascii_go(lab, True{})

def label_ok(+lab: String) -> Bool:
  label_ok_len(lab, len_ok(String.length(lab)))

def u8(+n: U32) -> U32:
  U32.and(n, 255)

def txid_nz(+n: U32, z: Bool) -> U32:
  match z:
    case True{}:
      1
    case False{}:
      n

# Full 16-bit id (never 0). High bytes go on the wire via send_octets.
def txid_of(+n: U32) -> U32:
  +id = U32.and(n, 65535)
  txid_nz(id, U32.is_zero(id))

def header(+id: U32) -> List<&2, U32>:
  u8(U32.shrn(id, 8n)) <> u8(id) <> 1 <> 0 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> Nil{}

def lab_octets(+lab: String) -> List<&2, U32>:
  match lab:
    case SNil{}:
      Nil{}
    case SCon{+h, t}:
      Char.to_u32(h) <> lab_octets(t)

def push_lab(+acc: List<&2, U32>, +lab: String) -> List<&2, U32>:
  List.append(&2, U32, acc, U32.from_nat(String.length(lab)) <> lab_octets(lab))

def enc_err(+msg: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  Fail{(1, msg)}

def enc_ok(+xs: List<&2, U32>) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  Done{xs}

type Enc is Data:
  ELab{}
  EOk{}
  ELen{}

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed encode_go
def encode_go(
  fuel: Nat,
  ph: Enc,
  xs: List<&2, String>,
  acc: List<&2, U32>,
  +lab: String,
  ok: Bool,
  +nlen: U32
) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match fuel:
    case 0n:
      enc_err("bad name")
    case 1n+p:
      match ph:
        case ELab{}:
          match xs:
            case Nil{}:
              enc_ok(List.append(&2, U32, acc, 0 <> 0 <> 1 <> 0 <> 1 <> Nil{}))
            case Con{+h, t}:
              encode_go(p, EOk{}, t, acc, h, label_ok(h), nlen)
        case EOk{}:
          match ok:
            case False{}:
              enc_err("bad name")
            case True{}:
              +n2 = U32.add(nlen, U32.add(1, U32.from_nat(String.length(lab))))
              encode_go(p, ELen{}, xs, acc, lab, U32.is_gt(n2, 255), n2)
        case ELen{}:
          match ok:
            case True{}:
              enc_err("bad name")
            case False{}:
              encode_go(p, ELab{}, xs, push_lab(acc, lab), "", True{}, nlen)

def encode_xs(+id: U32, +xs: List<&2, String>) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  encode_go(Nat.add(1n, Nat.mul(3n, List.length(&2, String, xs))), ELab{}, xs, header(id), "", True{}, 1)

def encode_id(+id: U32, +host: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  encode_xs(id, String.split(host, Chr{46}))

def encode(+host: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  encode_id(1, host)

# EDNS0 OPT RR (RFC 6891): name=0, type=41, payload=4096 (0x1000), ttl=0, rdlen=0
def opt_rr() -> List<&2, U32>:
  0 <> 0 <> 41 <> 16 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> Nil{}

# Header with ARCOUNT=1 (for EDNS0 OPT RR in Additional section)
def header_edns(+id: U32) -> List<&2, U32>:
  u8(U32.shrn(id, 8n)) <> u8(id) <> 1 <> 0 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> Nil{}

def encode_edns_tail(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{q}:
      Done{List.append(&2, U32, q, opt_rr())}

def encode_edns_xs(+id: U32, +xs: List<&2, String>) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  encode_edns_tail(encode_go(Nat.add(1n, Nat.mul(3n, List.length(&2, String, xs))), ELab{}, xs, header_edns(id), "", True{}, 1))

def encode_edns_id(+id: U32, +host: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  encode_edns_xs(id, String.split(host, Chr{46}))

def encode_edns(+host: String) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  encode_edns_id(1, host)

# 2-byte length-prefix framing for DNS over TCP (RFC 1035 §4.2.2)
def tcp_frame(+q: List<&2, U32>) -> List<&2, U32>:
  +n = U32.from_nat(List.length(&2, U32, q))
  u8(U32.shrn(n, 8n)) <> u8(n) <> q

def tcp_strip(xs: List<&2, U32>) -> List<&2, U32>:
  List.drop(&2, U32, xs, 2n)

# ---- Data cursor (copyable). Pairs are affine; a do-block needs Data. --

type Cur is Data:
  Cur{pkt: List<&2, U32>, rest: List<&2, U32>, off: U32}

type Got is Data:
  Got{v: U32, cur: Cur}

type Nm is Data:
  Nm{name: String, off: U32}

type Hdr is Data:
  Hdr{id: U32, fb: U32, sb: U32, qd: U32, an: U32, pkt: List<&2, U32>}

type Qsec is Data:
  Qsec{name: String, ty: U32, cls: U32, off: U32}

type RR is Data:
  RR{owner: String, ty: U32, cls: U32, rdlen: U32, rd: U32, next: U32}

type Chk is Data:
  Chk{good: Bool, msg: String}

def got_v(+g: Got) -> U32:
  match g:
    case Got{v, _}:
      v

def got_cur(+g: Got) -> Cur:
  match g:
    case Got{_, c}:
      c

def cur_off(+c: Cur) -> U32:
  match c:
    case Cur{_, _, off}:
      off

def rest_drop(n: Nat, xs: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      xs
    case 1n+p:
      match xs:
        case Nil{}:
          Nil{}
        case Con{_, t}:
          rest_drop(p, t)

def cur_add(+c: Cur, +n: U32) -> Cur:
  match c:
    case Cur{pkt, rest, off}:
      Cur{pkt, rest_drop(U32.to_nat(n), rest), U32.add(off, n)}

def at_off(+pkt: List<&2, U32>, +off: U32) -> Cur:
  Cur{pkt, rest_drop(U32.to_nat(off), pkt), off}

def nm_name(+n: Nm) -> String:
  match n:
    case Nm{name, _}:
      name

def nm_off(+n: Nm) -> U32:
  match n:
    case Nm{_, off}:
      off

def hdr_id(+h: Hdr) -> U32:
  match h:
    case Hdr{id, _, _, _, _, _}:
      id

def hdr_fb(+h: Hdr) -> U32:
  match h:
    case Hdr{_, fb, _, _, _, _}:
      fb

def hdr_sb(+h: Hdr) -> U32:
  match h:
    case Hdr{_, _, sb, _, _, _}:
      sb

def hdr_qd(+h: Hdr) -> U32:
  match h:
    case Hdr{_, _, _, qd, _, _}:
      qd

def hdr_an(+h: Hdr) -> U32:
  match h:
    case Hdr{_, _, _, _, an, _}:
      an

def hdr_pkt(+h: Hdr) -> List<&2, U32>:
  match h:
    case Hdr{_, _, _, _, _, pkt}:
      pkt

def rr_owner(+r: RR) -> String:
  match r:
    case RR{owner, _, _, _, _, _}:
      owner

def rr_ty(+r: RR) -> U32:
  match r:
    case RR{_, ty, _, _, _, _}:
      ty

def rr_cls(+r: RR) -> U32:
  match r:
    case RR{_, _, cls, _, _, _}:
      cls

def rr_rdlen(+r: RR) -> U32:
  match r:
    case RR{_, _, _, rdlen, _, _}:
      rdlen

def rr_rd(+r: RR) -> U32:
  match r:
    case RR{_, _, _, _, rd, _}:
      rd

def rr_next(+r: RR) -> U32:
  match r:
    case RR{_, _, _, _, _, next}:
      next

def at_xs(xs: List<&2, U32>) -> Maybe<&2, U32>:
  match xs:
    case Nil{}:
      None{}
    case Con{+h, _}:
      Some{h}

def byte_at(+c: Cur) -> Maybe<&2, U32>:
  match c:
    case Cur{_, rest, _}:
      at_xs(rest)

def take8(+c: Cur) -> Maybe<&2, Got>:
  do Maybe<&2, Got>:
    b : U32 <- byte_at(c)
    return Got{b, cur_add(c, 1)}

def take16(+c: Cur) -> Maybe<&2, Got>:
  do Maybe<&2, Got>:
    +g0 : Got <- take8(c)
    +g1 : Got <- take8(got_cur(g0))
    return Got{u16_of(got_v(g0), got_v(g1)), got_cur(g1)}

def lo_byte_on(+b: U32, up: Bool) -> U32:
  match up:
    case True{}:
      U32.add(b, 32)
    case False{}:
      b

def lo_byte(+b: U32) -> U32:
  lo_byte_on(b, U32.is_ge(b, 65) && U32.is_le(b, 90))

def name_lo_acc(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{+h, t}:
      name_lo_acc(t, SCon{Chr{lo_byte(Char.to_u32(h))}, acc})

def name_lo(+s: String) -> String:
  name_lo_acc(s, "")

def name_join_e(+acc: String, +lab: String, empty: Bool) -> String:
  match empty:
    case True{}:
      lab
    case False{}:
      acc ++ "." ++ lab

def name_join(+acc: String, +lab: String) -> String:
  name_join_e(acc, lab, String.is_empty(acc))

type End is Data:
  EndOpen{}
  EndGot{off: U32}

def end_of(+pos: U32, ret: End) -> U32:
  match ret:
    case EndOpen{}:
      U32.add(pos, 1)
    case EndGot{off}:
      off

def freeze_got(+e: U32) -> End:
  EndGot{e}

def freeze_end(+pos: U32, ret: End) -> End:
  match ret:
    case EndOpen{}:
      freeze_got(U32.add(pos, 2))
    case EndGot{off}:
      EndGot{off}

# Compression jumps; not a structural list walk. Fuel from packet length.
type RdN is Data:
  RdGet{}
  RdGot{}
  RdKind{}
  RdRes{}
  RdZero{}
  RdPtr{}
  RdHop{}
  RdLab{}
  RdLabZ{}
  RdLabB{}

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed read_name_go
def read_name_go(
  fuel: Nat,
  ph: RdN,
  +pkt: List<&2, U32>,
  +pos: U32,
  ret: End,
  +hops: U32,
  +acc: String,
  lab: String,
  +n: U32,
  +b: U32,
  got: Maybe<&2, U32>,
  flag: Bool
) -> Maybe<&2, Nm>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match ph:
        case RdGet{}:
          read_name_go(p, RdGot{}, pkt, pos, ret, hops, acc, lab, n, b, byte_at(at_off(pkt, pos)), False{})
        case RdGot{}:
          match got:
            case None{}:
              None{}
            case Some{+x}:
              read_name_go(p, RdKind{}, pkt, pos, ret, hops, acc, lab, n, x, None{}, U32.is_ge(x, 192))
        case RdKind{}:
          match flag:
            case True{}:
              read_name_go(p, RdPtr{}, pkt, pos, ret, hops, acc, lab, n, b, byte_at(at_off(pkt, U32.add(pos, 1))), False{})
            case False{}:
              read_name_go(p, RdRes{}, pkt, pos, ret, hops, acc, lab, n, b, None{}, U32.is_ge(b, 64))
        case RdRes{}:
          match flag:
            case True{}:
              None{}
            case False{}:
              read_name_go(p, RdZero{}, pkt, pos, ret, hops, acc, lab, n, b, None{}, U32.is_zero(b))
        case RdZero{}:
          match flag:
            case True{}:
              Some{Nm{acc, end_of(pos, ret)}}
            case False{}:
              read_name_go(p, RdLab{}, pkt, U32.add(pos, 1), ret, hops, acc, "", b, 0, None{}, False{})
        case RdPtr{}:
          match got:
            case None{}:
              None{}
            case Some{lo}:
              read_name_go(p, RdHop{}, pkt, u16_of(U32.and(b, 63), lo), freeze_end(pos, ret), U32.add(hops, 1), acc, lab, n, 0, None{}, U32.is_ge(hops, 10))
        case RdHop{}:
          match flag:
            case True{}:
              None{}
            case False{}:
              read_name_go(p, RdGet{}, pkt, pos, ret, hops, acc, lab, n, b, None{}, False{})
        case RdLab{}:
          read_name_go(p, RdLabZ{}, pkt, pos, ret, hops, acc, lab, n, b, None{}, U32.is_zero(n))
        case RdLabZ{}:
          match flag:
            case True{}:
              read_name_go(p, RdGet{}, pkt, pos, ret, hops, name_join(acc, lab), "", 0, 0, None{}, False{})
            case False{}:
              read_name_go(p, RdLabB{}, pkt, pos, ret, hops, acc, lab, n, b, byte_at(at_off(pkt, pos)), False{})
        case RdLabB{}:
          match got:
            case None{}:
              None{}
            case Some{c}:
              read_name_go(p, RdLab{}, pkt, U32.add(pos, 1), ret, hops, acc, lab ++ byte(lo_byte(c)), U32.sub(n, 1), b, None{}, False{})

def read_name(+pkt: List<&2, U32>, +off: U32) -> Maybe<&2, Nm>:
  read_name_go(
    Nat.add(4n, Nat.mul(8n, List.length(&2, U32, pkt))),
    RdGet{},
    pkt,
    off,
    EndOpen{},
    0,
    "",
    "",
    0,
    0,
    None{},
    False{}
  )

def ip4_at(+pkt: List<&2, U32>, +off: U32) -> Maybe<&2, String>:
  do Maybe<&2, String>:
    +g0 : Got <- take8(at_off(pkt, off))
    +g1 : Got <- take8(got_cur(g0))
    +g2 : Got <- take8(got_cur(g1))
    +g3 : Got <- take8(got_cur(g2))
    return U32.show(got_v(g0)) ++ "." ++ U32.show(got_v(g1)) ++ "." ++ U32.show(got_v(g2)) ++ "." ++ U32.show(got_v(g3))

def read_rr(+pkt: List<&2, U32>, +off: U32) -> Maybe<&2, RR>:
  do Maybe<&2, RR>:
    +nm : Nm <- read_name(pkt, off)
    +gt : Got <- take16(at_off(pkt, nm_off(nm)))
    +gc : Got <- take16(got_cur(gt))
    +t0 : Got <- take16(got_cur(gc))
    +t1 : Got <- take16(got_cur(t0))
    +gr : Got <- take16(got_cur(t1))
    return RR{nm_name(nm), got_v(gt), got_v(gc), got_v(gr), cur_off(got_cur(gr)), U32.add(cur_off(got_cur(gr)), got_v(gr))}

def rr0() -> RR:
  RR{"", 0, 0, 0, 0, 0}

type Aw is Data:
  AwLeft{}
  AwGot{}
  AwIn{}
  AwTyA{}
  AwOwnA{}
  AwTyCn{}
  AwOwnCn{}
  AwA{}
  AwCn{}
  AwLoop{}
  AwSkip{}

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed walk_an_go
def walk_an_go(
  fuel: Nat,
  ph: Aw,
  +pkt: List<&2, U32>,
  +base_off: U32,
  +an_total: U32,
  +off: U32,
  +left: U32,
  +sought: String,
  +rec: RR,
  mrr: Maybe<&2, RR>,
  mnm: Maybe<&2, Nm>,
  mip: Maybe<&2, String>,
  flag: Bool
) -> Result<&1, &1, U32 & String, String>:
  match fuel:
    case 0n:
      err("bad dns")
    case 1n+p:
      match ph:
        case AwLeft{}:
          match flag:
            case True{}:
              err("no A")
            case False{}:
              walk_an_go(p, AwGot{}, pkt, base_off, an_total, off, left, sought, rec, read_rr(pkt, off), None{}, None{}, False{})
        case AwGot{}:
          match mrr:
            case None{}:
              err("bad dns")
            case Some{+r}:
              walk_an_go(p, AwIn{}, pkt, base_off, an_total, off, left, sought, r, None{}, None{}, None{}, U32.is_eq(rr_cls(r), 1))
        case AwIn{}:
          match flag:
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, False{})
            case True{}:
              walk_an_go(p, AwTyA{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, U32.is_eq(rr_ty(rec), 1) && U32.is_eq(rr_rdlen(rec), 4))
        case AwTyA{}:
          match flag:
            case True{}:
              walk_an_go(p, AwOwnA{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, String.eq(rr_owner(rec), sought))
            case False{}:
              walk_an_go(p, AwTyCn{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, U32.is_eq(rr_ty(rec), 5))
        case AwOwnA{}:
          match flag:
            case True{}:
              walk_an_go(p, AwA{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, ip4_at(pkt, rr_rd(rec)), False{})
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, False{})
        case AwTyCn{}:
          match flag:
            case True{}:
              walk_an_go(p, AwOwnCn{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, String.eq(rr_owner(rec), sought))
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, False{})
        case AwOwnCn{}:
          match flag:
            case True{}:
              walk_an_go(p, AwCn{}, pkt, base_off, an_total, off, left, sought, rec, None{}, read_name(pkt, rr_rd(rec)), None{}, False{})
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, base_off, an_total, off, left, sought, rec, None{}, None{}, None{}, False{})
        case AwA{}:
          match mip:
            case None{}:
              err("bad dns")
            case Some{+addr}:
              ok(addr)
        case AwCn{}:
          match mnm:
            case None{}:
              err("bad dns")
            case Some{+tgt}:
              +new_sought = nm_name(tgt)
              walk_an_go(p, AwLoop{}, pkt, base_off, an_total, off, left, new_sought, rec, None{}, None{}, None{}, String.eq(new_sought, sought))
        case AwLoop{}:
          match flag:
            case True{}:
              err("bad dns")
            case False{}:
              walk_an_go(p, AwLeft{}, pkt, base_off, an_total, base_off, an_total, sought, rec, None{}, None{}, None{}, U32.is_zero(an_total))
        case AwSkip{}:
          +left2 = U32.sub(left, 1)
          walk_an_go(p, AwLeft{}, pkt, base_off, an_total, rr_next(rec), left2, sought, rec, None{}, None{}, None{}, U32.is_zero(left2))

def walk_an(+pkt: List<&2, U32>, +off: U32, +an: U32, +sought: String) -> Result<&1, &1, U32 & String, String>:
  walk_an_go(
    Nat.add(32n, Nat.mul(32n, List.length(&2, U32, pkt))),
    AwLeft{},
    pkt,
    off,
    an,
    off,
    an,
    sought,
    rr0(),
    None{},
    None{},
    None{},
    U32.is_zero(an)
  )

def parse_hdr(+pkt: List<&2, U32>) -> Maybe<&2, Hdr>:
  do Maybe<&2, Hdr>:
    +g0 : Got <- take16(at_off(pkt, 0))
    +g1 : Got <- take8(got_cur(g0))
    +g2 : Got <- take8(got_cur(g1))
    +g3 : Got <- take16(got_cur(g2))
    +g4 : Got <- take16(got_cur(g3))
    +g5 : Got <- take16(got_cur(g4))
    +g6 : Got <- take16(got_cur(g5))
    return Hdr{got_v(g0), got_v(g1), got_v(g2), got_v(g3), got_v(g4), pkt}

def read_qsec(+pkt: List<&2, U32>) -> Maybe<&2, Qsec>:
  do Maybe<&2, Qsec>:
    +nm : Nm <- read_name(pkt, 12)
    +gt : Got <- take16(at_off(pkt, nm_off(nm)))
    +gc : Got <- take16(got_cur(gt))
    return Qsec{nm_name(nm), got_v(gt), got_v(gc), cur_off(got_cur(gc))}

def first_fail(xs: List<&2, Chk>) -> Maybe<&2, String>:
  match xs:
    case Nil{}:
      None{}
    case Con{c, t}:
      match c:
        case Chk{good, msg}:
          match good:
            case False{}:
              Some{msg}
            case True{}:
              first_fail(t)

def tc_ok(+fb: U32, +an: U32) -> Bool:
  U32.is_zero(U32.and(fb, 2)) || U32.is_gt(an, 0)

def hdr_chks(+want: U32, +h: Hdr) -> List<&2, Chk>:
  Chk{U32.is_eq(hdr_id(h), want), "bad id"} <> Chk{U32.is_ge(hdr_fb(h), 128), "bad dns"} <> Chk{tc_ok(hdr_fb(h), hdr_an(h)), "tc"} <> Chk{rcode_ok(hdr_sb(h)), "rcode"} <> Chk{U32.is_eq(hdr_qd(h), 1), "bad dns"} <> Nil{}

def parse_q_qs_ok(
  +host: String,
  +pkt: List<&2, U32>,
  +an: U32,
  +off: U32,
  ok: Bool
) -> Result<&1, &1, U32 & String, String>:
  match ok:
    case False{}:
      err("bad dns")
    case True{}:
      walk_an(pkt, off, an, host)

def parse_q_qs(+host: String, +an: U32, +pkt: List<&2, U32>, m: Maybe<&2, Qsec>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("bad dns")
    case Some{q}:
      match q:
        case Qsec{qname, ty, cls, off}:
          parse_q_qs_ok(host, pkt, an, off, U32.is_eq(ty, 1) && U32.is_eq(cls, 1) && String.eq(qname, host))

def parse_q_chk(fail: Maybe<&2, String>, +host: String, +h: Hdr) -> Result<&1, &1, U32 & String, String>:
  match fail:
    case Some{+msg}:
      err(msg)
    case None{}:
      parse_q_qs(host, hdr_an(h), hdr_pkt(h), read_qsec(hdr_pkt(h)))

def parse_q_h(+want: U32, +host: String, m: Maybe<&2, Hdr>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{+h}:
      parse_q_chk(first_fail(hdr_chks(want, h)), host, h)

def parse_q(+want: U32, +host: String, +xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  parse_q_h(want, name_lo(host), parse_hdr(xs))

def parse_id(+want: U32, xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  parse_q(want, "a", xs)

def parse_done(r: Result<&1, &1, U32 & String, String>) -> Bool:
  match r:
    case Done{_}:
      True{}
    case Fail{_}:
      False{}

def xs_id(xs: List<&2, U32>) -> Maybe<&2, U32>:
  match xs:
    case Con{+a, Con{+b, _}}:
      Some{u16_of(a, b)}
    case Nil{}:
      None{}
    case Con{_, Nil{}}:
      None{}

def parse_id_mismatch_on(+want: U32, +xs: List<&2, U32>, m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}:
      Bool.not(parse_done(parse_id(want, xs)))
    case Some{id}:
      U32.is_eq(id, want) || Bool.not(parse_done(parse_id(want, xs)))

def parse_id_mismatch_ok(+want: U32, +xs: List<&2, U32>) -> Bool:
  parse_id_mismatch_on(want, xs, xs_id(xs))

# Full A packet whose id is 2 (want 1 fails). Short witnesses never reach
# the id-mismatch arm of parse_id_mismatch_on.
def sample_bad_id() -> List<&2, U32>:
  0 <> 2 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

type Take is Data:
  Miss{}
  HitOk{ip: String}
  HitErr{msg: String}

def peer_ok(+ns: String, +host: String, +port: U32) -> Bool:
  String.eq(ns, host) && U32.is_eq(port, 53)

def is_miss(+msg: String) -> Bool:
  String.eq(msg, "bad id") || String.eq(msg, "bad dns") || String.eq(msg, "short")

def take_id(+msg: String, miss: Bool) -> Take:
  match miss:
    case True{}:
      Miss{}
    case False{}:
      HitErr{msg}

def take_parse(r: Result<&1, &1, U32 & String, String>) -> Take:
  match r:
    case Fail{(_, +msg)}:
      take_id(msg, is_miss(msg))
    case Done{+ip}:
      HitOk{ip}

def take_on(ok: Bool, +id: U32, +qhost: String, xs: List<&2, U32>) -> Take:
  match ok:
    case False{}:
      Miss{}
    case True{}:
      take_parse(parse_q(id, qhost, xs))

def take_pkt(
  +ns: String,
  +id: U32,
  +qhost: String,
  +phost: String,
  +port: U32,
  xs: List<&2, U32>
) -> Take:
  take_on(peer_ok(ns, phost, port), id, qhost, xs)
