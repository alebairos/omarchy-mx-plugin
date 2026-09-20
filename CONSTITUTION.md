<!--
Sync Impact Report
- Version change: 1.0.0 → 1.1.0
- Modified principles: none. All five are unchanged in substance and wording.
- Modified sections: Development Workflow. It claimed manual verification
  against the device was the acceptance gate because the project had no
  other harness. That stopped being true in 1.2.0, which added three test
  tiers. It also named the spec-kit commands, which are internal tooling.
- Moved: this file now lives at the root of the public repository rather
  than under specs/. The principles are commitments to whoever reviews or
  installs the plugin, so they belong where those people will find them;
  the specs themselves moved to the private omarchy-mx-plugin-host repo.
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

A change is not done until it has been exercised in a running Omarchy shell
against real hardware. That gate has never been relaxed.

What has changed is that it is no longer the *only* gate. Three test tiers
now stand in front of it — `npm test` (no device), `npm run test:shell`
(the real widget in a throwaway quickshell), and
`npm run test:acceptance` (a live session and the real keyboard). See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for what each one proves and what it
cannot.

Two rules survive from when manual verification was all there was, because
automation did not make either of them safe to skip. Verification is
against the **device's** live value, never the widget's own reported state,
which is optimistic by design. And a passing test is not evidence until the
code it guards has been broken and the test watched to fail.

Specs and planning are written before implementation, in the private
`omarchy-mx-plugin-host` repository. They are kept out of this one because
installing the plugin clones this repository in full onto a user's machine.

## Governance

This constitution supersedes ad hoc implementation choices. Amendments
require a PR description explaining the rationale and, for any change that
weakens Principle I (Simplicity) or II (Shell Out), explicit justification
recorded in that PR. Versioning follows semver: MAJOR for incompatible
governance changes, MINOR for new/expanded principles, PATCH for wording
clarifications.

**Version**: 1.1.0 | **Ratified**: 2026-09-04 | **Last Amended**: 2026-09-20
