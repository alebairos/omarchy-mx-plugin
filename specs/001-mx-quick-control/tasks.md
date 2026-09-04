# Tasks: MX Quick Control

**Input**: Design documents from `/specs/001-mx-quick-control/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: No automated test harness for this project (constitution, Development
Workflow) — verification is the manual `quickstart.md` walkthrough against real
hardware, tracked as a Polish-phase task, not per-story test tasks.

**Organization**: Tasks are grouped by user story (spec.md) to enable independent
implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Path Conventions

Single Omarchy shell plugin at the repository root (plan.md, Project Structure):
`plugin/manifest.json`, `plugin/MxQuickControl.qml`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repository scaffolding, independent of any user story.

- [ ] T001 Create `plugin/` directory with placeholder `manifest.json` and `plugin/MxQuickControl.qml` skeleton (empty `BarWidget`) at repository root
- [ ] T002 [P] Add `.gitignore` at repository root excluding `.claude/` and any local plugin/editor state (per spec-kit's own credential-leakage warning)
- [ ] T003 [P] Add `LICENSE` (MIT) at repository root, for standard community sharing

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared status pipeline every user story reads from. No story can be
implemented until device status can be read and the widget can hide itself safely.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T004 Define `plugin/manifest.json`: `"kinds": ["bar-widget"]`, `entryPoints.barWidget`, `id: "alebairos.mx-quick-control"`, per contracts/ipc-contract.md and plan.md Project Structure
- [ ] T005 Implement `solaar show` `Process` call and defensive per-line parsing into a Paired Device list (`name`, `deviceIndex`, `batteryPercent`, `connected`, `hasBacklight`) in `plugin/MxQuickControl.qml`, per data-model.md and contracts/solaar-cli.md
- [ ] T006 Implement the refresh `Timer` (60s interval, `triggeredOnStart: true`) driving T005, and the `visible` binding that hides the widget when `solaar` is missing or no device is connected (constitution Principle IV, spec FR-005) in `plugin/MxQuickControl.qml`
- [ ] T007 [P] Implement the `IpcHandler` `refresh` function per contracts/ipc-contract.md in `plugin/MxQuickControl.qml`

**Checkpoint**: Widget loads in the bar, shows/hides correctly based on device presence, refreshes on a timer. Ready for user story work.

---

## Phase 3: User Story 1 - See device status at a glance (Priority: P1) 🎯 MVP

**Goal**: Battery percentage for each paired device is visible in the bar.

**Independent Test**: Compare the widget's displayed battery percentages against `solaar show` output for the same devices.

### Implementation for User Story 1

- [ ] T008 [US1] Render per-device battery percentage in the widget's button/tooltip in `plugin/MxQuickControl.qml`
- [ ] T009 [US1] Handle a device with `batteryPercent = null` (no battery reporting) without breaking the widget's layout in `plugin/MxQuickControl.qml`

**Checkpoint**: User Story 1 is fully functional and independently testable — this alone is a shippable MVP.

---

## Phase 4: User Story 2 - Toggle keyboard backlight from the bar (Priority: P2)

**Goal**: One click on the widget turns the keyboard backlight on/off.

**Independent Test**: With the backlight off, click the widget and confirm the physical backlight turns on; click again and confirm it turns off.

### Implementation for User Story 2

- [ ] T010 [US2] Extend T005's parsing to also read `Backlight` mode from the device's `BACKLIGHT2` block in `plugin/MxQuickControl.qml`
- [ ] T011 [US2] Implement the click handler: `solaar config <N> backlight Manual|Disabled` toggle via a dedicated `Process`, per contracts/solaar-cli.md, in `plugin/MxQuickControl.qml`
- [ ] T012 [US2] Optimistically update the displayed mode immediately on click, reconciled by the next Timer refresh (T006), in `plugin/MxQuickControl.qml`

**Checkpoint**: User Stories 1 and 2 both work independently.

---

## Phase 5: User Story 3 - Adjust backlight brightness from the bar (Priority: P3)

**Goal**: Scrolling over the widget steps keyboard brightness up/down.

**Independent Test**: With the backlight on at a mid-range level, scroll up and confirm brightness increases; scroll down and confirm it decreases and never exceeds the device's real min/max.

### Implementation for User Story 3

- [ ] T013 [US3] Extend T005's parsing to also read `Backlight Level` from the `BACKLIGHT2` block in `plugin/MxQuickControl.qml`
- [ ] T014 [US3] Implement the scroll handler: `solaar config <N> backlight_level <n±1>` via `Process`, clamped at 0, per data-model.md State Transitions, in `plugin/MxQuickControl.qml`
- [ ] T015 [US3] Detect an "out of bounds" `set` failure to learn and cap `levelMax` for the session, per contracts/solaar-cli.md, in `plugin/MxQuickControl.qml`

**Checkpoint**: All three user stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validation and documentation, spanning all stories.

- [ ] T016 Run every scenario in `quickstart.md` end-to-end against real paired hardware and record results
- [ ] T017 [P] Write repository `README.md` (what it does, install steps via `omarchy plugin`-style copy into `~/.config/omarchy/plugins/`, license) at repository root
- [ ] T018 [P] Confirm `omarchy-shell shell rescanPlugins` loads the widget with zero QML warnings/errors in the shell log

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational; independent of each other, implementable in priority order (P1 → P2 → P3) or in parallel
- **Polish (Phase 6)**: Depends on whichever user stories are in scope for the release being validated

### User Story Dependencies

- **US1 (P1)**: No dependency on US2/US3 — battery display works with zero backlight logic
- **US2 (P2)**: No dependency on US1's rendering, but shares the Foundational parsing pipeline (T005); independently testable via the click handler alone
- **US3 (P3)**: Builds on the same `BACKLIGHT2` parsing as US2 (T010) but its scroll handler (T014-T015) is independently testable without US2's click handler existing

### Parallel Opportunities

- T002 and T003 (Setup) in parallel
- T007 (Foundational) in parallel with T005/T006 once T004 exists (different concern, same file — coordinate on save order)
- Once Foundational (Phase 2) is done, US1, US2, and US3 phases can be implemented in any order; within this single-file plugin they touch the same `plugin/MxQuickControl.qml`, so true concurrent multi-author work isn't parallel in practice — sequence P1 → P2 → P3 is recommended
- T017 (README) in parallel with T016 (quickstart run)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup
2. Phase 2: Foundational
3. Phase 3: User Story 1
4. **STOP and VALIDATE**: Run the User Story 1 section of `quickstart.md`
5. This alone is a shippable MVP — battery visibility with zero backlight risk

### Incremental Delivery

1. Setup + Foundational → widget loads, hides gracefully, refreshes
2. + User Story 1 → battery visible (MVP, ship here if backlight isn't needed yet)
3. + User Story 2 → one-click backlight toggle (the original motivating pain point)
4. + User Story 3 → scroll-to-adjust brightness (polish)
5. + Phase 6 → validated against real hardware, documented, ready to publish

## Notes

- No test tasks: this project has no automated test harness (constitution,
  Development Workflow); `quickstart.md` (T016) is the acceptance gate.
- Commit after each task or logical group, consistent with the constitution's
  Development Workflow section.
- Single-file plugin (`plugin/MxQuickControl.qml`) by design (constitution
  Principle I, Simplicity First) — do not split into multiple QML files or
  add a services/models layer unless a future story genuinely requires it.
