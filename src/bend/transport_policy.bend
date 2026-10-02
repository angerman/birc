# SPDX-License-Identifier: Apache-2.0
# Pure endpoint policy; TLS transport details stay outside protocol laws.
import Base

def TLS_PORT() -> U32:
  6697

def enabled(force_tls: Bool, port: U32) -> Bool:
  force_tls || U32.is_eq(port, TLS_PORT())

def default_port(force_tls: Bool, port_explicit: Bool, port: U32) -> U32:
  Bool.pick(U32, force_tls && Bool.not(port_explicit), TLS_PORT(), port)
