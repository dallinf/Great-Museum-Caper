# Route Reveal Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add clear entry, exit, direction, and per-turn stop annotations to completed thief routes on the board.

**Architecture:** Extend `thief_history` with `exit: nil | %{id, label, position}` so rules record the actual door/window used only after a successful escape. Convert completed route history into grouped board-cell overlay marks in `GameLive`, allowing multiple annotations per cell. Keep active thief movement hidden by deriving overlays only from completed history.

**Tech Stack:** Elixir rules/state structs, Phoenix LiveView HEEx components, Tailwind classes/custom CSS, Phoenix LiveView tests, ExUnit rules tests.

## Global Constraints

- Mark the entry point clearly with an `ENTRY` badge on the door/window label cell and the entry label, such as `D2`.
- Mark the exit clearly with an `EXIT` badge on the door/window label cell when the thief escaped through a door or window.
- Keep the last inside square as a final stop marker, so detectives can see where the thief stood before checking or exiting.
- Add directional cues along the route so the path reads like movement, not only highlighted squares.
- Add per-turn stop markers for every committed thief move.
- No route annotations are shown during an active thief round.
- Rules set `exit` only when the thief actually escapes.

---

### Task 1: Persist Successful Escape Metadata

**Files:**
- Modify: `lib/museum_caper/game/state.ex`
- Modify: `lib/museum_caper/game/rules.ex`
- Modify: `test/museum_caper/game/rules_movement_test.exs`

**Interfaces:**
- Consumes: `Board.entry_by_id/1`, `Board.exit_door_cell/1`, `Rules.try_escape/2`.
- Produces: `thief_history.exit :: %{id: atom(), label: String.t(), position: {integer(), integer()}} | nil`.

- [ ] **Step 1: Write failing rules tests**

Update the existing `enter_museum/2` history assertion to include `exit: nil`:

```elixir
assert state.thief_history == %{
         entry: %{id: :exit_w1, label: "D2", position: {6, 2}},
         exit: nil,
         moves: []
       }
```

Update the existing full-game escape history fixture and assertion to include:

```elixir
exit: %{id: :window_1_5, label: "W1", position: {1, 5}}
```

Add this test under `try_escape/2`:

```elixir
test "successful escape records the exit door or window in thief history" do
  state =
    base_state()
    |> Map.merge(%{
      thief_position: {1, 5},
      stolen_count: 3,
      locks: Map.put(base_state().locks, :window_1_5, :open),
      thief_history: %{
        entry: %{id: :exit_w1, label: "D2", position: {6, 2}},
        exit: nil,
        moves: [%{path: [{1, 4}, {1, 5}]}]
      }
    })

  assert {:ok, :escaped, state} = Rules.try_escape(state, :window_1_5)

  assert state.thief_history.exit == %{
           id: :window_1_5,
           label: "W1",
           position: {1, 5}
         }
end
```

Add this test near locked escape coverage:

```elixir
test "locked escape checks do not record an exit marker" do
  state =
    base_state()
    |> Map.merge(%{
      thief_position: {1, 5},
      locks: Map.put(base_state().locks, :window_1_5, :locked),
      thief_history: %{
        entry: %{id: :exit_w1, label: "D2", position: {6, 2}},
        exit: nil,
        moves: []
      }
    })

  assert {:ok, :locked, state} = Rules.try_escape(state, :window_1_5)
  assert state.thief_history.exit == nil
end
```

- [ ] **Step 2: Verify RED**

Run:

```bash
mix test test/museum_caper/game/rules_movement_test.exs
```

Expected: tests fail because `thief_history.exit` is missing or remains `nil` after successful escape.

- [ ] **Step 3: Implement exit metadata**

Change `@empty_thief_history` in `lib/museum_caper/game/state.ex`:

```elixir
@empty_thief_history %{entry: nil, exit: nil, moves: []}
```

Change `thief_entry_history/2`:

```elixir
defp thief_entry_history(entry, pos) do
  %{
    entry: %{id: entry.id, label: entry.label, position: pos},
    exit: nil,
    moves: []
  }
end
```

Change open escape handling:

```elixir
:open ->
  finish_escape(state, entry)
```

Change `finish_escape/1` to `finish_escape/2`:

```elixir
defp finish_escape(state, entry) do
  state =
    state
    |> commit_thief_movement()
    |> put_thief_exit_history(entry)
    |> resolve_pending_steal()

  if limited_escape_without_enough_art?(state) do
    {:ok, :escaped_without_enough_art,
     finish_round(state, :detectives, :escaped_without_enough_art)}
  else
    {:ok, :escaped, finish_round(state, :thief, :escaped)}
  end
end
```

