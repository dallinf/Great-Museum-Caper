# Full Game Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully revealed animated replay that detectives can watch after each round and at game over.

**Architecture:** The rules layer records an authoritative replay timeline as game actions happen. Completed round results carry the replay events, LiveView exposes replay controls only during `:round_review` and `:game_over`, and a browser hook plays those already-revealed events on the existing board. The thief remains hidden during live play because replay payloads are not rendered while `state.phase == :playing`.

**Tech Stack:** Elixir, Phoenix LiveView, HEEx, Tailwind CSS v4, JavaScript ES modules, Node `node:test`.

## Global Constraints

- Detectives can watch a fully revealed animated replay after each full-game round and at final game over.
- Replay is not available during live play.
- Preserve a complete ordered replay timeline while the round is played.
- Show replay controls during `:round_review` and `:game_over` only.
- Animate all pawn movement paths using the existing board movement animation primitives.
- Keep hidden information hidden until the round is over.
- No live-game replay or partial replay while a round is still in progress.
- No reconstruction of historical games that were played before this feature exists.
- No speculative replay derived from incomplete state. The server timeline is authoritative.
- The replay surface should reuse the existing board, not create a separate board.
- Use only the existing app.js and app.css bundles.
- Do not write inline `<script>` tags in HEEx templates.
- Use `mix precommit` when done with all changes.

---

## File Structure

- Create `lib/museum_caper/game/replay.ex` for replay event construction, actor labels, event ids, movement-event replacement, and payload formatting helpers.
- Modify `lib/museum_caper/game/state.ex` to add `replay_events` and `turn_index` to in-memory game state.
- Modify `lib/museum_caper/game/rules.ex` to record replay events at authoritative state mutations and attach replay events to round results.
- Modify `lib/museum_caper_web/live/game_live.ex` to expose replay controls and selected replay payloads only after a round is complete.
- Create `assets/js/replay_playback.js` for pure playback state helpers that are easy to test.
- Create `assets/js/replay_playback_test.mjs` for Node tests.
- Create `assets/js/hooks/replay_playback_hook.js` for DOM playback on the existing board.
- Modify `assets/js/app.js` to register `ReplayPlaybackHook`.
- Modify `assets/css/app.css` for replay overlay and control states.
- Add tests in `test/museum_caper/game/replay_test.exs`, `test/museum_caper/game/rules_movement_test.exs`, and `test/museum_caper_web/live/game_live_test.exs`.

---

### Task 1: Replay Event Foundation

**Files:**
- Create: `lib/museum_caper/game/replay.ex`
- Modify: `lib/museum_caper/game/state.ex`
- Test: `test/museum_caper/game/replay_test.exs`

**Interfaces:**
- Consumes: `%MuseumCaper.Game.State{players: map(), detective_controllers: map(), replay_events: list(), turn_index: integer(), round_number: integer()}`
- Produces:
  - `MuseumCaper.Game.Replay.append_event(state, attrs) :: state`
  - `MuseumCaper.Game.Replay.put_movement_event(state, role, actor_id, path) :: state`
  - `MuseumCaper.Game.Replay.payload_events(events, state) :: list(map())`
  - State fields `:replay_events` and `:turn_index`

- [ ] **Step 1: Write the failing replay helper tests**

Create `test/museum_caper/game/replay_test.exs`:

```elixir
defmodule MuseumCaper.Game.ReplayTest do
  use ExUnit.Case, async: true

  alias MuseumCaper.Game.{Replay, State}

  @players %{
    "t" => %{name: "Theo", role: :thief, color: :grey},
    "d" => %{name: "Alice", role: :detective, color: :red}
  }

  test "append_event fills stable replay metadata" do
    state =
      @players
      |> State.new_game(["t", "d"], "t", game_mode: :full)
      |> Map.merge(%{phase: :playing, current_turn: "t", turn_index: 2})

    state =
      Replay.append_event(state, %{
        type: :enter,
        actor_id: "t",
        actor_role: :thief,
        path: [{6, 1}, {6, 2}],
        from: {6, 1},
        to: {6, 2},
        result: nil,
        label: "Theo entered through D2."
      })

    assert [
             %{
               id: 1,
               round_number: 1,
               turn_index: 2,
               actor_id: "t",
               actor_role: :thief,
               actor_label: "Theo",
               type: :enter,
               path: [{6, 1}, {6, 2}],
               from: {6, 1},
               to: {6, 2},
               result: nil,
               label: "Theo entered through D2."
             }
           ] = state.replay_events
  end

  test "put_movement_event replaces the current turn movement for the same actor" do
    state =
      @players
      |> State.new_game(["t", "d"], "t", game_mode: :full)
      |> Map.merge(%{phase: :playing, current_turn: "t", turn_index: 1})

    state = Replay.put_movement_event(state, :thief, "t", [{6, 2}, {6, 3}])
    state = Replay.put_movement_event(state, :thief, "t", [{6, 2}, {6, 3}, {6, 4}])

    assert [
             %{
               id: 1,
               type: :move,
               actor_id: "t",
               actor_role: :thief,
               path: [{6, 2}, {6, 3}, {6, 4}],
               from: {6, 2},
               to: {6, 4},
               label: "Theo moved 2 spaces."
             }
           ] = state.replay_events
  end

  test "payload_events converts positions and atom fields for JSON encoding" do
    state =
      @players
      |> State.new_game(["t", "d"], "t", game_mode: :full)
      |> Replay.append_event(%{
        type: :move,
        actor_id: "d",
        actor_role: :detective,
        path: [{3, 9}, {3, 8}],
        from: {3, 9},
        to: {3, 8},
        result: nil,
        label: "Alice moved 1 space."
      })

    assert [
             %{
               id: 1,
               type: "move",
               actor_id: "d",
               actor_role: "detective",
               actor_label: "Alice",
               actor_color: "red",
               path: "3-9 3-8",
               from: "3-9",
               to: "3-8",
               label: "Alice moved 1 space."
             }
           ] = Replay.payload_events(state.replay_events, state)
  end
end
```

