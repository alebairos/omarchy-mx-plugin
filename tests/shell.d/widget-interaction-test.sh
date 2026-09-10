#!/bin/bash
#
# The widget under synthetic input, against a fake transport.
#
# Loads the real MxQuickControl.qml into a throwaway quickshell (see
# fixtures/widget/shell.qml), clicks the bar icon, the slider and the toggle,
# reports a device state, presses Escape -- and then reads the fake
# transport's log to assert what the UI actually SENT: one write per gesture,
# and no read after a device-reported change. Omarchy's contract-test
# harness plus QtTest's TestEvent; nothing here touches hardware.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_compositor "widget interaction test"
require_quickshell "widget interaction test"
require_command jq
require_command python3

TMPDIR=""
QS_PID=""
cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

TMPDIR=$(mktemp -d)
plugin="$TMPDIR/plugin"
config="$TMPDIR/config"
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
mkdir -p "$plugin" "$config" "$TMPDIR/home"

# The widget resolves its transport relative to its own file, so the fake
# takes the real one's name and place.
cp "$ROOT/MxQuickControl.qml" "$ROOT/Model.js" "$plugin/"
cp "$ROOT/tests/fake-mx-device" "$plugin/mx-device"
chmod +x "$plugin/mx-device"

cp "$SHELL_TEST_DIR/fixtures/widget/shell.qml" "$config/shell.qml"
ln -s "$OMARCHY_PATH/shell/Ui" "$config/Ui"
ln -s "$OMARCHY_PATH/shell/Commons" "$config/Commons"

: >"$TMPDIR/fake.log"
printf 'mode=Manual\nlevel=4\n' >"$TMPDIR/fake.state"

MX_QML_TEST_RESULT="$result" \
MX_QML_WIDGET_URL="file://$plugin/MxQuickControl.qml" \
FAKE_MXD_LOG="$TMPDIR/fake.log" \
FAKE_MXD_STATE="$TMPDIR/fake.state" \
FAKE_MXD_FIXTURE="$ROOT/tests/fixtures/mx-device-keyboard-and-mouse.json" \
HOME="$TMPDIR/home" \
XDG_CONFIG_HOME="$TMPDIR/home/.config" \
XDG_CACHE_HOME="$TMPDIR/home/.cache" \
XDG_STATE_HOME="$TMPDIR/home/.local/state" \
QML2_IMPORT_PATH="$OMARCHY_PATH/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$OMARCHY_PATH/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  quickshell -p "$config" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..300}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,120p' "$log" >&2
    fail "quickshell stayed up until the verdict was written"
  fi
  sleep 0.1
done
[[ -s $result ]] || { sed -n '1,120p' "$log" >&2; fail "widget interaction test wrote a verdict within 30s"; }

# Every step the fixture passed is a line here; every failure is fatal.
jq -r '.passes[]' "$result" | while read -r line; do pass "$line"; done
if [[ $(jq -r '.ok' "$result") != "true" ]]; then
  jq -r '.failures[]' "$result" >&2
  grep -iE "error|warn" "$log" | grep -v "host portal" | head -20 >&2 || true
  fail "every interaction step passed"
fi

# A binding that throws on the first frame is a real defect the shell would
# only log: the bar is injected after creation, so every `bar.x` read needs a
# guard. This test found eighteen of them once; keep it that way.
if grep -q "TypeError" "$log"; then
  grep "TypeError" "$log" | head -5 >&2
  fail "no binding threw while the widget loaded"
fi
pass "no binding threw while the widget loaded"

# What the UI sent. The fake logs one argv per line.
reads=$(grep -c '^state' "$TMPDIR/fake.log" || true)
writes=$(grep -c '^set ' "$TMPDIR/fake.log" || true)
[[ $reads == 2 ]] || fail "exactly two reads: one at load, one on opening the panel" "reads=$reads
$(cat "$TMPDIR/fake.log")"
pass "two reads only: at load and on opening -- none after the reported state"
[[ $writes == 2 ]] || fail "exactly two writes: the slider click and the toggle" "writes=$writes
$(cat "$TMPDIR/fake.log")"
grep -q -- '--level 7' "$TMPDIR/fake.log" || fail "the slider click wrote level 7" "$(cat "$TMPDIR/fake.log")"
grep -q -- '--level 0' "$TMPDIR/fake.log" || fail "the toggle wrote level 0" "$(cat "$TMPDIR/fake.log")"
pass "two writes only: level 7 from the slider, level 0 from the toggle"
