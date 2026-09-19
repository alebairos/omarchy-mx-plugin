#!/bin/bash
#
# Capture the marketplace preview image. See spec.md in this directory for
# why each step is the way it is; the short version:
#
#   - The panel is drawn inside a FULLSCREEN layer surface, so its layer
#     rectangle is the whole monitor and is useless as a crop. The drawn
#     bounds are derived by differencing a closed-panel frame against an
#     open-panel one: whatever changed is the panel.
#   - Hyprland 0.56.2 routes `hyprctl dispatch` through Lua. The shell form
#     `hyprctl dispatch togglespecialworkspace scratchpad` exits 7.
#   - `grim` blocks forever, rather than failing, when the display is in
#     DPMS off. Every capture runs under `timeout`.
#   - The output is committed to a PUBLIC repository and republished by the
#     marketplace. Anything on screen ships with it, so this refuses to run
#     unless the visible workspace is empty.
#
# Device contact: exactly two writes (mid level, restore) and, at the end,
# one read to prove the restore actually landed -- the widget's own status
# is optimistic and is not evidence (CONTRIBUTING.md).
#
# Usage:  capture-preview.sh [--in SECONDS] [outfile]
#
#   --in N   wait N seconds before checking the screen and capturing, so you
#            can start this from a terminal and then switch to an empty
#            workspace. Without it the terminal you typed into is itself a
#            window on the visible workspace, and the check below refuses.
#
#   RESTORE_LEVEL=n   use n as the level to restore, when the widget's idea
#                     of the current level is already wrong when you start.

set -euo pipefail

PLUGIN_ID="alebairos.mx-quick-control"
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
DELAY=0
OUT=""
while (( $# )); do
  case $1 in
    --in) DELAY=${2:?--in needs a number of seconds}; shift 2 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) OUT=$1; shift ;;
  esac
done
OUT="${OUT:-$ROOT/preview.png}"
TMP=$(mktemp -d)
PAD=28          # logical px of breathing room around the union
MID=5           # mid-travel, so the slider is not at either stop
SCALE=2         # grim -s: caption text must survive the card downscale

widget() { omarchy-shell "$PLUGIN_ID" "$@"; }
widget_field() { widget status | grep -oE "$1=[^ ]+" | head -1 | cut -d= -f2; }
die() { printf 'capture-preview: %s\n' "$1" >&2; exit 1; }

hypr() { hyprctl dispatch "$1" >/dev/null; }   # Lua form; see header