- [ ] **Step 2: Run the new test and verify RED**

Run:

```bash
mix test test/museum_caper/game/replay_test.exs
```

Expected: failure because `MuseumCaper.Game.Replay` does not exist.

- [ ] **Step 3: Add replay fields to state**

Modify `lib/museum_caper/game/state.ex`:

```elixir
defstruct players: %{},
          turn_order: [],
          current_turn: nil,
          phase: :lobby,
          setup_step: :locks,
          host_player_id: nil,
          game_mode: :limited,
          thief_rotation: [],
          round_number: 1,
          artwork_scores: %{},
          round_results: [],
          winning_player_ids: [],
          thief_player_id: nil,
          thief_position: nil,
          motion_snips_remaining: 2,
          motion_detector_decision: nil,
          detective_result: nil,
          detective_result_id: 0,
          game_log: [],
          pending_steal: nil,
          stolen_count: 0,
          locks: %{},
          paintings: %{},
          painting_labels: %{},
          cameras: %{},
          detective_positions: %{},
          detective_controllers: %{},
          power_active: true,
          power_revealed: false,
          chase_mode: false,
          dice: nil,
          turn_actions_remaining: [],
          movement_path: [],
          movement_spent: 0,
          thief_history: @empty_thief_history,
          replay_events: [],
          turn_index: 0,
          winner: nil,
          game_over_reason: nil
```

In `new_game/4`, include opts:

```elixir
replay_events: Keyword.get(opts, :replay_events, []),
turn_index: Keyword.get(opts, :turn_index, 0),
```

- [ ] **Step 4: Implement `MuseumCaper.Game.Replay`**

Create `lib/museum_caper/game/replay.ex`:

```elixir
defmodule MuseumCaper.Game.Replay do
  @moduledoc false

  alias MuseumCaper.Game.PawnColors

  def append_event(state, attrs) do
    event =
      attrs
      |> normalize_event(state)
      |> Map.put(:id, next_event_id(state))

    %{state | replay_events: state.replay_events ++ [event]}
  end

  def put_movement_event(_state, _role, _actor_id, path) when length(path) < 2 do
    _state
  end

  def put_movement_event(state, role, actor_id, path) do
    attrs = %{
      type: :move,
      actor_id: actor_id,
      actor_role: role,
      path: path,
      from: List.first(path),
      to: List.last(path),
      result: nil,
      label: "#{actor_label(state, actor_id)} moved #{length(path) - 1} #{space_word(length(path) - 1)}."
    }

    event = normalize_event(attrs, state)

    case current_movement_event_index(state, actor_id) do
      nil ->
        append_event(state, attrs)

      index ->
        replacement =
          state.replay_events
          |> Enum.at(index)
          |> Map.take([:id])
          |> Map.merge(event)

        %{state | replay_events: List.replace_at(state.replay_events, index, replacement)}
    end
  end

  def payload_events(events, state) do
    Enum.map(events, &payload_event(&1, state))
  end

  defp normalize_event(attrs, state) do
    attrs
    |> Map.put_new(:round_number, state.round_number)
    |> Map.put_new(:turn_index, state.turn_index)
    |> Map.put_new(:actor_label, actor_label(state, Map.fetch!(attrs, :actor_id)))
    |> Map.put_new(:path, [])
    |> Map.put_new(:from, nil)
    |> Map.put_new(:to, nil)
    |> Map.put_new(:result, nil)
    |> Map.put_new(:label, nil)
  end

  defp next_event_id(state), do: length(state.replay_events) + 1

  defp current_movement_event_index(state, actor_id) do
    Enum.find_index(state.replay_events, fn event ->
      event.type == :move and event.turn_index == state.turn_index and event.actor_id == actor_id
    end)
  end

  defp payload_event(event, state) do
    %{
      id: event.id,
      round_number: event.round_number,
      turn_index: event.turn_index,
      actor_id: event.actor_id,
      actor_role: Atom.to_string(event.actor_role),
      actor_label: event.actor_label,
      actor_color: actor_color(state, event.actor_id),
      type: Atom.to_string(event.type),
      path: position_path(event.path),
      from: position_key(event.from),
      to: position_key(event.to),
      result: atom_string(event.result),
      label: event.label
    }
  end

  defp actor_label(state, actor_id) do
    player_id = Map.get(state.detective_controllers, actor_id, actor_id)

    case Map.get(state.players, player_id) do
      %{name: name} -> name
      nil -> actor_id
    end
  end

  defp actor_color(state, actor_id) do
    player_id = Map.get(state.detective_controllers, actor_id, actor_id)

    case Map.get(state.players, player_id) do
      %{color: color} -> PawnColors.to_param(color)
      nil -> "grey"
    end
  end

  defp position_path(path), do: Enum.map_join(path, " ", &position_key/1)
  defp position_key(nil), do: nil
  defp position_key({row, col}), do: "#{row}-#{col}"

  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_string(value), do: value

  defp space_word(1), do: "space"
  defp space_word(_count), do: "spaces"
end
```

