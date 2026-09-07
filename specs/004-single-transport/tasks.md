# Tasks: One transport to the device

**Input**: [spec.md](./spec.md), [plan.md](./plan.md)

**Prerequisites**: 1.0.0 shipped, tagged, and installable from `main`.

**Tests**: Unlike feature 002, this one has a suite to protect it — 33 tests
green at `v1.0.0`. Per [AGENTS.md](../../AGENTS.md), a test added for a fix
must be shown to fail against the unfixed code, and the commit must say so.

**Distribution note**: `main` is what users install and update from, by
`git merge --ff-only`. Every phase below merges as a release. Rollback is
`git revert`, never a history rewrite — see plan.md, "Release and rollback".

## Format: `[ID] [P?] Description` — `[P]` = parallelisable

---

## Measurements this plan is answering

Taken on the reference hardware on 2026-09-06 with the widget and the
Solaar GUI both running, so contention is included rather than excluded:

| Finding | Evidence |
|---|---|
| Panel open costs 6.6s | `solaar config` 2279ms + 2234ms, helper 2102ms, sequential |
| Discovery costs 10.5s | `solaar show` 10496 / 10629 ms |
| The backlight data is nearly free | `feature_request` GET_CONFIG 14ms, GET_STATE 15ms |
| Interpreter startup is not the problem | bare `python3` 9ms; `logitech_receiver` import 190ms total |
| Device construction dominates | `list(receiver)` 2136 / 2137 / 2139 ms — a 3ms spread, so a fixed timeout |
| The timeout cannot ever succeed here | `find_paired_node(idx, 1s)` → 1001ms, `None`; at 0s → 1ms, `None` |
| One udev scan is enough | a single full scan measures 52ms |
| ~~`ping()` is redundant and expensive~~ **withdrawn** | one ping per device happens either way (counted); interleaved runs put both orderings within noise |
| One call vs 1.0.0's panel open, interleaved | 2185/1874/2096 ms against 6475/6832/6626 ms — **3.2x** |
| Absolute timings are not stable | the same code measures 715–804ms or 1874–2185ms with device responsiveness; pausing the Solaar GUI changes nothing |

---

## Phase A: The transport (P1)

**Purpose**: A working `mx-device` verified against real hardware, before
any QML depends on it. Nothing in this phase changes what users run: the
widget still uses the old paths until Phase C.

- [ ] T001 Create `mx-device` with subcommands `state` and `set`, emitting JSON per plan.md's contract
- [ ] T002 Enumerate through a `low_level` shim overriding only `find_paired_node`, with a one-scan budget; comment the trade-off and cite the 52ms measurement
- [ ] T003 Read name, battery, backlight mode, level, level count, effect and supported effects for every paired device in the single `state` call
- [ ] T004 Omit the explicit liveness `ping()` on simplicity grounds, and route a failed first read into the plausibility layer. Claim no speed-up: the ping happens lazily via `Device.protocol` either way
- [ ] T005 Implement the plausibility invariants from plan.md in one place, with the retry budget sized to the real contention window
- [ ] T006 Distinguish `no-receiver` / `no-devices` / `unreadable` / `rejected` in the error payload (FR-004) — the 1.0.0 bug is this distinction's absence
- [ ] T007 Implement `set` for level, effect and mode, returning `{"ok":true}` without a confirming read (FR-002)
- [ ] T008 [P] Keep `mx-backlight-effect` in place and untouched, so `main` stays installable and 1.0.0's path is unaffected
- [ ] T009 Verify by hand against the hardware: `mx-device state` matches `solaar show` for both reference devices, field by field
- [ ] T010 Time `mx-device state` **interleaved with the 1.0.0 path**, alternating within the same minute, and record both columns — absolute timings taken minutes apart are not comparable on this hardware

**Checkpoint**: `mx-device state` is correct and under 1.5s, and nothing
the user runs has changed yet.

---

## Phase B: Tests before the rewrite (P1)

**Purpose**: The 1.0.0 bug class must be reproducible in the suite before
the QML is allowed to depend on the new path.

