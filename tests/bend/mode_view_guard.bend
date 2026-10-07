# SPDX-License-Identifier: Apache-2.0
# Stored-row and production View projections for MODE regression guards.
# The row's actual kind selects the same renderer used by live paint.
import Base
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/view.bend as V

def last(+cl: Cl.Client) -> Maybe<&2, Cl.Line>:
  List.last(&2, Cl.Line, Cl.active_buf_lines(cl))

def stored.line(got: Maybe<&2, Cl.Line>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Line{_, _, text, _, _}}: text

def stored(+cl: Cl.Client) -> String:
  stored.line(last(cl))

def visible.line(got: Maybe<&2, Cl.Line>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Line{kind, _, text, _, _}}: V.spans_text(V.line_spans_for(kind, text))

def visible(+cl: Cl.Client) -> String:
  visible.line(last(cl))
