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

# Native framing keeps the last min(cap, 1024) lines of each target and the
# final channel order of an empty client. Bend still accepts each record.
# A client that already holds another buffer stays on the byte walker: the
# ring above does not see those buffers.
law read_kept:
  String -> String -> U32 -> IO(U32 & U32 & List<&2, String> & List<&2, List<&2, String>>)

def read_kept(path, endpoint, cap):
  import "../ffi/history_ffi.c"
  import "../ffi/history_read_kept.js"

def history_file.plant_one.got(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (+next, _): next

def history_file.plant_one(+name: String, +cl: Cl.Client) -> Cl.Client:
  history_file.plant_one.got(Cl.buf_get(cl, name, Cl.target_channel(name), True{}))

def history_file.plant(names: List<&2, String>, +cl: Cl.Client) -> Cl.Client:
  match names:
    case Nil{}: cl
    case Con{+name, +rest}: history_file.plant(rest, history_file.plant_one(name, cl))

def history_file.prepare(zero: Bool, +names: List<&2, String>, +cl: Cl.Client, +cap: U32) -> Cl.Client:
  match zero:
    case True{}: cl
    case False{}: history_file.plant(names, Cl.client_hist_open(cl, H.hist_keep(cap)))

def history_file.one(fields: List<&2, String>, +cl: Cl.Client, +endpoint: String, +cap: U32) -> Cl.Client:
  H.read_record.entry(H.parse_line_for.tokens(fields, endpoint), cl, cap)

def history_file.walk(lines: List<&2, List<&2, String>>, +cl: Cl.Client, +endpoint: String, +cap: U32) -> Cl.Client:
  match lines:
    case Nil{}: cl
    case Con{+fields, +rest}: history_file.walk(rest, history_file.one(fields, cl, endpoint, cap), endpoint, cap)

def history_file.restored(+names: List<&2, String>, +lines: List<&2, List<&2, String>>, +cl: Cl.Client, +endpoint: String, +cap: U32) -> Cl.Client:
  history_file.walk(lines, history_file.prepare(U32.is_eq(cap, 0), names, cl, cap), endpoint, cap)

def history_file.stage(stage: U32, +err: U32, +names: List<&2, String>, +lines: List<&2, List<&2, String>>, +snapshot: Bool, +cl: Cl.Client, +endpoint: String, +cap: U32, +now: String) -> Cl.Client:
  match stage:
    case 0:
      H.read_finish.client(snapshot, history_file.restored(names, lines, cl, endpoint, cap), now)
    case 1:
      cl
    case 2:
      H.read_error(snapshot, cl, (err, ""), "open failed")
    case 3:
      H.read_error(snapshot, H.read_finish.client(snapshot, cl, now), (err, ""), "size unavailable")
    case _:
      H.read_error(snapshot, H.read_finish.client(snapshot, history_file.restored(names, lines, cl, endpoint, cap), now), (err, ""), "read failed; only completed records were restored")

def history_file.names(rest: List<&2, String> & List<&2, List<&2, String>>, +stage: U32, +err: U32, +snapshot: Bool, +cl: Cl.Client, +endpoint: String, +cap: U32, +now: String) -> Cl.Client:
  match rest:
    case (+names, +lines): history_file.stage(stage, err, names, lines, snapshot, cl, endpoint, cap, now)

def history_file.err(rest: U32 & List<&2, String> & List<&2, List<&2, String>>, +stage: U32, +snapshot: Bool, +cl: Cl.Client, +endpoint: String, +cap: U32, +now: String) -> Cl.Client:
  match rest:
    case (+err, rest2): history_file.names(rest2, stage, err, snapshot, cl, endpoint, cap, now)

def history_file.apply(got: U32 & U32 & List<&2, String> & List<&2, List<&2, String>>, +snapshot: Bool, +cl: Cl.Client, +endpoint: String, +cap: U32, +now: String) -> Cl.Client:
  match got:
    case (+stage, rest): history_file.err(rest, stage, snapshot, cl, endpoint, cap, now)

def history_file.load(+snapshot: Bool, +path: String, +endpoint: String, +cap: U32, +cl: Cl.Client, +now: String) -> IO(Cl.Client):
  do IO<Cl.Client>:
    got : U32 & U32 & List<&2, String> & List<&2, List<&2, String>> <- read_kept(path, endpoint, cap)
    return history_file.apply(got, snapshot, cl, endpoint, cap, now)

def history_file.plain(+cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _, _}:
      Nat.is_le(Cl.buf_count(bufs), 1n)

def history_load_client.route(plain: Bool, +path: String, +endpoint: String, +cap: U32, +cl: Cl.Client, +now: String) -> IO(Cl.Client):
  match plain:
    case True{}: history_file.load(False{}, path, endpoint, cap, cl, now)
    case False{}: H.history_load_client(path, endpoint, cap, cl)

def history_load_client.pick(skip: Bool, +path: String, +endpoint: String, +cap: U32, +cl: Cl.Client, +now: String) -> IO(Cl.Client):
  match skip:
    case True{}: IO.pure(Cl.Client, cl)
    case False{}: history_load_client.route(history_file.plain(cl), path, endpoint, cap, cl, now)

def history_load_client(+path: String, +endpoint: String, +cap: U32, +cl: Cl.Client) -> IO(Cl.Client):
  match cl:
    case Cl.Client{_, _, _, _, +now, _, _, _, _}:
      history_load_client.pick(String.is_empty(path) || Bool.not(Cl.settings_history(Cl.get_settings(cl))), path, endpoint, cap, cl, now)

def history_snapshot_client.route(plain: Bool, +path: String, +endpoint: String, +cap: U32, +cl: Cl.Client) -> IO(Cl.Client):
  match plain:
    case True{}: history_file.load(True{}, path, endpoint, cap, cl, "")
    case False{}: H.history_snapshot_client(path, endpoint, cap, cl)

def history_snapshot_client(+path: String, +endpoint: String, +cap: U32, +cl: Cl.Client) -> IO(Cl.Client):
  history_snapshot_client.route(history_file.plain(cl), path, endpoint, cap, cl)

def history_init_client.pick(empty: Bool, +path: String, +endpoint: String, +cap: U32, +nick: String, +host: String, +now: String) -> IO(Cl.Client):
  match empty:
    case True{}: IO.pure(Cl.Client, Cl.init_with_cap(nick, host, cap))
    case False{}: history_load_client(path, endpoint, cap, Cl.set_now(Cl.init_with_cap(nick, host, cap), now))

def history_init_client(+path: String, +endpoint: String, +cap: U32, +nick: String, +host: String, +now: String) -> IO(Cl.Client):
  history_init_client.pick(String.is_empty(path), path, endpoint, cap, nick, host, now)
