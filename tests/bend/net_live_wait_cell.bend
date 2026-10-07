# Pure payload characterization for the recursive Session wait-cell shape.
# This does not call recv_wait or qualify Chan.recv, Ui shutdown, or width.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/upload.bend as Up
import ../../src/bend/theme.bend as Theme

def request() -> Up.Request:
  Up.Request{Up.Scope{"synthetic.example", 7777, "#c"}, "/tmp/synthetic-one"}

def session(+state: Up.State, presented: Bool) -> Sess.Session:
  +st = Sess.session_online(Sess.session_demo_at(Cl.init("me", "synthetic.example"), "#c", 7777))
  +st2 = Sess.session_upload_draft(Sess.session_set_theme(st, Theme.Mono{}), "keep draft", 9)
  Sess.session_upload_mark(Sess.session_set_upload(st2, state), presented)

def busy_state(state: Up.State, wanted: Bool) -> Bool:
  match state:
    case Up.Busy{+req, +remaining, allowed}:
      Up.request_eq(req, request())
        && String.eq(String.join(remaining, "|"), "/tmp/synthetic-two")
        && Bool.not(Bool.xor(allowed, wanted))
    case _: False{}

def busy_saved(saved: Maybe<&2, Sess.Session>, wanted: Bool) -> Bool:
  match saved:
    case None{}: False{}
    case Some{+st}:
      U32.is_eq(Sess.session_port(st), 7777)
        && U32.is_eq(Sess.session_seed(st), 9)
        && String.eq(Sess.session_draft(st), "keep draft")
        && String.eq(Theme.show(Sess.session_theme(st)), "mono")
        && busy_state(Sess.session_upload(st), wanted)
        && Bool.not(Sess.session_upload_presented(st))

def busy_ok(+wanted: Bool) -> Bool:
  +st = session(Up.Busy{request(), ["/tmp/synthetic-two"], wanted}, False{})
  busy_saved(List.head(&2, Sess.Session, [st]), wanted)

def confirm_state(state: Up.State) -> Bool:
  match state:
    case Up.Confirm{+req, +remaining}:
      Up.request_eq(req, request())
        && String.eq(String.join(remaining, "|"), "/tmp/synthetic-two")
    case _: False{}

def confirm_saved(saved: Maybe<&2, Sess.Session>, wanted: Bool) -> Bool:
  match saved:
    case None{}: False{}
    case Some{+st}:
      confirm_state(Sess.session_upload(st))
        && Bool.not(Bool.xor(Sess.session_upload_presented(st), wanted))
        && String.eq(Sess.session_draft(st), "keep draft")

def confirm_ok(+wanted: Bool) -> Bool:
  +st = session(Up.Confirm{request(), ["/tmp/synthetic-two"]}, wanted)
  confirm_saved(List.head(&2, Sess.Session, [st]), wanted)

def empty_saved(saved: Maybe<&2, Sess.Session>) -> Bool:
  match saved:
    case None{}: True{}
    case Some{_}: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("busy_allowed_preserved", busy_ok(True{}))
    Unit <- E.must("busy_cancelled_not_revived", busy_ok(False{}))
    Unit <- E.must("warning_presented_preserved", confirm_ok(True{}))
    Unit <- E.must("warning_unpresented_not_armed", confirm_ok(False{}))
    Unit <- E.must("empty_has_no_fabricated_session", empty_saved(List.head(&2, Sess.Session, Nil{})))
    IO.print("net_live_wait_cell=ok")
