# SPDX-License-Identifier: Apache-2.0
# Bounded view-only media policy. Bend owns request identity and scheduling.
import Base
import ./links.bend as Links
import ./wire_style.bend as Ws
import ./buffer.bend as Cl
import ./irc.bend as Irc

def CAP() -> Nat:
  8n

def path_part.keep(stop: Bool, h: Char, rest: String) -> String:
  match stop:
    case True{}: ""
    case False{}: SCon{h, rest}

# Query and fragment affect the request, never the extension classification.
def path_part(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+h, t}:
      path_part.keep(U32.is_eq(Char.to_u32(h), 63) || U32.is_eq(Char.to_u32(h), 35), h, path_part(t))

def suffix(+s: String, end: String) -> Bool:
  String.starts_with(String.reverse(s), String.reverse(end))

def auto_url(+url: String) -> Bool:
  +path = Irc.rfc1459(path_part(url))
  Links.is_url_prefix(url) && (suffix(path, ".PNG") || suffix(path, ".JPG")
    || suffix(path, ".JPEG") || suffix(path, ".GIF") || suffix(path, ".WEBP")
    || suffix(path, ".BMP") || suffix(path, ".TIF") || suffix(path, ".TIFF") || suffix(path, ".AVIF"))

def image_alt_rev(s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{Chr{91}, SCon{Chr{33}, _}}: True{}
    case SCon{Chr{91}, _}: False{}
    case SCon{_, t}: image_alt_rev(t)

def image_prefix.rev(s: String) -> Bool:
  match s:
    case SCon{Chr{40}, SCon{Chr{93}, t}}: image_alt_rev(t)
    case _: False{}

def image_closed(xs: List<&2, Ws.SRun>) -> Bool:
  match xs:
    case Con{Ws.SRun{0, _, _, SCon{Chr{41}, _}, None{}}, _}: True{}
    case _: False{}

# Compatibility delegator: same Ws.SRun close-paren verdict as image_closed.
def image_closed_runs(xs: List<&2, Ws.SRun>) -> Bool:
  image_closed(xs)

# Per-run media verdict shared with Cards: automatic image URLs plus explicit
# ![alt](url) intents. Cards walks the same runs and keeps the complement.
def media_run_hit(+previous: String, +exact: String, +tail: List<&2, Ws.SRun>) -> Bool:
  auto_url(exact) || (image_prefix.rev(String.reverse(previous)) && image_closed_runs(tail))

def targets.keep(hit: Bool, url: String, tail: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}: url <> tail
    case False{}: tail

# Consume the same boundary-aware runs the view paints and /open collects:
# style bytes split runs, so glued forgeries and style-infixed URLs never
# autofetch while genuine styled images still do.
def targets.go(xs: List<&2, Ws.SRun>, +previous: String) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Ws.SRun{+attrs, _, _, +text, url}, +tail}:
      match url:
        case None{}:
          targets.go(tail, Bool.pick(String, U32.is_eq(attrs, 0), previous ++ text, ""))
        case Some{+exact}:
          targets.keep(media_run_hit(previous, exact, tail),
            exact, targets.go(tail, ""))

def targets(text: String) -> List<&2, String>:
  List.take(&2, String, targets.go(Ws.url_runs(text), ""), CAP())

type Target is Data:
  Inline{id: Nat}
  Manual{}

type Candidate is Data:
  Candidate{target: Target, url: String}

type Request is Data:
  Request{target: Target, url: String, generation: Nat, ticket: Nat}

type MediaReady is Data:
  MediaReady{target: Target, url: String, token: U32}

# Terminal support is independent of the user's automatic-preview preference.
# Reported is sticky for the lifetime of an unsupported UI, including reconnect.
type Display is Data:
  Supported{}
  Unsupported{}
  Reported{}

type State is Data:
  State{enabled: Bool, generation: Nat, ticket: Nat, active: Maybe<&2, Request>, pending: List<&2, Request>, ready: List<&2, MediaReady>, display: Display}

def initial(on: Bool) -> State:
  State{on, 1n, 1n, None{}, Nil{}, Nil{}, Supported{}}

def empty() -> State:
  initial(False{})

def enabled(state: State) -> Bool:
  match state:
    case State{on, _, _, _, _, _, _}: on

