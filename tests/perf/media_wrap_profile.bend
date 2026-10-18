# SPDX-License-Identifier: Apache-2.0
# Component profile only. Inputs come from IO to prevent constant folding.
# Usage: media_wrap_profile MODE LINKS SAMPLES [LINE_COUNT]
# Modes: lex, rows, empty, ready, parts-empty, parts-ready, body, body-media,
# whole, viewport.
# LINKS=0 uses plain text; 1..16 includes one known image plus ordinary links.
# New whole/viewport modes ignore LINKS and use stamped 171-character messages
# at width 180/height 45. Only these modes use LINE_COUNT (default 128, 1..1024).
# Every mode warms and consumes one full batch before its timed full batch.
import Base
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/links.bend as Links
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V

def image_url() -> String:
  "https://x.test/image.png"

def ordinary_links(+n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: " https://x.test/page" ++ Nat.show(n) ++ ".html" ++ ordinary_links(p)

def fixture_text(links: Nat, seed: Nat) -> String:
  match links:
    case 0n:
      "alice: " ++ Nat.show(seed) ++ " " ++ "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    case 1n+p:
      "alice: " ++ Nat.show(seed) ++ " " ++ image_url() ++ ordinary_links(p) ++ " tail"

def fixture_state(ready: Bool, +seed: Nat) -> M.State:
  match ready:
    case False{}: M.State{False{}, seed, seed, None{}, Nil{}, Nil{}, M.Supported{}}
    case True{}: M.State{True{}, seed, seed, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, image_url(), 7}], M.Supported{}}

def count_rows(rows: Bool, text: String, media: M.State) -> Nat:
  match rows:
    case True{}: List.length(&2, V.BodyRow, V.wrapped_rows(Cl.Msg{}, "", text, 80, False{}))
    case False{}: List.length(&2, V.BodyRow, V.wrapped_media(Cl.Msg{}, "", text, 80, False{}, 1n, media))

def count(parts: Bool, rows: Bool, text: String, media: M.State) -> Nat:
  match parts:
    case False{}: count_rows(rows, text, media)
    case True{}: List.length(&2, V.MediaPart, V.media_parts(V.line_spans_for(Cl.Msg{}, text), Nil{}, M.known_urls(media, M.Inline{1n})))

def batch(n: Nat, +parts: Bool, +rows: Bool, +text: String, +media: M.State, acc: Nat) -> Nat:
  match n:
    case 0n: acc
    case 1n+p: batch(p, parts, rows, text, media, Nat.add(acc, count(parts, rows, text, media)))

def finish(+t0: Nat, +mode: String, +links: Nat, +n: Nat, total: Nat) -> IO(Unit):
  do IO<Unit>:
    t1 : Nat <- IO.now()
    IO.print("mode=" ++ mode ++ " links=" ++ Nat.show(links) ++ " samples=" ++ Nat.show(n) ++ " consumed=" ++ Nat.show(total) ++ " wrap_ms=" ++ Nat.show(Nat.sub(t1, t0)) ++ "\n")

def measure(+mode: String, +links: Nat, +n: Nat, +parts: Bool, +rows: Bool, +text: String, +media: M.State) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print("warm_consumed=" ++ Nat.show(batch(n, parts, rows, text, media, 0n)) ++ "\n")
    t0 : Nat <- IO.now()
    finish(t0, mode, links, n, batch(n, parts, rows, text, media, 0n))

def fixture_lines(+n: Nat, +text: String) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p: Cl.Line{Cl.Msg{}, "", text, "alice", n} <> fixture_lines(p, text)

def viewport_text.number(+number: String) -> String:
  "<a> row" ++ String.take("000", Nat.sub(3n, String.length(number)))
    ++ number ++ " " ++ String.repeat("x", 160n)

def viewport_text(row: Nat) -> String:
  viewport_text.number(Nat.show(Nat.mod(row, 1000n)))

