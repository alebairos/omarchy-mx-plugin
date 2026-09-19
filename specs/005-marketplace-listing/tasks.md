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
- [ ] **T008 [US1] Run the capture and commit `preview.png` — BLOCKED**

  The session is locked (`omarchy-hyprland-session-locked` exits 0), and a
  locked session draws its lock surface above everything, so the bar renders
  nothing and the capture is a picture of the password box. Nothing in
  `hyprctl` says so: the bar layer is still present, still mapped, still
  `1920x26` at `0,0`.

  This needs an unlocked session and cannot be worked around. Unlock, then:

  ```bash
  bash specs/005-marketplace-listing/capture-preview.sh
  ```

  The script now refuses up front with the reason rather than producing a
  useless file, which is the behaviour proved by running it as it stands.

- [ ] T009 [US1] Confirm the captured file is within the 50 MB and 40
      megapixel input limits and reads at card size
- [ ] T010 [US1] Confirm `omarchy plugin validate .` still exits 0 with the
      new root file present (SC-001)

---

## Phase C: Make the asset legible to a reader (P2)

- [ ] T011 [US2] Add a line to README.md identifying `preview.png` as the
      marketplace listing image and pointing at this spec. Deferred with
      T008: a README pointing at a file that is not there is worse than no
      pointer

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
      repository rather than ticking it (SC-005). One carries a condition:
      the "own the preview assets" box depends on the desktop background
      that ends up in frame, so it is checked at capture time
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