def supported(state: State) -> Bool:
  match state:
    case State{_, _, _, _, _, _, Supported{}}: True{}
    case _: False{}

def reported(state: State) -> Bool:
  match state:
    case State{_, _, _, _, _, _, Reported{}}: True{}
    case _: False{}

def unsupported_text() -> String:
  "image previews disabled: terminal image protocol is unavailable"

def set_supported.display(on: Bool, display: Display) -> Display:
  match on:
    case True{}: Supported{}
    case False{}:
      match display:
        case Reported{}: Reported{}
        case _: Unsupported{}

# Install the opened UI's capability once, before any request is observed.
# If a worker is already owned, disabling support keeps it until completion.
def set_supported(+state: State, +on: Bool) -> State:
  match state:
    case State{enabled, +gen, ticket, active, pending, ready, display}:
      +changed = Bool.pick(Bool, on, Bool.not(supported(state)), supported(state))
      State{enabled, Bool.pick(Nat, changed, 1n+gen, gen), ticket, active,
        Bool.pick(List<&2, Request>, on, pending, Nil{}),
        Bool.pick(List<&2, MediaReady>, on, ready, Nil{}), set_supported.display(on, display)}

def generation(state: State) -> Nat:
  match state:
    case State{_, gen, _, _, _, _, _}: gen

def pending_count(state: State) -> Nat:
  match state:
    case State{_, _, _, _, pending, _, _}: List.length(&2, Request, pending)

def ready_count(state: State) -> Nat:
  match state:
    case State{_, _, _, _, _, ready, _}: List.length(&2, MediaReady, ready)

def bounded(+state: State) -> Bool:
  Nat.is_le(pending_count(state), CAP()) && Nat.is_le(ready_count(state), CAP())

def target_eq(a: Target, b: Target) -> Bool:
  match a:
    case Inline{+id}:
      match b:
        case Inline{other}: Nat.is_eq(id, other)
        case Manual{}: False{}
    case Manual{}:
      match b:
        case Inline{_}: False{}
        case Manual{}: True{}

def manual(target: Target) -> Bool:
  match target:
    case Manual{}: True{}
    case Inline{_}: False{}

def ready_matches(e: MediaReady, +target: Target, +url: String) -> Bool:
  match e:
    case MediaReady{t, u, _}: target_eq(t, target) && String.eq(u, url)

def ready_has(xs: List<&2, MediaReady>, +target: Target, +url: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}: ready_matches(h, target, url) || ready_has(t, target, url)

def ready_keep(hit: Bool, h: MediaReady, tail: List<&2, MediaReady>) -> List<&2, MediaReady>:
  match hit:
    case True{}: tail
    case False{}: h <> tail

def ready_without(xs: List<&2, MediaReady>, +target: Target, +url: String) -> List<&2, MediaReady>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}: ready_keep(ready_matches(h, target, url), h, ready_without(t, target, url))

def request_matches(req: Request, +target: Target, +url: String, +gen: Nat) -> Bool:
  match req:
    case Request{t, u, g, _}: target_eq(t, target) && String.eq(u, url) && Nat.is_eq(g, gen)

def request_has(xs: List<&2, Request>, +target: Target, +url: String, +gen: Nat) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}: request_matches(h, target, url, gen) || request_has(t, target, url, gen)

def active_has(active: Maybe<&2, Request>, +target: Target, +url: String, +gen: Nat) -> Bool:
  match active:
    case None{}: False{}
    case Some{req}: request_matches(req, target, url, gen)

def manual_saturated(state: State, +url: String) -> Bool:
  match state:
    case State{_, +gen, _, active, +pending, _, _}:
      Nat.is_ge(List.length(&2, Request, pending), CAP())
        && Bool.not(active_has(active, Manual{}, url, gen) || request_has(pending, Manual{}, url, gen))

def enqueue.on(hit: Bool, +state: State, +target: Target, +url: String) -> State:
  match hit:
    case False{}: state
    case True{}:
      match state:
        case State{on, +gen, +ticket, active, pending, +ready, display}:
          State{on, gen, (ticket + 1n : Nat), active, List.append(&2, Request, pending, [Request{target, url, gen, ticket}]),
            Bool.pick(List<&2, MediaReady>, manual(target), ready_without(ready, target, url), ready), display}

