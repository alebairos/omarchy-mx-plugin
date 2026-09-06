# Backlight effects are visible over HID++ (2026-09-05)

## Summary

The six firmware backlight effects on the MX Mechanical Mini — Static,
Contrast, Breathing, Wave, Reaction, Random — **are** announced to the host.
An earlier conclusion in this project said they were firmware-local and
invisible. That was wrong, and it was wrong for a specific, instructive
reason: it rested entirely on diffing `solaar show` output, which is a
*poll* of settings Solaar knows about. The device announces the change in a
HID++ *notification*, which nothing was listening to.

## What was captured

Raw reads from `/dev/hidraw2` (the Bolt receiver) while cycling the effects
by hand with the effect key, then pressing the backlight keys:

```
11 01 0b 00 08 03 05 03      byte 2 = 0x0b = feature index of BACKLIGHT2
                ^^    ^^     byte 5 = backlight LEVEL
              level  effect  byte 7 = EFFECT index
```

Cycling the effect key, with the level untouched — byte 5 pinned at `03`,
byte 7 walking a clean repeating cycle of six distinct values:

```
… 08 03 05 03      … 08 03 05 02      … 08 03 05 06
… 08 03 05 04      … 08 03 05 05      … 08 03 05 00      (then repeats)
```

Pressing the backlight keys, with the effect untouched — the mirror image:
byte 7 pinned at `06`, byte 5 moving `03 → 02 → 01 → 02 → 03 → 04`.

The two fields move independently, which is what identifies them.

## Observed effect values

`00, 02, 03, 04, 05, 06` — six distinct values for six effects. `01` never
appeared in this capture; it may be unused, reserved, or simply not reached.
The mapping of value to named effect has **not** been established: that
needs someone to watch the keyboard and the capture at the same time.

## Why the earlier conclusion was wrong

`solaar show` reports the settings Solaar models. Solaar's own capability
probe recorded every effect-ish setting as absent for this device
(`rgb_control`, `per-key-lighting`, `rgb_idle_effect`, …), and only exposes
`BACKLIGHT2` as mode + level + three fade delays. All of that is true and
none of it means the *device* is silent — it means Solaar does not surface
this field. Polling what a library models is not the same as watching what
the hardware says.

## What this makes possible, and what it does not

Possible: reading the current effect, and reacting to changes made with the
keyboard's own key, since the device volunteers the value.

Unknown: whether the effect can be **set** from the host. That needs the
HID++ 2.0 `0x1982` specification and a look at whether the feature exposes a
setter alongside the getter. Reading a notification proves the device talks,
not that it listens.

Also unresolved: the same frames carry bytes this project has not decoded
(`08` at byte 4, `05` at byte 6, and a trailing group seen during Solaar's
enumeration: `11 01 0b 2b 08 03 05 00 03 00 06 00 3c 00`). The `0x1982`
`getBacklightConfig` response is documented as carrying a supported-effects
bitmap; decoding it against the spec would confirm the field layout instead
of inferring it from movement, which is all this capture does.

## The constitutional question

Reading `/dev/hidraw2` directly is exactly what constitution Principle II
forbids: it reimplements HID++, and it contends with Solaar for the device.
This capture was a **diagnostic**, not a design.

The legitimate path stays what it was: Solaar (or `python-logitech-receiver`)
gains a `backlight_effect` setting, and this plugin exposes it in one more
panel row through the same CLI it already uses. The difference is that this
is now a concrete, evidenced upstream feature request — "the device
broadcasts the effect index in BACKLIGHT2 notifications, here is the
capture" — rather than a guess about whether the hardware supports it.

## Method note

Two earlier attempts produced nothing and were nearly recorded as negative
results. They failed for two avoidable reasons:

1. **No control.** With nothing known-noisy in the window, "no output" was
   indistinguishable from "nothing pressed". Adding the backlight keys as a
   control fixed that.
2. **Self-inflicted noise.** An entire capture was drowned in Solaar
   enumeration traffic caused by *this plugin's own* 300s `solaar show`
   timer. The clean capture required disabling the widget first.

Both are worth remembering before trusting any future negative result here.
