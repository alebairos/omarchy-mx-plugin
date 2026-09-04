# Contract: Widget IPC surface

Following the same pattern as the built-in `SystemUpdate` bar widget
(`IpcHandler` with a `target` name matching the plugin's module id), this
widget exposes one IPC command for manual refresh — useful for testing and
for any future keybinding that wants to force an update (e.g. right after
the user changes something in Solaar directly).

```qml
IpcHandler {
  target: "omarchy.mx-quick-control"
  function refresh(): void { root.broadcast("refresh") }
}
```

Callable from a terminal as (exact invocation follows Quickshell's IPC
conventions, same as other Omarchy widgets):

```
qs ipc call omarchy.mx-quick-control refresh
```

No other IPC surface is exposed in v1 — click/scroll interaction is handled
directly in the widget, not via IPC, since it's local UI, not something
another process needs to trigger.