def enqueue.eligible(eligible: Bool, +state: State, +target: Target, +url: String) -> State:
  match eligible:
    case False{}: state
    case True{}:
      match state:
        case State{+on, +gen, +ticket, +active, +pending, +ready, Supported{}}:
          enqueue.on(Nat.is_lt(List.length(&2, Request, pending), CAP())
            && Bool.not(active_has(active, target, url, gen) || request_has(pending, target, url, gen))
            && (manual(target) || Bool.not(ready_has(ready, target, url))),
            State{on, gen, ticket, active, pending, ready, Supported{}}, target, url)
        case State{on, gen, ticket, active, _, _, _}:
          State{on, gen, ticket, active, Nil{}, Nil{}, Reported{}}

def enqueue_allowed(+state: State, +target: Target, +url: String) -> Bool:
  (enabled(state) || manual(target)) && Bool.not(String.is_empty(url))
    && (manual(target) || Links.is_url_prefix(url))

def enqueue(+state: State, +target: Target, +url: String) -> State:
  enqueue.eligible(enqueue_allowed(state, target, url), state, target, url)

def enqueue_urls(urls: List<&2, String>, state: State, +target: Target) -> State:
  match urls:
    case Nil{}: state
    case Con{url, t}: enqueue_urls(t, enqueue(state, target, url), target)

def enqueue_candidates.go(xs: List<&2, Candidate>, state: State) -> State:
  match xs:
    case Nil{}: state
    case Con{Candidate{target, url}, tail}: enqueue_candidates.go(tail, enqueue(state, target, url))

def candidate_id(candidate: Candidate) -> Nat:
  match candidate:
    case Candidate{Inline{id}, _}: id
    case _: 0n

def candidate_newest(a: Candidate, b: Candidate) -> Bool:
  Nat.is_ge(candidate_id(a), candidate_id(b))

def candidate_known(state: State, candidate: Candidate) -> Bool:
  match state:
    case State{_, +gen, _, active, pending, ready, Supported{}}:
      match candidate:
        case Candidate{+target, +url}:
          ready_has(ready, target, url) || active_has(active, target, url, gen)
            || request_has(pending, target, url, gen)
    case _: False{}

def candidate_partition.keep(keep: Bool, candidate: Candidate, tail: List<&2, Candidate>) -> List<&2, Candidate>:
  match keep:
    case False{}: tail
    case True{}: candidate <> tail

def candidate_partition(xs: List<&2, Candidate>, +state: State, +keep_known: Bool) -> List<&2, Candidate>:
  match xs:
    case Nil{}: Nil{}
    case Con{+head, tail}:
      +known = candidate_known(state, head)
      candidate_partition.keep((known && keep_known) || (Bool.not(known) && Bool.not(keep_known)),
        head, candidate_partition(tail, state, keep_known))

def candidate_has(xs: List<&2, Candidate>, +target: Target, +url: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Candidate{t, u}, tail}: (target_eq(t, target) && String.eq(u, url)) || candidate_has(tail, target, url)

def newest_candidates.unique.keep(duplicate: Bool, +candidate: Candidate, +seen: List<&2, Candidate>, k: List<&2, Candidate> -> List<&2, Candidate>) -> List<&2, Candidate>:
  match duplicate:
    case True{}: k(seen)
    case False{}: candidate <> k(candidate <> seen)

def newest_candidates.unique(xs: List<&2, Candidate>, +seen: List<&2, Candidate>) -> List<&2, Candidate>:
  match xs:
    case Nil{}: Nil{}
    case Con{Candidate{+target, +url}, tail}:
      newest_candidates.unique.keep(candidate_has(seen, target, url), Candidate{target, url}, seen,
        next => newest_candidates.unique(tail, next))

# Retain visible previews before admitting new ones. In split panes, expansion
# must not let fresh text evict a visible token and repeatedly collapse/refetch it.
def newest_candidates(+xs: List<&2, Candidate>, +state: State) -> List<&2, Candidate>:
  List.take(&2, Candidate, newest_candidates.unique(List.append(&2, Candidate,
    List.sort(~Candidate, ~candidate_newest, candidate_partition(xs, state, True{})),
    List.sort(~Candidate, ~candidate_newest, candidate_partition(xs, state, False{}))), Nil{}), CAP())

