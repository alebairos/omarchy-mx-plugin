# Quickstart: MX Quick Control

Manual validation guide — per constitution (Development Workflow), this
project has no automated test harness; every user story is proven against
real hardware using the steps below.

## Prerequisites

- `solaar` installed and working (`solaar show` lists at least one paired
  Logitech device). See this repo's README for the one-line install.
- A Logitech keyboard with `BACKLIGHT2` support paired via a Bolt/Unifying
  receiver, for User Stories 2 and 3. Any Logitech device with battery
  reporting is enough for User Story 1.
- Omarchy's `omarchy-shell` running (standard on any Omarchy install).

## Install

```bash
cp -r plugin ~/.config/omarchy/plugins/mx-quick-control
omarchy-shell shell rescanPlugins
```

Then add it to the bar (adjust section to taste):

```bash
omarchy bar put alebairos.mx-quick-control --section right
```

## Validate User Story 1 — battery at a glance

1. Run `solaar show` in a terminal and note each paired device's battery %.
2. Look at the bar. **Expected**: the widget shows battery for each
   detected device, matching step 1.
3. **Expected**: no crash/error shown if a second device (e.g. the mouse)
   has no backlight — only battery is shown for it.

## Validate User Story 2 — toggle backlight

1. Confirm current state: `solaar config <N> backlight` (replace `<N>`
   with the keyboard's device index from `solaar show`).
2. Click the widget's backlight control.
   **Expected**: physical keyboard backlight visibly changes (on↔off), and
   `solaar config <N> backlight` reflects the new mode within one refresh.
3. Click again. **Expected**: toggles back to the original state.

## Validate User Story 3 — step brightness

1. Ensure backlight is on (mode `Manual`) at a non-extreme level.
2. Scroll up on the widget. **Expected**: keyboard visibly brightens one
   step; `solaar config <N> backlight_level` confirms the increment.
3. Scroll down twice. **Expected**: dims two steps; does not go below 0.
4. Scroll up repeatedly past the device's max. **Expected**: stops
   increasing at the device's actual maximum, no CLI error surfaces to the
   user (see contracts/solaar-cli.md, levelMax detection).

## Validate graceful degradation (Edge Cases)

1. Temporarily rename/hide `solaar` from `PATH`, or unplug the receiver.
2. **Expected**: widget hides itself (or shows a clear disabled state) —
   the rest of the bar keeps working normally, no error dialog, no freeze.
3. Restore `solaar`/the receiver. **Expected**: widget reappears within one
   refresh interval (default 60s) or after a manual
   `qs ipc call alebairos.mx-quick-control refresh`.
