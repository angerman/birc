# SPDX-License-Identifier: Apache-2.0
# Cards/fullscreen paint seams (pure).
#
# ADAPTER BOUNDARY (branch c8/session-adapter): View-side half of the
# cards adapter. Parent owns merges; this file is new and disjoint by
# construction. FROZEN at parent HEAD (public signatures never edited
# here): cards.bend, cards.py.
#
# C8.5 backstop: the overlay re-validates the stored token against the
# live Media state and Client on EVERY paint before emitting it, so a
# disable/reset/eviction/endpoint/source transition that dispatch missed
# still closes the overlay instead of emitting a stale token. Dispatch
# still calls maintain on every step (see session_cards.bend); paint
# never relies on dispatch having run.
import Base
import ./buffer.bend as Cl
import ./media.bend as M
import ./view.bend as V
import ./cards.bend as C

# Re-validate, then paint. A zero or stale token paints nothing, and an
# unsupported terminal keeps exact URL text with no overlay.
def overlay_ops(+full: C.Fullscreen, +media: M.State, +client: Cl.Client, +rows: U32, +cols: U32) -> List<&2, V.DrawOp>:
  C.fullscreen_ops(rows, cols, C.maintain_full(full, media, client))

# One ready card paints at most C.ROWS_MAX dim text rows. The integrator
# splices these rows under the anchor chat line; Client and history stay
# raw (synthetic rows only, never stored).
def card_rows(+cards: C.State, +target: C.Target, +url: String, +w: U32) -> List<&2, V.BodyRow>:
  C.rows_for_target(cards, target, url, w)
