# Tasks: Public Release Candidate

**Input**: [spec.md](./spec.md), and the audit findings recorded below

**Prerequisites**: 001-mx-quick-control shipped and verified against real
hardware.

**Tests**: This release introduces the project's first automated tests
(Phase D). Until then the acceptance gate remains manual verification per
the constitution.

## Format: `[ID] [P?] [Story] Description`

---

## Audit findings this plan is answering

Measured or read from the installed Omarchy shell, not assumed:

| Finding | Evidence |
|---|---|
| Native install path is broken for this repo | `omarchy plugin validate .` exits 1 at repo root ("missing manifest.json"), exits 0 on `plugin/`; `omarchy-plugin-add` clones and validates `$stage/manifest.json` |
| Emoji icons are not an Omarchy idiom | No first-party bar widget uses emoji; Microphone uses Nerd Font `󰍭`/`󰍬`. Our `💡`/`⌨` also carry no `color:` binding, so they ignore the theme |
| Keyboard navigation is expected of panels | 9 of the built-in panels implement `PanelKeyCatcher`; this plugin implements none |
| Per-instance settings are the norm | Built-ins read `setting("showPercentage", …)`, `setting("refreshMinutes", …)` etc. from `shell.json`; this plugin has zero |
| Vertical bars are supported by built-ins | 14 first-party files branch on `bar.vertical`; this plugin does so incidentally, not deliberately |
| Escape hatch convention exists | Microphone middle-click opens the audio panel; this plugin offers no route to Solaar for unexposed settings |
| Staleness window | Full refresh is on a 300s timer, so a level changed in the Solaar GUI or via Fn keys can display stale for up to 5 minutes |
| `solaar` call costs | `solaar show` 10.5s; targeted `solaar config <n> backlight` 2.5s; `backlight_level` 2.2s |

---

## Phase A: Native install (BLOCKER)

**Purpose**: Without this, `omarchy plugin add` refuses the repo outright.

- [ ] T001 Move `plugin/manifest.json` and `plugin/MxQuickControl.qml` to the repository root; delete the now-empty `plugin/` directory
- [ ] T002 Add `barWidget.defaultSection: "right"` to `manifest.json` (installer currently falls back to `center`)
- [ ] T003 Remove the leftover debug `console.log` in the `dispatchMode` busy branch of `MxQuickControl.qml`
- [ ] T004 Verify `omarchy plugin validate .` exits 0 at the repo root, and that a clean `omarchy plugin add <url> --enable` installs and enables the widget

**Checkpoint**: The documented one-line install works on a machine that has never seen this plugin.

---

## Phase B: Omarchy-native look and feel (P1)

**Purpose**: Make it indistinguishable from a built-in. This is what
determines acceptance, so it outranks packaging polish.

- [ ] T005 [US2] Replace the `💡`/`⌨` emoji with Nerd Font glyphs in `MxQuickControl.qml`, chosen from the set the first-party widgets already draw from
- [ ] T006 [US2] Bind every icon's `color` to the theme foreground so icons follow theme changes like their neighbours
- [ ] T007 [US2] Add `PanelKeyCatcher` to the panel with `focusTarget`: arrow keys move a cursor across the toggle and slider, Enter activates, Esc closes
- [ ] T008 [US2] Wire `onTabRequested` to `switchPanel(direction)` so this panel joins the Tab chain between adjacent panels
- [ ] T009 [US2] Give the toggle and slider `hasCursor` bindings driven by the panel cursor, matching the highlight behaviour of first-party controls
- [ ] T010 [US2] Handle `bar.vertical` deliberately in both the bar button and the panel layout (the fixed-width slider row currently assumes horizontal)
- [ ] T011 [US2] Middle-click on the bar icon launches Solaar, as the escape hatch to every setting this widget deliberately does not expose
- [ ] T012 [US2] Emit the standard Omarchy OSD on backlight level change, as volume and screen brightness already do

