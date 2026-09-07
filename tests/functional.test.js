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

// ------------------------------ the mx-device transport (feature 004)
//
// The claim under test is feature 004's central one: a user-visible action
// issues exactly ONE call to the device. 1.0.0 issued six across three
// mechanisms, and every extra invocation was another window in which the
// device could answer with plausible, wrong data.

const FAKE_MXD = path.join(__dirname, "fake-mx-device")

function newTransport({ mode = "Manual", level = 0, degrade = "", reject = false,
                        fixture = "mx-device-keyboard-and-mouse.json" } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mxd-"))
  const env = {
    ...process.env,
    FAKE_MXD_LOG: path.join(dir, "log"),
    FAKE_MXD_STATE: path.join(dir, "state"),
    FAKE_MXD_FIXTURE: path.join(__dirname, "fixtures", fixture),
    FAKE_MXD_DEGRADE: degrade,
    FAKE_MXD_REJECT: reject ? "1" : ""
  }
  fs.writeFileSync(env.FAKE_MXD_LOG, "")
  fs.writeFileSync(env.FAKE_MXD_STATE, `mode=${mode}\nlevel=${level}\n`)

  const run = (...args) =>
    execFileSync(FAKE_MXD, args, { env, encoding: "utf8" })
  const calls = () =>
    fs.readFileSync(env.FAKE_MXD_LOG, "utf8").trim().split("\n").filter(Boolean)
  return { run, calls }
}

test("reading everything the panel needs is one invocation", () => {
  // 1.0.0 needed three: `solaar config backlight`, `solaar config
  // backlight_level`, and the effect helper. Each paid its own setup cost
  // and opened its own contention window.
  const t = newTransport()
  const parsed = M.parseTransportState(t.run("state"))

  assert.equal(t.calls().length, 1)
  assert.equal(M.transportStatus(parsed), "ok")

  const kbd = parsed.devices.find((d) => d.hasBacklight)
  assert.equal(kbd.backlightLevels, 8)
  assert.deepEqual(kbd.supportedEffects, [0, 1, 2, 3, 4, 5, 6])
  assert.equal(parsed.devices.find((d) => !d.hasBacklight).batteryPercent, 35)
})

test("a write is one invocation and is not followed by a confirming read", () => {
  const t = newTransport({ level: 0 })
  t.run("set", "--device", "1", "--level", "5")

  assert.deepEqual(t.calls(), ["set --device 1 --level 5"])
})

test("a write takes effect, so the next read needs no correction", () => {
  const t = newTransport({ level: 0 })
  t.run("set", "--device", "1", "--level", "5")
  const kbd = M.parseTransportState(t.run("state")).devices.find((d) => d.hasBacklight)
  assert.equal(kbd.backlightLevel, 5)
})

test("a degraded frame reaches the UI as 'could not read', never as a loss", () => {
  // The 1.0.0 bug, at the functional layer: the keyboard is present and its
  // backlight read failed. The widget must not conclude there is no
  // backlight-capable device.
  const t = newTransport({ degrade: "unreadable" })
  const parsed = M.parseTransportState(t.run("state"))

  assert.equal(M.transportStatus(parsed), "unreadable")
  assert.notEqual(M.transportStatus(parsed), "no-keyboard")
  assert.equal(parsed.devices[0].unreadable, true)
})

test("transport failures keep their names through a real invocation", () => {
  for (const [degrade, expected] of [
    ["no-receiver", "solaar-missing"],
    ["no-devices", "no-devices"],
    ["garbage", "unreadable"]
  ]) {
    const t = newTransport({ degrade })
    assert.equal(M.transportStatus(M.parseTransportState(t.run("state"))), expected,
      `degrade=${degrade}`)
  }
})

test("a rejected write is reported as rejected, not as a read failure", () => {
  const t = newTransport({ reject: true })
  const parsed = M.parseTransportState(t.run("set", "--device", "1", "--level", "5"))
  assert.equal(parsed.ok, false)
  assert.equal(parsed.error, "rejected")
})

