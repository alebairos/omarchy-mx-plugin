#!/bin/bash
#
# Helpers for tests/shell.d/*-test.sh. Modelled on Omarchy's own
# test/shell.d/base-test.sh so a contributor who knows one knows the other.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source tests/shell.d/base-test.sh from a shell test; do not run it directly" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SHELL_TEST_DIR="$ROOT/tests/shell.d"

export ROOT
# The installed shell, whose Ui/ and Commons/ the widget imports. Omarchy's
# session exports this; a plain terminal may not.
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  local description="$1"
  local detail="${2:-}"

  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

# A test that cannot run here is not a failure. Say why, loudly enough to be
# seen in the runner's output, and pass.
skip() {
  printf 'ok - SKIPPED: %s\n' "$1"
  exit 0
}

require_command() {
  local command="$1"

  command -v "$command" >/dev/null || fail "required command is available: $command"
}

# WAYLAND_DISPLAY proves the variable was inherited, not that the compositor
# answers. Probe the socket, then Hyprland itself, since a compositor that
# died mid-session can leave its socket behind.
compositor_reachable() {
  local socket=${WAYLAND_DISPLAY:-}

  [[ -n $socket ]] || return 1
  [[ $socket == /* ]] || socket=${XDG_RUNTIME_DIR:-}/$socket
  [[ -S $socket ]] || return 1
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0

  local attempt
  for attempt in 1 2 3; do
    hyprctl -j monitors >/dev/null 2>&1 && return 0
    (( attempt < 3 )) && sleep 0.5
  done

  return 1
}

require_compositor() {
  local description="$1"

  if compositor_reachable; then
    # Quickshell leaves through qFatal() when its connection drops. Keep that
    # abort from writing a core; the test still fails, just without debris.
    ulimit -c 0 2>/dev/null || true
    return 0
  fi

  skip "no Wayland compositor; $description needs one"
}

require_quickshell() {
  command -v quickshell >/dev/null 2>&1 || skip "quickshell not installed; $1 needs it"
}
