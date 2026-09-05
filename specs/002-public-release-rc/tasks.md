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

- [x] T001 Move `plugin/manifest.json` and `plugin/MxQuickControl.qml` to the repository root; delete the now-empty `plugin/` directory
- [x] T002 Add `barWidget.defaultSection: "right"` to `manifest.json` (installer currently falls back to `center`)
- [x] T003 Remove the leftover debug `console.log` in the `dispatchMode` busy branch of `MxQuickControl.qml`
- [x] T004 Verify `omarchy plugin validate .` exits 0 at the repo root, and that a clean `omarchy plugin add <url> --enable` installs and enables the widget

**Checkpoint**: The documented one-line install works on a machine that has never seen this plugin.

---

## Phase B: Omarchy-native look and feel (P1)

**Purpose**: Make it indistinguishable from a built-in. This is what
determines acceptance, so it outranks packaging polish.

- [x] T005 [US2] Replace the `💡`/`⌨` emoji with Nerd Font glyphs in `MxQuickControl.qml`, chosen from the set the first-party widgets already draw from
- [x] T006 [US2] Bind every icon's `color` to the theme foreground so icons follow theme changes like their neighbours
- [x] T007 [US2] Add `PanelKeyCatcher` to the panel with `focusTarget`: arrow keys move a cursor across the toggle and slider, Enter activates, Esc closes *(verified at the keyboard — see T028)*
- [x] T008 [US2] Wire `onTabRequested` to `switchPanel(direction)` so this panel joins the Tab chain between adjacent panels *(verified at the keyboard — see T028)*
- [x] T009 [US2] Give the toggle and slider `hasCursor` bindings driven by the panel cursor, matching the highlight behaviour of first-party controls *(verified at the keyboard — see T028)*
- [ ] T010 [US2] Handle `bar.vertical` deliberately in both the bar button and the panel layout (the fixed-width slider row currently assumes horizontal)
- [x] T011 [US2] Middle-click on the bar icon launches Solaar, as the escape hatch to every setting this widget deliberately does not expose
- [ ] T012 [US2] Emit the standard Omarchy OSD on backlight level change, as volume and screen brightness already do

**Checkpoint**: Beside built-in widgets, on both themes and both bar orientations, keyboard-only — nothing gives it away.

---

## Phase B2: Keyboard navigation, verified (P1)

Keyboard operation is core to the Omarchy experience, not a nicety: every
first-party panel is fully drivable without a pointer, and a plugin that is
not breaks the flow the moment a user reaches for it. T007-T009 wrote the
code; nothing has confirmed it *works*, and marking those tasks done on the
strength of having written them was premature. These items close that gap.

**Already verified** (empirically, not assumed): the panel is summonable as
`SUPER + CTRL + 1`. `omarchy-shell shell togglePanelAt right 1` returns
`alebairos.mx-quick-control`, so it is correctly enumerated among the
built-in panels — the `Panel` base supplies the `open()` / `close()` /
`opened` interface that `Bar.panelNavigationSlots` requires. Nothing extra
was needed for summoning; the numbering is positional, so the hotkey follows
the widget if the bar is rearranged.

- [x] T028 [US2] **HITL verification of in-panel navigation.** Partially
      confirmed at the keyboard on 2026-09-05:
        - `SUPER + CTRL + 1` summons the panel — **works**
        - <kbd>Enter</kbd> toggles the backlight on and off — **works**
        - <kbd>←</kbd>/<kbd>→</kbd> change the brightness level — **works**
        - <kbd>↑</kbd>/<kbd>↓</kbd> moving the cursor between the toggle row
          and the slider row — **works**
        - <kbd>Esc</kbd> closing the panel — **works**
        - <kbd>Tab</kbd> reaching the adjacent panels and wrapping back
          round to this one — **works**, including repeated presses cycling
          through the right section and returning here. `Bar.switchPanelFrom`
          locates this widget's slot correctly, which was the part of the
          chain the other five paths did not exercise.
      All six keyboard paths are confirmed at the keyboard; this task is
      done.
