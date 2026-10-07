# Composer submit (M2). Pure: Client -> input -> (Client & List<&2, String>) outbound.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./links.bend as Links
import ./wire_style.bend as Ws
import ./endpoint.bend as Endpoint
import ./diagnostic.bend as Diagnostic
import ./irc_commands.bend as Commands
import ./message_chunks.bend as Chunks

def empty_out() -> List<&2, String>:
  Nil{}

def one_out(+s: String) -> List<&2, String>:
  Irc.clamp_line(Irc.strip_ctl(s)) <> Nil{}

# ---- shared automatic-image argument policy ----------------------------

def images_arg(arg: String) -> Maybe<&2, Bool>:
  match arg:
    case "on": Some{True{}}
    case "off": Some{False{}}
    case _: None{}

def images_status(intent: Maybe<&2, Bool>) -> String:
  match intent:
    case None{}: "usage: /images on|off"
    case Some{on}: Bool.pick(String, on, "automatic images on", "automatic images off")

# ---- shared space scan; command verb drops exactly one separator --------

def take_verb.scanned(pair: String & String) -> String & String:
  match pair:
    case (token, rest): (token, String.drop(rest, 1n))

def take_verb(s: String) -> String & String:
  take_verb.scanned(Irc.take_until_space(s))

def skip_slash.on(+h: Char, +t: String, slash: Bool) -> String:
  match slash:
    case True{}:
      t
    case False{}:
      SCon{h, t}

def skip_slash(+s: String) -> String:
  match s:
    case SCon{+h, t}:
      skip_slash.on(h, t, Irc.code_is(h, 47))
    case SNil{}:
      SNil{}

# Compatibility accessor used by existing command tests.
def active_name(+cl: Cl.Client) -> String:
  Cl.active_buf_name(cl)

# Service credential commands have ordinary IRC wire syntax, but must not
# become local chat or composer-history copies. Match complete command words;
# an ordinary peer saying IDENTIFY remains ordinary chat. LOGIN and SET
# PASSWORD are Atheme credential forms, alongside the common NickServ verbs.
def credential_set(pair: String & String) -> Bool:
  match pair:
    case (+word, _): Irc.ieq(word, "PASSWORD")

def credential_words(pair: String & String) -> Bool:
  match pair:
    case (+verb, +rest):
      Irc.ieq(verb, "IDENTIFY") || Irc.ieq(verb, "LOGIN")
        || Irc.ieq(verb, "REGISTER") || Irc.ieq(verb, "GHOST")
        || Irc.ieq(verb, "RECOVER") || Irc.ieq(verb, "RELEASE")
        || (Irc.ieq(verb, "SET") && credential_set(Irc.take_until_space(Irc.drop_spaces(rest))))

def credential_body(+body: String) -> Bool:
  credential_words(Irc.take_until_space(Irc.drop_spaces(Irc.proto_atom(Irc.strip_ctl(body)))))

def credential_target(+cl: Cl.Client, +target: String) -> Bool:
  +nick = Irc.nick_of_prefix(Cl.target_name(target))
  +service = Cl.client_auth_service(cl)
  Irc.ieq(nick, "NickServ") || (Bool.not(String.is_empty(service)) && Irc.ieq(nick, service))

def credential_targets(targets: List<&2, String>, +cl: Cl.Client) -> Bool:
  match targets:
    case Nil{}: False{}
    case Con{+target, rest}: credential_target(cl, target) || credential_targets(rest, cl)

def credential_message(+cl: Cl.Client, +target: String, +body: String) -> Bool:
  credential_targets(String.split(target, Chr{44}), cl) && credential_body(body)

def echo_self(+cl: Cl.Client, +bi: Nat, +body: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, _, _, _, _, _, +auth, +log_seq}:
      Cl.client_log_author_ts(cl, bi, Cl.Self{}, "", Feed.fmt_msg(nick, body), nick)

def echo_action(+cl: Cl.Client, +bi: Nat, +body: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, _, _, _, _, _, +auth, +log_seq}:
      Cl.client_log_author_ts(cl, bi, Cl.Action{}, "", Feed.fmt_action(nick, body), nick)

def echo_err(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, Cl.active_of(cl), Cl.Error{}, msg)

def echo_info(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, Cl.active_of(cl), Cl.System{}, msg)

def echo_sys(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, 0n, Cl.System{}, msg)

def echo_err_server(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, 0n, Cl.Error{}, msg)

# One exact line for proof-facing callers. Live sends plan complete chunks.
type MessageBody is Data:
  MessageBody{body: String, wire: String}

def prepare_message.fits(fits: Bool, +target: String, body: String, overhead: Nat) -> Maybe<&2, MessageBody>:
  match fits:
    case False{}: None{}
    case True{}:
      +clean = Irc.strip_ctl(body)
      Bool.pick(Maybe<&2, MessageBody>, Commands.framing(clean) && Nat.is_le(Irc.utf8_len(clean), Nat.sub(Irc.LINE_MAX(), overhead)),
        Some{MessageBody{clean, Irc.format_privmsg(target, clean)}}, None{})

def prepare_message(+target: String, body: String) -> Maybe<&2, MessageBody>:
  +clean = Cl.target_name(target)
  +overhead = Irc.utf8_len(Irc.format_privmsg(clean, ""))
  prepare_message.fits(Nat.is_le(overhead, Irc.LINE_MAX()), clean, body, overhead)

def credential_wire(+cl: Cl.Client, parsed: Maybe<&2, Irc.Message>) -> Bool:
  match parsed:
    case None{}: False{}
    case Some{+m}:
      +verb = Irc.msg_command(m)
      ((Irc.ieq(verb, "PRIVMSG") || Irc.ieq(verb, "NOTICE"))
        && credential_message(cl, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n)))
        || Irc.ieq(verb, "PASS") || Irc.ieq(verb, "AUTHENTICATE") || Irc.ieq(verb, "OPER")
        || Irc.ieq(verb, "IDENTIFY") || Irc.ieq(verb, "LOGIN")
        || ((credential_target(cl, verb) || Irc.ieq(verb, "NS") || Irc.ieq(verb, "CHANSERV") || Irc.ieq(verb, "CS"))
          && credential_body(String.join(Irc.msg_params(m), " ")))

def credential_echo.parsed(+cl: Cl.Client, parsed: Maybe<&2, Irc.Message>) -> Bool:
  match parsed:
    case None{}: False{}
    case Some{+m}:
      Irc.ieq(Irc.proto_atom(Irc.msg_nick(m)), Cl.nick_of(cl)) && credential_wire(cl, Some{m})

# An echoed copy of our own service credential command has the same privacy
# policy as the local echo. Other authors and ordinary messages stay chat.
def credential_echo(+cl: Cl.Client, +line: String) -> Bool:
  credential_echo.parsed(cl, Irc.parse(line))

def message_wire(+target: String, +body: String, notice: Bool) -> String:
  Bool.pick(String, notice, "NOTICE " ++ target ++ " :" ++ body, Irc.format_privmsg(target, body))

def credential_chunks(xs: List<&2, String>, +cl: Cl.Client, +target: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+body, rest}: credential_message(cl, target, body) || credential_chunks(rest, cl, target)

def message_sensitive.parts(parts: Maybe<&2, List<&2, String>>, +cl: Cl.Client, target: String) -> Bool:
  match parts:
    case None{}: False{}
    case Some{xs}: credential_chunks(xs, cl, target)

def message_sensitive.fits(fits: Bool, +cl: Cl.Client, target: String, body: String, overhead: Nat) -> Bool:
  match fits:
    case False{}: False{}
    case True{}: message_sensitive.parts(Chunks.split(body, Nat.sub(Irc.LINE_MAX(), overhead)), cl, target)

# A later chunk can start a service command although the original text did
# not. Use the same planned-wire predicate before sending and saving a draft.
def message_sensitive(+cl: Cl.Client, +target: String, +body: String, +notice: Bool) -> Bool:
  +clean = Irc.strip_ctl(body)
  +name = Cl.target_name(target)
  +overhead = Irc.utf8_len(message_wire(name, "", notice))
  credential_message(cl, name, clean)
    || message_sensitive.fits(Nat.is_lt(overhead, Irc.LINE_MAX()), cl, name, clean, overhead)

def echo_text.notice(notice: Bool, +cl: Cl.Client, +bi: Nat, +body: String) -> Cl.Client:
  match notice:
    case True{}: Cl.client_log_author_ts(cl, bi, Cl.Notice{}, "", Feed.fmt_msg(Cl.nick_of(cl), body), Cl.nick_of(cl))
    case False{}: echo_self(cl, bi, body)

def echo_text(private: Bool, notice: Bool, cl: Cl.Client, bi: Nat, body: String) -> Cl.Client:
  match private:
    case True{}: echo_self(cl, bi, "[credential command sent]")
    case False{}: echo_text.notice(notice, cl, bi, body)

