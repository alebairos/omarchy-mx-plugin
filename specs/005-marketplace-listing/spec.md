# Feature Specification: Marketplace listing

**Feature Branch**: `005-marketplace-listing`

**Created**: 2026-09-19

**Status**: Draft

**Input**: v1.2.0 is released and installable by URL, but the plugin is not
discoverable. List it on [plugins.omarchy.org](https://plugins.omarchy.org)
so a user who does not already know the repository can find it.

## What listing actually requires

Read on 2026-09-19 from [publish.html](https://plugins.omarchy.org/publish.html),
the marketplace repository's `SUBMISSION.md` (the CLI/agent path), and its
`SECURITY.md` (the scanner's own rules). Checked against this repository at
`main` = `v1.2.0`:

| Requirement | This repository | Verified by |
|---|---|---|
| Public GitHub repo, root URL, one plugin | `github.com/alebairos/omarchy-mx-plugin`, `visibility: PUBLIC` | `gh repo view --json visibility` |
| `manifest.json` at the repo root | present, schema-valid | `omarchy plugin validate .` exits 0 |
| Root README with **install and removal** instructions | `## Install`, `### Removing` | README.md headings |
| Root license file, external dependencies documented | `LICENSE` (MIT); `## Requirements` names Solaar | README.md, LICENSE |
| Globally unique ID outside `omarchy.*` | `alebairos.mx-quick-control` | manifest.json |
| Does not overwrite user config without consent | the Solaar rule is an optional **manual append** the user performs | README.md "Known limitations" |
| Optional root preview image | **missing** | `find . -iname 'preview.*'` returns nothing |

Six of seven already hold. Only the preview is absent, and the submission
itself has never been filed: the marketplace currently lists zero plugins
and no issue references this ID.

### The two gaps, stated precisely

1. **No preview image.** A root `preview.png`, `.jpg`, `.jpeg`, `.webp` or
   `.avif` is optional, but the marketplace generates both the card image
   and the detail image from it. Without one the listing is a text card
   beside plugins that have pictures. Input limits are 50 MB and 40
   megapixels; the marketplace strips metadata and does its own optimisation,
   so no manual resizing or compression is wanted.

2. **No chosen listing metadata.** The submission form requires exactly one
   category and one to three tags, from closed vocabularies. More than three
   tags is an automatic rejection. Nothing in the repository records which
   ones this plugin claims, so the choice would otherwise be made ad hoc at
   submission time and be unreviewable afterwards.

## Decisions, with the reasoning that produced them

### Category: `Hardware`

The closed list is Appearance, Desktop, Developer Tools, Hardware, Kids,
Productivity, System, Widgets, Other. This plugin exists to drive one class
of physical peripheral; that is what a user browsing for it would filter on.
`Widgets` describes its *form* and would be true of most bar plugins, so it
does not discriminate. `System` is the manifest's **bar** category, which is
a different vocabulary for a different purpose (where it sits in the panel
list) and should not be copied across by reflex.

### Tags: `bar`, `quickshell`, `power-management`

From the closed list, and capped at three. `bar` and `quickshell` are what
it structurally is. `power-management` is the honest third: the widget's
default visible state is a battery reading, which is the part most users
will see most of the time. `system` was considered and dropped as the least
discriminating of the four candidates.

### The ID stays `alebairos.mx-quick-control`

`SUBMISSION.md` *prefers* a reverse-domain form such as
`io.github.yourname.plugin-name`, but *requires* only a unique lowercase
namespaced ID outside `omarchy.*`, which this satisfies. Against that
preference stands the cost: the ID is the install path
(`~/.config/omarchy/plugins/alebairos.mx-quick-control`), it is written into
a published release, the README, the IPC target name and every acceptance
test, and it is already installed on at least one machine. Renaming breaks
all of that to satisfy a preference, not a rule.

This is nonetheless a **one-way door**, and that is why it is written down
here rather than decided silently: marketplace IDs are permanent, and IDs
from retired or renamed listings are never reusable, by anyone, including
their original author. The moment the listing is approved, this string is
fixed forever.

### The docs keep saying `sudo pacman -S solaar`

The Automated Security Baseline will return `review-required` rather than
`passed` for this repository. Two lines mention installing the dependency
with `sudo pacman -S solaar` — one in README.md, one in the widget's own
empty-state message in `MxQuickControl.qml` — which trip the `privilege` and
`package-manager` *capabilities*. Capabilities are not findings: they require
maintainer review and remain eligible for approval.

The scanner explicitly excludes negated mentions such as "No sudo is
required", so the label could be dodged by rewording. It should not be. The
line is a true and useful instruction to a user whose keyboard does nothing
because Solaar is missing, and the empty-state message is the single place a
user is most likely to read it. Writing worse documentation to flatter a
static scanner inverts the point of the scan.

None of the actual blocking patterns are present, confirmed by grep over the
repository: no `curl`/`wget` piped to a shell, no sudoers or `NOPASSWD`
policy, no unpinned `cargo install --git` or remote git execution, no bundled
executable binary (`mx-device` is an ASCII Python script, not an ELF image),
no privileged process control from shared temp.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A user discovers the plugin without being told about it (Priority: P1)

Someone browsing the marketplace for something to do with their Logitech
keyboard finds this plugin, sees what it looks like before installing, and
copies the install command.

**Why this priority**: It is the entire purpose of listing. The plugin is
already installable by URL for anyone who has the URL.

**Independent Test**: Load the marketplace, filter to the chosen category,
and confirm the card shows a picture of the actual widget and a working
install command.

**Acceptance Scenarios**:

1. **Given** the repository at the submitted commit, **When** the
   marketplace build reads it, **Then** it finds a root preview image within
   the 50 MB / 40 megapixel input limits and generates card and detail
   images from it.
2. **Given** the generated card, **When** a user looks at it, **Then** the
   image shows this plugin's own interface — the bar widget and its open
   panel — and not a generic logo, a full unrelated desktop, or an empty bar.
3. **Given** the submission issue, **When** automated validation runs,
   **Then** the category is one value spelled exactly as the closed list
   spells it and the tags number between one and three, all from the closed
   list.

---

### User Story 2 - A reviewer can tell what they are approving (Priority: P2)

A marketplace maintainer opens the submission, sees a `review-required`
label, and can resolve it without a round trip.

**Why this priority**: It does not block listing, but an unexplained
capability label is the most likely cause of the submission stalling.

**Acceptance Scenarios**:

1. **Given** the submission's maintainer-notes field, **When** a reviewer
   reads it, **Then** it states the external dependency, says where the
   privilege capability comes from and that it is a dependency-install
   instruction rather than plugin behaviour, and states that the optional
   Solaar rule is a manual user action.
2. **Given** the checklist, **When** each box is read against this
   repository, **Then** every box is true as written, including the one
   about not overwriting user configuration.

---

### User Story 3 - The preview can be regenerated when the UI changes (Priority: P3)

The widget's appearance changes in some later release, and the preview is
brought back into line without anyone guessing how the first one was made.

**Why this priority**: A stale preview is a slow, quiet failure — the
listing keeps showing a version of the interface that no longer exists.

**Acceptance Scenarios**:

1. **Given** this spec, **When** someone needs a new preview, **Then** the
   capture procedure is recorded here precisely enough to repeat, including
   how the crop region is derived rather than eyeballed.
2. **Given** the capture, **When** it contacts the device, **Then** it does
   so a counted number of times and restores the level it changed, per
   AGENTS.md.

## The capture procedure

Written after running it. The first two attempts both produced an unusable
image, for reasons that are not guessable from the documentation and are
therefore the useful part of this section.

The script is kept at
[`capture-preview.sh`](./capture-preview.sh), beside this spec rather than
in the plugin root: it is reasoning about the plugin, not part of it, and
the repository asks users to review the root as shipped code.

### Preconditions, all of which failed at least once

- **The session must be unlocked.** A locked Omarchy session draws the lock
  surface above everything, so the bar renders nothing and the capture is a
  picture of the password box. This is not obvious from `hyprctl`: the bar
  layer is still present, still mapped, still `1920x26` at `0,0`.
- **The display must be awake.** `grim` blocks indefinitely rather than
  failing when the monitor is in DPMS off, because no frame is ever
  produced. Check `hyprctl -j monitors | jq .[].dpmsStatus` first, and run
  `grim` under `timeout` regardless.
- **No special workspace may be showing.** The scratchpad overlay draws over
  the bar. Hide it for the capture and toggle it back afterwards.
- **The visible workspace should be empty.** This matters more than it
  looks: the resulting file is committed to a public repository and
  published to a marketplace, so anything on screen is published with it.
  Assert the window count on the visible workspace is zero, crop tightly,
  and never ship a full-desktop frame.

### Deriving the crop

The panel is drawn *inside* a fullscreen layer surface. `omarchy-bar` has a
real rectangle (`0,0 1920x26`), but `omarchy-keyboard-panel` reports
`0,0 1920x1080` — the whole monitor — so the union of the two layer
rectangles is the entire screen and is useless as a crop. Hardcoding the
panel's pixel offsets instead would be wrong on any other monitor.

Difference two frames instead:

1. Close the panel, capture frame A.
2. Open it, wait for `layer_on_screen`, capture frame B.
3. `magick A B -compose difference -composite -colorspace Gray -threshold 8%`
   and read the trim bounding box (`-format '%@'`). Whatever changed is the
   panel, in real pixels, derived rather than assumed.
4. Union that box with the bar strip above it, pad evenly, clamp to the
   monitor, and crop frame B.

Capture at `grim -s 2` so the panel's caption text survives the
marketplace's downscale to a card.

### Driving Hyprland on 0.56.2

`hyprctl dispatch` now routes through Lua, and the documented shell form
fails:

```
$ hyprctl dispatch togglespecialworkspace scratchpad
error: [string "return hl.dispatch(togglespecialworkspace scr..."]:1:
')' expected near 'scratchpad'
```

It exits **7**, which under `set -e` aborts the script at the first toggle.
The working form names the dispatcher as a function:

```bash
hyprctl dispatch 'hl.dsp.workspace.toggle_special("scratchpad")'
hyprctl dispatch 'hl.dsp.dpms("on")'
```

Dispatcher names are discoverable at runtime — `hyprctl eval` returns only
`ok`, so use `hyprctl repl`, which prints the value:

```bash
hyprctl repl 'local t={} for k,v in pairs(hl.dsp.workspace) do t[#t+1]=k end
              table.sort(t) return table.concat(t,", ")'
# change_id, move, rename, swap_monitors, toggle_special
```

Note that `hl.dsp.dpms` is a function where `hl.dsp.workspace` is a table,
so iterating it raises `table expected, got function`.

### Getting a blank backdrop: what does not work

The visible workspace has to be empty, because the frame is published. Two
plausible shortcuts were tried and neither works:

- **An empty special workspace does not blank the screen.** Toggling one on
  overlays nothing and leaves every window on the workspace beneath fully
  visible. A capture taken this way contained the author's open mail client.
- **There is no "switch to workspace N" in `hl.dsp.workspace`.** Its members
  are `change_id`, `move`, `rename`, `swap_monitors`, `toggle_special`.
  `change_id` *renames* a workspace (it wants `{ workspace, id }` and
  answers "no such workspace"), `move` wants a monitor, and `hl.dsp.focus`
  handles only `direction`, `monitor`, `window`, `urgent_or_last`, `last`.
  `hl.dsp.send_shortcut({ mods, key })` could replay the user's own
  workspace keybind, but that depends on their config and is not something
  this script should assume.

So the script does not try to arrange a blank screen. It asserts the
condition and refuses, and a person switches to an empty workspace before
running it. That is one action by someone who can see the screen, against
an unbounded set of ways to get it wrong on their behalf.

### The terminal you run it from is one of the windows

Requiring an empty visible workspace and requiring a person to type the
command are in direct conflict: the terminal is itself a window on that
workspace, and so is whatever agent session is driving it. The first
version of the script was therefore unrunnable by hand, which is exactly
how it failed the first time someone tried it.

`--in N` resolves it. The script does its preflight, counts down N seconds
while you switch to an empty workspace, and only then checks the window
count and captures:

```bash
bash specs/005-marketplace-listing/capture-preview.sh --in 10
```

The refusal also now lists the offending windows by class and title, so the
reason is visible rather than inferred.

Refusing must also cost the device nothing. The first version restored the
backlight level from its exit trap unconditionally, so a run that bailed
out before touching the keyboard still issued a write on the way out. The
restore is now guarded by whether the mid-level write actually happened.

### The device, and proving the restore

Set the level to mid-travel before capturing so the slider is not at either
stop, and write the original back afterwards: **two writes, counted, no
reads**, per AGENTS.md.

One restore silently did not take. The widget reported the pre-restore level
afterwards, and nothing errored. Per CONTRIBUTING.md the widget's own status
is optimistic and is not evidence, so the restore is confirmed with one
deliberate `mx-device state` read against the live device — the only device
read in the whole procedure.

## Scope

**In scope**: one root preview image; the category, tag and maintainer-note
values recorded in this spec; a README pointer so the image is not mistaken
for a stray asset.

**Out of scope**: renaming the plugin ID; rewording documentation to change
the scanner's outcome; the `Suggest a missing tag` field, since three of the
existing tags fit; filing the submission issue itself, which is a separate,
outward-facing act that happens once this is merged; and the marketplace's
`verify-plugin.yml` path, which applies to already-listed plugins.

## Success Criteria

- **SC-001**: `omarchy plugin validate .` still exits 0 at the repo root
  after the change.
- **SC-002**: A root preview file exists in one of the five accepted
  formats, under 50 MB and 40 megapixels.
- **SC-003**: The preview shows the bar widget and the open panel of a real
  paired device, legible at card size.
- **SC-004**: The recorded category is one of the nine listed values, spelled
  exactly; the recorded tags are between one and three of the thirteen
  listed values.
- **SC-005**: Every submission-checklist box is true of this repository as
  written.
- **SC-006**: The device ends the capture at the backlight level it started
  at.
