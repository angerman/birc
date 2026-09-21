# DNS resolver: identity, encode, parse edges (incl. WHATWG FFFD), live A.
import Base
import ./expect.bend as E
import ../../src/bend/dns.bend as Dns
import ../../src/bend/dns_wire.bend as Wire

def show_fail(e: U32 & String) -> String:
  match e:
    case (_, +msg):
      "fail:" ++ msg

def show_res(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+ip}:
      "ok:" ++ ip
    case Fail{e}:
      show_fail(e)

def show_take(t: Wire.Take) -> String:
  match t:
    case Wire.Miss{}:
      "miss"
    case Wire.HitOk{+ip}:
      "ok:" ++ ip
    case Wire.HitErr{+msg}:
      "fail:" ++ msg

def drop_s(fuel: Nat, z: Bool, +n: Nat, s: String) -> String:
  match fuel:
    case 0n:
      s
    case 1n+p:
      match z:
        case True{}:
          s
        case False{}:
          match s:
            case SNil{}:
              ""
            case SCon{_, t}:
              drop_s(p, Nat.is_eq(Nat.sub(n, 1n), 0n), Nat.sub(n, 1n), t)

def head_code(+s: String) -> U32:
  match s:
    case SNil{}:
      0
    case SCon{+h, _}:
      Char.to_u32(h)

def prefix_ok(+s: String) -> Bool:
  match s:
    case SCon{+a, SCon{+b, SCon{+c, SCon{+d, SCon{+e, SCon{+f, _}}}}}}:
      U32.is_eq(Char.to_u32(a), 0) && U32.is_eq(Char.to_u32(b), 1) && U32.is_eq(Char.to_u32(c), 1) && U32.is_eq(Char.to_u32(d), 0) && U32.is_eq(Char.to_u32(e), 0) && U32.is_eq(Char.to_u32(f), 1)
    case _:
      False{}

def from_octets(fuel: Nat, xs: List<&2, U32>, acc: String) -> String:
  match fuel:
    case 0n:
      String.reverse(acc)
    case 1n+p:
      match xs:
        case Nil{}:
          String.reverse(acc)
        case Con{+h, t}:
          from_octets(p, t, SCon{Chr{h}, acc})

def pack(+xs: List<&2, U32>) -> String:
  from_octets(Nat.add(1n, List.length(&2, U32, xs)), xs, "")

# Test-only WHATWG io_str → octets (live path uses recv_octets).
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
          octets_go(p, t, octets_put(utf8_bytes(Char.to_u32(h)), acc))

def octets(+s: String) -> List<&2, U32>:
  octets_go(Nat.add(1n, String.length(s)), s, Nil{})

