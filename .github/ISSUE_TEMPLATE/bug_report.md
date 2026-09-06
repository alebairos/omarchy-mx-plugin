---
name: Bug report
about: Something the widget does wrong
labels: bug
---

## What happened, and what you expected

## Your setup

- Plugin version: <!-- see manifest.json, or `omarchy plugin list` -->
- Device(s): <!-- e.g. MX Mechanical Mini + Bolt receiver / Bluetooth -->
- `solaar --version`:
- Omarchy version: <!-- omarchy version -->

## What the device itself reports

This separates "the widget is wrong" from "the device is in an odd state",
which are very different bugs:

```
solaar show | grep -E "^ +Backlight Level +:|^ +Backlight +:"
```

```
qs -p /usr/share/omarchy/shell ipc call alebairos.mx-quick-control status
```

## Anything in the shell log

```
journalctl --user -b 0 --since "5 minutes ago" | grep -i qml
```
