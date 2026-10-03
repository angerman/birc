# SPDX-License-Identifier: Apache-2.0
# One active helper and at most 16 coalesced endpoint jobs. Keys never enter here.
import Base
import ./preferences.bend as P

type Edits is Data:
  Edits{joins: Bool, ts: Bool, motd: Bool, history: Bool, cap: Bool, auto: Bool, bell: Bool, images: Bool, mutes: Bool}

type Job is Data:
  Read{ticket: Nat, host: String, port: U32, revision: Nat, deferred: List<&2, Deferred>}
  Write{ticket: Nat, host: String, port: U32, prefs: P.Preferences}

type Deferred is Data:
  Deferred{prefs: P.Preferences, mask: Edits, revision: Nat, explicit: Bool, first: Bool, dirty: Bool}

type Queue is Data:
  Queue{jobs: List<&2, Job>, notice: U32, lost: Bool}

type State is Data:
  Disabled{}
  State{host: String, port: U32, next: Nat, active: Maybe<&2, Job>, pending: Queue, loaded: Bool, blocked: Bool, first: Bool, snapshot: P.Preferences, edits: Edits, revision: Nat, explicit: Bool, dirty: Bool}

type Completion is Data:
  Completion{state: State, prefs: Maybe<&2, P.Preferences>, seed: Bool, resume: Bool}

def initial(on: Bool, +host: String, +port: U32, +snapshot: P.Preferences, +revision: Nat, +explicit: Bool, images: Bool, cap: Bool) -> State:
  match on:
    case False{}: Disabled{}
    case True{}:
      +mask : Edits = Edits{False{}, False{}, False{}, False{}, cap, False{}, False{}, images, False{}}
      State{host, port, 1n, None{}, Queue{Read{0n, host, port, revision, Deferred{snapshot, mask, revision, explicit, True{}, False{}} <> Nil{}} <> Nil{}, 0, False{}}, False{}, False{}, True{}, snapshot, mask, revision, explicit, False{}}

def enabled(state: State) -> Bool:
  match state:
    case Disabled{}: False{}
    case _: True{}

def waiting(state: State) -> Bool:
  match state:
    case State{_, _, _, _, _, loaded, blocked, _, _, _, _, _, _}: Bool.not(loaded) && Bool.not(blocked)
    case Disabled{}: False{}

def busy(state: State) -> Bool:
  match state:
    case State{_, _, _, Some{_}, _, _, _, _, _, _, _, _, _}: True{}
    case State{_, _, _, None{}, Queue{Con{_, _}, _, _}, _, _, _, _, _, _, _, _}: True{}
    case State{_, _, _, None{}, Queue{Nil{}, _, _}, loaded, blocked, _, _, _, _, _, _}: Bool.not(loaded) && Bool.not(blocked)
    case Disabled{}: False{}

def owns_read(state: State, ticket: Nat) -> Bool:
  match state:
    case State{_, _, _, Some{Read{owned, _, _, _, _}}, _, _, _, _, _, _, _, _, _}: Nat.is_eq(owned, ticket)
    case _: False{}

def owns_write(state: State, ticket: Nat) -> Bool:
  match state:
    case State{_, _, _, Some{Write{owned, _, _, _}}, _, _, _, _, _, _, _, _, _}: Nat.is_eq(owned, ticket)
    case _: False{}

def read_revision(state: State) -> Nat:
  match state:
    case State{_, _, _, Some{Read{_, _, _, revision, _}}, _, _, _, _, _, _, _, _, _}: revision
    case _: 0n

def same(+host: String, +port: U32, other: String, n: U32) -> Bool:
  String.eq(host, other) && U32.is_eq(port, n)

def canonical(prefs: P.Preferences) -> P.Preferences:
  match prefs:
    case P.Preferences{j, t, m, h, c, a, b, i, u, channels, _}:
      P.Preferences{j, t, m, h, c, a, b, i, u, channels, True{}}

def equal(a: P.Preferences, b: P.Preferences) -> Bool:
  String.eq(P.show(canonical(a)), P.show(canonical(b)))

def changed_bool(+a: Bool, +b: Bool) -> Bool:
  (a && Bool.not(b)) || (Bool.not(a) && b)

