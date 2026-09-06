# Guidance for agents (and the humans reviewing them)

This file is for AI coding agents working in this repository, and for the
person supervising one. It is deliberately short and specific: it records
the things that have already gone wrong here, so they do not go wrong the
same way twice.

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first — everything there applies.
This adds only what is peculiar to working on this code without hands on
the hardware.

## Orientation, in order

1. [`specs/constitution.md`](specs/constitution.md) — the non-negotiables.
   Shell out to `solaar`, stay a bar widget, no new daemons.
2. [`Model.js`](Model.js) — the parser and state logic, and the only place
   where device behaviour is written down as executable rules.
3. [`specs/001-mx-quick-control/`](specs/001-mx-quick-control/) — what the
   plugin is and the `solaar` command contract it depends on.
4. [`specs/002-public-release-rc/`](specs/002-public-release-rc/) — the
   remaining work, with each task's justification.

## The hardware is the source of truth, not the tool that reads it

`solaar` reports a *saved* value and a *live* value, and they disagree
precisely when something is broken. The widget's own `status` output is
optimistic by design and will happily report a lit keyboard that is dark.

```bash
solaar show | grep -E "^ +Backlight Level +:"    # live — the real answer
```

Never conclude a change works from the widget's own state. This is the
single most expensive mistake made in this project.

## Verify by driving, not by asking a person to click

The widget exposes its controls over IPC. Use them; do not run a
click-and-report loop with a human as the test harness.

```bash
Q="qs -p /usr/share/omarchy/shell ipc call alebairos.mx-quick-control"
$Q status; $Q backlight; $Q level 5
```

Reserve human verification for what genuinely needs eyes: whether a glyph
renders, whether an interaction *feels* right, whether the panel looks
native beside the built-ins. Those are real and cannot be automated here.

## Things that have silently wasted time here

- **`omarchy-shell shell rescanPlugins` does not reload a changed root
  type.** It logs "reloading" and keeps the old code. Use `omarchy restart
  shell` for anything structural, and confirm the process actually
  restarted (`ps -o pid,lstart -e | grep quickshell`).
- **QML cannot observe mutations to plain JavaScript objects**, and a
  binding that returns the same object reference emits no change signal.
  Keyboard state therefore lives in real observable properties. Do not
  "tidy" it back into a computed object.
- **`Process.running = true` is a no-op while that process is already
  running**, and inside its own `onExited` it still reads as running.
  Queued work is drained via `Qt.callLater` for that reason.
- **Astral-plane Nerd Font codepoints get mangled by naive text edits.**
  After editing a glyph, verify the codepoint rather than the rendering:
  `python3 -c "..."` printing `hex(ord(c))`. Check the font actually has it
  with `fc-list ':charset=F030C' family`.
- **`.pragma library` breaks node's parser.** `Model.js` is loaded by both
  QML and the test runner, so it must stay plain JavaScript.

## Do not trust a green test suite

Before claiming a test protects something, break the code and watch it
fail. A test here asserting "reads the live level, never the saved one"
passed with the parser deliberately broken, because the live line follows
the saved one and overwrote it — right answer, wrong reason, and it would
have slept through a real regression.

When adding a test for a fix, mutate the fix and confirm the new test
fails. Say in the commit message that you did.

## Calibrating things only a human can see

Some facts are only obtainable by someone looking at the hardware: what the
LEDs are doing, whether an interaction feels right, whether a glyph renders.
There is a method for that, learned by doing it badly first — see
[`specs/research/hitl-calibration.md`](specs/research/hitl-calibration.md).

The short version: make it drivable from one command before asking anyone to
look, change one thing per trial, leave the state applied so the answer can
arrive whenever they are next at the keyboard rather than inside a timed
window, label honestly until confirmed, and write each answer straight into
the code with the observation as the comment.

## Reporting

Report what was verified and how, and state plainly what was not. "Tests
pass and it loads without QML errors" is not the same claim as "the
backlight physically turns on", and only one of them can be made from a
terminal. If something is unverified — a device you do not have, a bar
orientation you cannot see — say so rather than implying coverage.