def visible_ready(xs: List<&2, MediaReady>, +selected: List<&2, Candidate>, +keep_selected: Bool) -> List<&2, MediaReady>:
  match xs:
    case Nil{}: Nil{}
    case Con{MediaReady{+target, +url, token}, tail}:
      +hit = candidate_has(selected, target, url)
      ready_keep(Bool.not((hit && keep_selected) || (Bool.not(hit) && Bool.not(keep_selected))),
        MediaReady{target, url, token}, visible_ready(tail, selected, keep_selected))

# The completion FIFO remains unchanged. Refresh its bounded priority only for
# this visible-admission path, so a new preview evicts a hidden result first.
def enqueue_candidates(+xs: List<&2, Candidate>, state: State) -> State:
  match state:
    case State{on, gen, ticket, active, pending, +ready, display}:
      enqueue_candidates.go(xs, State{on, gen, ticket, active, pending,
        List.append(&2, MediaReady, visible_ready(ready, xs, True{}), visible_ready(ready, xs, False{})), display})

def visible_result.active(active: Maybe<&2, Request>, +selected: List<&2, Candidate>) -> Bool:
  match active:
    case None{}: False{}
    case Some{Request{+target, url, _, _}}: manual(target) || candidate_has(selected, target, url)

# A full visible cache must not be displaced by an unrelated hidden completion.
# Manual requests are explicit user intent, including automatic previews off.
# Token-zero failures occupy the same identities and must not cause retry loops.
def visible_result_allowed(state: State, +selected: List<&2, Candidate>) -> Bool:
  match state:
    case State{_, _, _, active, _, ready, _}:
      Nat.is_lt(List.length(&2, MediaReady, visible_ready(ready, selected, True{})), CAP())
        || visible_result.active(active, selected)

def take_job(state: State) -> State & Maybe<&2, Request>:
  match state:
    case State{on, gen, ticket, active, _, _, Unsupported{}}:
      (State{on, gen, ticket, active, Nil{}, Nil{}, Unsupported{}}, None{})
    case State{on, gen, ticket, active, _, _, Reported{}}:
      (State{on, gen, ticket, active, Nil{}, Nil{}, Reported{}}, None{})
    case State{on, gen, ticket, Some{req}, pending, ready, Supported{}}:
      (State{on, gen, ticket, Some{req}, pending, ready, Supported{}}, None{})
    case State{on, gen, ticket, None{}, Nil{}, ready, Supported{}}:
      (State{on, gen, ticket, None{}, Nil{}, ready, Supported{}}, None{})
    case State{on, gen, ticket, None{}, Con{+req, pending}, ready, Supported{}}:
      (State{on, gen, ticket, Some{req}, pending, ready, Supported{}}, Some{req})

def take_job_allowed(allowed: Bool, state: State) -> State & Maybe<&2, Request>:
  match allowed:
    case False{}: (state, None{})
    case True{}: take_job(state)

# The physical worker remains owned until its completion, even after disable/reset.
def reset(state: State) -> State:
  match state:
    case State{on, gen, ticket, active, _, _, display}: State{on, (gen + 1n : Nat), ticket, active, Nil{}, Nil{}, display}

def set_enabled.pick(change: Bool, +state: State, on: Bool) -> State:
  match change:
    case False{}: state
    case True{}:
      match state:
        case State{_, gen, ticket, active, _, _, display}: State{on, (gen + 1n : Nat), ticket, active, Nil{}, Nil{}, display}

def set_enabled(+state: State, +on: Bool) -> State:
  set_enabled.pick(Bool.pick(Bool, on, Bool.not(enabled(state)), enabled(state)), state, on)

def lines_have_id(xs: List<&2, Cl.Line>, +id: Nat) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Cl.Line{_, _, _, _, n}, t}: Nat.is_eq(n, id) || lines_have_id(t, id)

def target_in_buf(target: Target, +url: String, buf: Cl.Buffer) -> Bool:
  match target:
    case Inline{id}:
      match buf:
        case Cl.Buffer{_, _, _, lines, _, _}: lines_have_id(lines, id)
    case Manual{}:
      match buf:
        case Cl.Buffer{name, _, topic, _, _, _}: String.eq(name, "*preview*") && String.eq(topic, url)