- [ ] **Step 5: Run the new test and verify GREEN**

Run:

```bash
mix test test/museum_caper/game/replay_test.exs
```

Expected: `3 tests, 0 failures`.

- [ ] **Step 6: Run formatting**

Run:

```bash
mix format
```

Expected: exit code `0`.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add lib/museum_caper/game/state.ex lib/museum_caper/game/replay.ex test/museum_caper/game/replay_test.exs
git commit -m "feat: add replay event foundation"
```

---

### Task 2: Record Replay Events in Rules

**Files:**
- Modify: `lib/museum_caper/game/rules.ex`
- Test: `test/museum_caper/game/rules_movement_test.exs`

**Interfaces:**
- Consumes: `MuseumCaper.Game.Replay.append_event/2` and `MuseumCaper.Game.Replay.put_movement_event/4`
- Produces: replay events for entry, movement, lock checks, steals, power changes, captures, escapes, round ends, and `round_result.replay_events`

- [ ] **Step 1: Write failing rules tests**

Append these tests to the existing replay-adjacent areas in `test/museum_caper/game/rules_movement_test.exs`:

```elixir
test "entering the museum records a replay entry event" do
  state = %{State.new_game(@players) | phase: :thief_entry}

  assert {:ok, state} = Rules.enter_museum(state, :exit_w1)

  assert [
           %{
             type: :enter,
             actor_id: "t",
             actor_role: :thief,
             path: [{6, 1}, {6, 2}],
             from: {6, 1},
             to: {6, 2},
             label: "Thief entered through D2."
           }
         ] = state.replay_events
end

test "detective movement records the final replay path for the turn" do
  state = %{
    base_state()
    | current_turn: "d1",
      dice: {4, :eye},
      turn_actions_remaining: [:move],
      detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}}
  }

  assert {:ok, state} = Rules.move_detective(state, "d1", {3, 8})
  assert {:ok, state} = Rules.move_detective(state, "d1", {3, 7})

  assert [
           %{
             type: :move,
             actor_id: "d1",
             actor_role: :detective,
             path: [{3, 9}, {3, 8}, {3, 7}],
             from: {3, 9},
             to: {3, 7}
           }
         ] = state.replay_events
end

test "locked escape records a lock check but not an escape event" do
  state = %{
    base_state()
    | current_turn: "t",
      turn_order: ["t", "d1", "t", "d2"],
      thief_position: {1, 5},
      locks: Map.put(base_state().locks, :window_1_5, :locked)
  }

  assert {:ok, :locked, state} = Rules.try_escape(state, :window_1_5)

  assert [%{type: :lock_check, actor_id: "t", result: :locked, to: {1, 5}}] =
           state.replay_events

  refute Enum.any?(state.replay_events, &(&1.type == :escape))
end

test "successful full game escape stores replay events on the round result" do
  state =
    full_round_state("alice", 1)
    |> Map.merge(%{
      current_turn: "alice",
      thief_position: {1, 5},
      stolen_count: 2,
      locks: Map.put(base_state().locks, :window_1_5, :open),
      replay_events: [
        %{
          id: 1,
          round_number: 1,
          turn_index: 0,
          actor_id: "alice",
          actor_role: :thief,
          actor_label: "Alice",
          type: :enter,
          path: [{1, 5}],
          from: {1, 5},
          to: {1, 5},
          result: nil,
          label: "Alice entered through W1."
        }
      ]
    })

  assert {:ok, :escaped, state} = Rules.try_escape(state, :window_1_5)

  assert [%{replay_events: events}] = state.round_results
  assert Enum.any?(events, &(&1.type == :lock_check and &1.result == :open))
  assert Enum.any?(events, &(&1.type == :escape and &1.to == {1, 5}))
  assert Enum.any?(events, &(&1.type == :round_end and &1.result == :escaped))
end

test "starting the next full round resets replay events and turn index" do
  state =
    full_round_state("alice", 1)
    |> Map.merge(%{
      phase: :round_review,
      round_results: [
        %{
          round_number: 1,
          thief_player_id: "alice",
          stolen_count: 2,
          outcome: :thief,
          reason: :escaped,
          thief_history: %{entry: nil, exit: nil, moves: []},
          replay_events: [%{id: 1, type: :round_end}]
        }
      ],
      replay_events: [%{id: 1, type: :round_end}],
      turn_index: 4
    })

  assert {:ok, state} = Rules.start_next_round(state)
  assert state.replay_events == []
  assert state.turn_index == 0
end
```

- [ ] **Step 2: Run the failing rules tests**

Run:

```bash
mix test test/museum_caper/game/rules_movement_test.exs
```

Expected: failures for missing replay events in rules.

- [ ] **Step 3: Import the replay helper in rules**

Modify the alias at the top of `lib/museum_caper/game/rules.ex`:

```elixir
alias MuseumCaper.Game.{Board, PawnColors, Replay, State}
```

- [ ] **Step 4: Record entry and movement events**

In `enter_museum/2`, after building the new state, append an entry event:

```elixir
state =
  state
  |> Replay.append_event(%{
    type: :enter,
    actor_id: state.thief_player_id,
    actor_role: :thief,
    path: entry_path(entry, pos),
    from: Board.exit_door_cell(entry),
    to: pos,
    result: nil,
    label: "#{player_name(state, state.thief_player_id)} entered through #{entry.label}."
  })
