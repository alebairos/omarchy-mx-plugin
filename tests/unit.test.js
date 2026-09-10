// Unit tests for Model.js — the parser and the state logic.
//
// Every case here corresponds to a defect that actually shipped and had to
// be found by hand on real hardware. If any of these regress, the keyboard
// goes dark or a write is silently lost, so they are the ones worth having.
//
// Uses node's built-in test runner: no dependencies, nothing to install.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const M = require("../Model.js")

const fixture = (name) =>
  fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")









// --------------------------------------------------------- state logic

test("Manual at level 0 is OFF, not on", () => {
  // Mode alone is not liveness: this exact confusion is why "on" once left
  // the keyboard dark.
  assert.equal(M.isOn("Manual", 0), false)
  assert.equal(M.isOn("Manual", 1), true)
  assert.equal(M.isOn("Disabled", 5), false)
  assert.equal(M.isOn("Automatic", 5), false)
})

test("clampLevel keeps levels inside the device range", () => {
  assert.equal(M.clampLevel(9, 7), 7)
  assert.equal(M.clampLevel(-3, 7), 0)
  assert.equal(M.clampLevel(4, 7), 4)
  assert.equal(M.clampLevel(9, undefined), 7, "defaults to 7 when max unknown")
  assert.equal(M.clampLevel(9, 3), 3, "honours a learned smaller max")
})

test("toggle turns off to 0 and restores the previous level", () => {
  const on = { backlightMode: "Manual", backlightLevel: 6, lastOnLevel: 6, defaultOnLevel: 4 }
  assert.equal(M.toggleTarget(on), 0)

  const off = { backlightMode: "Manual", backlightLevel: 0, lastOnLevel: 6, defaultOnLevel: 4 }
  assert.equal(M.toggleTarget(off), 6, "restores the remembered level")

  const neverOn = { backlightMode: "Manual", backlightLevel: 0, lastOnLevel: 0, defaultOnLevel: 4 }
  assert.equal(M.toggleTarget(neverOn), 4, "falls back to the default")
})

test("toggling on never targets level 0", () => {
  // A toggle that resolves to 0 would report success and leave the light off.
  const s = { backlightMode: "Manual", backlightLevel: 0, lastOnLevel: 0, defaultOnLevel: 0 }
  assert.ok(M.toggleTarget(s) > 0)
})

// ------------------------------------------------- command planning

test("in Manual mode a level change is a single write", () => {
  const plan = M.planSetLevel(
    { keyboardIndex: 1, backlightMode: "Manual", backlightLevel: 2, levelMax: 7 }, 5)
  assert.deepEqual(plan, [["solaar", "config", "1", "backlight_level", "5"]])
})

test("from a non-Manual mode, the plan sets mode then writes via 0", () => {
  // Both quirks in one: a level write only applies in Manual, and solaar
  // elides a write equal to the saved value — so after the mode switch the
  // target is written via 0 to guarantee a real change reaches the device.
  const plan = M.planSetLevel(
    { keyboardIndex: 1, backlightMode: "Disabled", backlightLevel: 3, levelMax: 7 }, 3)
  assert.deepEqual(plan, [
    ["solaar", "config", "1", "backlight", "Manual"],
    ["solaar", "config", "1", "backlight_level", "0"],
    ["solaar", "config", "1", "backlight_level", "3"]
  ])
})

test("switching mode to reach level 0 needs no via-0 step", () => {
  const plan = M.planSetLevel(
    { keyboardIndex: 1, backlightMode: "Automatic", backlightLevel: 4, levelMax: 7 }, 0)
  assert.deepEqual(plan, [
    ["solaar", "config", "1", "backlight", "Manual"],
    ["solaar", "config", "1", "backlight_level", "0"]
  ])
})

test("planned levels are clamped to the device maximum", () => {
  const plan = M.planSetLevel(
    { keyboardIndex: 1, backlightMode: "Manual", backlightLevel: 1, levelMax: 3 }, 99)
  assert.deepEqual(plan, [["solaar", "config", "1", "backlight_level", "3"]])
})

test("planToggle composes toggle target with the write plan", () => {
  const plan = M.planToggle(
    { keyboardIndex: 2, backlightMode: "Manual", backlightLevel: 5, lastOnLevel: 5, defaultOnLevel: 4, levelMax: 7 })
  assert.deepEqual(plan, [["solaar", "config", "2", "backlight_level", "0"]])
})

test("an out-of-bounds rejection teaches the real maximum", () => {
  assert.equal(M.learnLevelMax("backlight_level: value '8' out of bounds", 8), 7)
  assert.equal(M.learnLevelMax("some other failure", 8), null)
  assert.equal(M.learnLevelMax("", 8), null)
})

// ------------------------------------------------------- backlight effects



