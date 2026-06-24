# Host Controlled Round Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pause non-final full-game rounds in a host-controlled review phase before starting the next setup.

**Architecture:** Add a `:round_review` phase in `MuseumCaper.Game.Rules`. Non-final full-game `finish_round/3` records the completed result and scores but leaves the game in review; a new `start_next_round/1` rule reuses the existing next-round setup constructor. `MuseumCaper.Game.Server` exposes this as `start_next_round/1`, and `MuseumCaperWeb.GameLive` renders a review panel with a host-only action.

**Tech Stack:** Elixir, Phoenix LiveView, ExUnit, Phoenix.LiveViewTest.

## Global Constraints

- Limited games remain unchanged.
- Final full-game rounds still go directly to `:game_over`.
- Only the host can continue from review to setup.
- Completed route review remains visible during `:round_review`.
- Active thief information must not be revealed.
- Run `mix format`, focused tests, `mix precommit`, `mix assets.build`, `git diff --check`, and `mix credo` if available.

---

### Task 1: Rules Round Review Phase

**Files:**
- Modify: `lib/museum_caper/game/rules.ex`
- Test: `test/museum_caper/game/rules_movement_test.exs`

**Interfaces:**
- Produces: `Rules.start_next_round(state) :: {:ok, State.t()} | {:error, :invalid_phase}`.
- Produces: non-final full-game round completion returns `%State{phase: :round_review}`.

- [ ] **Step 1: Write failing rules tests**

Add tests expecting non-final full-game escape to pause in `:round_review`, and expecting `Rules.start_next_round/1` to move review into setup.

- [ ] **Step 2: Run failing rules tests**

Run `mix test test/museum_caper/game/rules_movement_test.exs`.

Expected: FAIL because the game currently enters `:setup` immediately and `Rules.start_next_round/1` does not exist.

- [ ] **Step 3: Implement rules**

Change non-final full-game `finish_round/3` to return a review state. Add `Rules.start_next_round/1` that calls the existing `start_next_full_round/4` using the latest round result.

- [ ] **Step 4: Run rules tests**

Run `mix test test/museum_caper/game/rules_movement_test.exs`.

Expected: PASS.

### Task 2: Server And LiveView Host Continue

**Files:**
- Modify: `lib/museum_caper/game/server.ex`
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Test: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: `Rules.start_next_round/1`.
- Produces: `GameServer.start_next_round(server)`.
- Produces: LiveView event `"start_next_round"`.

- [ ] **Step 1: Write failing LiveView tests**

Add tests verifying host sees `#round-review-panel` and `#start-next-round-button`, non-host sees `#round-review-waiting`, and host click moves the game to `:setup`.

- [ ] **Step 2: Run failing LiveView tests**

Run `mix test test/museum_caper_web/live/game_live_test.exs`.

Expected: FAIL because the review phase/panel/action are not wired yet.

- [ ] **Step 3: Implement server and LiveView**

Expose `GameServer.start_next_round/1`, add a server call handler, add LiveView handling for `"start_next_round"`, and render a `round_review_panel/1` for `:round_review`.

- [ ] **Step 4: Run LiveView tests**

Run `mix test test/museum_caper_web/live/game_live_test.exs`.

Expected: PASS.

### Task 3: Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Format**

Run `mix format`.

- [ ] **Step 2: Focused tests**

Run:

```bash
mix test test/museum_caper/game/rules_movement_test.exs
mix test test/museum_caper_web/live/game_live_test.exs
```

- [ ] **Step 3: Project checks**

Run:

```bash
mix credo
mix precommit
mix assets.build
git diff --check
```

Expected: all available checks pass. If `mix credo` is unavailable, report the exact Mix error.