def edits(prior: Edits, before: P.Preferences, after: P.Preferences) -> Edits:
  match prior:
    case Edits{j, t, m, h, c, a, b, i, u}:
      match before:
        case P.Preferences{j0, t0, m0, h0, c0, a0, b0, i0, u0, _, _}:
          match after:
            case P.Preferences{j1, t1, m1, h1, c1, a1, b1, i1, u1, _, _}:
              Edits{j || changed_bool(j0, j1), t || changed_bool(t0, t1), m || changed_bool(m0, m1), h || changed_bool(h0, h1), c || Bool.not(U32.is_eq(c0, c1)), a || changed_bool(a0, a1), b || changed_bool(b0, b1), i || changed_bool(i0, i1), u || Bool.not(String.eq(P.records_text(u0, "mute"), P.records_text(u1, "mute")))}

def mark.field(+name: String, mask: Edits) -> Edits:
  match mask:
    case Edits{j, t, m, h, c, a, b, i, u}:
      Edits{j || String.eq(name, "joins"), t || String.eq(name, "ts"), m || String.eq(name, "motd"), h || String.eq(name, "history"), c || String.eq(name, "hist_cap"), a || String.eq(name, "autoreconn"), b || String.eq(name, "bell"), i || String.eq(name, "images"), u || String.eq(name, "mutes")}

def mark.names(names: List<&2, String>, mask: Edits) -> Edits:
  match names:
    case Nil{}: mask
    case Con{h, t}: mark.names(t, mark.field(h, mask))

def mask_text(mask: Edits) -> String:
  match mask:
    case Edits{j, t, m, h, c, a, b, i, u}: P.bit(j) ++ P.bit(t) ++ P.bit(m) ++ P.bit(h) ++ P.bit(c) ++ P.bit(a) ++ P.bit(b) ++ P.bit(i) ++ P.bit(u)

def mark.changed(changed: Bool, state: State, mask: Edits) -> State:
  match changed:
    case False{}: state
    case True{}:
      match state:
        case Disabled{}: Disabled{}
        case State{host, port, next, active, queued, loaded, blocked, first, snapshot, _, revision, explicit, _}:
          State{host, port, next, active, queued, loaded, blocked, first, snapshot, mask, revision, explicit, True{}}

def mark(+state: State, names: List<&2, String>) -> State:
  match state:
    case State{_, _, _, _, _, _, _, _, _, +mask, _, _, _}:
      +next = mark.names(names, mask)
      mark.changed(Bool.not(String.eq(mask_text(mask), mask_text(next))), state, next)
    case _: state

def merge(+global: Bool, keep_channels: Bool, mask: Edits, current: P.Preferences, stored: P.Preferences) -> P.Preferences:
  match mask:
    case Edits{j, t, m, h, c, a, b, i, u}:
      match current:
        case P.Preferences{j0, t0, m0, h0, c0, a0, b0, i0, u0, channels0, _}:
          match stored:
            case P.Preferences{j1, t1, m1, h1, c1, a1, b1, i1, u1, channels1, _}:
              P.Preferences{Bool.pick(Bool, global && Bool.not(j), j1, j0), Bool.pick(Bool, global && Bool.not(t), t1, t0), Bool.pick(Bool, global && Bool.not(m), m1, m0), Bool.pick(Bool, global && Bool.not(h), h1, h0), Bool.pick(U32, global && Bool.not(c), c1, c0), Bool.pick(Bool, global && Bool.not(a), a1, a0), Bool.pick(Bool, global && Bool.not(b), b1, b0), Bool.pick(Bool, global && Bool.not(i), i1, i0), Bool.pick(List<&2, String>, global && Bool.not(u), u1, u0), Bool.pick(List<&2, String>, keep_channels, channels0, channels1), True{}}

def queue.same(job: Job, host: String, port: U32) -> Bool:
  match job:
    case Read{_, other, n, _, _}: same(host, port, other, n)
    case Write{_, other, n, _}: same(host, port, other, n)

def queue.has(xs: List<&2, Job>, +host: String, +port: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, t}: queue.same(h, host, port) || queue.has(t, host, port)

def queue.dirty(job: Job) -> Bool:
  match job:
    case Write{_, _, _, _}: True{}
    case Read{_, _, _, baseline, Deferred{_, _, revision, _, _, dirty} <> Nil{}}:
      dirty || Bool.not(Nat.is_eq(revision, baseline))
    case _: False{}

def queue.remove(xs: List<&2, Job>, +host: String, +port: U32) -> List<&2, Job>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +rest = queue.remove(t, host, port)
      Bool.pick(List<&2, Job>, queue.same(h, host, port), rest, h <> rest)

