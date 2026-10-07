# Disk-history scan IO: paging, cursors, isolation, and failure modes.
# Synthetic fixtures only; no user files or live services.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as Hist
import ../../src/bend/history_search.bend as Hs
import ../../src/bend/history_search_io.bend as HSIO

def num2.pad(+n: Nat, small: Bool) -> String:
  match small:
    case True{}: "0" ++ Nat.show(n)
    case False{}: Nat.show(n)

def num2(+n: Nat) -> String:
  num2.pad(n, Nat.is_lt(n, 10n))

def rec(+i: Nat) -> String:
  "BIRC2\ta:6667\t#chan\tMSG\t10:00:00\talice\tneedle " ++ num2(i) ++ "\n"

def recs_go(n: Nat, +i: Nat, +acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: recs_go(p, 1n+i, acc ++ rec(i))

def recs(+n: Nat) -> String:
  recs_go(n, 0n, "")

def repeat(n: Nat, +text: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: text ++ repeat(p, text)

def wrote(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  match pair:
    case (f, Done{_}): IO.pure(File, f)
    case (f, Fail{_}):
      do IO<File>:
        Unit <- File.close(f)
        IO.die(File, 1, "fixture write failed")

def write_file(+path: String, +content: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, content)
    f : File <- wrote(pair)
    File.close(f)

def file_size.sized(pair: File & Result<&1, &1, U32 & String, U32>) -> IO(Nat):
  match pair:
    case (f, Done{+s}):
      do IO<Nat>:
        Unit <- File.close(f)
        return U32.to_nat(s)
    case (f, Fail{_}):
      do IO<Nat>:
        Unit <- File.close(f)
        return 0n

def file_size(+path: String) -> IO(Nat):
  do IO<Nat>:
    f : File <- IO.try(File, File.open(path, "r"))
    pair : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
    file_size.sized(pair)

def run_code(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> U32:
  match got:
    case Fail{_}: 99
    case Done{(+code, _)}: code

def run(+prog: String, args: List<&1, String>) -> IO(U32):
  do IO<U32>:
    got : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, args, "", 4096, 5000)
    return run_code(got)

def show_complete(done: Bool) -> String:
  match done:
    case True{}: "complete"
    case False{}: "partial"

def page_sig(+p: Hs.DiskPage) -> String:
  match p:
    case Hs.DiskPage{+matches, +next, +total, +complete}:
      Nat.show(List.length(&2, Hs.DiskMatch, matches)) ++ "|" ++ Nat.show(total)
        ++ "|" ++ show_complete(complete) ++ "|" ++ Nat.show(next)

def result_sig(+r: Hs.DiskResult) -> String:
  match r:
    case Hs.DiskFound{+page}: page_sig(page)
    case Hs.DiskFailed{+diagnostic}: "fail:" ++ diagnostic

def result_next(+r: Hs.DiskResult) -> Nat:
  match r:
    case Hs.DiskFound{Hs.DiskPage{_, +next, _, _}}: next
    case Hs.DiskFailed{_}: 0n

def result_page(+r: Hs.DiskResult) -> Hs.DiskPage:
  match r:
    case Hs.DiskFound{+page}: page
    case Hs.DiskFailed{_}: Hs.DiskPage{Nil{}, 0n, 0n, True{}}

def match_texts.go(xs: List<&2, Hs.DiskMatch>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{Hs.DiskMatch{_, +line, _}, t}: match_texts.go(t, acc ++ Hs.line_text(line) ++ "|")

def match_texts(+xs: List<&2, Hs.DiskMatch>) -> String:
  match_texts.go(xs, "")

def page_texts(+p: Hs.DiskPage) -> String:
  match p:
    case Hs.DiskPage{+matches, _, _, _}: match_texts(matches)

def match_first(xs: List<&2, Hs.DiskMatch>) -> String:
  match xs:
    case Nil{}: "<empty>"
    case Con{Hs.DiskMatch{_, +line, _}, _}: Hs.line_text(line)

def page_first(+p: Hs.DiskPage) -> String:
  match p:
    case Hs.DiskPage{+matches, _, _, _}:
      match_first(matches)

def page_last.go(xs: List<&2, Hs.DiskMatch>, +last: String) -> String:
  match xs:
    case Nil{}: last
    case Con{Hs.DiskMatch{_, +line, _}, t}: page_last.go(t, Hs.line_text(line))

def page_last(+p: Hs.DiskPage) -> String:
  match p:
    case Hs.DiskPage{+matches, _, _, _}: page_last.go(matches, "<empty>")

def search_texts.got(got: Maybe<&2, Nat>, +cl: Cl.Client) -> String:
  match got:
    case None{}: "<missing>"
    case Some{+i}: CL.buf_texts(cl, i)

def search_texts(+cl: Cl.Client) -> String:
  search_texts.got(Cl.buf_find(cl, "*search*"), cl)

def search_nlines.got(got: Maybe<&2, Nat>, +cl: Cl.Client) -> Nat:
  match got:
    case None{}: 0n
    case Some{+i}: CL.buf_nlines(cl, i)

def search_nlines(+cl: Cl.Client) -> Nat:
  search_nlines.got(Cl.buf_find(cl, "*search*"), cl)

# H5c direct early-EOF guards: drive the live scan loop against an actual
# file with remaining exactly the contents (success) versus remaining past
# the contents (truncated), instead of testing the predicate alone.
def search_loop_exact(+path: String, +size: Nat) -> IO(Hs.DiskResult):
  do IO<Hs.DiskResult>:
    f : File <- IO.try(File, File.open(path, "r"))
    Hs.search_loop(Nat.add(1n, size), f, Hs.DiskQuery{"needle", ""}, "a:6667", size, Hs.scan_initial(), size)

def search_loop_over(+path: String, +size: Nat, +extra: Nat) -> IO(Hs.DiskResult):
  do IO<Hs.DiskResult>:
    f : File <- IO.try(File, File.open(path, "r"))
    Hs.search_loop(Nat.add(1n, Nat.add(size, extra)), f, Hs.DiskQuery{"needle", ""}, "a:6667",
      Nat.add(size, extra), Hs.scan_initial(), Nat.add(size, extra))

def fixture_client() -> Cl.Client:
  Feed.feed_all(Cl.init("me", "irc.test"),
    ":me!u@h JOIN #chan" <> ":alice!u@h PRIVMSG #chan :live hello" <> Nil{})

def main() -> IO(Unit):
  +path : String = "build/history_search_page.fixture"
  +other_ep : String = "BIRC2\tb:6667\t#chan\tMSG\t10:00:00\talice\tneedle foreign\n"
  +malformed : String = "this is not a record\n"
  +legacy : String = "#chan\tMSG\t\tneedle legacy\n"
  +big : String = "BIRC2\ta:6667\t#chan\tMSG\t10:00:00\talice\t" ++ repeat(9000n, "x") ++ "needle\n"
  +unterminated : String = "BIRC2\ta:6667\t#chan\tMSG\t10:00:00\talice\tneedle tail"
  +content : String = recs(60n) ++ other_ep ++ malformed ++ legacy ++ big ++ unterminated
  +grown : String = content ++ "\nBIRC2\ta:6667\t#chan\tMSG\t10:00:00\talice\tneedle 60\n"
  +rec_len : Nat = String.length(rec(0n))
  +utf8_path : String = "build/history_search_utf8.fixture"
  +pad : String = "BIRC2\ta:6667\t#chan\tMSG\t10:00:00\talice\t" ++ repeat(4000n, "x") ++ "\n"
  +split : String = "BIRC2\ta:6667\t#chan\tMSG\t10:00:00\talice\t" ++ repeat(18n, "x") ++ "café split\n"
  do IO<Unit>:
    Unit <- write_file(path, content)
    +c600 : U32 <- run("chmod", ["600", path])
    Unit <- E.must("page_fixtures", U32.is_eq(c600, 0))
    +size : Nat <- file_size(path)
    # First page: newest 50 of 60; extras are excluded by the exact total.
    +r1 : Hs.DiskResult <- HSIO.search_file_checked(path, "a:6667", Hs.DiskQuery{"needle", ""}, size, True{})
    Unit <- E.must_eq("page1_sig", result_sig(r1),
      "50|60|partial|" ++ Nat.show(Nat.mul(10n, rec_len)))
    +p1 : Hs.DiskPage <- IO.pure(Hs.DiskPage, result_page(r1))
    Unit <- E.must_eq("page1_first", page_first(p1), "needle 10")
    Unit <- E.must_eq("page1_last", page_last(p1), "needle 59")
    # Second page: the older 10, then the window is exhausted.
    +r2 : Hs.DiskResult <- HSIO.search_file_checked(path, "a:6667", Hs.DiskQuery{"needle", ""}, result_next(r1), True{})
    Unit <- E.must_eq("page2_sig", result_sig(r2), "10|10|complete|0")
    +p2 : Hs.DiskPage <- IO.pure(Hs.DiskPage, result_page(r2))
    Unit <- E.must_eq("page2_texts", page_texts(p2),
      "needle 00|needle 01|needle 02|needle 03|needle 04|needle 05|needle 06|needle 07|needle 08|needle 09|")
    # Import focuses *search* and stays checkpoint-neutral.
    Unit <- E.must("import_lines", Nat.is_eq(search_nlines(Hs.import_page(fixture_client(), "needle", p1)), 51n))
    Unit <- E.must("import_focus", String.eq(Cl.active_buf_name(Hs.import_page(fixture_client(), "needle", p1)), "*search*"))
    Unit <- E.must("import_checkpoint", Nat.is_eq(Cl.log_seq_of(Hs.import_page(fixture_client(), "needle", p1)), Cl.log_seq_of(fixture_client())))
    Unit <- E.must("import_nosave", String.is_empty(Hist.extract_new_history_for("irc.test:6697",
      Hs.import_page(fixture_client(), "needle", p1), Hs.import_page(fixture_client(), "needle", p1))))
    Unit <- E.must("import_header", String.starts_with(search_texts(Hs.import_page(fixture_client(), "needle", p1)),
      "disk history: newest 50 of 60 matches for \"needle\""))
    # Endpoint isolation both directions.
    +rb : Hs.DiskResult <- HSIO.search_file_checked(path, "b:6667", Hs.DiskQuery{"needle", ""}, size, True{})
    Unit <- E.must_eq("endpoint_b", result_sig(rb), "1|1|complete|"
      ++ Nat.show(Nat.mul(60n, rec_len)))
    +pb : Hs.DiskPage <- IO.pure(Hs.DiskPage, result_page(rb))
    Unit <- E.must_eq("endpoint_b_text", page_first(pb), "needle foreign")
    # Target filters.
    +rt : Hs.DiskResult <- HSIO.search_file_checked(path, "a:6667", Hs.DiskQuery{"needle", "#other"}, size, True{})
    Unit <- E.must_eq("target_miss", result_sig(rt), "0|0|complete|0")
    +rh : Hs.DiskResult <- HSIO.search_file_checked(path, "a:6667", Hs.DiskQuery{"needle", "#chan"}, size, True{})
    Unit <- E.must_eq("target_hit", result_sig(rh),
      "50|60|partial|" ++ Nat.show(Nat.mul(10n, rec_len)))
    # Missing and disabled files report no matches, not errors.
    +rm : Hs.DiskResult <- HSIO.search_file_checked("build/history_search.absent", "a:6667", Hs.DiskQuery{"needle", ""}, 0n, True{})
    Unit <- E.must_eq("missing_file", result_sig(rm), "0|0|complete|0")
    +rd : Hs.DiskResult <- HSIO.search_file_checked("", "a:6667", Hs.DiskQuery{"needle", ""}, 0n, True{})
    Unit <- E.must_eq("disabled_path", result_sig(rd), "0|0|complete|0")
    # A cursor past EOF fails closed instead of returning a wrong page.
    +ro : Hs.DiskResult <- HSIO.search_file_checked(path, "a:6667", Hs.DiskQuery{"needle", ""}, Nat.add(size, 100n), True{})
    Unit <- E.must_eq("cursor_overflow", result_sig(ro), "fail:history changed; restart search")
    # Appends never disturb older offsets: the old cursor still pages.
    Unit <- write_file(path, grown)
    +size2 : Nat <- file_size(path)
    +r2b : Hs.DiskResult <- HSIO.search_file_checked(path, "a:6667", Hs.DiskQuery{"needle", ""}, result_next(r1), True{})
    Unit <- E.must_eq("append_stable", result_sig(r2b), "10|10|complete|0")
    +p2b : Hs.DiskPage <- IO.pure(Hs.DiskPage, result_page(r2b))
    Unit <- E.must_eq("append_stable_texts", page_texts(p2b), page_texts(p2))
    +r1b : Hs.DiskResult <- HSIO.search_file_checked(path, "a:6667", Hs.DiskQuery{"needle", ""}, size2, True{})
    Unit <- E.must_eq("append_newest", result_sig(r1b),
      "50|62|partial|" ++ Nat.show(Nat.mul(12n, rec_len)))
    +p1b : Hs.DiskPage <- IO.pure(Hs.DiskPage, result_page(r1b))
    Unit <- E.must_eq("append_first", page_first(p1b), "needle 12")
    Unit <- E.must_eq("append_last", page_last(p1b), "needle 60")
    # Multibyte records decode; a split scalar never becomes a match.
    Unit <- write_file(utf8_path, pad ++ split)
    +c600u : U32 <- run("chmod", ["600", utf8_path])
    Unit <- E.must("utf8_fixtures", U32.is_eq(c600u, 0))
    +usize : Nat <- file_size(utf8_path)
    +ru : Hs.DiskResult <- HSIO.search_file_checked(utf8_path, "a:6667", Hs.DiskQuery{"café", ""}, usize, True{})
    Unit <- E.must_eq("utf8_sig", result_sig(ru), "1|1|complete|"
      ++ Nat.show(String.length(pad)))
    +pu : Hs.DiskPage <- IO.pure(Hs.DiskPage, result_page(ru))
    Unit <- E.must_eq("utf8_text", page_first(pu), repeat(18n, "x") ++ "café split")
    # H5c early EOF through actual files: exact remaining succeeds, overlong
    # remaining reports truncation instead of partial success.
    +eof_path : String = "build/history_search_eof.fixture"
    Unit <- write_file(eof_path, recs(2n))
    +esize : Nat <- file_size(eof_path)
    +rexact : Hs.DiskResult <- search_loop_exact(eof_path, esize)
    Unit <- E.must_eq("eof_exact", result_sig(rexact), "2|2|complete|0")
    +pexact : Hs.DiskPage <- IO.pure(Hs.DiskPage, result_page(rexact))
    Unit <- E.must_eq("eof_exact_texts", page_texts(pexact), "needle 00|needle 01|")
    +rover : Hs.DiskResult <- search_loop_over(eof_path, esize, 10n)
    Unit <- E.must_eq("eof_truncated", result_sig(rover), "fail:history changed; restart search")
    IO.print("history_search_io=ok")
