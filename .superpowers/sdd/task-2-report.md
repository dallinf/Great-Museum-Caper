# Task 2 Report: Record Replay Events in Rules

## Summary

Implemented authoritative replay event recording in `MuseumCaper.Game.Rules` and extended movement/rules tests to cover entry events, detective movement replay replacement, lock checks, full-round replay persistence, and replay reset between full rounds.

## TDD Evidence

### RED

Added failing tests to `test/museum_caper/game/rules_movement_test.exs` for:

- replay entry event on `enter_museum/2`
- replay movement event on repeated `move_detective/3`
- replay lock-check event on locked `try_escape/2`
- replay event persistence into full-game `round_results`
- replay reset and `turn_index` reset on `start_next_round/1`

Ran:

```bash
mix test test/museum_caper/game/rules_movement_test.exs
```

Result: 89 tests, 4 failures, all due to missing replay event behavior in rules.

### GREEN

Implemented replay recording in `lib/museum_caper/game/rules.ex` for:

- thief entry
- movement replay updates
- lock checks
- escape
- steals
- power off/on transitions
- detective capture
- round-end events
- full-game round result replay persistence
- turn index advancement

Ran:

```bash
mix test test/museum_caper/game/replay_test.exs test/museum_caper/game/rules_movement_test.exs
```

Result: 92 tests, 0 failures.

## Verification

Ran:

```bash
mix format
mix test test/museum_caper/game/replay_test.exs test/museum_caper/game/rules_movement_test.exs
mix precommit
```

Results:

- `mix format`: passed
- targeted replay/rules tests: 92 tests, 0 failures
- `mix precommit`: 335 tests, 0 failures

Additional note:

- `mix credo` could not be run because the task is not available in this repo (`** (Mix) The task "credo" could not be found`).

## Files Changed

- `lib/museum_caper/game/rules.ex`
- `test/museum_caper/game/rules_movement_test.exs`

## Self-Review

- Kept changes scoped to the Task 2-owned files only.
- Preserved existing rules behavior while layering replay event recording into authoritative state transitions.
- Ensured full-round results now carry `replay_events` and that new rounds reset replay state via existing `State.new_game/4` defaults.
- Removed an intermediate unused helper warning before final verification.

## Concerns

- Repository does not expose a `mix credo` task, so lint verification relied on `mix format` plus the project’s `mix precommit` gate.

## Fix: Clear stale replay move on in-turn undo

- Added a regression test in `test/museum_caper/game/rules_movement_test.exs` covering the shared `move_player/6` path through `move_detective/3`: move away one space, move back to the turn-start origin, and assert that `replay_events` is empty.
- Updated `lib/museum_caper/game/rules.ex` so `move_player/6` removes the current turn's `:move` replay event for that actor when the final authoritative `movement_path` becomes empty after returning to origin.

### Covering Tests

- `mix test test/museum_caper/game/rules_movement_test.exs` -> `90 tests, 0 failures`
- `mix precommit` -> `336 tests, 0 failures`
