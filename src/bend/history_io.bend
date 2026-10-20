# Private history writes. Keep foreign IO outside the proof-facing History.
import Base
import ./history.bend as H
import ./buffer.bend as Cl

# Durable write vs intentional skip vs failed append. Empty path/data (and
# caller-supplied skip) are Skip, not Ok: notice-only callers collapse both
# via append_notice, but checkpoint/save claims must not treat Skip as a write.
type Append is Data:
  Ok{}
  Skip{}
  Err{msg: String}

def append_notice(got: Append) -> Maybe<&2, String>:
  match got:
    case Ok{}: None{}
    case Skip{}: None{}
    case Err{+msg}: Some{msg}

# True only when bytes were written. Skip and Err must not advance durable claims.
def append_ok(got: Append) -> Bool:
  match got:
    case Ok{}: True{}
    case _: False{}

def append_err(got: Append) -> Bool:
  match got:
    case Err{_}: True{}
    case _: False{}

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

def history_append_file.skip(+path: String, +data: String) -> Bool:
  String.is_empty(path) || String.is_empty(data)

def history_append_file.err(+msg: String) -> Append:
  Err{msg}

def history_append_file.private_append(pair: U32 & U32) -> Append:
  match pair:
    case (0, _): Ok{}
    case (stage, code):
      history_append_file.err(H.save_error((code, ""), Bool.pick(String, U32.is_eq(stage, 1), "open failed", "write failed")))

def history_append_file.private_result(pair: U32 & U32) -> Maybe<&2, String>:
  append_notice(history_append_file.private_append(pair))

def history_append_file.outcome(skip: Bool, +path: String, +data: String) -> IO(Append):
  match skip:
    case True{}: IO.pure(Append, Skip{})
    case False{}:
      do IO<Append>:
        pair : U32 & U32 <- append_private(path, data)
        return history_append_file.private_append(pair)

# Characterization: empty path or data is Skip (collapsed to None by
# append_notice). Fail-closed symlink/ownership rejection stays in the native
# write path (skip=False).
def history_append_file.check(skip: Bool, +path: String, +data: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    got : Append <- history_append_file.outcome(skip, path, data)
    return append_notice(got)

def history_append_file(+path: String, +data: String) -> IO(Maybe<&2, String>):
  history_append_file.check(history_append_file.skip(path, data), path, data)

def history_append_file.typed(+path: String, +data: String) -> IO(Append):
  history_append_file.outcome(history_append_file.skip(path, data), path, data)

# Durable claim entry: empty data is Skip (nothing to write). Nonempty always
# attempts the native write so an empty path fails closed as Err, never a
# silent Skip success that advances checkpoint/hold/ack.
def history_append_file.claim(+path: String, +data: String) -> IO(Append):
  history_append_file.outcome(String.is_empty(data), path, data)

def maybe_save_history.outcome(enabled: Bool, +path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Append):
  match enabled:
    case False{}: IO.pure(Append, Skip{})
    case True{}: history_append_file.claim(path, H.extract_new_history_for(endpoint, old_cl, new_cl))

def maybe_save_history.outcome_except(enabled: Bool, +path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client, +excluded: List<&2, Nat>) -> IO(Append):
  match enabled:
    case False{}: IO.pure(Append, Skip{})
    case True{}: history_append_file.claim(path, H.extract_new_history_for_except(endpoint, old_cl, new_cl, excluded))

def maybe_save_history.check(enabled: Bool, +path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    got : Append <- maybe_save_history.outcome(enabled, path, endpoint, old_cl, new_cl)
    return append_notice(got)

# Exclusion variant: imported archive rows (the drain's claimed IDs,
# installed in the session owner) become the next baseline instead of
# being appended again. Live rows always save.
def maybe_save_history.check_except(enabled: Bool, +path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client, +excluded: List<&2, Nat>) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    got : Append <- maybe_save_history.outcome_except(enabled, path, endpoint, old_cl, new_cl, excluded)
    return append_notice(got)

def maybe_save_history.typed(+path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Append):
  maybe_save_history.outcome(
    Bool.not(String.is_empty(path)) && Cl.settings_history(Cl.get_settings(new_cl)),
    path, endpoint, old_cl, new_cl
  )

def maybe_save_history(+path: String, +endpoint: String, +old_cl: Cl.Client, +new_cl: Cl.Client) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    got : Append <- maybe_save_history.typed(path, endpoint, old_cl, new_cl)
    return append_notice(got)
