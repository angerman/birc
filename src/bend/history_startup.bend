# SPDX-License-Identifier: Apache-2.0
# Import a completed startup snapshot into the current preconnect client.
import Base
import ./buffer.bend as Cl
import ./history.bend as H
import ./irc.bend as Irc

# Temporary archive IDs establish file order only. Import assigns new global
# IDs after all current local events, without replaying diagnostic mirrors.
type Import is Data:
  Import{client: Cl.Client, entries: List<&2, H.HistEntry>, seen: List<&2, String>}

def operation_ids.keep(nonzero: Bool, id: Nat, rest: List<&2, Nat>) -> List<&2, Nat>:
  match nonzero:
    case True{}: id <> rest
    case False{}: rest

def operation_ids.lines(lines: List<&2, Cl.Line>) -> List<&2, Nat>:
  match lines:
    case Nil{}: Nil{}
    case Con{Cl.Line{Cl.Error{}, _, _, _, +id}, rest}:
      operation_ids.keep(Bool.not(Nat.is_eq(id, 0n)), id, operation_ids.lines(rest))
    case Con{_, rest}: operation_ids.lines(rest)

def operation_ids.buffers(bufs: List<&2, Cl.Buffer>) -> List<&2, Nat>:
  match bufs:
    case Nil{}: Nil{}
    case Con{Cl.Buffer{_, _, _, lines, _, _, _, _}, rest}:
      List.append(&2, Nat, operation_ids.lines(lines), operation_ids.buffers(rest))

def operation_ids(snapshot: Cl.Client) -> List<&2, Nat>:
  operation_ids.buffers(Cl.log_buffers(snapshot))

def operation_id(ids: List<&2, Nat>, +id: Nat) -> Bool:
  match ids:
    case Nil{}: False{}
    case Con{head, rest}: Nat.is_eq(head, id) || operation_id(rest, id)

def operation_line(line: Cl.Line, ids: List<&2, Nat>) -> Bool:
  match line:
    case Cl.Line{_, _, _, _, +id}: Bool.not(Nat.is_eq(id, 0n)) && operation_id(ids, id)

def strip_operations.keep(skip: Bool, line: Cl.Line, rest: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match skip:
    case True{}: rest
    case False{}: line <> rest

def strip_operations(lines: List<&2, Cl.Line>, +ids: List<&2, Nat>) -> List<&2, Cl.Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+line, rest}: strip_operations.keep(operation_line(line, ids), line, strip_operations(rest, ids))

def snapshot.buffers(bufs: List<&2, Cl.Buffer>, +ids: List<&2, Nat>) -> List<&2, Cl.Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{Cl.Buffer{name, channel, topic, lines, nicks, scroll, _, _}, rest}:
      Cl.buf_indexed(name, channel, topic, strip_operations(lines, ids), nicks, scroll) <> snapshot.buffers(rest, ids)

