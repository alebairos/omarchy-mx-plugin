# What a device costs to read, and why filtering them did not help

**Status:** measured, change rejected. 2026-09-09.

## The idea

`mx-device state` describes every paired device. A backlight notification is
about the keyboard, so the mouse is read for nothing on that path. Adding
`state --device N` looked like a free ~1s.

## What it actually costs

The cost is not the feature walk. It is waking a sleeping wireless device on
first attribute access. Per device, on the reference hardware:

| | keyboard | mouse |
|---|---|---|
| `.name` (first access, pays the lazy ping) | 0.739s | 0.984s |
| `.battery()` | 0.107s | 0.099s |
| `BACKLIGHT2 in device.features` | 0.013s | 0.013s |

So the feature lookup everyone assumes is expensive is 13ms. A device that
is asleep is worth about a second; a device that is awake is worth almost
nothing, and there is no way to make a device you actually need cheaper.

## Why the change was rejected

Measured sequentially, the filter looked like a clear win: 2.859s full
against 2.001s filtered. Interleaved -- which is what this project's own
`AGENTS.md` requires, after getting this wrong once already -- it vanishes:

```
full 2.796   filtered 1.783     first pair; the mouse was asleep
full 1.899   filtered 1.851     the first read woke it
full 1.832   filtered 1.925     filtered is now slower than full
```

The apparent saving was the mouse waking on the first read and staying
awake. The benefit is real but conditional on the mouse being asleep, which
it usually is not while someone is at the machine.

Against that, wiring it in was not free. A filtered read returns one device,
so `applyTransportState` could no longer replace the device list -- it would
need to merge, or the panel would silently lose every other device's
battery. That is a new branch in the exact code path that produced this
project's worst bug (announcing no backlight-capable keyboard while the
keyboard worked).

Conditional benefit, structural risk, in the most bug-prone code here. The
constitution's tie-breaker is explicit: when in doubt, the smaller
implementation wins.

## What would actually make the hardware keys instant

Both of them, not just the effect key -- and it is knowable, just not cheap.
The notification carries level at `data[1]` and effect at `data[3]`, but
Solaar's `Execute` passes fixed literals, and the rule list short-circuits so
exactly one rule fires. Conveying both values therefore needs one rule per
*combination*: 8 levels x 16 effects = 128 rules, against the 16 that make
the effect key instant today.

That is why brightness still falls back to a read. It is not an oversight;
it is 128 generated rules' worth of ruleset to make the second key as fast as
the first, and nobody has asked for it.
