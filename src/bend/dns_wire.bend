# Pure DNS A wire encode/parse. No IO. dns.bend owns UDP.
# Query bytes are all < 128 so String send stays one octet per Char.
# Live recv is recv_octets (List U32 0..255). Cursor is a Data record so
# a do Maybe block can bind more than once (idiom §4#1).
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

type IpS is Data:
  IpL{}
  IpC{}

def ipv4_go(fuel: Nat, ph: IpS, xs: List<&2, String>, +n: U32, ok: Bool) -> Bool:
  match fuel:
    case 0n:
      False{}
    case 1n+p:
      match ph:
        case IpL{}:
          match xs:
            case Nil{}:
              U32.is_eq(n, 4)
            case Con{+h, t}:
              ipv4_go(p, IpC{}, t, n, octet_ok(h))
        case IpC{}:
          match ok:
            case False{}:
              False{}
            case True{}:
              ipv4_go(p, IpL{}, xs, U32.add(n, 1), True{})

def is_ipv4_xs(+xs: List<&2, String>) -> Bool:
  ipv4_go(Nat.add(1n, Nat.mul(2n, List.length(&2, String, xs))), IpL{}, xs, 0, True{})

def is_ipv4(+host: String) -> Bool:
  is_ipv4_xs(String.split(host, Chr{46}))

# ---- query encoder ------------------------------------------------------

def ascii_go(fuel: Nat, s: String, ok: Bool) -> Bool:
  match fuel:
    case 0n:
      False{}
    case 1n+p:
      match s:
        case SNil{}:
          ok
        case SCon{+h, t}:
          ascii_go(p, t, ok && U32.is_lt(Char.to_u32(h), 128))

def len_ok(+n: Nat) -> Bool:
  Nat.is_ge(n, 1n) && Nat.is_le(n, 63n)

def label_ok_len(+lab: String, ok: Bool) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      ascii_go(Nat.add(1n, String.length(lab)), lab, True{})

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

# Both ID bytes must be < 128: UDP.send_to is a String, so a high byte
# becomes UTF-8 (two wire octets) and the resolver answers garbage
# ("bad dns") or nothing. 7+7 bits, never 0. 16-bit ids need send_octets.
def txid_hi(+n: U32) -> U32:
  U32.and(U32.shrn(n, 7n), 127)

def txid_lo(+n: U32) -> U32:
  U32.and(n, 127)

def txid_of(+n: U32) -> U32:
  +hi = txid_hi(n)
  +lo = txid_lo(n)
  txid_nz(U32.add(U32.mul(hi, 256), lo), U32.is_eq(hi, 0) && U32.is_eq(lo, 0))

def header(+id: U32) -> String:
  byte(u8(U32.shrn(id, 8n))) ++ byte(u8(id)) ++ byte(1) ++ byte(0) ++ byte(0) ++ byte(1) ++ byte(0) ++ byte(0) ++ byte(0) ++ byte(0) ++ byte(0) ++ byte(0)

def push_lab(+acc: String, +lab: String) -> String:
  String.append(acc, SCon{Chr{U32.from_nat(String.length(lab))}, lab})

type Enc is Data:
  ELab{}
  EOk{}
  ELen{}

def encode_go(
  fuel: Nat,
  ph: Enc,
  xs: List<&2, String>,
  acc: String,
  +lab: String,
  ok: Bool,
  +nlen: U32
) -> Result<&1, &1, U32 & String, String>:
  match fuel:
    case 0n:
      err("bad name")
    case 1n+p:
      match ph:
        case ELab{}:
          match xs:
            case Nil{}:
              Done{acc ++ byte(0) ++ byte(0) ++ byte(1) ++ byte(0) ++ byte(1)}
            case Con{+h, t}:
              encode_go(p, EOk{}, t, acc, h, label_ok(h), nlen)
        case EOk{}:
          match ok:
            case False{}:
              err("bad name")
            case True{}:
              +n2 = U32.add(nlen, U32.add(1, U32.from_nat(String.length(lab))))
              encode_go(p, ELen{}, xs, acc, lab, U32.is_gt(n2, 255), n2)
        case ELen{}:
          match ok:
            case True{}:
              err("bad name")
            case False{}:
              encode_go(p, ELab{}, xs, push_lab(acc, lab), "", True{}, nlen)

def encode_xs(+id: U32, +xs: List<&2, String>) -> Result<&1, &1, U32 & String, String>:
  encode_go(Nat.add(1n, Nat.mul(3n, List.length(&2, String, xs))), ELab{}, xs, header(id), "", True{}, 1)

def encode_id(+id: U32, +host: String) -> Result<&1, &1, U32 & String, String>:
  encode_xs(id, String.split(host, Chr{46}))

def encode(+host: String) -> Result<&1, &1, U32 & String, String>:
  encode_id(1, host)

# ---- Data cursor (copyable). Pairs are affine; a do-block needs Data. --

type Cur is Data:
  Cur{pkt: List<&2, U32>, off: U32}

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
    case Cur{_, off}:
      off