Add helper:

```elixir
defp put_thief_exit_history(state, entry) do
  exit = %{id: entry.id, label: entry.label, position: Board.exit_door_cell(entry)}
  put_in(state.thief_history.exit, exit)
end
```

- [ ] **Step 4: Verify GREEN**

Run:

```bash
mix test test/museum_caper/game/rules_movement_test.exs
```

Expected: all rules movement tests pass.

---

### Task 2: Render Entry, Exit, Direction, And Stop Marks

**Files:**
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Modify: `assets/css/app.css`
- Modify: `test/museum_caper_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: `thief_history.entry`, `thief_history.exit`, and `thief_history.moves`.
- Produces: grouped route overlay marks with `data-thief-route`, `data-route-direction`, `data-thief-route-stop`, and `data-route-round` attributes.

- [ ] **Step 1: Write failing LiveView tests**

Update the limited-game escape test to expect:

```elixir
assert has_element?(thief_view, "#cell-6-1 [data-thief-route='entry'][data-route-round='current']", "ENTRY D2")
assert has_element?(thief_view, "#cell-1-5 [data-thief-route='exit'][data-route-round='current']", "EXIT W1")
assert has_element?(thief_view, "#cell-1-5 [data-thief-route='stop'][data-thief-route-stop='1']", "1")
assert has_element?(thief_view, "#cell-1-4 [data-thief-route='path'][data-route-direction='east']")
```

Update the full-game route reveal test to expect the same entry/exit/direction/stop attributes with `data-route-round='1'`.

Update the selector switching test so round 1 entry appears on `#cell-6-1` for `D2`, round 2 entry appears on `#cell-5-12` for `D1`, and selected paths still switch.

Add this LiveView test:

```elixir
test "completed route without escape has no exit badge but shows turn stops", %{
  conn: conn,
  game_id: game_id
} do
  pid = start_two_player_full_game!(game_id)

  :sys.replace_state(pid, fn server_state ->
    game_state = %{
      server_state.game_state
      | phase: :setup,
        setup_step: :locks,
        round_number: 2,
        round_results: [
          %{
            round_number: 1,
            thief_player_id: "player-alice",
            stolen_count: 0,
            outcome: :detectives,
            reason: :caught,
            thief_history: %{
              entry: %{id: :exit_w1, label: "D2", position: {6, 2}},
              exit: nil,
              moves: [
                %{path: [{6, 2}, {6, 3}]},
                %{path: [{6, 3}, {5, 3}]}
              ]
            }
          }
        ]
    }

    %{server_state | game_state: game_state}
  end)

  {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

  assert has_element?(alice_view, "#cell-6-1 [data-thief-route='entry']", "ENTRY D2")
  assert has_element?(alice_view, "#cell-6-3 [data-thief-route='stop'][data-thief-route-stop='1']", "1")
  assert has_element?(alice_view, "#cell-5-3 [data-thief-route='stop'][data-thief-route-stop='2']", "2")
  refute has_element?(alice_view, "[data-thief-route='exit']")
end
```

- [ ] **Step 2: Verify RED**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: tests fail because entry markers are still on inside cells, exit markers are absent, and stop/direction attributes are absent.

- [ ] **Step 3: Implement grouped route marks**

Change board calls:

```heex
<.thief_route_cell_overlay route_marks={Map.get(@revealed_route_marks, pos, [])} />
```

Change component attr and render loop:

```elixir
attr :route_marks, :list, default: []

def thief_route_cell_overlay(assigns) do
  ~H"""
  <span
    :if={@route_marks != []}
    data-thief-route-cell
    class="pointer-events-none absolute inset-0 z-[18]"
  >
    <%= for mark <- @route_marks do %>
      <span
        data-thief-route={@mark.kind}
        data-route-round={@mark.round}
        data-route-direction={@mark[:direction]}
        data-thief-route-stop={@mark[:stop]}
        class={route_mark_class(@mark)}
      >
        {route_mark_label_text(@mark)}
      </span>
    <% end %>
  </span>
  """
end
```

Replace `route_marks/2` and related helpers so they return `%{{row, col} => [mark]}`:

```elixir
defp route_marks(history, round) do
  round = to_string(round)
  path_positions = thief_route_positions(history)

  []
  |> add_path_marks(path_positions, round)
  |> add_stop_marks(history, round)
  |> add_entry_mark(history, round)
  |> add_exit_mark(history, round)
  |> Enum.group_by(& &1.position, &Map.delete(&1, :position))
end
```

