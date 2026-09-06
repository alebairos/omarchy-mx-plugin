# MX Quick Control

An [Omarchy](https://omarchy.org/) bar widget for Logitech MX peripherals:
battery status at a glance, and your keyboard's backlight controlled from
the bar instead of from [Solaar](https://pwr-Solaar.github.io/Solaar/)'s
window.

> **Status: 1.0.0.** Used daily on the author's machine. See
> [Supported devices](#supported-devices) for exactly what has been tested
> versus what is expected to work — only two devices have ever been tried —
> and [Known limitations](#known-limitations) for what it does not do.

## What it does

- Shows battery percentage for every Logitech device `solaar` reports —
  keyboard, mouse, or anything else it recognises.
- **Click the bar icon** to open a panel with a backlight on/off toggle, a
  brightness slider, and a lighting-effect selector. The panel stays open,
  like Omarchy's own Network, Bluetooth and Power panels.
- **Switch lighting effects** — Static, Breathing, Contrast, Reaction,
  Random and Wave — from the panel. Solaar's CLI cannot do this; the plugin
  reaches it through Solaar's own library, and the effect list comes from
  what your device actually reports rather than a hardcoded table.
- **Middle-click the bar icon** to launch Solaar, for the many settings this
  widget deliberately does not expose.
- **Fully keyboard operable** — see [Keyboard control](#keyboard-control).


## Keyboard control

The panel takes part in Omarchy's normal panel hotkeys, exactly like the
built-in ones — nothing extra to configure.

| Key | Action |
|---|---|
| <kbd>Super</kbd>+<kbd>Ctrl</kbd>+<kbd>1</kbd>…<kbd>9</kbd> | Open the *n*th panel in the bar's right section |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move between the toggle, the brightness slider and the effect row |
| <kbd>←</kbd> <kbd>→</kbd> | Adjust brightness, or change effect, depending on the row |
| <kbd>Enter</kbd> | Toggle the backlight, or cycle the effect when the cursor is on that row |
| <kbd>Esc</kbd> | Close the panel |
| <kbd>Tab</kbd> / <kbd>Shift</kbd>+<kbd>Tab</kbd> | Move to the next/previous panel |

Your keyboard's own backlight keys (**F4** and **F5** on the MX Mechanical
Mini, pressed without Fn) keep working exactly as they always did — they are
handled by the keyboard's firmware, not by this widget. The widget is not
told about those presses as they happen, so it picks the new level up the
next time you open the panel. No on-screen display appears for them, unlike
changes made from the panel itself.

**The summon number is positional, not fixed to this plugin.** It counts
visible panels in the bar's right section from the left, skipping widgets
that have no panel of their own. Rearranging your bar changes the number.
To find the current one:

```bash
omarchy-shell shell togglePanelAt right 1   # prints the id it acted on
```

On the author's bar this widget is panel 1, so
<kbd>Super</kbd>+<kbd>Ctrl</kbd>+<kbd>1</kbd> opens it.

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

## Settings

Optional, and set the same way as any other Omarchy widget — add keys to
this widget's entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "alebairos.mx-quick-control",
  "defaultOnLevel": 4,
  "refreshMinutes": 5,
  "showBattery": true }
```

| key | default | what it does |
|---|---|---|
| `defaultOnLevel` | `4` | Brightness used when switching on from fully off, before any level has been remembered. Clamped to 1–7. |
| `refreshMinutes` | `5` | How often to re-enumerate devices. This is the expensive `solaar show` (~10s), needed only for discovery and battery, so the minimum is 1. |
| `showBattery` | `true` | Set to `false` to hide battery percentages entirely. |

All three are optional; omit them and the defaults apply.

## Known limitations

- **Roughly 2–3 seconds per action.** Each `solaar` invocation costs about
  2.3s on the reference hardware, and the plugin shells out rather than
  linking against the library, so a toggle or a brightness change takes
  about that long to reach the keyboard. The panel updates immediately; the
  keyboard follows.
- **The panel does not follow the keyboard's own keys, unless you opt in.**
  It re-reads the device when you open it, so what you see on opening is
  always current. But changing brightness with F4/F5, or the effect with the
  lamp key, will not move the panel while it is already open.

  The device *does* announce those changes over HID++; hearing them needs a
  process listening continuously, which this plugin deliberately is not. If
  you already run Solaar, [`solaar-rule.yaml`](solaar-rule.yaml) delegates
  the listening to it: append it to `~/.config/solaar/rules.yaml`, restart
  Solaar, and the panel follows the hardware keys and shows an on-screen
  display for them. Nothing breaks without it.
- **Effects are only exposed for keyboards that report them.** The list
  comes from the device's own capability bitmap, so a keyboard that
  advertises no effects simply gets no effect row.
- **The brightness slider assumes eight levels until told otherwise.** The
  device reports its real number of levels, but the maximum used for
  clamping is only corrected once a write is rejected as out of range. On a
  keyboard with fewer levels the slider may briefly offer one too many.

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

## More

Notes from building this, and from running Omarchy generally, are at
[omarchy.alebairos.xyz](https://omarchy.alebairos.xyz/) — including the
write-ups of the bugs behind several of the odder-looking decisions in this
code.

## License

MIT — see [LICENSE](LICENSE).
