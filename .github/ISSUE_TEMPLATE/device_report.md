---
name: Device report
about: Tell us whether this works on hardware we do not own
labels: device-report
---

Only an MX Mechanical Mini and a Signature M650, both on a Logi Bolt
receiver, have been tested. Everything else is *expected* to work rather
than known to. Reports either way are genuinely useful — especially
negative ones.

## Your device

- Model:
- Connection: <!-- Bolt receiver / Unifying / Bluetooth -->

## What works

- [ ] Battery shows
- [ ] Backlight toggle
- [ ] Brightness slider — how many levels does it offer?
- [ ] Effects row — how many effects, and do the names match what you see?
- [ ] Nothing at all / widget hidden

## Raw output

```
solaar show
```

```
# if the effects row is missing or wrong:
~/.config/omarchy/plugins/alebairos.mx-quick-control/mx-backlight-effect get
```
