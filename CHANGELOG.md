# Changelog

All notable changes to this project are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Note on releases: `omarchy plugin add` clones the default branch, so `main`
is the distribution channel rather than only an integration branch. It is
merged to only from a branch whose CI is green.

## [Unreleased]

Remaining before `1.0.0`: vertical-bar layout, on-screen display when the
level changes, a targeted refresh when the panel opens, per-instance
settings from `shell.json`, an explicit "Solaar not installed" state, and a
README rewrite that separates verified hardware from hardware merely
expected to work.

## [1.0.0-rc.4] — 2026-09-06

Adds lighting-effect control, and a good deal of hardening found by using it.

### Added

- **Lighting effects.** The panel gains a third row selecting the keyboard's
  effect — Static, Breathing, Contrast, Reaction, Random, Wave — clickable,
  right-clickable to go back, and reachable by keyboard like the other rows.
  Solaar's CLI has no setting for this; the plugin reaches it through
  Solaar's own `logitech_receiver` library, so it adds no dependency and
  does not touch `/dev/hidraw` directly. The list comes from the device's
  own capability bitmap rather than a hardcoded table, and each value was
  calibrated against real hardware rather than guessed.
- An "off" effect the device advertises is deliberately **not** offered: it
  clears the backlight's enabled flag, and the panel already has a toggle
  for that. Cycling skips it in both directions.
- CI guards against a broken `\U` unicode escape in QML, and against real
  device serials in test fixtures.

### Fixed

- **Every device read is now serialized.** The effect helper was missing
  from the single-flight guard, so it ran concurrently with `solaar` calls
  and both received degraded frames; separately, the panel's refresh-on-open
  dropped its queue whenever anything was in flight. Together these left a
  stale brightness level on screen after F4/F5.
- **Switching to a static effect left the previous effect's last frame**
  frozen on the keys. A brief off-pulse before applying clears it.
- **The helper could strand the keyboard dark**, by carrying through an
  `enabled` flag the off-effect had cleared.
- **Degraded reads returned zeros rather than errors**, which the panel
  would have read as "this keyboard has no effects" and hidden the row.
- The brightness slider's maximum is read from the device's reported level
  count instead of assuming eight and correcting after a rejected write.
- The effect row's icon rendered as the literal text `f0068`, because
  `\U000F0068` is not a valid QML escape.

### Changed

- Real device serials removed from the committed test fixture.
- Repository opened to contributors: `main` is protected, merges are
  rebase-only, and there are PR and issue templates, a security policy and a
  code of conduct.

## [1.0.0-rc.3] — 2026-09-04

Housekeeping release. No change to how the plugin behaves; a large change to
what lands on your machine when you install it.

### Removed

- **Spec-kit scaffolding (`.specify/`, `.claude/skills/speckit-*`)**, about
  5,100 lines. `omarchy plugin add` performs a full `git clone` into
  `~/.config/omarchy/plugins/`, so everything in this repository is copied
  onto every user's machine. That scaffolding is generic — a grep for
  anything naming Solaar, the backlight, or this device matched exactly one
  file in it — and is regenerable with `specify init`, so it was pure noise
  in a directory Omarchy explicitly asks users to review before enabling.
  A fresh install goes from 676K to 504K. The saving is smaller than the
  removed 5,100 lines suggests, because `plugin add` clones full history
  and the deleted files therefore still travel in `.git`; the real win is
  that the working tree a reviewer opens now contains only the plugin, its
  tests and its reasoning.

### Added

- **`CONTRIBUTING.md`** — how to test, how to verify against the device
  rather than the widget, and the device quirks that look like redundant
  work and must not be "simplified" away.
- **`AGENTS.md`** — guidance for AI agents and their supervisors, recording
  the failure modes this project has already hit: QML not observing plain
  object mutations, `rescanPlugins` silently not reloading a changed root
  type, astral-plane glyphs mangled by naive edits, and the instruction not
  to trust a green test suite without breaking the code first.
- A CI check that the scaffolding cannot creep back and that every document
  contributors are pointed at actually exists.

### Changed

- The project constitution moved from `.specify/memory/constitution.md` to
  **`specs/constitution.md`**, so the one project-specific file in the
  removed scaffolding survives where the rest of the reasoning lives.

## [1.0.0-rc.2] — 2026-09-04

First release with automated tests and CI. Everything below was verified
against real hardware in addition to the suite.

### Added

- **Test suite (25 tests, zero dependencies).** Runs on node's built-in
  test runner; the plugin itself still ships no JavaScript runtime
  dependency. Unit tests cover the `solaar show` parser against a real
  captured fixture plus edge cases (mouse-only, no battery, no devices,
  malformed output) and the state logic. Functional tests execute planned
  commands against a fake `solaar` that records every invocation and
  emulates the device's real quirks, asserting the exact command sequence.