def cur_add(+c: Cur, +n: U32) -> Cur:
  match c:
    case Cur{pkt, off}:
      Cur{pkt, U32.add(off, n)}

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
    case Cur{pkt, off}:
      at_xs(List.drop(&2, U32, pkt, U32.to_nat(off)))

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
          read_name_go(p, RdGot{}, pkt, pos, ret, hops, acc, lab, n, b, byte_at(Cur{pkt, pos}), False{})
        case RdGot{}:
          match got:
            case None{}:
              None{}
            case Some{+x}:
              read_name_go(p, RdKind{}, pkt, pos, ret, hops, acc, lab, n, x, None{}, U32.is_ge(x, 192))
        case RdKind{}:
          match flag:
            case True{}:
              read_name_go(p, RdPtr{}, pkt, pos, ret, hops, acc, lab, n, b, byte_at(Cur{pkt, U32.add(pos, 1)}), False{})
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
              read_name_go(p, RdLabB{}, pkt, pos, ret, hops, acc, lab, n, b, byte_at(Cur{pkt, pos}), False{})
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
    +g0 : Got <- take8(Cur{pkt, off})
    +g1 : Got <- take8(got_cur(g0))
    +g2 : Got <- take8(got_cur(g1))
    +g3 : Got <- take8(got_cur(g2))
    return U32.show(got_v(g0)) ++ "." ++ U32.show(got_v(g1)) ++ "." ++ U32.show(got_v(g2)) ++ "." ++ U32.show(got_v(g3))

def read_rr(+pkt: List<&2, U32>, +off: U32) -> Maybe<&2, RR>:
  do Maybe<&2, RR>:
    +nm : Nm <- read_name(pkt, off)
    +gt : Got <- take16(Cur{pkt, nm_off(nm)})
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
  AwSkip{}

def walk_an_go(
  fuel: Nat,
  ph: Aw,
  +pkt: List<&2, U32>,
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
              walk_an_go(p, AwGot{}, pkt, off, left, sought, rec, read_rr(pkt, off), None{}, None{}, False{})
        case AwGot{}:
          match mrr:
            case None{}:
              err("bad dns")
            case Some{+r}:
              walk_an_go(p, AwIn{}, pkt, off, left, sought, r, None{}, None{}, None{}, U32.is_eq(rr_cls(r), 1))
        case AwIn{}:
          match flag:
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, off, left, sought, rec, None{}, None{}, None{}, False{})
            case True{}:
              walk_an_go(p, AwTyA{}, pkt, off, left, sought, rec, None{}, None{}, None{}, U32.is_eq(rr_ty(rec), 1) && U32.is_eq(rr_rdlen(rec), 4))
        case AwTyA{}:
          match flag:
            case True{}:
              walk_an_go(p, AwOwnA{}, pkt, off, left, sought, rec, None{}, None{}, None{}, String.eq(rr_owner(rec), sought))
            case False{}:
              walk_an_go(p, AwTyCn{}, pkt, off, left, sought, rec, None{}, None{}, None{}, U32.is_eq(rr_ty(rec), 5))
        case AwOwnA{}:
          match flag:
            case True{}:
              walk_an_go(p, AwA{}, pkt, off, left, sought, rec, None{}, None{}, ip4_at(pkt, rr_rd(rec)), False{})
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, off, left, sought, rec, None{}, None{}, None{}, False{})
        case AwTyCn{}:
          match flag:
            case True{}:
              walk_an_go(p, AwOwnCn{}, pkt, off, left, sought, rec, None{}, None{}, None{}, String.eq(rr_owner(rec), sought))
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, off, left, sought, rec, None{}, None{}, None{}, False{})
        case AwOwnCn{}:
          match flag:
            case True{}:
              walk_an_go(p, AwCn{}, pkt, off, left, sought, rec, None{}, read_name(pkt, rr_rd(rec)), None{}, False{})
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, off, left, sought, rec, None{}, None{}, None{}, False{})
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
              +left2 = U32.sub(left, 1)
              walk_an_go(p, AwLeft{}, pkt, rr_next(rec), left2, nm_name(tgt), rec, None{}, None{}, None{}, U32.is_zero(left2))
        case AwSkip{}:
          +left2 = U32.sub(left, 1)
          walk_an_go(p, AwLeft{}, pkt, rr_next(rec), left2, sought, rec, None{}, None{}, None{}, U32.is_zero(left2))

def walk_an(+pkt: List<&2, U32>, +off: U32, +an: U32, +sought: String) -> Result<&1, &1, U32 & String, String>:
  walk_an_go(
    Nat.add(32n, Nat.mul(32n, List.length(&2, U32, pkt))),
    AwLeft{},
    pkt,
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
    +g0 : Got <- take16(Cur{pkt, 0})
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
    +gt : Got <- take16(Cur{pkt, nm_off(nm)})
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

def hdr_chks(+want: U32, +h: Hdr) -> List<&2, Chk>:
  Chk{U32.is_eq(hdr_id(h), want), "bad id"} <> Chk{U32.is_ge(hdr_fb(h), 128), "bad dns"} <> Chk{U32.is_zero(U32.and(hdr_fb(h), 2)), "tc"} <> Chk{rcode_ok(hdr_sb(h)), "rcode"} <> Chk{U32.is_eq(hdr_qd(h), 1), "bad dns"} <> Nil{}

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

type Take is Data:
  Miss{}
  HitOk{ip: String}
  HitErr{msg: String}

def peer_ok(+ns: String, +host: String, +port: U32) -> Bool:
  String.eq(ns, host) && U32.is_eq(port, 53)

def take_id(+msg: String, bad: Bool) -> Take:
  match bad:
    case True{}:
      Miss{}
    case False{}:
      HitErr{msg}

def take_parse(r: Result<&1, &1, U32 & String, String>) -> Take:
  match r:
    case Fail{(_, +msg)}:
      take_id(msg, String.eq(msg, "bad id"))
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
