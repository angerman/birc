# Per-buffer drafts and multiline composition goldens.
# Positive controls keep working; negative controls reject atomically.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as S
import ../../src/bend/drafts.bend as D

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def base() -> Cl.Client:
  client(S.submit(Cl.init("me", "irc.example"), "/join #room"))

def bodies.one(parsed: Maybe<&2, Irc.Message>) -> String:
  match parsed:
    case None{}: "[invalid]"
    case Some{m}: Irc.msg_param(m, 1n)

def bodies(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: bodies.one(Irc.parse(h)) ++ bodies(t)

def wire_ok(+xs: List<&2, String>, +want: String, n: Nat) -> Bool:
  S.out_all_ok(xs) && String.eq(bodies(xs), want) && Nat.is_eq(List.length(&2, String, xs), n)

def echoes(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{wire, rest}: "<me> " ++ bodies.one(Irc.parse(wire)) ++ "|" ++ echoes(rest)

def repeat(n: Nat, +s: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: s ++ repeat(p, s)

def line_block(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "a\n" ++ line_block(p)

def fill(n: Nat, +ds: D.Drafts) -> D.Drafts:
  match n:
    case 0n: ds
    case 1n+p: fill(p, D.set(ds, "b" ++ Irc.stars.go(D.count(ds)), "x"))

def single_line(+r: D.Route) -> String:
  match r:
    case D.RouteEmpty{}: ""
    case D.RouteSingle{+line}: line
    case D.RouteMulti{_}: ""

def multi_count(+r: D.Route) -> Nat:
  match r:
    case D.RouteEmpty{}: 0n
    case D.RouteSingle{_}: 1n
    case D.RouteMulti{+lines}: List.length(&2, String, lines)

def all_notice.go(+xs: List<&2, String>, ok: Bool) -> Bool:
  match xs:
    case Nil{}:
      ok
    case Con{+h, t}:
      match ok:
        case False{}:
          False{}
        case True{}:
          all_notice.go(t, String.starts_with(h, "NOTICE "))

def all_notice(+xs: List<&2, String>) -> Bool:
  all_notice.go(xs, True{})

def plan_wires_ok(+wires: Maybe<&2, List<&2, String>>, +want: String, +n: Nat) -> Bool:
  match wires:
    case None{}: False{}
    case Some{+xs}: wire_ok(xs, want, n)

def plan_none(+wires: Maybe<&2, List<&2, String>>) -> Bool:
  match wires:
    case None{}: True{}
    case Some{_}: False{}

def plan_concat(+wires: Maybe<&2, List<&2, String>>) -> String:
  match wires:
    case None{}: "[none]"
    case Some{+xs}: String.concat(xs)

def boundary_body(+target: String, notice: Bool) -> String:
  Irc.stars.go(Nat.sub(Irc.LINE_MAX(), Irc.utf8_len(S.message_wire(target, "", notice))))
    ++ "IDENTIFY opaque-secret"

def submit_lines_ok(pair: Cl.Client & List<&2, String>, +want: String, +n: Nat) -> Bool:
  match pair:
    case (+cl, +outs):
      S.out_all_ok(outs) && String.eq(bodies(outs), want) && Nat.is_eq(List.length(&2, String, outs), n)
        && Nat.is_eq(CL.buf_nlines(cl, 1n), n) && String.eq(CL.buf_texts(cl, 1n), echoes(outs))

def submit_empty_ok(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (+cl, +outs):
      List.is_empty(&2, String, outs) && Nat.is_eq(CL.buf_nlines(cl, 1n), 0n)

def reason_ok(pair: Cl.Client & List<&2, String>, +needle: String) -> Bool:
  match pair:
    case (+cl, +outs):
      List.is_empty(&2, String, outs) && String.contains(CL.buf_texts(cl, 1n), needle)

def focus_loaded(pair: D.Drafts & String) -> String:
  match pair:
    case (_, +loaded): loaded

def focus_stored(pair: D.Drafts & String, +name: String) -> String:
  match pair:
    case (+ds, _): D.get(ds, name)

def focus_store(pair: D.Drafts & String) -> D.Drafts:
  match pair:
    case (+ds, _): ds

def plan_each_or_empty(+wires: Maybe<&2, List<&2, String>>) -> List<&2, String>:
  match wires:
    case None{}: Nil{}
    case Some{+xs}: xs

def main() -> IO(Unit):
  +cl = base()
  +accent = "e" ++ SCon{Chr{769}, ""}
  +oversized_cluster = "e" ++ repeat(260n, SCon{Chr{769}, ""})
  +boundary = boundary_body("NickServ", False{})
  +ordinary_boundary = boundary_body("alice", False{})
  +full = fill(16n, D.empty())
  +soh = "a" ++ SCon{Chr{1}, "b"}
  +kanji: String = "漢"
  do IO<Unit>:
    Unit <- E.must_eq("set then get roundtrips", D.get(D.set(D.empty(), "#room", "hi"), "#room"), "hi")
    Unit <- E.must_eq("missing draft is empty", D.get(D.empty(), "#room"), "")
    Unit <- E.must_eq("overwrite replaces text", D.get(D.set(D.set(D.empty(), "#room", "old"), "#room", "new"), "#room"), "new")
    Unit <- E.must("empty text clears entry", Bool.not(D.has(D.set(D.set(D.empty(), "#room", "old"), "#room", ""), "#room")))
    Unit <- E.must("clear removes entry", Bool.not(D.has(D.clear(D.set(D.empty(), "#room", "hi"), "#room"), "#room")))
    Unit <- E.must("drop removes entry on close", Bool.not(D.has(D.drop(D.set(D.empty(), "#room", "hi"), "#room"), "#room")))
    Unit <- E.must_eq("rename moves text", D.get(D.rename(D.set(D.empty(), "alice", "hi"), "alice", "bob"), "bob"), "hi")
    Unit <- E.must("rename clears old name", Bool.not(D.has(D.rename(D.set(D.empty(), "alice", "hi"), "alice", "bob"), "alice")))
    Unit <- E.must_eq("case-only rename keeps text", D.get(D.rename(D.set(D.empty(), "alice", "hi"), "alice", "Alice"), "Alice"), "hi")
    Unit <- E.must("case-only rename keeps one entry", Nat.is_eq(D.count(D.rename(D.set(D.empty(), "alice", "hi"), "alice", "Alice")), 1n))
    Unit <- E.must_eq("rename collision keeps target draft", D.get(D.rename(D.set(D.set(D.empty(), "alice", "A"), "bob", "B"), "alice", "bob"), "bob"), "B")
    Unit <- E.must("rename without draft is a no-op", Nat.is_eq(D.count(D.rename(D.empty(), "alice", "bob")), 0n))
    Unit <- E.must_eq("rejected rename keeps old draft", D.get(D.rename(D.set(D.empty(), "alice", "hi"), "alice", "*log*"), "alice"), "hi")
    Unit <- E.must("retain keeps resident drafts", D.has(D.retain(D.set(D.set(D.empty(), "#room", "a"), "#gone", "b"), cl), "#room"))
    Unit <- E.must("retain prunes departed buffers", Bool.not(D.has(D.retain(D.set(D.set(D.empty(), "#room", "a"), "#gone", "b"), cl), "#gone")))
    Unit <- E.must("retain keeps server draft", D.has(D.retain(D.set(D.empty(), "server", "x"), cl), "server"))
    Unit <- E.must_eq("focus stashes current text", focus_stored(D.focus(D.set(D.empty(), "#a", "aa"), "#a", "aa2", "#b"), "#a"), "aa2")
    Unit <- E.must_eq("focus loads empty next", focus_loaded(D.focus(D.set(D.empty(), "#a", "aa"), "#a", "aa2", "#b")), "")
    Unit <- E.must_eq("focus loads stored next", focus_loaded(D.focus(D.set(D.set(D.empty(), "#a", "aa"), "#b", "bb"), "#a", "aa2", "#b")), "bb")
    Unit <- E.must("focus with empty current clears stash", Bool.not(D.has(focus_store(D.focus(D.set(D.empty(), "#a", "aa"), "#a", "", "#b")), "#a")))
    Unit <- E.must_eq("over-byte draft rejected, old kept", D.get(D.set(D.set(D.empty(), "#room", "old"), "#room", Irc.stars.go(4097n)), "#room"), "old")
    Unit <- E.must("4096-byte draft admitted", D.has(D.set(D.empty(), "#room", Irc.stars.go(4096n)), "#room"))
    Unit <- E.must("utf8 bytes counted, 4098 rejected", Bool.not(D.has(D.set(D.empty(), "#room", repeat(1366n, kanji)), "#room")))
    Unit <- E.must("utf8 bytes counted, 4095 admitted", D.has(D.set(D.empty(), "#room", repeat(1365n, kanji)), "#room"))
    Unit <- E.must("33-line draft rejected", Bool.not(D.has(D.set(D.empty(), "#room", line_block(33n)), "#room")))
    Unit <- E.must("32-line draft admitted", D.has(D.set(D.empty(), "#room", line_block(32n)), "#room"))
    Unit <- E.must("store holds sixteen entries", Nat.is_eq(D.count(full), 16n))
    Unit <- E.must("seventeenth draft rejected", Bool.not(D.has(D.set(full, "zz", "y"), "zz")))
    Unit <- E.must_eq("update at capacity admitted", D.get(D.set(full, "bx", "y2"), "bx"), "y2")
    Unit <- E.must_eq("crlf splits lines", String.join(D.split_lines("a\r\nb"), "|"), "a|b")
    Unit <- E.must_eq("lone cr splits", String.join(D.split_lines("a\rb"), "|"), "a|b")
    Unit <- E.must_eq("mixed separators split", String.join(D.split_lines("a\r\nb\rc\nd"), "|"), "a|b|c|d")
    Unit <- E.must_eq("trailing newline collapses", String.join(D.split_lines("a\n"), "|"), "a")
    Unit <- E.must_eq("soh is preserved, not a separator", String.join(D.split_lines(soh), "|"), soh)
    Unit <- E.must_eq("kanji survives split", String.join(D.split_lines(repeat(3n, kanji) ++ "\nbye"), "|"), repeat(3n, kanji) ++ "|bye")
    Unit <- E.must_eq("empty routes empty", single_line(D.route("")), "")
    Unit <- E.must_eq("single routes verbatim", single_line(D.route("hi")), "hi")
    Unit <- E.must_eq("trailing newline is single", single_line(D.route("hi\n")), "hi")
    Unit <- E.must("two lines route multi", Nat.is_eq(multi_count(D.route("a\nb")), 2n))
    Unit <- E.must("two-line plan emits ordered wires", plan_wires_ok(D.plan(cl, "#room", "hi\nyo", False{}), "hiyo", 2n))
    Unit <- E.must("plan splits long lines losslessly", plan_wires_ok(D.plan(cl, "#room", Irc.stars.go(1000n) ++ "\nend", False{}), Irc.stars.go(1000n) ++ "end", 4n))
    Unit <- E.must("combining cluster stays whole in plan", plan_wires_ok(D.plan(cl, "#room", Irc.stars.go(494n) ++ accent, False{}), Irc.stars.go(494n) ++ accent, 2n))
    Unit <- E.must("notice plan uses NOTICE", all_notice(plan_each_or_empty(D.plan(cl, "#room", "a\nb", True{}))))
    Unit <- E.must_eq("single-line plan matches submit wires", plan_concat(D.plan(cl, "#room", "hello", False{})), String.concat(Pair.snd(Cl.Client, List<&2, String>, S.submit(cl, "hello"))))
    Unit <- E.must("empty plan is none", plan_none(D.plan(cl, "#room", "", False{})))
    Unit <- E.must("command first line rejected", plan_none(D.plan(cl, "#room", "/join #x\nhi", False{})))
    Unit <- E.must("command middle line rejected", plan_none(D.plan(cl, "#room", "hi\n/me x\nbye", False{})))
    Unit <- E.must("command last line rejected", plan_none(D.plan(cl, "#room", "hi\n/quit", False{})))
    Unit <- E.must("oversized cluster rejects whole plan", plan_none(D.plan(cl, "#room", "ok\n" ++ oversized_cluster, False{})))
    Unit <- E.must("credential split-overflow rejects all", plan_none(D.plan(cl, "NickServ", boundary, False{})))
    Unit <- E.must("ordinary later IDENTIFY chunk still sends", plan_wires_ok(D.plan(cl, "alice", ordinary_boundary, False{}), ordinary_boundary, 2n))
    Unit <- E.must("submit emits ordered echoes", submit_lines_ok(D.submit_lines(cl, 1n, "#room", "aa\nbb", False{}), "aabb", 2n))
    Unit <- E.must("submit empty is a no-op", submit_empty_ok(D.submit_lines(cl, 1n, "#room", "", False{})))
    Unit <- E.must("submit command multiline echoes reason", reason_ok(D.submit_lines(cl, 1n, "#room", "hi\n/quit", False{}), "multiline commands are not sent"))
    Unit <- E.must("submit oversize echoes cluster reason", reason_ok(D.submit_lines(cl, 1n, "#room", oversized_cluster, False{}), "message cluster exceeds IRC line limit"))
    Unit <- E.must("submit credential overflow echoes credential reason", reason_ok(D.submit_lines(cl, 1n, "NickServ", boundary, False{}), "credential command exceeds IRC line limit"))
    Unit <- E.must("after submit clears draft", Bool.not(D.has(D.after_submit(D.set(D.empty(), "#room", "hi"), "#room"), "#room")))
    Unit <- E.must_eq("modal stash preserves typed text", D.get(D.stash_modal(D.empty(), "#room", "a\nb"), "#room"), "a\nb")
    IO.print("drafts_demo=ok")
