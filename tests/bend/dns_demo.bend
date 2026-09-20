# DNS resolver: identity, encode, parse edges (incl. WHATWG FFFD), live A.
import Base
import ./expect.bend as E
import ../../src/bend/dns.bend as Dns

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
  Dns.parse_id(1, Dns.octets(pack(xs)))

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

def live_fail_ok(+msg: String) -> Bool:
  String.eq(msg, "timeout") || String.eq(msg, "bind") || String.eq(msg, "send") || String.eq(msg, "recv") || String.eq(msg, "random") || String.eq(msg, "dns")

def check_live(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{+ip}:
      do IO<Unit>:
        Unit <- E.must("live_ipv4", Dns.is_ipv4(ip))
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
    Unit <- E.must("ipv4 127", Dns.is_ipv4("127.0.0.1"))
    Unit <- E.must("ipv4 1.1", Dns.is_ipv4("1.1.1.1"))
    Unit <- E.must("ipv4 zero", Dns.is_ipv4("0.0.0.0"))
    Unit <- E.must("ipv4 max", Dns.is_ipv4("255.255.255.255"))
    Unit <- E.must("lead zero", Bool.not(Dns.is_ipv4("01.2.3.4")))
    Unit <- E.must("short", Bool.not(Dns.is_ipv4("1.2.3")))
    Unit <- E.must("name", Bool.not(Dns.is_ipv4("one.one.one.one")))
    Unit <- check_enc_r(Dns.encode("example.com"))
    Unit <- check_enc_hi_r(Dns.encode_id(Dns.txid_of(65535), "example.com"))
    Unit <- E.must("pack_len", Nat.is_eq(String.length(pack(sample())), List.length(&2, U32, sample())))
    Unit <- E.must_eq("parse", show_res(Dns.parse_id(1, sample())), "ok:1.2.3.4")
    Unit <- E.must_eq("parse_fffd", show_res(parse_pack(sample_fffd())), "ok:1.2.3.4")
    Unit <- E.must_eq("parse_id", show_res(Dns.parse_id(1, sample_bad_id())), "fail:bad id")
    Unit <- E.must_eq("parse_id2", show_res(Dns.parse_id(2, sample_bad_id())), "ok:1.2.3.4")
    Unit <- E.must_eq("parse_rcode", show_res(Dns.parse_id(1, sample_rcode())), "fail:rcode")
    Unit <- E.must_eq("parse_noa", show_res(Dns.parse_id(1, sample_noa())), "fail:no A")
    Unit <- E.must_eq("octets_u80", show_oct(Dns.octets(SCon{Chr{128}, ""})), "194,128,")
    Unit <- E.must_eq("octets_fused", show_oct(Dns.octets(SCon{Chr{128}, SCon{Chr{0}, SCon{Chr{1}, ""}}})), "194,128,0,1,")
    Unit <- E.must_eq("parse_fused", show_res(parse_pack(sample_fused())), "ok:194.128.0.1")
    Unit <- E.must("txid_hi7", U32.is_lt(U32.shrn(Dns.txid_of(65535), 8n), 128))
    Unit <- E.must("txid_lo7", U32.is_lt(U32.and(Dns.txid_of(65535), 255), 128))
    Unit <- E.must("txid_nz", Bool.not(U32.is_zero(Dns.txid_of(0))))
    Unit <- E.must_eq("parse_three_a", show_res(Dns.parse_id(1, sample_three_a())), "ok:1.2.3.4")
    Unit <- E.must_eq("parse_cname_ar", show_res(Dns.parse_id(1, sample_cname_ar())), "ok:9.9.9.9")
    Unit <- E.must_eq("parse_cname_only", show_res(Dns.parse_id(1, sample_cname_only())), "fail:no A")
    Unit <- E.must_eq("parse_txt_ar", show_res(Dns.parse_id(1, sample_txt_ar())), "ok:8.8.8.8")
    Unit <- check_host("127.0.0.1")
    Unit <- check_host("1.1.1.1")
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve("one.one.one.one")
    Unit <- check_live(r)
    IO.print("dns_demo=ok")
