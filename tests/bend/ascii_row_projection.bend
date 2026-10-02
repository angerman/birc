# SPDX-License-Identifier: Apache-2.0
# Test-only projection for known ASCII source fixtures. Hidden wrap spaces
# still belong to the row. Do not use for Unicode source: even ASCII paint
# can be a replacement for a cluster, not proof that the source was ASCII.
import Base
import ../../src/bend/view.bend as V

def ascii(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{h, t}: U32.is_lt(Char.to_u32(h), 128) && ascii(t)

def text.valid(valid: Bool, +shown: String, source_chars: Nat) -> Maybe<&2, String>:
  match valid:
    case False{}: None{}
    case True{}: Some{shown ++ String.repeat(" ", Nat.sub(source_chars, String.length(shown)))}

def text(spans: List<&2, V.SpanOp>, +source_chars: Nat) -> Maybe<&2, String>:
  +shown = V.spans_text(spans)
  text.valid(ascii(shown) && Nat.is_ge(source_chars, String.length(shown)), shown, source_chars)

def show(spans: List<&2, V.SpanOp>, source_chars: Nat) -> String:
  Maybe.default(&2, String, text(spans, source_chars), "[ASCII projection rejected]")
