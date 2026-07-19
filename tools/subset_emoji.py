"""Emoji font subsetter for Goat (Козёл) — bundles the exact emoji the app uses.

CanvasKit downloads Noto fonts from fonts.gstatic.com at runtime for glyphs the
bundled fonts miss; offline (or during a network hiccup) reactions/achievements
render as tofu plus a "Could not find a set of Noto fonts" warning. This tool
subsets the monochrome Noto Emoji (color CBDT/COLR is unreliable in CanvasKit)
down to the ~20 codepoints in app string literals — ~10 KB instead of ~310 KB.

Deterministic (pinned upstream release, sha256-verified, SOURCE_DATE_EPOCH=0);
writes app/assets/fonts/NotoEmojiSubset.ttf.
Run:  py tools/subset_emoji.py   (needs:  py -m pip install fonttools)
"""

from __future__ import annotations

import hashlib
import io
import os
import urllib.request

# Deterministic head.modified/name timestamps — must be set before fontTools
# is imported (it reads the env var at import time).
os.environ["SOURCE_DATE_EPOCH"] = "0"

from fontTools import subset  # noqa: E402
from fontTools.ttLib import TTFont  # noqa: E402
from fontTools.varLib import instancer  # noqa: E402

# Pinned upstream source; the hash was computed from this exact URL once and
# is verified on every run (including against a previously cached download).
# Monochrome Noto Emoji left the noto-emoji repo years ago (its releases ship
# color-only fonts), so the pin is the google/fonts distribution — a variable
# font (wght 300-700) that gets instanced to the Regular default below.
SOURCE_URL = (
    "https://raw.githubusercontent.com/google/fonts/"
    "8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/notoemoji/NotoEmoji%5Bwght%5D.ttf"
)
SOURCE_SHA256 = "de6c18832938afc99caf132b39d6a30a19bac7f2e812e28db2535b4608d27551"

CACHE_PATH = os.path.join(os.path.dirname(__file__), ".cache", "NotoEmoji-Regular.ttf")
OUT_PATH = os.path.join(
    os.path.dirname(__file__), "..", "app", "assets", "fonts", "NotoEmojiSubset.ttf"
)

# Every emoji that appears in an app string literal (reactions, achievements,
# stats, the 🏆/🐐 moments) plus the suit symbols and VS16. Grep before adding
# new emoji to the app:  rg -n "[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}]" app/lib
CODEPOINTS = [
    0x1F44D,  # 👍 reaction thumbs_up
    0x1F602,  # 😂 reaction laugh
    0x1F631,  # 😱 reaction shock
    0x1F410,  # 🐐 reaction goat / game-over / stats
    0x1F525,  # 🔥 reaction fire / win-streak stat
    0x1F62D,  # 😭 reaction cry
    0x1F389,  # 🎉 achievement first_win
    0x1F451,  # 👑 achievement
    0x2663,  # ♣ achievement (♣️ = 2663 FE0F)
    0x1F4B0,  # 💰 achievement
    0x26A1,  # ⚡ achievement
    0x1F393,  # 🎓 achievement
    0x1F3C1,  # 🏁 achievement
    0x1F50C,  # 🔌 achievement
    0x1F6D6,  # 🛖 achievement
    0x1FAE5,  # 🫥 achievement
    0x1F3C6,  # 🏆 achievement banner / stats
    0x1F3B2,  # 🎲 games-played stat
    0xFE0F,  # variation selector-16 (emoji presentation)
    0x2660,  # ♠ suit text fallbacks
    0x2665,  # ♥ suit text fallbacks
    0x2666,  # ♦ suit text fallbacks
]


def fetch_source() -> bytes:
    if os.path.exists(CACHE_PATH):
        data = open(CACHE_PATH, "rb").read()
    else:
        print(f"downloading {SOURCE_URL}")
        data = urllib.request.urlopen(SOURCE_URL).read()
        os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
        with open(CACHE_PATH, "wb") as f:
            f.write(data)
    digest = hashlib.sha256(data).hexdigest()
    if digest != SOURCE_SHA256:
        raise SystemExit(
            f"sha256 mismatch for NotoEmoji-Regular.ttf:\n"
            f"  expected {SOURCE_SHA256}\n  got      {digest}\n"
            f"Delete {CACHE_PATH} and retry, or update the pin deliberately."
        )
    return data


def main() -> None:
    data = fetch_source()

    options = subset.Options()
    options.hinting = False  # emoji outlines don't need hints; saves bytes
    # Keep only the identification/legal name records (family/style/license).
    options.name_IDs = [0, 1, 2, 3, 4, 6, 13, 14]
    options.name_legacy = False
    options.name_languages = [0x409]  # en-US

    font = subset.load_font(io.BytesIO(data), options)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=CODEPOINTS)
    subsetter.subset(font)

    # Pin the weight axis at its Regular default → a plain static TTF
    # (drops fvar/gvar/HVAR; CanvasKit needs no variation machinery).
    instancer.instantiateVariableFont(font, {"wght": 400}, inplace=True)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    subset.save_font(font, OUT_PATH, options)

    # Verify: every requested codepoint must resolve to a glyph. FE0F is
    # exempt — Noto Emoji maps it via cmap format-14 variation sequences,
    # not the plain unicode cmap.
    cmap = TTFont(OUT_PATH).getBestCmap()
    missing = [cp for cp in CODEPOINTS if cp != 0xFE0F and cp not in cmap]
    if missing:
        raise SystemExit(
            "codepoints missing from subset cmap: "
            + ", ".join(f"U+{cp:04X}" for cp in missing)
        )

    size = os.path.getsize(OUT_PATH)
    print(f"NotoEmojiSubset.ttf  {size / 1024:.1f} KB  ({len(cmap)} codepoints mapped)")


if __name__ == "__main__":
    main()