test("the off-effect is never offered as an effect", () => {
  // Effect 1 clears the device's enabled flag and forces level 0. The panel
  // has a toggle for that; offering it here let a plain effect change switch
  // the backlight off with no obvious way back.
  assert.deepEqual(M.selectableEffects([0, 1, 2, 3, 4, 5, 6]), [0, 2, 3, 4, 5, 6])
  assert.ok(M.excludedEffects.includes(1))
})

test("cycling skips the excluded effect in both directions", () => {
  const sel = M.selectableEffects([0, 1, 2, 3, 4, 5, 6])
  assert.equal(M.nextEffect(0, sel, 1), 2, "forward from 0 skips 1")
  assert.equal(M.nextEffect(2, sel, -1), 0, "backward from 2 skips 1")
  assert.equal(M.nextEffect(6, sel, 1), 0, "wraps to the start")
  assert.equal(M.nextEffect(0, sel, -1), 6, "wraps to the end")
})

test("effect labels use known names and stay honest otherwise", () => {
  assert.equal(M.effectLabel(0), "Static")
  assert.equal(M.effectLabel(2), "Breathing")
  assert.equal(M.effectLabel(3), "Contrast")
  assert.equal(M.effectLabel(4), "Reaction")
  assert.equal(M.effectLabel(5), "Random")
  assert.equal(M.effectLabel(6), "Wave")
  assert.equal(M.effectLabel(99), "Effect 99", "unmapped values must not be guessed")
  assert.equal(M.effectLabel(-1), "\u2014")
})

test("cycling an empty set is a no-op rather than an error", () => {
  assert.equal(M.nextEffect(3, [], 1), 3)
})

test("the device's level count is read, not assumed", () => {
  // levels=8 means levels 0..7, so the slider maximum is 7. Reading this
  // replaced a hardcoded 7 that was only corrected after a write failed.
  const kbd = M.parseTransportState(fixture("mx-device-keyboard-and-mouse.json"))
    .devices.find((d) => d.hasBacklight)
  assert.equal(kbd.backlightLevels, 8)
  assert.equal(kbd.backlightLevels - 1, 7)

  // A keyboard with a smaller range must not be offered levels it lacks.
  assert.equal(M.clampLevel(7, 4 - 1), 3)
})

test("a keyboard that vanishes from one read is not believed immediately", () => {
  // The device answers contention with a well-formed frame that omits the
  // BACKLIGHT2 block, so a degraded read is indistinguishable from a real
  // disappearance. Believing the first one made the widget announce "no
  // backlight-capable keyboard" while the keyboard was working.
  assert.equal(M.shouldTrustKeyboardLoss(true, 1), false, "one miss is not proof")
  assert.equal(M.shouldTrustKeyboardLoss(true, 2), false)
  assert.equal(M.shouldTrustKeyboardLoss(true, M.missesBeforeBelievingLoss), true)

  // Never having had a keyboard is not a loss -- there is nothing to doubt,
  // and the widget must say so straight away rather than stalling.
  assert.equal(M.shouldTrustKeyboardLoss(false, 1), true)
})

// ------------------------------------- the mx-device transport (feature 004)
//
// These cover the distinction 1.0.0 could not make. Every "degraded" case
// below is one that actually shipped a bug, not one imagined for coverage:
// see specs/004-single-transport/spec.md, "Consequence 1".

const json = (name) => fixture(name)

test("parses a captured mx-device response with a keyboard and a mouse", () => {
  const parsed = M.parseTransportState(json("mx-device-keyboard-and-mouse.json"))
  assert.equal(parsed.ok, true)
  assert.equal(parsed.devices.length, 2)

  const kbd = parsed.devices.find((d) => d.hasBacklight)
  assert.equal(kbd.name, "MX Mechanical Mini")
  assert.equal(kbd.deviceIndex, 1)
  assert.equal(kbd.batteryPercent, 65)
  assert.equal(kbd.backlightMode, "Manual")
  assert.equal(kbd.backlightLevels, 8)
  assert.deepEqual(kbd.supportedEffects, [0, 1, 2, 3, 4, 5, 6])

  const mouse = parsed.devices.find((d) => !d.hasBacklight)
  assert.equal(mouse.batteryPercent, 35)
  assert.equal(mouse.unreadable, false)
})

test("the transport's shape feeds keyboardFrom unchanged", () => {
  // The whole point of matching parseDevices' shape: the UI binding does not
  // learn which transport produced its data.
  const parsed = M.parseTransportState(json("mx-device-keyboard-and-mouse.json"))
  const kbd = M.keyboardFrom(parsed.devices)
  assert.equal(kbd.keyboardIndex, 1)
  assert.equal(kbd.backlightMode, "Manual")
  assert.equal(kbd.keyboardBattery, 65)
})

