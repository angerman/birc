# SPDX-License-Identifier: Apache-2.0
# Pure selected-transport defaults; port numbers never choose the mode.
import Base

def default_secure() -> Bool:
  True{}

def TLS_PORT() -> U32:
  6697

def PLAIN_PORT() -> U32:
  6667

def default_port(secure: Bool, port_explicit: Bool, port: U32) -> U32:
  Bool.pick(U32, port_explicit, port, Bool.pick(U32, secure, TLS_PORT(), PLAIN_PORT()))