def queue.admit(ok: Bool, prior: Queue, +job: Job, +host: String, +port: U32, front: Bool) -> Queue:
  match ok:
    case False{}:
      match prior:
        case Queue{jobs, _, lost}: Queue{jobs, 7, lost || queue.dirty(job)}
    case True{}:
      match prior:
        case Queue{jobs, code, lost}:
          +rest = queue.remove(jobs, host, port)
          Queue{Bool.pick(List<&2, Job>, front, job <> rest, List.append(&2, Job, rest, job <> Nil{})), code, lost}

def queue.put(+prior: Queue, +job: Job, +host: String, +port: U32, front: Bool) -> Queue:
  match prior:
    case Queue{jobs, _, _}:
      queue.admit(queue.has(jobs, host, port) || Nat.is_lt(List.length(&2, Job, jobs), 16n), prior, job, host, port, front)

def queue.lost(prior: Queue, fail: Bool) -> Queue:
  match prior:
    case Queue{jobs, code, lost}: Queue{jobs, code, lost || fail}

def queue.put_job(prior: Queue, job: Job, front: Bool) -> Queue:
  match job:
    case Write{ticket, +h, +p, prefs}: queue.put(prior, Write{ticket, h, p, prefs}, h, p, front)
    case Read{ticket, +h, +p, r, d}: queue.put(prior, Read{ticket, h, p, r, d}, h, p, front)

def pending(change: Bool, +host: String, +port: U32, snapshot: P.Preferences, prior: Queue) -> Queue:
  match change:
    case False{}: prior
    case True{}: queue.put(prior, Write{0n, host, port, canonical(snapshot)}, host, port, False{})

def pending.first(change: Bool, +host: String, +port: U32, snapshot: P.Preferences, prior: Queue) -> Queue:
  match change:
    case False{}: prior
    case True{}: queue.put(prior, Write{0n, host, port, canonical(snapshot)}, host, port, True{})

def defer.current(on: Bool, ticket: Nat, host: String, port: U32, baseline: Nat, prior: List<&2, Deferred>, prefs: P.Preferences, mask: Edits, revision: Nat, explicit: Bool, first: Bool) -> Maybe<&2, Job>:
  match on:
    case False{}: Some{Read{ticket, host, port, baseline, prior}}
    case True{}: Some{Read{ticket, host, port, baseline, Deferred{prefs, mask, revision, explicit, first, True{}} <> Nil{}}}

def defer(+active: Maybe<&2, Job>, +host: String, +port: U32, prefs: P.Preferences, mask: Edits, +revision: Nat, explicit: Bool, first: Bool, dirty: Bool) -> Maybe<&2, Job>:
  match active:
    case Some{Read{ticket, +read_host, +read_port, +baseline, prior}}:
      defer.current(same(host, port, read_host, read_port) && (dirty || Bool.not(Nat.is_eq(revision, baseline))), ticket, read_host, read_port, baseline, prior, prefs, mask, revision, explicit, first)
    case _: active

def defer.job(+job: Job, +host: String, +port: U32, prefs: P.Preferences, mask: Edits, +revision: Nat, explicit: Bool, first: Bool, dirty: Bool) -> Job:
  match job:
    case Read{ticket, +h, +p, +baseline, old}:
      # Leave the original channel baseline intact when names change and back.
      Bool.pick(Job, queue.same(job, host, port) && (dirty || Bool.not(Nat.is_eq(revision, baseline))),
        Read{ticket, h, p, baseline, Deferred{prefs, mask, revision, explicit, first, True{}} <> Nil{}}, job)
    case _: job

def defer.jobs(xs: List<&2, Job>, +host: String, +port: U32, +prefs: P.Preferences, +mask: Edits, +revision: Nat, +explicit: Bool, +first: Bool, +dirty: Bool) -> List<&2, Job>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: defer.job(h, host, port, prefs, mask, revision, explicit, first, dirty) <> defer.jobs(t, host, port, prefs, mask, revision, explicit, first, dirty)

def defer.queue(q: Queue, host: String, port: U32, prefs: P.Preferences, mask: Edits, revision: Nat, explicit: Bool, first: Bool, dirty: Bool) -> Queue:
  match q:
    case Queue{jobs, code, lost}: Queue{defer.jobs(jobs, host, port, prefs, mask, revision, explicit, first, dirty), code, lost}

def edits.empty() -> Edits:
  Edits{False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}}

def edits.union(a: Edits, b: Edits) -> Edits:
  match a:
    case Edits{j0, t0, m0, h0, c0, a0, b0, i0, u0}:
      match b:
        case Edits{j1, t1, m1, h1, c1, a1, b1, i1, u1}: Edits{j0 || j1, t0 || t1, m0 || m1, h0 || h1, c0 || c1, a0 || a1, b0 || b1, i0 || i1, u0 || u1}

