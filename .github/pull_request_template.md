## What this changes

<!-- One or two sentences. If it fixes an issue, link it. -->

## How it was verified

Tick what applies. **Hardware verification matters here**: this plugin talks
to a physical keyboard, and every serious bug in it so far was found by
someone looking at the device, not by review.

- [ ] `npm test` passes
- [ ] Tried on a real device — model: <!-- e.g. MX Mechanical Mini, Bolt receiver -->
- [ ] Checked the *device's* state, not just the widget's
      (`solaar show | grep -E "^ +Backlight Level +:"`)
- [ ] No device to hand — please say so, it is fine, and say what you could not check

## Device behaviour

<!-- If you discovered something about how the hardware or solaar behaves,
     write it here AND in a code comment. That knowledge is not recoverable
     from a diff, and it is the most valuable thing in this repository. -->

## Checklist

- [ ] New behaviour is covered by a test where it can be
- [ ] If a test guards a fix, the fix was broken to confirm the test fails
- [ ] No emoji in QML (CI enforces this — Nerd Font glyphs, theme-coloured)
- [ ] Docs updated if behaviour a user sees has changed
