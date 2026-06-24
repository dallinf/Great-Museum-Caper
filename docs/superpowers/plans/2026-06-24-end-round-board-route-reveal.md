# End-Round Board Route Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render completed thief routes directly on the museum board, latest completed round selected by default, with round selector buttons for older completed rounds.

**Architecture:** Keep `thief_history` and `round_results[*].thief_history` as the source of truth. The LiveView owns only the selected revealed round number and derives route markers per board cell during render. The board overlay is CSS-only and reuses existing cell markup rather than adding a second board.

**Tech Stack:** Phoenix LiveView HEEx, Elixir helper functions, Tailwind utility classes, custom CSS in `assets/css/app.css`, Phoenix LiveView tests.

## Global Constraints

- Do not reveal an active thief route before the round is completed.
- Full-game route reveal defaults to the latest completed round.
- Completed full-game rounds can be selected with compact round buttons.
- Limited-game game-over shows the completed route on the board.
- Existing movement animation behavior remains unchanged.
- Run `mix format`, `mix credo`, `mix test`, `mix precommit`, and asset/JS checks where available before completion.

---

### Task 1: Board Route Overlay And Round Selection

**Files:**
- Modify: `test/museum_caper_web/live/game_live_test.exs`
- Modify: `lib/museum_caper_web/live/game_live.ex`
- Modify: `assets/css/app.css`

**Interfaces:**
- Consumes: `game_state.thief_history :: %{entry: map() | nil, moves: [%{path: [{integer(), integer()}]}]}` and `game_state.round_results :: [map()]`.
- Produces: `selected_revealed_round :: integer() | nil`, `data-thief-route` board-cell overlays, and `select_route_round` LiveView event with `%{"round" => round_number}`.

- [ ] **Step 1: Write the failing default overlay test**

Add this assertion block to the existing `"full game round report reveals the completed thief route"` test after the existing `state.round_number == 2` assertion:

```elixir
assert has_element?(alice_view, "#route-round-selector")
assert has_element?(alice_view, "#select-route-round-1[aria-pressed='true']", "Round 1")
assert has_element?(alice_view, "#cell-6-2 [data-thief-route='entry'][data-route-round='1']", "D2")
assert has_element?(alice_view, "#cell-1-4 [data-thief-route='path'][data-route-round='1']")
assert has_element?(alice_view, "#cell-1-5 [data-thief-route='final'][data-route-round='1']")
refute has_element?(alice_view, "#round-route-history-1 #thief-route-move-1")
```

- [ ] **Step 2: Write the failing hidden-information test**

Add a new LiveView test near the route reveal tests:

```elixir
test "active thief route is not drawn on the board before the round completes", %{
  conn: conn,
  game_id: game_id
} do
  pid = start_two_player_full_game!(game_id)
  advance_to_pawns(pid)

  assert {:ok, _state} =
           GameServer.place_detective_pawn(pid, "player-bob:detective-1", {3, 9})

  assert {:ok, _state} =
           GameServer.place_detective_pawn(pid, "player-bob:detective-2", {9, 5})

  assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)

  :sys.replace_state(pid, fn server_state ->
    game_state = %{
      server_state.game_state
      | thief_position: {1, 4},
        movement_path: [{6, 2}, {5, 2}, {4, 2}, {3, 2}, {2, 2}, {1, 2}, {1, 3}, {1, 4}],
        thief_history: %{
          entry: %{id: :exit_w1, label: "D2", position: {6, 2}},
          moves: []
        }
    }

    %{server_state | game_state: game_state}
  end)

  {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

  refute has_element?(alice_view, "[data-thief-route]")
  refute has_element?(alice_view, "#route-round-selector")
end
```

- [ ] **Step 3: Write the failing selector switching test**

Add a new LiveView test near the route reveal tests:

