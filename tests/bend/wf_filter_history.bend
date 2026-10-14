# History presence tags: PRS/NCK round-trip; pre-changeover SYS stays System.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/history.bend as H
import ../../src/bend/view.bend as V

def kind_of(entry: Maybe<&2, H.HistEntry>) -> String:
  match entry:
    case None{}: "none"
    case Some{H.Entry{_, Cl.Line{+kind, _, _, _, _}}}: H.serialize_kind(kind)
    case Some{H.ServerEntry{Cl.Line{+kind, _, _, _, _}}}: H.serialize_kind(kind)

def text_of(entry: Maybe<&2, H.HistEntry>) -> String:
  match entry:
    case None{}: "none"
    case Some{H.Entry{_, Cl.Line{_, _, +text, _, _}}}: text
    case Some{H.ServerEntry{Cl.Line{_, _, +text, _, _}}}: text

def main() -> IO(Unit):
  +prs = Cl.Line{Cl.Presence{}, "12:00:00", "-> a joined #t", "a", 1n}
  +nck = Cl.Line{Cl.Nick{}, "12:00:01", "a is now known as b", "a", 2n}
  +legacy_sys = Cl.Line{Cl.System{}, "12:00:02", "-> a joined #t", "", 3n}
  do IO<Unit>:
    Unit <- E.must_eq("presence serializes to PRS", H.serialize_kind(Cl.Presence{}), "PRS")
    Unit <- E.must_eq("nick serializes to NCK", H.serialize_kind(Cl.Nick{}), "NCK")
    Unit <- E.must_eq("PRS parses back to presence", H.serialize_kind(H.parse_kind("PRS")), "PRS")
    Unit <- E.must_eq("NCK parses back to nick", H.serialize_kind(H.parse_kind("NCK")), "NCK")
    Unit <- E.must("PRS is a valid persisted kind", H.valid_kind("PRS"))
    Unit <- E.must("NCK is a valid persisted kind", H.valid_kind("NCK"))
    Unit <- E.must("unknown tag stays invalid", Bool.not(H.valid_kind("WRONG")))
    Unit <- E.must_eq("presence line persists with PRS tag",
      H.serialize_line_for("a:6667", "#t", prs), "BIRC2\ta:6667\t#t\tPRS\t12:00:00\ta\t-> a joined #t\n")
    Unit <- E.must_eq("nick line persists with NCK tag",
      H.serialize_line_for("a:6667", "#t", nck), "BIRC2\ta:6667\t#t\tNCK\t12:00:01\ta\ta is now known as b\n")
    Unit <- E.must_eq("PRS record restores presence kind",
      kind_of(H.parse_line_for("a:6667", "BIRC2\ta:6667\t#t\tPRS\t12:00:00\ta\t-> a joined #t")), "PRS")
    Unit <- E.must_eq("PRS record restores text",
      text_of(H.parse_line_for("a:6667", "BIRC2\ta:6667\t#t\tPRS\t12:00:00\ta\t-> a joined #t")), "-> a joined #t")
    Unit <- E.must_eq("NCK record restores nick kind",
      kind_of(H.parse_line_for("a:6667", "BIRC2\ta:6667\t#t\tNCK\t12:00:01\ta\ta is now known as b")), "NCK")
    Unit <- E.must_eq("pre-changeover SYS join stays system",
      kind_of(H.parse_line_for("a:6667", "BIRC2\ta:6667\t#t\tSYS\t12:00:02\t\t-> a joined #t")), "SYS")
    Unit <- E.must_eq("pre-changeover SYS join stays visible when hidden",
      Nat.show(List.length(&2, Cl.Line, V.body_of.lines([legacy_sys], Nil{}, False{}, False{}, "#t", "s"))), "1")
    Unit <- E.must_eq("restored presence hides on toggle",
      Nat.show(List.length(&2, Cl.Line, V.body_of.lines([prs], Nil{}, False{}, True{}, "#t", "s"))), "0")
    Unit <- E.must_eq("restored nick hides on toggle",
      Nat.show(List.length(&2, Cl.Line, V.body_of.lines([nck], Nil{}, True{}, False{}, "#t", "s"))), "0")
    IO.print("wf_filter_history=ok")