def show_oct.go(fuel: Nat, +xs: List<&2, U32>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_oct.go(p, t, acc ++ U32.show(h) ++ ",")

def show_oct(+xs: List<&2, U32>) -> String:
  show_oct.go(Nat.add(1n, List.length(&2, U32, xs)), xs, "")

def sample() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

# Same packet after WHATWG io_str: 0x81/0x80 become U+FFFD.
def sample_fffd() -> List<&2, U32>:
  0 <> 1 <> 65533 <> 65533 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 65533 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

def sample_bad_id() -> List<&2, U32>:
  0 <> 2 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

def sample_rcode() -> List<&2, U32>:
  0 <> 1 <> 129 <> 1 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> Nil{}

def sample_noa() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> Nil{}

# WHATWG fused A rdata: U+0080, 0, 1 with rdlen 4 → C2 80 00 01 = 194.128.0.1.
# Flags/pointer stay FFFD so pack+octets does not re-expand 0x81/0xC0.
def sample_fused() -> List<&2, U32>:
  0 <> 1 <> 65533 <> 65533 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 65533 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 128 <> 0 <> 1 <> Nil{}

# Live octets (recv_octets): high-bit A rdata 194.128.0.1, real QR/RA flags.
def sample_fused_raw() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 194 <> 128 <> 0 <> 1 <> Nil{}

# ANCOUNT=1 CNAME, ARCOUNT=1 A 9.9.9.9.
def sample_cname_ar() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 5 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 3 <> 1 <> 98 <> 0 <> 1 <> 98 <> 0 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 9 <> 9 <> 9 <> 9 <> Nil{}

# Three A records (irc.libera.chat shape): first A wins.
def sample_three_a() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 3 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 5 <> 6 <> 7 <> 8 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 9 <> 9 <> 9 <> 9 <> Nil{}

# CNAME in AN, no additional.
def sample_cname_only() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 5 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 3 <> 1 <> 98 <> 0 <> Nil{}

# WHATWG roundtrip: String pack then octets (F9: parse_id is the only parse API).
def parse_pack(+xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  Wire.parse_id(1, octets(pack(xs)))

# 800 zero octets — larger than the old drop_go fuel of 700.
def txt_pad(fuel: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      txt_pad(p, 0 <> acc)

def sample_txt_ar_end(+mid: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, mid, 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 8 <> 8 <> 8 <> 8 <> Nil{})

# ANCOUNT=1 TXT rdlen=800, ARCOUNT=1 A 8.8.8.8 (F10: skip must consume full rdlen).
def sample_txt_ar() -> List<&2, U32>:
  sample_txt_ar_end(List.append(&2, U32, 0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 16 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 3 <> 32 <> Nil{}, txt_pad(800n, Nil{})))

# − dns#1: the only A is in ADDITIONAL for owner "evil" (an=0).
def pkt_ar_evil() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 4 <> 101 <> 118 <> 105 <> 108 <> 0 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 6 <> 6 <> 6 <> 6 <> Nil{}

# − dns#1: the only A is in AUTHORITY for owner "evil" (an=0).
def pkt_ns_evil() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 4 <> 101 <> 118 <> 105 <> 108 <> 0 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 6 <> 6 <> 6 <> 7 <> Nil{}

# − dns#2: AN A with CLASS=CHAOS (3).
def pkt_class_ch() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 3 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 7 <> 7 <> 7 <> 7 <> Nil{}

# − dns#6: TC bit set (flags byte 2 = 0x83).
def pkt_tc() -> List<&2, U32>:
  0 <> 1 <> 131 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 8 <> 8 <> 4 <> 4 <> Nil{}

# − dns#5: QDCOUNT=0.
def pkt_qd0() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 0 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 5 <> 5 <> 5 <> 5 <> Nil{}

# − dns#5: echoed question is z / QTYPE=255.
def pkt_wrong_q() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 122 <> 0 <> 0 <> 255 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 3 <> 3 <> 3 <> 3 <> Nil{}

# − dns#1 owner: AN has A for "evil", then CNAME a→b, then A for b.
def pkt_cname_owner() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 3 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 4 <> 101 <> 118 <> 105 <> 108 <> 0 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> 192 <> 12 <> 0 <> 5 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 3 <> 1 <> 98 <> 0 <> 1 <> 98 <> 0 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 9 <> 9 <> 9 <> 9 <> Nil{}

# + dns#1: CNAME a→b and A for b, both in ANSWER.
def pkt_cname_an() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 2 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 5 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 3 <> 1 <> 98 <> 0 <> 1 <> 98 <> 0 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 9 <> 9 <> 9 <> 9 <> Nil{}

# + dns#1: TXT then A, both in ANSWER (rdlen skip).
def pkt_txt_an() -> List<&2, U32>:
  List.append(&2, U32, 0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 2 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 16 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 3 <> 32 <> Nil{}, List.append(&2, U32, txt_pad(800n, Nil{}), 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 8 <> 8 <> 8 <> 8 <> Nil{}))

# lying counts; truncated rdata; short packets (already fail-closed).
def pkt_liar() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 255 <> 255 <> 255 <> 255 <> 255 <> 255 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> Nil{}

def pkt_trunc_rd() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 9 <> 9 <> Nil{}

def pkt_empty() -> List<&2, U32>:
  Nil{}

# dns#12: 5 × 63-char labels (QNAME 321 octets).
def rep_lab(fuel: Nat, acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      rep_lab(p, SCon{Chr{97}, acc})

def lab63() -> String:
  rep_lab(63n, "")

def long_name() -> String:
  lab63() ++ "." ++ lab63() ++ "." ++ lab63() ++ "." ++ lab63() ++ "." ++ lab63()

def live_addr_ok(+ip: String) -> Bool:
  String.eq(ip, "1.1.1.1") || String.eq(ip, "1.0.0.1")

def live_fail_ok(+msg: String) -> Bool:
  String.eq(msg, "timeout") || String.eq(msg, "bind") || String.eq(msg, "send") || String.eq(msg, "recv") || String.eq(msg, "random") || String.eq(msg, "bad id") || String.eq(msg, "bad dns") || String.eq(msg, "no A") || String.eq(msg, "short") || String.eq(msg, "tc") || String.eq(msg, "rcode") || String.eq(msg, "ipv6")

def check_live(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{+ip}:
      do IO<Unit>:
        Unit <- E.must("live_addr", live_addr_ok(ip))
        IO.print("name=ok:" ++ ip)
    case Fail{e}:
      match e:
        case (_, +msg):
          do IO<Unit>:
            Unit <- E.must("live_fail:" ++ msg, live_fail_ok(msg))
            IO.print("name=fail:" ++ msg)

def check_id_r(+host: String, r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{+ip}:
      E.must_eq("id " ++ host, ip, host)
    case Fail{_}:
      IO.die(Unit, 1, "identity fail")

def check_host(+host: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve(host)
    check_id_r(host, r)

def check_v6_r(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{_}:
      IO.die(Unit, 1, "ipv6 literal was accepted")
    case Fail{e}:
      match e:
        case (_, +msg):
          E.must_eq("resolve_v6", msg, "ipv6")

def check_enc_r(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.die(Unit, 1, "encode failed")
    case Done{+q}:
      do IO<Unit>:
        Unit <- E.must("enc_len", Nat.is_eq(String.length(q), 29n))
        Unit <- E.must("enc_pre", prefix_ok(q))
        E.must("enc_lab", U32.is_eq(head_code(drop_s(13n, False{}, 12n, q)), 7))

def snd_code(+s: String) -> U32:
  match s:
    case SCon{_, t}:
      head_code(t)
    case SNil{}:
      0

def check_enc_hi_r(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.die(Unit, 1, "encode hi failed")
    case Done{+q}:
      do IO<Unit>:
        Unit <- E.must("hi_b0", U32.is_lt(head_code(q), 128))
        E.must("hi_b1", U32.is_lt(snd_code(q), 128))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("ipv4 127", Wire.is_ipv4("127.0.0.1"))
    Unit <- E.must("ipv4 1.1", Wire.is_ipv4("1.1.1.1"))
    Unit <- E.must("ipv4 zero", Wire.is_ipv4("0.0.0.0"))
    Unit <- E.must("ipv4 max", Wire.is_ipv4("255.255.255.255"))
    Unit <- E.must("lead zero", Bool.not(Wire.is_ipv4("01.2.3.4")))
    Unit <- E.must("short", Bool.not(Wire.is_ipv4("1.2.3")))
    Unit <- E.must("name", Bool.not(Wire.is_ipv4("one.one.one.one")))
    Unit <- E.must("ipv6 lit", Wire.is_ipv6("::1"))
    Unit <- E.must("ipv6 full", Wire.is_ipv6("2001:db8::1"))
    Unit <- E.must("ipv6 not v4", Bool.not(Wire.is_ipv6("1.2.3.4")))
    Unit <- E.must("ipv6 not name", Bool.not(Wire.is_ipv6("example.com")))
    Unit <- check_enc_r(Wire.encode("example.com"))
    Unit <- check_enc_hi_r(Wire.encode_id(Wire.txid_of(65535), "example.com"))
    Unit <- E.must("pack_len", Nat.is_eq(String.length(pack(sample())), List.length(&2, U32, sample())))
    Unit <- E.must_eq("parse", show_res(Wire.parse_id(1, sample())), "ok:1.2.3.4")
    Unit <- E.must_eq("parse_fffd", show_res(parse_pack(sample_fffd())), "fail:rcode")
    Unit <- E.must_eq("parse_id", show_res(Wire.parse_id(1, sample_bad_id())), "fail:bad id")
    Unit <- E.must_eq("parse_id2", show_res(Wire.parse_id(2, sample_bad_id())), "ok:1.2.3.4")
    Unit <- E.must_eq("parse_rcode", show_res(Wire.parse_id(1, sample_rcode())), "fail:rcode")
    Unit <- E.must_eq("parse_noa", show_res(Wire.parse_id(1, sample_noa())), "fail:no A")
    Unit <- E.must_eq("octets_u80", show_oct(octets(SCon{Chr{128}, ""})), "194,128,")
    Unit <- E.must_eq("octets_fused", show_oct(octets(SCon{Chr{128}, SCon{Chr{0}, SCon{Chr{1}, ""}}})), "194,128,0,1,")
    Unit <- E.must_eq("parse_fused", show_res(Wire.parse_id(1, sample_fused_raw())), "ok:194.128.0.1")
    Unit <- E.must("txid_hi7", U32.is_lt(U32.shrn(Wire.txid_of(65535), 8n), 128))
    Unit <- E.must("txid_lo7", U32.is_lt(U32.and(Wire.txid_of(65535), 255), 128))
    Unit <- E.must("txid_nz", Bool.not(U32.is_zero(Wire.txid_of(0))))
    Unit <- E.must("txid_14", U32.is_eq(Wire.txid_of(1), Wire.txid_of(16385)))
    Unit <- E.must_eq("ns first", Wire.nameserver_of("nameserver 8.8.8.8\n"), "8.8.8.8")
    Unit <- E.must_eq("ns tab", Wire.nameserver_of("nameserver" ++ SCon{Chr{9}, "8.8.8.8\n"}), "8.8.8.8")
    Unit <- E.must_eq("ns indent", Wire.nameserver_of("  nameserver 8.8.8.8\n"), "8.8.8.8")
    Unit <- E.must_eq("ns dblsp", Wire.nameserver_of("nameserver  8.8.8.8\n"), "8.8.8.8")
    Unit <- E.must_eq("ns crlf", Wire.nameserver_of("nameserver 8.8.8.8\r\n"), "8.8.8.8")
    Unit <- E.must_eq("ns noeol", Wire.nameserver_of("nameserver 8.8.8.8"), "8.8.8.8")
    Unit <- E.must_eq("ns skip", Wire.nameserver_of("search lan\nnameserver 1.0.0.1\n"), "1.0.0.1")
    Unit <- E.must_eq("ns empty", Wire.nameserver_of(""), "1.1.1.1")
    Unit <- E.must_eq("ns v6", Wire.nameserver_of("nameserver 2001:db8::1\n"), "1.1.1.1")
    Unit <- E.must_eq("ns hash", Wire.nameserver_of("# nameserver 9.9.9.9\nnameserver 8.8.4.4\n"), "8.8.4.4")
    Unit <- E.must("tick_fast", U32.is_eq(Dns.tick_ms(0n), 10))
    Unit <- E.must("tick_slow", U32.is_eq(Dns.tick_ms(8n), 50))
    Unit <- E.must("resend0", Bool.not(Dns.need_resend(0n)))
    Unit <- E.must("resend16", Dns.need_resend(16n))
    Unit <- E.must_eq("parse_three_a", show_res(Wire.parse_id(1, sample_three_a())), "ok:1.2.3.4")
    Unit <- E.must_eq("parse_cname_ar", show_res(Wire.parse_id(1, sample_cname_ar())), "fail:no A")
    Unit <- E.must_eq("parse_cname_only", show_res(Wire.parse_id(1, sample_cname_only())), "fail:no A")
    Unit <- E.must_eq("parse_txt_ar", show_res(Wire.parse_id(1, sample_txt_ar())), "fail:no A")
    Unit <- E.must_eq("ar_evil", show_res(Wire.parse_id(1, pkt_ar_evil())), "fail:no A")
    Unit <- E.must_eq("ns_evil", show_res(Wire.parse_id(1, pkt_ns_evil())), "fail:no A")
    Unit <- E.must_eq("class_ch", show_res(Wire.parse_id(1, pkt_class_ch())), "fail:no A")
    Unit <- E.must_eq("tc", show_res(Wire.parse_id(1, pkt_tc())), "fail:tc")
    Unit <- E.must_eq("qd0", show_res(Wire.parse_id(1, pkt_qd0())), "fail:bad dns")
    Unit <- E.must_eq("wrong_q", show_res(Wire.parse_id(1, pkt_wrong_q())), "fail:bad dns")
    Unit <- E.must_eq("cname_owner", show_res(Wire.parse_id(1, pkt_cname_owner())), "ok:9.9.9.9")
    Unit <- E.must_eq("cname_an", show_res(Wire.parse_id(1, pkt_cname_an())), "ok:9.9.9.9")
    Unit <- E.must_eq("txt_an", show_res(Wire.parse_id(1, pkt_txt_an())), "ok:8.8.8.8")
    Unit <- E.must_eq("liar", show_res(Wire.parse_id(1, pkt_liar())), "fail:bad dns")
    Unit <- E.must_eq("trunc_rd", show_res(Wire.parse_id(1, pkt_trunc_rd())), "fail:bad dns")
    Unit <- E.must_eq("empty", show_res(Wire.parse_id(1, pkt_empty())), "fail:short")
    Unit <- E.must_eq("encode_long", show_res(Wire.encode(long_name())), "fail:bad name")
    Unit <- E.must("peer_ok", Wire.peer_ok("1.1.1.1", "1.1.1.1", 53))
    Unit <- E.must("peer_ip", Bool.not(Wire.peer_ok("1.1.1.1", "8.8.8.8", 53)))
    Unit <- E.must("peer_port", Bool.not(Wire.peer_ok("1.1.1.1", "1.1.1.1", 54)))
    Unit <- E.must_eq("take_hit", show_take(Wire.take_pkt("1.1.1.1", 1, "a", "1.1.1.1", 53, sample())), "ok:1.2.3.4")
    Unit <- E.must_eq("take_peer", show_take(Wire.take_pkt("1.1.1.1", 1, "a", "8.8.8.8", 53, sample())), "miss")
    Unit <- E.must_eq("take_id", show_take(Wire.take_pkt("1.1.1.1", 1, "a", "1.1.1.1", 53, sample_bad_id())), "miss")
    Unit <- E.must_eq("take_tc", show_take(Wire.take_pkt("1.1.1.1", 1, "a", "1.1.1.1", 53, pkt_tc())), "fail:tc")
    Unit <- check_host("127.0.0.1")
    Unit <- check_host("1.1.1.1")
    v6 : Result<&1, &1, U32 & String, String> <- Dns.resolve("::1")
    Unit <- check_v6_r(v6)
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve("one.one.one.one")
    Unit <- check_live(r)
    IO.print("dns_demo=ok")
