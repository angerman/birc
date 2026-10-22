# SPDX-License-Identifier: Apache-2.0
# Bounded view-only OpenGraph cards plus fullscreen image policy (pure).
# Text cards render on every terminal; only fullscreen and thumbnails need
# terminal image support. The helper owns fetching; Bend owns scheduling.
import Base
import ./links.bend as Links
import ./wire_style.bend as Ws
import ./buffer.bend as Cl
import ./split.bend as Sp
import ./media.bend as M
import ./view.bend as V

def CAP() -> Nat:
  8n

def TITLE_MAX() -> Nat:
  128n

def DESC_MAX() -> Nat:
  256n

def URL_MAX() -> Nat:
  1024n

def ROWS_MAX() -> Nat:
  4n

def MANUAL_BUF() -> String:
  "*card*"

def has_del.go(s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{+h, t}: U32.is_eq(Char.to_u32(h), 127) || has_del.go(t)

# The shared lexer already splits on bytes <= 32; only DEL can remain.
def has_del(+s: String) -> Bool:
  has_del.go(s)

# Cards are public-HTTPS only, like the helper's initial and redirect policy.
# Plaintext pages never schedule; plaintext thumbnails stay text-only below.
def is_https(+s: String) -> Bool:
  String.starts_with(s, "https://")

# Pure subset of the helper checks. Image URLs stay on the media worker;
# the helper enforces ports, credentials, content type, and size fail-closed.
def eligible_url(+url: String) -> Bool:
  is_https(url) && Bool.not(M.auto_url(url))
    && Bool.not(String.is_empty(url)) && Nat.is_le(String.length(url), URL_MAX())
    && Bool.not(has_del(url))

def targets_keep(hit: Bool, url: String, tail: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}: url <> tail
    case False{}: tail

# One walk over the shared boundary-aware runs: exact chat URLs minus the run
# the media worker owns (automatic images and explicit ![alt](url) intents via
# the shared per-run verdict). A bare duplicate of an image-intent URL keeps
# its own card run; flattened string exclusion would drop it. Code and styled
# runs stay opaque via Ws; style-infixed and SOH-glued links degrade first.
def targets_go(xs: List<&2, Ws.SRun>, +previous: String) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Ws.SRun{+attrs, _, _, +text, url}, +tail}:
      match url:
        case None{}:
          targets_go(tail, Bool.pick(String, U32.is_eq(attrs, 0), previous ++ text, ""))
        case Some{+exact}:
          targets_keep(eligible_url(exact) && Bool.not(M.media_run_hit(previous, exact, tail)),
            exact, targets_go(tail, ""))

def targets(+text: String) -> List<&2, String>:
  List.take(&2, String, targets_go(Ws.url_runs(text), ""), CAP())

type Fields is Data:
  Fields{title: String, desc: String, image: String}

def fields_title(f: Fields) -> String:
  match f:
    case Fields{+title, _, _}: title

def fields_desc(f: Fields) -> String:
  match f:
    case Fields{_, +desc, _}: desc

def fields_image(f: Fields) -> String:
  match f:
    case Fields{_, _, +image}: image

def field_at(xs: List<&2, String>, +n: Nat) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, t}:
      match n:
        case 0n: h
        case 1n+p: field_at(t, p)

# A card thumbnail reference must be absolute HTTPS; anything else stays a
# text-only card. Empty means no thumbnail, never a raw-file fallback.
# Overlong references are rejected, never truncated to a different URL.
def clean_image(+url: String) -> String:
  Bool.pick(String, is_https(url) && Nat.is_le(String.length(url), URL_MAX())
    && Bool.not(has_del(url)), url, "")

# The helper prints title, description, image on three sanitized single lines.
# Missing lines are empty; overlong lines truncate to character bounds.
def parse(+payload: String) -> Fields:
  +xs = String.split(payload, Chr{10})
  Fields{String.take(field_at(xs, 0n), TITLE_MAX()),
    String.take(field_at(xs, 1n), DESC_MAX()), clean_image(field_at(xs, 2n))}

type Target is Data:
  CardInline{id: Nat}
  CardManual{}

type Candidate is Data:
  Candidate{target: Target, url: String}

