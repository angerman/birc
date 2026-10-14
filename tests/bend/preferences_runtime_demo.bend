# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/preferences.bend as P
import ../../src/bend/preferences_runtime.bend as R
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/theme.bend as Theme

def base() -> P.Preferences:
  P.capture(Cl.init("me", "irc.example"), True{}, "#initial" <> Nil{})

def stored() -> P.Preferences:
  P.Preferences{False{}, False{}, False{}, False{}, 200, False{}, False{}, False{}, "muted" <> Nil{}, "#saved" <> Nil{}, True{}, Theme.Dark{}, True{}}

def settings_edited() -> P.Preferences:
  P.Preferences{False{}, True{}, True{}, True{}, 100, False{}, True{}, True{}, Nil{}, "#initial" <> Nil{}, True{}, Theme.Dark{}, True{}}

def loaded_ok(result: R.Completion) -> Bool:
  match result:
    case R.Completion{_, Some{prefs}, seed, resume}:
      String.eq(P.show(prefs), P.show(stored())) && seed && resume
    case _: False{}

def edit_wins(result: R.Completion) -> Bool:
  match result:
    case R.Completion{_, Some{P.Preferences{joins, ts, _, _, _, _, _, _, _, channels, _, _, _}}, seed, resume}:
      Bool.not(joins) && Bool.not(ts) && Bool.not(seed) && resume && String.eq(P.records_text(channels, "channel"), "channel\t#initial\n")
    case _: False{}

def ts_on(result: R.Completion) -> Bool:
  match result:
    case R.Completion{_, Some{P.Preferences{_, ts, _, _, _, _, _, _, _, _, _, _, _}}, _, _}: ts
    case _: False{}

def read_ticket(job: Maybe<&2, R.Job>) -> Nat:
  match job:
    case Some{R.Read{ticket, _, _, _, _}}: ticket
    case _: 0n

def stale(result: R.Completion) -> Bool:
  match result:
    case R.Completion{_, None{}, seed, resume}: Bool.not(seed) && Bool.not(resume)
    case _: False{}

def deferred_job(pair: R.State & Maybe<&2, R.Job>) -> Bool:
  match pair:
    case (_, Some{R.Write{_, host, port, P.Preferences{joins, ts, _, _, _, _, _, _, _, channels, _, _, _}}}):
      String.eq(host, "irc.example") && U32.is_eq(port, 6697) && Bool.not(joins) && Bool.not(ts)
        && String.eq(P.records_text(channels, "channel"), "channel\t#initial\n")
    case _: False{}

def deferred(result: R.Completion) -> Bool:
  match result:
    case R.Completion{next, _, _, _}: deferred_job(R.take(next))

def queued_a(pair: R.State & Maybe<&2, R.Job>) -> Bool:
  match pair:
    case (_, Some{R.Write{_, host, _, _}}): String.eq(host, "irc.example")
    case _: False{}

def after_loaded(result: R.Completion) -> Bool:
  match result:
    case R.Completion{next, _, _, _}:
      queued_a(R.take(R.observe(R.observe(next, "irc.example", 6697, settings_edited(), 1n), "other.example", 6697, base(), 1n)))

def start.pair(pair: R.State & Maybe<&2, R.Job>) -> R.State:
  match pair:
    case (state, _): state

def start() -> R.State:
  start.pair(R.take(R.initial(True{}, "irc.example", 6697, base(), 0n, False{}, False{}, False{})))

def named(name: String) -> P.Preferences:
  P.capture(Cl.init("me", "irc.example"), True{}, name <> Nil{})

def rapid() -> R.State:
  R.observe(R.observe(R.observe(R.observe(R.observe(start(), "irc.example", 6697, named("#a-edit"), 1n),
    "b.example", 6697, named("#b"), 1n), "b.example", 6697, named("#b-edit"), 2n),
    "c.example", 6697, named("#c"), 2n), "c.example", 6697, named("#c-edit"), 3n)

def drain.result(result: R.Completion) -> R.State:
  match result:
    case R.Completion{next, _, _, _}: next

def writes.pair(pair: R.State & Maybe<&2, R.Job>, k: R.State -> String) -> String:
  match pair:
    case (_, None{}): ""
    case (state, Some{R.Read{ticket, _, _, _, _}}): k(drain.result(R.loaded(state, ticket, None{}, 0)))
    case (state, Some{R.Write{ticket, host, _, prefs}}):
      host ++ ":" ++ P.records_text(P.channels(prefs), "channel") ++ k(R.saved(state, ticket))

