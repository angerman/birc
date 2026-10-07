# SPDX-License-Identifier: Apache-2.0
# Retained-fd disk search drivers. Production scans never reopen by
# pathname: the helper `scan` subcommand (or the native scan law) opens
# O_NOFOLLOW, gates on fstat, reads the exact bytes via that one checked
# descriptor, and closes it; Bend scans the bytes purely through the
# shared octet core (Hs.scan_content). No paths or file content cross the
# helper seam beyond the admitted bytes; refusals and helper failures
# fail closed with fixed diagnostics, never child output.
import Base
import ./history_search.bend as Hs
import ./history.bend as Hist
import ./session.bend as Sess

# Packaged default helper; BIRC_SEARCH_HELPER=native selects the linked
# native scan instead of a helper process.
def program.default(got: Result<&1, &1, U32 & String, String>) -> String:
  match got:
    case Fail{_}: "birc-history-search"
    case Done{+program}: Bool.pick(String, String.is_empty(program), "birc-history-search", program)

def program() -> IO(String):
  do IO<String>:
    got : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_SEARCH_HELPER")
    return program.default(got)

# The scan output head ("SEbbbbb\n") is fixed width; the rest is content.
def SCAN_EVIDENCE_LEN() -> Nat:
  8n

def SCAN_OUTPUT_CAP() -> U32:
  8388672

def SCAN_NATIVE_CAP() -> U32:
  8388608