def target_in_bufs(bufs: List<&2, Cl.Buffer>, +target: Target, +url: String) -> Bool:
  match bufs:
    case Nil{}: False{}
    case Con{buf, tail}: target_in_buf(target, url, buf) || target_in_bufs(tail, target, url)

def alive(+client: Cl.Client, target: Target, url: String) -> Bool:
  target_in_bufs(Cl.client_bufs(client), target, url)

def pending_keep(hit: Bool, h: Request, tail: List<&2, Request>) -> List<&2, Request>:
  match hit:
    case True{}: h <> tail
    case False{}: tail

def keep_pending(xs: List<&2, Request>, +client: Cl.Client, +gen: Nat) -> List<&2, Request>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}:
      match h:
        case Request{target, url, g, _}:
          pending_keep(Nat.is_eq(g, gen) && alive(client, target, url), h, keep_pending(t, client, gen))

def keep_ready(xs: List<&2, MediaReady>, +client: Cl.Client) -> List<&2, MediaReady>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}:
      match h:
        case MediaReady{target, url, _}: ready_keep(Bool.not(alive(client, target, url)), h, keep_ready(t, client))

def maintain(state: State, +client: Cl.Client) -> State:
  match state:
    case State{on, +gen, ticket, active, pending, ready, display}:
      State{on, gen, ticket, active, keep_pending(pending, client, gen), keep_ready(ready, client), display}

def exact(active: Maybe<&2, Request>, +gen: Nat, +ticket: Nat, +url: String) -> Bool:
  match active:
    case None{}: False{}
    case Some{Request{_, u, g, t}}: Nat.is_eq(g, gen) && Nat.is_eq(t, ticket) && String.eq(u, url)

def accept.active(active: Maybe<&2, Request>, +on: Bool, +gen: Nat, +client: Cl.Client) -> Bool:
  match active:
    case None{}: False{}
    case Some{Request{+target, url, g, _}}: Nat.is_eq(g, gen) && (on || manual(target)) && alive(client, target, url)

def accept(state: State, +client: Cl.Client, +gen: Nat, +ticket: Nat, +url: String) -> Bool:
  match state:
    case State{on, current, _, +active, _, _, Supported{}}: exact(active, gen, ticket, url) && accept.active(active, on, current, client)
    case _: False{}

def complete.on(hit: Bool, accepted: Bool, +state: State, token: U32) -> State:
  match hit:
    case False{}: state
    case True{}:
      match state:
        case State{on, gen, ticket, Some{Request{target, url, _, _}}, pending, +ready, display}:
          State{on, gen, ticket, None{}, pending, Bool.pick(List<&2, MediaReady>, accepted,
            List.take(&2, MediaReady, MediaReady{target, url, token} <> ready, CAP()), ready), display}
        case _: state

def complete(+state: State, +client: Cl.Client, +gen: Nat, +ticket: Nat, +url: String, token: U32) -> State:
  match state:
    case State{_, _, _, +active, _, _, _}:
      complete.on(exact(active, gen, ticket, url), accept(state, client, gen, ticket, url), state, token)

# Declined native admission releases only the exact physical worker. It cannot
# add a failed placeholder, evict a retained token, or clear a different worker.
def reject(+state: State, +gen: Nat, +ticket: Nat, +url: String) -> State:
  match state:
    case State{_, _, _, +active, _, _, _}:
      complete.on(exact(active, gen, ticket, url), False{}, state, 0)

# Full-budget native rejection records a token-zero failed identity for the
# exact worker, so observe/enqueue/take does not immediately relaunch the
# same automatic helper while every native slot stays owned. Wrong
# ticket/generation/URL arrivals keep the owner untouched; disabled and
# dead targets record nothing; manual intents still retry via enqueue.
def reject_full(+state: State, +client: Cl.Client, +gen: Nat, +ticket: Nat, +url: String) -> State:
  complete(state, client, gen, ticket, url, 0)