def writes(fuel: Nat, state: R.State) -> String:
  match fuel:
    case 0n: "limit"
    case 1n+p: writes.pair(R.take(state), next => writes(p, next))

def rapid_writes(code: U32) -> String:
  writes(12n, drain.result(R.loaded(rapid(), 1n, None{}, code)))

def active_write() -> R.State:
  start.pair(R.take(R.observe(drain.result(R.loaded(start(), 1n, Some{stored()}, 0)), "irc.example", 6697, named("#old"), 1n)))

def active_write_switch() -> R.State:
  R.observe(R.observe(R.observe(R.observe(active_write(), "irc.example", 6697, named("#latest"), 2n),
    "b.example", 6697, named("#b"), 2n), "b.example", 6697, named("#b-edit"), 3n), "c.example", 6697, named("#c"), 3n)

def returning_text(got: Maybe<&2, List<&2, String>>) -> String:
  match got:
    case None{}: "absent"
    case Some{names}: P.records_text(names, "channel")

def return_after_write() -> R.State:
  R.observe(R.observe(active_write_switch(), "irc.example", 6697, named("#latest"), 3n), "irc.example", 6697, named("#after-return"), 4n)

def ts_off(name: String) -> P.Preferences:
  P.Preferences{True{}, False{}, True{}, True{}, 100, False{}, True{}, True{}, Nil{}, name <> Nil{}, True{}, Theme.Dark{}, True{}}

def global_edit() -> R.State:
  R.observe(R.observe(R.observe(R.observe(start(), "irc.example", 6697, named("#a-edit"), 1n),
    "b.example", 6697, named("#b"), 1n), "b.example", 6697, ts_off("#b-edit"), 2n), "c.example", 6697, ts_off("#c"), 2n)

def first_write_ts(pair: R.State & Maybe<&2, R.Job>) -> Bool:
  match pair:
    case (_, Some{R.Write{_, _, _, P.Preferences{_, ts, _, _, _, _, _, _, _, _, _, _, _}}}): ts
    case _: True{}

def scopes(+n: Nat, state: R.State) -> R.State:
  match n:
    case 0n: state
    case 1n+p: scopes(p, R.observe(state, "scope" ++ Nat.show(n) ++ ".example", 6697, base(), 0n))

def depart_capacity(n: Nat) -> R.State:
  R.observe(R.observe(scopes(n, start()), "scope1.example", 6697, named("#edited"), 1n), "scope17.example", 6697, base(), 1n)