def send_chunks.tail(pair: Cl.Client & List<&2, String>, wire: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl, outs): (cl, wire <> outs)

def send_chunks(xs: List<&2, String>, +cl: Cl.Client, +bi: Nat, +target: String, +private: Bool, +notice: Bool) -> Cl.Client & List<&2, String>:
  match xs:
    case Nil{}: (cl, Nil{})
    case Con{+body, rest}:
      send_chunks.tail(send_chunks(rest, echo_text(private, notice, cl, bi, body), bi, target, private, notice), message_wire(target, body, notice))

def send_text.parts(parts: Maybe<&2, List<&2, String>>, +cl: Cl.Client, bi: Nat, target: String, +private: Bool, notice: Bool) -> Cl.Client & List<&2, String>:
  match parts:
    case None{}:
      (echo_err(cl, Bool.pick(String, private, "credential command exceeds IRC line limit", "message cluster exceeds IRC line limit")), Nil{})
    case Some{xs}: send_chunks(xs, cl, bi, target, private, notice)

def message_parts(private: Bool, +body: String, cap: Nat) -> Maybe<&2, List<&2, String>>:
  match private:
    case True{}: Bool.pick(Maybe<&2, List<&2, String>>, Nat.is_le(Irc.utf8_len(body), cap), Some{body <> Nil{}}, None{})
    case False{}: Chunks.split(body, cap)

def has_no_nul(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}: Bool.not(Irc.code_is(h, 0)) && has_no_nul(t)

# Single validation source for message sends, shared by send_text and the
# drafts multiline planner so both admit and report identically: target
# word, framing on the stripped body, no NUL anywhere in the raw body
# (CR/LF cannot survive line splitting, NUL would silently vanish), and
# target headroom under the wire cap.
def text_valid(+target: String, +raw: String, +notice: Bool) -> Bool:
  +name = Cl.target_name(target)
  Commands.word(name) && Commands.framing(Irc.strip_ctl(raw)) && has_no_nul(raw)
    && Nat.is_lt(Irc.utf8_len(message_wire(name, "", notice)), Irc.LINE_MAX())

# Accurate cause for a text_valid rejection: a NUL byte is a control-input
# failure even for a valid target, never a target failure.
def text_reason.cause(nul: Bool) -> String:
  match nul:
    case True{}: "message rejected: NUL byte in text"
    case False{}: "message target exceeds IRC line limit"

def text_reason(+target: String, +raw: String, +notice: Bool) -> String:
  text_reason.cause(Bool.not(has_no_nul(raw)))

def send_text.valid(valid: Bool, +reason: String, +cl: Cl.Client, bi: Nat, +target: String, +body: String, +private: Bool, notice: Bool, overhead: Nat) -> Cl.Client & List<&2, String>:
  match valid:
    case False{}: (echo_err(cl, reason), Nil{})
    case True{}:
      send_text.parts(message_parts(private, body, Nat.sub(Irc.LINE_MAX(), overhead)), cl, bi, target, private, notice)

def send_text(+cl: Cl.Client, bi: Nat, +target: String, +body: String, +notice: Bool) -> Cl.Client & List<&2, String>:
  +clean = Irc.strip_ctl(body)
  +name = Cl.target_name(target)
  +overhead = Irc.utf8_len(message_wire(name, "", notice))
  send_text.valid(text_valid(target, body, notice), text_reason(target, body, notice),
    cl, bi, name, clean, message_sensitive(cl, name, clean, notice), notice, overhead)

def send_message(cl: Cl.Client, bi: Nat, target: String, body: String) -> Cl.Client & List<&2, String>:
  send_text(cl, bi, target, body, False{})

# ---- /join --------------------------------------------------------------

def submit_join.args(+target: String, +key: String, has_key: Bool) -> String:
  match has_key:
    case False{}: target
    case True{}: target ++ " " ++ key

# A JOIN list is one wire command, but each channel has its own buffer.
# Validate the complete request before staging any local changes. A full
# buffer set rejects the request atomically instead of joining unseen tabs.
def join_channel(+target: String) -> Bool:
  match target:
    case SNil{}: False{}
    case SCon{h, t}: Irc.is_chan_type(h) && Bool.not(String.is_empty(t))

def join_channels(targets: List<&2, String>) -> Bool:
  match targets:
    case Nil{}: True{}
    case Con{+h, t}: join_channel(h) && join_channels(t)

def join_staged.got(pair: Cl.Client & Maybe<&2, Nat>) -> Maybe<&2, Cl.Client>:
  match pair:
    case (_, None{}): None{}
    case (+cl, Some{+i}): Some{Cl.set_active(Cl.nick_add_idx(cl, i, Cl.nick_of(cl)), i)}

def join_staged.step(acc: Maybe<&2, Cl.Client>, target: String) -> Maybe<&2, Cl.Client>:
  match acc:
    case None{}: None{}
    case Some{cl}: join_staged.got(Cl.buf_get(cl, target, True{}, True{}))

def join_staged(targets: List<&2, String>, +cl: Cl.Client) -> Maybe<&2, Cl.Client>:
  List.foldl(~&2, ~String, ~Maybe<&2, Cl.Client>, ~join_staged.step, targets, Some{cl})

def submit_join.staged(+original: Cl.Client, +args: String, staged: Maybe<&2, Cl.Client>) -> Cl.Client & List<&2, String>:
  match staged:
    case None{}: (echo_err_server(original, "buffer limit reached"), empty_out())
    case Some{cl}: (cl, one_out(Irc.format_join(args)))

def submit_join.valid(valid: Bool, +cl: Cl.Client, targets: List<&2, String>, +args: String) -> Cl.Client & List<&2, String>:
  match valid:
    case False{}: (echo_err(cl, "usage: /join #chan[,#chan] [key[,key]]"), empty_out())
    case True{}: submit_join.staged(cl, args, join_staged(targets, cl))

def submit_join.words(cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+channel, rest):
      +target = Cl.target_name(channel)
      +key = Irc.drop_spaces(rest)
      +targets = String.split(target, Chr{44})
      +args = submit_join.args(target, key, Bool.not(String.is_empty(key)))
      submit_join.valid(Bool.not(String.is_empty(target)) && join_channels(targets)
        && Bool.not(String.contains(key, " "))
        && (String.is_empty(key) || Nat.is_le(List.length(&2, String, String.split(key, Chr{44})), List.length(&2, String, targets)))
        && Nat.is_le(Irc.utf8_len(Irc.format_join(args)), Irc.LINE_MAX()), cl, targets, args)