def viewport_lines(n: Nat, +row: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p:
      Cl.Line{Cl.Msg{}, "12:34:56", viewport_text(row), "a", 1n+row}
        <> viewport_lines(p, 1n+row)

def buffer_count(whole: Bool, buffer: Cl.Buffer, media: M.State) -> Nat:
  match whole:
    case True{}:
      match buffer:
        case Cl.Buffer{name, _, _, lines, _, _, _, _}:
          List.length(&2, V.BodyRow, V.body_rows_media(lines, name, 180, True{}, media))
    case False{}:
      List.length(&2, V.BodyRow, V.body_of.buf_media(buffer, 45n, 180, True{}, Nil{}, True{}, True{}, "s", media))

def buffer_batch(n: Nat, +whole: Bool, +buffer: Cl.Buffer, +media: M.State, acc: Nat) -> Nat:
  match n:
    case 0n: acc
    case 1n+p: buffer_batch(p, whole, buffer, media, Nat.add(acc, buffer_count(whole, buffer, media)))

def measure_buffer(+mode: String, +links: Nat, +n: Nat, +buffer: Cl.Buffer, +media: M.State) -> IO(Unit):
  +whole = String.eq(mode, "whole")
  do IO<Unit>:
    Unit <- IO.print("warm_consumed=" ++ Nat.show(buffer_batch(n, whole, buffer, media, 0n)) ++ "\n")
    t0 : Nat <- IO.now()
    finish(t0, mode, links, n, buffer_batch(n, whole, buffer, media, 0n))

def body_count(rows: Bool, lines: List<&2, Cl.Line>, media: M.State) -> Nat:
  match rows:
    case True{}: List.length(&2, V.BodyRow, V.body_rows(lines, "#t", 80, False{}))
    case False{}: List.length(&2, V.BodyRow, V.body_rows_media(lines, "#t", 80, False{}, media))

def body_batch(n: Nat, +rows: Bool, +lines: List<&2, Cl.Line>, +media: M.State, acc: Nat) -> Nat:
  match n:
    case 0n: acc
    case 1n+p: body_batch(p, rows, lines, media, Nat.add(acc, body_count(rows, lines, media)))

def measure_body(+mode: String, +links: Nat, +n: Nat, +lines: List<&2, Cl.Line>, +media: M.State) -> IO(Unit):
  +rows = String.eq(mode, "body")
  do IO<Unit>:
    Unit <- IO.print("warm_consumed=" ++ Nat.show(body_batch(n, rows, lines, media, 0n)) ++ "\n")
    t0 : Nat <- IO.now()
    finish(t0, mode, links, n, body_batch(n, rows, lines, media, 0n))

# Consume every lexer run, without View span conversion or wrapping.
def lex_batch(n: Nat, +text: String, acc: Nat) -> Nat:
  match n:
    case 0n: acc
    case 1n+p: lex_batch(p, text, Nat.add(acc, List.length(&2, Links.Run, Links.render(text))))

def measure_lex(+mode: String, +links: Nat, +n: Nat, +text: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print("warm_consumed=" ++ Nat.show(lex_batch(n, text, 0n)) ++ "\n")
    t0 : Nat <- IO.now()
    finish(t0, mode, links, n, lex_batch(n, text, 0n))

def run_text(lex: Bool, +mode: String, +links: Nat, +n: Nat, text: String, media: M.State) -> IO(Unit):
  match lex:
    case True{}: measure_lex(mode, links, n, text)
    case False{}:
      measure(mode, links, n, String.eq(mode, "parts-empty") || String.eq(mode, "parts-ready"), String.eq(mode, "rows"), text, media)

def run_mode(body: Bool, +mode: String, +links: Nat, +n: Nat, text: String, media: M.State) -> IO(Unit):
  match body:
    case True{}: measure_body(mode, links, n, fixture_lines(128n, text), media)
    case False{}:
      run_text(String.eq(mode, "lex"), mode, links, n, text, media)

def source_info(+text: String) -> IO(Unit):
  # Every fixture character is ASCII, so this is its UTF-8 byte count.
  IO.print("source_bytes=" ++ Nat.show(String.length(text)) ++ " outbound_privmsg_bytes=" ++ Nat.show(Nat.add(14n, String.length(text))) ++ "\n")

def run_seed(buffer: Bool, +mode: String, +links: Nat, +n: Nat, +line_count: Nat, +seed: Nat) -> IO(Unit):
  match buffer:
    case True{}:
      +first = Nat.mod(seed, 1000n)
      +buf : Cl.Buffer = Cl.buf_indexed("#t", True{}, "", viewport_lines(line_count, first), Nil{}, Cl.ScrollAt{0n, 0n})
      do IO<Unit>:
        Unit <- source_info(viewport_text(first))
        Unit <- IO.print("line_count=" ++ Nat.show(line_count) ++ " width=180 height=45\n")
        measure_buffer(mode, links, n, buf, fixture_state(False{}, seed))
    case False{}:
      +text = fixture_text(links, seed)
      do IO<Unit>:
        Unit <- source_info(text)
        run_mode(String.eq(mode, "body") || String.eq(mode, "body-media"), mode, links, n, text,
          fixture_state(String.eq(mode, "ready") || String.eq(mode, "parts-ready"), seed))

def run(ok: Bool, +mode: String, +links: Nat, +n: Nat, line_count: Nat) -> IO(Unit):
  match ok:
    case False{}: IO.die(Unit, 1, "invalid profile arguments")
    case True{}:
      do IO<Unit>:
        +seed : Nat <- IO.now()
        run_seed(String.eq(mode, "whole") || String.eq(mode, "viewport"), mode, links, n, line_count, seed)

def parsed_samples(samples: Maybe<&2, Nat>, +mode: String, +links: Nat, +line_count: Nat) -> IO(Unit):
  match samples:
    case None{}: IO.die(Unit, 1, "invalid sample count")
    case Some{+n}:
      run(Nat.is_le(links, 16n) && Nat.is_gt(n, 0n) && Nat.is_le(n, 4096n)
        && Nat.is_gt(line_count, 0n) && Nat.is_le(line_count, 1024n)
        && (String.eq(mode, "lex") || String.eq(mode, "rows") || String.eq(mode, "empty") || String.eq(mode, "ready")
          || String.eq(mode, "parts-empty") || String.eq(mode, "parts-ready")
          || String.eq(mode, "body") || String.eq(mode, "body-media")
          || String.eq(mode, "whole") || String.eq(mode, "viewport")), mode, links, n, line_count)

def parsed_links(links: Maybe<&2, Nat>, mode: String, samples: String, line_count: Nat) -> IO(Unit):
  match links:
    case None{}: IO.die(Unit, 1, "invalid link count")
    case Some{n}: parsed_samples(Nat.read(samples), mode, n, line_count)

def parsed_lines(lines: Maybe<&2, Nat>, mode: String, links: String, samples: String) -> IO(Unit):
  match lines:
    case None{}: IO.die(Unit, 1, "invalid line count")
    case Some{n}: parsed_links(Nat.read(links), mode, samples, n)

def after_args(args: List<&1, String>) -> IO(Unit):
  match args:
    case Con{_, Con{mode, Con{links, Con{samples, Nil{}}}}}:
      parsed_links(Nat.read(links), mode, samples, 128n)
    case Con{_, Con{mode, Con{links, Con{samples, Con{lines, Nil{}}}}}}:
      parsed_lines(Nat.read(lines), mode, links, samples)
    case _: IO.die(Unit, 1, "usage: media_wrap_profile MODE LINKS SAMPLES [LINE_COUNT]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1, String> <- IO.args()
    after_args(args)
