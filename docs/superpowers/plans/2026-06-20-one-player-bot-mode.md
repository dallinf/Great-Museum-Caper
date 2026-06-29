# One-Player Bot Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-human start mode that creates two bot players and lets bots take automatic legal turns.

**Architecture:** Mark bot players in game state, add a server-side bot start path, and run bot decisions from the game server after successful mutations. Keep legality in `MuseumCaper.Game.Rules`; `MuseumCaper.Game.Bot` only chooses from legal actions and returns one action at a time.

**Tech Stack:** Elixir, Phoenix LiveView, GenServer, ExUnit, Phoenix.LiveViewTest, Tailwind CSS.

## Global Constraints

- Use `mix precommit` alias when done with all changes.
- Use existing Phoenix LiveView patterns and keep templates inside `<Layouts.app flash={@flash} ...>`.
- Use `<.icon>` for icons and existing `<.input>` for inputs.
- Use Tailwind classes; do not add daisyUI usage or inline scripts.
- Use test-first implementation for behavior changes.
- Human-only multiplayer behavior remains unchanged.
- Existing two-player controlled-detective behavior remains unchanged when two human players start a game.

---

## File Structure

- Create `lib/museum_caper/game/bot.ex`: bot decision module. Consumes game state and produces action tuples such as `{:toggle_lock, entry_id}`, `{:move_detective, detective_id, destination}`, or `:end_turn`.
- Modify `lib/museum_caper/game/server.ex`: add bot metadata helpers, bot-start validation, bot scheduling, and action execution.
- Modify `lib/museum_caper_web/live/game_live.ex`: add one-player bot start control, bot badge, and user-facing bot-start errors.
- Test `test/museum_caper/game/server_test.exs`: server start validation and bot metadata.
- Test `test/museum_caper/game/bot_test.exs`: bot choices and auto progression.
- Test `test/museum_caper_web/live/game_live_test.exs`: button visibility and bot badges.

---

### Task 1: Bot Player Start Path

**Files:**
- Modify: `lib/museum_caper/game/server.ex`
- Test: `test/museum_caper/game/server_test.exs`

**Interfaces:**
- Consumes: `Server.start_game(server, player_id, opts \\ [])`
- Produces: `Server.start_game(server, player_id, with_bots?: true, game_mode: :limited | :full)`
- Produces player maps with `bot?: true | false`

- [x] **Step 1: Write failing server tests**

Add tests to `test/museum_caper/game/server_test.exs`:

```elixir
test "one human host can start a game with two bots" do
  game_id = "bot-start-#{System.unique_integer()}"
  pid = start_game_server!(game_id, %{})

  assert :ok = Server.add_player(pid, "alice", "Alice", :purple)

  assert {:ok, state} =
           Server.start_game(pid, "alice",
             with_bots?: true,
             shuffle: fn order -> order end
           )

  assert state.phase == :setup
  assert map_size(state.players) == 3
  assert state.players["alice"].bot? == false
  assert state.players["bot-1"].bot? == true
  assert state.players["bot-2"].bot? == true
  assert state.players["bot-1"].name == "Bot 1"
  assert state.players["bot-2"].name == "Bot 2"
end

test "bot start requires exactly one human player" do
  game_id = "bot-start-invalid-#{System.unique_integer()}"
  pid = start_game_server!(game_id, %{})

  assert :ok = Server.add_player(pid, "alice", "Alice", :purple)
  assert :ok = Server.add_player(pid, "bob", "Bob", :green)

  assert {:error, :bots_require_one_human} =
           Server.start_game(pid, "alice", with_bots?: true)

  assert Server.get_state(pid).phase == :lobby
end
```

- [x] **Step 2: Run tests to verify failure**

Run:

```bash
mix test test/museum_caper/game/server_test.exs
```

Expected: failures because `bot?` is missing and `with_bots?: true` still follows normal start behavior.

- [x] **Step 3: Implement minimal bot start support**

In `lib/museum_caper/game/server.ex`:

