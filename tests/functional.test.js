// Functional tests: run the planned commands against a fake `solaar` that
// records every invocation and emulates the device's real quirks.
//
// This is the layer that unit tests cannot reach. Every serious defect in
// this plugin was about *which commands were issued, in what order* —
// writes dropped while another call was in flight, and writes elided by
// solaar because the value matched what it had stored. A suite that only
// tested pure functions passed on all of them.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const M = require("../Model.js")

const FAKE = path.join(__dirname, "fake-solaar")

// A disposable device: log of invocations, plus mode/saved/live state that
// the fake mutates the way real hardware does.
function newDevice({ mode = "Manual", saved = 0, live = 0, max = 7, fixture = "solaar-show-keyboard-and-mouse.txt" } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mxqc-"))
  const env = {
    ...process.env,
    FAKE_SOLAAR_LOG: path.join(dir, "log"),
    FAKE_SOLAAR_STATE: path.join(dir, "state"),
    FAKE_SOLAAR_FIXTURE: path.join(__dirname, "fixtures", fixture)
  }
  fs.writeFileSync(env.FAKE_SOLAAR_LOG, "")
  fs.writeFileSync(env.FAKE_SOLAAR_STATE,
    `mode=${mode}\nsaved=${saved}\nlive=${live}\nmax=${max}\n`)

  const read = (key) => {
    const lines = fs.readFileSync(env.FAKE_SOLAAR_STATE, "utf8").trim().split("\n")
    const hit = lines.filter((l) => l.startsWith(key + "=")).pop()
    return hit ? hit.slice(key.length + 1) : ""
  }

  return {
    env,
    // Run a planned argv (its first element is "solaar") against the fake.
    run(argv) {
      try {
        execFileSync(FAKE, argv.slice(1), { env, encoding: "utf8" })
        return 0
      } catch (e) {
        return e.status === undefined ? 1 : e.status
      }
    },
    runPlan(plan) { return plan.map((c) => this.run(c)) },
    invocations() {
      return fs.readFileSync(env.FAKE_SOLAAR_LOG, "utf8").trim().split("\n").filter(Boolean)
    },
    live() { return read("live") },
    mode() { return read("mode") },
    cleanup() { fs.rmSync(dir, { recursive: true, force: true }) }
  }
}

test("turning on from Manual/0 lights the device with one write", (t) => {
  const dev = newDevice({ mode: "Manual", saved: 0, live: 0 })
  t.after(() => dev.cleanup())

  const state = { keyboardIndex: 1, backlightMode: "Manual", backlightLevel: 0, lastOnLevel: 4, defaultOnLevel: 4, levelMax: 7 }
  dev.runPlan(M.planToggle(state))

  assert.deepEqual(dev.invocations(), ["config 1 backlight_level 4"])
  assert.equal(dev.live(), "4", "the device must actually be lit")
})

test("turning on from a non-Manual mode still lights the device", (t) => {
  // The regression that shipped: a mode switch resets LIVE to 0 and solaar
  // then elides the level write because it equals the saved value, so the
  // keyboard stayed dark while everything reported success. The plan must
  // route via 0 so the final write is a genuine change.
  const dev = newDevice({ mode: "Disabled", saved: 3, live: 3 })
  t.after(() => dev.cleanup())

  const state = { keyboardIndex: 1, backlightMode: "Disabled", backlightLevel: 3, lastOnLevel: 3, defaultOnLevel: 4, levelMax: 7 }
  dev.runPlan(M.planToggle(state))

  assert.deepEqual(dev.invocations(), [
    "config 1 backlight Manual",
    "config 1 backlight_level 0",
    "config 1 backlight_level 3"
  ])
  assert.equal(dev.mode(), "Manual")
  assert.equal(dev.live(), "3", "must be lit, not dark at 0")
})

test("a naive mode-then-write plan would leave the device dark", (t) => {
  // Guards the fix itself: if someone 'simplifies' planSetLevel by dropping
  // the via-0 step, this is what happens. Asserting the failure keeps the
  // reason for the extra write visible.
  const dev = newDevice({ mode: "Disabled", saved: 3, live: 3 })
  t.after(() => dev.cleanup())

  dev.run(["solaar", "config", "1", "backlight", "Manual"])
  dev.run(["solaar", "config", "1", "backlight_level", "3"])

  assert.equal(dev.live(), "0", "elided write leaves the keyboard dark")
})

test("turning off writes level 0 and does not touch the mode", (t) => {
  const dev = newDevice({ mode: "Manual", saved: 5, live: 5 })
  t.after(() => dev.cleanup())

  const state = { keyboardIndex: 1, backlightMode: "Manual", backlightLevel: 5, lastOnLevel: 5, defaultOnLevel: 4, levelMax: 7 }
  dev.runPlan(M.planToggle(state))

  assert.deepEqual(dev.invocations(), ["config 1 backlight_level 0"])
  assert.equal(dev.live(), "0")
  assert.equal(dev.mode(), "Manual", "off is a level, not a mode change")
})

test("off then on restores the previous brightness", (t) => {
  const dev = newDevice({ mode: "Manual", saved: 6, live: 6 })
  t.after(() => dev.cleanup())

  let state = { keyboardIndex: 1, backlightMode: "Manual", backlightLevel: 6, lastOnLevel: 6, defaultOnLevel: 4, levelMax: 7 }
  dev.runPlan(M.planToggle(state))          // off
  state = { ...state, backlightLevel: 0 }
  dev.runPlan(M.planToggle(state))          // on again

  assert.equal(dev.live(), "6", "brightness is remembered across an off")
  assert.deepEqual(dev.invocations(), [
    "config 1 backlight_level 0",
    "config 1 backlight_level 6"
  ])
})

test("a level above the device maximum is rejected and teaches the max", (t) => {
  const dev = newDevice({ mode: "Manual", saved: 1, live: 1, max: 3 })
  t.after(() => dev.cleanup())

  // Deliberately bypass clamping to simulate a device whose smaller range
  // is not yet known.
  const code = dev.run(["solaar", "config", "1", "backlight_level", "4"])
  assert.equal(code, 1, "solaar rejects out-of-range levels")
  assert.equal(M.learnLevelMax("backlight_level: value '4' out of bounds", 4), 3)

  // Once learned, the plan clamps and the write succeeds.
  const plan = M.planSetLevel({ keyboardIndex: 1, backlightMode: "Manual", backlightLevel: 1, levelMax: 3 }, 9)
  dev.runPlan(plan)
  assert.equal(dev.live(), "3")
})

test("parses the fake's own `show` output, closing the loop", (t) => {
  const dev = newDevice()
  t.after(() => dev.cleanup())

  const out = execFileSync(FAKE, ["show"], { env: dev.env, encoding: "utf8" })
  const kbd = M.keyboardFrom(M.parseDevices(out))
  assert.equal(kbd.keyboardName, "MX Mechanical Mini")
  assert.equal(kbd.keyboardIndex, 1)
})
