# Research: MX Quick Control

## Decision: Plugin kind = `bar-widget`

**Rationale**: Inspected `/usr/share/omarchy/shell/plugins/bar/widgets/` on
this machine. Persistent status icons in the bar (e.g. `SystemUpdate.qml`,
`Microphone.qml`) use `manifest.json` with `"kinds": ["bar-widget"]` and an
`entryPoints.barWidget` pointing at a QML file that extends the `BarWidget`
QML type. This is a different plugin kind from the `overlay` kind used by
full-screen pickers (`Emojis.qml`, `Clipboard.qml`) — those aren't the right
shape for an always-visible status indicator.

**Alternatives considered**:
- `overlay` kind (like the emoji picker): rejected — overlays are
  triggered/dismissed UIs, not persistent bar icons; wrong fit for
  "glance at battery/backlight status".
- Cloning and modifying `omarchy.bar` itself: rejected — the Omarchy skill
  guide explicitly warns against editing built-in plugin source, and this
  feature doesn't need to change the bar's own layout logic, just add one
  more widget to it.

## Decision: Shell out via Quickshell's `Process` (Quickshell.Io), not a shell script wrapper

**Rationale**: `SystemUpdate.qml`'s reference pattern runs `Process` with a
`command` array and reads `onExited`. This is async by construction (does
not block the QML/UI thread) and is the same mechanism every other built-in
widget already uses for external commands, satisfying constitution
Principle II (shell out to `solaar`, don't reimplement) without inventing a
new integration pattern.

**Alternatives considered**:
- A helper shell script the QML calls: rejected — adds an extra file/moving
  part for no benefit; `solaar config`/`solaar show` are already simple,
  single commands.
- A persistent `solaar` D-Bus/API-mode connection: rejected — out of scope
  per constitution Principle V (no new daemon), and the CLI-based command
  latency (a few seconds) is acceptable at a 60s refresh cadence per the
  Performance Goals in plan.md.

## Decision: Refresh via QML `Timer`, default 60s interval

**Rationale**: `solaar show`/`solaar config` device enumeration measured at
several seconds per call in this session's manual testing (see field notes:
`2026-09-04-logitech-mx-mechanical-backlight-solaar.md`). A short poll
interval would risk overlapping `Process` invocations for little user
benefit — battery percentage and backlight level don't change fast enough
to need sub-minute freshness. `SystemUpdate.qml` uses a 6-hour interval for
a slower-changing value; 60s is a reasonable middle ground for a
user-visible status that should still feel "current" without hammering
`solaar`.

**Alternatives considered**:
- Refresh only on click/hover: rejected — spec FR-006 requires periodic
  refresh without manual action.
- Sub-10s polling: rejected — no user value at that frequency, adds load
  for nothing (spec has no low-latency requirement).

## Decision: Detect "no `solaar`/no device" via `Process` exit code, not a separate probe

**Rationale**: `solaar show` exits non-zero (or produces no matching
device block) when no supported device is paired, and simply isn't on
`PATH` when uninstalled — both cases surface as a failed/empty `Process`
result the widget already has to handle for FR-005 (graceful hide). No
separate detection step is needed.

**Alternatives considered**:
- A one-time `which solaar` check at plugin load: rejected — doesn't cover
  "solaar installed but device unplugged mid-session," so the ongoing
  `Process` result check is needed regardless; a separate check would be
  redundant.

## Open items

None — all Technical Context unknowns from plan.md are resolved above.
