# Feature Specification: MX Quick Control

**Feature Branch**: `001-mx-quick-control`

**Created**: 2026-09-04

**Status**: Draft

**Input**: User description: "MX peripheral quick control widget for the Omarchy bar — a bar widget that shows Logitech MX Mechanical Mini / paired mouse battery status and lets the user toggle/cycle keyboard backlight mode and brightness level directly from the bar, without opening the Solaar GUI. Simplest yet effective standard Omarchy plugin."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See device status at a glance (Priority: P1)

A user glances at the Omarchy bar and sees battery percentage for their
paired Logitech keyboard and mouse, without opening a separate application.

**Why this priority**: This is the minimum viable version — pure read-only
status display. It requires no interaction handling and delivers value
(no more guessing when a battery is about to die) on its own.

**Independent Test**: With a Logitech keyboard/mouse paired via a Bolt or
Unifying receiver, open the bar and confirm battery percentage for each
device is visible and matches `solaar show`.

**Acceptance Scenarios**:

1. **Given** a keyboard and mouse are paired and both report battery via
   `solaar`, **When** the user looks at the bar, **Then** both devices'
   battery percentages are visible.
2. **Given** a device's battery drops to a low level, **When** the bar next
   refreshes, **Then** the displayed percentage reflects the new value
   within one refresh cycle.

---

### User Story 2 - Toggle keyboard backlight from the bar (Priority: P2)

A user turns their keyboard backlight on or off with a single click on the
bar widget, instead of opening Solaar and navigating its settings.

**Why this priority**: This is the specific pain point that motivated the
plugin — the backlight was previously stuck effectively off because nothing
surfaced an easy way to control it. A one-click toggle is the smallest
change that fixes that pain point.

**Independent Test**: With the backlight currently off (Manual, level 0),
click the widget and confirm the physical keyboard backlight turns on; click
again and confirm it turns back off.

**Acceptance Scenarios**:

1. **Given** the keyboard backlight is off, **When** the user clicks the
   widget's backlight control, **Then** the backlight turns on at a
   reasonable default level and the widget reflects the new state.
2. **Given** the keyboard backlight is on, **When** the user clicks the
   widget's backlight control, **Then** the backlight turns off and the
   widget reflects the new state.

---

### User Story 3 - Adjust backlight brightness from the bar (Priority: P3)

A user scrolls over the widget to step the keyboard backlight brightness up
or down without leaving the bar.

**Why this priority**: A nice-to-have refinement once on/off control
exists — most users will be satisfied by Story 2 alone, but fine brightness
control avoids needing to reach for Solaar for anything at all.

**Independent Test**: With the backlight on at a mid-range level, scroll up
on the widget and confirm brightness visibly increases; scroll down and
confirm it decreases; confirm it does not go below the device's minimum or
above its maximum level.

**Acceptance Scenarios**:

1. **Given** the backlight is on at a non-maximum level, **When** the user
   scrolls up on the widget, **Then** the brightness increases one step and
   does not exceed the device's maximum supported level.
2. **Given** the backlight is on at a non-minimum level, **When** the user
   scrolls down on the widget, **Then** the brightness decreases one step
   and does not go below the device's minimum level.

---

### Edge Cases

- What happens when `solaar` is not installed? The widget MUST hide itself
  rather than show an error.
- What happens when no supported device is currently paired/powered on?
  The widget MUST hide itself or clearly show a "no device" state rather
  than showing stale or blank data.
- How does the widget behave while a device is asleep or out of range
  (e.g., keyboard powered off, receiver unplugged)? It MUST show a
  disconnected/unavailable state rather than crashing or hanging the bar.
- What happens if a `solaar` call takes a long time or hangs? The widget
  MUST NOT block or freeze the rest of the Omarchy bar while waiting.
- What happens on a device that has battery reporting but no backlight
  feature (e.g., a mouse)? The widget MUST show battery only, with no
  backlight control for that device.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display current battery percentage for each
  paired, supported Logitech device visible to `solaar`.
- **FR-002**: System MUST display the keyboard's current backlight state
  (on/off, and level when on) in the bar.
- **FR-003**: Users MUST be able to toggle the keyboard backlight on/off
  with a single click on the widget.
- **FR-004**: Users MUST be able to step the keyboard backlight brightness
  up or down (e.g., via scroll) without opening a separate application.
- **FR-005**: System MUST hide or clearly disable the widget when `solaar`
  is not installed or no supported device is detected, rather than showing
  an error state or crashing the shell.
- **FR-006**: System MUST refresh device status on a periodic interval
  without requiring manual user action to see current values.
- **FR-007**: System MUST interact with hardware exclusively through the
  `solaar` CLI and MUST NOT reimplement device communication directly
  (per project constitution, Principle II).
- **FR-008**: System MUST NOT block or freeze the rest of the Omarchy bar
  while a `solaar` call is in progress or times out.

### Key Entities

- **Paired Device**: A Logitech device visible to `solaar` (keyboard or
  mouse), identified by name, with a battery percentage and connection
  state.
- **Backlight State**: For keyboards that support it, the current mode
  (on/off, i.e. Manual vs. a level-0/Disabled state) and brightness level
  (an integer between the device's minimum and maximum).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can determine current keyboard and mouse battery
  percentage in under 2 seconds, without launching any application besides
  glancing at the bar.
- **SC-002**: A user can turn the keyboard backlight on or off in exactly
  one click, down from the multi-step CLI sequence previously required.
- **SC-003**: The widget adds no perceptible startup delay to the Omarchy
  bar (status populates asynchronously after the bar is already usable).
- **SC-004**: When no supported device or `solaar` installation is present,
  the shell continues operating normally 100% of the time — no crash, no
  error dialog, no blocked bar.

## Assumptions

- `solaar` is already installed and correctly permissioned (verified
  working in this environment); this plugin does not install or configure
  `solaar` itself.
- The primary supported topology is one receiver with one keyboard and
  optionally one mouse; multi-receiver or multi-host fleets are out of
  scope for v1.
- Onboard lighting "effects" (e.g., wave, pulsating patterns observed on
  the physical keys) are firmware-internal behavior with no state exposed
  to the host (confirmed by direct testing) and are therefore out of scope
  — this plugin only exposes what `solaar` itself can read or control
  (battery, backlight mode, backlight level).
- Devices without a controllable backlight (e.g., a mouse) show battery
  status only, with no backlight control shown for that device.
