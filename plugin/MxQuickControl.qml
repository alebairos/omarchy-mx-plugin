import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// MX Quick Control - battery status + backlight control for Logitech MX
// peripherals, driven entirely through the `solaar` CLI. Click the bar icon
// to open a panel (same click-to-open, stays-open pattern as Omarchy's
// built-in Network/Bluetooth/Power panels) with a backlight on/off switch,
// a brightness slider, and battery status for every paired device.
// See specs/001-mx-quick-control/ in the source repo for the full spec,
// plan, and the exact `solaar` command contract this file implements.
Panel {
  id: root
  moduleName: "alebairos.mx-quick-control"
  ipcTarget: "alebairos.mx-quick-control"
  // Owning the IpcHandler ourselves (see below) so we can add `refresh`
  // alongside the open/close/show/hide/toggle the base Panel would
  // otherwise register on our behalf.
  manageIpc: false

  // One entry per device solaar reports this refresh:
  // { name, deviceIndex, batteryPercent (or null), connected, hasBacklight,
  //   backlightMode ("Automatic"|"Manual"|"Disabled"|null), backlightLevel (int or null) }
  property var devices: []
  property bool solaarAvailable: true

  // Per-device learned max backlight level (deviceIndex -> int), populated
  // lazily the first time a level-set is rejected as out of bounds. See
  // contracts/solaar-cli.md, "levelMax detection".
  property var levelMaxByDevice: ({})

  // A reasonable default brightness when turning the backlight on from
  // fully off (level 0) — otherwise "on" can land at level 0, which looks
  // identical to off.
  readonly property int defaultOnLevel: 4

  readonly property var keyboard: {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].hasBacklight) return devices[i]
    }
    return null
  }

  readonly property var otherDevices: {
    var list = []
    for (var i = 0; i < devices.length; i++) {
      if (!devices[i].hasBacklight) list.push(devices[i])
    }
    return list
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
    if (turningOn) {
      var level = (keyboard.backlightLevel && keyboard.backlightLevel > 0) ? keyboard.backlightLevel : defaultOnLevel
      keyboard.backlightMode = "Manual"
      keyboard.backlightLevel = level
      devices = devices.slice()
      ensureManualThenSetLevel(keyboard.deviceIndex, level)
    } else {
      keyboard.backlightMode = "Disabled"
      devices = devices.slice()
      setMode(keyboard.deviceIndex, "Disabled")
    }
  }

  function setBrightness(level) {
    if (!keyboard) return
    var needsModeSwitch = keyboard.backlightMode !== "Manual"
    keyboard.backlightLevel = level
    if (needsModeSwitch) keyboard.backlightMode = "Manual"
    devices = devices.slice()
    if (needsModeSwitch) ensureManualThenSetLevel(keyboard.deviceIndex, level)
    else setLevel(keyboard.deviceIndex, level)
  }

  function setMode(deviceIndex, mode) {
    modeProc.pendingLevel = -1
    modeProc.command = ["solaar", "config", String(deviceIndex), "backlight", mode]
    modeProc.running = true
  }

  function ensureManualThenSetLevel(deviceIndex, level) {
    modeProc.pendingLevel = level
    modeProc.pendingDeviceIndex = deviceIndex
    modeProc.command = ["solaar", "config", String(deviceIndex), "backlight", "Manual"]
    modeProc.running = true
  }

  function setLevel(deviceIndex, level) {
    levelProc.targetDeviceIndex = deviceIndex
    levelProc.targetLevel = level
    levelProc.command = ["solaar", "config", String(deviceIndex), "backlight_level", String(level)]
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
        // Every BACKLIGHT2 field is printed twice by `solaar show`: a
        // "(saved)" line and the live value. The saved variant always has
        // non-whitespace ("(saved)") between the label and the colon, so
        // requiring whitespace right up to the colon here naturally skips
        // it and only matches the live line.
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
    id: modeProc
    property int pendingLevel: -1
    property int pendingDeviceIndex: -1
    onExited: function(exitCode) {
      if (pendingLevel >= 0) {
        var lvl = pendingLevel
        var idx = pendingDeviceIndex
        pendingLevel = -1
        pendingDeviceIndex = -1
        root.setLevel(idx, lvl)
      } else {
        root.refresh()
      }
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
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.keyboard && root.keyboard.backlightMode === "Manual") ? "💡" : "⌨"
    active: root.keyboard && root.keyboard.backlightMode === "Manual"
    tooltipText: "MX Quick Control"
    onPressed: function(b) {
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      PanelSectionHeader {
        text: root.keyboard ? root.keyboard.name : "MX Quick Control"
        foreground: root.bar.foreground
      }

      Text {
        visible: !root.keyboard
        width: parent.width
        textFormat: Text.PlainText
        text: root.devices.length === 0 ? "No Logitech devices detected" : "No backlight-capable device paired"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        wrapMode: Text.WordWrap
      }

      Toggle {
        visible: !!root.keyboard
        width: parent.width
        label: "Backlight"
        description: root.keyboard && root.keyboard.batteryPercent !== null
          ? "Battery " + root.keyboard.batteryPercent + "%" : ""
        checked: !!(root.keyboard && root.keyboard.backlightMode === "Manual")
        foreground: root.bar.foreground
        onClicked: root.toggleBacklight()
      }

      Row {
        visible: !!(root.keyboard && root.keyboard.backlightMode === "Manual")
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "💡"
          font.pixelSize: Style.font.heading
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelSlider {
          id: brightnessSlider
          bar: root.bar
          width: parent.width - 70
          anchors.verticalCenter: parent.verticalCenter
          minimum: 0
          maximum: root.keyboard && root.levelMaxByDevice[root.keyboard.deviceIndex] !== undefined
            ? root.levelMaxByDevice[root.keyboard.deviceIndex] : 7
          step: 1
          integer: true
          value: root.keyboard && root.keyboard.backlightLevel !== null ? root.keyboard.backlightLevel : 0
          onMoved: function(v) { root.setBrightness(Math.round(v)) }
        }

        Text {
          textFormat: Text.PlainText
          text: String(root.keyboard && root.keyboard.backlightLevel !== null ? root.keyboard.backlightLevel : 0)
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          width: 24
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      PanelSeparator {
        visible: root.otherDevices.length > 0
        foreground: root.bar.foreground
      }

      Repeater {
        model: root.otherDevices
        delegate: Text {
          width: column.width
          textFormat: Text.PlainText
          text: modelData.name + ": " + (modelData.batteryPercent !== null ? modelData.batteryPercent + "%" : "battery n/a")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
        }
      }
    }
  }
}