type Request is Data:
  Request{target: Target, url: String, generation: Nat, ticket: Nat}

type CardReady is Data:
  CardReady{target: Target, url: String, title: String, desc: String, image: String}

# Text cards need no terminal image protocol, so there is no display gate.
# Fullscreen below reuses Media support instead of a second report path.
type State is Data:
  State{enabled: Bool, generation: Nat, ticket: Nat, active: Maybe<&2, Request>,
    pending: List<&2, Request>, ready: List<&2, CardReady>}

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

def active_target(+state: State) -> Maybe<&2, Target>:
  match state:
    case State{_, _, _, active, _, _}:
      match active:
        case None{}: None{}
        case Some{Request{+target, _, _, _}}: Some{target}

def pending_count(state: State) -> Nat:
  match state:
    case State{_, _, _, _, pending, _}: List.length(&2, Request, pending)

def ready_count(state: State) -> Nat:
  match state:
    case State{_, _, _, _, _, ready}: List.length(&2, CardReady, ready)

def bounded(+state: State) -> Bool:
  Nat.is_le(pending_count(state), CAP()) && Nat.is_le(ready_count(state), CAP())

def target_eq(a: Target, b: Target) -> Bool:
  match a:
    case CardInline{+id}:
      match b:
        case CardInline{other}: Nat.is_eq(id, other)
        case CardManual{}: False{}
    case CardManual{}:
      match b:
        case CardInline{_}: False{}
        case CardManual{}: True{}

def manual(target: Target) -> Bool:
  match target:
    case CardManual{}: True{}
    case CardInline{_}: False{}

def ready_title(r: CardReady) -> String:
  match r:
    case CardReady{_, _, +title, _, _}: title

def ready_matches(e: CardReady, +target: Target, +url: String) -> Bool:
  match e:
    case CardReady{t, u, _, _, _}: target_eq(t, target) && String.eq(u, url)

def ready_has(xs: List<&2, CardReady>, +target: Target, +url: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}: ready_matches(h, target, url) || ready_has(t, target, url)

def ready_keep(hit: Bool, h: CardReady, tail: List<&2, CardReady>) -> List<&2, CardReady>:
  match hit:
    case True{}: tail
    case False{}: h <> tail

def ready_without(xs: List<&2, CardReady>, +target: Target, +url: String) -> List<&2, CardReady>:
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
        && Bool.not(active_has(active, CardManual{}, url, gen) || request_has(pending, CardManual{}, url, gen))

def enqueue.on(hit: Bool, +state: State, +target: Target, +url: String) -> State:
  match hit:
    case False{}: state
    case True{}:
      match state:
        case State{on, +gen, +ticket, active, pending, +ready}:
          State{on, gen, (ticket + 1n : Nat), active, List.append(&2, Request, pending, [Request{target, url, gen, ticket}]),
            Bool.pick(List<&2, CardReady>, manual(target), ready_without(ready, target, url), ready)}

def enqueue.eligible(eligible: Bool, +state: State, +target: Target, +url: String) -> State:
  match eligible:
    case False{}: state
    case True{}:
      match state:
        case State{on, +gen, +ticket, +active, +pending, +ready}:
          enqueue.on(Nat.is_lt(List.length(&2, Request, pending), CAP())
            && Bool.not(active_has(active, target, url, gen) || request_has(pending, target, url, gen))
            && (manual(target) || Bool.not(ready_has(ready, target, url))),
            State{on, gen, ticket, active, pending, ready}, target, url)

# Manual sources mirror Media: any nonempty path or URL, helper-validated.
def enqueue_allowed(+state: State, +target: Target, +url: String) -> Bool:
  (enabled(state) || manual(target)) && Bool.not(String.is_empty(url))
    && (manual(target) || eligible_url(url))

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
    case Candidate{CardInline{id}, _}: id
    case _: 0n

def candidate_newest(a: Candidate, b: Candidate) -> Bool:
  Nat.is_ge(candidate_id(a), candidate_id(b))

def candidate_has(xs: List<&2, Candidate>, +target: Target, +url: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Candidate{t, u}, tail}: (target_eq(t, target) && String.eq(u, url)) || candidate_has(tail, target, url)

