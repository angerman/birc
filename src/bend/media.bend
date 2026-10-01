# SPDX-License-Identifier: Apache-2.0
# Bounded view-only media policy. Bend owns request identity and scheduling.
import Base
import ./links.bend as Links
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

def image_closed(xs: List<&2, Links.Run>) -> Bool:
  match xs:
    case Con{Links.Run{0, SCon{Chr{41}, _}, None{}}, _}: True{}
    case _: False{}

def targets.keep(hit: Bool, url: String, tail: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}: url <> tail
    case False{}: tail

# Reuse the shared exact-URL lexer; code/styled opaque runs cannot trigger fetches.
def targets.go(xs: List<&2, Links.Run>, +previous: String) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Links.Run{+attrs, +text, url}, +tail}:
      match url:
        case None{}:
          targets.go(tail, Bool.pick(String, U32.is_eq(attrs, 0), previous ++ text, ""))
        case Some{+exact}:
          targets.keep(auto_url(exact) || (image_prefix.rev(String.reverse(previous)) && image_closed(tail)),
            exact, targets.go(tail, ""))

def targets(text: String) -> List<&2, String>:
  List.take(&2, String, targets.go(Links.render(text), ""), CAP())

type Target is Data:
  Inline{id: Nat}
  Manual{}

type Request is Data:
  Request{target: Target, url: String, generation: Nat, ticket: Nat}

type Ready is Data:
  Ready{target: Target, url: String, token: U32}

type State is Data:
  State{enabled: Bool, generation: Nat, ticket: Nat, active: Maybe<&2, Request>, pending: List<&2, Request>, ready: List<&2, Ready>}

def initial(on: Bool) -> State:
  State{on, 1n, 1n, None{}, Nil{}, Nil{}}

def empty() -> State:
  initial(False{})

def enabled(state: State) -> Bool:
  match state:
    case State{on, _, _, _, _, _}: on

def generation(state: State) -> Nat:
  match state:
    case State{_, gen, _, _, _, _}: gen

def pending_count(state: State) -> Nat:
  match state:
    case State{_, _, _, _, pending, _}: List.length(&2, Request, pending)

def ready_count(state: State) -> Nat:
  match state:
    case State{_, _, _, _, _, ready}: List.length(&2, Ready, ready)

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

def ready_matches(e: Ready, +target: Target, +url: String) -> Bool:
  match e:
    case Ready{t, u, _}: target_eq(t, target) && String.eq(u, url)

def ready_has(xs: List<&2, Ready>, +target: Target, +url: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}: ready_matches(h, target, url) || ready_has(t, target, url)

def ready_keep(hit: Bool, h: Ready, tail: List<&2, Ready>) -> List<&2, Ready>:
  match hit:
    case True{}: tail
    case False{}: h <> tail

def ready_without(xs: List<&2, Ready>, +target: Target, +url: String) -> List<&2, Ready>:
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
    case State{_, +gen, _, active, +pending, _}:
      Nat.is_ge(List.length(&2, Request, pending), CAP())
        && Bool.not(active_has(active, Manual{}, url, gen) || request_has(pending, Manual{}, url, gen))

def enqueue.on(hit: Bool, +state: State, +target: Target, +url: String) -> State:
  match hit:
    case False{}: state
    case True{}:
      match state:
        case State{on, +gen, +ticket, active, pending, +ready}:
          State{on, gen, (ticket + 1n : Nat), active, List.append(&2, Request, pending, [Request{target, url, gen, ticket}]),
            Bool.pick(List<&2, Ready>, manual(target), ready_without(ready, target, url), ready)}

def enqueue(+state: State, +target: Target, +url: String) -> State:
  match state:
    case State{+on, +gen, _, +active, +pending, +ready}:
      enqueue.on((on || manual(target)) && (manual(target) || Links.is_url_prefix(url))
        && Nat.is_lt(List.length(&2, Request, pending), CAP())
        && Bool.not(active_has(active, target, url, gen) || request_has(pending, target, url, gen))
        && (manual(target) || Bool.not(ready_has(ready, target, url))), state, target, url)

def enqueue_urls(urls: List<&2, String>, state: State, +target: Target) -> State:
  match urls:
    case Nil{}: state
    case Con{url, t}: enqueue_urls(t, enqueue(state, target, url), target)

def take_job(state: State) -> State & Maybe<&2, Request>:
  match state:
    case State{on, gen, ticket, Some{req}, pending, ready}:
      (State{on, gen, ticket, Some{req}, pending, ready}, None{})
    case State{on, gen, ticket, None{}, Nil{}, ready}:
      (State{on, gen, ticket, None{}, Nil{}, ready}, None{})
    case State{on, gen, ticket, None{}, Con{+req, pending}, ready}:
      (State{on, gen, ticket, Some{req}, pending, ready}, Some{req})

# The physical worker remains owned until its completion, even after disable/reset.
def reset(state: State) -> State:
  match state:
    case State{on, gen, ticket, active, _, _}: State{on, (gen + 1n : Nat), ticket, active, Nil{}, Nil{}}

def set_enabled.pick(change: Bool, +state: State, on: Bool) -> State:
  match change:
    case False{}: state
    case True{}:
      match state:
        case State{_, gen, ticket, active, _, _}: State{on, (gen + 1n : Nat), ticket, active, Nil{}, Nil{}}

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

def keep_ready(xs: List<&2, Ready>, +client: Cl.Client) -> List<&2, Ready>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}:
      match h:
        case Ready{target, url, _}: ready_keep(Bool.not(alive(client, target, url)), h, keep_ready(t, client))

def maintain(state: State, +client: Cl.Client) -> State:
  match state:
    case State{on, +gen, ticket, active, pending, ready}:
      State{on, gen, ticket, active, keep_pending(pending, client, gen), keep_ready(ready, client)}

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
    case State{on, current, _, +active, _, _}: exact(active, gen, ticket, url) && accept.active(active, on, current, client)

def complete.on(hit: Bool, accepted: Bool, +state: State, token: U32) -> State:
  match hit:
    case False{}: state
    case True{}:
      match state:
        case State{on, gen, ticket, Some{Request{target, url, _, _}}, pending, +ready}:
          State{on, gen, ticket, None{}, pending, Bool.pick(List<&2, Ready>, accepted,
            List.take(&2, Ready, Ready{target, url, token} <> ready, CAP()), ready)}
        case _: state

def complete(+state: State, +client: Cl.Client, +gen: Nat, +ticket: Nat, +url: String, token: U32) -> State:
  match state:
    case State{_, _, _, +active, _, _}:
      complete.on(exact(active, gen, ticket, url), accept(state, client, gen, ticket, url), state, token)

def token_from(xs: List<&2, Ready>, +target: Target, +url: String) -> U32:
  match xs:
    case Nil{}: 0
    case Con{+h, t}:
      match h:
        case Ready{_, _, +token}: Bool.pick(U32, ready_matches(h, target, url), token, token_from(t, target, url))

def token(state: State, target: Target, url: String) -> U32:
  match state:
    case State{_, _, _, _, _, ready}: token_from(ready, target, url)

def urls_ready(xs: List<&2, Ready>, +target: Target) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Ready{t, url, _}, tail}: targets.keep(target_eq(t, target), url, urls_ready(tail, target))

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
    case State{_, +gen, _, active, pending, ready}:
      List.append(&2, String, urls_ready(ready, target), List.append(&2, String,
        urls_active(active, target, gen), urls_pending(pending, target, gen)))

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
