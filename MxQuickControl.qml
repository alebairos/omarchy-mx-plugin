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

  // Keyboard state lives in plain observable properties rather than being
  // read through `devices`. QML cannot observe field mutations on plain JS
  // objects, and a computed `keyboard` binding hands back the *same* object
  // reference after a refresh, so no change signal fires and every control
  // bound to it goes stale -- which is exactly what made the toggle snap
  // back and kept the brightness slider from ever appearing.
  property int keyboardIndex: -1
  property string keyboardName: ""
  property string backlightMode: ""
  property int backlightLevel: 0
  property int keyboardBattery: -1
  readonly property bool hasKeyboard: keyboardIndex >= 0

  // "On" is a lit keyboard, which means Manual mode *and* a non-zero level.
  // Mode alone is not enough: switching Disabled -> Manual resets the live
  // level to 0 while solaar still reports the saved value, so a keyboard in
  // Manual at level 0 is physically dark.
  readonly property bool backlightOn: backlightMode === "Manual" && backlightLevel > 0

  // Level to restore when switching back on, remembered across an off.
  property int lastOnLevel: 0

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

  // Only one `solaar` invocation may be in flight at a time. Concurrent
  // calls contend for the same receiver and one of them fails (observed:
  // `solaar config ... backlight Manual` exiting 1 while a background
  // `solaar show` was running), so a background refresh must never race a
  // user action. Writes take priority; a refresh that would collide is
  // dropped, since the next timer tick re-reads state anyway.
  readonly property bool solaarBusy: statusProc.running || modeProc.running || levelProc.running || verifyProc.running

  function refresh() {
    if (solaarBusy) return
    statusProc.running = true
  }

  // Copy the freshly parsed keyboard row into the observable properties the
  // UI binds to. Anything not backlight-capable stays in `devices` and is
  // rendered straight from there (read-only, so plain objects are fine).
  function publishKeyboardState() {
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d.hasBacklight) continue
      keyboardIndex = d.deviceIndex
      keyboardName = d.name
      backlightMode = d.backlightMode !== null ? d.backlightMode : ""
      backlightLevel = d.backlightLevel !== null ? d.backlightLevel : 0
      keyboardBattery = d.batteryPercent !== null ? d.batteryPercent : -1
      if (backlightLevel > 0) lastOnLevel = backlightLevel
      return
    }
    keyboardIndex = -1
    keyboardName = ""
    backlightMode = ""
    backlightLevel = 0
    keyboardBattery = -1
  }

  // Off is level 0 rather than mode Disabled. Keeping the device permanently
  // in Manual means a toggle is a single level write whose value always
  // differs from the previous one (0 <-> N), so solaar never skips it as a
  // no-op -- and there is no mode switch to reset the live level behind our
  // back. Both were why the light stayed dark until you nudged the slider.
  function toggleBacklight() {
    if (!hasKeyboard) return
    if (backlightOn) {
      lastOnLevel = backlightLevel
      setBrightness(0)
    } else {
      setBrightness(lastOnLevel > 0 ? lastOnLevel : defaultOnLevel)
    }
  }

  function setBrightness(level) {
    if (!hasKeyboard) return
    var needsModeSwitch = backlightMode !== "Manual"
    backlightLevel = level
    if (level > 0) lastOnLevel = level
    if (needsModeSwitch) {
      backlightMode = "Manual"
      ensureManualThenSetLevel(keyboardIndex, level)
    } else {
      setLevel(keyboardIndex, level)
    }
  }

  // Setting Process.running = true while it is already running is a no-op
  // (the running->running transition fires no start), so a request that
  // arrives mid-command would otherwise be silently dropped -- exactly what
  // a slider drag (many onMoved calls in a row) or a fast double-click
  // produces. dispatchMode()/setLevel() queue the latest request instead
  // and each Process's onExited replays it, so only the *final* desired
  // state after a burst of input is ever lost, never an arbitrary one.
  property var queuedModeAction: null   // { deviceIndex, mode, thenLevel }

  function setMode(deviceIndex, mode) {
    dispatchMode(deviceIndex, mode, -1)
  }

  function ensureManualThenSetLevel(deviceIndex, level) {
    dispatchMode(deviceIndex, "Manual", level)
  }

  function dispatchMode(deviceIndex, mode, thenLevel) {
    // Queue behind ANY in-flight solaar call, not just another mode write:
    // a concurrent `solaar show` refresh will make this one fail with exit 1.
    if (solaarBusy) {
      queuedModeAction = { deviceIndex: deviceIndex, mode: mode, thenLevel: thenLevel }
      return
    }
    modeProc.pendingLevel = thenLevel
    modeProc.pendingDeviceIndex = deviceIndex
    modeProc.command = ["solaar", "config", String(deviceIndex), "backlight", mode]
    modeProc.running = true
  }

  property int queuedLevelDeviceIndex: -1
  property int queuedLevel: -1

  // Called when a write finishes and nothing is queued behind it. On success
  // the optimistic state already matches the device, so we deliberately skip
  // any read -- that is what removes ~10.5s of `solaar show` from every
  // toggle and level change. Only a failed write needs verification.
  function afterWrite(exitCode) {
    if (exitCode === 0 || !hasKeyboard) return
    // Deferred for the same reason as drainQueued(): the Process that just
    // failed still reads as running inside its own onExited.
    Qt.callLater(function() {
      if (root.solaarBusy) return
      verifyProc.command = ["solaar", "config", String(root.keyboardIndex), "backlight"]
      verifyProc.running = true
    })
  }

  // Replay whatever was deferred while solaar was busy. Mode first: a queued
  // level usually belongs to the mode change that preceded it.
  //
  // Every caller is a Process's onExited, and `running` is still true at
  // that point, so dispatching straight from here would hit the solaarBusy
  // guard and re-queue the very item being drained -- with no one left to
  // retry it, which is how a fast off-then-on lost its "on" write entirely
  // and left the keyboard dark while the UI showed it lit. Defer until the
  // running flag has actually settled, and keep deferring while busy.
  function drainQueued() {
    if (solaarBusy) {
      Qt.callLater(drainQueued)
      return
    }
    if (queuedModeAction) {
      var a = queuedModeAction
      queuedModeAction = null
      dispatchMode(a.deviceIndex, a.mode, a.thenLevel)
      return
    }
    if (queuedLevel >= 0) {
      var d = queuedLevelDeviceIndex
      var l = queuedLevel
      queuedLevelDeviceIndex = -1
      queuedLevel = -1
      setLevel(d, l)
    }
  }

  function setLevel(deviceIndex, level) {
    if (solaarBusy) {
      queuedLevelDeviceIndex = deviceIndex
      queuedLevel = level
      return
    }
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
        root.publishKeyboardState()
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.solaarAvailable = false
        root.devices = []
      }
      // A write that arrived while this read was in flight is waiting.
      root.drainQueued()
    }
  }

  Process {
    id: modeProc
    property int pendingLevel: -1
    property int pendingDeviceIndex: -1
    onExited: function(exitCode) {
      // The follow-up level write belongs to the mode change that just
      // landed, so it takes precedence over anything queued behind it.
      if (pendingLevel >= 0) {
        var lvl = pendingLevel
        var idx = pendingDeviceIndex
        pendingLevel = -1
        pendingDeviceIndex = -1
        // A mode switch resets the live level to 0 while solaar's saved
        // value is unchanged, so writing the target directly can be dropped
        // as a no-op. Write 0 first to make the saved value differ, then
        // chain the real target, which is then guaranteed to reach the
        // device. Only the rare mode-switch path pays for the extra write.
        // Deferred: modeProc still reads as running inside its own
        // onExited, so a direct call would re-queue instead of dispatching.
        if (lvl > 0) {
          levelProc.followupLevel = lvl
          levelProc.followupDeviceIndex = idx
          Qt.callLater(function() { root.setLevel(idx, 0) })
        } else {
          Qt.callLater(function() { root.setLevel(idx, lvl) })
        }
        return
      }
      if (root.queuedModeAction || root.queuedLevel >= 0) {
        root.drainQueued()
        return
      }
      // A successful write means the device now holds exactly what we
      // optimistically published, so there is nothing to reconcile and no
      // reason to pay for a full `solaar show` (see afterWrite()).
      root.afterWrite(exitCode)
    }
  }

  Process {
    id: levelProc
    property int targetDeviceIndex: -1
    property int targetLevel: -1
    // Set when this write is the "0 first" half of a mode-switch chain; the
    // real target follows once this one lands.
    property int followupLevel: -1
    property int followupDeviceIndex: -1
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
      if (followupLevel >= 0) {
        var l = followupLevel
        var d = followupDeviceIndex
        followupLevel = -1
        followupDeviceIndex = -1
        Qt.callLater(function() { root.setLevel(d, l) })
        return
      }
      if (root.queuedModeAction || root.queuedLevel >= 0) {
        root.drainQueued()
        return
      }
      root.afterWrite(exitCode)
    }
  }

  // `solaar show` enumerates every device and costs ~10.5s on this hardware,
  // against ~2.3s for a targeted `solaar config` read (measured). It is only
  // needed to discover devices and read battery, neither of which changes
  // quickly, so it runs on a slow timer instead of after every interaction.
  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A write that failed left the device in an unknown state, so re-read the
  // backlight fields -- targeted, not the full enumeration.
  Process {
    id: verifyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var modeMatch = text.match(/backlight\s*=\s*(\w+)/)
        if (modeMatch) root.backlightMode = modeMatch[1]
        var levelMatch = text.match(/backlight_level\s*=\s*(\d+)/)
        if (levelMatch) root.backlightLevel = parseInt(levelMatch[1], 10)
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }

    // Same entry points the panel's controls use, exposed so the widget can
    // be driven and verified without a pointer -- `qs ipc call
    // alebairos.mx-quick-control backlight` etc.
    function backlight(): void { root.toggleBacklight() }
    function level(value: string): void { root.setBrightness(parseInt(value, 10)) }
    function status(): string {
      if (!root.hasKeyboard) return "no backlight-capable device (devices=" + root.devices.length + ")"
      return root.keyboardName + " mode=" + root.backlightMode
        + " level=" + root.backlightLevel
        + " busy=" + root.solaarBusy
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font (Material Design Icons) keyboard glyphs, matching the rest
    // of the bar. Emoji render in a different font at a different weight
    // and ignore the theme colour, which is three separate ways of looking
    // foreign next to a first-party widget. Both codepoints verified
    // present in JetBrainsMono Nerd Font via `fc-list :charset=...`.
    text: root.backlightOn ? "󰌌" : "󰌐"   // mdi-keyboard / mdi-keyboard-off
    active: root.backlightOn
    tooltipText: {
      if (!root.solaarAvailable) return "Solaar not installed"
      if (!root.hasKeyboard) return "No Logitech keyboard detected"
      return root.keyboardName + (root.keyboardBattery >= 0 ? " · " + root.keyboardBattery + "%" : "")
        + " · backlight " + (root.backlightOn ? root.backlightLevel : "off")
    }
    onPressed: function(b) {
      // Middle-click opens Solaar itself, the escape hatch to every
      // setting this widget deliberately does not expose. Mirrors the
      // built-in Microphone widget, which middle-clicks into the audio panel.
      if (b === Qt.MiddleButton) root.bar.run("solaar")
      else root.toggle()
    }
  }

  // Keyboard navigation, matching every first-party panel. `cursorActive`
  // stays false until the first arrow press so opening the panel with the
  // mouse does not paint a cursor nobody asked for -- same convention the
  // built-in Power and Dropbox panels use.
  property bool cursorActive: false
  property int cursorIndex: 0
  // Rows the cursor can visit: 0 = backlight toggle, 1 = brightness slider
  // (only reachable while the backlight is on, since it is disabled when off).
  readonly property int cursorRowCount: backlightOn ? 2 : 1

  function moveCursor(dx, dy) {
    var delta = dy !== 0 ? dy : dx
    cursorIndex = Math.max(0, Math.min(cursorRowCount - 1, cursorIndex + delta))
  }

  function activateCursor() {
    if (cursorIndex === 0) toggleBacklight()
  }

  // Left/right on the slider row nudges brightness; on the toggle row the
  // horizontal keys just move the cursor like anywhere else.
  function adjustCursor(dx) {
    if (cursorIndex !== 1 || !backlightOn) return false
    var max = levelMaxByDevice[keyboardIndex] !== undefined ? levelMaxByDevice[keyboardIndex] : 7
    setBrightness(Math.max(1, Math.min(max, backlightLevel + dx)))
    return true
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorIndex = 0
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0 && root.adjustCursor(dx)) return
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      PanelSectionHeader {
        text: root.hasKeyboard ? root.keyboardName : "MX Quick Control"
        foreground: root.bar.foreground
      }

      Text {
        visible: !root.hasKeyboard
        width: parent.width
        textFormat: Text.PlainText
        text: root.devices.length === 0 ? "No Logitech devices detected" : "No backlight-capable device paired"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        wrapMode: Text.WordWrap
      }

      Toggle {
        visible: root.hasKeyboard
        width: parent.width
        label: "Backlight"
        description: root.keyboardBattery >= 0 ? "Battery " + root.keyboardBattery + "%" : ""
        checked: root.backlightOn
        foreground: root.bar.foreground
        hasCursor: root.cursorActive && root.cursorIndex === 0
        onClicked: root.toggleBacklight()
        onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = 0 } }
      }

      // The brightness row stays mounted whether the backlight is on or
      // off, and only dims when off. Showing/hiding it moved everything
      // below it the instant the toggle was clicked, so the slider could
      // materialise directly under a pointer that was still over the
      // toggle and immediately take the drag.
      Row {
        visible: root.hasKeyboard
        enabled: root.backlightOn
        opacity: root.backlightOn ? 1.0 : 0.35
        width: parent.width
        spacing: Style.space(10)

        Behavior on opacity { NumberAnimation { duration: 120 } }

        Text {
          // mdi-brightness-7, verified present in JetBrainsMono Nerd Font.
          text: "󰃠"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.heading
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelSlider {
          id: brightnessSlider
          bar: root.bar
          width: parent.width - 70
          anchors.verticalCenter: parent.verticalCenter
          // Starts at 1, not 0: level 0 *is* off, and that is the toggle's
          // job. A slider that can reach 0 gives two controls for the same
          // state and lets a drag silently switch the backlight off.
          minimum: 1
          maximum: root.levelMaxByDevice[root.keyboardIndex] !== undefined
            ? root.levelMaxByDevice[root.keyboardIndex] : 7
          step: 1
          integer: true
          value: root.backlightLevel > 0 ? root.backlightLevel : root.lastOnLevel
          onMoved: function(v) { root.setBrightness(Math.max(1, Math.round(v))) }
          onDraggingChanged: if (dragging) { root.cursorActive = true; root.cursorIndex = 1 }
        }

        Text {
          textFormat: Text.PlainText
          text: String(root.backlightLevel > 0 ? root.backlightLevel : root.lastOnLevel)
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
}
