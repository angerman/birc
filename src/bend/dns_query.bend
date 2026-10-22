# SPDX-License-Identifier: Apache-2.0
# Pure A/AAAA query dispatch for the shared DNS chains in dns.bend. No IO:
# the JS backend pins this admission without sockets, while dns.bend owns
# UDP/TCP, timeouts, and resends. AAAA text/walk/parse stay in ipv6.bend.
# Dual-stack dial policy (v6-first ordering, fallback predicate) is also
# pure here; dns.bend owns the deadline-owned TCP attempts. Only
# TCP-connect failure falls back, never TLS-verification failure or
# plaintext downgrade.
import Base
import ./dns_wire.bend as Wire
import ./ipv6.bend as V6

def take_for(
  +aaaa: Bool,
  +ns: String,
  +id: U32,
  +qhost: String,
  +phost: String,
  +port: U32,
  xs: List<&2, U32>
) -> Wire.Take:
  match aaaa:
    case True{}:
      V6.take_pkt_aaaa(ns, id, qhost, phost, port, xs)
    case False{}:
      Wire.take_pkt(ns, id, qhost, phost, port, xs)

def tcp_parse(
  +aaaa: Bool,
  +id: U32,
  +host: String,
  +xs: List<&2, U32>
) -> Result<&1, &1, U32 & String, String>:
  match aaaa:
    case True{}:
      V6.parse_aaaa(id, host, xs)
    case False{}:
      Wire.parse_q(id, host, xs)

def encode_for(
  +aaaa: Bool,
  +id: U32,
  +host: String
) -> Result<&1, &1, U32 & String, List<&2, U32>>:
  match aaaa:
    case True{}:
      V6.encode_aaaa_id(id, host)
    case False{}:
      Wire.encode_edns_id(id, host)

# Explicit-port peer admission for owned fixtures. Production passes 53;
# verification still requires exact ns+port equality, never downgrades.
def peer_ok_at(+ns: String, +want_port: U32, +phost: String, +port: U32) -> Bool:
  String.eq(ns, phost) && U32.is_eq(port, want_port)

def take_a_at(ok: Bool, +id: U32, +qhost: String, xs: List<&2, U32>) -> Wire.Take:
  match ok:
    case False{}:
      Wire.Miss{}
    case True{}:
      Wire.take_parse(Wire.parse_q(id, qhost, xs))

def take_aaaa_at(ok: Bool, +id: U32, +qhost: String, xs: List<&2, U32>) -> Wire.Take:
  match ok:
    case False{}:
      Wire.Miss{}
    case True{}:
      V6.take_parse_aaaa(V6.parse_aaaa(id, qhost, xs))

def take_for_at(
  +aaaa: Bool,
  +ns: String,
  +want_port: U32,
  +id: U32,
  +qhost: String,
  +phost: String,
  +port: U32,
  xs: List<&2, U32>
) -> Wire.Take:
  match aaaa:
    case True{}:
      take_aaaa_at(peer_ok_at(ns, want_port, phost, port), id, qhost, xs)
    case False{}:
      take_a_at(peer_ok_at(ns, want_port, phost, port), id, qhost, xs)

# v6 wins when present; otherwise v4. Pure ordering for dual dial.
def first_of(v6: Maybe<&2, String>, v4: Maybe<&2, String>) -> Maybe<&2, String>:
  match v6:
    case Some{+ip}:
      Some{ip}
    case None{}:
      v4

def has_addr(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# Only a failed first attempt with a second address present falls back.
def should_fallback(first_failed: Bool, second: Maybe<&2, String>) -> Bool:
  match first_failed:
    case False{}:
      False{}
    case True{}:
      has_addr(second)

# Production dials lazily (AAAA, TCPv6, then A/TCPv4 only on TCP failure),
# so no up-front attempt plan is shared here; first_of/should_fallback
# above remain the pinned ordering/fallback predicates.