# Zero denotes a placeholder, never native payload ownership. Compute this on
# the prospective completion with token zero before admitting its new payload.
def retained_tokens.ready(xs: List<&2, MediaReady>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{MediaReady{_, _, +token}, tail}:
      match token:
        case 0: retained_tokens.ready(tail)
        case _: token <> retained_tokens.ready(tail)

def retained_tokens(state: State) -> List<&2, U32>:
  match state:
    case State{_, _, _, _, _, ready, Supported{}}: retained_tokens.ready(ready)
    case _: Nil{}

def token_from(xs: List<&2, MediaReady>, +target: Target, +url: String) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+h, t}:
      match h:
        case MediaReady{_, _, +token}: Bool.pick(U32, ready_matches(h, target, url), token, token_from(t, target, url))

def token(state: State, target: Target, url: String) -> U32:
  match state:
    case State{_, _, _, _, _, ready, Supported{}}: token_from(ready, target, url)
    case _: 0

# Fullscreen entry target (C8 live): the newest ready result with an accepted
# nonzero token whose source is still live. Ready is newest-first, so the head
# hit wins. Unsupported terminals pick nothing; callers revalidate anyway.
def fullscreen_pick.keep(hit: Bool, h: MediaReady, rest: Maybe<&2, MediaReady>) -> Maybe<&2, MediaReady>:
  match hit:
    case True{}: Some{h}
    case False{}: rest

def fullscreen_pick.go(xs: List<&2, MediaReady>, +client: Cl.Client) -> Maybe<&2, MediaReady>:
  match xs:
    case Nil{}: None{}
    case Con{+h, t}:
      match h:
        case MediaReady{+target, +url, +token}:
          fullscreen_pick.keep(Bool.not(U32.is_zero(token)) && alive(client, target, url), h, fullscreen_pick.go(t, client))

def fullscreen_pick(+state: State, +client: Cl.Client) -> Maybe<&2, MediaReady>:
  match state:
    case State{_, _, _, _, _, ready, Supported{}}: fullscreen_pick.go(ready, client)
    case _: None{}

def urls_ready(xs: List<&2, MediaReady>, +target: Target) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{MediaReady{t, url, _}, tail}: targets.keep(target_eq(t, target), url, urls_ready(tail, target))

def urls_pending(xs: List<&2, Request>, +target: Target, +gen: Nat) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Request{t, url, g, _}, tail}: targets.keep(target_eq(t, target) && Nat.is_eq(g, gen), url, urls_pending(tail, target, gen))

def urls_active(active: Maybe<&2, Request>, target: Target, gen: Nat) -> List<&2, String>:
  match active:
    case None{}: Nil{}
    case Some{req}: urls_pending([req], target, gen)

def known_urls(state: State, +target: Target) -> List<&2, String>:
  match state:
    case State{_, +gen, _, active, pending, ready, Supported{}}:
      List.append(&2, String, urls_ready(ready, target), List.append(&2, String,
        urls_active(active, target, gen), urls_pending(pending, target, gen)))
    case _: Nil{}

def live_kind(kind: Cl.LineKind) -> Bool:
  match kind:
    case Cl.Msg{}: True{}
    case Cl.Self{}: True{}
    case Cl.Highlight{}: True{}
    case Cl.Action{}: True{}
    case _: False{}

def observe_line.pick(hit: Bool, +state: State, id: Nat, text: String) -> State:
  match hit:
    case False{}: state
    case True{}: enqueue_urls(targets(text), state, Inline{id})

def observe_lines(xs: List<&2, Cl.Line>, state: State, +after: Nat) -> State:
  match xs:
    case Nil{}: state
    case Con{Cl.Line{kind, _, text, _, +id}, tail}:
      observe_lines(tail, observe_line.pick(Nat.is_gt(id, after) && live_kind(kind), state, id, text), after)

def observe_bufs(bufs: List<&2, Cl.Buffer>, state: State, +after: Nat) -> State:
  match bufs:
    case Nil{}: state
    case Con{Cl.Buffer{_, _, _, lines, _, _}, tail}: observe_bufs(tail, observe_lines(lines, state, after), after)

def observe.pick(online: Bool, +state: State, +client: Cl.Client, after: Nat) -> State:
  match online:
    case False{}: maintain(state, client)
    case True{}: observe_bufs(Cl.client_bufs(client), maintain(state, client), after)

def observe(state: State, +client: Cl.Client, after: Nat, online: Bool) -> State:
  observe.pick(online, state, client, after)