```

Add helper near `thief_entry_history/2`:

```elixir
defp entry_path(%{type: :door} = entry, pos), do: [Board.exit_door_cell(entry), pos]
defp entry_path(_entry, pos), do: [pos]
```

In `move_player/6`, after `put_player_position/4`, record movement:

```elixir
state = put_player_position(state, role, player_id, destination)

if state.movement_path == [] do
  state
else
  Replay.put_movement_event(state, role, player_id, state.movement_path)
end
```

- [ ] **Step 5: Record escape and lock-check events**

In `try_escape/2`, before each result branch returns, record lock checks:

```elixir
state =
  Replay.append_event(state, %{
    type: :lock_check,
    actor_id: state.thief_player_id,
    actor_role: :thief,
    path: [state.thief_position],
    from: state.thief_position,
    to: state.thief_position,
    result: Map.get(state.locks, exit_id, :open),
    label: "#{player_name(state, state.thief_player_id)} checked the #{entry.label} lock."
  })
```

In `finish_escape/2`, append the escape event before `finish_round/3`:

```elixir
state =
  state
  |> commit_thief_movement()
  |> put_thief_exit_history(entry)
  |> resolve_pending_steal()
  |> Replay.append_event(%{
    type: :escape,
    actor_id: state.thief_player_id,
    actor_role: :thief,
    path: [state.thief_position],
    from: state.thief_position,
    to: Board.exit_door_cell(entry),
    result: :escaped,
    label: "#{player_name(state, state.thief_player_id)} escaped through #{entry.label}."
  })
```

- [ ] **Step 6: Record steal, power, capture, and round end events**

In `resolve_pending_steal/1`, after removing the artwork, append:

```elixir
|> Replay.append_event(%{
  type: :steal,
  actor_id: state.thief_player_id,
  actor_role: :thief,
  path: [pos],
  from: pos,
  to: pos,
  result: :stolen,
  label: "#{player_name(state, state.thief_player_id)} stole #{label}."
})
```

In `turn_power_off_on_power_room/2` and `turn_power_on_on_power_room/2`, when the power state changes, append:

```elixir
Replay.append_event(%{state | power_active: false}, %{
  type: :power,
  actor_id: state.thief_player_id,
  actor_role: :thief,
  path: [pos],
  from: pos,
  to: pos,
  result: :off,
  label: "Power turned off."
})
```

For detective power-on, use the detective id from the caller. If the current helper lacks that id, add a private helper:

```elixir
defp turn_power_on_from_detective_action(state, detective_id) do
  pos = Map.get(state.detective_positions, detective_id)

  if state.power_active == false and power_room?(pos) do
    %{state | power_active: true, power_revealed: false}
    |> Replay.append_event(%{
      type: :power,
      actor_id: detective_id,
      actor_role: :detective,
      path: [pos],
      from: pos,
      to: pos,
      result: :on,
      label: "Power turned on."
    })
  else
    state
  end
end
```

In `catch_thief/1`, append capture before `finish_round/3`:

```elixir
state =
  Replay.append_event(state, %{
    type: :capture,
    actor_id: state.current_turn,
    actor_role: :detective,
    path: [state.thief_position],
    from: state.thief_position,
    to: state.thief_position,
    result: :caught,
    label: "Detectives caught #{player_name(state, state.thief_player_id)}."
  })

finish_round(state, :detectives, :caught)
```

At the start of `finish_round/3`, append a round-end event through a helper:

```elixir
defp finish_round(state, outcome, reason) do
  state = put_round_end_replay_event(state, outcome, reason)
  ...
end
```

Helper:

```elixir
defp put_round_end_replay_event(state, outcome, reason) do
  Replay.append_event(state, %{
    type: :round_end,
    actor_id: state.thief_player_id,
    actor_role: :thief,
    path: [],
    from: nil,
    to: nil,
    result: reason,
    label: round_result_message(state, %{
      round_number: state.round_number,
      thief_player_id: state.thief_player_id,
      stolen_count: scored_stolen_count(outcome, state.stolen_count),
      outcome: outcome
    })
  })
end
```

- [ ] **Step 7: Attach replay events to round results and advance turn index**

In full-game `round_result`, include:

```elixir
replay_events: state.replay_events
```

In limited-game `finish_round/3`, keep `state.replay_events` on state so game-over replay can use it.

In `advance_turn/1`, increment:

```elixir
turn_index: state.turn_index + 1,
```

In `start_next_full_round/4`, pass no `replay_events` and no `turn_index` opts so they reset to defaults.

- [ ] **Step 8: Run rules tests and verify GREEN**

Run:

```bash
mix test test/museum_caper/game/replay_test.exs test/museum_caper/game/rules_movement_test.exs
```

Expected: all tests pass.

- [ ] **Step 9: Run formatting**

Run:

```bash
mix format
```

Expected: exit code `0`.

- [ ] **Step 10: Commit Task 2**

Run:

```bash
git add lib/museum_caper/game/rules.ex test/museum_caper/game/rules_movement_test.exs
git commit -m "feat: record replay timeline events"
```

---

### Task 3: LiveView Replay Availability and Payload

**Files:**
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Test: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: `round_result.replay_events`, `state.replay_events`, `Replay.payload_events/2`, and existing selected round behavior.
- Produces:
  - Replay controls only during `:round_review` and `:game_over`
  - `#replay-panel`
  - `#replay-round-button`
  - `#replay-playback`
  - `data-replay-events`
  - `data-replay-event-count`

- [ ] **Step 1: Write failing LiveView tests**