layer_on_screen() {   # same geometry test as tests/acceptance.d/base-test.sh
  local monitors
  monitors=$(hyprctl -j monitors) || return 1
  hyprctl -j layers | jq -e --arg ns "$1" --argjson monitors "$monitors" '
    to_entries[]
    | .key as $name | .value as $levels
    | ($monitors[] | select(.name == $name)) as $m
    | (if ($m.transform // 0) % 2 == 1 then $m.height else $m.width end) / $m.scale | round as $width
    | (if ($m.transform // 0) % 2 == 1 then $m.width else $m.height end) / $m.scale | round as $height
    | [$levels | .. | objects | select(.namespace? == $ns)][]
    | select(.x + .w > 0 and .x < $width and .y + .h > 0 and .y < $height)
  ' >/dev/null
}

wait_until() {
  local desc="$1" t="$2"; shift 2
  local deadline=$((SECONDS + t))
  until "$@" >/dev/null 2>&1; do
    (( SECONDS >= deadline )) && die "timed out waiting for $desc"
    sleep 0.2
  done
  echo "ok - $desc"
}

shot() { timeout 20 grim -s "$SCALE" "$1" || die "grim failed or timed out (display asleep?)"; }

# ---------------------------------------------------------------- preconditions
for c in hyprctl jq grim magick omarchy-shell; do
  command -v "$c" >/dev/null || die "required command missing: $c"
done

if omarchy-hyprland-session-locked 2>/dev/null; then
  die "the session is locked; the lock surface covers the bar. Unlock and re-run."
fi

if [[ $(hyprctl -j monitors | jq -r '[.[] | select(.focused) | .dpmsStatus] | first') != "true" ]]; then
  echo "display is in DPMS off; waking it"
  hypr 'hl.dsp.dpms("on")'
  sleep 2
fi

status=$(widget status)
[[ $status == *"mode="* ]] || die "no backlight-capable keyboard is paired ($status)"
ORIG="${RESTORE_LEVEL:-$(widget_field level)}"
echo "widget reports: $status"
echo "will restore level to: $ORIG"

SPECIAL=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .specialWorkspace.name // ""')

# Only put the level back if we actually moved it. Refusing early must cost
# the device nothing: AGENTS.md counts every contact, and a restore that
# writes a value the device already holds is still a contact.
WROTE_LEVEL=0

restore() {
  widget close >/dev/null 2>&1 || true
  if [[ -n $SPECIAL ]]; then
    echo "restoring $SPECIAL"
    hypr "hl.dsp.workspace.toggle_special(\"${SPECIAL#special:}\")" || true
  fi
  if (( WROTE_LEVEL )); then
    echo "restoring level $ORIG (device write 2 of 2)"
    widget level "$ORIG" >/dev/null 2>&1 || true
  else
    echo "device was never written; nothing to restore"
  fi
  rm -rf "$TMP"
}
trap restore EXIT

# The scratchpad overlay draws over the bar.
if [[ -n $SPECIAL ]]; then
  echo "hiding $SPECIAL for the capture"
  hypr "hl.dsp.workspace.toggle_special(\"${SPECIAL#special:}\")"
  sleep 1.5
fi

if (( DELAY > 0 )); then
  echo "switch to an empty workspace now; capturing in ${DELAY}s"
  for (( i = DELAY; i > 0; i-- )); do printf '\r  %2ds ' "$i"; sleep 1; done
  printf '\r        \r'
fi

ws=$(hyprctl -j activeworkspace | jq -r .name)
occupied=$(hyprctl -j clients | jq --arg ws "$ws" '[.[] | select(.workspace.name == $ws)] | length')
if (( occupied != 0 )); then
  hyprctl -j clients | jq -r --arg ws "$ws" '.[] | select(.workspace.name == $ws) | "    \(.class)  \(.title[0:50])"' >&2
  die "$occupied window(s) on workspace $ws, listed above. This image is published to a public
listing, so whatever is on screen goes with it. The terminal you are typing in counts -- rerun as
  $(basename "${BASH_SOURCE[0]}") --in 10
and switch to an empty workspace while it counts down."
fi

# ------------------------------------------------------- device write 1 of 2
echo "setting level $MID (device write 1 of 2)"
WROTE_LEVEL=1
widget level "$MID" >/dev/null
sleep 3

# ------------------------------------------- closed frame, open frame, diff
widget close >/dev/null 2>&1 || true
sleep 1
shot "$TMP/closed.png"

widget open >/dev/null
wait_until "panel is on screen" 15 layer_on_screen "omarchy-keyboard-panel"
sleep 2
shot "$TMP/open.png"

read -r MW MH < <(hyprctl -j monitors | jq -r '.[] | select(.focused) |
  "\((if (.transform // 0) % 2 == 1 then .height else .width end) / .scale | round) \((if (.transform // 0) % 2 == 1 then .width else .height end) / .scale | round)"')
BH=$(hyprctl -j layers | jq -r '[.. | objects | select(.namespace? == "omarchy-bar")][0].h')

# Everything below is in captured (SCALE x) pixels.
PADP=$((PAD * SCALE)); BARH=$((BH * SCALE)); MWP=$((MW * SCALE)); MHP=$((MH * SCALE))

# Diff BELOW the bar only. The bar is full of things that change on their own
# between two frames a few seconds apart -- the clock ticking is enough -- and
# any of them drags the bounding box across the whole screen. The first real
# capture came out 1889px wide for exactly that reason: the clock, at the far
# left, had changed. The panel is never in the bar, so the bar cannot help
# locate it and can only mislead.
body="${MWP}x$((MHP - BARH))+0+${BARH}"
magick "$TMP/closed.png" -crop "$body" +repage "$TMP/closed-body.png"
magick "$TMP/open.png"   -crop "$body" +repage "$TMP/open-body.png"

box=$(magick "$TMP/closed-body.png" "$TMP/open-body.png" -compose difference -composite \
        -colorspace Gray -threshold 8% -format '%@' info:)
echo "changed region below the bar (${SCALE}x px): $box"
[[ $box =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]] \
  || die "could not derive the panel bounds from the frame difference"
PW=${BASH_REMATCH[1]}; PH=${BASH_REMATCH[2]}; PX=${BASH_REMATCH[3]}
PY=$(( ${BASH_REMATCH[4]} + BARH ))   # back into full-frame coordinates

# A panel that appears to span most of the screen means something else moved.
# Say so rather than silently shipping a picture of the whole desktop.
(( PW < MWP / 2 )) || echo "WARNING: derived panel is ${PW}px wide, over half the screen. \
Something other than the panel changed between frames; check the output before using it." >&2

X1=$PX; Y1=0                       # include the bar strip above the panel
X2=$((PX + PW)); Y2=$((PY + PH))
(( Y2 < BARH )) && Y2=$BARH
X1=$(( X1 - PADP < 0 ? 0 : X1 - PADP ))
X2=$(( X2 + PADP > MWP ? MWP : X2 + PADP ))
Y2=$(( Y2 + PADP > MHP ? MHP : Y2 + PADP ))
W=$((X2 - X1)); H=$((Y2 - Y1))
echo "crop (${SCALE}x px): ${W}x${H}+${X1}+${Y1}   monitor ${MWP}x${MHP}   bar ${BARH}"

magick "$TMP/open.png" -crop "${W}x${H}+${X1}+${Y1}" +repage "$OUT"
echo "wrote $OUT"
magick identify "$OUT"

cat <<'NOTE'

Still to do by hand:
  1. Look at the image. Nothing private in frame? Widget and panel both legible?
  2. Confirm the restore landed against the DEVICE, not the widget:
       mx-device state | jq '[.devices[]|select(.backlight)][0].backlight.level'
     The widget's own status is optimistic; one restore has already been
     observed to silently not take.
NOTE