- [ ] T011 Capture real `mx-device state` responses as `tests/fixtures/*.json` for: keyboard+mouse, mouse only, no devices, no receiver
- [ ] T012 [P] Diff those against the retained `solaar show` fixtures and record any field the transport does not reproduce (plan.md, Risk 2)
- [ ] T013 Redact serials from every captured fixture before committing — this repo has shipped a real serial once already
- [ ] T014 Port the `Model.js` parser tests from scraped text to JSON
- [ ] T015 Add degraded-frame fixtures for all four 1.0.0 defects: write-failed-mid-refresh, all-zero effect frame, dropped read queue, missing `BACKLIGHT2` block (SC-004)
- [ ] T016 Assert each degraded frame is retried and never surfaces as state; assert an exhausted retry reports an error distinguishable from "no device"
- [ ] T017 Build `tests/fake-mx-device`, which records invocations and can emit degraded frames on demand
- [ ] T018 Add a functional test asserting a user-visible action issues exactly one invocation (SC-003)
- [ ] T019 Add a regression test pinning the two cost fixes, so a `logitech_receiver` change that reinstates them fails loudly rather than silently costing 2s
- [ ] T020 For each test above, break the code it protects and confirm it fails; say so in the commit (AGENTS.md)

**Checkpoint**: The suite fails against the old data path and passes
against the new one, with every 1.0.0 defect represented.

---

## Phase C: The QML (P1)

**Purpose**: Six call sites become two. This is the phase that ships the
change to users, so it merges only with Phase B green.

- [ ] T021 Replace the three panel-open reads with one `mx-device state` call
- [ ] T022 Rewrite `publishKeyboardState` to consume JSON instead of scraped text
- [ ] T023 Route writes through `mx-device set`, and delete the confirming reads that follow them (FR-002)
- [ ] T024 Collapse `runNextVerify`'s queue to a single "read state" step, keeping the single-flight guard and the optimistic updates unchanged
- [ ] T025 Render "no keyboard" and "could not read" differently, which 1.0.0 cannot (FR-004)
- [ ] T026 Delete the `solaar show` parser, the text-scraping paths, and `mx-backlight-effect`; confirm no `solaar` invocation remains in the data path (FR-005)
- [ ] T027 Confirm the OSD, cursor model, hardware-key path and Solaar rule still behave, none of which this phase intends to touch

**Checkpoint**: The widget runs entirely on `mx-device`, and `main` is
installable.

---

## Phase D: Verify and release (P1)

- [ ] T028 Run feature 001's `quickstart.md` end to end
- [ ] T029 Run the 1.0.0 acceptance pass: toggle, brightness, effects, panel refresh, hardware keys with the Solaar rule, vertical bar (SC-005)
- [ ] T030 Measure and record SC-001 (panel open under 1.5s), SC-002 (no `solaar show`), SC-003 (one invocation per action)
- [ ] T031 Verify on a machine that has never seen the plugin: `omarchy plugin add … --enable`
- [ ] T032 Verify the upgrade path a real user takes: `omarchy plugin update` fast-forwarding from `v1.0.0` to the new tip
- [ ] T033 Rehearse the rollback: `git revert` the feature on a scratch clone, confirm it fast-forwards cleanly for a user already on the new tip
- [ ] T034 Bump `manifest.json` and `package.json` to `1.1.0`
- [ ] T035 Update `README.md` — the "roughly two seconds per action" limitation is no longer true
- [ ] T036 Update `CHANGELOG.md`, tag `v1.1.0`, and cut the GitHub release
- [ ] T037 [P] Report the `find_paired_node` busy-wait upstream to Solaar, with the measurements

**Checkpoint**: 1.1.0 is tagged, installable, upgradable, and revertible.

---

## Out of scope, deliberately

- New user-facing features. This is a data-path rewrite.
- Anything requiring a persistent process (Constitution Principle V).
- Fixing `find_paired_node` for anyone but this plugin — T037 reports it;
  it does not carry a patched copy of Solaar.