def submit_join(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_join.words(cl, Irc.take_until_space(Irc.drop_spaces(rest)))

# ---- /part --------------------------------------------------------------

def submit_part.drop.pick(+cl: Cl.Client, +chan: String, +bi: Nat, is_server: Bool) -> Cl.Client & List<&2, String>:
  match is_server:
    case True{}:
      (cl, one_out(Irc.format_part(chan)))
    case False{}:
      (Cl.drop_buf(cl, bi), one_out(Irc.format_part(chan)))

def submit_part.drop(+cl: Cl.Client, +chan: String, +bi: Nat) -> Cl.Client & List<&2, String>:
  submit_part.drop.pick(cl, chan, bi, Nat.is_eq(bi, 0n))

def submit_part.on(+cl: Cl.Client, +chan: String, found: Maybe<&2, Nat>) -> Cl.Client & List<&2, String>:
  match found:
    case None{}:
      (cl, one_out(Irc.format_part(chan)))
    case Some{+bi}:
      submit_part.drop(cl, chan, bi)

def submit_part.with(+cl: Cl.Client, +chan: String) -> Cl.Client & List<&2, String>:
  submit_part.on(cl, chan, Cl.buf_find(cl, chan))

def submit_part.is_ch(+cl: Cl.Client, +chan: String, is_chan: Bool) -> Cl.Client & List<&2, String>:
  match is_chan:
    case True{}:
      submit_part.with(cl, chan)
    case False{}:
      (echo_err(cl, "not a channel — use /close"), empty_out())

def submit_part.empty.on(+cl: Cl.Client, +rest: String, server: Bool) -> Cl.Client & List<&2, String>:
  match server:
    case True{}:
      (echo_err(cl, "usage: /part #chan"), empty_out())
    case False{}:
      submit_part.is_ch(cl, Cl.active_buf_name(cl), Cl.target_channel(Cl.active_buf_name(cl)))

def submit_part.empty(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      submit_part.empty.on(cl, rest, Nat.is_eq(Cl.active_of(cl), 0n))
    case False{}:
      submit_part.is_ch(cl, rest, Irc.starts_channel(rest))

def submit_part(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_part.empty(cl, rest, String.is_empty(rest))

# ---- /close -------------------------------------------------------------

def submit_close.out(+tgt: String, is_chan: Bool) -> List<&2, String>:
  match is_chan:
    case True{}:
      one_out(Irc.format_part(tgt))
    case False{}:
      empty_out()

def submit_close.fin(+cl: Cl.Client, +tgt: String, +bi: Nat, is_chan: Bool) -> Cl.Client & List<&2, String>:
  (Cl.drop_buf(cl, bi), submit_close.out(tgt, is_chan))

def submit_close.drop(+cl: Cl.Client, +tgt: String, +bi: Nat, is_server: Bool) -> Cl.Client & List<&2, String>:
  match is_server:
    case True{}:
      (echo_err(cl, "cannot close server buffer"), empty_out())
    case False{}:
      submit_close.fin(cl, tgt, bi, Irc.starts_channel(tgt))

def submit_close.miss(+cl: Cl.Client, +tgt: String, is_chan: Bool) -> Cl.Client & List<&2, String>:
  match is_chan:
    case True{}:
      (cl, one_out(Irc.format_part(tgt)))
    case False{}:
      (echo_err(cl, "no such buffer: " ++ tgt), empty_out())

def submit_close.on(+cl: Cl.Client, +tgt: String, found: Maybe<&2, Nat>) -> Cl.Client & List<&2, String>:
  match found:
    case None{}:
      submit_close.miss(cl, tgt, Irc.starts_channel(tgt))
    case Some{+bi}:
      submit_close.drop(cl, tgt, bi, Nat.is_eq(bi, 0n))

def submit_close.with(+cl: Cl.Client, +tgt: String) -> Cl.Client & List<&2, String>:
  submit_close.on(cl, tgt, Cl.buf_find(cl, tgt))

def submit_close.empty(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      submit_close.drop(cl, Cl.active_buf_name(cl), Cl.active_of(cl), Nat.is_eq(Cl.active_of(cl), 0n))
    case False{}:
      submit_close.with(cl, rest)

def submit_close(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_close.empty(cl, rest, String.is_empty(rest))

# ---- /msg ---------------------------------------------------------------

# A target/argument word drops all separators after the shared scan.
def take_word.scanned(pair: String & String) -> String & String:
  match pair:
    case (token, rest): (token, Irc.drop_spaces(rest))

def take_word(s: String) -> String & String:
  take_word.scanned(Irc.take_until_space(s))

def submit_msg.got(pair: Cl.Client & Maybe<&2, Nat>, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      send_message(Cl.set_active(cl2, bi), bi, who, body)

def submit_msg.readonly(internal: Bool, +cl: Cl.Client, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match internal:
    case True{}: (echo_err(cl, "read-only buffer"), empty_out())
    case False{}: submit_msg.got(Cl.buf_get(cl, Cl.message_key(cl, who), Cl.target_channel(who), True{}), who, body)

def submit_msg.bad(+cl: Cl.Client, bad: Bool, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match bad:
    case True{}:
      (echo_err(cl, "usage: /msg nick text"), empty_out())
    case False{}:
      submit_msg.readonly(Cl.target_is_synthetic(who), cl, who, body)

def submit_msg.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+who, +body):
      +target = Cl.target_name(who)
      submit_msg.bad(cl, String.is_empty(target) || String.is_empty(body), target, body)

def submit_msg(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_msg.words(cl, take_word(rest))

def submit_query.send(has_text: Bool, +cl: Cl.Client, +bi: Nat, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match has_text:
    case False{}:
      (cl, empty_out())
    case True{}:
      send_message(cl, bi, who, body)

def submit_query.found(+cl2: Cl.Client, +bi: Nat, +who: String, +body: String, has_text: Bool) -> Cl.Client & List<&2, String>:
  submit_query.send(has_text, Cl.set_active(cl2, bi), bi, who, body)

def submit_query.text(pair: Cl.Client & Maybe<&2, Nat>, +who: String, +body: String, has_text: Bool) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      submit_query.found(cl2, bi, who, body, has_text)

def submit_query.readonly(internal: Bool, +cl: Cl.Client, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match internal:
    case True{}: (echo_err(cl, "read-only buffer"), empty_out())
    case False{}: submit_query.text(Cl.buf_get(cl, Cl.message_key(cl, who), Cl.target_channel(who), True{}), who, body, Bool.not(String.is_empty(body)))

def submit_query.empty(+cl: Cl.Client, empty: Bool, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /query <nick> [text]"), empty_out())
    case False{}:
      submit_query.readonly(Cl.target_is_synthetic(who) && Bool.not(String.is_empty(body)), cl, who, body)

def submit_query.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+who, +body):
      +target = Cl.target_name(who)
      submit_query.empty(cl, String.is_empty(target), target, body)

def submit_query(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_query.words(cl, take_word(Irc.drop_spaces(rest)))

# Explicit protocol commands do not guess or alter incoming channel state.
def submit_wire(+cl: Cl.Client, line: Maybe<&2, String>, usage: String) -> Cl.Client & List<&2, String>:
  match line:
    case None{}: (echo_err(cl, usage), Nil{})
    case Some{wire}: (cl, wire <> Nil{})

def mode_resident(bufs: List<&2, Cl.Buffer>, +target: String) -> Bool:
  match bufs:
    case Nil{}: False{}
    case Con{Cl.Buffer{+name, +channel, _, _, _, _}, rest}:
      (channel && Irc.ieq(name, target)) || mode_resident(rest, target)

def mode_command.named(named: Bool, +cl: Cl.Client, +args: String) -> Maybe<&2, String>:
  match named:
    case True{}: Commands.word_command("MODE", args, 1n, 14n)
    case False{}: Commands.mode(Cl.active_buf_name(cl), Cl.nick_of(cl), args)

# Existing +channels win over implicit flags. An unseen ambiguous +local
# query remains expressible as /raw MODE +local; +i stays an implicit flag.
def mode_command.words(+cl: Cl.Client, +args: String, pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (first, _): mode_command.named(mode_resident(Cl.client_bufs(cl), first), cl, args)

def mode_command(+cl: Cl.Client, +args: String) -> Maybe<&2, String>:
  mode_command.words(cl, args, Irc.take_until_space(args))

def submit_mode(+cl: Cl.Client, +args: String) -> Cl.Client & List<&2, String>:
  submit_wire(cl, mode_command(cl, args), "usage: /mode [target] [modes [args]]")

def submit_notice.got(pair: Cl.Client & Maybe<&2, Nat>, +target: String, body: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl, None{}): (echo_err(cl, "buffer limit reached"), Nil{})
    case (cl, Some{+i}): send_text(Cl.set_active(cl, i), i, target, body, True{})

def submit_notice.valid(valid: Bool, +cl: Cl.Client, +target: String, body: String) -> Cl.Client & List<&2, String>:
  match valid:
    case False{}: (echo_err(cl, "usage: /notice target text"), Nil{})
    case True{}:
      submit_notice.got(Cl.buf_get(cl, Cl.message_key(cl, target), Cl.target_channel(target), True{}), target, body)

def submit_notice.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+target, +body):
      submit_notice.valid(Commands.word(target) && Commands.framing(body) && Bool.not(Cl.target_is_synthetic(target) || String.is_empty(body)),
        cl, target, Commands.trailing(body))

def submit_notice(cl: Cl.Client, rest: String) -> Cl.Client & List<&2, String>:
  submit_notice.words(cl, take_word(rest))

# ---- /nick /me /quit /unknown -------------------------------------------

def submit_nick.on(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /nick name"), empty_out())
    case False{}:
      (cl, one_out(Irc.format_nick(rest)))

def submit_nick(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_nick.on(cl, rest, String.is_empty(rest))

def ctcp_action(+rest: String) -> String:
  SCon{Chr{1}, "ACTION " ++ rest ++ SCon{Chr{1}, SNil{}}}

# Each action chunk reserves its complete envelope, including the closing SOH.
def send_action_chunks(xs: List<&2, String>, +cl: Cl.Client, +target: String) -> Cl.Client & List<&2, String>:
  match xs:
    case Nil{}: (cl, Nil{})
    case Con{+body, rest}:
      send_chunks.tail(send_action_chunks(rest, echo_action(cl, Cl.active_of(cl), body), target), Irc.format_privmsg(target, ctcp_action(body)))

def submit_me.parts(parts: Maybe<&2, List<&2, String>>, cl: Cl.Client, target: String) -> Cl.Client & List<&2, String>:
  match parts:
    case None{}: (echo_err(cl, "action cluster exceeds IRC line limit"), Nil{})
    case Some{xs}: send_action_chunks(xs, cl, target)

def submit_me.clean(valid: Bool, cl: Cl.Client, target: String, body: String, budget: Nat) -> Cl.Client & List<&2, String>:
  match valid:
    case False{}: (echo_err(cl, "action contains an invalid framing character"), Nil{})
    case True{}: submit_me.parts(Chunks.split(body, budget), cl, target)

def submit_me.budget(+cl: Cl.Client, +tgt: String, +rest: String, +overhead: Nat, fits: Bool) -> Cl.Client & List<&2, String>:
  match fits:
    case False{}:
      (echo_err(cl, "action target exceeds IRC line limit"), empty_out())
    case True{}:
      +body = Irc.strip_ctl(rest)
      submit_me.clean(Commands.framing(body), cl, tgt, body, Nat.sub(Irc.LINE_MAX(), overhead))

def submit_me.chan(+cl: Cl.Client, +rest: String, on_server: Bool) -> Cl.Client & List<&2, String>:
  match on_server:
    case True{}:
      (echo_err(cl, "not in a channel — /join #chan first"), empty_out())
    case False{}:
      +tgt = Irc.strip_ctl(Cl.active_buf_name(cl))
      +overhead = Irc.utf8_len(Irc.format_privmsg(tgt, ctcp_action("")))
      submit_me.budget(cl, tgt, rest, overhead, Commands.word(tgt) && Nat.is_lt(overhead, Irc.LINE_MAX()))

def active_is_synthetic(+cl: Cl.Client) -> Bool:
  Cl.target_is_synthetic(Cl.active_buf_name(cl))

def submit_me.target(+cl: Cl.Client, +rest: String, synthetic: Bool) -> Cl.Client & List<&2, String>:
  match synthetic:
    case True{}: (echo_err(cl, "read-only buffer"), empty_out())
    case False{}: submit_me.chan(cl, rest, Nat.is_eq(Cl.active_of(cl), 0n))

def submit_me.on(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /me action"), empty_out())
    case False{}:
      submit_me.target(cl, rest, active_is_synthetic(cl))

def submit_me(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_me.on(cl, rest, String.is_empty(rest))

def submit_quit.reason(+rest: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "birc"
    case False{}:
      rest

def submit_quit(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  (cl, one_out(Irc.format_quit(submit_quit.reason(rest, String.is_empty(rest)))))

def submit_unknown(+cl: Cl.Client, +verb: String) -> Cl.Client & List<&2, String>:
  (echo_err(cl, "unknown command: /" ++ verb), empty_out())

# Session handles connection commands as Dial, not IRC wire output.

type Conn is Data:
  ConnBad{}
  ConnOk{host: String, port: U32}
  ConnDefault{host: String}
  ConnReconnect{}

def connect_resolved(got: Maybe<&1, String & U32>) -> Conn:
  match got:
    case None{}: ConnBad{}
    case Some{(host, port)}: ConnOk{host, port}

def connect_separate(got: Maybe<&2, U32>, endpoint: Endpoint.Endpoint) -> Conn:
  match got:
    case None{}: ConnBad{}
    case Some{port}: connect_resolved(Endpoint.resolve(endpoint, Some{port}, 6697))

def connect_endpoint.default(endpoint: Endpoint.Endpoint) -> Conn:
  match endpoint:
    case Endpoint.Endpoint{host, None{}}: ConnDefault{host}
    case Endpoint.Endpoint{host, Some{port}}: ConnOk{host, port}

def connect_endpoint.empty(endpoint: Endpoint.Endpoint, more: String, empty: Bool) -> Conn:
  match empty:
    case True{}: connect_endpoint.default(endpoint)
    case False{}: connect_separate(Endpoint.port(more), endpoint)

def connect_endpoint(parsed: Result<&2, &2, String, Endpoint.Endpoint>, +more: String) -> Conn:
  match parsed:
    case Fail{_}: ConnBad{}
    case Done{endpoint}: connect_endpoint.empty(endpoint, more, String.is_empty(more))

def connect_parse.words(pair: String & String) -> Conn:
  match pair:
    case (+host, +more):
      connect_endpoint(Endpoint.parse(host), more)

def connect_parse(+rest: String) -> Conn:
  connect_parse.words(take_word(Irc.drop_spaces(rest)))

# ---- /settings, /set, /toggle -------------------------------------------

def bool_str(b: Bool) -> String:
  match b:
    case True{}:
      "ON"
    case False{}:
      "OFF"

def populate_settings(+cl: Cl.Client, +bi: Nat) -> Cl.Client:
  +stg = Cl.get_settings(cl)
  +c1 = Cl.buf_clear_at(cl, bi)
  +c2 = Cl.client_log(c1, bi, Cl.System{}, "=== BIRC SETTINGS ===")
  +c3 = Cl.client_log(c2, bi, Cl.System{}, "  joins     : " ++ bool_str(Cl.settings_joins(stg)) ++ "  (show join/part/quit messages)")
  +c4 = Cl.client_log(c3, bi, Cl.System{}, "  ts        : " ++ bool_str(Cl.settings_ts(stg)) ++ "  (show message timestamps)")
  +c5 = Cl.client_log(c4, bi, Cl.System{}, "  motd      : " ++ bool_str(Cl.settings_motd(stg)) ++ "  (show server motd on connect)")
  +c6 = Cl.client_log(c5, bi, Cl.System{}, "  history   : " ++ bool_str(Cl.settings_history(stg)) ++ "  (persist chat scrollback to disk)")
  +c7 = Cl.client_log(c6, bi, Cl.System{}, "  hist_cap  : " ++ U32.show(Cl.settings_hist_cap(stg)) ++ "  (lines of history per channel/server)")
  +c8 = Cl.client_log(c7, bi, Cl.System{}, "  autoreconn: " ++ bool_str(Cl.settings_autoreconn(stg)) ++ "  (auto-reconnect on unexpected disconnect)")
  +c9 = Cl.client_log(c8, bi, Cl.System{}, "  bell      : " ++ bool_str(Cl.settings_bell(stg)) ++ "  (terminal bell on mentions/highlights)")
  +c10 = Cl.client_log(c9, bi, Cl.System{}, "  mutes     : " ++ Nat.show(List.length(&2, String, Cl.settings_mutes(stg))) ++ " active rule(s)")
  +c11 = Cl.client_log(c10, bi, Cl.System{}, "")
  +c12 = Cl.client_log(c11, bi, Cl.System{}, "Commands:")
  +c13 = Cl.client_log(c12, bi, Cl.System{}, "  /set <setting> <value>    — change a setting")
  +c14 = Cl.client_log(c13, bi, Cl.System{}, "  /toggle <setting>         — toggle a boolean setting")
  +c15 = Cl.client_log(c14, bi, Cl.System{}, "  /query <nick> [text]      — open 1-on-1 private chat tab")
  +c16 = Cl.client_log(c15, bi, Cl.System{}, "  /mute <nick>              — mute nick on active channel/server")
  +c17 = Cl.client_log(c16, bi, Cl.System{}, "  /unmute <nick>            — remove nick from mute list")
  +c18 = Cl.client_log(c17, bi, Cl.System{}, "  /mutes                    — show active mute rules")
  +c19 = Cl.client_log(c18, bi, Cl.System{}, "  /reconnect                — reconnect to current server")
  Cl.client_log(c19, bi, Cl.System{}, "  /close                    — close settings buffer")

def refresh_settings_if_open.found(+cl: Cl.Client, found: Maybe<&2, Nat>) -> Cl.Client:
  match found:
    case None{}:
      cl
    case Some{+bi}:
      populate_settings(cl, bi)

def refresh_settings_if_open(+cl: Cl.Client) -> Cl.Client:
  refresh_settings_if_open.found(cl, Cl.buf_find(cl, "*settings*"))

def submit_settings.got(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      (populate_settings(Cl.set_active(cl2, bi), bi), empty_out())

def submit_settings(+cl: Cl.Client) -> Cl.Client & List<&2, String>:
  submit_settings.got(Cl.buf_get(cl, "*settings*", False{}, True{}))

type SettingKey is Data:
  KeyJoins{}
  KeyTs{}
  KeyMotd{}
  KeyHist{}
  KeyHistCap{}
  KeyAutoreconn{}
  KeyBell{}
  KeyBad{}

def parse_key.bell(hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyBell{}
    case False{}:
      KeyBad{}

def parse_key.bad(hit: Bool, +s: String) -> SettingKey:
  match hit:
    case True{}:
      KeyAutoreconn{}
    case False{}:
      parse_key.bell(Irc.ieq(s, "bell") || Irc.ieq(s, "beep") || Irc.ieq(s, "alert"))

def parse_key.cap(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyHistCap{}
    case False{}:
      parse_key.bad(Irc.ieq(s, "autoreconn") || Irc.ieq(s, "autoreconnect") || Irc.ieq(s, "reconn"), s)

def parse_key.hist(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyHist{}
    case False{}:
      parse_key.cap(s, Irc.ieq(s, "hist_cap") || Irc.ieq(s, "histcap") || Irc.ieq(s, "lines") || Irc.ieq(s, "history_cap"))

def parse_key.motd(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyMotd{}
    case False{}:
      parse_key.hist(s, Irc.ieq(s, "history") || Irc.ieq(s, "hist"))

def parse_key.ts(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyTs{}
    case False{}:
      parse_key.motd(s, Irc.ieq(s, "motd"))

def parse_key.joins(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyJoins{}
    case False{}:
      parse_key.ts(s, Irc.ieq(s, "ts") || Irc.ieq(s, "timestamp") || Irc.ieq(s, "timestamps"))

def parse_key(+s: String) -> SettingKey:
  parse_key.joins(s, Irc.ieq(s, "joins") || Irc.ieq(s, "join"))

def is_bool_true(+s: String) -> Bool:
  Irc.ieq(s, "on") || Irc.ieq(s, "true") || Irc.ieq(s, "yes") || Irc.ieq(s, "1")

def is_bool_false(+s: String) -> Bool:
  Irc.ieq(s, "off") || Irc.ieq(s, "false") || Irc.ieq(s, "no") || Irc.ieq(s, "0")

def parse_bool.false(hit: Bool) -> Maybe<&2, Bool>:
  match hit:
    case True{}:
      Some{False{}}
    case False{}:
      None{}

def parse_bool.true(+s: String, hit: Bool) -> Maybe<&2, Bool>:
  match hit:
    case True{}:
      Some{True{}}
    case False{}:
      parse_bool.false(is_bool_false(s))

def parse_bool(+s: String) -> Maybe<&2, Bool>:
  parse_bool.true(s, is_bool_true(s))

def setting_changed(cl: Cl.Client, key: String, value: String) -> Cl.Client & List<&2, String>:
  (echo_info(refresh_settings_if_open(cl), "setting '" ++ key ++ "' is now " ++ value), empty_out())

def apply_set_key.joins(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_joins(stg, b))
  setting_changed(cl2, "joins", bool_str(b))

def apply_set_key.ts(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_ts(stg, b))
  setting_changed(cl2, "ts", bool_str(b))

def apply_set_key.motd(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_motd(stg, b))
  setting_changed(cl2, "motd", bool_str(b))

def apply_set_key.hist(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_history(stg, b))
  setting_changed(cl2, "history", bool_str(b))

def apply_set_key.cap(+cl: Cl.Client, +cap: U32) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_hist_cap(stg, cap))
  setting_changed(cl2, "hist_cap", U32.show(cap))

def apply_set_key.autoreconn(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_autoreconn(stg, b))
  setting_changed(cl2, "autoreconn", bool_str(b))

def apply_set_key.bell(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_bell(stg, b))
  setting_changed(cl2, "bell", bool_str(b))

def apply_set_key(k: SettingKey, +cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  match k:
    case KeyJoins{}:
      apply_set_key.joins(cl, b)
    case KeyTs{}:
      apply_set_key.ts(cl, b)
    case KeyMotd{}:
      apply_set_key.motd(cl, b)
    case KeyHist{}:
      apply_set_key.hist(cl, b)
    case KeyHistCap{}:
      (echo_err(cl, "hist_cap expects a number: /set hist_cap <number>"), empty_out())
    case KeyAutoreconn{}:
      apply_set_key.autoreconn(cl, b)
    case KeyBell{}:
      apply_set_key.bell(cl, b)
    case KeyBad{}:
      (echo_err(cl, "unknown setting (valid: joins, ts, motd, history, hist_cap, autoreconn, bell)"), empty_out())

def apply_toggle_key(k: SettingKey, +cl: Cl.Client) -> Cl.Client & List<&2, String>:
  match k:
    case KeyJoins{}:
      apply_set_key.joins(cl, Bool.not(Cl.settings_joins(Cl.get_settings(cl))))
    case KeyTs{}:
      apply_set_key.ts(cl, Bool.not(Cl.settings_ts(Cl.get_settings(cl))))
    case KeyMotd{}:
      apply_set_key.motd(cl, Bool.not(Cl.settings_motd(Cl.get_settings(cl))))
    case KeyHist{}:
      apply_set_key.hist(cl, Bool.not(Cl.settings_history(Cl.get_settings(cl))))
    case KeyHistCap{}:
      (echo_err(cl, "cannot toggle hist_cap: use /set hist_cap <number>"), empty_out())
    case KeyAutoreconn{}:
      apply_set_key.autoreconn(cl, Bool.not(Cl.settings_autoreconn(Cl.get_settings(cl))))
    case KeyBell{}:
      apply_set_key.bell(cl, Bool.not(Cl.settings_bell(Cl.get_settings(cl))))
    case KeyBad{}:
      (echo_err(cl, "usage: /toggle <joins|ts|motd|history|autoreconn|bell>"), empty_out())

def show_setting_key(k: SettingKey, +cl: Cl.Client) -> Cl.Client & List<&2, String>:
  match k:
    case KeyJoins{}:
      (echo_info(cl, "joins is " ++ bool_str(Cl.settings_joins(Cl.get_settings(cl)))), empty_out())
    case KeyTs{}:
      (echo_info(cl, "ts is " ++ bool_str(Cl.settings_ts(Cl.get_settings(cl)))), empty_out())
    case KeyMotd{}:
      (echo_info(cl, "motd is " ++ bool_str(Cl.settings_motd(Cl.get_settings(cl)))), empty_out())
    case KeyHist{}:
      (echo_info(cl, "history is " ++ bool_str(Cl.settings_history(Cl.get_settings(cl)))), empty_out())
    case KeyHistCap{}:
      (echo_info(cl, "hist_cap is " ++ U32.show(Cl.settings_hist_cap(Cl.get_settings(cl)))), empty_out())
    case KeyAutoreconn{}:
      (echo_info(cl, "autoreconn is " ++ bool_str(Cl.settings_autoreconn(Cl.get_settings(cl)))), empty_out())
    case KeyBell{}:
      (echo_info(cl, "bell is " ++ bool_str(Cl.settings_bell(Cl.get_settings(cl)))), empty_out())
    case KeyBad{}:
      (echo_err(cl, "unknown setting (valid: joins, ts, motd, history, hist_cap, autoreconn, bell)"), empty_out())

def submit_set.cap(+cl: Cl.Client, mb: Maybe<&2, U32>) -> Cl.Client & List<&2, String>:
  match mb:
    case None{}:
      (echo_err(cl, "invalid value: expected number (e.g. 50, 100, 200)"), empty_out())
    case Some{cap}:
      apply_set_key.cap(cl, cap)

def submit_set.parsed(mb: Maybe<&2, Bool>, k: SettingKey, +cl: Cl.Client) -> Cl.Client & List<&2, String>:
  match mb:
    case None{}:
      (echo_err(cl, "invalid value: expected on|off"), empty_out())
    case Some{+b}:
      apply_set_key(k, cl, b)

def submit_set.dispatch(k: SettingKey, +cl: Cl.Client, +val: String) -> Cl.Client & List<&2, String>:
  match k:
    case KeyHistCap{}:
      submit_set.cap(cl, U32.read(val))
    case _:
      submit_set.parsed(parse_bool(val), k, cl)

def submit_set.val(+cl: Cl.Client, +key: String, +val: String, empty_val: Bool) -> Cl.Client & List<&2, String>:
  match empty_val:
    case True{}:
      show_setting_key(parse_key(key), cl)
    case False{}:
      submit_set.dispatch(parse_key(key), cl, val)

def submit_set.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+key, +val_raw):
      +val = Irc.drop_spaces(val_raw)
      submit_set.val(cl, key, val, String.is_empty(val))

def submit_set.empty(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      submit_settings(cl)
    case False{}:
      submit_set.words(cl, take_word(rest))

def submit_set(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_set.empty(cl, rest, String.is_empty(rest))

def submit_toggle.word(+cl: Cl.Client, +key: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /toggle <joins|ts|motd>"), empty_out())
    case False{}:
      apply_toggle_key(parse_key(key), cl)

def submit_toggle.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+key, _):
      submit_toggle.word(cl, key, String.is_empty(key))

def submit_toggle(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_toggle.words(cl, take_word(Irc.drop_spaces(rest)))

def submit_mute.pat(+cl: Cl.Client, +nick: String, is_chan: Bool) -> String:
  match is_chan:
    case True{}:
      nick ++ Cl.active_buf_name(cl) ++ "@" ++ Cl.server_of(cl)
    case False{}:
      nick ++ "*@" ++ Cl.server_of(cl)

def submit_mute.nick(+cl: Cl.Client, +nick: String) -> Cl.Client & List<&2, String>:
  +pat = submit_mute.pat(cl, nick, Irc.starts_channel(Cl.active_buf_name(cl)))
  +cl2 = Cl.add_mute_client(cl, pat)
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "muted " ++ nick ++ " (" ++ pat ++ ")"), empty_out())

def submit_mute.word(+cl: Cl.Client, +nick: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /mute <nick>"), empty_out())
    case False{}:
      submit_mute.nick(cl, nick)

def submit_mute.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+nick, _):
      submit_mute.word(cl, nick, String.is_empty(nick))

def submit_mute(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_mute.words(cl, take_word(Irc.drop_spaces(rest)))

def submit_unmute.nick(+cl: Cl.Client, +nick: String) -> Cl.Client & List<&2, String>:
  +cl2 = Cl.del_mute_client(cl, nick)
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "unmuted " ++ nick), empty_out())

def submit_unmute.word(+cl: Cl.Client, +nick: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /unmute <nick>"), empty_out())
    case False{}:
      submit_unmute.nick(cl, nick)

def submit_unmute.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+nick, _):
      submit_unmute.word(cl, nick, String.is_empty(nick))

def submit_unmute(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_unmute.words(cl, take_word(Irc.drop_spaces(rest)))

def submit_mutes.go(+cl: Cl.Client, mutes: List<&2, String>) -> Cl.Client & List<&2, String>:
  match mutes:
    case Nil{}:
      (echo_info(cl, "no active mutes"), empty_out())
    case Con{+m, t}:
      (echo_info(cl, "active mutes: " ++ String.join(m <> t, ", ")), empty_out())

def submit_mutes(+cl: Cl.Client) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  submit_mutes.go(cl, Cl.settings_mutes(stg))

def submit.is_slash.on(+h: Char) -> Bool:
  Irc.code_is(h, 47)

def submit.is_slash(+s: String) -> Bool:
  match s:
    case SCon{+h, _}:
      submit.is_slash.on(h)
    case SNil{}:
      False{}

def is_http_pfx(+s: String) -> Bool:
  Links.is_url_prefix(s)

def extract_urls(+s: String) -> List<&2, String>:
  Ws.extract(s)

def lines_urls.line(skip: Bool, +text: String) -> List<&2, String>:
  match skip:
    case True{}: Nil{}
    case False{}: Ws.extract(text)

def lines_urls.go(fuel: Nat, lines: List<&2, Cl.Line>) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match lines:
        case Nil{}: Nil{}
        case Con{ln, t}:
          match ln:
            case Cl.Line{+kind, _, +text, _, _}:
              List.append(&2, String, lines_urls.line(Cl.is_link_result(kind) || Cl.is_reconnect(kind), text), lines_urls.go(p, t))

def active_buf_urls(+cl: Cl.Client) -> List<&2, String>:
  +rev_lines = List.reverse(&2, Cl.Line, Cl.active_buf_lines(cl))
  lines_urls.go(Nat.add(1n, List.length(&2, Cl.Line, rev_lines)), rev_lines)

def nth_link.go(fuel: Nat, xs: List<&2, String>, n: Nat) -> Maybe<&2, String>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      match xs:
        case Nil{}: None{}
        case Con{+h, t}:
          match n:
            case 0n: Some{h}
            case 1n+pn: nth_link.go(p, t, pn)

def nth_link(xs: List<&2, String>, +n: Nat) -> Maybe<&2, String>:
  nth_link.go(Nat.add(1n, n), xs, n)

def echo_link_result(+cl: Cl.Client, +text: String) -> Cl.Client:
  Cl.client_log(cl, Cl.active_of(cl), Cl.LinkResult{}, text)

def clear_link_results.keep(skip: Bool, line: Cl.Line, rest: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match skip:
    case True{}: rest
    case False{}: line <> rest

def clear_link_results.lines(lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+line, t}:
      match line:
        case Cl.Line{kind, _, _, _, _}:
          clear_link_results.keep(Cl.is_link_result(kind), line, clear_link_results.lines(t))

def clear_link_results.buf(b: Cl.Buffer) -> Cl.Buffer:
  match b:
    case Cl.Buffer{name, channel, topic, +lines, nicks, scroll}:
      +kept = clear_link_results.lines(lines)
      Cl.Buffer{name, channel, topic, kept, nicks, Cl.reanchor_lines(lines, kept, scroll)}

def clear_link_results(+cl: Cl.Client) -> Cl.Client:
  Cl.buf_modify_client(cl, Cl.active_of(cl), clear_link_results.buf)

def echo_links.go(fuel: Nat, cl: Cl.Client, xs: List<&2, String>, +idx: Nat) -> Cl.Client:
  match fuel:
    case 0n: cl
    case 1n+p:
      match xs:
        case Nil{}: cl
        case Con{+h, t}:
          +msg = "[" ++ Nat.show(idx) ++ "] " ++ h
          echo_links.go(p, echo_link_result(cl, msg), t, Nat.add(idx, 1n))

def submit_links.on(+cl: Cl.Client, urls: List<&2, String>) -> Cl.Client & List<&2, String>:
  match urls:
    case Nil{}:
      (echo_link_result(cl, "no links found in buffer"), empty_out())
    case Con{+h, t}:
      +cl2 = echo_link_result(cl, "recent links:")
      (echo_links.go(100n, cl2, h <> t, 1n), empty_out())

def submit_links(+cl: Cl.Client) -> Cl.Client & List<&2, String>:
  +source = clear_link_results(cl)
  submit_links.on(source, active_buf_urls(source))

def open_parse_arg.zero(is_zero: Bool, +cl: Cl.Client, n: U32) -> Maybe<&2, String>:
  match is_zero:
    case True{}: None{}
    case False{}:
      nth_link(active_buf_urls(cl), U32.to_nat(U32.sub(n, 1)))

def open_parse_arg.num(+cl: Cl.Client, num_mb: Maybe<&2, U32>) -> Maybe<&2, String>:
  match num_mb:
    case None{}:
      None{}
    case Some{+n}:
      open_parse_arg.zero(U32.is_eq(n, 0), cl, n)

def open_resolve_target.http(is_http: Bool, +cl: Cl.Client, +arg: String) -> Maybe<&2, String>:
  match is_http:
    case True{}:
      Some{arg}
    case False{}:
      open_parse_arg.num(cl, U32.read(arg))

def open_resolve_target.empty(empty: Bool, +cl: Cl.Client, +arg: String) -> Maybe<&2, String>:
  match empty:
    case True{}:
      nth_link(active_buf_urls(cl), 0n)
    case False{}:
      open_resolve_target.http(is_http_pfx(arg), cl, arg)

def open_resolve_target(+cl: Cl.Client, +arg: String) -> Maybe<&2, String>:
  open_resolve_target.empty(String.is_empty(arg), cl, arg)

def submit_open_cmd.got(+cl: Cl.Client, mb: Maybe<&2, String>) -> Cl.Client & List<&2, String>:
  match mb:
    case None{}:
      (echo_err(cl, "no link found"), empty_out())
    case Some{+url}:
      (echo_link_result(cl, "opening " ++ url), empty_out())

def submit_open_cmd(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_open_cmd.got(cl, open_resolve_target(cl, Irc.drop_spaces(rest)))

# ---- /search ------------------------------------------------------------

def submit_search.on(empty: Bool, +cl: Cl.Client, +query: String) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /search <query>"), empty_out())
    case False{}:
      (Feed.search_and_open(cl, query), empty_out())

def submit_search(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_search.on(String.is_empty(rest), cl, rest)

# ---- /preview -----------------------------------------------------------

def preview_local_path.file(file_url: Bool, +arg: String) -> String:
  match file_url:
    case True{}: String.drop(arg, 7n)
    case False{}: arg

def preview_local_path(+arg: String) -> String:
  preview_local_path.file(String.starts_with(arg, "file://"), arg)

def preview_file_url_ok() -> Bool:
  String.eq(preview_local_path("file:///tmp/image.png"), "/tmp/image.png")

def submit_preview.open(pair: Cl.Client & Maybe<&2, Nat>, +path: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+cl, None{}):
      (echo_err(cl, "preview unavailable: buffer limit reached"), empty_out())
    case (cl, Some{+i}):
      +cl2 = Cl.set_topic_at(cl, i, path)
      (Cl.set_active(cl2, i), empty_out())

def submit_preview.local(+cl: Cl.Client, +path: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /preview <local-path>"), empty_out())
    case False{}:
      submit_preview.open(Cl.buf_get(cl, "*preview*", False{}, True{}), path)

def submit_preview.remote(+cl: Cl.Client, +arg: String, remote: Bool) -> Cl.Client & List<&2, String>:
  match remote:
    case True{}:
      submit_preview.open(Cl.buf_get(cl, "*preview*", False{}, True{}), arg)
    case False{}:
      +path = preview_local_path(arg)
      submit_preview.local(cl, path, String.is_empty(path))

def submit_preview(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  +arg = Irc.drop_spaces(rest)
  submit_preview.remote(cl, arg, is_http_pfx(arg))

type Slash is Data:
  Join{}
  Part{}
  CloseCmd{}
  Msg{}
  QueryCmd{}
  Nick{}
  Me{}
  Quit{}
  SettingsCmd{}
  SetCmd{}
  ToggleCmd{}
  MuteCmd{}
  UnmuteCmd{}
  MutesCmd{}
  LinksCmd{}
  OpenCmd{}
  SearchCmd{}
  PreviewCmd{}
  ImagesCmd{}
  UploadCmd{}
  LogCmd{}
  WhoisCmd{}
  WhoCmd{}
  ListCmd{}
  NamesCmd{}
  TopicCmd{}
  ModeCmd{}
  KickCmd{}
  InviteCmd{}
  AwayCmd{}
  NoticeCmd{}
  RawCmd{}
  Unknown{}

type SlashRow is Data:
  SlashRow{name: String, cmd: Slash}

def slash_rows() -> List<&2, SlashRow>:
  SlashRow{"join", Join{}}
    <> SlashRow{"part", Part{}}
    <> SlashRow{"close", CloseCmd{}}
    <> SlashRow{"msg", Msg{}}
    <> SlashRow{"query", QueryCmd{}}
    <> SlashRow{"nick", Nick{}}
    <> SlashRow{"me", Me{}}
    <> SlashRow{"quit", Quit{}}
    <> SlashRow{"settings", SettingsCmd{}}
    <> SlashRow{"set", SetCmd{}}
    <> SlashRow{"toggle", ToggleCmd{}}
    <> SlashRow{"mute", MuteCmd{}}
    <> SlashRow{"unmute", UnmuteCmd{}}
    <> SlashRow{"mutes", MutesCmd{}}
    # Session owns connection and pane commands; keep their aliases here too.
    <> SlashRow{"connect", Unknown{}}
    <> SlashRow{"reconnect", Unknown{}}
    <> SlashRow{"open", OpenCmd{}}
    <> SlashRow{"links", LinksCmd{}}
    <> SlashRow{"search", SearchCmd{}}
    <> SlashRow{"preview", PreviewCmd{}}
    <> SlashRow{"images", ImagesCmd{}}
    <> SlashRow{"log", LogCmd{}}
    <> SlashRow{"split", Unknown{}}
    <> SlashRow{"vsplit", Unknown{}}
    <> SlashRow{"split-off", Unknown{}}
    <> SlashRow{"unsplit", Unknown{}}
    <> SlashRow{"focus", Unknown{}}
    <> SlashRow{"upload", UploadCmd{}}
    <> SlashRow{"whois", WhoisCmd{}}
    <> SlashRow{"who", WhoCmd{}}
    <> SlashRow{"list", ListCmd{}}
    <> SlashRow{"names", NamesCmd{}}
    <> SlashRow{"topic", TopicCmd{}}
    <> SlashRow{"mode", ModeCmd{}}
    <> SlashRow{"kick", KickCmd{}}
    <> SlashRow{"invite", InviteCmd{}}
    <> SlashRow{"away", AwayCmd{}}
    <> SlashRow{"notice", NoticeCmd{}}
    <> SlashRow{"raw", RawCmd{}}
    <> SlashRow{"quote", RawCmd{}}
    <> Nil{}

def slash_lookup(xs: List<&2, SlashRow>, +verb: String) -> Slash:
  match xs:
    case Nil{}:
      Unknown{}
    case Con{row, t}:
      match row:
        case SlashRow{+name, +c}:
          Bool.pick(Slash, Irc.ieq(name, verb), c, slash_lookup(t, verb))

def slash_of(+verb: String) -> Slash:
  slash_lookup(slash_rows(), verb)

# Unknown also names Session-owned aliases. Distinguish those catalog entries
# from a dropped absolute path without duplicating the command list.
def slash_known.rows(rows: List<&2, SlashRow>, +verb: String) -> Bool:
  match rows:
    case Nil{}: False{}
    case Con{SlashRow{name, _}, rest}: Irc.ieq(name, verb) || slash_known.rows(rest, verb)

def slash_known(verb: String) -> Bool:
  slash_known.rows(slash_rows(), verb)

type Input is Data:
  EmptyInput{}
  PlainInput{text: String}
  CommandInput{cmd: Slash, verb: String, rest: String}

def parse_input.words(pair: String & String) -> Input:
  match pair:
    case (+verb, +rest): CommandInput{slash_of(verb), verb, Irc.drop_spaces(rest)}

def parse_input.slash(+input: String, slash: Bool) -> Input:
  match slash:
    case True{}: parse_input.words(take_verb(skip_slash(input)))
    case False{}: PlainInput{input}

def parse_input.empty(+input: String, empty: Bool) -> Input:
  match empty:
    case True{}: EmptyInput{}
    case False{}: parse_input.slash(input, submit.is_slash(input))

def parse_input(+input: String) -> Input:
  parse_input.empty(input, String.is_empty(input))

# Durable-setting admission shares the submission parsers. A successful edit
# matters even when its value is unchanged; show-only and rejected inputs do not.
def preference_key(k: SettingKey) -> Maybe<&2, String>:
  match k:
    case KeyJoins{}: Some{"joins"}
    case KeyTs{}: Some{"ts"}
    case KeyMotd{}: Some{"motd"}
    case KeyHist{}: Some{"history"}
    case KeyAutoreconn{}: Some{"autoreconn"}
    case KeyBell{}: Some{"bell"}
    case _: None{}

def preference_set.boolean(parsed: Maybe<&2, Bool>, key: SettingKey) -> Maybe<&2, String>:
  match parsed:
    case None{}: None{}
    case Some{_}: preference_key(key)

def preference_set.cap(parsed: Maybe<&2, U32>) -> Maybe<&2, String>:
  match parsed:
    case None{}: None{}
    case Some{_}: Some{"hist_cap"}

def preference_set.key(key: SettingKey, value: String) -> Maybe<&2, String>:
  match key:
    case KeyHistCap{}: preference_set.cap(U32.read(value))
    case _: preference_set.boolean(parse_bool(value), key)

def preference_set.words(pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (key, value): preference_set.key(parse_key(key), Irc.drop_spaces(value))

def preference_toggle.words(pair: String & String) -> Maybe<&2, String>:
  match pair:
    # submit_toggle intentionally uses only its first word.
    case (key, _): preference_key(parse_key(key))

def preference_mute.present(present: Bool) -> Maybe<&2, String>:
  match present:
    case False{}: None{}
    case True{}: Some{"mutes"}

def preference_mute.words(pair: String & String) -> Maybe<&2, String>:
  match pair:
    # submit_mute/unmute likewise accept one nonempty first word.
    case (nick, _): preference_mute.present(Bool.not(String.is_empty(nick)))

def preference_images(parsed: Maybe<&2, Bool>) -> Maybe<&2, String>:
  match parsed:
    case None{}: None{}
    case Some{_}: Some{"images"}

def preference_intent(input: Input) -> Maybe<&2, String>:
  match input:
    case CommandInput{SetCmd{}, _, rest}: preference_set.words(take_word(rest))
    case CommandInput{ToggleCmd{}, _, rest}: preference_toggle.words(take_word(Irc.drop_spaces(rest)))
    case CommandInput{MuteCmd{}, _, rest}: preference_mute.words(take_word(Irc.drop_spaces(rest)))
    case CommandInput{UnmuteCmd{}, _, rest}: preference_mute.words(take_word(Irc.drop_spaces(rest)))
    case CommandInput{ImagesCmd{}, _, rest}: preference_images(images_arg(Irc.drop_spaces(rest)))
    case _: None{}

def input_sensitive.words(+cl: Cl.Client, pair: String & String) -> Bool:
  match pair:
    case (target, body): message_sensitive(cl, target, body, False{})

def input_sensitive.notice_words(+cl: Cl.Client, pair: String & String) -> Bool:
  match pair:
    case (target, body): message_sensitive(cl, target, Commands.trailing(body), True{})

def input_sensitive.join_words(pair: String & String) -> Bool:
  match pair:
    case (_, keys): Bool.not(String.is_empty(keys))

def input_sensitive.mode_wire(wire: Maybe<&2, String>) -> Bool:
  match wire:
    case None{}: False{}
    case Some{line}: Commands.mode_has_key.line(line)

# Classify the original input against its original active buffer. Submission
# and simultaneous navigation can change focus before history is retained.
def input_sensitive.parsed(+cl: Cl.Client, input: Input) -> Bool:
  match input:
    case PlainInput{body}: message_sensitive(cl, Cl.active_buf_name(cl), body, False{})
    case CommandInput{Msg{}, _, rest}: input_sensitive.words(cl, take_word(rest))
    case CommandInput{QueryCmd{}, _, rest}: input_sensitive.words(cl, take_word(Irc.drop_spaces(rest)))
    case CommandInput{NoticeCmd{}, _, rest}: input_sensitive.notice_words(cl, take_word(rest))
    # Channel keys are runtime-only, including manual keyed joins.
    case CommandInput{Join{}, _, rest}: input_sensitive.join_words(take_word(rest))
    case CommandInput{ModeCmd{}, _, rest}: input_sensitive.mode_wire(mode_command(cl, rest))
    # Raw/quote may carry authentication commands unknown to this client.
    # Keep the complete escape hatch outside composer history; it has no echo.
    case CommandInput{RawCmd{}, _, _}: True{}
    case _: False{}

def input_sensitive(+cl: Cl.Client, +raw: String) -> Bool:
  input_sensitive.parsed(cl, parse_input(raw))

def submit_is_open.parsed(input: Input) -> Bool:
  match input:
    case CommandInput{OpenCmd{}, _, _}: True{}
    case _: False{}

def submit_is_open(+input: String) -> Bool:
  submit_is_open.parsed(parse_input(input))

def open_arg_from_input.parsed(input: Input) -> String:
  match input:
    case CommandInput{OpenCmd{}, _, rest}: rest
    case _: ""

def open_arg_from_input(+input: String) -> String:
  open_arg_from_input.parsed(parse_input(input))

def query_needs_connection(pair: String & String) -> Bool:
  match pair:
    case (_, +body): Bool.not(String.is_empty(body))

def command_needs_connection(cmd: Slash, +rest: String) -> Bool:
  match cmd:
    case Join{}: True{}
    case Part{}: True{}
    case Msg{}: True{}
    case Nick{}: True{}
    case Me{}: True{}
    case WhoisCmd{}: True{}
    case WhoCmd{}: True{}
    case ListCmd{}: True{}
    case NamesCmd{}: True{}
    case TopicCmd{}: True{}
    case ModeCmd{}: True{}
    case KickCmd{}: True{}
    case InviteCmd{}: True{}
    case AwayCmd{}: True{}
    case NoticeCmd{}: True{}
    case RawCmd{}: True{}
    case QueryCmd{}: query_needs_connection(take_word(rest))
    case _: False{}

def needs_connection(input: Input) -> Bool:
  match input:
    case PlainInput{_}: True{}
    case CommandInput{cmd, _, +rest}: command_needs_connection(cmd, rest)
    case EmptyInput{}: False{}

def submit_cmd.do(+cl: Cl.Client, +verb: String, +rest: String, cmd: Slash) -> Cl.Client & List<&2, String>:
  match cmd:
    case Join{}:
      submit_join(cl, rest)
    case Part{}:
      submit_part(cl, rest)
    case CloseCmd{}:
      submit_close(cl, rest)
    case Msg{}:
      submit_msg(cl, rest)
    case QueryCmd{}:
      submit_query(cl, rest)
    case Nick{}:
      submit_nick(cl, rest)
    case Me{}:
      submit_me(cl, rest)
    case Quit{}:
      submit_quit(cl, rest)
    case SettingsCmd{}:
      submit_settings(cl)
    case SetCmd{}:
      submit_set(cl, rest)
    case ToggleCmd{}:
      submit_toggle(cl, rest)
    case MuteCmd{}:
      submit_mute(cl, rest)
    case UnmuteCmd{}:
      submit_unmute(cl, rest)
    case MutesCmd{}:
      submit_mutes(cl)
    case LinksCmd{}:
      submit_links(cl)
    case OpenCmd{}:
      submit_open_cmd(cl, rest)
    case SearchCmd{}:
      submit_search(cl, rest)
    case PreviewCmd{}:
      submit_preview(cl, rest)
    case ImagesCmd{}:
      (echo_sys(cl, images_status(images_arg(Irc.drop_spaces(rest)))), empty_out())
    case LogCmd{}:
      (Cl.log_open(cl), empty_out())
    case UploadCmd{}:
      (echo_err(cl, "upload requires an active session confirmation"), empty_out())
    case WhoisCmd{}:
      submit_wire(cl, Commands.whois(rest), "usage: /whois [server] nick[,nick]")
    case WhoCmd{}:
      submit_wire(cl, Commands.who(Cl.active_buf_name(cl), rest), "usage: /who [mask [o]]")
    case ListCmd{}:
      submit_wire(cl, Commands.list(rest), "usage: /list [channels [server]]")
    case NamesCmd{}:
      submit_wire(cl, Commands.names(Cl.active_buf_name(cl), rest), "usage: /names [channels [server]]")
    case TopicCmd{}:
      submit_wire(cl, Commands.topic(Cl.active_buf_name(cl), rest), "usage: /topic [#channel] [:text]")
    case ModeCmd{}:
      submit_mode(cl, rest)
    case KickCmd{}:
      submit_wire(cl, Commands.kick(Cl.active_buf_name(cl), rest), "usage: /kick [#channel] nick [reason]")
    case InviteCmd{}:
      submit_wire(cl, Commands.invite(Cl.active_buf_name(cl), rest), "usage: /invite nick [#channel]")
    case AwayCmd{}:
      submit_wire(cl, Commands.away(rest), "usage: /away [reason]")
    case NoticeCmd{}:
      submit_notice(cl, rest)
    case RawCmd{}:
      submit_wire(cl, Commands.raw(rest), "usage: /raw IRC-COMMAND [parameters] (one line, at most 510 bytes)")
    case Unknown{}:
      submit_unknown(cl, verb)

def submit_plain.on(+cl: Cl.Client, +input: String, on_server: Bool) -> Cl.Client & List<&2, String>:
  match on_server:
    case True{}:
      (echo_err(cl, "not in a channel — /join #chan first"), empty_out())
    case False{}:
      +tgt = Cl.active_buf_name(cl)
      +bi = Cl.active_of(cl)
      send_message(cl, bi, tgt, input)

def submit_plain.virtual(virtual: Bool, +cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  match virtual:
    case True{}:
      (echo_err(cl, "read-only buffer"), empty_out())
    case False{}:
      submit_plain.on(cl, input, Nat.is_eq(Cl.active_of(cl), 0n))

def submit_plain(+cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  submit_plain.virtual(active_is_synthetic(cl), cl, input)

def submit_parsed(+cl: Cl.Client, input: Input) -> Cl.Client & List<&2, String>:
  match input:
    case EmptyInput{}: (cl, empty_out())
    case PlainInput{+text}: submit_plain(cl, text)
    case CommandInput{cmd, +verb, +rest}: submit_cmd.do(cl, verb, rest, cmd)

def submit(+cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  submit_parsed(cl, parse_input(input))

def out_all_ok.go(+xs: List<&2, String>, ok: Bool) -> Bool:
  match xs:
    case Nil{}:
      ok
    case Con{+h, t}:
      match ok:
        case False{}:
          False{}
        case True{}:
          out_all_ok.go(t, Irc.line_ok(h))

def out_all_ok(+xs: List<&2, String>) -> Bool:
  out_all_ok.go(xs, True{})

def submit_ok.fin(outs: List<&2, String>) -> Bool:
  out_all_ok(outs)

def submit_ok.pair(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, outs):
      submit_ok.fin(outs)

def submit_ok(+cl: Cl.Client, +input: String) -> Bool:
  submit_ok.pair(submit(cl, input))

def submit_is_quit.parsed(input: Input) -> Bool:
  match input:
    case CommandInput{Quit{}, _, _}: True{}
    case _: False{}

def submit_is_quit(+input: String) -> Bool:
  submit_is_quit.parsed(parse_input(input))

def submit_halt_ok() -> Bool:
  submit_is_quit("/quit") && submit_is_quit("/quit bye") && Bool.not(submit_is_quit("hello")) && Bool.not(submit_is_quit("/join #x"))

def submit_is_connect.parsed(input: Input) -> Bool:
  match input:
    case CommandInput{_, +verb, _}: Irc.ieq(verb, "connect") || Irc.ieq(verb, "reconnect")
    case _: False{}

def submit_is_connect(+input: String) -> Bool:
  submit_is_connect.parsed(parse_input(input))

def connect_from_input.verb(is_recon: Bool, +rest: String) -> Conn:
  match is_recon:
    case True{}:
      ConnReconnect{}
    case False{}:
      connect_parse(Irc.drop_spaces(rest))

def connect_from_input.parsed(input: Input) -> Conn:
  match input:
    case CommandInput{_, +verb, +rest}:
      connect_from_input.verb(Irc.ieq(verb, "reconnect"), rest)
    case _: ConnBad{}

def connect_from_input(+input: String) -> Conn:
  connect_from_input.parsed(parse_input(input))

def connect_parse_ok.on(c: Conn) -> Bool:
  match c:
    case ConnOk{+host, port}:
      String.eq(host, "irc.example.net") && U32.is_eq(port, 6668)
    case ConnBad{}:
      False{}
    case ConnReconnect{}:
      False{}
    case ConnDefault{_}:
      False{}

def connect_default_ok.on(c: Conn) -> Bool:
  match c:
    case ConnDefault{_}: True{}
    case _: False{}

def connect_bad.on(c: Conn) -> Bool:
  match c:
    case ConnBad{}:
      True{}
    case ConnOk{_, _}:
      False{}
    case ConnReconnect{}:
      False{}
    case ConnDefault{_}:
      False{}

def connect_port_range_ok() -> Bool:
  connect_bad.on(connect_parse("h 0"))
    && connect_bad.on(connect_parse("h 99999"))
    && connect_bad.on(connect_parse("h 4294967295"))
    && connect_parse_ok.on(connect_parse("irc.example.net 6668"))

def connect_parse_ok() -> Bool:
  connect_parse_ok.on(connect_parse("irc.example.net 6668"))
    && connect_default_ok.on(connect_parse("irc.example.net"))
    && connect_port_range_ok()
