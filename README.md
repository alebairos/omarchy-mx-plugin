# MX Quick Control

An [Omarchy](https://omarchy.org/) bar widget for Logitech MX peripherals:
battery status at a glance, and your keyboard's backlight controlled from
the bar instead of from [Solaar](https://pwr-Solaar.github.io/Solaar/)'s
window.

> **Status: release candidate** (`1.0.0-rc.3`). It works and is used daily
> on the author's machine, but see [Supported devices](#supported-devices)
> for exactly what has been tested versus what is expected to work, and
> [Known limitations](#known-limitations) for what it does not do yet.

## What it does

- Shows battery percentage for every Logitech device `solaar` reports —
  keyboard, mouse, or anything else it recognises.
- **Click the bar icon** to open a panel with a backlight on/off toggle and
  a brightness slider. The panel stays open, like Omarchy's own Network,
  Bluetooth and Power panels.
- **Middle-click the bar icon** to launch Solaar, for the many settings this
  widget deliberately does not expose.
- **Keyboard navigable**: arrow keys move between the toggle and the slider,
  left/right adjust brightness, <kbd>Enter</kbd> activates,
  <kbd>Esc</kbd> closes, <kbd>Tab</kbd> moves to an adjacent panel.

## Requirements

- **Solaar**, installed and working — `solaar show` should list your
  device(s). On Arch/Omarchy:

  ```bash
  sudo pacman -S solaar
  ```

  The same package provides both the CLI this plugin uses and the GUI that
  middle-click opens; there is no separate `solaar-gui` package.

- A Logitech device paired via a **Logi Bolt or Unifying receiver**.

## Install

```bash
omarchy plugin add https://github.com/alebairos/omarchy-mx-plugin.git --enable
```

That clones, validates, installs and enables the plugin, and offers to place
it in the bar (it asks for a section; the manifest suggests `right`).

To place or move it afterwards:

```bash
omarchy bar put alebairos.mx-quick-control --section right   # add it
omarchy bar move alebairos.mx-quick-control --section left   # move it
```

`put` adds a widget that is not on the bar yet; `move` only repositions one
that already is, and fails with "could not find widget" otherwise.

### Updating

```bash
omarchy plugin update alebairos.mx-quick-control
```

### Removing

```bash
omarchy plugin remove alebairos.mx-quick-control
```

**Note:** removing the plugin also drops its entry from your bar layout. If
you later reinstall it, it will not reappear on the bar until you enable it
again:

```bash
omarchy plugin enable alebairos.mx-quick-control --section right
```

## Supported devices

The plugin is capability-driven, not model-locked: any device `solaar`
reports with a `BACKLIGHT2` feature gets backlight controls, and any device
reporting a battery gets a battery readout. No model allow-list.

**Verified on real hardware:**

| Device | Connection | What was tested |
|---|---|---|
| MX Mechanical Mini | Logi Bolt receiver | battery, backlight on/off, brightness levels 0–7 |
| Signature M650 mouse | Logi Bolt receiver | battery readout |

**Expected to work but not tested** — because the author does not own the
hardware. Reports welcome:

- Other backlit Logitech keyboards (MX Mechanical full-size, MX Keys, …).
  Backlight control should work; the brightness slider assumes a maximum
  level of **7** until the device rejects a higher value and the real
  maximum is learned, so a device with a different range may briefly show a
  wrong maximum.
- **Bluetooth-paired** Logitech devices. `solaar show` output has only been
  parsed against Bolt-receiver output; a Bluetooth device may format its
  block differently.
- Setups with **more than one backlit keyboard**. Only the first
  backlight-capable device is controlled; the rest show battery only.

## Known limitations

- **Roughly 2–3 seconds per action.** Each `solaar` invocation costs about
  2.3s on the reference hardware, and the plugin shells out rather than
  linking against the library, so a toggle or a brightness change takes
  about that long to reach the keyboard. The UI updates immediately.
- **Changes made elsewhere take up to 5 minutes to appear.** If you adjust
  the backlight in the Solaar window or with the keyboard's own Fn keys, the
  widget catches up on its next refresh. A targeted refresh when the panel
  opens is planned.
- **If Solaar is not installed, the widget hides itself** rather than
  explaining why. That is deliberate (it must never break the bar) but
  unhelpful; an explicit message is planned.
- Exposes backlight and battery only. Everything else Solaar can do —
  `fn-swap`, host switching, key remapping, mouse DPI — is one middle-click
  away in Solaar itself, by design. See
  [`specs/constitution.md`](specs/constitution.md).

## How it works

The plugin never talks to hardware directly. Every interaction goes through
the `solaar` CLI (`solaar show`, `solaar config … backlight`, `solaar config
… backlight_level`). The exact commands and the output it depends on are
documented in
[`specs/001-mx-quick-control/contracts/solaar-cli.md`](specs/001-mx-quick-control/contracts/solaar-cli.md).

Two device behaviours are worth knowing if you read the code, because they
look like bugs and are not:

- A backlight level write only takes effect while the mode is `Manual`.
- Solaar ignores a level write whose value equals the one it has stored, and
  switching mode to `Manual` resets the device's *live* level to 0 while the
  stored value persists. "Off" is therefore level 0 rather than mode
  `Disabled`, so every toggle is a write that genuinely changes something.

## Development

```bash
npm test        # 25 unit + functional tests, no dependencies to install
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for how to test a change against
real hardware, and [`AGENTS.md`](AGENTS.md) if you are working with an AI
agent on this repository.

Design decisions and their reasoning live in
[`specs/`](specs/): the [constitution](specs/constitution.md),
the [original feature spec](specs/001-mx-quick-control/), and the
[release-candidate plan](specs/002-public-release-rc/).

## License

MIT — see [LICENSE](LICENSE).
