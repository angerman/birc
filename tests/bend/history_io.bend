# Read past one MiB through EOF without retaining the whole file.
# Empty append path/data is typed Skip, not durable Ok.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as H
import ../../src/bend/history_io.bend as HistIO
import ../../src/bend/frame.bend as Fr
import ../../src/bend/client.bend as Feed

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

def write_many(n: Nat, f: File, +batch: String) -> IO(File):
  match n:
    case 0n: IO.pure(File, f)
    case 1n+p:
      do IO<File>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, batch)
        f : File <- wrote(pair)
        write_many(p, f, batch)

def marker_count(lines: List<&2, Cl.Line>) -> Nat:
  match lines:
    case Nil{}: 0n
    case Con{Cl.Line{kind, _, _, _, _}, t}:
      Nat.add(Bool.pick(Nat, Cl.is_reconnect(kind), 1n, 0n), marker_count(t))

def loaded_ok(+cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{_, _, Con{Cl.Buffer{_, _, _, +lines, _, _, _, _}, Nil{}}, _, _, _, _, _, _}:
      Nat.is_eq(List.length(&2, Cl.Line, lines), 4n)
        && Nat.is_eq(marker_count(lines), 1n)
        && String.ends_with(CL.buf_texts(cl, 0n), "last-2|last-1|last-é|12:00:00|")
    case _: False{}

def preserved_ok(cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{+nick, +server, _, _, +now, +settings, Cl.AuthCap{}, seq, _}:
      String.eq(nick, "configured") && String.eq(server, "a") && String.eq(now, "14:00:00")
        && Bool.not(Cl.settings_ts(settings)) && String.eq(Cl.settings_sasl_user(settings), "user")
        && Nat.is_gt(seq, 50n)
    case _: False{}

def configured() -> Cl.Client:
  +cl = Cl.client_set_sasl(Cl.init_with_cap("configured", "a", 3), "user", "pass")
  +stg = Cl.set_ts(Cl.get_settings(cl), False{})
  Cl.Client{"configured", "a", Cl.empty_buf("server", False{}) <> Nil{}, 0n, "14:00:00", stg, Cl.AuthCap{}, 50n, False{}}

def loaded_checkpoint_ok(+cl: Cl.Client) -> Bool:
  preserved_ok(cl) && String.is_empty(H.extract_new_history_for("a:6667", cl, Feed.feed(cl, "PING :x")))

def empty_ok(+cl: Cl.Client) -> Bool:
  Nat.is_eq(CL.buf_nlines(cl, 0n), 0n) && Nat.is_eq(Cl.log_seq_of(cl), 50n)

def append_is_skip(got: HistIO.Append) -> Bool:
  match got:
    case HistIO.Skip{}: True{}
    case _: False{}

def append_is_ok(got: HistIO.Append) -> Bool:
  match got:
    case HistIO.Ok{}: True{}
    case _: False{}

def append_is_err(got: HistIO.Append) -> Bool:
  match got:
    case HistIO.Err{_}: True{}
    case _: False{}

def oracle_buf(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, _, +lines, _, _, _, _}:
      name ++ "=" ++ CL.lines_pipe(lines) ++ "\n"

def oracle_bufs(bufs: List<&2, Cl.Buffer>) -> String:
  match bufs:
    case Nil{}: ""
    case Con{+b, +rest}: oracle_buf(b) ++ oracle_bufs(rest)

def oracle_sig(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _, _}:
      oracle_bufs(bufs)

def evict_chan(+ep: String, +i: Nat, +round: Nat) -> String:
  "BIRC2\t" ++ ep ++ "\t#c" ++ Nat.show(i) ++ "\tMSG\t\tu\tr" ++ Nat.show(round) ++ "-" ++ Nat.show(i) ++ "\n"

def evict_chans(n: Nat, +i: Nat, +ep: String, +round: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: evict_chan(ep, i, round) ++ evict_chans(p, 1n+i, ep, round)

def evict_rounds(n: Nat, +ep: String, +round: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: evict_chans(20n, 0n, ep, round) ++ evict_rounds(p, ep, 1n+round)

def evict_plus(n: Nat, +i: Nat, +ep: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: "BIRC2\t" ++ ep ++ "\t+#room\tMSG\t\tu\tplus" ++ Nat.show(i) ++ "\n" ++ evict_plus(p, 1n+i, ep)

def qpow(fuel: Nat, +chunk: String) -> String:
  match fuel:
    case 0n: chunk
    case 1n+p: qpow(p, chunk ++ chunk)

def qblock() -> String:
  qpow(13n, "q")

def sized_line(+ep: String, +mark: String, +n: Nat) -> String:
  +prefix = "BIRC2\t" ++ ep ++ "\t*server*\tMSG\t\ta\t" ++ mark
  prefix ++ String.take(qblock(), Nat.sub(n, String.length(prefix))) ++ "\n"

def evict_body(+ep: String) -> String:
  "server\tMSG\t\tlegacy-row\n"
    ++ "BIRC2\tother.example:6697\t*server*\tMSG\t\ta\twrong-server\n"
    ++ "BIRC2\t" ++ ep ++ "\t*server*\tDAY\t\ta\t2026-10-22\n"
    ++ "BIRC2\t" ++ ep ++ "\t*SERVER*\tMSG\t\ta\tnot-server\n"
    ++ "BIRC2\t" ++ ep ++ "\t*server*\tMSG\t\ta\thas\ttab\n"
    ++ "BIRC2\t" ++ ep ++ "\t*server*\tMSG\t\ta\tearly-server\n"
    ++ sized_line(ep, "TOO-LONG", 8193n)
    ++ evict_rounds(3n, ep, 0n)
    ++ "BIRC2\t" ++ ep ++ "\t@#c0\tMSG\t\tu\talias\n"
    ++ evict_plus(3n, 0n, ep)
    ++ "BIRC2\t" ++ ep ++ "\t#Haskell\tMSG\t\tu\tspell-a\n"
    ++ "BIRC2\t" ++ ep ++ "\t#haskell\tMSG\t\tu\tspell-b\n"
    ++ "BIRC2\tIRC.EXAMPLE:6697\t*server*\tMSG\t\ta\tfolded\n"
    ++ sized_line(ep, "BOUND-OK", 8192n)

def evict_paced(pair: H.ReadState & List<&2, U32>) -> Cl.Client:
  match pair:
    case (H.ReadState{+cl, _, _, _}, _): cl

def evict_pace(+content: String, +ep: String) -> Cl.Client:
  +bytes = Fr.string_to_octets(content)
  evict_paced(H.read_pace.step(List.length(&2, U32, bytes), bytes, H.ReadState{Cl.init_with_cap("me", "irc.example", 2), Nil{}, 0n, False{}}, ep, 2))

def evict_saved(+sig: String, +paced: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("kept lines match the byte walker", sig, oracle_sig(paced))
    Unit <- E.must("exact 8192-byte record is kept", String.contains(sig, "BOUND-OK"))
    Unit <- E.must("overlong record is dropped", Bool.not(String.contains(sig, "TOO-LONG")))
    E.must("older server row falls out of the cap", Bool.not(String.contains(sig, "early-server")))

def evict_check(+ep: String) -> IO(Unit):
  +content = evict_body(ep)
  +paced = evict_pace(content, ep)
  do IO<Unit>:
    f : File <- IO.try(File, File.open("build/history_io.evict", "w"))
    pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, content)
    f : File <- wrote(pair)
    Unit <- File.close(f)
    snap : Cl.Client <- HistIO.history_snapshot_client("build/history_io.evict", ep, 2, Cl.init_with_cap("me", "irc.example", 2))
    evict_saved(oracle_sig(snap), paced)

def main() -> IO(Unit):
  +path: String = "build/history_io.fixture"
  +old = "BIRC2\ta:6667\t*server*\tMSG\t\ta\t" ++ repeat(300n, "x") ++ "\n"
  +end = "server\tMSG\t\tambiguous-legacy\n"
    ++ "BIRC2\tb:6667\tprivate\tMSG\t\ta\tother-server\n"
    ++ "BIRC2\ta:6667\t*server*\tMSG\t\ta\tlast-2\n"
    ++ "BIRC2\ta:6667\t*server*\tMSG\t\ta\tlast-1\n"
    ++ "BIRC2\ta:6667\t*server*\tMSG\t\ta\tlast-é\n"
    ++ repeat(9000n, "z") ++ "\n"
    ++ "BIRC2\ta:6667\t*server*\tMSG\t\ta\tunterminated"
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    f : File <- write_many(20n, f, repeat(200n, old))
    pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, end)
    f : File <- wrote(pair)
    Unit <- File.close(f)
    cl : Cl.Client <- HistIO.history_init_client(path, "a:6667", 3, "me", "a", "12:00:00")
    Unit <- E.must("latest_after_one_mib", loaded_ok(cl))
    missing : Cl.Client <- HistIO.history_init_client("build/history_io.absent", "a:6667", 3, "me", "a", "12:00:00")
    Unit <- E.must("missing_file", Nat.is_eq(CL.buf_nlines(missing, 0n), 0n))
    loaded : Cl.Client <- HistIO.history_load_client(path, "a:6667", 3, configured())
    Unit <- E.must("load_preserves_configuration_and_checkpoint", loaded_checkpoint_ok(loaded))
    empty_file : File <- IO.try(File, File.open("build/history_io.empty", "w"))
    Unit <- File.close(empty_file)
    empty : Cl.Client <- HistIO.history_load_client("build/history_io.empty", "a:6667", 3, configured())
    Unit <- evict_check("irc.example:6697")
    Unit <- E.must("empty_file", empty_ok(empty))
    skip_empty : HistIO.Append <- HistIO.history_append_file.typed(path, "")
    Unit <- E.must("empty_data_is_skip", append_is_skip(skip_empty))
    skip_path : HistIO.Append <- HistIO.history_append_file.typed("", "fixture\n")
    Unit <- E.must("empty_path_is_skip", append_is_skip(skip_path))
    notice_skip : Maybe<&2, String> <- HistIO.history_append_file(path, "")
    Unit <- E.must("skip_notice_collapses", Maybe.is_none(&2, String, notice_skip))
    # Durable claims must not treat empty path + nonempty data as Skip success.
    claim_path : HistIO.Append <- HistIO.history_append_file.claim("", "fixture\n")
    Unit <- E.must("claim_empty_path_is_err", append_is_err(claim_path))
    claim_empty : HistIO.Append <- HistIO.history_append_file.claim(path, "")
    Unit <- E.must("claim_empty_data_is_skip", append_is_skip(claim_empty))
    wrote : HistIO.Append <- HistIO.history_append_file.typed("build/history_io.append", "append-ok\n")
    Unit <- E.must("nonempty_append_is_ok", append_is_ok(wrote))
    IO.print("history_io=ok")
