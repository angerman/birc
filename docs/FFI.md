# Bend ↔ TimUI / native FFI (M0.2–M0.4)

Pinned Bend: see `flake.lock` (`bend-src`). Foreign effects follow bendano
TOOLCHAIN conventions and upstream `bend2/effs/*.c`.

## Shape

```bend
law Timui.hello:
  U32 -> IO(Unit)

def Timui.hello(max_frames):
  import "./timui_hello.c"
```

- Body is **only** `import "….c"` (optional `.js` twin if JS backend needed).
- Must return base `IO(...)`.
- C registers with `io_eff(CID_<NAME>, run, flags)` from a constructor.
- `Timui.hello` → `CID_TIMUI_HELLO` (`name_clean` then uppercased).

## Terms

| Bend | Native |
|---|---|
| `U32` / `Nat` (≤ 2^48−1) | low bits of raw `Term` word |
| `Unit` | `term_pak(CID_UNIT, 0)` |
| `String` | `io_cstr` / `io_str` (UTF-8) |
| `List<&2, U32>` octets | walk `CID_CON` / build with `io_node` (see bendano `bytes_roundtrip.c`) |
| Handle (`Ui`, `Socket`, …) | `io_hand(ptr)` / `io_hand_v(term)` — **never** store pointers in `U32`/`Nat` |
| `Result` | `io_done` / `io_fail` |
| Pair | `io_tup` |

## Build

`bend x.bend -o bin` compiles from a **temp** `.c` with
`clang -std=c11 -O3 … -lpthread -lm` and **no** `-I`.

For TimUI includes, emit C then link ourselves:

```sh
bend tests/ffi/timui_hello.bend -o build/timui_hello.c
$CC -std=c11 -O2 -pthread -Isrc/ui build/timui_hello.c -o build/timui_hello
```

`TIMUI_IMPLEMENTATION` is defined in exactly one FFI translation unit
(inlined into the emitted program).

## Target TimUI API (M0.4 — locked)

Coarse draw first (D1). Types below are Bend-side; TimUI structs stay in C.

```text
law Ui: Type
law Frame: Type

Timui.open  : Config -> IO(Result<&1,&1, U32 & String, Ui>)
Timui.begin : Ui -> IO(Result<&1,&1, U32 & String, Frame & List<&2, UiEvent>>)
Timui.draw  : Frame -> ViewModel -> IO(Frame)
Timui.end   : Frame -> IO(Ui)
Timui.close : Ui -> IO(Unit)
Timui.post  : Ui -> NetEvent -> IO(Unit)   # net → UI (model B)
```

### Pure domain types (M0.3 — no TimUI leakage)

```text
Client, Buffer, Line, LineKind
NetEvent, UiEvent, Outbound, ViewModel
Config   # nick, host, port, channel, demo, max_frames
```

`ViewModel` is what `Timui.draw` consumes (tabs, scrollback rows, nicks, header, composer).

## M8 packing (D6)

Bend owns `BodyLine{kind, ts, spans}`, `TextSpan` (Plain/Bold/Italic/Code/Link),
`Tab{name, on}`. Live paint still joins spans to a `String` shim until the
FFI walks that Data. When it does:

- `kind` is `kind_code : LineKind -> U32` (`0=Msg` … `5=Error`), not a C enum.
- Body wire (one line per `BodyLine`): `k|ts|spans` with span units
  `P`/`B`/`I`/`C` text or `L` `url` `\x1d` `text`, units separated by `\x1f`.
- C interprets that packing inside one `Timui.frame`. C does not tokenize.

## Decisions

| ID | Choice |
|---|---|
| D1 | Coarse paint inside one `Timui.frame` (Bend owns iteration) |
| D2 | `IO.spawn` net actor + `Chan` Data events; UI paints then `Chan.recv` |
| D3 | Base `TCP.send` / `TCP.recv` strings; octet `Fr.push` remains for laws |
| D4 | `--frames` fuel + `ui_loop_trust` |
| D5 | C demo deleted; Bend `build/birc` only |

## Spike (M0.5)

`Timui.hello(max_frames)` opens TimUI, draws one label each frame, quits on
Escape or after `max_frames` (>0). Used by `make ffi-smoke`.

## App UI (M5/M6)

Thin FFI (Bend owns the loop):

```text
Timui.open     : IO(Result<&1,&1, U32 & String, Ui>)  # IO.try at call sites
Timui.frame    : Ui -> String×6 -> IO(Ui)   # one begin/draw/end
Timui.did_quit : IO(Bool)
Timui.keys     : IO(Bool & Bool & Bool & String & U32)  # quit, enter, bs, typed, rows
Timui.close    : Ui -> IO(Unit)
App.budget     : IO(U32)   # from --frames / birc_max_frames
```

`app.bend` / `net.bend` fuel-loop calling `Timui.frame`. Build:
`bend src/bend/app.bend -o build/birc_bend.c`, rename `main`→`bend_main`,
link with `birc_main.c` (`-Isrc/ui -Isrc/ffi -pthread`).
