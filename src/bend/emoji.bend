# SPDX-License-Identifier: Apache-2.0
# View-only emoji shortcodes. IRC wire and history keep the raw `:name:`
# source; the View scanner substitutes glyphs at paint time only. Code spans
# and URLs stay opaque. Matching is exact and case-sensitive; unknown names
# remain literal. No two names share a prefix, so table order is irrelevant.
import Base

type Entry is Data:
  Entry{name: String, text: String}

# One cons builds one table row. aliases() folds the catalog here once per
# call site; callers bind the result instead of rebuilding for each scan.
# First 22 rows are the exact chat-reference table (P03); later rows extend
# it with common single-glyph shortcodes. Glyphs are single Unicode scalars
# inside the existing cluster-width contract (columns.bend).
def entry_cons(+name: String, +text: String, rest: List<&2, Entry>) -> List<&2, Entry>:
  Entry{name, text} <> rest

def aliases() -> List<&2, Entry>:
  entry_cons(":eyes:", "👀",
  entry_cons(":wave:", "👋",
  entry_cons(":thumbsup:", "👍",
  entry_cons(":thumbs-up:", "👍",
  entry_cons(":+1:", "👍",
  entry_cons(":tada:", "🎉",
  entry_cons(":fire:", "🔥",
  entry_cons(":rocket:", "🚀",
  entry_cons(":heart:", "❤",
  entry_cons(":sparkles:", "✨",
  entry_cons(":bulb:", "💡",
  entry_cons(":clap:", "👏",
  entry_cons(":brain:", "🧠",
  entry_cons(":zap:", "⚡",
  entry_cons(":star:", "⭐",
  entry_cons(":joy:", "🤣",
  entry_cons(":raised_hands:", "🙌",
  entry_cons(":bow:", "🙇",
  entry_cons(":party:", "🥳",
  entry_cons(":bug:", "🐛",
  entry_cons(":globe:", "🌍",
  entry_cons(":boom:", "💥",
  entry_cons(":smile:", "😄",
  entry_cons(":laughing:", "😆",
  entry_cons(":wink:", "😉",
  entry_cons(":cry:", "😢",
  entry_cons(":sob:", "😭",
  entry_cons(":angry:", "😠",
  entry_cons(":thinking:", "🤔",
  entry_cons(":sweat_smile:", "😅",
  entry_cons(":innocent:", "😇",
  entry_cons(":sleeping:", "😴",
  entry_cons(":mask:", "😷",
  entry_cons(":nerd_face:", "🤓",
  entry_cons(":sunglasses:", "😎",
  entry_cons(":ghost:", "👻",
  entry_cons(":skull:", "💀",
  entry_cons(":poop:", "💩",
  entry_cons(":ok_hand:", "👌",
  entry_cons(":crossed_fingers:", "🤞",
  entry_cons(":call_me_hand:", "🤙",
  entry_cons(":muscle:", "💪",
  entry_cons(":pray:", "🙏",
  entry_cons(":fist:", "✊",
  entry_cons(":coffee:", "☕",
  entry_cons(":beer:", "🍺",
  entry_cons(":pizza:", "🍕",
  entry_cons(":cake:", "🍰",
  entry_cons(":gift:", "🎁",
  entry_cons(":trophy:", "🏆",
  entry_cons(":check:", "✅",
  entry_cons(":x:", "❌",
  entry_cons(":warning:", "⚠",
  entry_cons(":question:", "❓",
  entry_cons(":exclamation:", "❗",
  entry_cons(":info:", "ℹ",
  entry_cons(":sun:", "☀",
  entry_cons(":moon:", "🌙",
  entry_cons(":cloud:", "☁",
  entry_cons(":snowflake:", "❄",
  entry_cons(":ocean:", "🌊",
  entry_cons(":car:", "🚗",
  entry_cons(":airplane:", "✈",
  entry_cons(":ship:", "🚢",
  entry_cons(":dog:", "🐶",
  entry_cons(":cat:", "🐱",
  entry_cons(":whale:", "🐳",
  entry_cons(":butterfly:", "🦋",
  entry_cons(":rose:", "🌹",
  entry_cons(":gem:", "💎",
  entry_cons(":rofl:", "🤣",
  entry_cons(":rolling-on-the-floor-laughing:", "🤣",
  Nil{}))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
