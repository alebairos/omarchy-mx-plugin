// Hosts the REAL MxQuickControl.qml in a throwaway quickshell and drives it
// the way a person would: a click on the bar icon, a click on the slider, a
// click on the toggle, Escape. Same harness shape as Omarchy's own
// test/shell.d/fixtures/bar-widget-contract/shell.qml, plus QtTest's
// TestEvent for synthetic input -- the closest thing QML has to Playwright.
//
// The widget's transport is a fake (tests/fake-mx-device) that records every
// invocation, so the bash side can assert not just what the UI shows but
// what it *sent* -- one write per gesture, no read after a device-reported
// change. Nothing here touches hardware.
//
// Environment (set by widget-interaction-test.sh):
//   MX_QML_TEST_RESULT   where to write the JSON verdict
//   MX_QML_WIDGET_URL    file:// URL of the MxQuickControl.qml copy to load
import QtQuick
import Quickshell
import QtTest
import qs.Commons

ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("MX_QML_TEST_RESULT")
  readonly property string widgetUrl: Quickshell.env("MX_QML_WIDGET_URL")
  property var failures: []
  property var passes: []
  property var summons: []          // every shell.summon(id, payload) the widget asked for
  property var item: null
  property var slider: null
  property var toggle: null
  property int summonsBefore: 0

  function fail(message) { failures.push(String(message)) }
  function pass(message) { passes.push(String(message)) }
  function assertTrue(condition, message) { if (condition) pass(message); else fail(message) }
  function assertEqual(actual, expected, message) {
    if (actual === expected) pass(message)
    else fail(message + " expected=" + expected + " actual=" + actual)
  }
  function shellQuote(value) { return "'" + String(value).replace(/'/g, "'\\''") + "'" }

  function writeResult() {
    var payload = JSON.stringify({
      ok: failures.length === 0,
      failures: failures,
      passes: passes,
      summons: summons
    })
    if (resultPath)
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
  }

  // Depth-first search for the first object whose QML type name starts with
  // `prefix`. Ids are private to the file that declares them, so a test can
  // only reach the widget's controls by type, which is also what a person
  // sees: "the slider", "the toggle".
  function findByType(obj, prefix, depth) {
    if (!obj || depth > 40) return null
    if (String(obj).indexOf(prefix) === 0) return obj
    var pools = [obj.children, obj.contentItem ? [obj.contentItem] : null, obj.data]
    for (var p = 0; p < pools.length; p++) {
      var pool = pools[p]
      if (!pool) continue
      for (var i = 0; i < pool.length; i++) {
        var hit = findByType(pool[i], prefix, depth + 1)
        if (hit) return hit
      }
    }
    return null
  }

  // ---- a tiny step machine: each step acts, then waits for a condition ---
  property var steps: []
  property int stepIndex: 0
  property double stepStarted: 0
  property var current: null

  Timer {
    id: pump
    interval: 50
    repeat: true
    onTriggered: root.pumpStep()
  }

  function runSteps(list) { steps = list; stepIndex = 0; nextStep() }

  function nextStep() {
    if (stepIndex >= steps.length) { finish(); return }
    current = steps[stepIndex++]
    stepStarted = Date.now()
    try { if (current.action) current.action() } catch (e) { fail(current.name + " threw: " + e); finish(); return }
    pump.running = true
  }

  function pumpStep() {
    var done = false
    try { done = !current.until || current.until() } catch (e) { done = false }
    if (done) {
      pump.running = false
      pass(current.name)
      try { if (current.then) current.then() } catch (e) { fail(current.name + " then() threw: " + e) }
      nextStep()
      return
    }
    if (Date.now() - stepStarted > (current.timeout || 5000)) {
      pump.running = false
      fail("timed out: " + current.name + (current.detail ? " (" + current.detail() + ")" : ""))
      finish()
    }
  }

  function finish() {
    writeResult()
    Qt.quit()
  }

  // ---- the fake shell and bar the widget is given ------------------------
  QtObject {
    id: mockShell
    property var bar: fakeBar
    property var barConfig: ({ position: "top" })
    function firstPartyServiceFor(id) { return null }
    function serviceFor(id) { return null }
    function summon(id, payloadJson) { root.summons.push({ id: id, payload: payloadJson }); return true }
    function hide(id) { return true }
    function toggle(id, payloadJson) { return true }
    function isPluginOpen(id) { return false }
    function updateEntryInline(moduleName, settings) { return true }
  }

  // Everything the Ui kit reads off a bar (grep `bar\.` in shell/Ui): a
  // property left out here reaches KeyboardPanel as undefined and quietly
  // breaks positioning and focus, which is how Escape stopped arriving.
  QtObject {
    id: fakeBar
    property bool vertical: false
    property string position: "top"
    property int barSize: 26
    property int sizeHorizontal: 26
    property real iconSlot: Style.bar.iconSlot
    property real iconCanvas: Style.bar.iconCanvas
    property real iconFont: Style.bar.iconFont
    property string fontFamily: "monospace"
    property color foreground: "white"
    property color background: "black"
    property color barForeground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: []
    property var shell: mockShell
    function targetBelongsToWindow(target, window) { return true }
    function run(command) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) {}
    function releasePopout(owner) {}
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function switchPanelFrom(owner, direction) { return false }
  }

  TestEvent { id: ev }

  // Input needs a real window to travel through; a bare Item has none.
  FloatingWindow {
    id: win
    implicitWidth: 320
    implicitHeight: 64
    visible: true
    title: "mx-quick-control interaction test"
    Item { id: host; anchors.fill: parent }
  }

  Timer {
    interval: 300
    running: true
    repeat: false
    onTriggered: root.runSteps([
      {
        name: "widget loads and instantiates without a bar",
        action: function() {
          var component = Qt.createComponent(root.widgetUrl, Component.PreferSynchronous)
          if (component.status !== Component.Ready) { root.fail("widget failed to load: " + component.errorString()); return }
          root.item = component.createObject(host, { moduleName: "alebairos.mx-quick-control", settings: {} })
          if (!root.item) { root.fail("widget failed to instantiate: " + component.errorString()); return }
          root.assertTrue(root.item.bar === null || root.item.bar === undefined, "starts without an injected bar")
          root.item.bar = fakeBar
          root.assertEqual(root.item.setting("missing", "fallback"), "fallback", "exposes the setting() fallback")
          root.assertEqual(root.item.visible, true, "stays visible before any device is known")
        },
        until: function() { return root.item && root.item.hasKeyboard },
        timeout: 10000,
        detail: function() { return root.item ? root.item.status() : "no item" },
        then: function() {
          root.assertEqual(root.item.backlightMode, "Manual", "initial read: mode from the transport")
          root.assertEqual(root.item.backlightLevel, 4, "initial read: level from the transport")
          root.assertTrue(isFinite(root.item.implicitWidth) && root.item.implicitWidth > 0, "has a positive implicitWidth")
          root.assertTrue(isFinite(root.item.implicitHeight) && root.item.implicitHeight > 0, "has a positive implicitHeight")
          root.item.width = root.item.implicitWidth
          root.item.height = root.item.implicitHeight
        }
      },
      {
        name: "a click on the bar icon opens the panel",
        action: function() { ev.mouseClick(root.item, root.item.width / 2, root.item.height / 2, Qt.LeftButton, Qt.NoModifier, -1) },
        until: function() { return root.item.opened === true }
      },
      {
        name: "the panel presents a brightness slider and a backlight toggle",
        until: function() {
          root.slider = root.findByType(root.item, "PanelSlider", 0)
          root.toggle = root.findByType(root.item, "Toggle", 0)
          return root.slider && root.slider.visible && root.slider.width > 0 && root.toggle && root.toggle.visible
        },
        then: function() {
          root.assertEqual(root.slider.minimum, 1, "slider cannot reach 0: off is the toggle's job")
          root.assertEqual(root.slider.maximum, 7, "slider maximum comes from the device's level count")
          root.assertEqual(root.toggle.checked, true, "toggle shows the backlight as on")
        }
      },
      {
        name: "a click at the right end of the slider sets the maximum level",
        action: function() { ev.mouseClick(root.slider, root.slider.width - 2, root.slider.height / 2, Qt.LeftButton, Qt.NoModifier, -1) },
        until: function() { return root.item.backlightLevel === 7 },
        detail: function() { return "level=" + root.item.backlightLevel }
      },
      {
        name: "a click on the toggle switches the backlight off",
        action: function() { ev.mouseClick(root.toggle, root.toggle.width / 2, root.toggle.height / 2, Qt.LeftButton, Qt.NoModifier, -1) },
        until: function() { return root.item.backlightOn === false && root.item.backlightLevel === 0 },
        detail: function() { return root.item.status() }
      },
      {
        name: "a device-reported state applies both values and asks for two OSDs",
        action: function() {
          root.summonsBefore = root.summons.length
          root.item.applyExternalState("3:2")
        },
        until: function() { return root.item.backlightLevel === 3 && root.item.effectIndex === 2 },
        then: function() {
          var mine = root.summons.slice(root.summonsBefore)
          root.assertEqual(mine.length, 2, "one OSD for the level and one for the effect")
          for (var i = 0; i < mine.length; i++) {
            root.assertEqual(mine[i].id, "omarchy.osd", "OSD is summoned by its first-party id")
            var p = JSON.parse(mine[i].payload)
            root.assertEqual(p.icon, "keyboard", "OSD payload carries the keyboard icon")
          }
          root.assertEqual(root.item.solaarBusy, false, "no device read was started by the reported state")
        }
      },
      {
        name: "Escape closes the panel",
        action: function() { ev.keyClick(Qt.Key_Escape, Qt.NoModifier, -1) },
        until: function() { return root.item.opened === false },
        timeout: 3000
      }
    ])
  }
}