- [ ] T029 [US2] Confirm the cursor appears only after the first arrow press
      when the panel is opened with the mouse, and decide what should happen
      when it is opened with `SUPER + CTRL + 1`: a keyboard-summoned panel
      arguably ought to show its cursor immediately, since the user is
      already on the keyboard. Check what the first-party panels do and
      match them rather than inventing behaviour.
- [ ] T030 [US2] Verify the brightness slider is reachable and adjustable by
      keyboard *while the backlight is off*. It is currently `enabled: false`
      and dimmed when off, and `cursorRowCount` drops to 1, so the cursor
      cannot reach it — which is probably right, but it means the only
      keyboard route to turning the light on is the toggle. Confirm that is
      the intended flow.
- [x] T031 [US2] Document the keyboard controls in the README, including the
      `SUPER + CTRL + <n>` summon and the fact that the number is positional.
      Users should not have to infer that a third-party panel participates
      in the same hotkey scheme as the built-ins.

---

## Phase C: Freshness, honesty, and tunability (P2)

- [x] T013 [US3] Targeted read (`solaar config <n> backlight`, ~2.3s) when the panel opens, so state is current without paying the 10.5s enumeration
- [ ] T014 [US3] Expose per-instance settings via `setting()` from `shell.json`: default on-level, refresh interval, and whether to show the battery line
- [x] T015 [US3] Replace the silent hide when `solaar` is missing with an explicit panel state naming the install command
- [ ] T016 Probe the device's real maximum backlight level rather than assuming 7 until a write is rejected — or, if no clean probe exists, document the assumption as a known limitation

- [ ] T027 [US3] Document, or fix, that `omarchy plugin remove` also drops the widget's bar-layout entry, so a reinstall needs `omarchy plugin enable` again (found by reinstalling from GitHub; now stated in the README)

**Checkpoint**: The widget tells the truth about the device and about itself, and can be tuned like any other widget.

---

## Phase D: Tests (P2)

**Purpose**: Close the project's largest gap. Every defect in 001 lived in
one of the two components extracted here.

- [x] T017 Extract the `solaar` output parser and the write/queue state machine from `MxQuickControl.qml` into `Model.js`, following Omarchy's own convention (`bar/BarModel.js`, `panels/power/Model.js`)
- [x] T018 [P] Unit-test the parser against real `solaar show` fixtures: the `(saved)` versus live duplicate-field trap, a device with no battery, a mouse-only device, no devices at all, and malformed output
- [x] T019 [P] Unit-test the state machine: toggle maths, level clamping, and queue/drain ordering under overlapping requests
- [x] T020 Integration test driving the widget with a fake `solaar` on `PATH` that returns fixtures and records invocations, asserting **the exact commands issued** — the check that would have caught the dropped-write defect
- [x] T021 [P] GitHub Actions workflow running the unit tests on push

**Checkpoint**: Reintroducing any 001-era defect fails a test.

---

## Phase E: Release (P3)

