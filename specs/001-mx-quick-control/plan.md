# Implementation Plan: MX Quick Control

**Branch**: `001-mx-quick-control` | **Date**: 2026-09-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-mx-quick-control/spec.md`

## Summary

A single Omarchy bar widget (`alebairos.mx-quick-control`) that shows paired
Logitech device battery status and lets the user toggle/step keyboard
backlight, all by shelling out to the already-installed `solaar` CLI. No new
daemon, no direct HID++ handling — the widget is a thin, periodically
refreshing view + click/scroll handlers over `solaar config`/`solaar show`.

## Technical Context

**Language/Version**: QML (Qt Quick), running inside the existing
`omarchy-shell` Quickshell process — no separate runtime/toolchain to add.

**Primary Dependencies**: `solaar` CLI (external process, already verified
installed and working on this machine). No QML library dependencies beyond
what `omarchy-shell` already provides (`Quickshell.Io.Process`, `Timer`,
Omarchy's `qs.Ui`/`qs.Commons` widget helpers).

**Storage**: N/A — stateless; every value is re-read live from `solaar` on
each refresh tick, nothing is persisted by the plugin itself.

**Testing**: No automated test harness (per constitution, Development
Workflow) — manual verification via `quickstart.md` against real paired
hardware is the acceptance gate for every user story.

**Target Platform**: Omarchy's Quickshell-based shell (`omarchy-shell`) on
this Hyprland/Linux desktop.

**Project Type**: Omarchy shell plugin, `bar-widget` kind (single QML file +
manifest, following the same shape as the built-in `SystemUpdate` and
`Microphone` bar widgets).

**Performance Goals**: Bar stays responsive at all times; `solaar` calls run
as async `Process` invocations (never block the UI thread), refreshed on a
generous `Timer` interval (default 60s) since `solaar`'s own device
enumeration takes a few seconds per call and there is no need for
sub-second freshness on battery/backlight state.

**Constraints**: Exactly one `Process` + one `Timer` per constitution
Principle V (no new daemon/systemd unit); widget MUST hide (not error) when
`solaar` or a supported device is absent (constitution Principle IV, spec
FR-005).

**Scale/Scope**: Single user, single Bolt/Unifying receiver, one keyboard +
optional one mouse (spec Assumptions) — v1 does not support multiple
receivers or multi-seat/multi-host fleets.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Simplicity First | Scope limited to spec's 3 user stories (battery view, backlight toggle, brightness step); no macros/RGB/multi-device management | PASS |
| II. Shell Out, Don't Reimplement | All device interaction via `solaar config`/`solaar show` `Process` calls; no `/dev/hidraw*` or `/dev/input/*` access | PASS |
| III. Standard Omarchy Plugin Conventions | `bar-widget` kind, `manifest.json` + single QML file, same shape as built-in `SystemUpdate`/`Microphone` widgets | PASS |
| IV. Graceful Degradation | Widget `visible` bound to a detected-device flag; `Process` failures caught via `onExited`, never thrown to the shell | PASS |
| V. No Speculative Dependencies | Only dependency is `solaar` (already present); refresh uses QML `Timer`, not an external cron/systemd unit | PASS |

No violations — Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/001-mx-quick-control/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/            # Phase 1 output
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

**Structure Decision**: Single Omarchy shell plugin directory at the repo
root, mirroring exactly what `omarchy plugin clone` produces so it can be
dropped into `~/.config/omarchy/plugins/` unmodified.

```text
plugin/
├── manifest.json          # kind: bar-widget, entryPoints.barWidget
└── MxQuickControl.qml     # BarWidget: Process calls to solaar, Timer refresh, click/scroll handlers

README.md                  # install instructions (copy to ~/.config/omarchy/plugins/)
LICENSE
```

## Complexity Tracking

*No entries — Constitution Check has no violations.*