Implement helpers:

```elixir
defp add_entry_mark(marks, %{entry: %{id: id} = entry}, round) do
  position =
    id
    |> Board.entry_by_id()
    |> Board.exit_door_cell()

  [%{kind: "entry", round: round, position: position, label: "ENTRY #{route_entry_label(entry)}"} | marks]
end

defp add_entry_mark(marks, _history, _round), do: marks

defp add_exit_mark(marks, %{exit: %{label: label, position: position}}, round) do
  [%{kind: "exit", round: round, position: position, label: "EXIT #{label}"} | marks]
end

defp add_exit_mark(marks, _history, _round), do: marks

defp add_stop_marks(marks, %{moves: moves}, round) do
  moves
  |> Enum.with_index(1)
  |> Enum.reduce(marks, fn {move, index}, marks ->
    case List.last(Map.get(move, :path, [])) do
      nil -> marks
      position -> [%{kind: "stop", round: round, position: position, stop: index, label: Integer.to_string(index)} | marks]
    end
  end)
end

defp add_stop_marks(marks, _history, _round), do: marks

defp add_path_marks(marks, positions, round) do
  positions
  |> Enum.zip(Enum.drop(positions, 1))
  |> Enum.reduce(marks, fn {position, next_position}, marks ->
    direction = route_direction(position, next_position)
    [%{kind: "path", round: round, position: position, direction: direction, label: route_direction_glyph(direction)} | marks]
  end)
end
```

Add direction helpers:

```elixir
defp route_direction({row, col}, {row, next_col}) when next_col == col + 1, do: "east"
defp route_direction({row, col}, {row, next_col}) when next_col == col - 1, do: "west"
defp route_direction({row, col}, {next_row, col}) when next_row == row + 1, do: "south"
defp route_direction({row, col}, {next_row, col}) when next_row == row - 1, do: "north"
defp route_direction(_position, _next_position), do: nil

defp route_direction_glyph("east"), do: ">"
defp route_direction_glyph("west"), do: "<"
defp route_direction_glyph("north"), do: "^"
defp route_direction_glyph("south"), do: "v"
defp route_direction_glyph(_direction), do: ""
```

Add `route_mark_class/1` and `route_mark_label_text/1`:

```elixir
defp route_mark_label_text(%{label: label}), do: label
defp route_mark_label_text(_mark), do: ""

defp route_mark_class(%{kind: "entry"}), do: "absolute left-0.5 top-0.5 rounded bg-sky-300 px-1 py-0.5 text-[0.48rem] font-black text-stone-950 shadow"
defp route_mark_class(%{kind: "exit"}), do: "absolute right-0.5 bottom-0.5 rounded bg-amber-300 px-1 py-0.5 text-[0.48rem] font-black text-stone-950 shadow"
defp route_mark_class(%{kind: "stop"}), do: "absolute right-0.5 top-0.5 grid size-3 place-items-center rounded-full border border-stone-950 bg-stone-50 text-[0.5rem] font-black text-stone-950 shadow"
defp route_mark_class(%{kind: "path"}), do: "absolute left-1/2 top-1/2 grid size-3 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-sm border border-sky-200/70 bg-sky-300/25 text-[0.55rem] font-black text-sky-50 shadow-[0_0_0.65rem_rgba(125,211,252,0.45)]"
```

- [ ] **Step 4: Add small CSS affordance**

Add to `assets/css/app.css`:

```css
[data-thief-route-cell] {
  pointer-events: none;
}
```

- [ ] **Step 5: Verify GREEN**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: all LiveView tests pass.

---

### Task 3: Final Verification

**Files:**
- Verify all touched files.

- [ ] **Step 1: Run verification commands**

Run:

```bash
mix test test/museum_caper/game/rules_movement_test.exs
mix test test/museum_caper_web/live/game_live_test.exs
node --test assets/js/game_audio_preference_test.mjs assets/js/board_movement_animation_test.mjs
mix format
mix credo
mix precommit
mix assets.build
git diff --check
```

Expected:
- Rules tests pass.
- LiveView tests pass.
- Node tests pass.
- `mix format` exits 0.
- `mix credo` exits 0, or if unavailable, record the exact Mix error.
- `mix precommit` passes.
- `mix assets.build` passes.
- `git diff --check` reports no whitespace errors.
