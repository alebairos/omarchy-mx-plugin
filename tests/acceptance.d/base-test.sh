#!/bin/bash
#
# Helpers for tests/acceptance.d/*-test.sh. The layer, screenshot and OCR
# helpers follow Omarchy's own test/acceptance.d/base-test.sh, so an
# assertion here reads the same as one upstream.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source tests/acceptance.d/base-test.sh from an acceptance test; do not run it directly" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
ARTIFACTS="${OMARCHY_ACCEPTANCE_DIR:-/tmp/omarchy-acceptance}"
PLUGIN_ID="alebairos.mx-quick-control"

mkdir -p "$ARTIFACTS"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  local description="$1"
  local detail="${2:-}"
  local step=${description,,}

  step=${step// /-}
  step=${step//[^a-z0-9-]/}

  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  screenshot "failure-$step"
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

skip() {
  printf 'ok - SKIPPED: %s\n' "$1"
  exit 0
}

require_command() {
  command -v "$1" >/dev/null || fail "required command is available: $1"
}

screenshot() {
  timeout 10 grim "$ARTIFACTS/$1.png" 2>/dev/null || true
}

# Capture at 2x: tesseract drops small caption text at native resolution.
screen_contains() {
  local text="$1"
  local snapshot="/tmp/mx-acceptance-ocr-$$.png"

  if ! timeout 10 grim -s 2 "$snapshot" 2>/dev/null; then
    rm -f "$snapshot"
    return 1
  fi
  tesseract "$snapshot" stdout --psm 11 2>/dev/null | grep -Fi -- "$text" >/dev/null
  local status=$?
  rm -f "$snapshot"
  return $status
}

# Poll a command until it succeeds; screenshot and fail on timeout.
wait_until() {
  local description="$1" timeout="$2"
  shift 2

  local deadline=$((SECONDS + timeout))

  until "$@" >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      fail "$description" "timed out after ${timeout}s waiting for: $*"
    fi
    sleep 0.2
  done

  pass "$description"
}

layer_present() {
  hyprctl -j layers | jq -e --arg ns "$1" '[.. | objects | select(.namespace? == $ns)] | length > 0'
}

layer_absent() {
  ! layer_present "$1"
}

# A layer can be mapped but parked off the monitor -- the keyboard panel
# surface stays mapped and is revealed by moving it on screen. Assert on
# geometry when what matters is that a person can actually see it.
layer_on_screen() {
  local monitors
  monitors=$(hyprctl -j monitors) || return 1

  hyprctl -j layers | jq -e --arg ns "$1" --argjson monitors "$monitors" '
    to_entries[]
    | .key as $name
    | .value as $levels
    | ($monitors[] | select(.name == $name)) as $m
    | (if ($m.transform // 0) % 2 == 1 then $m.height else $m.width end) / $m.scale | round as $width
    | (if ($m.transform // 0) % 2 == 1 then $m.width else $m.height end) / $m.scale | round as $height
    | [$levels | .. | objects | select(.namespace? == $ns)][]
    | select(
        .x + .w > 0 and .x < $width and
        .y + .h > 0 and .y < $height
      )
  ' >/dev/null
}

layer_off_screen() {
  ! layer_on_screen "$1"
}

# The plugin's IPC, through Omarchy's own forwarder.
widget() {
  omarchy-shell "$PLUGIN_ID" "$@"
}

widget_field() {
  widget status | grep -oE "$1=[^ ]+" | head -1 | cut -d= -f2
}