```elixir
test "round route selector switches the path drawn on the board", %{
  conn: conn,
  game_id: game_id
} do
  pid = start_two_player_full_game!(game_id)

  :sys.replace_state(pid, fn server_state ->
    game_state = %{
      server_state.game_state
      | phase: :setup,
        setup_step: :locks,
        round_number: 3,
        round_results: [
          %{
            round_number: 1,
            thief_player_id: "player-alice",
            stolen_count: 2,
            outcome: :escaped,
            reason: :escaped,
            thief_history: %{
              entry: %{id: :exit_w1, label: "D2", position: {6, 2}},
              moves: [%{path: [{6, 2}, {5, 2}, {4, 2}]}]
            }
          },
          %{
            round_number: 2,
            thief_player_id: "player-bob",
            stolen_count: 1,
            outcome: :escaped,
            reason: :escaped,
            thief_history: %{
              entry: %{id: :exit_e1, label: "D3", position: {5, 11}},
              moves: [%{path: [{5, 11}, {5, 10}, {5, 9}]}]
            }
          }
        ]
    }

    %{server_state | game_state: game_state}
  end)

  {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

  assert has_element?(alice_view, "#select-route-round-2[aria-pressed='true']")
  assert has_element?(alice_view, "#cell-5-11 [data-thief-route='entry'][data-route-round='2']", "D3")
  assert has_element?(alice_view, "#cell-5-9 [data-thief-route='final'][data-route-round='2']")
  refute has_element?(alice_view, "#cell-6-2 [data-thief-route='entry']")

  render_click(element(alice_view, "#select-route-round-1"))

  assert has_element?(alice_view, "#select-route-round-1[aria-pressed='true']")
  assert has_element?(alice_view, "#cell-6-2 [data-thief-route='entry'][data-route-round='1']", "D2")
  assert has_element?(alice_view, "#cell-4-2 [data-thief-route='final'][data-route-round='1']")
  refute has_element?(alice_view, "#cell-5-11 [data-thief-route='entry']")
end
```

- [ ] **Step 4: Write the failing limited-game overlay test**

Extend the existing `"thief chooses whether to check a window lock before escaping"` test after the game-over route history assertions:

```elixir
assert has_element?(thief_view, "#cell-6-2 [data-thief-route='entry'][data-route-round='current']", "D2")
assert has_element?(thief_view, "#cell-1-4 [data-thief-route='path'][data-route-round='current']")
assert has_element?(thief_view, "#cell-1-5 [data-thief-route='final'][data-route-round='current']")
```

- [ ] **Step 5: Run tests to verify RED**

Run each focused test and confirm it fails because the selector or `data-thief-route` overlay is missing:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: the new or extended tests fail with missing element assertions for `#route-round-selector` or `[data-thief-route]`, not compile errors.

- [ ] **Step 6: Add selected round state and event handling**

Update `mount/3` initial assigns:

```elixir
selected_revealed_round: latest_revealed_round_number(game_state),
```

Update `handle_info({:state_changed, game_state}, socket)` and `refresh_state/2` assign blocks:

```elixir
selected_revealed_round:
  selected_revealed_round(socket.assigns[:selected_revealed_round], previous_state, game_state),
```

Add the event handler near other `handle_event/3` callbacks:

```elixir
@impl true
def handle_event("select_route_round", %{"round" => round}, socket) do
  selected_round =
    case Integer.parse(round) do
      {round_number, ""} -> selectable_revealed_round(socket.assigns.game_state, round_number)
      _ -> socket.assigns.selected_revealed_round
    end

  {:noreply, assign(socket, :selected_revealed_round, selected_round)}
end
```

Add helpers:

