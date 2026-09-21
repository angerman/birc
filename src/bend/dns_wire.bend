# Pure DNS A wire encode/parse. No IO. dns.bend owns UDP.
# Query bytes are all < 128 so String send stays one octet per Char.
# Live recv is recv_octets (List U32 0..255). Tests still pack WHATWG
# io_str: ASCII one octet, U+FFFD stays 65533 (name-skip treats >=192 as
# a pointer; rcode_ok treats >255 as rcode 0), other codepoints expand as
# UTF-8 so fused A rdata is recovered.
import Base

def byte(+n: U32) -> String:
  SCon{Chr{n}, ""}

def err(+msg: String) -> Result<&1, &1, U32 & String, String>:
  Fail{(1, msg)}

def ok(+ip: String) -> Result<&1, &1, U32 & String, String>:
  Done{ip}

def code_of(+c: Char) -> U32:
  match c:
    case Chr{code}:
      code

def u16_of(+hi: U32, +lo: U32) -> U32:
  U32.add(U32.mul(hi, 256), lo)

# WHATWG io_str turns bytes 0x80–0xC1 into U+FFFD (65533). RA is 0x80, so a
# normal recursive answer's rcode byte becomes FFFD; FFFD & 15 == 13. Treat
# replacement chars as "high byte, rcode 0". Real rcode 1–15 without the high
# bit stay in 0–15 and still fail.
def rcode_ok(+b: U32) -> Bool:
  U32.is_eq(U32.and(b, 15), 0)

# ---- dotted IPv4 (no leading zeros; inet_pton rejects those) -----------

def starts_zero(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+h, _}:
      U32.is_eq(code_of(h), 48)

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
          ascii_go(p, t, ok && U32.is_lt(code_of(h), 128))

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
# ("bad dns") or nothing. 7+7 bits, never 0.
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

# ---- response bytes -----------------------------------------------------

# WHATWG io_str codepoints → wire octets. ASCII one byte; FFFD kept as 65533
# (not EF BF BD); everything else is UTF-8 so fused C2 80 becomes 194,128.
def utf8_4(+code: U32) -> List<&2, U32>:
  U32.or(240, U32.shrn(code, 18n)) <> U32.or(128, U32.and(U32.shrn(code, 12n), 63)) <> U32.or(128, U32.and(U32.shrn(code, 6n), 63)) <> U32.or(128, U32.and(code, 63)) <> Nil{}

def utf8_3(+code: U32, three: Bool) -> List<&2, U32>:
  match three:
    case True{}:
      U32.or(224, U32.shrn(code, 12n)) <> U32.or(128, U32.and(U32.shrn(code, 6n), 63)) <> U32.or(128, U32.and(code, 63)) <> Nil{}
    case False{}:
      utf8_4(code)

def utf8_2(+code: U32, two: Bool) -> List<&2, U32>:
  match two:
    case True{}:
      U32.or(192, U32.shrn(code, 6n)) <> U32.or(128, U32.and(code, 63)) <> Nil{}
    case False{}:
      utf8_3(code, U32.is_le(code, 65535))

def utf8_keep(+code: U32, keep: Bool) -> List<&2, U32>:
  match keep:
    case True{}:
      code <> Nil{}
    case False{}:
      utf8_2(code, U32.is_le(code, 2047))

def utf8_bytes(+code: U32) -> List<&2, U32>:
  utf8_keep(code, U32.is_le(code, 127) || U32.is_eq(code, 65533))

def octets_put(bs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, List.reverse(&2, U32, bs), acc)

