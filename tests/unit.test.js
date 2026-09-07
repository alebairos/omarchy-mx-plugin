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
