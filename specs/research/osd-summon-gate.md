# A third-party bar widget may no longer summon the OSD (2026-09-10)

## Summary

Omarchy `4.0.0.r2095` narrowed the plugin shell API. `bar.shell.summon(
"omarchy.osd", ...)` — the call every OSD in this widget goes through, and
the same call the first-party audio and monitor panels make — now returns
`false` for this plugin and opens nothing.

Nothing about this plugin broke. The keyboard still broadcasts, the Solaar
rules still fire, the IPC call still lands, and the widget's own state still
tracks the device exactly. Only the OSD is gone, and it goes without a log
line, because the denial is a bare `return false`.

Upgraded 14:44, rebooted 14:58, reported broken minutes later. The previous
package, `r1861`, was installed 2026-08-28 and had no such gate.

## The gate

`shell.qml`, in the `_summon` given to a scoped (third-party) plugin:

```javascript
_summon: function(requestedId, payloadJson) {
  if (!shell.pluginOwnsTarget(key, requestedId)
      && !shell.barPluginMayControl(currentManifest(), requestedId)
      && !shell.pluginCloneMaySummon(currentManifest(), requestedId)) return false
  return shell.summon(shell.pluginRegistry.resolveEnabledId(requestedId), payloadJson)
}
```

All three refuse this plugin:

| Gate | Why it refuses |
|---|---|
| `pluginOwnsTarget` | We do not own `omarchy.osd`. |
| `barPluginMayControl` | Calls `pluginHasBarCapabilities`, which is `manifestHasKind(manifest, "bar")`. Our kind is `bar-widget`. **`bar` means a plugin that replaces the bar, not one that sits on it** — so no bar widget can ever satisfy this. |
| `pluginCloneMaySummon` | An allowlist keyed on `omarchy.clonedFrom`: `omarchy.audio`, `omarchy.media` and `omarchy.monitor` may summon `omarchy.osd`; `omarchy.network` may summon the speedtest and wifi-QR panels. We are not a clone of any of them. |

First-party widgets are unaffected for a reason that is easy to miss:
`Bar.qml` hands a registered built-in `root` itself — the real shell, with no
facade — and only wraps third-party widgets in the scoped API.

So the capability is not merely restricted, it is unreachable: there is no
manifest a genuine third-party bar widget can write that satisfies any of
the three. Declaring `clonedFrom: "omarchy.monitor"` would technically open
it, and is a lie to the permission system that would also claim the monitor
clone's other behaviour. Not done.

## How it was established

Not by reading the source first. The chain was bisected from the device up,
and the source was read afterwards to explain what the bisection found.

1. **The keyboard is broadcasting.** A second reader on `/dev/hidraw2`
   caught nine BACKLIGHT2 frames across three keypresses.
2. **Solaar's rules fire and the IPC lands.** The widget moved to
   `level=5 effect=0`, matching the final captured frame exactly.
3. **The widget's own path runs.** Driving `externalEffect 3..6` over IPC
   advanced `status` each time — so `showEffectOsd` was reached.
4. **The OSD never opened.** `omarchy-shell osd state` returned `closed`
   after every one of those calls.
5. **The OSD itself is healthy.** `omarchy-shell shell summon omarchy.osd
   '{"icon":"keyboard","message":"Backlight: Wave"}'` returned `ok` and
   `state: open`.

Step 5 is both the proof and the fix: the CLI reaches `shell.summon`
directly, and the gate lives only in the facade handed to plugins.

## The payload contract did not change

`plugins/osd/OsdModel.js` still reads `icon`, `message`, `value`, `max`,
`progressText` and `duration`, and `Osd.qml:open()` still parses them from
the same JSON. The fallback therefore sends the identical payload the native
call sent — the only difference is which door it goes through.

## Worth reporting upstream

A bar widget having no route to the shared OSD makes third-party widgets
permanently second-class next to the built-ins, which show one for volume,
microphone and display brightness. The plausible intent was to stop plugins
opening each other's *panels*, and the OSD — a transient, payload-only,
system-wide notice — got caught by the same rule. If upstream widens it,
`osdSummonOutcome` starts answering `summoned` again and this fallback goes
quiet on its own, with no code change needed here.