test("a keyboard whose backlight could not be read is not a keyboard without one", () => {
  // This is the 1.0.0 bug, in one assertion. A contended read that omitted
  // the BACKLIGHT2 block made the widget announce no backlight-capable
  // device while the keyboard was working.
  const parsed = M.parseTransportState(json("mx-device-keyboard-unreadable.json"))
  assert.equal(parsed.ok, true)
  const kbd = parsed.devices[0]
  assert.equal(kbd.hasBacklight, false)
  assert.equal(kbd.unreadable, true)
  assert.equal(M.transportStatus(parsed), "unreadable")
})

test("a genuine mouse-only setup is reported as no keyboard, not as an error", () => {
  const parsed = M.parseTransportState(json("mx-device-mouse-only.json"))
  assert.equal(parsed.ok, true)
  assert.equal(M.transportStatus(parsed), "no-keyboard")
})

test("each transport error keeps its own name", () => {
  assert.equal(M.transportStatus(M.parseTransportState(json("mx-device-no-receiver.json"))), "solaar-missing")
  assert.equal(M.transportStatus(M.parseTransportState(json("mx-device-no-devices.json"))), "no-devices")
  assert.equal(M.transportStatus(M.parseTransportState(json("mx-device-unreadable.json"))), "unreadable")
  assert.equal(M.transportStatus(M.parseTransportState(json("mx-device-rejected.json"))), "unreadable")
})

test("output that is not JSON is a failed read, never an empty device list", () => {
  // The dangerous failure is the quiet one: parsing garbage into zero
  // devices reads as "nothing is paired" and hides the keyboard.
  const parsed = M.parseTransportState(json("mx-device-malformed.json"))
  assert.equal(parsed.ok, false)
  assert.equal(parsed.error, "unreadable")
  assert.equal(M.transportStatus(parsed), "unreadable")
})

test("an empty or absent response does not read as a keyboardless machine", () => {
  for (const input of ["", null, undefined, "null"]) {
    const parsed = M.parseTransportState(input)
    assert.equal(parsed.ok, false, `input ${JSON.stringify(input)} must not parse as ok`)
    assert.equal(M.transportStatus(parsed), "unreadable")
  }
})

test("a degraded frame never yields a zero level count the UI could believe", () => {
  // levels=0 was the effect helper's tell for a contended read. It must not
  // arrive as a plausible "this keyboard has one level" or "has none".
  const parsed = M.parseTransportState(json("mx-device-unreadable.json"))
  assert.equal(parsed.devices.length, 0)
  assert.equal(parsed.ok, false)
})


// ------------------------------------------- device-reported backlight change

test("a moved effect is taken from the notification, not read back", () => {
  // The whole point of the per-effect Solaar rules: the value arrived with
  // the notification, so the 2.7s receiver enumeration is not needed.
  assert.equal(M.externalEffectAction(5, 4, true), "apply")
  assert.equal(M.externalEffectAction(0, 6, true), "apply")
})

test("an unchanged effect means something else moved, so it must be read", () => {
  // The BACKLIGHT2 notification is a full state report, not a delta. Pressing
  // F4/F5 changes the brightness and still reports the old effect, so
  // treating "same effect" as "nothing happened" would swallow every
  // brightness change made on the keyboard itself.
  assert.equal(M.externalEffectAction(4, 4, true), "read")
})

test("an effect reported before any device is known falls back to a read", () => {
  // Nothing to compare against, and showEffectOsd needs a keyboard index.
  assert.equal(M.externalEffectAction(5, 0, false), "read")
})

test("a malformed effect argument never becomes effect NaN", () => {
  // The value crosses a process boundary as a string; parseInt of anything
  // unexpected is NaN, and NaN !== current would otherwise read as "apply"
  // and publish an OSD for an effect that does not exist.
  for (const bad of [NaN, undefined, null, "3", -1]) {
    assert.equal(M.externalEffectAction(bad, 4, true), "read",
      `reported ${JSON.stringify(bad)} must not be applied`)
  }
})

// ------------------------------------------------------- the generated rules

const Rules = require("./solaar-rules.js")

test("solaar-rule.yaml is exactly what the generator produces", () => {
  // 128 near-identical rules whose only content is two numbers repeated in
  // three places each. The file is asserted against its source so a hand
  // edit that tests one value and passes another cannot survive CI.
  const onDisk = fs.readFileSync(path.join(__dirname, "..", "solaar-rule.yaml"), "utf8")
  assert.equal(onDisk, Rules.render(), "run `npm run rules` and commit the result")
})

