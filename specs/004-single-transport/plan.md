# Implementation Plan: One transport to the device

**Branch**: `004-single-transport` | **Date**: 2026-09-06 | **Spec**: [spec.md](./spec.md)

## Summary

Replace three device mechanisms with one: a bundled Python transport built
on `logitech_receiver` that answers a whole-state query in a single
invocation and performs writes in a single invocation, emitting JSON. The
QML keeps its single-flight queue and its optimistic updates; what changes
underneath is that a "read everything" is one call instead of three, and
`solaar show` leaves the data path entirely.

## Technical Context

**Language**: Python 3 for the transport (already a dependency via
`solaar`), QML for the widget. No new packages.

**Primary dependency**: `logitech_receiver`, shipped by `solaar`. Already
depended upon in 1.0.0 for effects; this widens that surface.

**Testing**: node's built-in runner for the parser and state logic;
functional tests against a fake transport that can emit degraded frames.
Manual acceptance per feature 001's `quickstart.md`.

**Performance goal**: panel open under 3s (from ~6s); no 11s enumeration.

**Constraints**: no daemon (Principle V); no direct HID++ (Principle II —
using Solaar's own library satisfies this, as established in feature 003).

## Constitution Check

| Principle | Assessment |
|---|---|
| I. Simplicity First | **Improves.** Three mechanisms become one; four ad hoc plausibility checks become one layer. |
| II. Shell Out, Don't Reimplement | **Holds.** `logitech_receiver` is Solaar's own transport. No HID++ is reimplemented, and no `/dev/hidraw` is opened. |
| III. Standard Omarchy Conventions | Unchanged — the widget's shape, panel and bindings stay as they are. |
| IV. Graceful Degradation | **Improves.** "No device" and "could not read" become distinguishable, which they are not today. |
| V. No Speculative Dependencies | **Holds.** No new dependency, no daemon; fewer invocations, not longer-lived ones. |

No violations. The one judgement call is deepening reliance on
`logitech_receiver`'s API, recorded in the spec's Assumptions.

## Design

### The transport

One executable, `mx-device` (replacing `mx-backlight-effect`), speaking JSON:

```
mx-device state
  -> {"ok":true,"devices":[{"index":1,"name":"...","battery":100,
        "backlight":{"mode":"Manual","level":3,"levels":8,
                     "effect":5,"effects":[0,1,2,3,4,5,6]}}]}

mx-device set --device 1 --level 5
mx-device set --device 1 --effect 3
mx-device set --device 1 --mode Manual
  -> {"ok":true}

on failure:
  -> {"ok":false,"error":"no-receiver"|"no-devices"|"unreadable"|"rejected",
      "detail":"..."}
```

`ok:false` with a distinguishable `error` is what lets the widget tell "no
keyboard" from "could not read" (FR-004) — the distinction whose absence
caused the 1.0.0 "no backlight-capable keyboard" bug.

### Plausibility, in one place

Every response is checked before it is returned, using invariants the
device itself supplies:

- a device advertising `BACKLIGHT2` reports at least one level
- a device seen with a backlight does not lose it between reads
- an effects bitmap is non-empty when `BACKLIGHT2` is present

A frame failing any of these is retried, with a budget sized to the real
contention window; only after exhaustion does it return `ok:false`.

### What stays in QML

The single-flight guard, the optimistic updates, the OSD, the cursor model
and the panel layout are unchanged. `runNextVerify`'s queue collapses to a
single "read state" step, and `publishKeyboardState` consumes structured
JSON rather than scraped text.

## Project Structure

```
mx-device                     new transport (replaces mx-backlight-effect)
Model.js                      parses JSON instead of solaar's text output
MxQuickControl.qml            one read call site instead of six
tests/fixtures/*.json         captured real responses, plus degraded frames
tests/fake-mx-device          records invocations; can emit degraded frames
```

## Phases

- **A — transport**: build `mx-device`, with retries and plausibility.
  Verify by hand against real hardware before any QML changes.
- **B — tests first**: capture real responses as fixtures, port the parser
  tests to JSON, add degraded-frame cases that must not reach the UI.
- **C — QML**: swap the six call sites for the two transport calls; delete
  the `solaar show` parser and the text-scraping paths.
- **D — verify**: 001's `quickstart.md`, the 1.0.0 acceptance run, timings
  for SC-001 to SC-003, then tag `1.1.0`.

Each phase merges on its own, green, per the branch protection rules — and
1.0.0 stays installable throughout, since `main` is the distribution channel.

## Risks

- **Library API drift.** `logitech_receiver` is Solaar's internal API with
  no stability promise. Mitigation: keep the surface small (device
  enumeration, `feature_request`), and pin the behaviour with fixtures so a
  break is a failing test rather than a silent misread.
- **Losing something `solaar show` gave us for free.** Mitigation: capture
  its output before deleting the parser, and diff the transport's `state`
  against it for the reference devices.
- **A rewrite regressing behaviour nobody tests.** Mitigation: this is
  exactly why the phases are ordered tests-before-QML, and why 1.0.0 shipped
  first.
