# DNS A lookup. Pure wire (encode/parse) lives in dns_wire.bend for tests.
# Live resolve is getaddrinfo (dns_ffi.c): UDP String recv cannot recover
# A rdata bytes 0x80–0xC1 (WHATWG U+FFFD), which real hosts like
# irc.libera.chat use.
import Base
import ./dns_wire.bend as Wire

def err(+msg: String) -> Result<&1, &1, U32 & String, String>:
  Wire.err(msg)

def is_ipv4(+host: String) -> Bool:
  Wire.is_ipv4(host)

def txid_of(+n: U32) -> U32:
  Wire.txid_of(n)

def encode_id(+id: U32, +host: String) -> Result<&1, &1, U32 & String, String>:
  Wire.encode_id(id, host)

def encode(+host: String) -> Result<&1, &1, U32 & String, String>:
  Wire.encode(host)

def octets(+s: String) -> List<&2, U32>:
  Wire.octets(s)

def parse_id(+want: U32, xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  Wire.parse_id(want, xs)

law lookup_a:
  String -> IO(Result<&1, &1, U32 & String, String>)

def lookup_a(name):
  import "../ffi/dns_ffi.c"

def resolve_pick(+host: String, ip: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match ip:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{host})
    case False{}:
      lookup_a(host)

def resolve(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  resolve_pick(host, is_ipv4(host))
