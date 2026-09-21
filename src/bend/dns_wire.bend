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
  U32.is_eq(U32.and(b, 15), 0) || U32.is_gt(b, 255)

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

def encode_go(
  fuel: Nat,
  ph: Enc,
  xs: List<&2, String>,
  acc: String,
  lab: String,
  ok: Bool
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
              encode_go(p, EOk{}, t, acc, h, label_ok(h))
        case EOk{}:
          match ok:
            case False{}:
              err("bad name")
            case True{}:
              encode_go(p, ELab{}, xs, push_lab(acc, lab), "", True{})

def encode_xs(+id: U32, +xs: List<&2, String>) -> Result<&1, &1, U32 & String, String>:
  encode_go(Nat.add(1n, Nat.mul(2n, List.length(&2, String, xs))), ELab{}, xs, header(id), "", True{})

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

def parse_id_ok(rest: List<&2, U32>, same: Bool) -> Result<&1, &1, U32 & String, String>:
  match same:
    case False{}:
      err("bad id")
    case True{}:
      parse_fb(take1(rest))

def parse_id_p(+want: U32, p: U32 & List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  match p:
    case (id, rest):
      parse_id_ok(rest, U32.is_eq(id, want))

def parse_id_m(+want: U32, m: Maybe<&1, U32 & List<&2, U32>>) -> Result<&1, &1, U32 & String, String>:
  match m:
    case None{}:
      err("short")
    case Some{p}:
      parse_id_p(want, p)

# Only parse API. Callers pass octets (WHATWG: octets(pack(wire)) for fused
# bytes). There is no parse(String) alias — that always used txid 1.
def parse_id(+want: U32, xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  parse_id_m(want, take_u16(xs))