def archive_lines.keep(skip: Bool, line: Cl.Line, rest: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match skip:
    case True{}: rest
    case False{}: line <> rest

def archive_lines(lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+line, rest}:
      match line:
        case Cl.Line{+kind, _, _, _, _}:
          archive_lines.keep(Cl.is_reconnect(kind) || Cl.is_link_result(kind), line, archive_lines(rest))

def seen(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case Con{head, rest}: Irc.ieq(head, name) || seen(rest, name)

def room(got: Maybe<&2, Cl.Buffer>, +cap: U32) -> Nat:
  match got:
    case None{}: 0n
    case Some{Cl.Buffer{_, _, _, lines, _, _, _, _}}:
      Cl.clamp_nat(U32.to_nat(cap), Nat.sub(Cl.SCROLL_CAP(), List.length(&2, Cl.Line, lines)))

def target.create(ok: Bool, +cl: Cl.Client, +name: String) -> Cl.Client & Maybe<&2, Nat>:
  match ok:
    case False{}: (cl, None{})
    case True{}: Cl.buf_get(cl, name, Cl.target_channel(name), True{})

def target.found(found: Maybe<&2, Nat>, +cl: Cl.Client, +name: String) -> Cl.Client & Maybe<&2, Nat>:
  match found:
    case Some{index}: (cl, Some{index})
    case None{}:
      +bufs = Cl.client_bufs(cl)
      target.create(Nat.is_lt(Cl.buf_count(bufs), Cl.MAX_BUFFERS()) && Nat.is_lt(Cl.normal_buffer_count(bufs), Cl.NORMAL_BUFFERS()), cl, name)

def target(control: Bool, +cl: Cl.Client, +name: String) -> Cl.Client & Maybe<&2, Nat>:
  match control:
    case True{}: (cl, Some{0n})
    case False{}: target.found(Cl.buf_find(cl, name), cl, name)

def collect.target(pair: Cl.Client & Maybe<&2, Nat>, entries: List<&2, H.HistEntry>, +names: List<&2, String>, +name: String, +lines: List<&2, Cl.Line>, +control: Bool, cap: U32) -> Import:
  match pair:
    case (cl, None{}): Import{cl, entries, names}
    case (+cl, Some{+index}):
      +kept = Cl.take_last(lines, room(Cl.nth_buf(Cl.client_bufs(cl), index), cap))
      Import{cl, List.append(&2, H.HistEntry, H.new_entries.lines(kept, name, control), entries),
        Bool.pick(List<&2, String>, control, names, name <> names)}

def collect.nonempty(empty: Bool, acc: Import, +name: String, lines: List<&2, Cl.Line>, +control: Bool, cap: U32) -> Import:
  match empty:
    case True{}: acc
    case False{}:
      match acc:
        case Import{cl, entries, names}: collect.target(target(control, cl, name), entries, names, name, lines, control, cap)

def collect.allowed(ok: Bool, acc: Import, +name: String, +lines: List<&2, Cl.Line>, +control: Bool, cap: U32) -> Import:
  match ok:
    case False{}: acc
    case True{}: collect.nonempty(List.is_empty(&2, Cl.Line, lines), acc, name, lines, control, cap)

def collect.buffer(+acc: Import, b: Cl.Buffer, +control: Bool, cap: U32) -> Import:
  match acc:
    case Import{_, _, names}:
      match b:
        case Cl.Buffer{+name, _, _, lines, _, _, _, _}:
          collect.allowed((control || (Cl.target_wire(name) && Bool.not(String.is_empty(name))))
            && (control || Bool.not(seen(names, name))), acc, name, archive_lines(lines), control, cap)

def collect.when(ok: Bool, +acc: Import, +b: Cl.Buffer, +cap: U32) -> Import:
  match ok:
    case False{}: acc
    case True{}: collect.buffer(acc, b, False{}, cap)

def import_client(acc: Import) -> Cl.Client:
  match acc:
    case Import{cl, _, _}: cl

def admit.present(got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def collect.chosen(+acc: Import, +b: Cl.Buffer, +picked: List<&2, String>, +cap: U32) -> Import:
  match b:
    case Cl.Buffer{+name, _, _, _, _, _, _, _}:
      collect.when(seen(picked, name) || admit.present(Cl.buf_find(import_client(acc), name)), acc, b, cap)

def collect.ordered(bufs: List<&2, Cl.Buffer>, acc: Import, +picked: List<&2, String>, +cap: U32) -> Import:
  match bufs:
    case Nil{}: acc
    case Con{+b, +rest}: collect.ordered(rest, collect.chosen(acc, b, picked, cap), picked, cap)

def recent_id(b: Cl.Buffer) -> Nat:
  match b:
    case Cl.Buffer{_, _, _, lines, _, _, _, _}: H.last_id(archive_lines(lines))

def recent(a: Cl.Buffer, b: Cl.Buffer) -> Bool:
  Nat.is_ge(recent_id(a), recent_id(b))

def restore.at(got: Maybe<&2, Nat>, cl: Cl.Client, line: Cl.Line) -> Cl.Client:
  match got:
    case None{}: cl
    case Some{index}: H.apply_entry.bi(cl, index, line)

def restore(entry: H.HistEntry, +cl: Cl.Client) -> Cl.Client:
  match entry:
    case H.ServerEntry{line}: H.apply_entry.bi(cl, 0n, line)
    case H.Entry{+target, line}: restore.at(Cl.buf_find(cl, target), cl, line)

def install.collected(got: Import) -> Cl.Client:
  match got:
    case Import{cl, entries, _}:
      List.foldl(~&2, ~H.HistEntry, ~Cl.Client, ~(cl => entry => restore(entry, cl)), List.sort(~H.HistEntry, ~H.entry_id_le, entries), cl)

def admit.usable(+name: String, +lines: List<&2, Cl.Line>, +acc: List<&2, String>, +cl: Cl.Client) -> Bool:
  Bool.not(List.is_empty(&2, Cl.Line, archive_lines(lines)))
    && Cl.target_wire(name)
    && Bool.not(String.is_empty(name))
    && Bool.not(seen(acc, name))
    && Bool.not(admit.present(Cl.buf_find(cl, name)))

# `left` is room-1. A skipped target does not spend a slot, so the next room
# is 1+left. The walk itself shrinks the buffer list, which is the recursive
# argument. Nat.sub stays behind the full-client match in room_for.
def admit.keep(
  ok: Bool,
  +name: String,
  +left: Nat,
  +acc: List<&2, String>,
  k: Nat -> List<&2, String> -> List<&2, String>
) -> List<&2, String>:
  match ok:
    case False{}: k(1n+left, acc)
    case True{}: k(left, name <> acc)

def admit.buffer(
  +b: Cl.Buffer,
  +left: Nat,
  +cl: Cl.Client,
  +acc: List<&2, String>,
  k: Nat -> List<&2, String> -> List<&2, String>
) -> List<&2, String>:
  match b:
    case Cl.Buffer{+name, _, _, +lines, _, _, _, _}:
      admit.keep(admit.usable(name, lines, acc, cl), name, left, acc, k)

def admit.go(bufs: List<&2, Cl.Buffer>, room: Nat, +cl: Cl.Client, +acc: List<&2, String>) -> List<&2, String>:
  match bufs:
    case Nil{}: acc
    case Con{+b, +rest}:
      match room:
        case 0n: acc
        case 1n+left:
          admit.buffer(b, left, cl, acc, next => acc2 => admit.go(rest, next, cl, acc2))

def room_for.normal(under: Bool, +count: Nat, +normal: Nat) -> Nat:
  match under:
    case False{}: 0n
    case True{}: Nat.min(Nat.sub(Cl.MAX_BUFFERS(), count), Nat.sub(Cl.NORMAL_BUFFERS(), normal))

def room_for.span(under: Bool, +count: Nat, +normal: Nat) -> Nat:
  match under:
    case False{}: 0n
    case True{}: room_for.normal(Nat.is_lt(normal, Cl.NORMAL_BUFFERS()), count, normal)

def room_for.counts(+count: Nat, +normal: Nat) -> Nat:
  room_for.span(Nat.is_lt(count, Cl.MAX_BUFFERS()), count, normal)

def room_for.bufs(+bufs: List<&2, Cl.Buffer>) -> Nat:
  room_for.counts(Cl.buf_count(bufs), Cl.normal_buffer_count(bufs))

def room_for(+cl: Cl.Client) -> Nat:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _, _}: room_for.bufs(bufs)

def install.picked(+rest: List<&2, Cl.Buffer>, +current: Cl.Client) -> List<&2, String>:
  admit.go(List.sort(~Cl.Buffer, ~recent, rest), room_for(current), current, Nil{})

def install.ordered(+server: Cl.Buffer, +rest: List<&2, Cl.Buffer>, +current: Cl.Client, +cap: U32) -> Cl.Client:
  +base = collect.buffer(Import{current, Nil{}, Nil{}}, server, True{}, cap)
  install.collected(collect.ordered(rest, base, install.picked(rest, current), cap))

def install.buffers(bufs: List<&2, Cl.Buffer>, +current: Cl.Client, +cap: U32) -> Cl.Client:
  match bufs:
    case Nil{}: current
    case Con{server, rest}:
      # Current tabs win. Spare slots go to the most recently used archive
      # targets, then those targets are appended in snapshot order. Accepted
      # rows still replay in file order.
      install.ordered(server, rest, current, cap)

def install.allowed(ok: Bool, +current: Cl.Client, +snapshot: Cl.Client) -> Cl.Client:
  match ok:
    case False{}: current
    case True{}:
      install.buffers(snapshot.buffers(Cl.client_bufs(snapshot), operation_ids(snapshot)), current, Cl.settings_hist_cap(Cl.get_settings(current)))

# Exact host:port strings. Outer archive_current / reload_match also check this;
# this defense rejects host-colliding different ports when a caller skips them.
def same_endpoint(+current_ep: String, +snapshot_ep: String) -> Bool:
  String.eq(current_ep, snapshot_ep)

# The outer startup gate owns ticket/generation checks and the checkpoint.
# This defense also rejects a changed endpoint (host or port) or a newly
# disabled history setting. Never cap current rows or evict current targets to
# make room for an archive. Startup-before-005 still imports with the default
# RFC1459 map. Live merges go through install_startup and that same map.
def install(+current: Cl.Client, +snapshot: Cl.Client, +current_ep: String, +snapshot_ep: String) -> Cl.Client:
  +settings = Cl.get_settings(current)
  install.allowed(same_endpoint(current_ep, snapshot_ep)
    && String.eq(Cl.server_of(current), Cl.server_of(snapshot))
    && Cl.settings_history(settings) && Bool.not(U32.is_zero(Cl.settings_hist_cap(settings))), current, snapshot)

def install_startup.mark(on: Bool, cl: Cl.Client, index: Nat, now: String) -> Cl.Client:
  match on:
    case False{}: cl
    case True{}:
      match cl:
        case Cl.Client{nick, host, bufs, active, clock, settings, auth, seq, welcomed}:
          +next: Nat = 1n+seq
          +marker: Cl.Line = Cl.Line{Cl.Reconnect{}, "", Cl.now_hms(now), "", next}
          Cl.Client{nick, host, Cl.buf_modify(bufs, index, b => Cl.buf_append_line(b, marker)), active, clock, settings, auth, next, welcomed}

def install_startup.buffers(bufs: List<&2, Cl.Buffer>, +index: Nat, +cutoff: Nat, cl: Cl.Client, +now: String) -> Cl.Client:
  match bufs:
    case Nil{}: cl
    case Con{Cl.Buffer{+name, _, _, +lines, _, _, _, _}, rest}:
      install_startup.buffers(rest, 1n+index, cutoff,
        install_startup.mark(Bool.not(Cl.target_is_synthetic(name)) && Nat.is_gt(H.last_id(lines), cutoff)
          && Nat.is_lt(List.length(&2, Cl.Line, lines), Cl.SCROLL_CAP()), cl, index, now), now)

def install_startup.marked(+cl: Cl.Client, cutoff: Nat, now: String) -> Cl.Client:
  install_startup.buffers(Cl.client_bufs(cl), 0n, cutoff, cl, now)

# The caller reports owned worker diagnostics first. Its current sequence is
# therefore the archive cutoff: local and operation-only targets get no marker.
# Never make room for a divider by removing a retained row.
def install_startup(+current: Cl.Client, snapshot: Cl.Client, +current_ep: String, +snapshot_ep: String) -> Cl.Client:
  match current:
    case Cl.Client{_, _, _, _, now, _, _, +cutoff, _}:
      install_startup.marked(install(current, snapshot, current_ep, snapshot_ep), cutoff, now)

# Fresh worker *log* rows describe only this read operation. Synthetic history
# records are rejected by the archive parser; archived Error imports never
# create these mirrors. Report them as current events, not restored log rows.
def diagnostics.lines(lines: List<&2, Cl.Line>) -> List<&2, String>:
  match lines:
    case Nil{}: Nil{}
    case Con{Cl.Line{Cl.Error{}, _, text, _, _}, rest}: text <> diagnostics.lines(rest)
    case Con{_, rest}: diagnostics.lines(rest)

def diagnostics.buffers(bufs: List<&2, Cl.Buffer>) -> List<&2, String>:
  match bufs:
    case Nil{}: Nil{}
    case Con{Cl.Buffer{_, _, _, lines, _, _, _, _}, rest}:
      List.append(&2, String, diagnostics.lines(lines), diagnostics.buffers(rest))

def diagnostics(snapshot: Cl.Client) -> List<&2, String>:
  diagnostics.buffers(Cl.log_buffers(snapshot))

def report_diagnostics.logs(messages: List<&2, String>, current: Cl.Client) -> Cl.Client:
  match messages:
    case Nil{}: current
    case Con{message, rest}: report_diagnostics.logs(rest, Cl.client_log(current, 0n, Cl.Error{}, message))

def report_diagnostics.allowed(ok: Bool, current: Cl.Client, snapshot: Cl.Client) -> Cl.Client:
  match ok:
    case False{}: current
    case True{}: report_diagnostics.logs(diagnostics(snapshot), current)

def report_diagnostics(+current: Cl.Client, +snapshot: Cl.Client, +current_ep: String, +snapshot_ep: String) -> Cl.Client:
  report_diagnostics.allowed(same_endpoint(current_ep, snapshot_ep)
    && String.eq(Cl.server_of(current), Cl.server_of(snapshot)), current, snapshot)