// -------------------- the transport itself, against a stub HID++ library
//
// mx-device is Python and talks to hardware, so it would otherwise be the
// one part of this plugin with no automated coverage — which is exactly
// backwards, since it is now the only thing that touches the device. The
// stub in tests/stub-hidpp stands in for Solaar's logitech_receiver and is
// driven by env vars, so every failure the real device produces only
// intermittently can be produced here on demand.

const TRANSPORT = path.join(__dirname, "..", "mx-device")
const STUB = path.join(__dirname, "stub-hidpp")

function runTransport(args, extraEnv = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mxdstub-"))
  const log = path.join(dir, "log")
  const out = execFileSync(TRANSPORT, args, {
    env: { ...process.env, PYTHONPATH: STUB, MXD_STUB_LOG: log, ...extraEnv },
    encoding: "utf8"
  })
  const events = fs.existsSync(log)
    ? fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse)
    : []
  return { json: JSON.parse(out), events }
}

test("the transport never pays the one-second node probe", () => {
  // Solaar's Device constructor hardcodes a 1s budget on a udev busy-wait
  // that cannot succeed for receiver-paired devices — measured at 1001ms
  // per device, returning None, and it was two thirds of every invocation.
  // A refactor that drops the shim would restore that cost with no visible
  // symptom, so the budget is asserted rather than trusted.
  const { events } = runTransport(["state"])
  const probes = events.filter((e) => e.event === "find_paired_node")

  assert.ok(probes.length > 0, "expected the transport to probe for device nodes")
  for (const p of probes) {
    assert.ok(p.timeout < 1,
      `node probe budget ${p.timeout}s would cost ~1s per device`)
    assert.ok(p.timeout > 0,
      "a zero budget skips the udev scan entirely and would never find a real node")
  }
})

test("the transport issues no explicit ping", () => {
  const { events } = runTransport(["state"])
  assert.equal(events.filter((e) => e.event === "ping").length, 0)
})

test("one invocation returns every device and every backlight field", () => {
  const { json } = runTransport(["state"])
  assert.equal(json.ok, true)
  assert.equal(json.devices.length, 2)
  const kbd = json.devices.find((d) => d.backlight)
  assert.equal(kbd.backlight.levels, 8)
  assert.deepEqual(kbd.backlight.effects, [0, 1, 2, 3, 4, 5, 6])
  assert.equal(json.devices.find((d) => !d.backlight).battery, 35)
})

test("degraded frames are retried and never reach the caller", () => {
  // Two contended reads, then a good one. The caller must see only the
  // good one — not a keyboard with zero levels and no effects.
  const { json } = runTransport(["state"], { MXD_STUB_DEGRADED_READS: "2" })
  const kbd = json.devices.find((d) => d.backlight)
  assert.equal(kbd.backlight.levels, 8)
  assert.notEqual(kbd.backlight.levels, 0)
  assert.ok(kbd.backlight.effects.length > 0)
})

test("an exhausted retry budget reports the device present but unreadable", () => {
  // The 1.0.0 bug in its original form: this must NOT come back as "there
  // is no backlight-capable keyboard".
  const { json } = runTransport(["state"], { MXD_STUB_DEGRADED_READS: "99" })
  const kbd = json.devices.find((d) => d.index === 1)
  assert.equal(kbd.unreadable, true)
  assert.equal(kbd.backlight, null)

  const parsed = M.parseTransportState(JSON.stringify(json))
  assert.equal(M.transportStatus(parsed), "unreadable")
})

test("no receiver and no paired devices are different answers", () => {
  assert.equal(runTransport(["state"], { MXD_STUB_NO_RECEIVER: "1" }).json.error, "no-receiver")
  assert.equal(runTransport(["state"], { MXD_STUB_NO_DEVICES: "1" }).json.error, "no-devices")
})

test("a write the device refuses is reported as rejected", () => {
  const { json } = runTransport(["set", "--device", "1", "--effect", "3"],
    { MXD_STUB_REJECT: "1" })
  assert.equal(json.ok, false)
  assert.equal(json.error, "rejected")
})