def dedup.keep(duplicate: Bool, +candidate: Candidate, +seen: List<&2, Candidate>, k: List<&2, Candidate> -> List<&2, Candidate>) -> List<&2, Candidate>:
  match duplicate:
    case True{}: k(seen)
    case False{}: candidate <> k(candidate <> seen)

def dedup(xs: List<&2, Candidate>, +seen: List<&2, Candidate>) -> List<&2, Candidate>:
  match xs:
    case Nil{}: Nil{}
    case Con{Candidate{+target, +url}, tail}:
      dedup.keep(candidate_has(seen, target, url), Candidate{target, url}, seen,
        next => dedup(tail, next))

# Text completions are cheap and carry no native token, so visible admission
# needs newest-first dedup only, not the media visible/hidden partition.
def newest(+xs: List<&2, Candidate>) -> List<&2, Candidate>:
  List.take(&2, Candidate, dedup(List.sort(~Candidate, ~candidate_newest, xs), Nil{}), CAP())

def enqueue_candidates(+xs: List<&2, Candidate>, state: State) -> State:
  enqueue_candidates.go(newest(xs), state)

def take_job(state: State) -> State & Maybe<&2, Request>:
  match state:
    case State{on, gen, ticket, Some{req}, pending, ready}:
      (State{on, gen, ticket, Some{req}, pending, ready}, None{})
    case State{on, gen, ticket, None{}, Nil{}, ready}:
      (State{on, gen, ticket, None{}, Nil{}, ready}, None{})
    case State{on, gen, ticket, None{}, Con{+req, pending}, ready}:
      (State{on, gen, ticket, Some{req}, pending, ready}, Some{req})

def take_job_allowed(allowed: Bool, state: State) -> State & Maybe<&2, Request>:
  match allowed:
    case False{}: (state, None{})
    case True{}: take_job(state)

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
    case CardInline{id}:
      match buf:
        case Cl.Buffer{_, _, _, lines, _, _, _, _}: lines_have_id(lines, id)
    case CardManual{}:
      match buf:
        case Cl.Buffer{name, _, topic, _, _, _, _, _}: String.eq(name, MANUAL_BUF()) && String.eq(topic, url)

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

def keep_ready(xs: List<&2, CardReady>, +client: Cl.Client) -> List<&2, CardReady>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}:
      match h:
        case CardReady{target, url, _, _, _}: ready_keep(Bool.not(alive(client, target, url)), h, keep_ready(t, client))

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

# Accepted completions always occupy their identity, even with empty fields,
# so helper failures cannot cause retry loops. Stale results only release.
def complete.on(hit: Bool, accepted: Bool, +state: State, +fields: Fields) -> State:
  match hit:
    case False{}: state
    case True{}:
      match state:
        case State{on, gen, ticket, Some{Request{target, url, _, _}}, pending, +ready}:
          match fields:
            case Fields{+title, +desc, +image}:
              State{on, gen, ticket, None{}, pending, Bool.pick(List<&2, CardReady>, accepted,
                List.take(&2, CardReady, CardReady{target, url, title, desc, image} <> ready, CAP()), ready)}
        case _: state

def complete(+state: State, +client: Cl.Client, +gen: Nat, +ticket: Nat, +url: String, +payload: String) -> State:
  match state:
    case State{_, _, _, +active, _, _}:
      complete.on(exact(active, gen, ticket, url), accept(state, client, gen, ticket, url), state, parse(payload))

def reject(+state: State, +gen: Nat, +ticket: Nat, +url: String) -> State:
  match state:
    case State{_, _, _, +active, _, _}:
      complete.on(exact(active, gen, ticket, url), False{}, state, Fields{"", "", ""})

def card_for.pick(hit: Bool, +h: CardReady, rest: Maybe<&2, CardReady>) -> Maybe<&2, CardReady>:
  match hit:
    case True{}: Some{h}
    case False{}: rest

def card_for(xs: List<&2, CardReady>, +target: Target, +url: String) -> Maybe<&2, CardReady>:
  match xs:
    case Nil{}: None{}
    case Con{+h, t}: card_for.pick(ready_matches(h, target, url), h, card_for(t, target, url))