```elixir
defp start_lobby_game(%State{phase: :lobby} = game_state, player_id, opts) do
  game_state =
    if Keyword.get(opts, :with_bots?, false) do
      add_bot_players(game_state)
    else
      game_state
    end

  start_lobby_game_after_bot_setup(game_state, player_id, opts)
end
```

Add helpers that validate one human, preserve host checks, add `bot-1` and `bot-2`, and default human joins to `bot?: false`.

- [x] **Step 4: Run tests to verify pass**

Run:

```bash
mix test test/museum_caper/game/server_test.exs
```

Expected: all server tests pass.

---

### Task 2: Bot Decision Module

**Files:**
- Create: `lib/museum_caper/game/bot.ex`
- Test: `test/museum_caper/game/bot_test.exs`

**Interfaces:**
- Consumes: `%MuseumCaper.Game.State{}`
- Produces: `MuseumCaper.Game.Bot.next_action(state) :: action | nil`
- Action tuples:
  - `{:toggle_lock, entry_id}`
  - `{:place_painting, pos}`
  - `{:place_camera, camera_id, pos}`
  - `{:place_detective_pawn, detective_id, pos}`
  - `{:enter_museum, entry_id}`
  - `{:move_thief, pos}`
  - `{:move_detective, detective_id, pos}`
  - `{:use_eye_action, detective_id}`
  - `:use_camera_scan`
  - `:use_motion_detector`
  - `{:decide_motion_detector, player_id, :allow}`
  - `:end_turn`

- [x] **Step 1: Write failing bot tests**

Create `test/museum_caper/game/bot_test.exs` with tests for setup and turn choices:

```elixir
defmodule MuseumCaper.Game.BotTest do
  use ExUnit.Case, async: true
  alias MuseumCaper.Game.{Bot, Board, Rules, State}

  test "chooses lock placement during detective setup" do
    state = bot_setup_state()

    assert {:toggle_lock, entry_id} = Bot.next_action(state)
    assert entry_id in Enum.map(Board.entries(), & &1.id)
  end

  test "chooses thief entry when bot thief is entering" do
    state = %{bot_setup_state() | phase: :thief_entry, thief_player_id: "bot-1"}

    assert {:enter_museum, entry_id} = Bot.next_action(state)
    assert Board.entry_by_id(entry_id) != nil
  end

  test "chooses detective movement during a bot detective turn" do
    state =
      bot_playing_state()
      |> Map.put(:current_turn, "bot-1")
      |> Map.put(:turn_actions_remaining, [:move])
      |> Map.put(:dice, {1, nil})

    assert {:move_detective, "bot-1", destination} = Bot.next_action(state)
    assert destination in Rules.valid_detective_destinations(state, "bot-1")
  end
end
```

- [x] **Step 2: Run tests to verify failure**

Run:

```bash
mix test test/museum_caper/game/bot_test.exs
```

Expected: compile failure because `MuseumCaper.Game.Bot` does not exist.

- [x] **Step 3: Implement bot decisions**

Create `lib/museum_caper/game/bot.ex` with deterministic candidate lists and one-action decisions. Use `Rules.valid_thief_destinations/1`, `Rules.valid_detective_destinations/2`, `Board.entries/0`, `Board.painting_placeable_cell?/1`, `Board.camera_placeable_cell?/1`, and `Board.detective_placeable_cell?/1`.

- [x] **Step 4: Run tests to verify pass**

Run:

```bash
mix test test/museum_caper/game/bot_test.exs
```

Expected: bot decision tests pass.

---

### Task 3: Server Bot Runner

**Files:**
- Modify: `lib/museum_caper/game/server.ex`
- Test: `test/museum_caper/game/bot_test.exs`

**Interfaces:**
- Consumes: `Bot.next_action/1`
- Produces: delayed internal `:run_bots` handling after mutations
- Produces automatic state progression until a human actor is current

- [x] **Step 1: Write failing auto-run tests**

Add to `test/museum_caper/game/bot_test.exs`:

