# Replay a bounded file snapshot through the live byte framer. Reads are small;
# UTF-8 and CRLF may cross chunks, and an unterminated final record is retained.
import Base
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./frame.bend as Fr
import ./irc.bend as Irc
import ./clock.bend as Clock

type ReadState is Data:
  ReadState{cl: Cl.Client, rem: List<&2, U32>, drop: Bool}

def die(+path: String, +msg: String) -> IO(Cl.Client):
  IO.die(Cl.Client, 1, "birc: cannot read replay " ++ path ++ ": " ++ msg)

def fail(f: File, +path: String, +msg: String) -> IO(Cl.Client):
  do IO<Cl.Client>:
    Unit <- File.close(f)
    die(path, msg)

def fail_error(f: File, +path: String, error: U32 & String) -> IO(Cl.Client):
  match error:
    case (_, +msg): fail(f, path, msg)

def chunk.got(cl: Cl.Client, got: List<&2, String> & List<&2, U32> & Bool) -> ReadState:
  match got:
    case (lines, rem, drop): ReadState{Feed.feed_all(cl, lines), rem, drop}

def chunk(state: ReadState, bytes: List<&2, U32>) -> ReadState:
  match state:
    case ReadState{cl, drop_rem, dropping}:
      chunk.got(cl, Fr.push_ex(dropping, drop_rem, bytes))

def finish_client(drop: Bool, cl: Cl.Client, rem: List<&2, U32>) -> Cl.Client:
  match drop:
    case True{}: cl
    case False{}: Feed.feed_all(cl, Cl.replay_lines(Irc.sanitize_keep_style(Fr.line_from_octets(rem))))

def finish(f: File, state: ReadState) -> IO(Cl.Client):
  match state:
    case ReadState{cl, rem, drop}:
      do IO<Cl.Client>:
        Unit <- File.close(f)
        return finish_client(drop, cl, rem)

# Same yield as history reads: the replay framer stays on the event
# thread, so a 4096-byte push would stall every other fiber. Slice,
# park, then continue. The framer already keeps a cross-chunk remainder.
def read_pace.step(fuel: Nat, +bytes: List<&2, U32>, state: ReadState) -> ReadState & List<&2, U32>:
  match fuel:
    case 0n: (state, bytes)
    case 1n+p:
      match bytes:
        case Nil{}: (state, Nil{})
        case Con{+byte, +t}: read_pace.step(p, t, chunk(state, byte <> Nil{}))

def read_pace.unpack(pair: ReadState & List<&2, U32>, k: List<&2, U32> -> ReadState -> IO(Cl.Client)) -> IO(Cl.Client):
  match pair:
    case (state, +bytes): k(bytes, state)

def read_pace.more(fuel: Nat, +bytes: List<&2, U32>, +drop: Nat, f: File, +path: String, state: ReadState, +remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match fuel:
    case 0n: next(f, state, Nat.sub(remaining, drop))
    case 1n+p:
      match bytes:
        case Nil{}: next(f, state, Nat.sub(remaining, drop))
        case Con{+byte, +t}:
          do IO<Cl.Client>:
            Unit <- IO.sleep(0)
            read_pace.unpack(read_pace.step(256n, byte <> t, state), bs => st => read_pace.more(p, bs, drop, f, path, st, remaining, next))

def read_pace.launch(pair: ReadState & List<&2, U32>, +drop: Nat, f: File, +path: String, +remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match pair:
    case (state, +left): read_pace.more(List.length(&2, U32, left), left, drop, f, path, state, remaining, next)

def read_pace.begin(+bytes: List<&2, U32>, +drop: Nat, f: File, +path: String, state: ReadState, +remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  read_pace.launch(read_pace.step(256n, bytes, state), drop, f, path, remaining, next)

def read_loop.bytes(empty: Bool, f: File, +path: String, state: ReadState, +bytes: List<&2, U32>, +remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match empty:
    case True{}: fail(f, path, "unexpected end of file")
    case False{}: read_pace.begin(bytes, List.length(&2, U32, bytes), f, path, state, remaining, next)

def read_loop.got(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>, +path: String, state: ReadState, remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match pair:
    case (f, Fail{error}): fail_error(f, path, error)
    case (f, Done{+bytes}): read_loop.bytes(Nat.is_eq(List.length(&2, U32, bytes), 0n), f, path, state, bytes, remaining, next)

def read_loop.read(done: Bool, f: File, +path: String, state: ReadState, +remaining: Nat, next: File -> ReadState -> Nat -> IO(Cl.Client)) -> IO(Cl.Client):
  match done:
    case True{}: finish(f, state)
    case False{}:
      do IO<Cl.Client>:
        pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, U32.from_nat(Cl.clamp_nat(remaining, 4096n)))
        read_loop.got(pair, path, state, remaining, next)

# The initial size bounds total work even if another process keeps appending.
# Positive short reads consume the snapshot; early EOF fails instead of painting
# a partial replay. File.size itself fails for a file larger than U32 can hold.
def read_loop(fuel: Nat, f: File, +path: String, state: ReadState, +remaining: Nat) -> IO(Cl.Client):
  match fuel:
    case 0n: fail(f, path, "read budget exhausted")
    case 1n+p:
      read_loop.read(Nat.is_eq(remaining, 0n), f, path, state, remaining,
        f2 => st2 => rest => read_loop(p, f2, path, st2, rest))

def sized(pair: File & Result<&1, &1, U32 & String, U32>, +path: String, cl: Cl.Client) -> IO(Cl.Client):
  match pair:
    case (f, Fail{error}): fail_error(f, path, error)
    case (f, Done{+size}): read_loop(1n+U32.to_nat(size), f, path, ReadState{cl, Nil{}, False{}}, U32.to_nat(size))

def opened(+path: String, +nick: String, +server: String, result: Result<&1, &1, U32 & String, File>) -> IO(Cl.Client):
  match result:
    case Fail{(_, +msg)}: die(path, msg)
    case Done{f}:
      do IO<Cl.Client>:
        ts : String <- Clock.hhmmss()
        pair : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
        sized(pair, path, Cl.set_now(Cl.init(nick, server), ts))

def load(+path: String, +nick: String, +server: String) -> IO(Cl.Client):
  do IO<Cl.Client>:
    result : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    opened(path, nick, server, result)
