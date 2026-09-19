# The marketplace submission, prepared

Not yet filed. Filing it is a deliberate, outward-facing act that happens
once this branch merges and `preview.png` exists — see spec.md.

**Where it goes**: a new issue on `omacom/omarchy-plugin-marketplace` using
the `submit-plugin.yml` template. The marketplace applies the `submission`
label and starts validation when the title and body match the format below,
so the CLI path and the web form produce the same result.

**Title**

```
[Plugin]: MX Quick Control
```

**Body** — the headings are what the template's parser reads, so they are
reproduced exactly, including `_No response_` for the field left blank.

```markdown
### Repository URL

https://github.com/alebairos/omarchy-mx-plugin

### Category

Hardware

### Tags

bar, quickshell, power-management

### Suggest a missing tag

_No response_

### Maintainer notes

Bar widget for Logitech MX peripherals: battery percentage, backlight
on/off, brightness level and lighting effect, for any device Solaar
supports. Developed and verified against an MX Mechanical Mini on a Logi
Bolt receiver.

**External dependency**: Solaar, which the plugin shells out to. It is the
only one. The plugin ships no JavaScript dependencies and adds no daemon,
systemd unit or timer of its own; Node is used solely to run the test suite
and is not needed to install or run the widget.

**On the privilege/package-manager capabilities the baseline will flag**:
the only `sudo` in this repository is the instruction `sudo pacman -S
solaar`, telling the user how to install that dependency. It appears twice,
in README.md and in the widget's own "Solaar is not installed" empty-state
message. The plugin itself never invokes sudo, pkexec, or any package
manager at runtime or install time. I have deliberately not reworded these
to negated forms to change the scan outcome, since they are the most useful
thing a user with a dark keyboard can read.

**On user configuration**: the plugin writes none. It ships an optional
`solaar-rule.yaml` that makes the keyboard's own backlight keys drive the
on-screen display. Installing it is a manual append to
`~/.config/solaar/rules.yaml` performed by the user and documented under
"Known limitations"; nothing in the plugin edits that file, and the widget
works without it.

**Install and removal**: `omarchy plugin add
https://github.com/alebairos/omarchy-mx-plugin.git --enable`, and `omarchy
plugin remove alebairos.mx-quick-control`. Both are in the README, with the
note that removal also drops the bar entry.

Latest release is v1.2.0. `omarchy plugin validate .` exits 0 at the repo
root on Omarchy 4.0.0.r2095.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
```

## Each box, checked rather than ticked

| Box | Evidence |
|---|---|
| Public, with install **and** removal instructions | `gh repo view` reports `visibility: PUBLIC`; README.md has `## Install` and `### Removing` |
| License and external dependencies documented | `LICENSE` (MIT), `## License` in README, `## Requirements` names Solaar as the only one |
| Own the plugin and its preview assets | Repository is the author's; the preview is a capture of this plugin running on the author's own machine. The background in frame is Omarchy's own Tokyo Night wallpaper, byte-identical to `/usr/share/omarchy/themes/tokyo-night/backgrounds/0-winding-road.webp`. An earlier capture on a `wallhaven-*` theme was discarded for this reason |
| Does not overwrite user configuration | The plugin writes no config. `solaar-rule.yaml` is an optional manual append by the user |
| Approval is listing, not a security review | Acknowledged; the marketplace states it plainly and so does this repository's own README about reviewing plugin source |

## Filing it

Once `preview.png` is on `main`:

```bash
gh issue create -R omacom/omarchy-plugin-marketplace \
  --title '[Plugin]: MX Quick Control' \
  --body-file specs/005-marketplace-listing/submission-body.md
```

Extract the fenced body above into `submission-body.md` first, without the
surrounding fence. Validation runs against **the commit that is current when
the scan runs**, not against a tag, so `main` must be in the state you want
reviewed at that moment.