def edits.fresh(a: Edits, b: Edits) -> Edits:
  match a:
    case Edits{j0, t0, m0, h0, c0, a0, b0, i0, u0}:
      match b:
        case Edits{j1, t1, m1, h1, c1, a1, b1, i1, u1}: Edits{j0 && Bool.not(j1), t0 && Bool.not(t1), m0 && Bool.not(m1), h0 && Bool.not(h1), c0 && Bool.not(c1), a0 && Bool.not(a1), b0 && Bool.not(b1), i0 && Bool.not(i1), u0 && Bool.not(u1)}

# Global patches retain each endpoint's own public names.
def globals(current: P.Preferences, endpoint: P.Preferences) -> P.Preferences:
  match current:
    case P.Preferences{j, t, m, h, c, a, b, i, u, _, _}:
      match endpoint:
        case P.Preferences{_, _, _, _, _, _, _, _, _, channels, known}: P.Preferences{j, t, m, h, c, a, b, i, u, channels, known}

def rebase.job(job: Job, +prefs: P.Preferences, +mask: Edits, diff: Edits) -> Job:
  match job:
    case Write{ticket, host, port, +before}: Write{ticket, host, port, globals(merge(True{}, True{}, diff, prefs, before), before)}
    case Read{ticket, host, port, baseline, Deferred{+before, +prior, revision, explicit, first, +dirty} <> Nil{}}:
      +patch = edits.union(diff, edits.fresh(mask, prior))
      Read{ticket, host, port, baseline, Deferred{globals(merge(True{}, True{}, patch, prefs, before), before), edits.union(mask, prior), revision, explicit, first, dirty || Bool.not(String.eq(mask_text(patch), mask_text(edits.empty())))} <> Nil{}}
    case _: job

def rebase.jobs(xs: List<&2, Job>, +prefs: P.Preferences, +mask: Edits, +diff: Edits) -> List<&2, Job>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: rebase.job(h, prefs, mask, diff) <> rebase.jobs(t, prefs, mask, diff)

def rebase.queue(q: Queue, prefs: P.Preferences, mask: Edits, diff: Edits) -> Queue:
  match q:
    case Queue{jobs, code, lost}: Queue{rebase.jobs(jobs, prefs, mask, diff), code, lost}

def rebase.active(active: Maybe<&2, Job>, prefs: P.Preferences, mask: Edits, diff: Edits) -> Maybe<&2, Job>:
  match active:
    case Some{Read{ticket, host, port, revision, deferred}}: Some{rebase.job(Read{ticket, host, port, revision, deferred}, prefs, mask, diff)}
    case _: active

def queue.contains(q: Queue, host: String, port: U32) -> Bool:
  match q:
    case Queue{jobs, _, _}: queue.has(jobs, host, port)

def queue.limit(active: Maybe<&2, Job>, +q: Queue) -> Nat:
  match active:
    case None{}: 16n
    case Some{Read{_, host, port, _, _}}: Bool.pick(Nat, queue.contains(q, host, port), 16n, 15n)
    case Some{Write{_, host, port, _}}: Bool.pick(Nat, queue.contains(q, host, port), 16n, 15n)

def queue.new(+q: Queue, +host: String, +port: U32, prefs: P.Preferences, mask: Edits, +revision: Nat, first: Bool, limit: Nat) -> Queue:
  match q:
    case Queue{+jobs, _, _}:
      # Returning to an unresolved endpoint cannot erase its accepted edits.
      Bool.pick(Queue, queue.has(jobs, host, port), q,
        queue.admit(Nat.is_lt(List.length(&2, Job, jobs), limit), q,
          Read{0n, host, port, revision, Deferred{prefs, mask, revision, False{}, first, False{}} <> Nil{}}, host, port, False{}))

def active.same(active: Maybe<&2, Job>, host: String, port: U32) -> Bool:
  match active:
    case Some{Read{_, h, p, _, _}}: same(host, port, h, p)
    case _: False{}

def queue.retain_missing(on: Bool, +q: Queue, +host: String, +port: U32, prefs: P.Preferences, mask: Edits, +revision: Nat, first: Bool, limit: Nat) -> Queue:
  match on:
    case False{}: q
    case True{}:
      match q:
        case Queue{+jobs, _, _}:
          Bool.pick(Queue, queue.contains(q, host, port), q,
            queue.admit(Nat.is_lt(List.length(&2, Job, jobs), limit), q,
              Read{0n, host, port, revision, Deferred{prefs, mask, revision, True{}, first, True{}} <> Nil{}}, host, port, False{}))

