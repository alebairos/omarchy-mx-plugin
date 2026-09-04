# Feature Specification: Public Release Candidate

**Feature Branch**: `002-public-release-rc`

**Created**: 2026-09-04

**Status**: Draft

**Input**: Ship this plugin as something the Omarchy community would accept:
simple yet effective at the basic problem for the devices it supports, and
recognisably *Omarchy* in both design and engineering conventions.

## Goal

Two bars must be cleared, and they are different bars:

1. **Correct** — it solves the basic problem (see the backlight/battery
   control already specified in [001-mx-quick-control](../001-mx-quick-control/spec.md))
   reliably, on the devices it claims to support, and says plainly which
   devices those are.
2. **Native** — a user who did not write it cannot tell it from a built-in
   widget. Omarchy is a high-profile, opinionated project; a plugin that
   works but *looks and behaves* foreign will not be adopted, and should
   not be.

Anything that does not serve one of those two goals is out of scope for
this release.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install it the way you install anything else (Priority: P1)

A user reads about the plugin, runs the one documented command, and has a
working widget on their bar.

**Why this priority**: This is currently broken, not merely unpolished.
`omarchy plugin add` validates `manifest.json` at the **repo root**, and
this repo keeps the plugin in `plugin/` — so the native install path
rejects it outright. Nothing else matters until this works.

**Independent Test**: On a machine that has never seen this plugin, run
`omarchy plugin add <repo-url> --enable` and confirm the widget appears on
the bar without any manual copying.

**Acceptance Scenarios**:

1. **Given** a clean Omarchy machine with `solaar` installed, **When** the
   user runs `omarchy plugin add <repo-url> --enable`, **Then** the plugin
   installs, validates, and appears on the bar.
2. **Given** the repo checked out locally, **When** `omarchy plugin
   validate .` is run at the repo root, **Then** it exits 0.
3. **Given** installation completes, **When** the user is offered a bar
   section, **Then** the manifest's declared default is offered rather than
   the generic fallback.

---

### User Story 2 - It looks and behaves like a built-in (Priority: P1)

A user opens the panel and cannot tell, from appearance or interaction,
that this is not part of Omarchy itself.

**Why this priority**: Equal to install, because it is the difference
between "accepted" and "works, but obviously bolted on". Audited against
the first-party plugins, the current widget fails this on four counts, all
independently visible.

**Independent Test**: Place the widget beside built-in widgets in the same
bar, on a light theme and a dark theme, on a horizontal and a vertical bar,
and drive it with the keyboard only. Nothing should stand out.

**Acceptance Scenarios**:

1. **Given** any theme, **When** the bar renders, **Then** the widget's
   icon is a Nerd Font glyph tinted with the theme foreground, matching its
   neighbours in font, weight and colour.
2. **Given** the panel is open, **When** the user presses arrow keys, Enter
   and Esc, **Then** the panel responds like every other Omarchy panel.
3. **Given** an adjacent panel is open, **When** the user presses Tab,
   **Then** focus moves between panels including this one.
4. **Given** a vertical (left/right) bar, **When** the widget and panel
   render, **Then** the layout adapts rather than assuming horizontal.
5. **Given** the user wants a setting this widget does not expose, **When**
   they middle-click the icon, **Then** Solaar itself opens.

---

### User Story 3 - Honest, tunable, and current (Priority: P2)

A user changes brightness somewhere else — the Solaar GUI, or the
keyboard's own Fn keys — and the widget reflects reality when they look at
it. A user who wants different defaults edits `shell.json`, as they would
for any other widget.

**Why this priority**: Real gaps, but the plugin is usable without them.
Both were found by using it rather than by review.

**Independent Test**: Change the level in the Solaar GUI, then open the
panel and confirm it shows the new value. Separately, set a config key in
`shell.json` and confirm the widget honours it.

**Acceptance Scenarios**:

1. **Given** brightness was changed outside the plugin, **When** the user
   opens the panel, **Then** it shows the current device state (not state
   up to five minutes stale).
2. **Given** a per-instance setting in `shell.json`, **When** the shell
   loads the widget, **Then** the setting is honoured.
3. **Given** `solaar` is not installed, **When** the user opens the panel,
   **Then** it says so and how to fix it, rather than silently hiding.

---

### Edge Cases

- A device whose maximum backlight level is not 7 (the current hardcoded
  assumption until a write is rejected).
- More than one backlight-capable keyboard paired at once (currently only
  the first is controlled).
- A Logitech device paired over Bluetooth rather than a Bolt/Unifying
  receiver — `solaar show` output shape is unverified there.
- `solaar` present but no device paired; `solaar` absent entirely.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST install via `omarchy plugin add <git-url>`
  with no manual file copying, and MUST pass `omarchy plugin validate` at
  the repo root.
- **FR-002**: The manifest MUST declare its preferred bar section.
- **FR-003**: All widget iconography MUST use Nerd Font glyphs tinted from
  the active theme, and MUST NOT use emoji.
- **FR-004**: The panel MUST support keyboard navigation consistent with
  first-party panels, including Esc to close and Tab to move between
  panels.
- **FR-005**: The widget and panel MUST render correctly on horizontal and
  vertical bars.
- **FR-006**: The widget MUST offer a path to Solaar itself for settings it
  deliberately does not expose.
- **FR-007**: The panel MUST show current device state when opened, without
  paying the cost of a full device enumeration.
- **FR-008**: Behaviour that a user might reasonably want to change MUST be
  exposed as per-instance settings read from `shell.json`.
- **FR-009**: When `solaar` is missing, the panel MUST say so and name the
  install command.
- **FR-010**: The parser and the write/queue state machine MUST be covered
  by automated tests, including a test that asserts the exact `solaar`
  commands issued for a given interaction.
- **FR-011**: Documentation MUST state which devices are verified and which
  are merely expected to work.

### Key Entities

Unchanged from [001](../001-mx-quick-control/data-model.md). This release
adds no new device concepts; it changes packaging, presentation,
interaction, and test coverage.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from "never heard of it" to a working widget in
  a single command.
- **SC-002**: Placed among built-in widgets, the plugin is not identifiable
  as third-party by appearance or interaction alone.
- **SC-003**: The panel is fully operable without a pointing device.
- **SC-004**: State shown on opening the panel matches the device, even
  after the level was changed elsewhere.
- **SC-005**: Every defect class found during 001's manual verification
  (parser mis-reads, dropped writes, elided no-op writes) is covered by a
  test that fails if reintroduced.
- **SC-006**: A reader of the README can tell, without running anything,
  whether their own hardware is supported and how confidently.

## Assumptions

- Only capability-driven device support is claimed: anything Solaar reports
  with a `BACKLIGHT2` feature gets backlight controls, anything reporting a
  battery gets a battery readout. No model allow-list.
- Verified hardware is limited to what is physically available (an MX
  Mechanical Mini and a Signature M650, both on a Bolt receiver). Broader
  support is stated as expected, not verified.
- Scope stays deliberately narrow per the project constitution: this is a
  bar widget, not a second Solaar GUI.
