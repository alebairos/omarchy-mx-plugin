#!/bin/bash
#
# Every Nerd Font glyph the QML draws must exist in an installed font.
#
# A codepoint the font lacks renders as a tofu box, and nothing else catches
# it: the QML parses, the widget loads, the tests pass. It has shipped once
# already (a glyph mangled by a text edit; see AGENTS.md). The check is
# static and fast, so it runs on every machine that has fontconfig.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command -v fc-list >/dev/null 2>&1 || skip "fontconfig (fc-list) not installed; glyph coverage needs it"
# fontconfig alone is not enough: a machine with fonts but no Nerd Font (a
# stock CI runner) would fail every glyph, which says nothing about the
# code. CI installs one before this tier so the check is real there too.
# Not `grep -q`: under `set -o pipefail` it exits on the first match, fc-list
# takes SIGPIPE, the pipeline "fails", and the test skips on a machine that
# has the font -- which is exactly what it did, twice, before this comment.
fc-list | grep -i "nerd font" >/dev/null || skip "no Nerd Font installed; glyph coverage needs one (Omarchy ships JetBrainsMono Nerd Font)"
require_command python3

codepoints=$(python3 - "$ROOT" <<'PY'
import sys, glob, os
root = sys.argv[1]
cps = set()
for path in glob.glob(os.path.join(root, "*.qml")):
    for ch in open(path, encoding="utf-8").read():
        if ord(ch) >= 0xE000:          # private-use and astral: Nerd Font territory
            cps.add(f"{ord(ch):x}")
print(" ".join(sorted(cps)))
PY
)

[[ -n $codepoints ]] || fail "the QML uses at least one Nerd Font glyph" "extractor found none; it is probably broken"

for cp in $codepoints; do
  family=$(fc-list ":charset=$cp" family 2>/dev/null | head -1)
  [[ -n $family ]] || fail "glyph U+${cp^^} exists in an installed font" "no installed font has U+${cp^^}; it would render as a box"
  pass "glyph U+${cp^^} is provided by: $family"
done
