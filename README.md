# MX Quick Control

An [Omarchy](https://omarchy.org/) bar widget that shows battery status for
paired Logitech MX peripherals and lets you toggle/step your keyboard's
backlight directly from the bar — no need to open
[Solaar](https://pwr-Solaar.github.io/Solaar/)'s own window for everyday use.

Built with [spec-kit](https://github.com/github/spec-kit); the full spec,
plan, and task breakdown live in [`specs/001-mx-quick-control/`](specs/001-mx-quick-control/).

## What it does

- Shows battery percentage for every Logitech device `solaar` sees (keyboard,
  mouse, etc.)
- **Click** the widget to toggle your keyboard's backlight on/off
- **Scroll** over the widget to step brightness up/down
- Hides itself cleanly if `solaar` isn't installed or no supported device is
  paired — never errors or blocks the rest of the bar

## Requirements

- [Solaar](https://pwr-Solaar.github.io/Solaar/) installed and working:
  `solaar show` should list your device(s). On Arch/Omarchy:
  ```bash
  sudo pacman -S solaar
  ```
- A Logitech keyboard/mouse paired via a Logi Bolt or Unifying receiver.
  Backlight control requires a keyboard with Solaar's `BACKLIGHT2` feature
  (e.g. MX Mechanical / MX Mechanical Mini / MX Keys); other devices still
  show battery-only status.

## Install

```bash
git clone https://github.com/alebairos/omarchy-mx-plugin.git
cp -r omarchy-mx-plugin/plugin ~/.config/omarchy/plugins/mx-quick-control
omarchy-shell shell rescanPlugins
omarchy bar move omarchy.mx-quick-control --section right
```

## How it works

This plugin does not talk to hardware directly — every device interaction
goes through the `solaar` CLI (`solaar show`, `solaar config ... backlight`,
`solaar config ... backlight_level`). See
[`specs/001-mx-quick-control/contracts/solaar-cli.md`](specs/001-mx-quick-control/contracts/solaar-cli.md)
for the exact commands and output this plugin depends on.

## Design principles

See [`.specify/memory/constitution.md`](.specify/memory/constitution.md) for
the project's governing principles — in short: shell out to `solaar` rather
than reimplementing HID++, keep the plugin to the standard Omarchy
`bar-widget` shape, and stay as simple as the use case actually requires.

## License

MIT — see [LICENSE](LICENSE).
