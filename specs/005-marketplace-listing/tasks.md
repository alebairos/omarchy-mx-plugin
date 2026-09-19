# Tasks: Marketplace listing

**Input**: [spec.md](./spec.md)

**Prerequisites**: v1.2.0 released; `main` clean and green.

**Tests**: This feature adds no runtime code, so it adds no unit or shell
tests. Its gates are `omarchy plugin validate .` and the reviewable content
of the preview image itself, which is exactly the kind of thing the
constitution reserves for human verification.

## Format: `[ID] [P?] [Story] Description`

---

## Phase A: Record the decisions (BLOCKER)

**Purpose**: The category, tags and ID are one-way doors. They are written
down and reviewed before anything is submitted, not chosen in the issue form.

- [x] T001 Write `spec.md`: the seven listing requirements measured against
      this repository, the two gaps, and the four decisions with reasoning
- [x] T002 Record the capture procedure, deriving the crop from measured
      geometry rather than hardcoded offsets

**Checkpoint**: A reviewer can disagree with the category, the tags or the
retained ID before any of them becomes permanent. ✅

---

## Phase B: The preview image (P1)

**Purpose**: Close the one missing listing requirement.

- [x] T003 [US1] Write the capture as a repeatable script
      ([`capture-preview.sh`](./capture-preview.sh)) rather than a one-off:
      three attempts each failed differently, and the preconditions are not
      guessable
- [x] T004 [US1] Make the script derive the panel's drawn bounds by
      differencing a closed frame against an open one. The layer rectangle
      cannot be used: the panel is drawn inside a **fullscreen** layer
      surface reporting `0,0 1920x1080`
- [x] T005 [US1] Port the Hyprland calls to the 0.56.2 Lua dispatch API.
      `hyprctl dispatch togglespecialworkspace scratchpad` exits **7** and
      aborts the script under `set -e`
- [x] T006 [US1] Guard the preconditions that each silently produced a
      useless image: session locked, display in DPMS off (`grim` hangs
      rather than failing), scratchpad overlay covering the bar, and windows
      on the visible workspace
- [x] T007 [US1] Refuse to capture when the visible workspace is not empty.
      This image is published; whatever is on screen is published with it
- [x] T008 [US1] Run the capture and commit `preview.png`

  Captured on the third attempt, after two script fixes found by running it:
  `--in N` (the terminal you type into is itself a window on the visible
  workspace) and differencing below the bar (the clock ticking at the far
  left stretched the first crop to 1889px). Taken on the built-in Tokyo
  Night theme, whose background is byte-identical to the Omarchy-shipped
  asset — which is what makes the "I own the preview assets" checklist box
  true.

- [x] T009 [US1] Confirm the captured file is within the 50 MB and 40
      megapixel input limits and reads at card size — 669x589, 0.39 MP, 92 KB
- [x] T010 [US1] Confirm `omarchy plugin validate .` still exits 0 with the
      new root file present (SC-001)

---

## Phase C: Make the asset legible to a reader (P2)

- [x] T011 [US2] Add a line to README.md identifying `preview.png` as the
      marketplace listing image and pointing at this spec

---

## Phase D: The submission, prepared but not sent (P2)

**Purpose**: Filing the issue is outward-facing and permanent. Prepare it
fully; send it as a deliberate separate act.

- [x] T012 [US2] Draft the submission in the exact format `SUBMISSION.md`
      requires — [`submission.md`](./submission.md)
- [x] T013 [US2] Write maintainer notes that pre-answer the
      `review-required` label: the Solaar dependency, where the privilege
      capability comes from, and that the Solaar rule is a manual user step
- [x] T014 [US2] Verify each of the five checklist boxes against the
      repository rather than ticking it (SC-005). The "own the preview
      assets" box was conditional on the background in frame; **resolved** —
      the capture was taken on built-in Tokyo Night, and its background is
      byte-identical to `/usr/share/omarchy/themes/tokyo-night/backgrounds/0-winding-road.webp`
- [ ] T015 Submit the issue to `omacom/omarchy-plugin-marketplace` — **human
      decision, after `preview.png` lands and this branch merges**

---

## What this deliberately does not do

- **No ID rename.** See the spec's one-way-door note.
- **No documentation reworded to move `review-required` to `passed`.** The
  scanner rewards negated mentions of `sudo`; the honest instruction is
  worth more than the label.
- **The capture script lives in `specs/`, not the repo root.** It is
  reasoning about the plugin, not part of it, and the root is what users are
  asked to review as shipped code. This reverses T002's first draft, which
  said no script at all: three different failure modes made a written
  procedure insufficient.
