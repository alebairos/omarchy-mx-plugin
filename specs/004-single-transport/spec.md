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

Those totals were re-confirmed on 2026-09-06 after the spec's first draft:
`solaar show` 10496/10629ms, `solaar config` 2279/2191ms and 2234/2222ms,
the helper 2102/2116ms. Opening the panel runs the last three in sequence:
**6.6s**.

### Where that time actually goes

The first draft of this spec assumed the per-call cost was irreducible —
the helper does one `logitech_receiver` round trip and takes 2.1s, so 2s
looked like a floor. It is not. Timed stage by stage:

| stage | cost |
|---|---|
| Python + `logitech_receiver` imports | 190 ms |
| `base.receivers()` | 80 ms |
| `list(receiver)` — constructing Device objects | **2136 ms** |
| `ping()` per device (lazy; happens whether or not it is called) | 590–890 ms |
| `.name`, `.battery()` | ~90 ms each |
| `feature_request` — the backlight data itself | **14–21 ms** |

The data this plugin exists to read costs **15 milliseconds**. Everything
else is setup, and interpreter startup — the suspected culprit — is 6%.

`list(receiver)` measured 2136/2137/2139 ms across three runs. A 3ms spread
over two seconds is a fixed timeout, not device I/O. It is this, in
`logitech_receiver/device.py:183`:

```python
if not self.path:
    self.path = self.low_level.find_paired_node(receiver.path, number, 1) if receiver else None
```

A one-second budget, per device, spent in `hidapi/udev_impl.py:204` on a
busy-wait that rescans every hidraw node until it expires. On this hardware
it cannot succeed — these devices are reached through the receiver's own
handle and expose no individual hidraw node:

```
find_paired_node(idx=1, timeout=1s) ->  1001 ms   node=None
find_paired_node(idx=1, timeout=0s) ->     1 ms   node=None
find_paired_node(idx=2, timeout=1s) ->  1002 ms   node=None
find_paired_node(idx=2, timeout=0s) ->     1 ms   node=None
```

One full scan takes 52ms; the remaining 948ms waits for a device that will
never appear. Two devices, two seconds, on **every** invocation — including
each of the three that make up a panel open, and every device `solaar show`
enumerates, which is much of why that costs ten seconds.

Passing a budget that permits one scan cuts `list(receiver)` from 2136ms to
436ms, reproducibly.

### Two corrections to the above, from building it

The first draft of this section also claimed that dropping the explicit
`ping()` was worth ~950ms. **It is not, and the claim has been withdrawn.**
`Device.protocol` pings lazily on first use, so exactly one ping per device
happens either way — counted, not assumed. Run interleaved rather than in
sequence, the two orderings are within noise of each other (~720ms both
ways); the apparent saving was a cold first run that happened to land in the
`ping()` column. There is still a reason not to call it — a ping whose
result the next read re-establishes is one more thing that can fail — but it
is a simplicity argument, not a performance one.

The second correction is the headline. A single call measured **715–804ms**
in one window and **1874–2185ms** in another, with identical code and no
change to the machine. The difference is per-device HID++ round-trip
latency, which varies from ~15ms to ~900ms with the wireless devices' own
power state and is not ours to control. Pausing the Solaar GUI changed
nothing, so this is not contention with another process.

The comparison that survives this is an interleaved one, where both paths
meet the same conditions in the same minute:

| | run 1 | run 2 | run 3 |
|---|---|---|---|
| 1.0.0 panel open | 6475 ms | 6832 ms | 6626 ms |
| `mx-device state` | 2185 ms | 1874 ms | 2096 ms |

**~3.2x**, holding in the conditions where 1.0.0 costs its full 6.6s. When
the devices are responsive the single call drops to ~0.75s; 1.0.0 was not
measured in that same window, so no larger ratio is claimed here.

This changes the size of the prize, not the design. One call is still the
right shape.

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
- **FR-009**: The transport MUST NOT pay `find_paired_node`'s default
  one-second-per-device budget. It MUST pass a budget that still permits at
  least one complete udev scan, so a device whose node genuinely exists is
  still found, and MUST record the trade-off where it is set.
- **FR-010**: The transport SHOULD NOT issue a `ping()` whose only purpose
  is to establish liveness that the following read establishes anyway —
  on simplicity grounds. It is explicitly *not* a performance requirement:
  measurement showed the ping happens lazily regardless.
- **FR-008**: The parser and the plausibility rules MUST be unit-tested, and
  the command sequence MUST be covered by functional tests against a fake
  transport that can emit degraded frames on demand.

## Success Criteria *(mandatory)*

- **SC-001**: Opening the panel reflects device state in **at most a third
  of the time 1.0.0 takes, measured interleaved** — the two paths alternating
  within the same minute, so both meet the same device conditions. Observed:
  6.6s against 2.0s. An absolute figure is not used as the criterion, because
  the same code measures 0.75s or 2.1s depending on how responsive the
  wireless devices happen to be, and that is not something this feature
  controls.

  *This criterion has been wrong twice. The first draft said "under 3
  seconds", written from call counts before anything was timed. The second
  said "under 1.5 seconds", written from a measurement taken in an
  unusually responsive window and not reproduced. A ratio under matched
  conditions is the only form that has survived contact with the hardware.*
- **SC-002**: Device discovery no longer costs 10.5 seconds; there is no
  `solaar show` in the data path, and the device list arrives from the same
  single call as everything else.
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
- `find_paired_node` returning `None` for these devices is a property of
  how they attach (through the receiver's handle), not a fault to be fixed
  here. A shortened budget is therefore behaviour-preserving on this
  hardware and merely faster; on hardware where the node does exist, one
  complete scan still finds it. What is given up is the grace period for a
  node that appears *during* the probe. This is worth reporting upstream:
  it taxes every Solaar invocation on every machine.
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
