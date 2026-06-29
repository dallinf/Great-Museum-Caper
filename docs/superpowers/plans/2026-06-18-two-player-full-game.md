# Two-Player Full Game Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two-player Full Game support where the non-thief controls two detective pawns and each human gets one thief round.

**Architecture:** Add a `detective_controllers` map to game state. Keep rules pawn-based, and teach LiveView to resolve controlled detective pawn turns back to the human player session.

**Tech Stack:** Elixir, Phoenix LiveView, ExUnit, LazyHTML.

## Global Constraints

- Use `mix precommit` when done.
- Use `mix format` and `mix credo` before claiming Elixir changes complete.
- Do not change Limited Game two-player behavior.
- Do not change three- or four-player behavior.

---

### Task 1: State And Server Round Setup

**Files:**
- Modify: `lib/museum_caper/game/state.ex`
- Modify: `lib/museum_caper/game/server.ex`
- Modify: `lib/museum_caper/game/rules.ex`
- Test: `test/museum_caper/game/state_test.exs`
- Test: `test/museum_caper/game/server_test.exs`
- Test: `test/museum_caper/game/rules_movement_test.exs`

**Interfaces:**
- Produces: `state.detective_controllers :: %{String.t() => String.t()}`
- Produces: detective pawn IDs formatted as `"#{controller_id}:detective-1"` and `"#{controller_id}:detective-2"` for two-player full rounds.

- [ ] Write failing tests for two-player Full Game setup and role rotation.
- [ ] Run focused tests and verify they fail.
- [ ] Add state helpers and server setup options for controlled detective pawns.
- [ ] Update full-round reset logic to rebuild controlled pawns.
- [ ] Run focused tests and verify they pass.

### Task 2: LiveView Controller Resolution

**Files:**
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Test: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: `state.detective_controllers`
- Produces: `active_detective_id(state, player_id) :: String.t() | nil`
- Produces: controller-aware `my_turn?`, board clickability, setup pawn placement, movement, look, labels, and banners.

- [ ] Write failing LiveView tests for two-pawn placement and movement by one human controller.
- [ ] Run focused tests and verify they fail.
- [ ] Resolve the active detective pawn for setup and playing actions.
- [ ] Keep player list and score list human-player based.
- [ ] Run focused tests and verify they pass.

### Task 3: Verification

**Files:**
- Modify as needed based on formatter/linter/test feedback.

- [ ] Run `mix test`.
- [ ] Run `mix format`.
- [ ] Run `mix credo`.
- [ ] Run `mix precommit`.
- [ ] Fix any failures and rerun the relevant command.
