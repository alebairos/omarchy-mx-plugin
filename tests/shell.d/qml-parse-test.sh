#!/bin/bash
#
# The QML parses. That is the only thing qmllint can tell us here: it cannot
# resolve Omarchy's own types, so every import warning it prints is noise
# (AGENTS.md), but a syntax error is real and would otherwise be found only
# by restarting the shell.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

qmllint=$(command -v qmllint 2>/dev/null || true)
[[ -n $qmllint ]] || [[ -x /usr/lib/qt6/bin/qmllint ]] && qmllint=${qmllint:-/usr/lib/qt6/bin/qmllint}
[[ -n $qmllint ]] || skip "qmllint not installed (qt6-declarative); parse check needs it"

for qml in "$ROOT"/*.qml; do
  output=$("$qmllint" "$qml" 2>&1 || true)
  if grep -qiE "syntax error|^Error:|error:" <<<"$output"; then
    fail "$(basename "$qml") parses" "$(grep -iE 'syntax error|error:' <<<"$output" | head -5)"
  fi
  pass "$(basename "$qml") parses (import warnings ignored by design)"
done
