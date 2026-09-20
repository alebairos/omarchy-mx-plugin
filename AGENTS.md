# Guidance for agents

## What this is

An [Omarchy](https://omarchy.org/) **bar widget**: battery status and
backlight control for Logitech MX peripherals, driven through
[Solaar](https://pwr-Solaar.github.io/Solaar/)'s own `logitech_receiver`
library rather than raw HID++. Plugin id
`alebairos.mx-quick-control`, declared in `manifest.json`.

Four files are the product. `MxQuickControl.qml` is the widget and its
panel, `Model.js` is the parsing and state logic shared with the tests,
`mx-device` is the one Python transport that talks to the device, and
`solaar-rule.yaml` is an optional Solaar rule users install by hand.

Read [`README.md`](README.md) first — what it does, what it requires, what
it deliberately does not do, and the two device behaviours that look like
bugs and are not. Then [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing
anything: it carries the hardware rules that matter.

[`CONSTITUTION.md`](CONSTITUTION.md) is five principles, and it governs
what you may propose. Three are hard limits: device access only through
Solaar's own code, never raw HID++ and never `/dev/hidraw`; no new daemon,
systemd unit or background service; no build step or packaging format of
its own. Two are obligations rather than limits: behave like a built-in
Omarchy plugin, and degrade gracefully — never crash the shell or spam
errors when Solaar is missing or no device is paired.

Features like macros, per-key RGB or gesture config are **deferred, not
banned**. The rule is that they wait for a real, validated need, so the way
to propose one is with evidence that the need exists, not to assume the
answer is no. Amendments have their own procedure, in the file.

## Install it

```bash
omarchy plugin add https://github.com/alebairos/omarchy-mx-plugin.git --enable
```

Requires Solaar and a paired MX device. Removal, placement and settings are
in [`README.md`](README.md).

## Test it

```bash
npm test                 # node only, no device, no setup
npm run test:shell       # real widget in a throwaway quickshell
npm run test:acceptance  # live session and real hardware
```

`npm test` is what CI runs and what you should run. The other two skip
themselves, saying why, wherever they cannot run.

## Three rules that are not negotiable

1. **The hardware is the source of truth, not the widget.** Its `status`
   output is optimistic by design and will report a lit keyboard that is
   dark. Confirm against the device:
   `solaar show | grep -E "^ +Backlight Level +:"`. This is the most
   expensive mistake available here.

2. **Polling the device during diagnosis is not read-only.** Repeated
   `solaar show` or `mx-device state` calls make Solaar lose the keyboard's
   feature table, after which no rule fires, silently, with a clean journal.
   Prefer instruments that cost the device nothing. After any burst of
   polling, restart Solaar before concluding anything:
   `systemctl --user restart app-solaar@autostart.service`.

3. **Do not trust a green suite.** Before claiming a test protects
   something, break the code and watch it fail. A test here once passed
   with the parser deliberately broken, for the wrong reason, and would
   have slept through a real regression.

## Where the reasoning lives

Specs, planning and research are in a separate private repository,
`omarchy-mx-plugin-host`. Installing this plugin clones this repository in
full onto a user's machine, so this one holds the plugin, its tests, and
the documentation a user or contributor reads. Nothing else.

Commit messages here are load-bearing. They record why a write is sent
twice, why "off" is a level rather than a mode, why a redundant-looking
step exists. Squash merging is disabled so each survives on its own. If you
learn something about the device or Solaar, put it in the commit message
**and** in a code comment.
