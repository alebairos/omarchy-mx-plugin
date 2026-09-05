<!--
Sync Impact Report
- Version change: (none) → 1.0.0
- Modified principles: n/a (initial ratification)
- Added sections: Core Principles (5), Compatibility Requirements, Development Workflow, Governance
- Removed sections: none
- Follow-up TODOs: none
-->
# Omarchy MX Plugin Constitution

## Core Principles

### I. Simplicity First (YAGNI)
The plugin solves exactly the use cases already validated by hand: backlight
mode/level control and battery/status display for Logitech MX peripherals
paired over a Logi Bolt/Unifying receiver. No speculative features (macros,
per-key RGB, gesture config, multi-device fleet management) are added until a
real, validated need exists. When in doubt, the smaller implementation wins.

### II. Shell Out, Don't Reimplement
The plugin MUST talk to hardware exclusively through the `solaar` CLI. It
MUST NOT parse raw HID++ reports, talk to `/dev/hidraw*`/`/dev/input/event*`
directly, or reimplement any part of the HID++ protocol. `solaar` already
solves device discovery, feature negotiation, and persistence; duplicating
that logic is unnecessary risk for zero benefit. If `solaar` cannot do
something, the answer is a `solaar`/`python-logitech-receiver` upstream
contribution, not a workaround in this plugin.

### III. Standard Omarchy Plugin Conventions
The plugin MUST follow the same structure as Omarchy's built-in shell
plugins (`manifest.json` + QML under a single plugin directory) so it can be
installed via `omarchy plugin clone`-style workflows and inspected/modified
by any Omarchy user the same way they'd modify a stock plugin. No custom
build step, packaging format, or plugin loader is introduced.

### IV. Graceful Degradation
The plugin MUST NOT crash the shell or spam errors when `solaar` is absent,
no supported device is paired, or a `solaar` call fails. In any of those
cases it hides itself or shows a clearly disabled state, and logs at most
once per condition change.

### V. No Speculative Dependencies
`solaar` (already verified present and working) is the only required
external dependency. No new daemon, systemd unit, or background service is
introduced by this plugin; if periodic polling is needed, it MUST use
Quickshell's own timer primitives, not an external cron/systemd timer.

## Compatibility Requirements

Targets Omarchy's Quickshell-based shell (`omarchy-shell`) as documented in
this machine's Omarchy skill guides. Device support is whatever `solaar`
itself supports — no device allowlist is hardcoded beyond gracefully
handling the absence of a supported device (Principle IV).

## Development Workflow

Specs, plans, and tasks are produced via spec-kit (`/speckit-specify`,
`/speckit-plan`, `/speckit-tasks`, `/speckit-implement`) before
implementation. Each change is validated by actually loading the plugin in a
running Omarchy shell (`omarchy-shell shell rescanPlugins` or a restart) and
exercising it against real hardware before being considered done — this
project has no other test harness, so manual verification against the real
device is the acceptance gate.

## Governance

This constitution supersedes ad hoc implementation choices. Amendments
require a PR description explaining the rationale and, for any change that
weakens Principle I (Simplicity) or II (Shell Out), explicit justification
recorded in that PR. Versioning follows semver: MAJOR for incompatible
governance changes, MINOR for new/expanded principles, PATCH for wording
clarifications.

**Version**: 1.0.0 | **Ratified**: 2026-09-04 | **Last Amended**: 2026-09-04