- [x] T022 [P] Rewrite `README.md` around the one-line install, with a screenshot and an explicit supported-devices section separating *verified* hardware from *expected to work*
- [x] T023 [P] Add `CHANGELOG.md`
- [x] T024 Version and tag each release candidate (`v1.0.0-rc.1` baseline, `v1.0.0-rc.2` tests + native look, `v1.0.0-rc.3` slimmed install + contributor docs), with GitHub releases and changelog entries
- [ ] T026 Tag `v1.0.0` once Phases B and C close and T025 passes
- [ ] T025 Re-run the full manual verification from [001's quickstart](../001-mx-quick-control/quickstart.md) against the final build before tagging 1.0.0 — including a from-scratch `omarchy plugin add` on a clean machine, both bar orientations, and a light and a dark theme

---

## Parked: backlight effects (investigation, not scheduled)

The MX Mechanical Mini has six firmware backlight effects — Static,
Contrast, Breathing, Wave, Reaction, Random — and `Fn` + the backlight key
cycles them, on Linux as well as Windows. The obvious feature is a third
panel row showing the current effect and letting you cycle it.

**Parked because the evidence says the host cannot see them.** Two
independent findings, both from this machine:

1. **Solaar probed the device and recorded every lighting capability as
   absent.** `~/.config/solaar/config.yaml` lists, under this keyboard's
   `_absent` key: `rgb_control`, `rgb_zone_`, `per-key-lighting`,
   `led_control`, `brightness_control`, `rgb_idle_effect`,
   `rgb_startup_animation`, `rgb_shutdown_animation`, and more. The only
   lighting feature present is `BACKLIGHT2 {1982}`, which exposes mode,
   level, and three fade delays — there is no effect field.
2. **Cycling the effects changes nothing the host can observe.** A full
   `solaar show` was diffed against a baseline while the effects were
   cycled by hand: the only field that ever changed was `Backlight Level`.
   No effect state appeared anywhere in the output.

Taken together: the effects live in the keyboard's firmware and are not
reported over any HID++ feature Solaar knows about.

**Why this is not simply "more work" but a constitutional question.**
Reading or setting the effect would mean going around Solaar to
undocumented HID++ feature pages, which Principle II of
[the constitution](../constitution.md) forbids outright — that principle
exists precisely so this plugin does not become a half-reimplementation of
a library that already works. The legitimate route is upstream: Solaar (or
`python-logitech-receiver`) gains effect support, and this plugin then
exposes it in one more row for free.

- [ ] T032 **Investigate whether the effects are reachable at all.** Check
      whether Logi Options+ on Windows changes anything observable over
      HID++ (a USB capture would settle it), whether the pwr-Solaar project
      has an open issue or a feature page for MX Mechanical effects, and
      whether the effect is stored in a writable register or is purely a
      firmware-side cycle with no host representation. Outcome is either an
      upstream contribution or a documented "not possible", not a
      workaround here.
- [ ] T033 **Separately: capturing the key press.** `divert-keys` can set
      `Backlight Down` / `Backlight Up` to `Diverted`, which makes the
      keyboard send HID++ notifications instead of acting natively — this
      was verified on the Emoji key earlier in the project. That is a path
      to *knowing* the key was pressed, but note the trade-off: a diverted
      key stops doing its firmware job, so diverting the effect-cycle key
      would disable the very cycling it is meant to mirror. Only worth
      pursuing if T032 finds the effect is host-settable.

Neither task blocks 1.0.0.

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

## Decisions (settled 2026-09-04)

### 1. Plugin id namespace: keep `alebairos.mx-quick-control`

**Decided: keep the publisher handle. Do not bind the namespace to Solaar.**

The namespace slot carries *publisher identity*, not the dependency. That is
exactly how Omarchy uses it: `omarchy.*` is reserved for first-party and
validation rejects it outright, and `omarchy-plugin-clone` stamps
`${USER}.` precisely so the id "stays yours".

An id such as `solaar.mx-quick-control` would therefore claim an identity
belonging to the pwr-Solaar project — implying an official plugin they
neither wrote nor endorsed. That is a misrepresentation, and in a community
that cares about provenance it is a reason to reject a plugin on sight.
It also ages badly: the namespace should not be hostage to a backend
choice, and a publisher namespace lets further plugins ship under it
without collision.

Solaar is surfaced where it genuinely helps discovery and gives credit —
the manifest `description`, the README's requirements section, and the
middle-click-to-open action (T011). Attribution, not appropriation.

**Consequence**: no rename, no work. Ids stay as they are.

### 2. Test depth: full Phase D, including the integration test

**Decided: T017-T021 in full, not unit-only.**

The genuine open-source acceptance minimum is narrower than this: pure
logic under unit test, plus CI running green on push (T017-T019, T021). A
reviewer wants to see that tests exist, run automatically, and exercise the
logic rather than the framework.

Phase D is nonetheless taken in full because this project's own defect
history argues for it. The dropped-write bug, the no-op write elided by
solaar, and the mode-switch level reset were all invisible to unit tests of
pure functions — they lived in *which commands were issued, and in what
order*. An RC whose suite passes on all three of the defects a human
actually found would be theatre. T020's fake `solaar` is a short shell
script on `PATH`, so the marginal cost is small against what it covers.

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
