# Data Model: MX Quick Control

No persistent storage (per plan.md, Storage: N/A). The entities below are
in-memory QML properties, refreshed from `solaar` on each `Timer` tick —
nothing survives a shell restart, and nothing needs to.

## Paired Device

Represents one Logitech device `solaar` reports as currently paired.

| Field | Type | Source | Notes |
|---|---|---|---|
| `name` | string | `solaar show` device name line | e.g. "MX Mechanical Mini" |
| `deviceIndex` | int (1-6) | `solaar show` device index | Used as the `solaar config <N> ...` argument |
| `batteryPercent` | int (0-100) or `null` | `solaar show` "Battery: NN%" line | `null` if device doesn't report battery or is unreachable |
| `connected` | bool | Whether `solaar show` returned this device at all this refresh | Drives the "disconnected" edge case (spec Edge Cases) |
| `hasBacklight` | bool | Whether `BACKLIGHT2` feature is present in this device's `solaar show` output | Gates whether backlight controls render for this device (spec FR-002 vs. mouse-only battery) |

## Backlight State

Only present for a Paired Device where `hasBacklight` is true (in practice,
the keyboard).

| Field | Type | Source | Notes |
|---|---|---|---|
| `mode` | enum: `Automatic` \| `Manual` \| `Disabled` | `solaar config <N> backlight` | Widget's on/off toggle (spec FR-003) maps to `Manual` (on) vs `Disabled`/level-0 (off) — see contracts/solaar-cli.md |
| `level` | int (0-7 on this hardware; range is device-reported, not hardcoded) | `solaar config <N> backlight_level` | Widget's step up/down (spec FR-004) moves this by 1, clamped to the device's actual min/max |
| `levelMax` | int | Derived once by probing `solaar config <N> backlight_level <max+1>` for an "out of bounds" error, OR read from device capabilities if `solaar` exposes a max directly | See contracts/solaar-cli.md for the exact detection approach |

## State Transitions

```
Backlight mode: Automatic <-> Manual <-> Disabled
  - Widget click (spec US2) toggles between "off" (Disabled or level 0)
    and "on" (Manual at last-known or default level).
  - Widget does not offer a control for Automatic mode in v1 (spec does not
    request it — Automatic relies on hardware sensors, not a bar toggle).

Backlight level: integer, clamped [0, levelMax]
  - Scroll up (spec US3): level = min(level + 1, levelMax)
  - Scroll down (spec US3): level = max(level - 1, 0)
  - Only meaningful/sent to solaar when mode == Manual (matches Solaar's
    own semantics: level changes only take effect in Manual mode).
```
