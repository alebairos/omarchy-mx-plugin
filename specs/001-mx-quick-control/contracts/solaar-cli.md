# Contract: `solaar` CLI (external dependency)

This plugin's only external interface is the `solaar` CLI (constitution
Principle II — no direct HID++ access). This document is the contract this
plugin is written against; it does not define an API of the plugin's own
beyond the IPC surface in `ipc-contract.md`.

All commands below were exercised directly against real hardware (a
Logitech MX Mechanical Mini + Signature M650 mouse on a Bolt receiver)
during this project's research; exact output shapes are copied from that
session, not assumed.

## List devices / read status

```
solaar show
```

- **Exit code**: 0 on success even with zero paired devices; non-zero (or
  command-not-found) if `solaar` isn't installed or the receiver isn't
  present — this is the signal for FR-005 graceful-hide.
- **Relevant output lines** (per device block):
  - `  N: <Device Name>` — device index `N` (1-6) and name.
  - `     Battery: NN%, BatteryStatus.<STATE>.` — battery percentage.
  - Presence of a `BACKLIGHT2 {1982}` feature line within that device's
    block indicates `hasBacklight = true` for that device.
  - Within the `BACKLIGHT2` block: `Backlight        : <Mode>` and
    `Backlight Level        : <N>` give current mode/level.
- **Parsing note**: this is human-readable text, not JSON — the plugin
  parses it defensively (regex per line) and treats any unparseable device
  block as `connected = false` for that device rather than erroring.

## Read/set backlight mode

```
solaar config <N> backlight              # read
solaar config <N> backlight Manual       # set to Manual (on)
solaar config <N> backlight Disabled     # set to Disabled (off)
```

- Confirmed values: `Automatic`, `Manual`, `Disabled`.
- Widget only ever writes `Manual` or `Disabled` (spec: no Automatic
  control in v1 — see data-model.md).

## Read/set backlight level

```
solaar config <N> backlight_level        # read
solaar config <N> backlight_level <n>    # set
```

- Confirmed behavior on the reference hardware: valid range is device-
  specific (0-7 on the MX Mechanical Mini used during research); setting a
  value above the max fails with a CLI error (`backlight_level: value 'N'
  out of bounds`), non-zero exit.
- **`levelMax` detection**: on first successful read of the current level,
  the plugin does NOT probe for the max by trial and error against live
  hardware (that would mean deliberately sending invalid commands on every
  load). Instead: clamp scroll-up requests optimistically, and if a `set`
  call fails (non-zero exit / "out of bounds" in stderr), treat the
  previous known-good level as the max and stop incrementing further this
  session. This avoids hardcoding "8 levels" as a universal constant while
  still avoiding needless failed calls after the first one.

## Timing

- A `solaar show` call was observed taking several seconds during manual
  testing (device enumeration cost). All `Process` calls MUST be
  fire-and-forget/async (never block the QML thread) — see research.md,
  "Shell out via Quickshell's Process."
