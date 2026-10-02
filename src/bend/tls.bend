# Native verified TLS over a connected Socket. Handles are affine aliases
# of the runtime's opaque Window shape; dup shares one TLS connection.
import Base

law Handle: Type

def Handle():
  Window

# Consumes the connected Socket, including on every failure. No application
# write can occur until certificate and original-hostname verification finish.
law open_for:
  Socket -> String -> U32 -> IO(Result<&1, &1, U32 & String, Handle>)

def open_for(sock, hostname, timeout_ms):
  import "../ffi/tls_ffi.c"

# Same octet/EOF shape as Dns.recv_octets. Native TLS first checks buffered
# plaintext; registering this effect with IO_READ would strand SSL_pending.
law recv_octets:
  Handle -> U32 -> IO(Handle & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>)

def recv_octets(handle, max):
  import "../ffi/tls_ffi.c"

law send_for:
  Handle -> String -> U32 -> IO(Handle & Result<&1, &1, U32 & String, Unit>)

def send_for(handle, text, timeout_ms):
  import "../ffi/tls_ffi.c"

law dup:
  Handle -> IO(Handle & Result<&1, &1, U32 & String, Handle>)

def dup(handle):
  import "../ffi/tls_ffi.c"

# Nonblocking best-effort close_notify followed by SHUT_RDWR. This wakes the
# shared reader, but each affine wrapper must still be closed exactly once.
law shutdown:
  Handle -> IO(Handle & Result<&1, &1, U32 & String, Unit>)

def shutdown(handle):
  import "../ffi/tls_ffi.c"

law close:
  Handle -> IO(Unit)

def close(handle):
  import "../ffi/tls_ffi.c"