```elixir
test "server automatically advances bot setup actions after bot start" do
  game_id = "bot-auto-#{System.unique_integer()}"
  pid = start_supervised!(%{
    id: {MuseumCaper.Game.Server, game_id},
    start: {MuseumCaper.Game.Server, :start_link, [[game_id: game_id, players: %{}]]}
  })

  assert :ok = MuseumCaper.Game.Server.add_player(pid, "alice", "Alice", :purple)
  assert {:ok, _state} =
           MuseumCaper.Game.Server.start_game(pid, "alice",
             with_bots?: true,
             shuffle: fn _order -> ["alice", "bot-1", "bot-2"] end
           )

  _ = :sys.get_state(pid)
  state = MuseumCaper.Game.Server.get_state(pid)

  assert state.phase in [:setup, :thief_entry, :playing, :game_over]
  assert Enum.count(state.locks, fn {_id, status} -> status == :locked end) > 0
end
```

- [x] **Step 2: Run tests to verify failure**

Run:

```bash
mix test test/museum_caper/game/bot_test.exs
```

Expected: failure because no bot runner schedules or applies actions.

- [x] **Step 3: Implement scheduling and action execution**

In `server.ex`, alias `Bot`, add `handle_info(:run_bots, server_state)`, call `schedule_bots(server_state)` after successful mutations, and execute action tuples by calling `Rules` functions directly inside the GenServer state.

- [x] **Step 4: Run tests to verify pass**

Run:

```bash
mix test test/museum_caper/game/bot_test.exs test/museum_caper/game/server_test.exs
```

Expected: all bot and server tests pass.

---

### Task 4: LiveView Bot Start UI

**Files:**
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Test: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: `Server.start_game(server, player_id, with_bots?: true, game_mode: :limited)`
- Produces: `phx-click="start_game"` with `phx-value-bots="true"`

- [x] **Step 1: Write failing LiveView tests**

Add tests:

```elixir
test "single host can start with bots from the waiting room", %{conn: conn, game_id: game_id} do
  {:ok, pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

  {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

  assert has_element?(alice_view, "#start-bot-game-button:not([disabled])", "Start with Bots")

  render_click(element(alice_view, "#start-bot-game-button"))

  state = GameServer.get_state(pid)
  assert map_size(state.players) == 3
  assert state.players["bot-1"].bot? == true
  assert has_element?(alice_view, "#player-row-bot-1 [data-player-bot-badge]", "Bot")
end

test "bot start is hidden once a second human joins", %{conn: conn, game_id: game_id} do
  {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

  {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
  {:ok, _bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")

  refute has_element?(alice_view, "#start-bot-game-button")
end
```

- [x] **Step 2: Run tests to verify failure**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: failure because the bot start button and badges do not exist.

- [x] **Step 3: Implement UI and event params**

In `handle_event("start_game", params, socket)`, detect `params["bots"] == "true"` and pass `with_bots?: true`. In the waiting-room template, render `#start-bot-game-button` only when `one_human_player?(state)` and host. In the player row, render a `data-player-bot-badge` when `Map.get(player, :bot?, false)`.

- [x] **Step 4: Run tests to verify pass**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: LiveView tests pass.

---

### Task 5: Final Verification

**Files:**
- Verify: `lib/museum_caper/game/server.ex`
- Verify: `lib/museum_caper/game/bot.ex`
- Verify: `lib/museum_caper_web/live/game_live.ex`
- Verify: `test/museum_caper/game/server_test.exs`
- Verify: `test/museum_caper/game/bot_test.exs`
- Verify: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Consumes all previous tasks.
- Produces a clean project check.

- [x] **Step 1: Run focused tests**

Run:

```bash
mix test test/museum_caper/game/server_test.exs test/museum_caper/game/bot_test.exs test/museum_caper_web/live/game_live_test.exs
```

Expected: all focused tests pass.

- [x] **Step 2: Run project precommit**

Run:

```bash
mix precommit
```

Expected: format, compile, and test checks pass according to the project alias.

- [x] **Step 3: Check git status**

Run:

```bash
git status --short
```

Expected: only intentional bot-mode files are modified or untracked; pre-existing untracked docs remain separate.