def card(state: State, target: Target, url: String) -> Maybe<&2, CardReady>:
  match state:
    case State{_, _, _, _, _, ready}: card_for(ready, target, url)

def urls_keep(hit: Bool, url: String, tail: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}: url <> tail
    case False{}: tail

def urls_ready(xs: List<&2, CardReady>, +target: Target) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{CardReady{t, url, _, _, _}, tail}: urls_keep(target_eq(t, target), url, urls_ready(tail, target))

def urls_pending(xs: List<&2, Request>, +target: Target, +gen: Nat) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Request{t, url, g, _}, tail}: urls_keep(target_eq(t, target) && Nat.is_eq(g, gen), url, urls_pending(tail, target, gen))

def urls_active(active: Maybe<&2, Request>, target: Target, gen: Nat) -> List<&2, String>:
  match active:
    case None{}: Nil{}
    case Some{req}: urls_pending([req], target, gen)

def known_urls(state: State, +target: Target) -> List<&2, String>:
  match state:
    case State{_, +gen, _, active, pending, ready}:
      List.append(&2, String, urls_ready(ready, target), List.append(&2, String,
        urls_active(active, target, gen), urls_pending(pending, target, gen)))

# Scheduling consumes bounded visible candidates only (visible_candidates):
# exact panes, rows, mutes, anchors, eligibility, and media exclusion are
# settled there. There is no all-buffer scan; unlisted buffers never schedule.
# Integrator: replace the old (client, after, online) call with
# observe(state, client, visible_candidates(client, rows, cols, split, media), online).
def observe.pick(online: Bool, +state: State, +client: Cl.Client, +candidates: List<&2, Candidate>) -> State:
  match online:
    case False{}: maintain(state, client)
    case True{}: enqueue_candidates(candidates, maintain(state, client))

def observe(+state: State, +client: Cl.Client, +candidates: List<&2, Candidate>, online: Bool) -> State:
  observe.pick(online, state, client, candidates)

# ---- View adapters (synthetic rows only; Client and history stay raw) ----

def nonempty.keep(empty: Bool, +h: String, tail: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}: tail
    case False{}: h <> tail

def nonempty(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}: nonempty.keep(String.is_empty(h), h, nonempty(t))

# The empty-title URL fallback fires only when a description keeps the card
# text-bearing: all-empty cards yield no texts (zero rows in both cascades),
# while image-only cards keep their single thumbnail row.
def card_texts(r: CardReady) -> List<&2, String>:
  match r:
    case CardReady{_, +url, +title, +desc, +image}:
      nonempty([Bool.pick(String, String.is_empty(title),
        Bool.pick(String, String.is_empty(desc), "", url), title), desc,
        Bool.pick(String, String.is_empty(image), "", "image: " ++ image)])

def rows_for_texts(xs: List<&2, String>, +w: U32) -> List<&2, V.BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}: List.append(&2, V.BodyRow, V.wrapped_rows(Cl.System{}, "", h, w, False{}), rows_for_texts(t, w))

# One ready card paints at most ROWS_MAX dim text rows. The image reference
# linkifies through render_spans; thumbnails stay on the media worker.
def rows_for(+r: CardReady, +w: U32) -> List<&2, V.BodyRow>:
  List.take(&2, V.BodyRow, rows_for_texts(card_texts(r), w), ROWS_MAX())

def rows_for_target.maybe(m: Maybe<&2, CardReady>, +w: U32) -> List<&2, V.BodyRow>:
  match m:
    case None{}: Nil{}
    case Some{+r}: rows_for(r, w)

def rows_for_target(state: State, +target: Target, +url: String, +w: U32) -> List<&2, V.BodyRow>:
  rows_for_target.maybe(card(state, target, url), w)

def ready_target(r: CardReady) -> Target:
  match r:
    case CardReady{+target, _, _, _, _}: target

def paint_entries.entry(target: Target, +texts: List<&2, String>, tail: List<&2, V.CardEntry>) -> List<&2, V.CardEntry>:
  match target:
    case CardInline{id}: V.CardEntry{id, texts} <> tail
    case CardManual{}: tail

def paint_entries.go(xs: List<&2, CardReady>) -> List<&2, V.CardEntry>:
  match xs:
    case Nil{}: Nil{}
    case Con{+r, t}: paint_entries.entry(ready_target(r), card_texts(r), paint_entries.go(t))