def failed_then_other() -> R.Completion:
  R.loaded(start.pair(R.take(R.observe(drain.result(R.loaded(start(), 1n, None{}, 2)), "other.example", 6697, base(), 0n))), 2n, Some{stored()}, 0)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("loaded defaults apply after async read", loaded_ok(R.loaded(start(), 1n, Some{stored()}, 0)))
    Unit <- E.must("settings edits and key-only channel revision win late load", edit_wins(R.loaded(R.observe(start(), "irc.example", 6697, settings_edited(), 1n), 1n, Some{stored()}, 0)))
    Unit <- E.must("same-value accepted setting intent wins stored opposite value", ts_on(R.loaded(R.mark(start(), ["ts"]), 1n, Some{stored()}, 0)))
    Unit <- E.must("unknown setting intent does not block stored value", Bool.not(ts_on(R.loaded(R.mark(start(), ["unknown"]), 1n, Some{stored()}, 0))))
    Unit <- E.must("stale endpoint completion never applies or resumes new endpoint", stale(R.loaded(R.observe(start(), "other.example", 6697, base(), 0n), 1n, Some{stored()}, 0)))
    Unit <- E.must("wrong ticket cannot release current worker", stale(R.loaded(start(), 99n, Some{stored()}, 0)))
    Unit <- E.must("preload edits survive endpoint switch and merge untouched stored fields", deferred(R.loaded(R.observe(R.observe(start(), "irc.example", 6697, settings_edited(), 1n), "other.example", 6697, base(), 1n), 1n, Some{stored()}, 0)))
    Unit <- E.must("postload edit survives endpoint switch", after_loaded(R.loaded(start(), 1n, Some{stored()}, 0)))
    Unit <- E.must_eq("rapid A B C preserves every endpoint edit", rapid_writes(0), "irc.example:channel\t#a-edit\nb.example:channel\t#b-edit\nc.example:channel\t#c-edit\n")
    Unit <- E.must_eq("unsafe unresolved A is never written while B C still drain", rapid_writes(2), "b.example:channel\t#b-edit\nc.example:channel\t#c-edit\n")
    Unit <- E.must_eq("active write cannot replace deferred B intent", writes(12n, R.saved(active_write_switch(), 2n)), "irc.example:channel\t#latest\nb.example:channel\t#b-edit\n")
    Unit <- E.must_eq("return prefers latest pending names over active old write", returning_text(R.returning_channels(active_write_switch(), "irc.example", 6697, 3n)), "channel\t#latest\n")
    Unit <- E.must_eq("return to active read restores earlier names intent", returning_text(R.returning_channels(rapid(), "irc.example", 6697, 3n)), "channel\t#a-edit\n")
    Unit <- E.must_eq("return to queued read restores earlier names intent", returning_text(R.returning_channels(rapid(), "b.example", 6697, 3n)), "channel\t#b-edit\n")
    Unit <- E.must_eq("old endpoint membership revision does not cancel cached return", returning_text(R.returning_channels(rapid(), "b.example", 6697, 4n)), "channel\t#b-edit\n")
    Unit <- E.must("other endpoint revision does not invent edit in untouched A", loaded_ok(R.loaded(R.observe(R.observe(R.observe(start(), "b.example", 6697, named("#b"), 0n), "b.example", 6697, named("#b-edited"), 1n), "irc.example", 6697, base(), 1n), 1n, Some{stored()}, 0)))
    Unit <- E.must_eq("edit after return replaces old pending write", writes(12n, R.saved(return_after_write(), 2n)), "b.example:channel\t#b-edit\nirc.example:channel\t#after-return\n")
    Unit <- E.must("newer global setting wins stale endpoint write", Bool.not(first_write_ts(R.take(drain.result(R.loaded(global_edit(), 1n, Some{base()}, 0))))))
    Unit <- E.must("read failure without accepted edits is a clean quit", R.clean(drain.result(R.loaded(start(), 1n, None{}, 2))))
    Unit <- E.must("failed initial globals decision is not reopened at another endpoint", ts_on(failed_then_other()))
    Unit <- E.must("post-failure same-value accepted setting intent remains accounted", Bool.not(R.clean(R.observe(R.mark(drain.result(R.loaded(start(), 1n, None{}, 2)), ["ts"]), "irc.example", 6697, base(), 0n))))
    Unit <- E.must("read failure with accepted setting intent is not a clean quit", Bool.not(R.clean(drain.result(R.loaded(R.mark(start(), ["ts"]), 1n, None{}, 2)))))
    Unit <- E.must("failed pending write is not a clean quit", Bool.not(R.clean(R.saved_result(active_write(), 2n, 3))))
    Unit <- E.must("wrong write ticket cannot make quit fail", R.clean(R.saved_result(active_write(), 99n, 3)))
    Unit <- E.must("sixteen endpoint scopes fit one active plus fifteen queued", Nat.is_eq(R.queue_depth(scopes(15n, start())), 15n) && U32.is_zero(R.queue_code(scopes(15n, start()))))
    Unit <- E.must("seventeenth unresolved scope is reported without truncating queue", Nat.is_eq(R.queue_depth(scopes(16n, start())), 15n) && U32.is_eq(R.queue_code(scopes(16n, start())), 7))
    Unit <- E.must("dirty refused scope cannot exceed active-inclusive capacity", Nat.is_eq(R.queue_depth(depart_capacity(16n)), 15n) && Bool.not(R.clean(depart_capacity(16n))))
    Unit <- E.must_eq("accepted sixteenth scope retains its edit when a new scope is refused", returning_text(R.returning_channels(depart_capacity(15n), "scope1.example", 6697, 1n)), "channel\t#edited\n")
    Unit <- E.must("disabled preferences schedule no helper", R.no_job(R.take(R.initial(False{}, "irc.example", 6697, base(), 0n, False{}, False{}, False{}))))
    Unit <- E.must("explicit channel flag recognized", R.channel_explicit(["--connect", "irc.example", "--channel", "#explicit"]))
    Unit <- E.must("channel-like flag value is not mistaken for flag", Bool.not(R.channel_explicit(["--nick", "--channel"])))
    IO.print("preferences_runtime_demo=ok\n")
