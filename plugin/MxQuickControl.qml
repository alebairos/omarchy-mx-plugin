import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// MX Quick Control - battery status + one-click backlight control for
// Logitech MX peripherals, driven entirely through the `solaar` CLI.
// See specs/001-mx-quick-control/ in the source repo for the full spec,
// plan, and the exact `solaar` command contract this file implements.
BarWidget {
  id: root
  moduleName: "omarchy.mx-quick-control"

  // One entry per device solaar reports this refresh:
  // { name, deviceIndex, batteryPercent (or null), connected, hasBacklight,
  //   backlightMode ("Automatic"|"Manual"|"Disabled"|null), backlightLevel (int or null) }
  property var devices: []
  property bool solaarAvailable: true

  // Per-device learned max backlight level (deviceIndex -> int), populated
  // lazily the first time a level-set is rejected as out of bounds. See
  // contracts/solaar-cli.md, "levelMax detection".
  property var levelMaxByDevice: ({})

  readonly property var keyboard: {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].hasBacklight) return devices[i]
    }
    return null
  }

  visible: solaarAvailable && devices.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggleBacklight() {
    if (!keyboard) return
    var turningOn = keyboard.backlightMode !== "Manual"
    var newMode = turningOn ? "Manual" : "Disabled"
    // Optimistic update; reconciled by the next refresh() (spec US2, task T012).
    keyboard.backlightMode = newMode
    devices = devices.slice()
    toggleProc.command = ["solaar", "config", String(keyboard.deviceIndex), "backlight", newMode]
    toggleProc.running = true
  }

  function stepBacklight(delta) {
    if (!keyboard || keyboard.backlightMode !== "Manual") return
    var max = levelMaxByDevice[keyboard.deviceIndex]
    var current = keyboard.backlightLevel !== null ? keyboard.backlightLevel : 0
    var next = current + (delta > 0 ? 1 : -1)
    next = Math.max(0, next)
    if (max !== undefined) next = Math.min(next, max)
    if (next === current) return
    levelProc.targetDeviceIndex = keyboard.deviceIndex
    levelProc.targetLevel = next
    levelProc.command = ["solaar", "config", String(keyboard.deviceIndex), "backlight_level", String(next)]
    levelProc.running = true
  }

  function parseStatus(text) {
    var lines = text.split("\n")
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

  Process {
    id: statusProc
    command: ["solaar", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.solaarAvailable = true
        root.devices = root.parseStatus(text)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.solaarAvailable = false
        root.devices = []
      }
    }
  }

  Process {
    id: toggleProc
    onExited: function(exitCode) {
      // Non-zero here means the optimistic update in toggleBacklight() was
      // wrong; the next refresh() will correct the displayed state either way.
      root.refresh()
    }
  }

  Process {
    id: levelProc
    property int targetDeviceIndex: -1
    property int targetLevel: -1
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.indexOf("out of bounds") !== -1 && levelProc.targetDeviceIndex >= 0) {
          var m = levelMaxByDevice
          m[levelProc.targetDeviceIndex] = levelProc.targetLevel - 1
          levelMaxByDevice = m
        }
      }
    }
    onExited: function(exitCode) {
      root.refresh()
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "omarchy.mx-quick-control"
    function refresh(): void {
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.keyboard && root.keyboard.backlightMode === "Manual") ? "💡" : "⌨"
    active: root.keyboard && root.keyboard.backlightMode === "Manual"
    tooltipText: {
      if (root.devices.length === 0) return "No Logitech devices detected"
      var parts = []
      for (var i = 0; i < root.devices.length; i++) {
        var d = root.devices[i]
        var line = d.name + ": " + (d.batteryPercent !== null ? d.batteryPercent + "%" : "battery n/a")
        if (d.hasBacklight) {
          line += " · backlight " + (d.backlightMode === "Manual" ? ("on, level " + d.backlightLevel) : "off")
        }
        parts.push(line)
      }
      return parts.join("\n")
    }
    onPressed: function(b) {
      root.toggleBacklight()
    }
    onWheelMoved: function(delta) {
      root.stepBacklight(delta)
    }
  }
}