# Width-independent paint data for the View cascade: one entry per ready
# inline card with its formatted texts. View wraps at pane width and caps rows
# per card. Manual cards have no anchor line and stay out of chat paint.
def paint_entries(state: State) -> List<&2, V.CardEntry>:
  match state:
    case State{_, _, _, _, _, ready}: paint_entries.go(ready)

# ---- Visible admission (same panes, rows, mutes, and anchors as paint) ----

def visible_urls(urls: List<&2, String>, +id: Nat) -> List<&2, Candidate>:
  match urls:
    case Nil{}: Nil{}
    case Con{url, tail}: Candidate{CardInline{id}, url} <> visible_urls(tail, id)

def visible_line.allowed(allowed: Bool, id: Nat, text: String) -> List<&2, Candidate>:
  match allowed:
    case False{}: Nil{}
    case True{}: visible_urls(targets(text), id)

def visible_line(line: Maybe<&2, Cl.Line>) -> List<&2, Candidate>:
  match line:
    case None{}: Nil{}
    case Some{Cl.Line{kind, _, text, _, +id}}:
      visible_line.allowed(M.live_kind(kind) && Nat.is_gt(id, 0n), id, text)

def line_at(lines: List<&2, Cl.Line>, index: Nat) -> Maybe<&2, Cl.Line>:
  match lines:
    case Nil{}: None{}
    case Con{line, tail}:
      match index:
        case 0n: Some{line}
        case 1n+p: line_at(tail, p)

def visible_rows(rows: List<&2, V.AnchoredRow>) -> List<&2, Candidate>:
  match rows:
    case Nil{}: Nil{}
    case Con{V.AnchoredRow{_, _, +line}, tail}:
      List.append(&2, Candidate, visible_line(Some{line}), visible_rows(tail))

# Prefer when the caller already holds rows from
# V.visible_anchored_panes_media_cards_iso_pends. Live observe
# (session_observe_visible_media.gated and
# session_observe_visible_cards.gated) passes those here.
def visible_candidates_from_rows(+rows: List<&2, V.AnchoredRow>) -> List<&2, Candidate>:
  newest(visible_rows(rows))

# Live observe admits through
# V.visible_anchored_panes_media_cards_iso_pends
# (session_observe_visible_media.gated and
# session_observe_visible_cards.gated). The live tail includes that
# buffer's optimistic rows; Cl.Pending stays ineligible. The cm walker remains the
# default-RFC / law path: visible_candidates, tests, and LAWS.bend
# still enter visible_candidates_cards_cm with Cl.dflt_cm() and Nil{}
# cards. A separate non-cm walk would mute rows that walk retains
# (e.g. a[b under CASEMAPPING=ascii with muted a{b) and leak hidden URLs.
def visible_buffer_cards_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, V.CardEntry>) -> List<&2, Candidate>:
  visible_rows(V.visible_anchored_buf_media_cards_cm(cm, b, height, w, show_ts, mutes, joins, nicks, server, media, cards))

def visible_panes_cards_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, V.CardEntry>) -> List<&2, Candidate>:
  visible_rows(V.visible_anchored_panes_media_cards_cm(cm, cl, rows, cols, split, media, cards))

def visible_candidates_cards_cm(+cm: String, +cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, V.CardEntry>) -> List<&2, Candidate>:
  newest(visible_panes_cards_cm(cm, cl, rows, cols, split, media, cards))

def visible_panes_cards_iso(+isc: Cl.Iso, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, V.CardEntry>) -> List<&2, Candidate>:
  visible_rows(V.visible_anchored_panes_media_cards_iso(isc, cl, rows, cols, split, media, cards))

def visible_candidates_cards_iso(+isc: Cl.Iso, +cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, V.CardEntry>) -> List<&2, Candidate>:
  newest(visible_panes_cards_iso(isc, cl, rows, cols, split, media, cards))

# Default-RFC / law entry: one-line delegate to the cm walker.
def visible_candidates(+cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State) -> List<&2, Candidate>:
  visible_candidates_cards_cm(Cl.dflt_cm(), cl, rows, cols, split, media, Nil{})

