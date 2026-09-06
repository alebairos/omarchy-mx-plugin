# Feature Specification: Backlight effects

**Feature Branch**: `003-backlight-effects`
**Created**: 2026-09-06
**Status**: Draft

## Why this is possible now

An earlier investigation concluded the keyboard's six lighting effects were
firmware-local and unreachable. That was wrong — see
[`specs/research/backlight-effects-hidpp.md`](../research/backlight-effects-hidpp.md).
Established since, on real hardware:

- The device advertises its supported effects: `getBacklightConfig`
  (`0x1982` fn `0x00`) returns an effects bitmap of `0x007f`, i.e. seven
  values, `0`–`6`.
- **Function `0x20` reads the current state**: `08 07 05 06` →
  `numLevels=8`, `level=7`, `effect=6`. Verified to track changes.
- **Writes work.** `setBacklightConfig` (fn `0x10`) carries an effect byte
  that Solaar hardcodes to `0xFF` ("no change"). Setting it to `0`–`6`
  changes the effect — confirmed visually on the keyboard.

## The dependency question, and why this does not break Principle II

Solaar's **CLI** cannot do this: it exposes `backlight` and
`backlight_level`, and no effect setting. But Solaar's **library**,
`logitech_receiver`, already parses the effects bitmap and already has the
write path — it simply never wires either to a user-facing setting.

That library is shipped by the `solaar` package this plugin already
requires (`pacman -Qo` confirms), and constitution Principle II names
`python-logitech-receiver` explicitly as the sanctioned route when Solaar
falls short. So this feature uses Solaar's own HID++ transport
(`device.feature_request`) through a different door than the CLI. It does
**not** open `/dev/hidraw*` and does not reimplement the protocol.

No new dependency is introduced: `python3` and `logitech_receiver` both
arrive with `solaar`.

## User Scenarios & Testing

### User Story 1 - Change the effect from the panel (Priority: P1)

A third row in the panel shows the current effect and lets the user change
it, with the pointer or the keyboard, without opening anything else.

**Independent Test**: open the panel, change the effect, and watch the
keyboard's lighting behaviour change.

**Acceptance Scenarios**:

1. **Given** the panel is open, **When** the user selects a different
   effect, **Then** the keyboard's lighting changes and the row shows the
   new selection.
2. **Given** the effect was changed elsewhere, **When** the panel is
   opened, **Then** the row shows the effect actually on the device.
3. **Given** the cursor is on the effect row, **When** the user presses
   left or right, **Then** the effect changes, consistent with how the
   brightness row already behaves.

---

### User Story 2 - An OSD when the effect changes (Priority: P2)

Changing the effect pops the same on-screen display Omarchy already uses
for volume and brightness, so the change is visible without watching the
keyboard.

**Independent Test**: change the effect and confirm the OSD appears naming
the new effect.

**Acceptance Scenarios**:

1. **Given** the user changes the effect from the panel, **When** the write
   lands, **Then** the standard OSD appears showing the effect.

---

### Edge Cases

- A keyboard that reports no effects bitmap, or fewer than seven values:
  the row must adapt or hide rather than offering values the device will
  reject.
- `logitech_receiver` missing or unimportable (a Solaar packaged without
  it): the effect row hides; everything else keeps working.
- The helper contending with the widget's own `solaar` CLI calls — the
  existing single-flight guard must cover it.

## Requirements

- **FR-001**: The panel MUST show the effect currently on the device, read
  from the device rather than remembered.
- **FR-002**: Users MUST be able to change the effect by pointer and by
  keyboard.
- **FR-003**: The available effects MUST come from the device's own bitmap,
  not a hardcoded list.
- **FR-004**: Effect access MUST go through `logitech_receiver`, never raw
  `/dev/hidraw*`.
- **FR-005**: If effects are unavailable for any reason, the rest of the
  widget MUST continue to work unchanged.
- **FR-006**: Changing the effect MUST show the standard Omarchy OSD.

## Out of scope for this feature

**Reacting to the keyboard's own effect key.** The device does announce
effect changes in a HID++ notification, so an OSD on the hardware key is
technically possible — but consuming notifications needs a listener running
continuously, which is what constitution Principle V forbids. That needs a
deliberate amendment discussion, not a quiet exception. Tracked separately.

## Assumptions

- Effect values are `0`–`6` on this hardware; names are **not yet known**.
  The first build labels them numerically and is calibrated against the
  hardware afterwards, because mapping a value to "Wave" requires a human
  watching the keyboard.
- Verified only on the MX Mechanical Mini. Other keyboards advertising
  `BACKLIGHT2` should work, and the bitmap makes the row adapt, but this is
  untested elsewhere.