Add tests near the route review tests in `test/museum_caper_web/live/game_live_test.exs`:

```elixir
test "replay controls are hidden during active play", %{conn: conn, game_id: game_id} do
  pid = start_two_player_full_game!(game_id)
  advance_to_pawns(pid)

  assert {:ok, _state} =
           GameServer.place_detective_pawn(pid, "player-bob:detective-1", {3, 9})

  assert {:ok, _state} =
           GameServer.place_detective_pawn(pid, "player-bob:detective-2", {9, 5})

  assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)

  {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

  refute has_element?(alice_view, "#replay-panel")
  refute has_element?(alice_view, "#replay-playback")
end

test "round review exposes replay payload for the latest completed round", %{
  conn: conn,
  game_id: game_id
} do
  pid = start_two_player_full_game!(game_id)

  :sys.replace_state(pid, fn server_state ->
    replay_events = [
      %{
        id: 1,
        round_number: 1,
        turn_index: 0,
        actor_id: "player-alice",
        actor_role: :thief,
        actor_label: "Alice",
        type: :enter,
        path: [{6, 1}, {6, 2}],
        from: {6, 1},
        to: {6, 2},
        result: nil,
        label: "Alice entered through D2."
      }
    ]

    game_state = %{
      server_state.game_state
      | phase: :round_review,
        round_number: 2,
        round_results: [
          %{
            round_number: 1,
            thief_player_id: "player-alice",
            stolen_count: 0,
            outcome: :detectives,
            reason: :caught,
            thief_history: %{entry: nil, exit: nil, moves: []},
            replay_events: replay_events
          }
        ]
    }

    %{server_state | game_state: game_state}
  end)

  {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

  assert has_element?(alice_view, "#replay-panel")
  assert has_element?(alice_view, "#replay-round-button", "Replay round")
  assert has_element?(alice_view, "#replay-playback[phx-hook='ReplayPlaybackHook']")
  assert has_element?(alice_view, "#replay-playback[data-replay-event-count='1']")
  assert has_element?(alice_view, "#replay-playback[data-replay-events*='Alice entered through D2.']")
end

test "game over exposes limited game replay events", %{conn: conn, game_id: game_id} do
  pid = start_fixed_setup_game!(game_id)

  :sys.replace_state(pid, fn server_state ->
    replay_events = [
      %{
        id: 1,
        round_number: 1,
        turn_index: 0,
        actor_id: "player-theo",
        actor_role: :thief,
        actor_label: "Theo",
        type: :escape,
        path: [{1, 5}],
        from: {1, 5},
        to: {1, 5},
        result: :escaped,
        label: "Theo escaped through W1."
      }
    ]

    game_state = %{
      server_state.game_state
      | phase: :game_over,
        winner: :thief,
        game_over_reason: :escaped,
        replay_events: replay_events
    }

    %{server_state | game_state: game_state}
  end)

  {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

  assert has_element?(thief_view, "#replay-panel")
  assert has_element?(thief_view, "#replay-playback[data-replay-event-count='1']")
  assert has_element?(thief_view, "#replay-playback[data-replay-events*='Theo escaped through W1.']")
end
```

- [ ] **Step 2: Run the failing LiveView tests**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: failures for missing replay controls and hook.

- [ ] **Step 3: Import Replay and add replay assigns**

Modify aliases in `lib/museum_caper_web/live/game_live.ex`:

```elixir
alias MuseumCaper.Game.{Board, PawnColors, Replay, Server}
```

In the connected mount path and `handle_info/2`, assign selected replay data using the existing selected round:

```elixir
replay_payload = selected_replay_payload(game_state, selected_revealed_round)

assign(socket,
  game_state: game_state,
  selected_revealed_round: selected_revealed_round,
  revealed_route_marks: revealed_route_marks(game_state, selected_revealed_round),
  replay_payload: replay_payload
)
```

- [ ] **Step 4: Add replay panel component**

Add this component near `route_round_selector/1`:

```elixir
attr :game_state, :map, required: true
attr :selected_revealed_round, :integer, default: nil
attr :replay_payload, :list, default: []

def replay_panel(assigns) do
  ~H"""
  <section
    :if={@replay_payload != []}
    id="replay-panel"
    class="space-y-2 rounded-lg border border-sky-300/30 bg-sky-300/10 p-3"
  >
    <div class="flex items-center justify-between gap-2">
      <h3 class="text-[0.68rem] font-black uppercase tracking-[0.16em] text-sky-100">
        Replay
      </h3>
      <button
        id="replay-round-button"
        type="button"
        data-replay-command="restart"
        class="rounded-md bg-sky-300 px-2 py-1 text-xs font-black text-stone-950 transition hover:bg-sky-200"
      >
        Replay round
      </button>
    </div>
    <div
      id="replay-playback"
      phx-hook="ReplayPlaybackHook"
      phx-update="ignore"
      data-replay-events={replay_events_json(@replay_payload)}
      data-replay-event-count={length(@replay_payload)}
      class="space-y-2"
    >
      <p data-replay-caption class="min-h-5 text-sm font-semibold text-sky-50"></p>
      <div class="flex flex-wrap items-center gap-1">
        <button type="button" data-replay-command="back" class={replay_control_class()}>
          <.icon name="hero-backward" class="size-4" />
        </button>
        <button type="button" data-replay-command="play" class={replay_control_class()}>
          <.icon name="hero-play" class="size-4" />
        </button>
        <button type="button" data-replay-command="forward" class={replay_control_class()}>
          <.icon name="hero-forward" class="size-4" />
        </button>
        <button type="button" data-replay-command="exit" class={replay_control_class()}>
          Exit replay
        </button>
        <select data-replay-speed class="rounded-md border border-stone-700 bg-stone-950 px-2 py-1 text-xs font-bold text-stone-100">
          <option value="0.5">0.5x</option>
          <option value="1" selected>1x</option>
          <option value="2">2x</option>
        </select>
      </div>
    </div>
  </section>
  """
end
```

