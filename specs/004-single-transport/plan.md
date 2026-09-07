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

**Performance goal**: panel open under 1.5s (from 6.6s measured; ~0.8s
observed); no 10.5s enumeration. See the spec's stage timings — most of the
win is removing `find_paired_node`'s one-second-per-device busy-wait, not
merging call sites.

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

### Two costs the transport must not pay

Established by measurement (spec, "Where that time actually goes"), and the
reason this is worth 8x rather than 2x:

1. **The node probe.** `Device.__init__` spends up to one second per device
   in `find_paired_node`, a busy-wait that cannot succeed for devices behind
   this receiver. The transport passes its own `low_level` shim whose
   `find_paired_node` uses a budget sized to one complete udev scan (~52ms
   measured; 150ms gives two scans and still saves 1.7s of the 2s). The
   shim is the smallest possible override — one function — precisely because
   Risk 1 below says this API has no stability promise.

2. **The redundant ping.** `ping()` costs 590–890ms and establishes
   liveness that the very next `feature_request` establishes anyway. A read
   that fails is already handled by the plausibility layer; a ping only
   moves that failure earlier at full price.

Both are behaviour-preserving here — the shimmed path returned byte-identical
config, state, battery and name data — and both must be covered by a
fixture-backed test, so a future `logitech_receiver` that changes either one
fails loudly rather than silently costing two seconds again.

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

## Release and rollback

**`main` is the distribution channel, literally.** `omarchy plugin add` runs
`git clone` and `omarchy plugin update` runs `git fetch origin HEAD` followed
by `git merge --ff-only FETCH_HEAD` (`/usr/share/omarchy/bin/omarchy-plugin-update`).
Users track `main`'s tip. Tags and GitHub releases are documentation of what
was shipped; they are not what anybody installs. Every merge to `main` is a
release to everyone who updates next.

Three consequences, and the third is the one that is easy to get wrong:

1. **Each phase must merge green and installable.** Already the plan; now
   with a stated reason. A half-migrated `main` — the transport landed, the
   QML still calling `solaar show` — is a shipped product, not an
   intermediate state.

2. **There is one automatic safety net, and it is narrower than it looks.**
   After fast-forwarding, the updater runs `omarchy-plugin-validate` and, on
   failure, `git reset --hard ORIG_HEAD`. But validate checks the manifest
   schema, required fields, and that entry-point files exist — *not* that the
   QML loads or the widget works. It catches a broken `manifest.json`. It
   will happily ship a widget that renders nothing.

3. **Rollback is a forward revert, never a history rewrite.** Because updates
   are `--ff-only`, resetting or force-pushing `main` backwards leaves every
   user who already pulled the bad commit unable to fast-forward: their next
   update fails with "cannot fast-forward" and they are stranded on the
   broken version. The correct rollback is `git revert` — a new commit that
   moves forward to the old behaviour, which fast-forwards cleanly for
   everyone. Branch protection already forbids the force-push; this is the
   reason it is right to.

So the rollback procedure for this feature is:

```bash
git revert --no-edit <merge-or-commit>     # forward, ff-safe
npm test                                    # 33 tests must stay green
# PR, rebase-merge, then confirm the widget on real hardware
```

The escape hatch for a user who cannot wait is `omarchy plugin remove` and
`omarchy plugin add` again, which re-clones. That is a worse experience than
a revert and should never be the plan.

**Version marker.** `manifest.json` and `package.json` both carry `1.0.0`
today. Neither gates installation, but they are how a user reports which
version misbehaves, so they move to `1.1.0` in phase D with the tag — not
before, so that anything shipped mid-migration still identifies honestly as
what it is.

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