```elixir
defp selected_revealed_round(_selected_round, nil, game_state) do
  latest_revealed_round_number(game_state)
end

defp selected_revealed_round(selected_round, previous_state, game_state) do
  previous_latest = latest_revealed_round_number(previous_state)
  latest = latest_revealed_round_number(game_state)

  cond do
    latest != previous_latest -> latest
    selectable_revealed_round?(game_state, selected_round) -> selected_round
    true -> latest
  end
end

defp selectable_revealed_round(game_state, round_number) do
  if selectable_revealed_round?(game_state, round_number) do
    round_number
  else
    latest_revealed_round_number(game_state)
  end
end

defp selectable_revealed_round?(game_state, round_number) when is_integer(round_number) do
  Enum.any?(game_state.round_results, fn result ->
    result.round_number == round_number and thief_history_present?(Map.get(result, :thief_history))
  end)
end

defp selectable_revealed_round?(_game_state, _round_number), do: false

defp latest_revealed_round_number(game_state) do
  game_state.round_results
  |> Enum.filter(&thief_history_present?(Map.get(&1, :thief_history)))
  |> List.last()
  |> case do
    nil -> nil
    result -> result.round_number
  end
end
```

- [ ] **Step 7: Render selector buttons and pass selected round into components**

Change the scoreboard call:

```heex
<.full_game_scoreboard
  game_state={@game_state}
  selected_revealed_round={@selected_revealed_round}
/>
```

Change the game-over panel call:

```heex
<.game_over_panel
  game_state={@game_state}
  selected_revealed_round={@selected_revealed_round}
/>
```

Add `attr :selected_revealed_round, :integer, default: nil` to both components.

Replace the full-game text route histories with selector buttons:

```heex
<.route_round_selector
  :if={thief_histories_present?(@game_state.round_results)}
  game_state={@game_state}
  selected_revealed_round={@selected_revealed_round}
/>
```

Add this component:

```elixir
attr :game_state, :map, required: true
attr :selected_revealed_round, :integer, default: nil

def route_round_selector(assigns) do
  ~H"""
  <div id="route-round-selector" class="space-y-2 border-t border-amber-300/20 pt-2">
    <h3 class="text-[0.62rem] font-black uppercase tracking-[0.16em] text-amber-100">
      Revealed route
    </h3>
    <div class="grid grid-cols-[repeat(auto-fit,minmax(4.75rem,1fr))] gap-1">
      <%= for result <- route_selectable_results(@game_state) do %>
        <button
          id={"select-route-round-#{result.round_number}"}
          type="button"
          phx-click="select_route_round"
          phx-value-round={result.round_number}
          aria-pressed={to_string(result.round_number == @selected_revealed_round)}
          class={[
            "rounded-md border px-2 py-1 text-xs font-black transition",
            if(result.round_number == @selected_revealed_round,
              do: "border-sky-200 bg-sky-300 text-stone-950",
              else: "border-stone-700 bg-stone-950/60 text-stone-200 hover:border-sky-200 hover:text-sky-100"
            )
          ]}
        >
          Round {result.round_number}
        </button>
      <% end %>
    </div>
  </div>
  """
end
```

Add:

```elixir
defp route_selectable_results(game_state) do
  Enum.filter(game_state.round_results, fn result ->
    thief_history_present?(Map.get(result, :thief_history))
  end)
end
```

- [ ] **Step 8: Derive and render board route marks**

Pass route marks to every board cell:

```heex
<.thief_route_cell_overlay
  route_mark={Map.get(@revealed_route_marks, pos)}
/>
```

Add `revealed_route_marks` to `mount/3`, `handle_info/2`, and `refresh_state/2` assigns:

```elixir
revealed_route_marks: revealed_route_marks(game_state, selected_round)
```

When assigning `selected_revealed_round`, calculate it before `revealed_route_marks` so both values are consistent.

Add component:

```elixir
attr :route_mark, :map, default: nil

def thief_route_cell_overlay(assigns) do
  ~H"""
  <span
    :if={@route_mark}
    data-thief-route={@route_mark.kind}
    data-route-round={@route_mark.round}
    class={[
      "pointer-events-none absolute inset-1 z-[18] rounded-sm border text-[0.5rem] font-black leading-none",
      route_overlay_class(@route_mark.kind)
    ]}
  >
    <span class="sr-only">Thief route {@route_mark.kind}</span>
    <span :if={@route_mark.label} class="absolute left-0.5 top-0.5 rounded bg-stone-950/90 px-1 py-0.5 text-[0.48rem] text-sky-100">
      {@route_mark.label}
    </span>
  </span>
  """
end
```