Add helpers:

```elixir
defp replay_control_class do
  "inline-flex min-h-8 items-center justify-center rounded-md border border-sky-200/40 bg-stone-950 px-2 text-xs font-black text-sky-100 transition hover:border-sky-100 hover:text-white"
end

defp replay_events_json(payload) do
  Phoenix.json_library().encode!(payload)
end
```

- [ ] **Step 5: Render replay panel only after completed rounds**

In `full_game_scoreboard/1`, after the route selector, render:

```elixir
<.replay_panel
  game_state={@game_state}
  selected_revealed_round={@selected_revealed_round}
  replay_payload={@replay_payload}
/>
```

In `game_over_panel/1`, render the same panel for full and limited game modes when payload exists.

Pass `replay_payload={@replay_payload}` at call sites for `full_game_scoreboard` and `game_over_panel`.

- [ ] **Step 6: Add replay payload selection helpers**

Add helpers near route selection helpers:

```elixir
defp selected_replay_payload(%{phase: :round_review} = game_state, selected_round) do
  game_state
  |> replay_events_for_round(selected_round)
  |> Replay.payload_events(game_state)
end

defp selected_replay_payload(%{phase: :game_over, game_mode: :full} = game_state, selected_round) do
  game_state
  |> replay_events_for_round(selected_round)
  |> Replay.payload_events(game_state)
end

defp selected_replay_payload(%{phase: :game_over, game_mode: :limited} = game_state, _selected_round) do
  Replay.payload_events(game_state.replay_events, game_state)
end

defp selected_replay_payload(_game_state, _selected_round), do: []

defp replay_events_for_round(game_state, selected_round) when is_integer(selected_round) do
  game_state.round_results
  |> Enum.find(&(&1.round_number == selected_round))
  |> case do
    %{replay_events: events} when is_list(events) -> events
    _result -> []
  end
end

defp replay_events_for_round(_game_state, _selected_round), do: []
```

- [ ] **Step 7: Run LiveView tests and verify GREEN**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: all LiveView tests pass.

- [ ] **Step 8: Run formatting**

Run:

```bash
mix format
```

Expected: exit code `0`.

- [ ] **Step 9: Commit Task 3**

Run:

```bash
git add lib/museum_caper_web/live/game_live.ex test/museum_caper_web/live/game_live_test.exs
git commit -m "feat: expose replay payload after rounds"
```

---

### Task 4: Browser Replay Playback

**Files:**
- Create: `assets/js/replay_playback.js`
- Create: `assets/js/replay_playback_test.mjs`
- Create: `assets/js/hooks/replay_playback_hook.js`
- Modify: `assets/js/app.js`

**Interfaces:**
- Consumes: `data-replay-events` JSON payload, existing board cell ids, `parseMovePath`, `movementDuration`, and `pathCellId`.
- Produces:
  - `initialReplayState(events)`
  - `nextReplayIndex(state)`
  - `previousReplayIndex(state)`
  - `replayEventDuration(event, speed)`
  - `ReplayPlaybackHook`

- [ ] **Step 1: Write failing JS playback tests**

Create `assets/js/replay_playback_test.mjs`:

```javascript
import assert from "node:assert/strict";
import test from "node:test";

import {
  initialReplayState,
  nextReplayIndex,
  previousReplayIndex,
  replayEventDuration,
} from "./replay_playback.js";

const events = [
  {type: "enter", path: "6-1 6-2"},
  {type: "move", path: "6-2 6-3 6-4"},
  {type: "lock_check", path: "6-4"},
];

test("initialReplayState starts paused at the first event", () => {
  assert.deepEqual(initialReplayState(events), {
    events,
    index: 0,
    playing: false,
    speed: 1,
  });
});

test("nextReplayIndex stops at the final event", () => {
  const state = {...initialReplayState(events), index: 1};

  assert.equal(nextReplayIndex(state), 2);
  assert.equal(nextReplayIndex({...state, index: 2}), 2);
});

test("previousReplayIndex stops at the first event", () => {
  const state = {...initialReplayState(events), index: 1};

  assert.equal(previousReplayIndex(state), 0);
  assert.equal(previousReplayIndex({...state, index: 0}), 0);
});

test("replayEventDuration scales movement duration by speed", () => {
  assert.equal(replayEventDuration(events[1], 1), 240);
  assert.equal(replayEventDuration(events[1], 2), 120);
  assert.equal(replayEventDuration(events[1], 0.5), 480);
  assert.equal(replayEventDuration(events[2], 1), 700);
});
```

- [ ] **Step 2: Run the failing JS tests**

Run:

```bash
node --test assets/js/replay_playback_test.mjs
```

Expected: failure because `assets/js/replay_playback.js` does not exist.

- [ ] **Step 3: Implement pure playback helpers**

Create `assets/js/replay_playback.js`:

```javascript
import {movementDuration, parseMovePath} from "./board_movement_animation";

const NON_MOVEMENT_DURATION_MS = 700;

export const initialReplayState = events => ({
  events,
  index: 0,
  playing: false,
  speed: 1,
});

export const nextReplayIndex = state =>
  Math.min(state.index + 1, Math.max(state.events.length - 1, 0));

export const previousReplayIndex = state => Math.max(state.index - 1, 0);

export const replayEventDuration = (event, speed = 1) => {
  const parsedPath = parseMovePath(event?.path);
  const baseDuration =
    parsedPath.length > 1 ? movementDuration(parsedPath) : NON_MOVEMENT_DURATION_MS;

  return Math.round(baseDuration / Number.parseFloat(speed || 1));
};
```

- [ ] **Step 4: Run JS tests and verify GREEN**

Run:

```bash
node --test assets/js/replay_playback_test.mjs
```

Expected: `4 tests, 0 failures`.

- [ ] **Step 5: Implement replay playback hook**

Create `assets/js/hooks/replay_playback_hook.js`:

```javascript
import {
  initialReplayState,
  nextReplayIndex,
  previousReplayIndex,
  replayEventDuration,
} from "../replay_playback";
import {parseMovePath, pathCellId} from "../board_movement_animation";

const pawnClass = event =>
  `replay-pawn replay-pawn-${event.actor_role} replay-pawn-${event.actor_color || "grey"}`;

const centerOf = element => {
  const rect = element.getBoundingClientRect();

  return {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
};

const ReplayPlaybackHook = {
  mounted() {
    this.state = initialReplayState(this.events());
    this.caption = this.el.querySelector("[data-replay-caption]");
    this.speedInput = this.el.querySelector("[data-replay-speed]");
    this.bindControls();
    this.renderFrame();
  },
  destroyed() {
    this.stop();
    this.clearLayer();
  },
  events() {
    try {
      return JSON.parse(this.el.dataset.replayEvents || "[]");
    } catch (_error) {
      return [];
    }
  },
  bindControls() {
    this.el.querySelectorAll("[data-replay-command]").forEach(button => {
      button.addEventListener("click", event => {
        this.command(event.currentTarget.dataset.replayCommand);
      });
    });

    this.speedInput?.addEventListener("change", event => {
      this.state = {...this.state, speed: Number.parseFloat(event.target.value || "1")};
    });
  },
  command(command) {
    if (command === "play") {
      this.togglePlay();
    } else if (command === "back") {
      this.stop();
      this.state = {...this.state, index: previousReplayIndex(this.state)};
      this.renderFrame();
    } else if (command === "forward") {
      this.stop();
      this.state = {...this.state, index: nextReplayIndex(this.state)};
      this.renderFrame();
    } else if (command === "restart") {
      this.stop();
      this.state = {...this.state, index: 0};
      this.renderFrame();
    } else if (command === "exit") {
      this.stop();
      this.clearLayer();
      this.caption && (this.caption.textContent = "");
    }
  },
  togglePlay() {
    if (this.state.playing) {
      this.stop();
    } else {
      this.state = {...this.state, playing: true};
      this.playCurrent();
    }
  },
  playCurrent() {
    this.renderFrame();

    if (!this.state.playing || this.state.index >= this.state.events.length - 1) {
      this.state = {...this.state, playing: false};
      return;
    }

    const event = this.state.events[this.state.index];
    const duration = replayEventDuration(event, this.state.speed);

    this.timer = setTimeout(() => {
      this.state = {...this.state, index: nextReplayIndex(this.state)};
      this.playCurrent();
    }, duration);
  },
  stop() {
    clearTimeout(this.timer);
    this.timer = null;
    this.state = {...this.state, playing: false};
  },
  renderFrame() {
    const event = this.state.events[this.state.index];

    if (!event) {
      return;
    }

    this.caption && (this.caption.textContent = event.label || "");
    this.renderPawn(event);
  },
  renderPawn(event) {
    const path = parseMovePath(event.path);
    const finalCell = path[path.length - 1];

    if (!finalCell) {
      return;
    }

    const cell = document.getElementById(pathCellId(finalCell));

    if (!cell) {
      return;
    }

    const layer = this.layer();
    const marker = document.createElement("span");
    marker.className = pawnClass(event);
    marker.textContent = event.actor_role === "thief" ? "T" : "D";

    const center = centerOf(cell);
    marker.style.left = `${center.x}px`;
    marker.style.top = `${center.y}px`;

    layer.replaceChildren(marker);
  },
  layer() {
    if (!this.replayLayer) {
      this.replayLayer = document.createElement("div");
      this.replayLayer.id = "replay-board-layer";
      this.replayLayer.className = "replay-board-layer";
      document.body.appendChild(this.replayLayer);
    }

    return this.replayLayer;
  },
  clearLayer() {
    this.replayLayer?.remove();
    this.replayLayer = null;
  },
};

export default ReplayPlaybackHook;
```

- [ ] **Step 6: Register the hook**

Modify `assets/js/app.js`:

```javascript
import ReplayPlaybackHook from "./hooks/replay_playback_hook"

Hooks.ReplayPlaybackHook = ReplayPlaybackHook
```

- [ ] **Step 7: Run JS test set**

Run:

```bash
node --test assets/js/replay_playback_test.mjs assets/js/board_movement_animation_test.mjs assets/js/game_audio_preference_test.mjs assets/js/route_arrow_contrast_test.mjs
```

Expected: all JS tests pass.

- [ ] **Step 8: Commit Task 4**

Run:

```bash
git add assets/js/replay_playback.js assets/js/replay_playback_test.mjs assets/js/hooks/replay_playback_hook.js assets/js/app.js
git commit -m "feat: add replay playback hook"
```

