# Security

## Scope, honestly

This plugin runs as unsandboxed QML inside your long-lived `omarchy-shell`
process, and it shells out to `solaar` and to a bundled Python helper that
talks to your keyboard. It handles no credentials, opens no network
connections, and stores nothing.

The realistic risks are:

- **Command construction.** The plugin builds `solaar` and helper argument
  lists from device data it parses. Argument arrays are used throughout
  rather than shell strings, so device output cannot become shell syntax.
- **Device writes.** The helper writes backlight configuration to your
  keyboard through Solaar's own library. A malformed write can leave the
  backlight in an odd state; it cannot brick the device, and unplugging or
  re-pairing recovers it.
- **What you install.** `omarchy plugin add` clones this repository onto
  your machine and Omarchy runs it unsandboxed. Read the code before
  enabling it — that advice is Omarchy's, and it is right.

## Reporting

Open a normal issue for anything that is merely a bug.

For something you believe is genuinely exploitable, use GitHub's private
vulnerability reporting (**Security → Report a vulnerability**) rather than
a public issue, and please include what an attacker would have to control.

This is a small hobby project maintained by one person. There is no SLA;
expect a best-effort reply.
