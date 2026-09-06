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

// ------------------------------------------------------------- parsing

test("parses a real solaar show with a keyboard and a mouse", () => {
  const devices = M.parseDevices(fixture("solaar-show-keyboard-and-mouse.txt"))
  assert.equal(devices.length, 2)

  const kbd = devices.find((d) => d.hasBacklight)
  assert.ok(kbd, "keyboard with BACKLIGHT2 should be found")
  assert.equal(kbd.deviceIndex, 1)
  assert.equal(kbd.name, "MX Mechanical Mini")
  assert.equal(kbd.batteryPercent, 100)

  const mouse = devices.find((d) => !d.hasBacklight)
  assert.equal(mouse.name, "Signature M650")
  assert.equal(mouse.hasBacklight, false)
})

test("reads the LIVE backlight level, never the (saved) one", () => {
  // The bug this guards: solaar prints both, they disagree, and the saved
  // value is not what the hardware is doing. Reading "3" here would mean
  // reporting a lit keyboard that is physically dark.
  const devices = M.parseDevices(fixture("solaar-show-saved-differs-from-live.txt"))
  const kbd = M.keyboardFrom(devices)
  assert.equal(kbd.backlightLevel, 0, "must take the live level, not saved 3")
  assert.equal(kbd.backlightMode, "Manual")
})

test("a (saved) line alone is ignored — it is not a live reading", () => {
  // The case above passes even with a sloppy regex, because the live line
  // follows the saved one and simply overwrites it. This fixture has ONLY
  // the "(saved)" lines, so a parser that matches them reports a level and
  // mode that the hardware never confirmed. Found by mutation-testing the
  // suite: the previous test alone did not pin this.
  const devices = M.parseDevices(fixture("solaar-show-saved-only.txt"))
  assert.equal(devices.length, 1)
  assert.equal(devices[0].backlightLevel, null, "must not adopt the saved level")
  assert.equal(devices[0].backlightMode, null, "must not adopt the saved mode")

  // And the flattened view degrades safely rather than inventing a value.
  const kbd = M.keyboardFrom(devices)
  assert.equal(kbd.backlightLevel, 0)
  assert.equal(M.isOn(kbd.backlightMode, kbd.backlightLevel), false)
})

test("a mouse-only setup yields no keyboard but keeps the device", () => {
  const devices = M.parseDevices(fixture("solaar-show-mouse-only.txt"))
  assert.equal(devices.length, 1)
  assert.equal(M.keyboardFrom(devices).keyboardIndex, -1)
  assert.equal(M.otherDevices(devices).length, 1)
})

test("a device without a battery reports -1 rather than crashing", () => {
  const devices = M.parseDevices(fixture("solaar-show-no-battery.txt"))
  const kbd = M.keyboardFrom(devices)
  assert.equal(kbd.keyboardBattery, -1)
  assert.equal(kbd.backlightLevel, 5)
})

test("no paired devices parses to an empty list", () => {
  assert.deepEqual(M.parseDevices(fixture("solaar-show-no-devices.txt")), [])
  assert.equal(M.keyboardFrom([]).keyboardIndex, -1)
})

test("malformed output degrades to no devices instead of throwing", () => {
  assert.doesNotThrow(() => M.parseDevices(fixture("solaar-show-malformed.txt")))
  assert.equal(M.parseDevices(fixture("solaar-show-malformed.txt")).length, 0)
  assert.equal(M.parseDevices("").length, 0)
  assert.equal(M.parseDevices(null).length, 0)
})

test("parses a targeted config read", () => {
  const r = M.parseConfigRead("backlight = Manual\nbacklight_level = 6\n")
  assert.equal(r.mode, "Manual")
  assert.equal(r.level, 6)
})

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

test("parses the effect helper's state line", () => {
  const st = M.parseEffectState("levels=8 level=3 effect=6 supported=0,1,2,3,4,5,6")
  assert.equal(st.levels, 8)
  assert.equal(st.level, 3)
  assert.equal(st.effect, 6)
  assert.deepEqual(st.supported, [0, 1, 2, 3, 4, 5, 6])
})

test("a degraded effect read yields no effects rather than a false one", () => {
  // The device answers with zeros under contention. The helper retries, but
  // if a bad line ever reaches here it must not look like a real state.
  const st = M.parseEffectState("levels=0 level=0 effect=0 supported=none")
  assert.deepEqual(st.supported, [])
  assert.equal(M.selectableEffects(st.supported).length, 0)
  assert.equal(M.parseEffectState("").effect, -1)
  assert.equal(M.parseEffectState(null).supported.length, 0)
})

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
  const st = M.parseEffectState("levels=8 level=3 effect=0 supported=0,2,3")
  assert.equal(st.levels, 8)
  assert.equal(st.levels - 1, 7)

  // A keyboard with a smaller range must not be offered levels it lacks.
  const small = M.parseEffectState("levels=4 level=1 effect=0 supported=0")
  assert.equal(small.levels - 1, 3)
  assert.equal(M.clampLevel(7, small.levels - 1), 3)
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