def disk_search_bytes.admitted(admitted: Bool, +content: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match admitted:
    case True{}: Hs.DiskFound{Hs.scan_content(content, query, endpoint, cursor)}
    case False{}: Hs.DiskFailed{"history search refused: file not admitted"}

def disk_search_bytes.missing(missing: Bool, +ev: Hs.SearchEvidence, +content: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match missing:
    case True{}: Hs.DiskFound{Hs.empty_page()}
    case False{}:
      disk_search_bytes.admitted(Hs.search_evidence_admitted(ev), content, endpoint, query, cursor)

def disk_search_bytes(+ev: Hs.SearchEvidence, +content: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match ev:
    case Hs.SearchEvidence{_, _, _, _, +missing}:
      disk_search_bytes.missing(missing, ev, content, endpoint, query, cursor)

def disk_search_failed.too_large(huge: Bool) -> Hs.DiskResult:
  match huge:
    case True{}: Hs.DiskFailed{"history search refused: file too large"}
    case False{}: Hs.DiskFailed{"history search refused: file not admitted"}

def disk_search_result.code(+code: U32, +out: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match code:
    case 0:
      disk_search_bytes(Hs.parse_search_evidence(String.take(out, SCAN_EVIDENCE_LEN())),
        String.drop(out, SCAN_EVIDENCE_LEN()), endpoint, query, cursor)
    case 5:
      Hs.DiskFailed{Hs.scan_changed_text()}
    case _: disk_search_failed.too_large(U32.is_eq(code, 3))

def disk_search_result.out(rest: String & String, +code: U32, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match rest:
    case (+out, _): disk_search_result.code(code, out, endpoint, query, cursor)

def disk_search_result.pair(pair: U32 & (String & String), +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match pair:
    case (+code, rest):
      disk_search_result.out(rest, code, endpoint, query, cursor)

def disk_search_result(got: Result<&1, &1, U32 & String, U32 & (String & String)>, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match got:
    case Fail{_}: Hs.DiskFailed{"history search refused: file not admitted"}
    case Done{pair}: disk_search_result.pair(pair, endpoint, query, cursor)

law search_scan:
  String -> U32 -> IO(U32 & U32 & String)

def search_scan(path, cap):
  import "../ffi/history_search_ffi.c"

def scan_native_failed(huge: Bool) -> Hs.DiskResult:
  match huge:
    case True{}: Hs.DiskFailed{"history search refused: file too large"}
    case False{}: Hs.DiskFailed{"history search refused: file not admitted"}

def scan_native_shrunk(shrunk: Bool, +bits: U32, +content: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match shrunk:
    case True{}: Hs.DiskFailed{Hs.scan_changed_text()}
    case False{}: disk_search_bytes(Hs.search_evidence_bits(bits), content, endpoint, query, cursor)

def scan_native_done(+bits: U32, +err: U32, +content: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match err:
    case 0: scan_native_shrunk(Hs.search_evidence_truncated(bits), bits, content, endpoint, query, cursor)
    case _: scan_native_failed(U32.is_eq(err, 27))

def scan_native_rest(rest: U32 & String, +bits: U32, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match rest:
    case (+err, +content): scan_native_done(bits, err, content, endpoint, query, cursor)

def scan_native_triple(triple: U32 & U32 & String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> Hs.DiskResult:
  match triple:
    case (+bits, rest): scan_native_rest(rest, bits, endpoint, query, cursor)

def scan_native(+path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> IO(Hs.DiskResult):
  do IO<Hs.DiskResult>:
    triple : U32 & U32 & String <- search_scan(path, SCAN_NATIVE_CAP())
    return scan_native_triple(triple, endpoint, query, cursor)

def disk_search_checked.gated(disabled: Bool, +path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> IO(Hs.DiskResult):
  match disabled:
    case True{}: IO.pure(Hs.DiskResult, Hs.DiskFound{Hs.empty_page()})
    case False{}:
      do IO<Hs.DiskResult>:
        helper : String <- program()
        got : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(helper, ["scan", path], "", SCAN_OUTPUT_CAP(), 30000)
        return disk_search_result(got, endpoint, query, cursor)

def disk_search_checked(+path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat, +history_on: Bool) -> IO(Hs.DiskResult):
  disk_search_checked.gated(String.is_empty(path) || Bool.not(history_on), path, endpoint, query, cursor)

# Affine-FD seam: one checked native open (lstat, O_NOFOLLOW, fstat
# admission) hands the retained descriptor out as an affine File; refusals
# arrive already closed. No probe-then-reopen window remains: the scan runs
# on the checked descriptor itself. Both backends link (C effect plus its
# numeric-fd JS twin), so suites prove the seam on the JS backend too.
law open_private:
  String -> IO(Result<&1, &1, U32 & String, File>)

def open_private(path):
  import "../ffi/history_search_ffi.c"
  import "../ffi/history_search_open.js"

def search_file_checked.gated(disabled: Bool, +path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat) -> IO(Hs.DiskResult):
  match disabled:
    case True{}: IO.pure(Hs.DiskResult, Hs.DiskFound{Hs.empty_page()})
    case False{}:
      do IO<Hs.DiskResult>:
        result : Result<&1, &1, U32 & String, File> <- open_private(path)
        Hs.search_opened(query, endpoint, cursor, result)

def search_file_checked(+path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat, +history_on: Bool) -> IO(Hs.DiskResult):
  search_file_checked.gated(String.is_empty(path) || Bool.not(history_on), path, endpoint, query, cursor)

# Async completion owner: the worker scans and posts SearchDone; the loop
# completes it against the CURRENT session (ticket/gen/endpoint must match
# the live owner). The wgen incarnation passes through untouched for the
# loop's incarnation fence. No scan runs, and nothing posts, when disabled.
def post_search_done(+result: Hs.DiskResult, +ticket: Nat, +gen: Nat, +wgen: U32, +endpoint: String, +orig: String, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.SearchDone{ticket, gen, wgen, endpoint, orig, result})
    return Unit{}

def search_run.post.go(post: Bool, +path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat, +ticket: Nat, +gen: Nat, +wgen: U32, +orig: String, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match post:
    case True{}:
      do IO<Unit>:
        result : Hs.DiskResult <- disk_search_checked(path, endpoint, query, cursor, True{})
        post_search_done(result, ticket, gen, wgen, endpoint, orig, evt)
    case False{}: IO.pure(Unit, Unit{})

def search_run.post(+history_on: Bool, +path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat, +ticket: Nat, +gen: Nat, +wgen: U32, +orig: String, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  search_run.post.go(history_on && Bool.not(String.is_empty(path)), path, endpoint, query, cursor, ticket, gen, wgen, orig, evt)

def search_run(+endpoint: String, +query: Hs.DiskQuery, +cursor: Nat, +history_on: Bool, +ticket: Nat, +gen: Nat, +wgen: U32, +orig: String, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    path : String <- Hist.resolve_history_path()
    search_run.post(history_on, path, endpoint, query, cursor, ticket, gen, wgen, orig, evt)

# Native twin of the worker for BIRC_SEARCH_HELPER=native (linked builds
# without a helper process). Called only from the loop's emit arm, never
# from suite-reachable code: the C law cannot link on the JS backend.
def search_run_native.post.go(post: Bool, +path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat, +ticket: Nat, +gen: Nat, +wgen: U32, +orig: String, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match post:
    case True{}:
      do IO<Unit>:
        result : Hs.DiskResult <- scan_native(path, endpoint, query, cursor)
        post_search_done(result, ticket, gen, wgen, endpoint, orig, evt)
    case False{}: IO.pure(Unit, Unit{})

def search_run_native.post(+history_on: Bool, +path: String, +endpoint: String, +query: Hs.DiskQuery, +cursor: Nat, +ticket: Nat, +gen: Nat, +wgen: U32, +orig: String, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  search_run_native.post.go(history_on && Bool.not(String.is_empty(path)), path, endpoint, query, cursor, ticket, gen, wgen, orig, evt)

def search_run_native(+endpoint: String, +query: Hs.DiskQuery, +cursor: Nat, +history_on: Bool, +ticket: Nat, +gen: Nat, +wgen: U32, +orig: String, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    path : String <- Hist.resolve_history_path()
    search_run_native.post(history_on, path, endpoint, query, cursor, ticket, gen, wgen, orig, evt)