**Checkpoint**: Beside built-in widgets, on both themes and both bar orientations, keyboard-only — nothing gives it away.

---

## Phase C: Freshness, honesty, and tunability (P2)

- [ ] T013 [US3] Targeted read (`solaar config <n> backlight`, ~2.3s) when the panel opens, so state is current without paying the 10.5s enumeration
- [ ] T014 [US3] Expose per-instance settings via `setting()` from `shell.json`: default on-level, refresh interval, and whether to show the battery line
- [ ] T015 [US3] Replace the silent hide when `solaar` is missing with an explicit panel state naming the install command
- [ ] T016 Probe the device's real maximum backlight level rather than assuming 7 until a write is rejected — or, if no clean probe exists, document the assumption as a known limitation

**Checkpoint**: The widget tells the truth about the device and about itself, and can be tuned like any other widget.

---

## Phase D: Tests (P2)

**Purpose**: Close the project's largest gap. Every defect in 001 lived in
one of the two components extracted here.

- [ ] T017 Extract the `solaar` output parser and the write/queue state machine from `MxQuickControl.qml` into `Model.js`, following Omarchy's own convention (`bar/BarModel.js`, `panels/power/Model.js`)
- [ ] T018 [P] Unit-test the parser against real `solaar show` fixtures: the `(saved)` versus live duplicate-field trap, a device with no battery, a mouse-only device, no devices at all, and malformed output
- [ ] T019 [P] Unit-test the state machine: toggle maths, level clamping, and queue/drain ordering under overlapping requests
- [ ] T020 Integration test driving the widget with a fake `solaar` on `PATH` that returns fixtures and records invocations, asserting **the exact commands issued** — the check that would have caught the dropped-write defect
- [ ] T021 [P] GitHub Actions workflow running the unit tests on push

**Checkpoint**: Reintroducing any 001-era defect fails a test.

---

## Phase E: Release (P3)

- [ ] T022 [P] Rewrite `README.md` around the one-line install, with a screenshot and an explicit supported-devices section separating *verified* hardware from *expected to work*
- [ ] T023 [P] Add `CHANGELOG.md`
- [ ] T024 Set version `1.0.0-rc.1` in `manifest.json` and tag the release
- [ ] T025 Re-run the full manual verification from [001's quickstart](../001-mx-quick-control/quickstart.md) against the restructured, renamed build before tagging

---

## Explicitly out of scope

Deliberately not exposed, per constitution Principle I (Simplicity First) —
this is a bar widget, not a second Solaar GUI. Solaar itself is one
middle-click away (T011) for all of it:

`fn-swap`, `multiplatform` (Windows/MacOS/iOS), `disable-keyboard-keys`,
`divert-keys`, `backlight_duration_*`, mouse `dpi`, mouse
`reprogrammable-keys`, `lowres-scroll-mode`.

Candidates for a *later* release, not this one: `change-host` (switching
the keyboard between paired computers — genuinely useful, a single call)
and mouse `dpi`.

---

## Open decisions

1. **Plugin id namespace.** `alebairos.mx-quick-control` is valid and
   collision-free, but the `<username>.` form is specifically the *clone*
   convention (`omarchy-plugin-clone` builds `${USER}.${id}` so a shared
   clone does not collide). For a published plugin the namespace should be
   a deliberate public identity. Keep as-is, or choose another before it is
   public and expensive to change?
2. **Test depth for RC.** Phase D in full (unit + integration), or
   unit-only to ship sooner with integration following? Integration is the
   phase that covers the class of bug that actually bit us.

---

## Dependencies & Execution Order

- **Phase A** blocks everything: until the repo installs natively, none of
  the rest can be validated the way a user would encounter it.
- **Phase B** is the acceptance-critical phase and should follow
  immediately; it is independent of C and D.
- **Phase C** is independent of B and can proceed in parallel.
- **Phase D** benefits from A (stable file layout) but is otherwise
  independent; T017 blocks T018–T020.
- **Phase E** last, with T025 gating the tag.
