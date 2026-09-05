# Contributing

Thanks for looking at this. It is a small plugin on purpose, so the bar for
a change is mostly: does it keep the plugin simple, does it still feel like
part of Omarchy, and can you show it works on real hardware.

## The one thing to know first

`omarchy plugin add` performs a **full `git clone` of the default branch**
into `~/.config/omarchy/plugins/`. That has two consequences:

1. **`main` is the distribution channel**, not just an integration branch.
   A broken `main` is a broken install for every new user immediately.
   Never merge red. Work on a branch, let CI go green, then merge and tag.
2. **Everything in the repository ships to users' machines.** Plugins run
   unsandboxed and Omarchy tells users to review the code before enabling
   it, so keep the repository free of anything that is not the plugin, its
   tests, or the reasoning behind it.

## Setup

You need [Solaar](https://pwr-Solaar.github.io/Solaar/) and a paired
Logitech device to run the plugin; you need only node to run the tests.

```bash
git clone https://github.com/alebairos/omarchy-mx-plugin.git
cd omarchy-mx-plugin
npm test          # no dependencies to install, node's built-in runner
```

To try your change on a real shell:

```bash
cp manifest.json MxQuickControl.qml Model.js \
   ~/.config/omarchy/plugins/alebairos.mx-quick-control/
omarchy restart shell
```

Use `omarchy restart shell`, not `omarchy-shell shell rescanPlugins`, for
anything structural. The hot-reload path silently fails to re-instantiate a
changed root type — it logs "reloading" and keeps running the old code,
which is an easy hour to lose.

## Testing without a pointer

The widget exposes its own controls over IPC, so you can drive and verify
it from a terminal instead of clicking:

```bash
Q="qs -p /usr/share/omarchy/shell ipc call alebairos.mx-quick-control"
$Q status        # device, mode, level, whether a solaar call is in flight
$Q backlight     # toggle
$Q level 5       # set brightness
$Q open / close  # the panel
```

**Verify against the device, not against the widget.** `solaar` reports a
saved value and a live value, and they disagree exactly when it matters:

```bash
solaar show | grep -E "^ +Backlight Level +:"   # the LIVE level
```

A change that looks right in `status` but leaves the live level at 0 has
not worked; that specific confusion cost a whole debugging session.

## Device quirks you must not "simplify" away

These are encoded in `Model.js` and covered by tests. They look like
redundant work and are not:

- **A level write only takes effect while the mode is `Manual`.**
- **`solaar` silently ignores a level write whose value equals the stored
  one.** Combined with the fact that switching mode to `Manual` resets the
  device's *live* level to 0 while the saved value persists, writing the
  remembered level straight after a mode switch is dropped as a no-op and
  the keyboard stays dark. Hence `planSetLevel` writing via 0 first.
- **"Off" is level 0, not mode `Disabled`.** Keeping the device in `Manual`
  means every toggle is a single write whose value always differs from the
  previous one, so it can never be elided.

`tests/functional.test.js` contains a test that asserts the *failure* of
the naive mode-then-write sequence, precisely so this reasoning stays
executable rather than folkloric.

## Tests

- `tests/unit.test.js` — the parser and the pure state logic.
- `tests/functional.test.js` — runs planned commands against
  `tests/fake-solaar`, which records every invocation and emulates the
  quirks above. This is where command *sequence* is asserted; unit tests
  cannot see it, and every serious bug in this plugin lived there.

**Do not trust a green suite.** Before relying on a test, break the code it
covers and confirm it fails. One test here previously passed with the
parser deliberately broken, because `solaar` prints the saved line before
the live one and the correct value fell out by accident of ordering. It was
only caught by mutation testing.

## Style and scope

- Follow the conventions of Omarchy's first-party plugins in
  `/usr/share/omarchy/shell/plugins/`. Read them before inventing an
  approach; they answer most questions.
- **Nerd Font glyphs, never emoji**, and bind `color` to the theme. CI
  enforces the first half. Verify a codepoint exists before using it:
  `fc-list ':charset=F030C' family`.
- All device access goes through the `solaar` CLI. No direct HID++, no
  `/dev/hidraw*`, no new daemon or systemd unit.
- Scope stays deliberately narrow: this is a bar widget, not a second
  Solaar GUI. Settings it does not expose are reachable by middle-clicking
  the bar icon, which opens Solaar. See [`specs/constitution.md`](specs/constitution.md).

## Pull requests

Describe what you changed and how you verified it on hardware. If you found
a device behaviour that is not obvious from the code, put it in the commit
message — that is the part nobody can reconstruct later.
