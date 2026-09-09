# Changelog

All notable changes to this project are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Note on releases: `omarchy plugin add` clones the default branch, so `main`
is the distribution channel rather than only an integration branch. It is
merged to only from a branch whose CI is green.

## [Unreleased]

### Fixed

- **Effect switching no longer writes over LEDs it failed to clear.** The
  backlight is blanked between effects to stop the previous effect's last
  frame staying lit; that write's return value was discarded, so a blank that
  lost a race failed silently and the new effect was written anyway — the
  intermittent "Wave to Static leaves a frozen wave" fault. `request` answers
  `None` on a timeout or error, so the failure was already being reported and
  thrown away. The blank is now retried on its own small budget, and a blank
  that never lands is reported (`"blanked": false`) rather than raised: the
  effect change itself succeeded, and failing the call would show an error
  for something that worked.

  Reproducible on demand for the first time, via a new `MXD_STUB_FAILED_WRITES`
  knob — the existing `MXD_STUB_REJECT` fails *every* write, so it could only
  model a device refusing outright, never contention.

- **The keyboard's own effect key no longer waits on a device read.** Pressing
  it took 3.08s to raise an OSD, measured off `/dev/hidraw` from the device's
  own notification to the last frame of the read it triggered. The value was
  in that first notification the whole time: a BACKLIGHT2 broadcast reports
  `[levels, level, ?, effect]`, and Solaar hands its rule engine `data[2:]`,
  so the effect sits at `data[3]`.

  `Execute` cannot substitute a matched value into its argument list, so
  [`solaar-rule.yaml`](solaar-rule.yaml) now enumerates one rule per effect —
  `TestBytes: [3, 4, N, N]` paired with a literal `N` — and the rule list
  short-circuits, so exactly one fires.

  Verified on the reference hardware against the running shell, watching the
  wire and the widget's own state at the same time:

  | device broadcast | widget shows the new effect | gap |
  |---|---|---|
  | 14:15:54.075 → effect 0 | 14:15:54.231 | 156ms |
  | 14:15:56.130 → effect 3 | 14:15:56.305 | 175ms |
  | 14:15:59.002 → effect 2 | 14:15:59.069 | 67ms |

  Those gaps are upper bounds: the observer polled at 100ms and spent ~36ms
  per sample in `qs ipc call`, so the 67ms row is the one that bounds the real
  figure. Under 100ms, against 3.08s.

  The stronger evidence is the absence: **three frames crossed the wire in
  the twenty seconds covering all three presses** — the three notifications
  themselves and nothing else. `busy` never went true. One press previously
  produced around forty frames of receiver enumeration.

  Brightness from F4/F5 is unchanged in speed and deliberately so: the
  notification is a full state report rather than a delta, so it arrives
  carrying an *unchanged* effect. `Model.externalEffectAction` treats that as
  "something moved that this rule cannot name" and falls back to the previous
  read, rather than mistaking it for nothing having happened and swallowing
  the change.

  The old single `deviceChanged` rule keeps working, so an existing
  `~/.config/solaar/rules.yaml` from 1.0.0 needs no edit to keep behaving as
  it does today.

## [1.1.0] — 2026-09-07

One transport to the device. The plugin previously reached the keyboard
three different ways — `solaar show` (10.5s), `solaar config` (2.2s per
call) and a bundled effect helper (2.1s) — across six call sites. All of it
is now a single bundled transport, `mx-device`, speaking JSON over Solaar's
own `logitech_receiver` library.

No new features. This is a data-path rewrite, and every user-visible
behaviour is meant to be identical apart from speed.

### Changed

- Opening the panel issues **one** device call instead of three. Measured
  interleaved with 1.0.0 on the reference hardware, alternating within the
  same minute so both meet the same device conditions: 6475 / 6832 / 6626 ms
  before, 2185 / 1874 / 2096 ms after.
- Device discovery no longer costs a separate 10.5s enumeration; the same
  single call returns the device list.
- A user-visible action issues exactly one device invocation, and a
  successful write is no longer followed by a read to confirm it.
- The brightness slider's maximum is read from the device on every refresh
  rather than being corrected only after a write is rejected as out of
  range.

### Fixed

- **"No backlight-capable keyboard" while the keyboard was working.** A
  contended read that omitted the device's backlight block was
  indistinguishable from a keyboard that has no backlight, because scraped
  text cannot express "I could not read this". The transport reports
  `no-receiver`, `no-devices`, `unreadable` and `rejected` as distinct
  answers, and the panel now says "Could not read the keyboard" rather than
  claiming there is none. A failed read no longer tears down working state.