# ---- Fullscreen images (one overlay; Bend owns open/close, C only paints) ----

type Fullscreen is Data:
  FullOff{}
  FullOn{target: M.Target, url: String, token: U32}

# One retained cell: the cards worker state plus the fullscreen overlay.
# Session keeps a single boxed one-element list of these (live_context idiom).
type Retained is Data:
  Retained{st: State, full: Fullscreen}

# Only accepted nonzero media tokens open, and only on supported terminals.
# Unsupported terminals keep exact URL text plus the one media log line.
def open_allowed(+media: M.State, +target: M.Target, +url: String) -> Bool:
  M.supported(media) && Bool.not(U32.is_zero(M.token(media, target, url)))

def open.on(allowed: Bool, +target: M.Target, +url: String, token: U32) -> Fullscreen:
  match allowed:
    case True{}: FullOn{target, url, token}
    case False{}: FullOff{}

def open(+media: M.State, +target: M.Target, +url: String) -> Fullscreen:
  open.on(open_allowed(media, target, url), target, url, M.token(media, target, url))

def close(+fs: Fullscreen) -> Fullscreen:
  match fs:
    case FullOff{}: FullOff{}
    case FullOn{_, _, _}: FullOff{}

# Paint must re-validate the stored token against current Media state before
# emitting it. Disable/reset/eviction clear ready rows (M.reset and
# M.set_enabled both drop them, and every generation bump clears ready), so a
# token mismatch closes those; M.alive closes endpoint or source removal; and
# M.supported closes terminal-capability loss. Integrator: call maintain_full
# with the live Media state and Client on every frame before fullscreen_ops.
def maintain_full.keep(ok: Bool, +fs: Fullscreen) -> Fullscreen:
  match ok:
    case True{}: fs
    case False{}: FullOff{}

def maintain_full(+fs: Fullscreen, +media: M.State, +client: Cl.Client) -> Fullscreen:
  match fs:
    case FullOff{}: FullOff{}
    case FullOn{+target, +url, +token}:
      maintain_full.keep(M.supported(media) && Bool.not(U32.is_zero(token))
        && U32.is_eq(M.token(media, target, url), token) && M.alive(client, target, url),
        FullOn{target, url, token})

def is_open(fs: Fullscreen) -> Bool:
  match fs:
    case FullOff{}: False{}
    case FullOn{_, _, _}: True{}

def token_of(fs: Fullscreen) -> U32:
  match fs:
    case FullOff{}: 0
    case FullOn{_, _, +token}: token

def fullscreen_h.on(+last: U32, +first: U32, ge: Bool) -> U32:
  match ge:
    case True{}: U32.add(U32.sub(last, first), 1)
    case False{}: 0

def fullscreen_h(+y: U32, +h: U32) -> U32:
  fullscreen_h.on(V.inner_last(y, h), V.inner_min(y, h), U32.is_ge(V.inner_last(y, h), V.inner_min(y, h)))

def fullscreen_ops.box(+box: V.Rect, +token: U32) -> List<&2, V.DrawOp>:
  match box:
    case V.Rect{+x, +y, +w, +h}:
      V.OpBox{x, y, w, h, V.PANE_BODY()} <> (V.OpMedia{V.inner_x(x), V.inner_min(y, h), V.inner_w(w),
        fullscreen_h(y, h), 0, fullscreen_h(y, h), token} <> Nil{})

def fullscreen_ops.token(+box: V.Rect, +token: U32) -> List<&2, V.DrawOp>:
  match token:
    case 0: Nil{}
    case _: fullscreen_ops.box(box, token)

def fullscreen_ops.paint(+box: V.Rect, +fs: Fullscreen) -> List<&2, V.DrawOp>:
  match fs:
    case FullOff{}: Nil{}
    case FullOn{_, _, +token}: fullscreen_ops.token(box, token)

# The overlay covers the body box with the accepted payload at native scale.
# A zero token never reaches the painter, even if constructed by hand.
def fullscreen_ops(+rows: U32, +cols: U32, +fs: Fullscreen) -> List<&2, V.DrawOp>:
  fullscreen_ops.paint(V.lay_body_rect(V.lay(rows, cols, 0)), fs)
