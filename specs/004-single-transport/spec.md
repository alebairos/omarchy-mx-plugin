# Feature Specification: One transport to the device

**Feature Branch**: `004-single-transport`

**Created**: 2026-09-06

**Status**: Draft

**Input**: 1.0.0 talks to the keyboard three different ways. Consolidate on
one, to remove a class of bug and most of the latency.

## The problem, stated from evidence

Six call sites in `MxQuickControl.qml` reach the device through three
different mechanisms, each with its own cost (re-measured 2026-09-06 on the
reference hardware):

| mechanism | used for | cost |
|---|---|---|
| `solaar show` | device discovery, battery, backlight mode/level | **11s** |
| `solaar config <n> <setting> [value]` | reading and writing mode and level | **2s** per call |
| `mx-backlight-effect` (bundled, uses `logitech_receiver`) | reading and setting the effect, and reporting level | **2s** |

Two consequences follow, and both were felt in 1.0.0 rather than predicted.

### Consequence 1: a recurring class of bug

Four separate defects in 1.0.0 had one cause:

> **The device answers concurrent access with plausible, well-formed, wrong
> data — never an error.**

1. A `solaar config` write failing with exit 1 while a background refresh ran
2. The effect helper returning `levels=0 level=0 effect=0 supported=none`
3. The read queue being dropped, leaving a stale level after F4/F5
4. A `solaar show` omitting the `BACKLIGHT2` block entirely, so the widget
   announced "no backlight-capable keyboard" while the keyboard worked

Each was patched where it surfaced, as though it were a distinct bug —
because that is how each presented. The common factor is that **every extra
invocation is another window in which contention can occur**, and each
mechanism validates its own results differently or not at all.

### Consequence 2: latency that is mostly self-inflicted

Opening the panel currently runs three sequential reads (`backlight`,
`backlight_level`, effect) ≈ 6s. Discovery costs 11s on its own. Yet the
helper already returns level *and* effect in a single 2s call — the
information is not expensive, the number of round trips is.

## Goal

**One process, one call, per user-visible operation.** Every read the widget
needs — device list, name, battery, backlight mode, level, effect,
capabilities — comes back from a single invocation. Every write is a single
invocation. Retry and plausibility logic lives in one place, in Python,
under test.

Explicitly **not** a goal: a daemon or a persistent connection. Constitution
Principle V stands. This reduces the number of short-lived invocations; it
does not introduce a long-lived one.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The panel opens promptly (Priority: P1)

Opening the panel shows current, correct state noticeably faster than in
1.0.0.

**Why this priority**: It is the most frequent interaction, and the one
where the current three-read pipeline is most visible.

**Independent Test**: Time from opening the panel to the displayed state
matching the device, compared against 1.0.0 on the same hardware.

**Acceptance Scenarios**:

1. **Given** the panel is closed and the level was changed elsewhere,
   **When** the user opens the panel, **Then** it shows the device's actual
   state in materially less time than 1.0.0's ~6s.
2. **Given** the panel is open, **When** any control is used, **Then** the
   device reflects it and no other read is issued to confirm what the write
   already established.

---

### User Story 2 - Degraded reads stop reaching the UI (Priority: P1)

A contended or truncated response never becomes a visible wrong state.

**Why this priority**: This is the bug class, not a symptom of it. Four
defects in 1.0.0 came from a degraded frame being believed somewhere.

**Independent Test**: Inject degraded responses (the fake transport should
be able to produce them deliberately) and assert the widget's state is
unchanged and a retry occurs, rather than the UI showing a loss.

**Acceptance Scenarios**:

1. **Given** the device returns a frame with no levels, **When** the
   transport processes it, **Then** it retries and never reports that state
   upward.
2. **Given** the device omits a feature block for a keyboard previously
   seen, **When** the transport processes it, **Then** the loss is not
   reported until confirmed.
3. **Given** every retry is exhausted, **When** the transport gives up,
   **Then** it reports an explicit error the widget can distinguish from
   "there is genuinely no keyboard".

---

### User Story 3 - Behaviour is unchanged from the user's side (Priority: P1)

Everything that worked in 1.0.0 still works, identically.

**Why this priority**: This is a rewrite of the data path with no new
features. Any behavioural difference other than speed is a regression.

**Independent Test**: The `quickstart.md` pass from feature 001, plus the
1.0.0 acceptance run: toggle, brightness, effects, panel refresh, hardware
keys with the Solaar rule, vertical bar.

**Acceptance Scenarios**:

1. **Given** any control in the panel, **When** it is used, **Then** the
   device responds exactly as in 1.0.0.
2. **Given** Solaar or a supported device is absent, **When** the widget
   loads, **Then** it degrades exactly as in 1.0.0.

---

### Edge Cases

- `logitech_receiver` present but a device that `solaar show` would list is
  not reachable through it.
- A keyboard with no `BACKLIGHT2` feature at all: must still show battery.
- Several devices, only one with a backlight.
- The transport failing outright (library missing, no receiver): the widget
  must show its existing explicit "Solaar is not installed" state, not a
  blank or a crash.
- A write and a read requested close together: the single-flight guard must
  still serialize them, and a write must still win over a stale read.

## Requirements *(mandatory)*

- **FR-001**: One invocation MUST return everything the widget needs about
  every paired device: index, name, battery, backlight mode, level, level
  count, effect, and supported effects.
- **FR-002**: Writes MUST be single invocations, and MUST NOT be followed by
  a confirming read when they succeed.
- **FR-003**: The transport MUST validate every response against
  device-derived invariants before returning it, and retry rather than
  return an implausible one.
- **FR-004**: The transport MUST distinguish "no device" from "could not
  read", and the widget MUST render those differently.
- **FR-005**: All device access MUST go through `logitech_receiver`;
  `solaar show` and `solaar config` MUST no longer be invoked.
- **FR-006**: No daemon or persistent connection may be introduced.
- **FR-007**: Output MUST be machine-readable (JSON), so parsing is not
  another place for a degraded frame to look valid.
- **FR-008**: The parser and the plausibility rules MUST be unit-tested, and
  the command sequence MUST be covered by functional tests against a fake
  transport that can emit degraded frames on demand.

## Success Criteria *(mandatory)*

- **SC-001**: Opening the panel reflects device state in **under 3 seconds**
  (from ~6s), measured on the reference hardware.
- **SC-002**: Device discovery no longer costs 11 seconds; there is no
  `solaar show` in the data path.
- **SC-003**: A user-visible action issues **exactly one** device
  invocation.
- **SC-004**: Every degraded-frame scenario from 1.0.0 is reproducible in
  the test suite and provably cannot reach the UI.
- **SC-005**: The full 1.0.0 acceptance pass succeeds with no behavioural
  difference other than speed.

## Assumptions

- `logitech_receiver` remains available with `solaar`, and its device API is
  stable enough to depend on. This is already true for effects in 1.0.0;
  this feature deepens that dependency, which is the main risk and is
  accepted deliberately — the alternative is reimplementing HID++, which the
  constitution forbids for good reason.
- Contention with *other* processes (the Solaar GUI, a user's own `solaar`
  commands) cannot be eliminated, only made less likely by reducing the
  number and duration of our own invocations. The retry and plausibility
  layer remains necessary.
- Verified hardware remains an MX Mechanical Mini and a Signature M650 on a
  Bolt receiver.

## Out of scope

- New user-facing features. This is a data-path rewrite.
- Anything requiring a persistent process, including reacting to HID++
  notifications directly; that stays delegated to the optional Solaar rule.
- Battery for devices Solaar cannot see.
