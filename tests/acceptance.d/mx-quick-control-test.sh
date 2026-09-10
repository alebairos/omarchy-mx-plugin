#!/bin/bash
#
# The widget on a real desktop: the panel opens where a person can see it and
# says what it should; the on-screen display appears for a device-reported
# change without a device read; a brightness write reaches the keyboard.
#
# Device contact is deliberate and counted: two writes and ONE read, at the
# end, to compare against device truth (CONTRIBUTING.md: verify against the
# device, not the widget). Nothing here polls.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command hyprctl
require_command jq
require_command grim
require_command omarchy-shell
hyprctl -j monitors >/dev/null 2>&1 || skip "no Hyprland session; acceptance needs a live desktop"

omarchy-shell shell ping >/dev/null 2>&1 || skip "omarchy-shell is not running"
qs -p "$OMARCHY_PATH/shell" ipc show 2>/dev/null | grep -q "target $PLUGIN_ID" \
  || skip "$PLUGIN_ID is not loaded in the running shell; install and enable it first"

ocr=1
command -v tesseract >/dev/null 2>&1 || { ocr=0; echo "# tesseract not installed; text assertions will be skipped"; }

status=$(widget status)
[[ $status == *"mode="* ]] || skip "no backlight-capable keyboard is paired ($status)"
orig_level=$(widget_field level)
orig_effect=$(widget_field effect)
pass "widget reports a keyboard: $status"

restore() {
  widget close >/dev/null 2>&1 || true
  # Put the widget's belief back where it started. This is an optimistic
  # write to the widget only -- the device was restored by the last `level`
  # write below -- so it raises one more OSD and touches nothing else.
  widget externalState "$orig_level:$orig_effect" >/dev/null 2>&1 || true
}
trap restore EXIT

# ---- the panel ------------------------------------------------------------

widget open >/dev/null
wait_until "panel opens on screen" 10 layer_on_screen "omarchy-keyboard-panel"
sleep 1
if ((ocr)); then
  wait_until "panel names the backlight control" 30 screen_contains "Backlight"
fi
screenshot "success-panel-open"

widget close >/dev/null
wait_until "panel leaves the screen" 10 layer_off_screen "omarchy-keyboard-panel"

# ---- the OSD, from a device-reported change, with no read -----------------

new_level=$(( (orig_level + 3) % 8 ))
widget externalState "$new_level:$orig_effect" >/dev/null
wait_until "OSD appears for a reported level change" 3 layer_present "omarchy-osd"
screenshot "success-osd-level"
[[ $(widget_field level) == "$new_level" ]] || fail "widget adopted the reported level" "$(widget status)"
[[ $(widget_field busy) == "false" ]] || fail "a reported level triggered no device read" "$(widget status)"
pass "reported level $new_level applied with no device read"
wait_until "OSD goes away on its own" 5 layer_absent "omarchy-osd"

# ---- a write reaches the keyboard: one read, against device truth ---------

transport="$HOME/.config/omarchy/plugins/$PLUGIN_ID/mx-device"
[[ -x $transport ]] || transport="$ROOT/mx-device"

target=$(( orig_level == 5 ? 6 : 5 ))
widget level "$target" >/dev/null
sleep 3
live=$(timeout 30 "$transport" state 2>/dev/null | jq -r '[.devices[] | select(.backlight)][0].backlight.level')
[[ $live == "$target" ]] || fail "brightness write reached the device" "asked for $target, device reports $live"
pass "device live level is $target after the write"

widget level "$orig_level" >/dev/null
pass "original level $orig_level written back"
