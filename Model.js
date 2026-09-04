// Pure logic for MX Quick Control, kept out of the QML so it can be tested
// without a running shell. Follows the convention of Omarchy's own plugins
// (bar/BarModel.js, panels/power/Model.js).
//
// Loaded by QML as `import "Model.js" as Model`, and by node in the test
// suite via the guarded export at the bottom. Nothing in here may touch QML
// types, timers, or Process — it is all input -> output so that the parts
// which have historically broken are the parts under test.
//
// Deliberately NOT a `.pragma library` file: that directive is QML-only and
// makes node fail to parse the file, which would defeat the entire point of
// keeping one shared copy under test.

// ---------------------------------------------------------------- parsing

// Parse `solaar show` output into one entry per paired device.
//
// The trap this exists to survive: every BACKLIGHT2 field is printed twice,
// once as "Backlight Level (saved): 3" and once as the live
// "Backlight Level        : 0". They routinely disagree — the saved value is
// what solaar remembers, the live value is what the hardware is actually
// doing — and reading the wrong one is why the keyboard once sat dark while
// everything claimed it was lit. The regexes below require whitespace right
// up to the colon, which the "(saved)" variant cannot match.
function parseDevices(text) {
  var lines = String(text || "").split("\n")
  var result = []
  var current = null
  var inBacklight2 = false

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]

    var deviceMatch = line.match(/^\s{2}(\d+):\s+(.+?)\s*$/)
    if (deviceMatch) {
      if (current) result.push(current)
      current = {
        name: deviceMatch[2],
        deviceIndex: parseInt(deviceMatch[1], 10),
        batteryPercent: null,
        connected: true,
        hasBacklight: false,
        backlightMode: null,
        backlightLevel: null
      }
      inBacklight2 = false
      continue
    }
    if (!current) continue

    var batteryMatch = line.match(/Battery:\s*(\d+)%/)
    if (batteryMatch) current.batteryPercent = parseInt(batteryMatch[1], 10)

    if (line.indexOf("BACKLIGHT2") !== -1) {
      current.hasBacklight = true
      inBacklight2 = true
      continue
    }
    // A new numbered HID++ feature line ends the BACKLIGHT2 block.
    if (inBacklight2 && /^\s{8}\d+:\s/.test(line) && line.indexOf("BACKLIGHT2") === -1) {
      inBacklight2 = false
    }
    if (inBacklight2) {
      var modeMatch = line.match(/Backlight\s+:\s*(\w+)/)
      if (modeMatch) current.backlightMode = modeMatch[1]
      var levelMatch = line.match(/Backlight Level\s+:\s*(\d+)/)
      if (levelMatch) current.backlightLevel = parseInt(levelMatch[1], 10)
    }
  }
  if (current) result.push(current)
  return result
}

// Parse the targeted `solaar config <n> backlight` read used to re-sync
// after a failed write.
function parseConfigRead(text) {
  var s = String(text || "")
  var out = { mode: null, level: null }
  var modeMatch = s.match(/backlight\s*=\s*(\w+)/)
  if (modeMatch) out.mode = modeMatch[1]
  var levelMatch = s.match(/backlight_level\s*=\s*(\d+)/)
  if (levelMatch) out.level = parseInt(levelMatch[1], 10)
  return out
}

// The first backlight-capable device, flattened into the shape the UI binds
// to. Returns a "no keyboard" record rather than null so callers have no
// special case.
function keyboardFrom(devices) {
  var list = devices || []
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (!d.hasBacklight) continue
    return {
      keyboardIndex: d.deviceIndex,
      keyboardName: d.name,
      backlightMode: d.backlightMode !== null ? d.backlightMode : "",
      backlightLevel: d.backlightLevel !== null ? d.backlightLevel : 0,
      keyboardBattery: d.batteryPercent !== null ? d.batteryPercent : -1
    }
  }
  return {
    keyboardIndex: -1,
    keyboardName: "",
    backlightMode: "",
    backlightLevel: 0,
    keyboardBattery: -1
  }
}

function otherDevices(devices) {
  var list = devices || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (!list[i].hasBacklight) out.push(list[i])
  }
  return out
}

// ------------------------------------------------------------ state logic

// A lit keyboard needs Manual mode AND a non-zero level. Mode alone is not
// enough: switching Disabled -> Manual resets the live level to 0 while
// solaar keeps reporting the saved value, so "Manual at level 0" is a dark
// keyboard.
function isOn(mode, level) {
  return mode === "Manual" && level > 0
}

function clampLevel(level, max) {
  var top = (max === undefined || max === null) ? 7 : max
  return Math.max(0, Math.min(top, level))
}

// What level a toggle should move to. Off is level 0, not mode Disabled, so
// that every toggle is a single level write whose value differs from the
// previous one — solaar elides a write equal to the saved value, and a mode
// switch resets the live level, so the old mode-based toggle could leave the
// hardware dark while reporting success.
function toggleTarget(state) {
  var level = state.backlightLevel || 0
  var mode = state.backlightMode || ""
  if (isOn(mode, level)) return 0
  var restore = state.lastOnLevel > 0 ? state.lastOnLevel : state.defaultOnLevel
  return restore > 0 ? restore : 1
}

// The ordered solaar invocations needed to reach `level` from `state`.
//
// Two device quirks are encoded here, both learned the hard way:
//   - a level write only takes effect in Manual mode, so a device found in
//     Disabled/Automatic needs the mode set first;
//   - solaar skips a level write whose value equals the saved one, so after
//     a mode switch (which resets the live level to 0 without changing the
//     saved value) the target is written via 0 first, guaranteeing the
//     second write is a real change.
function planSetLevel(state, level) {
  var idx = String(state.keyboardIndex)
  var target = clampLevel(level, state.levelMax)
  var plan = []
  if (state.backlightMode !== "Manual") {
    plan.push(["solaar", "config", idx, "backlight", "Manual"])
    if (target > 0) plan.push(["solaar", "config", idx, "backlight_level", "0"])
  }
  plan.push(["solaar", "config", idx, "backlight_level", String(target)])
  return plan
}

function planToggle(state) {
  return planSetLevel(state, toggleTarget(state))
}

// A level-set rejected as out of bounds teaches us the device's real
// maximum, which is otherwise unknown (defaults to 7).
function learnLevelMax(stderrText, attemptedLevel) {
  if (String(stderrText || "").indexOf("out of bounds") === -1) return null
  return attemptedLevel - 1
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseDevices: parseDevices,
    parseConfigRead: parseConfigRead,
    keyboardFrom: keyboardFrom,
    otherDevices: otherDevices,
    isOn: isOn,
    clampLevel: clampLevel,
    toggleTarget: toggleTarget,
    planSetLevel: planSetLevel,
    planToggle: planToggle,
    learnLevelMax: learnLevelMax
  }
}
