# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/ipv6.bend as V6
import ../../src/bend/endpoint.bend as Ep
import ../../src/bend/dns_wire.bend as Wire

def show_bytes.go(xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+h, t}: show_bytes.go(t, acc ++ U32.show(h) ++ ",")

def show_bytes(+xs: List<&2, U32>) -> String:
  show_bytes.go(xs, "")

def show_enc(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> String:
  match r:
    case Fail{(_, +msg)}: "fail:" ++ msg
    case Done{+q}: "ok:" ++ show_bytes(q)

def show_res(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{(_, +msg)}: "fail:" ++ msg
    case Done{+ip}: "ok:" ++ ip

def show_port(m: Maybe<&2, U32>) -> String:
  match m:
    case None{}: "none"
    case Some{+n}: U32.show(n)

def show_ep.host(+e: V6.EndpointV) -> String:
  match e:
    case V6.EndpointV{+host, +port, _}: host ++ ":" ++ show_port(port)

def show_ep.go(fam: V6.Family, +e: V6.EndpointV) -> String:
  match fam:
    case V6.V6{}: "v6:" ++ show_ep.host(e)
    case V6.V4{}: "v4:" ++ show_ep.host(e)

def show_ep(r: Result<&2, &2, String, V6.EndpointV>) -> String:
  match r:
    case Fail{+msg}: "bad:" ++ msg
    case Done{+e}: show_ep.go(V6.family_of(e), e)

def show_plan(p: V6.DialPlan) -> String:
  match p:
    case V6.Direct{+ip}: "direct:" ++ ip
    case V6.Resolve{+name}: "resolve:" ++ name

def show_take(t: Wire.Take) -> String:
  match t:
    case Wire.Miss{}: "miss"
    case Wire.HitOk{+ip}: "ok:" ++ ip
    case Wire.HitErr{+msg}: "err:" ++ msg

def show_resolved.fam(family: V6.Family, +host: String, +port: U32) -> String:
  match family:
    case V6.V6{}: "[" ++ host ++ "]:" ++ U32.show(port)
    case V6.V4{}: host ++ ":" ++ U32.show(port)

def show_resolved.rr(+r: V6.Resolved) -> String:
  match r:
    case V6.Resolved{+host, +port, +family}: show_resolved.fam(family, host, port)

def show_resolved(m: Maybe<&2, V6.Resolved>) -> String:
  match m:
    case None{}: "conflict"
    case Some{+r}: show_resolved.rr(r)

def resolved.go(r: Result<&2, &2, String, V6.EndpointV>, sep: Maybe<&2, U32>, +fb: U32) -> String:
  match r:
    case Fail{+msg}: "bad:" ++ msg
    case Done{+ep}: show_resolved(V6.resolve(ep, sep, fb))

def resolved(+text: String, sep: Maybe<&2, U32>, +fb: U32) -> String:
  resolved.go(V6.parse_any(text), sep, fb)

def repeated(n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: repeated(p, "a" ++ acc)

def hdr(+b0: U32, +b1: U32, +fb: U32, +sb: U32, +an0: U32, +an1: U32) -> List<&2, U32>:
  b0 <> b1 <> fb <> sb <> 0 <> 1 <> an0 <> an1 <> 0 <> 0 <> 0 <> 0 <> Nil{}

def qsec_a() -> List<&2, U32>:
  1 <> 97 <> 0 <> 0 <> 28 <> 0 <> 1 <> Nil{}

def qsec_a_old() -> List<&2, U32>:
  1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> Nil{}

def rdata16() -> List<&2, U32>:
  32 <> 1 <> 13 <> 184 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> Nil{}

def ans_aaaa_ptr() -> List<&2, U32>:
  List.append(&2, U32, 192 <> 12 <> 0 <> 28 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 16 <> Nil{}, rdata16())

def ans_cname_ptr() -> List<&2, U32>:
  192 <> 12 <> 0 <> 5 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 3 <> 1 <> 98 <> 0 <> Nil{}

def ans_aaaa_b() -> List<&2, U32>:
  List.append(&2, U32, 1 <> 98 <> 0 <> 0 <> 28 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 16 <> Nil{}, rdata16())

def ans_cname_self() -> List<&2, U32>:
  192 <> 12 <> 0 <> 5 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 2 <> 192 <> 12 <> Nil{}

def ans_aaaa_rdlen4() -> List<&2, U32>:
  192 <> 12 <> 0 <> 28 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

def ans_aaaa_nonin() -> List<&2, U32>:
  List.append(&2, U32, 192 <> 12 <> 0 <> 28 <> 0 <> 3 <> 0 <> 0 <> 0 <> 1 <> 0 <> 16 <> Nil{}, rdata16())

def ans_a_ptr() -> List<&2, U32>:
  192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

def pkt_of(+h: List<&2, U32>, +q: List<&2, U32>, +a: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, h, List.append(&2, U32, q, a))

def resp_direct() -> List<&2, U32>:
  pkt_of(hdr(0, 1, 129, 128, 0, 1), qsec_a(), ans_aaaa_ptr())

def resp_cname() -> List<&2, U32>:
  pkt_of(hdr(0, 1, 129, 128, 0, 2), qsec_a(), List.append(&2, U32, ans_cname_ptr(), ans_aaaa_b()))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("loopback", V6.valid_inner("::1"))
    Unit <- E.must("unspecified", V6.valid_inner("::"))
    Unit <- E.must("trailing gap", V6.valid_inner("1::"))
    Unit <- E.must("middle gap", V6.valid_inner("1::2"))
    Unit <- E.must("link local", V6.valid_inner("fe80::1"))
    Unit <- E.must("doc prefix", V6.valid_inner("2001:db8::1"))
    Unit <- E.must("full", V6.valid_inner("1:2:3:4:5:6:7:8"))
    Unit <- E.must("upper hex", V6.valid_inner("FD00::ABCD"))
    Unit <- E.must("all zero words", V6.valid_inner("0:0:0:0:0:0:0:0"))
    Unit <- E.must("gap seven", V6.valid_inner("1::2:3:4:5:6:7"))
    Unit <- E.must("empty refused", Bool.not(V6.valid_inner("")))
    Unit <- E.must("single colon refused", Bool.not(V6.valid_inner(":")))
    Unit <- E.must("trailing colon refused", Bool.not(V6.valid_inner("1:")))
    Unit <- E.must("leading colon refused", Bool.not(V6.valid_inner(":1")))
    Unit <- E.must("double gap refused", Bool.not(V6.valid_inner("1::2::3")))
    Unit <- E.must("triple colon refused", Bool.not(V6.valid_inner("1:::2")))
    Unit <- E.must("long group refused", Bool.not(V6.valid_inner("12345::")))
    Unit <- E.must("nonhex refused", Bool.not(V6.valid_inner("gggg::")))
    Unit <- E.must("nine groups refused", Bool.not(V6.valid_inner("1:2:3:4:5:6:7:8:9")))
    Unit <- E.must("seven bare refused", Bool.not(V6.valid_inner("1:2:3:4:5:6:7")))
    Unit <- E.must("dotted tail refused", Bool.not(V6.valid_inner("::ffff:1.2.3.4")))
    Unit <- E.must("zone refused", Bool.not(V6.valid_inner("fe80::1%eth0")))
    Unit <- E.must("space refused", Bool.not(V6.valid_inner("1::2 ")))
    Unit <- E.must("gap eight refused", Bool.not(V6.valid_inner("1:2:3:4:5:6:7:8::")))
    Unit <- E.must_eq("bracketed", show_ep(V6.parse_v6("[::1]:6697")), "v6:::1:6697")
    Unit <- E.must_eq("bracketed no port", show_ep(V6.parse_v6("[::1]")), "v6:::1:none")
    Unit <- E.must_eq("bracketed full", show_ep(V6.parse_v6("[2001:db8::1]:7000")), "v6:2001:db8::1:7000")
    Unit <- E.must_eq("bracketed zero port", show_ep(V6.parse_v6("[::1]:00007000")), "v6:::1:7000")
    Unit <- E.must_eq("bare refused", show_ep(V6.parse_v6("::1")), "bad:bad endpoint")
    Unit <- E.must_eq("unclosed refused", show_ep(V6.parse_v6("[::1")), "bad:bad endpoint")
    Unit <- E.must_eq("trailing text refused", show_ep(V6.parse_v6("[::1]extra")), "bad:bad endpoint")
    Unit <- E.must_eq("zero port refused", show_ep(V6.parse_v6("[::1]:0")), "bad:bad port")
    Unit <- E.must_eq("big port refused", show_ep(V6.parse_v6("[::1]:65536")), "bad:bad port")
    Unit <- E.must_eq("alpha port refused", show_ep(V6.parse_v6("[::1]:tls")), "bad:bad port")
    Unit <- E.must_eq("empty refused", show_ep(V6.parse_v6("[]:6697")), "bad:bad endpoint")
    Unit <- E.must_eq("bad literal refused", show_ep(V6.parse_v6("[1::2::3]:1")), "bad:bad endpoint")
    Unit <- E.must_eq("nested refused", show_ep(V6.parse_v6("[[::1]]:1")), "bad:bad endpoint")
    Unit <- E.must_eq("any dns", show_ep(V6.parse_any("irc.example:7000")), "v4:irc.example:7000")
    Unit <- E.must_eq("any ipv4", show_ep(V6.parse_any("127.0.0.1:7000")), "v4:127.0.0.1:7000")
    Unit <- E.must_eq("any v6", show_ep(V6.parse_any("[::1]:7000")), "v6:::1:7000")
    Unit <- E.must_eq("any bare v6 refused", show_ep(V6.parse_any("::1")), "bad:bad endpoint")
    Unit <- E.must_eq("any empty refused", show_ep(V6.parse_any("")), "bad:bad endpoint")
    Unit <- E.must_eq("any dns port", show_ep(V6.parse_any("irc.example:6697")), "v4:irc.example:6697")
    Unit <- E.must_eq("any v6 port", show_ep(V6.parse_any("[2001:db8::1]:6697")), "v6:2001:db8::1:6697")
    Unit <- E.must_eq("any alpha port kept", show_ep(V6.parse_any("irc.example:tls")), "bad:bad port")
    Unit <- E.must_eq("any zero port kept", show_ep(V6.parse_any("irc.example:0")), "bad:bad port")
    Unit <- E.must_eq("any big port kept", show_ep(V6.parse_any("irc.example:65536")), "bad:bad port")
    Unit <- E.must_eq("any ipv4 zero port kept", show_ep(V6.parse_any("127.0.0.1:0")), "bad:bad port")
    Unit <- E.must_eq("resolve inline", resolved("[::1]:6697", None{}, 6667), "[::1]:6697")
    Unit <- E.must_eq("resolve fallback", resolved("[::1]", None{}, 6667), "[::1]:6667")
    Unit <- E.must_eq("resolve separate", resolved("[::1]", Some{7000}, 6697), "[::1]:7000")
    Unit <- E.must_eq("resolve conflict", resolved("[::1]:6697", Some{7001}, 6697), "conflict")
    Unit <- E.must_eq("resolve v4", resolved("h", Some{7000}, 6697), "h:7000")
    Unit <- E.must_eq("format v6", V6.format(V6.EndpointV{"::1", Some{6697}, V6.V6{}}), "[::1]:6697")
    Unit <- E.must_eq("format v6 bare", V6.format(V6.EndpointV{"::1", None{}, V6.V6{}}), "[::1]")
    Unit <- E.must_eq("format v4", V6.format(V6.EndpointV{"h", Some{1}, V6.V4{}}), "h:1")
    Unit <- E.must_eq("scope v6", V6.scope_key("::1", 6697, V6.V6{}), "[::1]:6697")
    Unit <- E.must_eq("scope v4", V6.scope_key("h", 1, V6.V4{}), "h:1")
    Unit <- E.must_eq("plan v6", show_plan(V6.dial_plan("::1", V6.V6{})), "direct:::1")
    Unit <- E.must_eq("plan v4 lit", show_plan(V6.dial_plan("127.0.0.1", V6.V4{})), "direct:127.0.0.1")
    Unit <- E.must_eq("plan name", show_plan(V6.dial_plan("example.com", V6.V4{})), "resolve:example.com")
    Unit <- E.must("prefer v6", V6.prefer_v6())
    Unit <- E.must_eq("aaaa golden", show_enc(V6.encode_aaaa("example.com")), "ok:0,1,1,0,0,1,0,0,0,0,0,1,7,101,120,97,109,112,108,101,3,99,111,109,0,0,28,0,1,0,0,41,16,0,0,0,0,0,0,0,")
    Unit <- E.must_eq("aaaa id", show_enc(V6.encode_aaaa_id(Wire.txid_of(65535), "a")), "ok:255,255,1,0,0,1,0,0,0,0,0,1,1,97,0,0,28,0,1,0,0,41,16,0,0,0,0,0,0,0,")
    Unit <- E.must_eq("aaaa bad name", show_enc(V6.encode_aaaa("")), "fail:bad name")
    Unit <- E.must_eq("aaaa long label", show_enc(V6.encode_aaaa(repeated(64n, ""))), "fail:bad name")
    Unit <- E.must("aaaa root dot", String.eq(show_enc(V6.encode_aaaa("a.")), show_enc(V6.encode_aaaa("a"))))
    Unit <- E.must_eq("aaaa direct", show_res(V6.parse_aaaa(1, "a", resp_direct())), "ok:2001:db8:0:0:0:0:0:1")
    Unit <- E.must_eq("aaaa cname", show_res(V6.parse_aaaa(1, "a", resp_cname())), "ok:2001:db8:0:0:0:0:0:1")
    Unit <- E.must_eq("aaaa self cname", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 129, 128, 0, 1), qsec_a(), ans_cname_self()))), "fail:bad dns")
    Unit <- E.must_eq("aaaa wrong qtype", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 129, 128, 0, 1), qsec_a_old(), ans_a_ptr()))), "fail:bad dns")
    Unit <- E.must_eq("aaaa short", show_res(V6.parse_aaaa_id(1, 0 <> 1 <> 129 <> Nil{})), "fail:short")
    Unit <- E.must_eq("aaaa bad id", show_res(V6.parse_aaaa(1, "a", pkt_of(hdr(0, 2, 129, 128, 0, 1), qsec_a(), ans_aaaa_ptr()))), "fail:bad id")
    Unit <- E.must_eq("aaaa no answers", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 129, 128, 0, 0), qsec_a(), Nil{}))), "fail:no AAAA")
    Unit <- E.must_eq("aaaa short rdata", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 129, 128, 0, 1), qsec_a(), ans_aaaa_rdlen4()))), "fail:no AAAA")
    Unit <- E.must_eq("aaaa wrong owner", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 129, 128, 0, 1), qsec_a(), ans_aaaa_b()))), "fail:no AAAA")
    Unit <- E.must_eq("aaaa rcode", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 129, 131, 0, 0), qsec_a(), Nil{}))), "fail:rcode")
    Unit <- E.must_eq("aaaa tc empty", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 131, 128, 0, 0), qsec_a(), Nil{}))), "fail:tc")
    Unit <- E.must_eq("aaaa tc full", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 131, 128, 0, 1), qsec_a(), ans_aaaa_ptr()))), "ok:2001:db8:0:0:0:0:0:1")
    Unit <- E.must_eq("aaaa nonin", show_res(V6.parse_aaaa_id(1, pkt_of(hdr(0, 1, 129, 128, 0, 1), qsec_a(), ans_aaaa_nonin()))), "fail:no AAAA")
    Unit <- E.must_eq("aaaa root case", show_res(V6.parse_aaaa(1, "A.", resp_direct())), "ok:2001:db8:0:0:0:0:0:1")
    Unit <- E.must_eq("aaaa wrong host", show_res(V6.parse_aaaa(1, "b", resp_direct())), "fail:bad dns")
    Unit <- E.must_eq("take hit", show_take(V6.take_pkt_aaaa("1.1.1.1", 1, "a", "1.1.1.1", 53, resp_direct())), "ok:2001:db8:0:0:0:0:0:1")
    Unit <- E.must_eq("take peer miss", show_take(V6.take_pkt_aaaa("1.1.1.1", 1, "a", "9.9.9.9", 53, resp_direct())), "miss")
    Unit <- E.must_eq("take port miss", show_take(V6.take_pkt_aaaa("1.1.1.1", 1, "a", "1.1.1.1", 5353, resp_direct())), "miss")
    Unit <- E.must_eq("take id miss", show_take(V6.take_pkt_aaaa("1.1.1.1", 2, "a", "1.1.1.1", 53, resp_direct())), "miss")
    Unit <- E.must("literal ok", V6.literal_ok())
    Unit <- E.must("endpoint ok", V6.endpoint_ok())
    Unit <- E.must("dial ok", V6.dial_ok())
    IO.print("server_id_ipv6=ok")