test("every rule passes exactly the level and effect its own tests matched", () => {
  const rules = Rules.render()
  const triples = [...rules.matchAll(
    /TestBytes: \[1, 2, (\d+), (\d+)\]\n\s*- TestBytes: \[3, 4, (\d+), (\d+)\]\n\s*- Execute: \[[^\]]*externalState, "(\d+):(\d+)"\]/g)]
  assert.equal(triples.length, Rules.LEVELS * Rules.EFFECTS, "one rule per (level, effect) pair")
  for (const [, l0, l1, e0, e1, pl, pe] of triples) {
    assert.equal(l0, l1, `level test must match a single value, got ${l0}-${l1}`)
    assert.equal(e0, e1, `effect test must match a single value, got ${e0}-${e1}`)
    assert.equal(pl, l0, `rule testing level ${l0} passes level ${pl}`)
    assert.equal(pe, e0, `rule testing effect ${e0} passes effect ${pe}`)
  }
  assert.deepEqual(triples.map((m) => [Number(m[1]), Number(m[3])]), Rules.pairs(),
    "every pair exactly once, in generator order")
})

test("the level test reads data[1] and the effect test data[3]", () => {
  // The offsets are the whole contract with Solaar. They were established by
  // evaluating captured frames through logitech_receiver.diversion itself:
  // make_notification hands the engine data[2:], so [08 04 05 00] has the
  // level at 1 and the effect at 3. A rule testing any other byte would
  // still parse, still load, and silently never fire.
  const rules = Rules.render()
  assert.ok(!/TestBytes: \[(?!1, 2,|3, 4,)/.test(rules), "only [1,2] and [3,4] byte ranges may be tested")
})

test("the deviceChanged catch-all is the last rule", () => {
  // Solaar stops at the first rule whose Execute runs (diversion.py,
  // _evaluate), so a catch-all placed earlier would shadow every pair rule
  // and reinstate the slow path for both keys.
  const rules = Rules.render()
  const catchAll = rules.lastIndexOf("deviceChanged]")
  const lastTest = rules.lastIndexOf("TestBytes:")
  assert.ok(catchAll > lastTest, "the deviceChanged fallback must be the last rule")
  assert.equal((rules.match(/deviceChanged\]/g) || []).length, 1, "exactly one catch-all")
})

// ------------------------------------------------ device-reported full state

test("a state literal parses to two integers and nothing else does", () => {
  assert.deepEqual(M.parseExternalState("4:3"), { level: 4, effect: 3 })
  assert.deepEqual(M.parseExternalState("0:0"), { level: 0, effect: 0 })
  assert.deepEqual(M.parseExternalState(" 7:15 "), { level: 7, effect: 15 })
  for (const bad of ["4", "4:", ":3", "4:3:1", "a:b", "-1:3", "", null, undefined, "4,3"]) {
    assert.equal(M.parseExternalState(bad), null, `${JSON.stringify(bad)} must not parse`)
  }
})

test("a moved level is applied and announced without a read", () => {
  // The point of the 128-rule file: brightness from F4/F5 no longer costs
  // the 2s device read that the effect-only rules left it paying.
  assert.deepEqual(M.externalStateAction({ level: 5, effect: 3 }, 4, 3, true),
    { level: "apply", effect: "keep", read: false })
})

test("a moved effect is applied and announced without a read", () => {
  assert.deepEqual(M.externalStateAction({ level: 4, effect: 6 }, 4, 3, true),
    { level: "keep", effect: "apply", read: false })
})

test("both moving applies both, still without a read", () => {
  assert.deepEqual(M.externalStateAction({ level: 1, effect: 0 }, 4, 3, true),
    { level: "apply", effect: "apply", read: false })
})

test("a report where nothing moved is the one case that still reads", () => {
  // Something this rule cannot name changed -- the mode, say. That is
  // exactly the pre-existing behaviour, now confined to the rare case.
  assert.deepEqual(M.externalStateAction({ level: 4, effect: 3 }, 4, 3, true),
    { level: "keep", effect: "keep", read: true })
})

test("a state reported before any device is known falls back to a read", () => {
  assert.deepEqual(M.externalStateAction({ level: 5, effect: 3 }, 0, -1, false),
    { level: "keep", effect: "keep", read: true })
})

test("an unusable state never applies anything", () => {
  // NaN !== current would otherwise read as "apply" and publish an OSD for
  // a level that does not exist.
  for (const bad of [null, undefined, {}, { level: NaN, effect: 3 }, { level: 4, effect: -1 },
                     { level: "4", effect: 3 }, { level: 4 }]) {
    const a = M.externalStateAction(bad, 4, 3, true)
    assert.equal(a.level, "keep", `${JSON.stringify(bad)} must not apply a level`)
    assert.equal(a.effect, "keep", `${JSON.stringify(bad)} must not apply an effect`)
    assert.equal(a.read, true, `${JSON.stringify(bad)} must fall back to a read`)
  }
})