---

### Task 5: Replay Styling, Integration Checks, and Final Verification

**Files:**
- Modify: `assets/css/app.css`
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Test: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: `#replay-board-layer`, `.replay-pawn`, `#replay-panel`, and `ReplayPlaybackHook`.
- Produces: polished replay layer styling, reduced-motion behavior, and final verification.

- [ ] **Step 1: Write failing CSS/markup assertions**

Add to `test/museum_caper_web/live/game_live_test.exs`:

```elixir
test "replay playback surface includes accessible controls and speed selector", %{
  conn: conn,
  game_id: game_id
} do
  pid = start_two_player_full_game!(game_id)

  :sys.replace_state(pid, fn server_state ->
    game_state = %{
      server_state.game_state
      | phase: :round_review,
        round_number: 2,
        round_results: [
          %{
            round_number: 1,
            thief_player_id: "player-alice",
            stolen_count: 0,
            outcome: :detectives,
            reason: :caught,
            thief_history: %{entry: nil, exit: nil, moves: []},
            replay_events: [
              %{
                id: 1,
                round_number: 1,
                turn_index: 0,
                actor_id: "player-alice",
                actor_role: :thief,
                actor_label: "Alice",
                type: :enter,
                path: [{6, 1}, {6, 2}],
                from: {6, 1},
                to: {6, 2},
                result: nil,
                label: "Alice entered through D2."
              }
            ]
          }
        ]
    }

    %{server_state | game_state: game_state}
  end)

  {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

  assert has_element?(alice_view, "#replay-playback [data-replay-command='back']")
  assert has_element?(alice_view, "#replay-playback [data-replay-command='play']")
  assert has_element?(alice_view, "#replay-playback [data-replay-command='forward']")
  assert has_element?(alice_view, "#replay-playback [data-replay-command='exit']", "Exit replay")
  assert has_element?(alice_view, "#replay-playback select[data-replay-speed] option[value='0.5']")
  assert has_element?(alice_view, "#replay-playback select[data-replay-speed] option[value='1'][selected]")
  assert has_element?(alice_view, "#replay-playback select[data-replay-speed] option[value='2']")
end
```

- [ ] **Step 2: Run the focused LiveView test**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: failure until the markup/styling pass is complete.

- [ ] **Step 3: Add replay CSS**

Modify `assets/css/app.css`:

```css
.replay-board-layer {
  position: fixed;
  inset: 0;
  z-index: 85;
  pointer-events: none;
}

.replay-pawn {
  position: fixed;
  display: grid;
  width: 1.5rem;
  height: 1.5rem;
  place-items: center;
  border: 2px solid rgba(15, 23, 42, 0.92);
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 900;
  line-height: 1;
  color: #0c0a09;
  box-shadow:
    0 0.45rem 0.65rem rgba(0, 0, 0, 0.35),
    0 0 0.75rem rgba(125, 211, 252, 0.45);
  transform: translate(-50%, -50%);
}

.replay-pawn-thief {
  background: #d6d3d1;
}

.replay-pawn-detective {
  background: #fbbf24;
}

.replay-pawn-red {
  background: #f87171;
}

.replay-pawn-blue {
  background: #60a5fa;
}

.replay-pawn-green {
  background: #34d399;
}

.replay-pawn-yellow {
  background: #facc15;
}

@media (prefers-reduced-motion: reduce) {
  .replay-pawn {
    transition: none;
  }
}
```

- [ ] **Step 4: Tighten replay markup states**

In `replay_panel/1`, ensure buttons have `aria-label` values:

```elixir
<button type="button" aria-label="Step back" data-replay-command="back" class={replay_control_class()}>
```

Use labels:

- `Step back`
- `Play replay`
- `Step forward`
- `Exit replay`

- [ ] **Step 5: Run focused LiveView and JS tests**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
node --test assets/js/replay_playback_test.mjs assets/js/board_movement_animation_test.mjs assets/js/game_audio_preference_test.mjs assets/js/route_arrow_contrast_test.mjs
```

Expected: all tests pass.

- [ ] **Step 6: Run asset build**

Run:

```bash
mix assets.build
```

Expected: Tailwind and esbuild complete with exit code `0`.

- [ ] **Step 7: Run final project checks**

Run:

```bash
mix format
mix credo
mix precommit
git diff --check
```

Expected:

- `mix format` exits `0`.
- `mix credo` exits `0` when Credo is installed; if the project still does not define the task, record the exact missing-task output in the final response.
- `mix precommit` exits `0`.
- `git diff --check` exits `0`.

- [ ] **Step 8: Commit Task 5**

Run:

```bash
git add assets/css/app.css lib/museum_caper_web/live/game_live.ex test/museum_caper_web/live/game_live_test.exs
git commit -m "style: polish replay playback controls"
```

---

## Plan Self-Review

- Spec coverage: Task 1 covers replay data shape and payload formatting. Task 2 covers authoritative rules recording, completed round storage, and reset behavior. Task 3 covers after-round/game-over-only LiveView exposure. Task 4 covers browser playback. Task 5 covers controls, styling, reduced motion, and verification.
- Placeholder scan: The plan contains concrete file paths, commands, code snippets, expected failures, expected passing results, and commit commands.
- Type consistency: The plan consistently uses `replay_events`, `turn_index`, `Replay.append_event/2`, `Replay.put_movement_event/4`, `Replay.payload_events/2`, `ReplayPlaybackHook`, and `data-replay-events`.