def active.writable(active: Maybe<&2, Job>, host: String, port: U32) -> Bool:
  match active:
    case Some{Write{_, h, p, _}}: same(host, port, h, p)
    case _: False{}

def queue.writable_jobs(xs: List<&2, Job>, +host: String, +port: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Write{_, h, p, _}, t}: same(host, port, h, p) || queue.writable_jobs(t, host, port)
    case Con{_, t}: queue.writable_jobs(t, host, port)

def queue.writable(q: Queue, host: String, port: U32) -> Bool:
  match q:
    case Queue{jobs, _, _}: queue.writable_jobs(jobs, host, port)

def returning.when(on: Bool, names: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match on:
    case False{}: None{}
    case True{}: Some{names}

def returning.or(got: Maybe<&2, List<&2, String>>, k: Unit -> Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match got:
    case None{}: k(Unit{})
    case Some{names}: Some{names}

def returning.job(job: Job, host: String, port: U32) -> Maybe<&2, List<&2, String>>:
  match job:
    case Write{_, h, p, prefs}: returning.when(same(h, p, host, port), P.channels(prefs))
    case Read{_, h, p, baseline, Deferred{prefs, _, revision, explicit, _, _} <> Nil{}}:
      returning.when(same(h, p, host, port) && (explicit || Bool.not(Nat.is_eq(revision, baseline))), P.channels(prefs))
    case _: None{}

def returning.jobs(xs: List<&2, Job>, +host: String, +port: U32) -> Maybe<&2, List<&2, String>>:
  match xs:
    case Nil{}: None{}
    case Con{h, t}: returning.or(returning.job(h, host, port), _ => returning.jobs(t, host, port))

def returning.active_jobs(active: Maybe<&2, Job>, jobs: List<&2, Job>, +host: String, +port: U32) -> Maybe<&2, List<&2, String>>:
  match active:
    case None{}: returning.jobs(jobs, host, port)
    case Some{job}: returning.or(returning.jobs(jobs, host, port), _ => returning.job(job, host, port))

def returning.active(active: Maybe<&2, Job>, q: Queue, host: String, port: U32) -> Maybe<&2, List<&2, String>>:
  match q:
    case Queue{jobs, _, _}: returning.active_jobs(active, jobs, host, port)

def returning.allowed(on: Bool, active: Maybe<&2, Job>, q: Queue, host: String, port: U32) -> Maybe<&2, List<&2, String>>:
  match on:
    case False{}: None{}
    case True{}: returning.active(active, q, host, port)

def returning_channels(state: State, +host: String, +port: U32, revision: Nat) -> Maybe<&2, List<&2, String>>:
  match state:
    case Disabled{}: None{}
    case State{h, p, _, active, q, _, _, _, _, _, _, _, _}:
      # An old endpoint's membership revision cannot cancel this return. One
      # frame accepts one Enter; /connect cannot also accept /join in new scope.
      returning.allowed(Bool.not(same(h, p, host, port)), active, q, host, port)

def reenter.job(+job: Job, +host: String, +port: U32, +revision: Nat) -> Job:
  match job:
    case Read{ticket, +h, +p, +baseline, Deferred{prefs, mask, +r, +explicit, first, dirty} <> Nil{}}:
      # Other endpoints' revisions cannot invent an edit in this endpoint.
      Bool.pick(Job, same(h, p, host, port) && Bool.not(explicit) && Nat.is_eq(baseline, r),
        Read{ticket, h, p, revision, Deferred{prefs, mask, revision, explicit, first, dirty} <> Nil{}}, job)
    case _: job

def reenter.jobs(xs: List<&2, Job>, +host: String, +port: U32, +revision: Nat) -> List<&2, Job>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: reenter.job(h, host, port, revision) <> reenter.jobs(t, host, port, revision)

def reenter.queue(q: Queue, host: String, port: U32, revision: Nat) -> Queue:
  match q:
    case Queue{jobs, code, lost}: Queue{reenter.jobs(jobs, host, port, revision), code, lost}

def reenter.active(active: Maybe<&2, Job>, host: String, port: U32, revision: Nat) -> Maybe<&2, Job>:
  match active:
    case None{}: None{}
    case Some{job}: Some{reenter.job(job, host, port, revision)}

def observe.same(state: State, +after: P.Preferences, +new_revision: Nat) -> State:
  match state:
    case Disabled{}: Disabled{}
    case State{+host, +port, next, +active, +queued, +loaded, +blocked, +first, +before, +mask, _, +explicit, +dirty}:
      +change = dirty || Bool.not(equal(before, after))
      +next_mask = edits(mask, before, after)
      +diff = edits(edits.empty(), before, after)
      State{host, port, next, defer(rebase.active(active, after, next_mask, diff), host, port, after, next_mask, new_revision, explicit, first, change),
        queue.lost(pending((loaded || active.writable(active, host, port) || queue.writable(queued, host, port)) && Bool.not(blocked) && change, host, port, after,
          defer.queue(rebase.queue(queued, after, next_mask, diff), host, port, after, next_mask, new_revision, explicit, first, change)), blocked && change),
        loaded, blocked, first, after, next_mask, new_revision, explicit, change}

def observe.changed(state: State, +new_host: String, +new_port: U32, +after: P.Preferences, +new_revision: Nat) -> State:
  match state:
    case Disabled{}: Disabled{}
    case State{+host, +port, next, +active, +queued, +loaded, +blocked, +first, +before, +mask, +revision, _, +dirty}:
      +existing = pending(loaded && Bool.not(blocked) && dirty, host, port, before, queued)
      +saved = queue.retain_missing(Bool.not(loaded || blocked || active.same(active, host, port)) && dirty,
        existing, host, port, before, mask, revision, first, queue.limit(active, existing))
      +next_mask = edits(mask, before, after)
      +known = active.writable(active, new_host, new_port) || queue.writable(queued, new_host, new_port)
      State{new_host, new_port, next, reenter.active(active, new_host, new_port, new_revision),
        reenter.queue(Bool.pick(Queue, known || active.same(active, new_host, new_port), saved,
          queue.new(saved, new_host, new_port, after, next_mask, new_revision, first, queue.limit(active, saved))), new_host, new_port, new_revision),
        False{}, False{}, first, after, next_mask, new_revision, False{}, False{}}

def observe.endpoint(endpoint_same: Bool, state: State, new_host: String, new_port: U32, after: P.Preferences, new_revision: Nat) -> State:
  match endpoint_same:
    case True{}: observe.same(state, after, new_revision)
    case False{}: observe.changed(state, new_host, new_port, after, new_revision)

def observe(+state: State, +host: String, +port: U32, after: P.Preferences, revision: Nat) -> State:
  match state:
    case Disabled{}: Disabled{}
    case State{old_host, old_port, _, _, _, _, _, _, _, _, _, _, _}:
      observe.endpoint(same(old_host, old_port, host, port), state, host, port, after, revision)

def stamp(job: Job, ticket: Nat) -> Job:
  match job:
    case Read{_, host, port, revision, deferred}: Read{ticket, host, port, revision, deferred}
    case Write{_, host, port, prefs}: Write{ticket, host, port, prefs}

def job_same(job: Job, host: String, port: U32) -> Bool:
  match job:
    case Read{_, other, n, _, _}: same(host, port, other, n)
    case Write{_, other, n, _}: same(host, port, other, n)

def job_write(job: Job) -> Bool:
  match job:
    case Write{_, _, _, _}: True{}
    case _: False{}

def job_snapshot(job: Job, prefs: P.Preferences) -> Bool:
  match job:
    case Write{_, _, _, saved}: equal(saved, prefs)
    case _: False{}

def take.read(read: Bool, state: State) -> State & Maybe<&2, Job>:
  match read:
    case True{}:
      match state:
        case Disabled{}: (Disabled{}, None{})
        case State{+host, +port, +next, _, queued, loaded, blocked, +first, +snapshot, +mask, +revision, +explicit, +dirty}:
          +job : Job = Read{next, host, port, revision, Deferred{snapshot, mask, revision, explicit || dirty, first, dirty} <> Nil{}}
          (State{host, port, 1n+next, Some{job}, queued, loaded, blocked, first, snapshot, mask, revision, explicit, dirty}, Some{job})
    case False{}: (state, None{})

def take(+state: State) -> State & Maybe<&2, Job>:
  match state:
    case Disabled{}: (Disabled{}, None{})
    case State{_, _, _, Some{_}, _, _, _, _, _, _, _, _, _}: (state, None{})
    case State{+host, +port, +next, None{}, Queue{+job <> rest, code, lost}, loaded, blocked, first, +snapshot, mask, revision, explicit, dirty}:
      +started = stamp(job, next)
      (State{host, port, 1n+next, Some{started}, Queue{rest, code, lost}, loaded, blocked, first, snapshot, mask, revision, explicit, dirty && Bool.not(job_same(job, host, port) && job_snapshot(job, snapshot))}, Some{started})
    case State{_, _, _, None{}, Queue{Nil{}, _, _}, loaded, blocked, _, _, _, _, _, _}:
      take.read(Bool.not(loaded) && Bool.not(blocked), state)

def clear(state: State) -> State:
  match state:
    case Disabled{}: Disabled{}
    case State{host, port, next, _, queued, loaded, blocked, first, snapshot, mask, revision, explicit, dirty}:
      State{host, port, next, None{}, queued, loaded, blocked, first, snapshot, mask, revision, explicit, dirty}

def loaded.absent(state: State, +code: U32) -> Completion:
  match state:
    case Disabled{}: Completion{Disabled{}, None{}, False{}, False{}}
    case State{+host, +port, next, _, queued, _, _, +first, +snapshot, mask, revision, explicit, +dirty}:
      Completion{State{host, port, next, None{}, queue.lost(pending.first(U32.is_zero(code) && dirty, host, port, snapshot, queued), Bool.not(U32.is_zero(code)) && dirty), True{}, Bool.not(U32.is_zero(code)), False{}, snapshot, mask, revision, explicit, False{}}, None{}, False{}, True{}}

def loaded.present(state: State, +stored: P.Preferences, load_revision: Nat) -> Completion:
  match state:
    case Disabled{}: Completion{Disabled{}, None{}, False{}, False{}}
    case State{+host, +port, next, _, queued, _, _, first, snapshot, +mask, +revision, +explicit, dirty}:
      +keep = explicit || Bool.not(P.known_channels(stored)) || Bool.not(Nat.is_eq(revision, load_revision))
      +merged = merge(first, keep, mask, snapshot, stored)
      Completion{State{host, port, next, None{}, pending.first(dirty || Bool.not(equal(merged, stored)), host, port, merged, queued), True{}, False{}, False{}, merged, mask, revision, explicit, False{}}, Some{merged}, Bool.not(keep), True{}}

def loaded.current(got: Maybe<&2, P.Preferences>, state: State, code: U32, revision: Nat) -> Completion:
  match got:
    case None{}: loaded.absent(state, code)
    case Some{stored}: loaded.present(state, stored, revision)

def reconcile.present(stored: Maybe<&2, P.Preferences>, host: String, port: U32, baseline: Nat, prefs: P.Preferences, mask: Edits, +revision: Nat, +explicit: Bool, first: Bool) -> Maybe<&2, Job>:
  match stored:
    case None{}: Some{Write{0n, host, port, prefs}}
    case Some{+saved}:
      Some{Write{0n, host, port, merge(first, explicit || Bool.not(P.known_channels(saved)) || Bool.not(Nat.is_eq(revision, baseline)), mask, prefs, saved)}}

def reconcile.safe(ok: Bool, job: Job, stored: Maybe<&2, P.Preferences>) -> Maybe<&2, Job>:
  match ok:
    case False{}: None{}
    case True{}:
      match job:
        case Read{_, host, port, baseline, Deferred{prefs, mask, revision, explicit, first, _} <> Nil{}}:
          reconcile.present(stored, host, port, baseline, prefs, mask, revision, explicit, first)
        case _: None{}

def reconcile.queued(got: Maybe<&2, Job>, state: State) -> State:
  match got:
    case None{}: clear(state)
    case Some{job}:
      match state:
        case Disabled{}: Disabled{}
        case State{host, port, next, _, queued, loaded, blocked, first, snapshot, mask, revision, explicit, dirty}:
          State{host, port, next, None{}, queue.put_job(queued, job, True{}), loaded, blocked, first, snapshot, mask, revision, explicit, dirty}

def fail(state: State, on: Bool) -> State:
  match state:
    case Disabled{}: Disabled{}
    case State{h, p, n, a, q, l, b, f, s, m, r, e, d}: State{h, p, n, a, queue.lost(q, on), l, b, f, s, m, r, e, d}

def with_dirty(state: State, on: Bool) -> State:
  match state:
    case Disabled{}: Disabled{}
    case State{h, p, n, a, q, l, b, f, s, m, r, e, d}: State{h, p, n, a, q, l, b, f, s, m, r, e, d || on}

def job_revision(job: Job) -> Nat:
  match job:
    case Read{_, _, _, revision, _}: revision
    case _: 0n

def loaded.endpoint(current: Bool, state: State, got: Maybe<&2, P.Preferences>, +code: U32, +job: Job) -> Completion:
  match current:
    case False{}: Completion{fail(reconcile.queued(reconcile.safe(U32.is_zero(code) && queue.dirty(job), job, got), state), Bool.not(U32.is_zero(code)) && queue.dirty(job)), None{}, False{}, False{}}
    case True{}: loaded.current(got, with_dirty(state, queue.dirty(job)), code, job_revision(job))

def loaded.match(same_ticket: Bool, current: Bool, state: State, got: Maybe<&2, P.Preferences>, code: U32, job: Job) -> Completion:
  match same_ticket:
    case False{}: Completion{state, None{}, False{}, False{}}
    case True{}: loaded.endpoint(current, state, got, code, job)

def loaded(+state: State, +ticket: Nat, got: Maybe<&2, P.Preferences>, code: U32) -> Completion:
  match state:
    case Disabled{}: Completion{Disabled{}, None{}, False{}, False{}}
    case State{host, port, _, Some{Read{+owned, +read_host, +read_port, read_revision, deferred}}, _, _, _, _, _, _, _, _, _}:
      loaded.match(Nat.is_eq(ticket, owned), same(host, port, read_host, read_port), state, got, code, Read{owned, read_host, read_port, read_revision, deferred})
    case _: Completion{state, None{}, False{}, False{}}

def saved.match(same: Bool, state: State) -> State:
  match same:
    case False{}: state
    case True{}: clear(state)

def saved(+state: State, ticket: Nat) -> State:
  match state:
    case Disabled{}: Disabled{}
    case State{_, _, _, Some{Write{owned, _, _, _}}, _, _, _, _, _, _, _, _, _}:
      saved.match(Nat.is_eq(ticket, owned), state)
    case _: state

def write_current(state: State, +ticket: Nat) -> Bool:
  match state:
    case State{host, port, _, Some{Write{owned, h, p, _}}, _, _, _, _, _, _, _, _, _}: Nat.is_eq(ticket, owned) && same(host, port, h, p)
    case _: False{}

def saved.preserve(on: Bool, state: State) -> State:
  match on:
    case False{}: state
    case True{}:
      match state:
        case Disabled{}: Disabled{}
        case State{h, p, n, a, q, l, b, f, s, m, r, _, _}: State{h, p, n, a, q, l, b, f, s, m, r, True{}, True{}}

def saved_result(+state: State, +ticket: Nat, +code: U32) -> State:
  saved.preserve(write_current(state, ticket) && Bool.not(U32.is_zero(code)),
    fail(saved(state, ticket), owns_write(state, ticket) && Bool.not(U32.is_zero(code))))

# A read error without accepted edits is not a failed quit. Lost intent is.
def clean(state: State) -> Bool:
  match state:
    case Disabled{}: True{}
    case State{_, _, _, _, Queue{_, _, lost}, _, blocked, _, _, _, _, _, dirty}: Bool.not(lost || (blocked && dirty))

def queue_code(state: State) -> U32:
  match state:
    case State{_, _, _, _, Queue{_, code, _}, _, _, _, _, _, _, _, _}: code
    case _: 0

def active(state: State) -> Bool:
  match state:
    case State{_, _, _, Some{_}, _, _, _, _, _, _, _, _, _}: True{}
    case _: False{}

def queue_depth(state: State) -> Nat:
  match state:
    case State{_, _, _, _, Queue{jobs, _, _}, _, _, _, _, _, _, _, _}: List.length(&2, Job, jobs)
    case _: 0n

def clear_notice(state: State) -> State:
  match state:
    case Disabled{}: Disabled{}
    case State{h, p, n, a, Queue{jobs, _, lost}, l, b, f, s, m, r, e, d}: State{h, p, n, a, Queue{jobs, 0, lost}, l, b, f, s, m, r, e, d}

def no_job(pair: State & Maybe<&2, Job>) -> Bool:
  match pair:
    case (_, None{}): True{}
    case _: False{}

# Scan only option positions. Values may themselves look like flags.
def channel_explicit(xs: List<&2, String>) -> Bool:
  match xs:
    case "--channel" <> _: True{}
    case "--connect" <> _ <> t: channel_explicit(t)
    case "--port" <> _ <> t: channel_explicit(t)
    case "--nick" <> _ <> t: channel_explicit(t)
    case "--frames" <> _ <> t: channel_explicit(t)
    case "--replay" <> _ <> t: channel_explicit(t)
    case "--sasl-user" <> _ <> t: channel_explicit(t)
    case "--sasl-pass" <> _ <> t: channel_explicit(t)
    case "--nickserv-prefix" <> _ <> t: channel_explicit(t)
    case "--nickserv-success" <> _ <> t: channel_explicit(t)
    case _ <> t: channel_explicit(t)
    case Nil{}: False{}