Add helpers:

```elixir
defp revealed_route_marks(game_state, selected_round) do
  cond do
    selected_round != nil ->
      game_state.round_results
      |> Enum.find(&(&1.round_number == selected_round))
      |> case do
        nil -> %{}
        result -> route_marks(Map.get(result, :thief_history), selected_round)
      end

    game_state.phase == :game_over and thief_history_present?(game_state.thief_history) ->
      route_marks(game_state.thief_history, "current")

    true ->
      %{}
  end
end

defp route_marks(history, round) do
  positions = thief_route_positions(history)
  final_pos = List.last(positions)

  positions
  |> Enum.with_index()
  |> Enum.reduce(%{}, fn {pos, index}, marks ->
    kind =
      cond do
        index == 0 -> "entry"
        pos == final_pos -> "final"
        true -> "path"
      end

    Map.put(marks, pos, %{kind: kind, round: to_string(round), label: route_mark_label(history, index)})
  end)
end

defp route_mark_label(%{entry: entry}, 0), do: route_entry_label(entry)
defp route_mark_label(_history, _index), do: nil

defp thief_route_positions(%{entry: %{position: entry_pos}, moves: moves}) do
  moves
  |> Enum.flat_map(&Map.get(&1, :path, []))
  |> prepend_entry_position(entry_pos)
  |> Enum.dedup()
end

defp thief_route_positions(_history), do: []

defp prepend_entry_position([], entry_pos), do: [entry_pos]
defp prepend_entry_position([entry_pos | _rest] = positions, entry_pos), do: positions
defp prepend_entry_position(positions, entry_pos), do: [entry_pos | positions]

defp route_overlay_class("entry"), do: "border-sky-200 bg-sky-300/25 shadow-[0_0_0.75rem_rgba(125,211,252,0.45)]"
defp route_overlay_class("final"), do: "border-amber-200 bg-amber-300/30 shadow-[0_0_0.8rem_rgba(251,191,36,0.55)]"
defp route_overlay_class(_kind), do: "border-sky-300/55 bg-sky-300/12"
```

- [ ] **Step 9: Reduce text-heavy route history**

Change `thief_route_history/1` to render only a concise summary, keeping IDs that existing tests need:

```heex
<p class="mt-2 text-sm text-stone-200">
  <span id={route_entry_dom_id(@id)}>{route_entry_label(@history.entry)}</span>
  <span class="text-stone-500">to</span>
  <span id={route_move_dom_id(@id, 1)}>{route_summary_final_label(@history)}</span>
</p>
```

Add:

```elixir
defp route_summary_final_label(history) do
  history
  |> thief_route_positions()
  |> List.last()
  |> position_label()
end
```

If an existing test only checks text chip presence, update it to check the board overlay instead.

- [ ] **Step 10: Add CSS polish**

Append focused CSS to `assets/css/app.css` if Tailwind utility classes are not enough:

```css
[data-thief-route] {
  box-shadow: inset 0 0 0 1px rgba(15, 23, 42, 0.38);
}
```

Do not add decorative blobs or unrelated palette changes.

- [ ] **Step 11: Run focused tests to verify GREEN**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
```

Expected: the full LiveView test file passes.

- [ ] **Step 12: Run broad verification**

Run:

```bash
mix test test/museum_caper_web/live/game_live_test.exs
mix test test/museum_caper/game/rules_movement_test.exs
node --test assets/js/game_audio_preference_test.mjs assets/js/board_movement_animation_test.mjs
mix format
mix credo
mix precommit
mix assets.build
git diff --check
```

Expected:
- LiveView tests pass.
- Rules movement tests pass.
- Node tests pass.
- `mix format` exits 0.
- `mix credo` exits 0, or if the project does not define the task, record the exact failure.
- `mix precommit` passes.
- `mix assets.build` passes.
- `git diff --check` reports no whitespace errors.
