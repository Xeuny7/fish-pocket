#!/usr/bin/env python3
"""Make the Bot tab navigation bar transparent so the pale wash shows through.

Run by CI from scripts/build-engine.sh, right after tooling/skin/apply.py.
Idempotent; a missing anchor fails the build instead of shipping a white band.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BOT = ROOT / "app" / "DshIOS" / "Views" / "BotViews.swift"

ANCHOR = '        .navigationTitle("Bot")\n        .navigationBarTitleDisplayMode(.inline)'
PATCHED = (
    '        .navigationTitle("Bot")\n'
    "        .toolbarBackground(.hidden, for: .navigationBar)\n"
    '        .navigationBarTitleDisplayMode(.inline)'
)

text = BOT.read_text(encoding="utf-8")
if PATCHED in text:
    print("skin: BotViews.swift: nav transparent already applied")
elif ANCHOR in text:
    BOT.write_text(text.replace(ANCHOR, PATCHED, 1), encoding="utf-8")
    print("skin: BotViews.swift: nav transparent patched")
else:
    print("skin: BotViews.swift: nav anchor missing (upstream changed)", file=sys.stderr)
    raise SystemExit(1)