- **`Model.js`**, holding the parser and state logic as pure functions,
  following the convention of Omarchy's own plugins (`bar/BarModel.js`,
  `panels/power/Model.js`).
- **CI on every push and pull request**: the test suite, manifest
  validation mirroring `omarchy-plugin-validate`, and a guard against emoji
  re-entering the shipped QML.
- **Keyboard navigation.** Arrow keys move a cursor across the backlight
  toggle and the brightness slider, left/right adjust brightness, Enter
  activates, Esc closes, and Tab hands off to an adjacent panel — matching
  all nine first-party Omarchy panels.
- **Middle-click on the bar icon opens Solaar**, the escape hatch to every
  setting this widget deliberately does not expose. Mirrors the built-in
  Microphone widget's middle-click-through.
- The bar tooltip now reports device, battery and backlight state instead
  of a fixed string.

### Changed

- **Icons are now Nerd Font glyphs tinted from the active theme**
  (`mdi-keyboard`, `mdi-keyboard-off`, `mdi-brightness-7`), replacing emoji.
  No first-party Omarchy widget uses emoji: they render in a different font
  at a different weight and, without a colour binding, ignore the theme
  entirely. Every codepoint was verified present in JetBrainsMono Nerd Font
  with `fc-list :charset=…` rather than assumed.
- The plugin now lives at the **repository root**, so `omarchy plugin add
  <git-url>` installs it directly. Previously the plugin sat in `plugin/`,
  and since `omarchy plugin add` validates `manifest.json` at the clone
  root, the documented one-line install rejected this repository outright.
- `manifest.json` declares `barWidget.defaultSection: "right"`; the
  installer previously offered "center" by default.

### Fixed

- A parser test that passed for the wrong reason. It asserted that the live
  backlight level is read rather than the `(saved)` one, but still passed
  with the parser deliberately broken, because the live line follows the
  saved line and simply overwrote it. Found by mutation-testing the suite;
  fixed with a fixture containing only `(saved)` lines, which genuinely
  distinguishes the two.
- Removed a leftover debug `console.log` from the write path.

## [1.0.0-rc.1] — 2026-09-04

Initial release candidate: the working plugin, tagged as a rollback point
before the test and packaging work began.

### Added

- Bar widget showing battery for every paired Logitech device, with a
  click-to-open panel carrying a backlight on/off toggle and a brightness
  slider — the same panel pattern as the built-in Network, Bluetooth and
  Power widgets.
- All device access through the `solaar` CLI; no direct HID++ handling.

### Fixed

The defects below were all found by hand on real hardware during
verification, and are the reason the test suite in `rc.2` exists.

- **Backlight stayed dark after being switched on.** Two compounding causes:
  switching mode `Disabled → Manual` resets the device's *live* level to 0
  while `solaar` keeps reporting the unchanged saved value, and `solaar`
  elides a level write whose value equals the saved one — so the write
  meant to light the keyboard was dropped as a no-op. "Off" is now level 0
  with the device left permanently in `Manual`, making every toggle a
  single write that always differs from the previous value.
- **Writes silently lost on fast input.** Queue draining ran inside a
  `Process`'s `onExited`, where that process still reports `running`, so
  the drain hit its own busy guard and re-queued the item it was draining
  with nothing left to retry it. Drains are now deferred until the flag
  settles.
- **Controls did not react to state changes.** The panel bound to a
  computed property returning an element of a plain JavaScript array; QML
  cannot observe field mutations on plain objects, and reassigning the
  array returned the same object reference, so no change signal fired.
  Keyboard state now lives in real observable properties.
- **Toggling took 15–26 seconds.** Every write was reconciled with a full
  `solaar show`, measured at 10.5s against 2.2–2.5s for a targeted read. A
  successful write already matches the optimistic state, so no read is
  issued on success; the full enumeration is reserved for device discovery
  and battery on a slow timer. Toggling now settles in about 3 seconds.
- **The brightness slider doubled as an off switch** and could capture a
  drag the moment the row appeared. Its range now starts at 1, and the row
  stays mounted and merely dims when off, so nothing moves under the
  pointer.
- Plugin id namespaced to the publisher; `omarchy.*` is reserved for
  first-party plugins and installation is refused outright.

[Unreleased]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.4...HEAD
[1.0.0-rc.4]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.3...v1.0.0-rc.4
[1.0.0-rc.3]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.2...v1.0.0-rc.3
[1.0.0-rc.2]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.1...v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/alebairos/omarchy-mx-plugin/releases/tag/v1.0.0-rc.1