- A missing receiver reported "no devices" rather than "no receiver".
  Found by the test suite, not by hardware.

### Removed

- `mx-backlight-effect`, the `solaar show` text parser, and every `solaar`
  invocation in the data path. Solaar is still required — the plugin uses
  its library — and is still what the panel's middle-click opens.

### Internal

- `mx-device` is covered by a stub `logitech_receiver`, so the transport can
  be driven without hardware and every degraded frame that caused a 1.0.0
  bug is reproducible on demand.
- The node-probe budget is asserted by a test. Solaar's `Device` constructor
  spends up to one second per device in a busy-wait looking for a hidraw
  node that receiver-paired devices do not have — measured at 1001ms,
  returning nothing, and two thirds of every invocation's cost. Restoring
  that default would be invisible without the test.

## [1.0.0] — 2026-09-06

First stable release. Verified by removing the plugin entirely and
reinstalling from GitHub the way a new user would, then exercising every
control against the hardware.

### Added

- Per-instance settings from `shell.json`: `defaultOnLevel`,
  `refreshMinutes` and `showBattery`, read through the base panel's
  `setting()` exactly as first-party widgets do, and clamped rather than
  trusted.

### Fixed

- **A single degraded read could make the widget announce "no
  backlight-capable keyboard" while the keyboard was working.** The device
  answers contention with a well-formed frame that omits the `BACKLIGHT2`
  block, so a truncated read and a keyboard without a backlight look
  identical. A loss now requires three consecutive confirmations, with a
  fast re-read between them.

### Verified for this release

- Clean `omarchy plugin add` from GitHub, with the bundled helper arriving
  executable
- Backlight toggle, brightness, and effect changes reaching the device
- Panel refresh on open, and live following of the keyboard's own keys with
  the optional Solaar rule
- Vertical (right-side) bar
- 33 unit and functional tests, and both CI checks

### Still true, and deliberately so

- Roughly two seconds per action: this shells out to `solaar` rather than
  holding a connection, and that startup cost is the floor for anything
  that refuses to run a daemon.
- Only an MX Mechanical Mini and a Signature M650 on a Bolt receiver have
  ever been tested. Everything else — other backlit keyboards, Bluetooth
  pairing, multiple keyboards — is expected to work rather than known to.
  Reports are welcome, especially negative ones.

## [1.0.0-rc.5] — 2026-09-06

Closes the last of the README's known limitations: the panel can now follow
the keyboard's own backlight keys.

### Added

- **Optional live sync with the keyboard's own keys.**
  [`solaar-rule.yaml`](solaar-rule.yaml) is an opt-in Solaar rule that calls
  the widget when the device reports a backlight change, so pressing F4/F5
  or the effect key moves the panel and pops an on-screen display, in about
  two seconds.

  The device has always announced these changes over HID++; hearing them
  needs a process listening continuously, and this plugin deliberately is
  not one (constitution Principle V). Solaar already is such a process for
  anyone who runs it, and its rules engine exists to react to exactly these
  notifications — so the listening is delegated rather than duplicated.
  Without Solaar running nothing breaks: the panel catches up on open, as
  before.
- `status` over IPC now reports the current effect, so this class of problem
  can be diagnosed from a terminal instead of by watching the screen.

### Fixed

- **The effect OSD never appeared** while the brightness one always did.
  A `Process`'s `onExited` and its `StdioCollector`'s `onStreamFinished`
  fire in no guaranteed order, and the queue driver cleared its "announce"
  flag when the queue emptied — so whichever read ran *last* could lose the
  race with itself. The effect read is last; the level read never is.
- **The hardware-key OSD lagged about five seconds.** An external change ran
  three reads (~7s) when the effect helper's single call already reports
  level and effect together (~2s).

### Verified

- **Vertical bars.** Confirmed working on a right-side bar, with no code
  change required: placement comes from `Ui/KeyboardPanel` reading
  `bar.position`, and the panel sizes itself rather than assuming geometry.
  Left-side bars remain untested.

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

[Unreleased]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.5...v1.0.0
[1.0.0-rc.5]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.4...v1.0.0-rc.5
[1.0.0-rc.4]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.3...v1.0.0-rc.4
[1.0.0-rc.3]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.2...v1.0.0-rc.3
[1.0.0-rc.2]: https://github.com/alebairos/omarchy-mx-plugin/compare/v1.0.0-rc.1...v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/alebairos/omarchy-mx-plugin/releases/tag/v1.0.0-rc.1
