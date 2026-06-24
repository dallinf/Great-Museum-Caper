# Task 5 Report: Replay Styling, Integration Checks, and Final Verification

## Summary

Completed Task 5 for the full-game replay feature. This pass focused on replay playback polish inside the existing game board UI, accessible control labeling, reduced-motion support for replay pawns, and a new integration assertion covering the replay playback surface.

## Files Changed

- `assets/css/app.css`
- `lib/museum_caper_web/live/game_live.ex`
- `test/museum_caper_web/live/game_live_test.exs`

## What Changed

### `test/museum_caper_web/live/game_live_test.exs`

- Added a focused LiveView test: `replay playback surface includes accessible controls and speed selector`.
- Wrote the test first and ran it before implementation.
- The initial failure showed the replay panel was not rendered for a round that had replay events but no thief route history.

### `lib/museum_caper_web/live/game_live.ex`

- Polished the replay panel surface to better match the quiet in-game board UI.
- Added exact `aria-label` values required by the brief:
  - `Step back`
  - `Play replay`
  - `Step forward`
  - `Exit replay`
- Added an `aria-label` for the replay speed selector.
- Tightened button/select focus and hover states for clearer keyboard and pointer interaction.
- Adjusted replay round availability logic so replay controls render when a round has replay events even if `thief_history` is empty. This was required to satisfy the new integration assertion and makes the replay surface depend on replay data rather than route-mark visibility alone.

### `assets/css/app.css`

- Added replay overlay styling for:
  - `.replay-board-layer`
  - `.replay-pawn`
  - `.replay-pawn-thief`
  - `.replay-pawn-detective`
  - `.replay-pawn-red`
  - `.replay-pawn-blue`
  - `.replay-pawn-green`
  - `.replay-pawn-yellow`
- Tuned replay pawn legibility with fixed positioning, stronger border contrast, and clearer shadows.
- Added reduced-motion handling so replay pawns do not transition when `prefers-reduced-motion: reduce` is enabled.

## TDD Notes

1. Added the focused replay playback LiveView assertion first.
2. Ran:

   `mix test test/museum_caper_web/live/game_live_test.exs:2603`

3. Observed expected failure:
   - `assert has_element?(alice_view, "#replay-playback [data-replay-command='back']")`
4. Implemented the LiveView/CSS changes.
5. Re-ran the focused test and confirmed it passed.

## Verification Run

### Focused test

- `mix test test/museum_caper_web/live/game_live_test.exs:2603`
- Result: passed after implementation

### Required test file

- `mix test test/museum_caper_web/live/game_live_test.exs`
- Result: passed

### Required JS tests

- `node --test assets/js/replay_playback_test.mjs assets/js/board_movement_animation_test.mjs assets/js/game_audio_preference_test.mjs assets/js/route_arrow_contrast_test.mjs`
- Result: passed

### Asset build

- `mix assets.build`
- Result: passed

### Formatting

- `mix format`
- Result: passed

### Credo

- `mix credo`
- Result: failed because the task is not available in this repo
- Exact output:

  `** (Mix) The task "credo" could not be found`

### Final project checks

- `mix precommit`
- Result: passed (`341 tests, 0 failures`)

- `git diff --check`
- Result: passed

## Self-Review

- Kept the implementation scoped to the three owned source files.
- Did not modify unrelated config or existing JS hook files.
- Preserved existing replay payload plumbing and only changed selection behavior where the new test exposed a real gap.
- The replay panel styling stays subdued and functional rather than reading like a separate marketing surface.
- Reduced-motion handling is intentionally minimal and targeted to replay pawn movement only.

## Concerns

- `mix credo` is unavailable in the current repo/tooling state, so lint verification is limited to formatting plus the existing `mix precommit` suite.
