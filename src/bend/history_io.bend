# Private history writes. Keep foreign IO outside the proof-facing History.
import Base
import ./history.bend as H
import ./buffer.bend as Cl

# Test seam for a failed write after a descriptor was acquired.
def history_append_file.done(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(Maybe<&2, String>):
  match pair:
    case (f, result):
      do IO<Maybe<&2, String>>:
        Unit <- File.close(f)
        return H.save_result(result)

# Native append owns descriptor validation, per-file 0600 repair, write and
# close. Stage/errno alone cross the seam; neither paths nor file text leak
# into diagnostics. Blocking file work runs on the runtime helper thread.
law append_private:
  String -> String -> IO(U32 & U32)

def append_private(path, data):
  import "../ffi/history_ffi.c"

def history_append_file.private_result(pair: U32 & U32) -> Maybe<&2, String>:
  match pair:
    case (0, _): None{}
    case (stage, code): Some{H.save_error((code, ""), Bool.pick(String, U32.is_eq(stage, 1), "open failed", "write failed"))}

def history_append_file.check(skip: Bool, +path: String, +data: String) -> IO(Maybe<&2, String>):
  match skip:
    case True{}: IO.pure(Maybe<&2, String>, None{})
    case False{}:
      do IO<Maybe<&2, String>>:
        pair : U32 & U32 <- append_private(path, data)
        return history_append_file.private_result(pair)

def history_append_file(+path: String, +data: String) -> IO(Maybe<&2, String>):
  history_append_file.check(String.is_empty(path) || String.is_empty(data), path, data)

def maybe_save_history.check(enabled: Bool, +path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Maybe<&2, String>):
  match enabled:
    case False{}: IO.pure(Maybe<&2, String>, None{})
    case True{}: history_append_file(path, H.extract_new_history_for(endpoint, old_cl, new_cl))

def maybe_save_history(+path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Maybe<&2, String>):
  maybe_save_history.check(
    Bool.not(String.is_empty(path)) && Cl.settings_history(Cl.get_settings(new_cl)),
    path, endpoint, old_cl, new_cl
  )
