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

- [x] T001 Write `specs/005-marketplace-listing/spec.md`: the seven listing
      requirements measured against this repository, the two gaps, and the
      four decisions with their reasoning
- [x] T002 Record the capture procedure in the spec, deriving the crop from
      `hyprctl` geometry rather than hardcoded offsets

**Checkpoint**: A reviewer can disagree with the category, the tags or the
retained ID before any of them becomes permanent.

---

## Phase B: The preview image (P1)

**Purpose**: Close the one missing listing requirement.

- [ ] T003 [US1] Capture the bar widget and its open panel per the spec's
      procedure: drive the panel over IPC, wait on `layer_on_screen`, crop
      to the union of the bar and panel rectangles, `grim -s 2`
- [ ] T004 [US1] Set the backlight to a mid level before the capture and
      write the original back afterwards; report the two writes
- [ ] T005 [US1] Save as root `preview.png`; confirm it is within the 50 MB
      and 40 megapixel input limits and that it reads at card size
- [ ] T006 [US1] Confirm `omarchy plugin validate .` still exits 0 with the
      new root file present (SC-001)

**Checkpoint**: The repository satisfies every listing requirement,
mandatory and optional.

---

## Phase C: Make the asset legible to a reader (P2)

**Purpose**: A binary at the repo root with no explanation is exactly the
kind of thing this repository tells users to be suspicious of.

- [ ] T007 [US2] Add a line to README.md identifying `preview.png` as the
      marketplace listing image and pointing at this spec

---

## Phase D: The submission, prepared but not sent (P2)

**Purpose**: Filing the issue is outward-facing and permanent. Prepare it
fully; send it as a deliberate separate act.

- [ ] T008 [US2] Draft the submission issue body in the exact format
      `SUBMISSION.md` requires: repository URL, category, tags, maintainer
      notes, and all five checklist boxes
- [ ] T009 [US2] Write maintainer notes that pre-answer the
      `review-required` label: the Solaar dependency, where the privilege
      capability comes from, and that the Solaar rule is a manual user step
- [ ] T010 [US2] Verify each of the five checklist boxes against the
      repository before ticking it (SC-005)
- [ ] T011 Submit the issue to `omacom/omarchy-plugin-marketplace` — **human
      decision, after this branch merges**

---

## Notes on what this deliberately does not do

- **No capture script in the plugin root.** It would run about once per
  release, and the repository keeps non-plugin tooling out of the way of the
  source review it asks users to perform. The procedure lives in the spec.
- **No ID rename.** See the spec's one-way-door note.
- **No documentation reworded to move `review-required` to `passed`.** The
  scanner rewards negated mentions of `sudo`; the honest instruction is
  worth more than the label.