def octets_go(fuel: Nat, s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+p:
      match s:
        case SNil{}:
          List.reverse(&2, U32, acc)
        case SCon{+h, t}:
          octets_go(p, t, octets_put(utf8_bytes(code_of(h)), acc))

def octets(+s: String) -> List<&2, U32>:
  octets_go(Nat.add(1n, String.length(s)), s, Nil{})

def take1(xs: List<&2, U32>) -> Maybe<&1, U32 & List<&2, U32>>:
  match xs:
    case Nil{}:
      None{}
    case Con{+h, t}:
      Some{(h, t)}

def take_u16_lo_p(+hi: U32, p: U32 & List<&2, U32>) -> Maybe<&1, U32 & List<&2, U32>>:
  match p:
    case (lo, rest):
      Some{(u16_of(hi, lo), rest)}

def take_u16_lo(+hi: U32, m: Maybe<&1, U32 & List<&2, U32>>) -> Maybe<&1, U32 & List<&2, U32>>:
  match m:
    case None{}:
      None{}
    case Some{p}:
      take_u16_lo_p(hi, p)

def take_u16_hi_p(p: U32 & List<&2, U32>) -> Maybe<&1, U32 & List<&2, U32>>:
  match p:
    case (hi, rest):
      take_u16_lo(hi, take1(rest))

def take_u16_hi(m: Maybe<&1, U32 & List<&2, U32>>) -> Maybe<&1, U32 & List<&2, U32>>:
  match m:
    case None{}:
      None{}
    case Some{p}:
      take_u16_hi_p(p)

def take_u16(xs: List<&2, U32>) -> Maybe<&1, U32 & List<&2, U32>>:
  take_u16_hi(take1(xs))

def drop_go(fuel: Nat, zero: Bool, +n: U32, xs: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match zero:
        case True{}:
          Some{xs}
        case False{}:
          match xs:
            case Nil{}:
              None{}
            case Con{_, t}:
              drop_go(p, U32.is_zero(U32.sub(n, 1)), U32.sub(n, 1), t)

# Fuel is remaining length + 1 so a u16 rdlen can skip every leftover octet
# (700 was too small for TXT then A in AR). Truncation still yields None.
def drop_rd(+xs: List<&2, U32>, +n: U32) -> Maybe<&2, List<&2, U32>>:
  drop_go(Nat.add(1n, List.length(&2, U32, xs)), U32.is_zero(n), n, xs)

type Sk is Data:
  SkRead{}
  SkZero{}
  SkPtr{}
  SkDrop{}
  SkBad{}
  SkLab{}
  SkLabOn{}
  SkLabDrop{}

def skip_name_go(
  fuel: Nat,
  ph: Sk,
  xs: List<&2, U32>,
  +b: U32,
  +n: U32,
  zero: Bool,
  ptr: Bool,
  bad: Bool
) -> Maybe<&2, List<&2, U32>>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match ph:
        case SkRead{}:
          match xs:
            case Nil{}:
              None{}
            case Con{+h, t}:
              skip_name_go(p, SkZero{}, t, h, 0, U32.is_zero(h), False{}, False{})
        case SkZero{}:
          match zero:
            case True{}:
              Some{xs}
            case False{}:
              skip_name_go(p, SkPtr{}, xs, b, n, False{}, U32.is_ge(b, 192), False{})
        case SkPtr{}:
          match ptr:
            case True{}:
              skip_name_go(p, SkDrop{}, xs, b, n, False{}, False{}, False{})
            case False{}:
              skip_name_go(p, SkBad{}, xs, b, n, False{}, False{}, U32.is_ge(b, 64))
        case SkDrop{}:
          match xs:
            case Nil{}:
              None{}
            case Con{_, t}:
              Some{t}
        case SkBad{}:
          match bad:
            case True{}:
              None{}
            case False{}:
              skip_name_go(p, SkLab{}, xs, b, b, False{}, False{}, False{})
        case SkLab{}:
          skip_name_go(p, SkLabOn{}, xs, b, n, U32.is_zero(n), False{}, False{})
        case SkLabOn{}:
          match zero:
            case True{}:
              skip_name_go(p, SkRead{}, xs, 0, 0, False{}, False{}, False{})
            case False{}:
              skip_name_go(p, SkLabDrop{}, xs, b, n, False{}, False{}, False{})
        case SkLabDrop{}:
          match xs:
            case Nil{}:
              None{}
            case Con{_, t}:
              skip_name_go(p, SkLab{}, t, b, U32.sub(n, 1), False{}, False{}, False{})

def skip_name(+xs: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  skip_name_go(
    Nat.add(1n, Nat.mul(12n, List.length(&2, U32, xs))),
    SkRead{},
    xs,
    0,
    0,
    False{},
    False{},
    False{}
  )

def join_oct(+acc: String, +b: U32, empty: Bool) -> String:
  match empty:
    case True{}:
      U32.show(b)
    case False{}:
      acc ++ "." ++ U32.show(b)

type IpPh is Data:
  IpCheck{}
  IpTake{}
  IpFit{}

def ip_go(
  fuel: Nat,
  ph: IpPh,
  xs: List<&2, U32>,
  done: Bool,
  fit: Bool,
  +left: U32,
  +acc: String,
  +h: U32
) -> Maybe<&1, String & List<&2, U32>>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match ph:
        case IpCheck{}:
          match done:
            case True{}:
              Some{(acc, xs)}
            case False{}:
              ip_go(p, IpTake{}, xs, False{}, False{}, left, acc, 0)
        case IpTake{}:
          match xs:
            case Nil{}:
              None{}
            case Con{+b, t}:
              ip_go(p, IpFit{}, t, False{}, U32.is_le(b, 255), left, acc, b)
        case IpFit{}:
          match fit:
            case False{}:
              None{}
            case True{}:
              ip_go(p, IpCheck{}, xs, U32.is_zero(U32.sub(left, 1)), False{}, U32.sub(left, 1), join_oct(acc, h, String.is_empty(acc)), 0)

def ip_call(xs: List<&2, U32>) -> Maybe<&1, String & List<&2, U32>>:
  ip_go(16n, IpCheck{}, xs, False{}, False{}, 4, "", 0)

type Qs is Data:
  QsZ{}
  QsN{}
  QsD{}

def skip_qs_go(
  fuel: Nat,
  ph: Qs,
  +xs: List<&2, U32>,
  +n: U32,
  got: Maybe<&2, List<&2, U32>>,
  zero: Bool
) -> Maybe<&2, List<&2, U32>>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match ph:
        case QsZ{}:
          match zero:
            case True{}:
              Some{xs}
            case False{}:
              skip_qs_go(p, QsN{}, xs, n, skip_name(xs), False{})
        case QsN{}:
          match got:
            case None{}:
              None{}
            case Some{+rest}:
              skip_qs_go(p, QsD{}, rest, n, drop_go(16n, False{}, 4, rest), False{})
        case QsD{}:
          match got:
            case None{}:
              None{}
            case Some{rest}:
              skip_qs_go(p, QsZ{}, rest, U32.sub(n, 1), None{}, U32.is_zero(U32.sub(n, 1)))

def skip_qs(xs: List<&2, U32>, +qd: U32) -> Maybe<&2, List<&2, U32>>:
  skip_qs_go(32n, QsZ{}, xs, qd, None{}, U32.is_zero(qd))

type Step is Data:
  StepHit{ip: String}
  StepNext{rest: List<&2, U32>}
  StepBad{}

def rr_hit_p(p: String & List<&2, U32>) -> Step:
  match p:
    case (+ip, _):
      StepHit{ip}

def rr_hit(m: Maybe<&1, String & List<&2, U32>>) -> Step:
  match m:
    case None{}:
      StepBad{}
    case Some{p}:
      rr_hit_p(p)

def rr_skip(m: Maybe<&2, List<&2, U32>>) -> Step:
  match m:
    case None{}:
      StepBad{}
    case Some{rest}:
      StepNext{rest}

def rr_use(+ty: U32, +rdlen: U32, rest: List<&2, U32>, is_a: Bool) -> Step:
  match is_a:
    case True{}:
      rr_hit(ip_call(rest))
    case False{}:
      rr_skip(drop_rd(rest, rdlen))

def rr_rd_p(+ty: U32, p: U32 & List<&2, U32>) -> Step:
  match p:
    case (+rdlen, rest):
      rr_use(ty, rdlen, rest, U32.is_eq(ty, 1) && U32.is_eq(rdlen, 4))

def rr_rd(+ty: U32, m: Maybe<&1, U32 & List<&2, U32>>) -> Step:
  match m:
    case None{}:
      StepBad{}
    case Some{p}:
      rr_rd_p(ty, p)

def rr_ttl(+ty: U32, m: Maybe<&2, List<&2, U32>>) -> Step:
  match m:
    case None{}:
      StepBad{}
    case Some{rest}:
      rr_rd(ty, take_u16(rest))

def rr_cls_p(+ty: U32, p: U32 & List<&2, U32>) -> Step:
  match p:
    case (_, rest):
      rr_ttl(ty, drop_go(8n, False{}, 4, rest))

def rr_cls(+ty: U32, m: Maybe<&1, U32 & List<&2, U32>>) -> Step:
  match m:
    case None{}:
      StepBad{}
    case Some{p}:
      rr_cls_p(ty, p)

def rr_ty_p(p: U32 & List<&2, U32>) -> Step:
  match p:
    case (ty, rest):
      rr_cls(ty, take_u16(rest))

def rr_ty(m: Maybe<&1, U32 & List<&2, U32>>) -> Step:
  match m:
    case None{}:
      StepBad{}
    case Some{p}:
      rr_ty_p(p)

def rr_named(m: Maybe<&2, List<&2, U32>>) -> Step:
  match m:
    case None{}:
      StepBad{}
    case Some{rest}:
      rr_ty(take_u16(rest))

def rr_one(xs: List<&2, U32>) -> Step:
  rr_named(skip_name(xs))

type Sec is Data:
  SAn{}
  SNs{}
  SAr{}

type Ans is Data:
  AZero{}
  AStep{}
  ANext{}

def answers_go(
  fuel: Nat,
  ph: Ans,
  +left: U32,
  +xs: List<&2, U32>,
  st: Step,
  zero: Bool,
  +ns: U32,
  +ar: U32,
  sec: Sec
) -> Result<&1, &1, U32 & String, String>:
  match fuel:
    case 0n:
      err("bad dns")
    case 1n+p:
      match ph:
        case AZero{}:
          match zero:
            case True{}:
              answers_go(p, ANext{}, left, xs, StepBad{}, False{}, ns, ar, sec)
            case False{}:
              answers_go(p, AStep{}, left, xs, rr_one(xs), False{}, ns, ar, sec)
        case AStep{}:
          match st:
            case StepBad{}:
              err("bad dns")
            case StepHit{+ip}:
              ok(ip)
            case StepNext{rest}:
              answers_go(p, AZero{}, U32.sub(left, 1), rest, StepBad{}, U32.is_zero(U32.sub(left, 1)), ns, ar, sec)
        case ANext{}:
          match sec:
            case SAn{}:
              answers_go(p, AZero{}, ns, xs, StepBad{}, U32.is_zero(ns), ns, ar, SNs{})
            case SNs{}:
              answers_go(p, AZero{}, ar, xs, StepBad{}, U32.is_zero(ar), ns, ar, SAr{})
            case SAr{}:
              err("no A")

def answers_call(+an: U32, +ns: U32, +ar: U32, +xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  answers_go(Nat.add(8n, Nat.mul(4n, List.length(&2, U32, xs))), AZero{}, an, xs, StepBad{}, U32.is_zero(an), ns, ar, SAn{})

def parse_qs(+an: U32, +ns: U32, +ar: U32, m: Maybe<&2, List<&2, U32>>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("bad dns")
    case Some{rest}:
      answers_call(an, ns, ar, rest)

def parse_got_empty(+qd: U32, +an: U32, +ns: U32, +ar: U32, rest: List<&2, U32>, empty: Bool) -> Result<&1, &1, U32 & String, String>:
  match empty:
    case True{}:
      err("no A")
    case False{}:
      parse_qs(an, ns, ar, skip_qs(rest, qd))

def parse_got(+qd: U32, +an: U32, +ns: U32, +ar: U32, rest: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  parse_got_empty(qd, an, ns, ar, rest, U32.is_zero(qd) && U32.is_zero(an))

def parse_ar_p(+qd: U32, +an: U32, +ns: U32, p: U32 & List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  match p:
    case (ar, rest):
      parse_got(qd, an, ns, ar, rest)

def parse_ar(+qd: U32, +an: U32, +ns: U32, m: Maybe<&1, U32 & List<&2, U32>>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{p}:
      parse_ar_p(qd, an, ns, p)

def parse_ns_p(+qd: U32, +an: U32, p: U32 & List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  match p:
    case (ns, rest):
      parse_ar(qd, an, ns, take_u16(rest))

def parse_ns(+qd: U32, +an: U32, m: Maybe<&1, U32 & List<&2, U32>>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{p}:
      parse_ns_p(qd, an, p)

def parse_an_p(+qd: U32, p: U32 & List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  match p:
    case (an, rest):
      parse_ns(qd, an, take_u16(rest))

def parse_an(+qd: U32, m: Maybe<&1, U32 & List<&2, U32>>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{p}:
      parse_an_p(qd, p)

def parse_qd_p(p: U32 & List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  match p:
    case (qd, rest):
      parse_an(qd, take_u16(rest))

def parse_qd(m: Maybe<&1, U32 & List<&2, U32>>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{p}:
      parse_qd_p(p)

def parse_sb_ok(rest: List<&2, U32>, okb: Bool) -> Result<&1, &1, U32 & String, String>:
  match okb:
    case False{}:
      err("rcode")
    case True{}:
      parse_qd(take_u16(rest))

def parse_sb_p(p: U32 & List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  match p:
    case (b, rest):
      parse_sb_ok(rest, rcode_ok(b))

def parse_sb(m: Maybe<&1, U32 & List<&2, U32>>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{p}:
      parse_sb_p(p)

def parse_fb_ok(rest: List<&2, U32>, qr: Bool) -> Result<&1, &1, U32 & String, String>:
  match qr:
    case False{}:
      err("bad dns")
    case True{}:
      parse_sb(take1(rest))

def parse_fb_p(p: U32 & List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  match p:
    case (b, rest):
      parse_fb_ok(rest, U32.is_ge(b, 128))

def parse_fb(m: Maybe<&1, U32 & List<&2, U32>>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{p}:
      parse_fb_p(p)

# Offset cursor over the original packet. Compression pointers jump here.
def at_xs(xs: List<&2, U32>) -> Maybe<&1, U32>:
  match xs:
    case Nil{}:
      None{}
    case Con{+h, _}:
      Some{h}

def at(+pkt: List<&2, U32>, +off: U32) -> Maybe<&1, U32>:
  at_xs(List.drop(&2, U32, pkt, U32.to_nat(off)))

def u16_at_lo(+hi: U32, m: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match m:
    case None{}:
      None{}
    case Some{lo}:
      Some{u16_of(hi, lo)}

def u16_at_hi(+pkt: List<&2, U32>, +off: U32, m: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match m:
    case None{}:
      None{}
    case Some{hi}:
      u16_at_lo(hi, at(pkt, U32.add(off, 1)))

def u16_at(+pkt: List<&2, U32>, +off: U32) -> Maybe<&1, U32>:
  u16_at_hi(pkt, off, at(pkt, off))

def lo_byte_on(+b: U32, up: Bool) -> U32:
  match up:
    case True{}:
      U32.add(b, 32)
    case False{}:
      b

def lo_byte(+b: U32) -> U32:
  lo_byte_on(b, U32.is_ge(b, 65) && U32.is_le(b, 90))

def name_lo.go(fuel: Nat, s: String, acc: String) -> String:
  match fuel:
    case 0n:
      String.reverse(acc)
    case 1n+p:
      match s:
        case SNil{}:
          String.reverse(acc)
        case SCon{+h, t}:
          name_lo.go(p, t, SCon{Chr{lo_byte(code_of(h))}, acc})

def name_lo(+s: String) -> String:
  name_lo.go(Nat.add(1n, String.length(s)), s, "")

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
  got: Maybe<&1, U32>,
  flag: Bool
) -> Maybe<&1, String & U32>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match ph:
        case RdGet{}:
          read_name_go(p, RdGot{}, pkt, pos, ret, hops, acc, lab, n, b, at(pkt, pos), False{})
        case RdGot{}:
          match got:
            case None{}:
              None{}
            case Some{+x}:
              read_name_go(p, RdKind{}, pkt, pos, ret, hops, acc, lab, n, x, None{}, U32.is_ge(x, 192))
        case RdKind{}:
          match flag:
            case True{}:
              read_name_go(p, RdPtr{}, pkt, pos, ret, hops, acc, lab, n, b, at(pkt, U32.add(pos, 1)), False{})
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
              Some{(acc, end_of(pos, ret))}
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
              read_name_go(p, RdLabB{}, pkt, pos, ret, hops, acc, lab, n, b, at(pkt, pos), False{})
        case RdLabB{}:
          match got:
            case None{}:
              None{}
            case Some{c}:
              read_name_go(p, RdLab{}, pkt, U32.add(pos, 1), ret, hops, acc, lab ++ byte(lo_byte(c)), U32.sub(n, 1), b, None{}, False{})

def read_name(+pkt: List<&2, U32>, +off: U32) -> Maybe<&1, String & U32>:
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

def ip4_d(+a: U32, +b: U32, +c: U32, m: Maybe<&1, U32>) -> Maybe<&1, String>:
  match m:
    case None{}:
      None{}
    case Some{d}:
      Some{U32.show(a) ++ "." ++ U32.show(b) ++ "." ++ U32.show(c) ++ "." ++ U32.show(d)}

def ip4_c(+a: U32, +b: U32, +pkt: List<&2, U32>, +off: U32, m: Maybe<&1, U32>) -> Maybe<&1, String>:
  match m:
    case None{}:
      None{}
    case Some{c}:
      ip4_d(a, b, c, at(pkt, U32.add(off, 3)))

def ip4_b(+a: U32, +pkt: List<&2, U32>, +off: U32, m: Maybe<&1, U32>) -> Maybe<&1, String>:
  match m:
    case None{}:
      None{}
    case Some{b}:
      ip4_c(a, b, pkt, off, at(pkt, U32.add(off, 2)))

def ip4_a(+pkt: List<&2, U32>, +off: U32, m: Maybe<&1, U32>) -> Maybe<&1, String>:
  match m:
    case None{}:
      None{}
    case Some{a}:
      ip4_b(a, pkt, off, at(pkt, U32.add(off, 1)))

def ip4_at(+pkt: List<&2, U32>, +off: U32) -> Maybe<&1, String>:
  ip4_a(pkt, off, at(pkt, off))

type Aw is Data:
  AwLeft{}
  AwName{}
  AwTy{}
  AwCls{}
  AwTtl{}
  AwRd{}
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
  +owner: String,
  +ty: U32,
  +cls: U32,
  +rdlen: U32,
  nm: Maybe<&1, String & U32>,
  u: Maybe<&1, U32>,
  ip: Maybe<&1, String>,
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
              walk_an_go(p, AwName{}, pkt, off, left, sought, owner, ty, cls, rdlen, read_name(pkt, off), None{}, None{}, False{})
        case AwName{}:
          match nm:
            case None{}:
              err("bad dns")
            case Some{(+own, +o2)}:
              walk_an_go(p, AwTy{}, pkt, o2, left, sought, own, ty, cls, rdlen, None{}, u16_at(pkt, o2), None{}, False{})
        case AwTy{}:
          match u:
            case None{}:
              err("bad dns")
            case Some{t}:
              walk_an_go(p, AwCls{}, pkt, U32.add(off, 2), left, sought, owner, t, cls, rdlen, None{}, u16_at(pkt, U32.add(off, 2)), None{}, False{})
        case AwCls{}:
          match u:
            case None{}:
              err("bad dns")
            case Some{c}:
              walk_an_go(p, AwTtl{}, pkt, U32.add(off, 2), left, sought, owner, ty, c, rdlen, None{}, None{}, None{}, False{})
        case AwTtl{}:
          walk_an_go(p, AwRd{}, pkt, U32.add(off, 4), left, sought, owner, ty, cls, rdlen, None{}, u16_at(pkt, U32.add(off, 4)), None{}, False{})
        case AwRd{}:
          match u:
            case None{}:
              err("bad dns")
            case Some{n}:
              walk_an_go(p, AwIn{}, pkt, U32.add(off, 2), left, sought, owner, ty, cls, n, None{}, None{}, None{}, U32.is_eq(cls, 1))
        case AwIn{}:
          match flag:
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, False{})
            case True{}:
              walk_an_go(p, AwTyA{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, U32.is_eq(ty, 1) && U32.is_eq(rdlen, 4))
        case AwTyA{}:
          match flag:
            case True{}:
              walk_an_go(p, AwOwnA{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, String.eq(owner, sought))
            case False{}:
              walk_an_go(p, AwTyCn{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, U32.is_eq(ty, 5))
        case AwOwnA{}:
          match flag:
            case True{}:
              walk_an_go(p, AwA{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, ip4_at(pkt, off), False{})
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, False{})
        case AwTyCn{}:
          match flag:
            case True{}:
              walk_an_go(p, AwOwnCn{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, String.eq(owner, sought))
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, False{})
        case AwOwnCn{}:
          match flag:
            case True{}:
              walk_an_go(p, AwCn{}, pkt, off, left, sought, owner, ty, cls, rdlen, read_name(pkt, off), None{}, None{}, False{})
            case False{}:
              walk_an_go(p, AwSkip{}, pkt, off, left, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, False{})
        case AwA{}:
          match ip:
            case None{}:
              err("bad dns")
            case Some{+addr}:
              ok(addr)
        case AwCn{}:
          match nm:
            case None{}:
              err("bad dns")
            case Some{(+tgt, _)}:
              +left2 = U32.sub(left, 1)
              walk_an_go(p, AwLeft{}, pkt, U32.add(off, rdlen), left2, tgt, owner, ty, cls, rdlen, None{}, None{}, None{}, U32.is_zero(left2))
        case AwSkip{}:
          +left2 = U32.sub(left, 1)
          walk_an_go(p, AwLeft{}, pkt, U32.add(off, rdlen), left2, sought, owner, ty, cls, rdlen, None{}, None{}, None{}, U32.is_zero(left2))

def walk_an(+pkt: List<&2, U32>, +off: U32, +an: U32, +sought: String) -> Result<&1, &1, U32 & String, String>:
  walk_an_go(
    Nat.add(32n, Nat.mul(32n, List.length(&2, U32, pkt))),
    AwLeft{},
    pkt,
    off,
    an,
    sought,
    "",
    0,
    0,
    0,
    None{},
    None{},
    None{},
    U32.is_zero(an)
  )

def parse_q_an(+pkt: List<&2, U32>, +off: U32, +host: String, m: Maybe<&1, U32>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{an}:
      walk_an(pkt, off, an, host)

def parse_q_nm(
  +host: String,
  +pkt: List<&2, U32>,
  +off: U32,
  +qname: String,
  same: Bool
) -> Result<&1, &1, U32 & String, String>:
  match same:
    case False{}:
      err("bad dns")
    case True{}:
      parse_q_an(pkt, off, host, u16_at(pkt, 6))

def parse_q_cls_ok(
  +host: String,
  +pkt: List<&2, U32>,
  +off: U32,
  +qname: String,
  okc: Bool
) -> Result<&1, &1, U32 & String, String>:
  match okc:
    case False{}:
      err("bad dns")
    case True{}:
      parse_q_nm(host, pkt, U32.add(off, 2), qname, String.eq(qname, host))

def parse_q_cls(
  +host: String,
  +pkt: List<&2, U32>,
  +off: U32,
  +qname: String,
  m: Maybe<&1, U32>
) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{c}:
      parse_q_cls_ok(host, pkt, off, qname, U32.is_eq(c, 1))

def parse_q_ty_ok(
  +host: String,
  +pkt: List<&2, U32>,
  +off: U32,
  +qname: String,
  okt: Bool
) -> Result<&1, &1, U32 & String, String>:
  match okt:
    case False{}:
      err("bad dns")
    case True{}:
      parse_q_cls(host, pkt, U32.add(off, 2), qname, u16_at(pkt, U32.add(off, 2)))

def parse_q_ty(
  +host: String,
  +pkt: List<&2, U32>,
  +off: U32,
  +qname: String,
  m: Maybe<&1, U32>
) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{t}:
      parse_q_ty_ok(host, pkt, off, qname, U32.is_eq(t, 1))

def parse_q_go(
  +host: String,
  +pkt: List<&2, U32>,
  +off: U32,
  nm: Maybe<&1, String & U32>
) -> Result<&1, &1, U32 & String, String>:
  match nm:
    case None{}:
      err("bad dns")
    case Some{(+qname, +o2)}:
      parse_q_ty(host, pkt, o2, qname, u16_at(pkt, o2))

def parse_q_qd_ok(+host: String, +pkt: List<&2, U32>, one: Bool) -> Result<&1, &1, U32 & String, String>:
  match one:
    case False{}:
      err("bad dns")
    case True{}:
      parse_q_go(host, pkt, 12, read_name(pkt, 12))

def parse_q_qd(+host: String, +pkt: List<&2, U32>, m: Maybe<&1, U32>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{qd}:
      parse_q_qd_ok(host, pkt, U32.is_eq(qd, 1))

def parse_q_rcode(+host: String, +pkt: List<&2, U32>, okb: Bool) -> Result<&1, &1, U32 & String, String>:
  match okb:
    case False{}:
      err("rcode")
    case True{}:
      parse_q_qd(host, pkt, u16_at(pkt, 4))

def parse_q_sb(+host: String, +pkt: List<&2, U32>, m: Maybe<&1, U32>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{b}:
      parse_q_rcode(host, pkt, rcode_ok(b))

def parse_q_tc(+host: String, +pkt: List<&2, U32>, +fb: U32, clear: Bool) -> Result<&1, &1, U32 & String, String>:
  match clear:
    case False{}:
      err("tc")
    case True{}:
      parse_q_sb(host, pkt, at(pkt, 3))

def parse_q_qr(+host: String, +pkt: List<&2, U32>, +fb: U32, qr: Bool) -> Result<&1, &1, U32 & String, String>:
  match qr:
    case False{}:
      err("bad dns")
    case True{}:
      parse_q_tc(host, pkt, fb, U32.is_zero(U32.and(fb, 2)))

def parse_q_fb(+host: String, +pkt: List<&2, U32>, m: Maybe<&1, U32>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{+b}:
      parse_q_qr(host, pkt, b, U32.is_ge(b, 128))

def parse_q_eq(+host: String, +pkt: List<&2, U32>, same: Bool) -> Result<&1, &1, U32 & String, String>:
  match same:
    case False{}:
      err("bad id")
    case True{}:
      parse_q_fb(host, pkt, at(pkt, 2))

def parse_q_id(+want: U32, +host: String, +pkt: List<&2, U32>, m: Maybe<&1, U32>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{id}:
      parse_q_eq(host, pkt, U32.is_eq(id, want))

def parse_q(+want: U32, +host: String, +xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  parse_q_id(want, name_lo(host), xs, u16_at(xs, 0))

# Tests use QNAME "a". Live lookup calls parse_q with the asked host.
def parse_id(+want: U32, xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  parse_q(want, "a", xs)

# Source-address check + wrong-id keep-listening (dns#3 #7).
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

def take_on(
  ok: Bool,
  +id: U32,
  +qhost: String,
  xs: List<&2, U32>
) -> Take:
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
