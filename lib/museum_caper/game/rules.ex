defmodule MuseumCaper.Game.Rules do
  alias MuseumCaper.Game.{Board, PawnColors, Replay, State}

  @limited_escape_stolen_count 3

  # --- Setup ---

  def toggle_lock(%State{setup_step: :locks} = state, entry_id) do
    with %{} <- Board.entry_by_id(entry_id) do
      case Map.get(state.locks, entry_id, :open) do
        :locked ->
          {:ok, %{state | locks: Map.put(state.locks, entry_id, :open)}}

        :open ->
          lock_entry(state, entry_id)
      end
    else
      _ -> {:error, :invalid_placement}
    end
  end

  def toggle_lock(_state, _entry_id), do: {:error, :invalid_phase}

  def place_painting(%State{setup_step: :paintings} = state, pos) do
    with :ok <- validate_painting_cell(pos),
         :ok <- validate_unoccupied(state, pos, [:paintings, :cameras, :detective_positions]) do
      paintings = Map.put(state.paintings, pos, :present)
      painting_labels = Map.put(state.painting_labels, pos, next_painting_label(state))

      with :ok <- validate_painting_color_coverage(paintings) do
        state = %{state | paintings: paintings, painting_labels: painting_labels}
        state = if map_size(paintings) >= 9, do: %{state | setup_step: :cameras}, else: state
        {:ok, state}
      end
    end
  end

  def place_painting(_state, _pos), do: {:error, :invalid_phase}

  def remove_painting(%State{phase: :setup} = state, pos) do
    if Map.has_key?(state.paintings, pos) do
      {:ok,
       %{
         state
         | paintings: Map.delete(state.paintings, pos),
           painting_labels: Map.delete(state.painting_labels, pos),
           setup_step: :paintings
       }}
    else
      {:error, :not_found}
    end
  end

  def remove_painting(_state, _pos), do: {:error, :invalid_phase}

  defp next_painting_label(state) do
    used_numbers =
      state.painting_labels
      |> Map.values()
      |> Enum.map(&painting_label_number/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    next_number =
      Stream.iterate(1, &(&1 + 1))
      |> Enum.find(&(not MapSet.member?(used_numbers, &1)))

    "A#{next_number}"
  end

  defp painting_label_number("A" <> number), do: String.to_integer(number)
  defp painting_label_number(_label), do: nil

  defp painting_label(state, pos) do
    Map.get(state.painting_labels, pos) || fallback_painting_label(state.paintings, pos)
  end

  defp fallback_painting_label(paintings, pos) do
    index =
      paintings
      |> Map.keys()
      |> Enum.sort()
      |> Enum.find_index(&(&1 == pos))

    if index == nil, do: "artwork", else: "A#{index + 1}"
  end

  def place_camera(%State{setup_step: :cameras} = state, camera_id, pos) do
    with true <- Board.camera_placeable_cell?(pos),
         :ok <- validate_unoccupied(state, pos, [:paintings, :cameras, :detective_positions]) do
      cameras = Map.put(state.cameras, camera_id, %{pos: pos, status: :active})
      state = %{state | cameras: cameras}
      placed = Enum.count(cameras, fn {_, v} -> v != nil end)
      state = if placed >= 4, do: %{state | setup_step: :pawns}, else: state
      {:ok, state}
    else
      {:error, :cell_occupied} -> {:error, :cell_occupied}
      _ -> {:error, :invalid_placement}
    end
  end

  def place_camera(_state, _camera_id, _pos), do: {:error, :invalid_phase}

  def remove_camera_at(%State{phase: :setup} = state, pos) do
    case Enum.find(state.cameras, fn {_id, camera} -> camera != nil and camera.pos == pos end) do
      {camera_id, _camera} ->
        {:ok, %{state | cameras: Map.put(state.cameras, camera_id, nil), setup_step: :cameras}}

      nil ->
        {:error, :not_found}
    end
  end

  def remove_camera_at(_state, _pos), do: {:error, :invalid_phase}

  def place_detective_pawn(%State{setup_step: :pawns} = state, detective_id, pos) do
    with true <- Board.detective_placeable_cell?(pos),
         :ok <- validate_unoccupied(state, pos, [:paintings, :cameras, :detective_positions]) do
      det_positions = Map.put(state.detective_positions, detective_id, pos)

      state =
        %{state | detective_positions: det_positions}
        |> Replay.append_event(%{
          type: :setup,
          actor_id: detective_id,
          actor_role: :detective,
          path: [pos],
          from: pos,
          to: pos,
          result: nil,
          label: "#{player_name(state, detective_id)} started at #{position_label(pos)}."
        })

      all_placed = Enum.all?(det_positions, fn {_, v} -> v != nil end)
      state = if all_placed, do: %{state | phase: :thief_entry}, else: state
      {:ok, state}
    else
      _ -> {:error, :cell_occupied}
    end
  end

  def place_detective_pawn(_state, _detective_id, _pos), do: {:error, :invalid_phase}

  # --- Thief Entry ---

  def enter_museum(state, entry_id) do
    with %{} = entry <- Board.entry_by_id(entry_id) do
      pos = Board.exit_adjacent_cell(entry)
      turn_order = thief_entry_turn_order(state)
      next_player = state.thief_player_id
      {actions, dice} = turn_setup(state, next_player)

      state = %{
        state
        | thief_position: pos,
          thief_history: thief_entry_history(entry, pos),
          phase: :playing,
          turn_order: turn_order,
          current_turn: next_player,
          turn_actions_remaining: actions,
          dice: dice
      }

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

      {:ok, state}
    else
      _ -> {:error, :invalid_entry}
    end
  end

  # --- Thief Movement ---

  def valid_thief_destinations(state, max_steps \\ nil) do
    detective_cells =
      state.detective_positions |> Map.values() |> Enum.reject(&is_nil/1) |> MapSet.new()

    origin = movement_origin(state, state.thief_position)
    step_limit = movement_limit(3, max_steps)

    bfs_distances(origin, step_limit, MapSet.new())
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.delete(state.thief_position)
    |> MapSet.difference(detective_cells)
    |> MapSet.to_list()
  end

  def move_thief(state, destination) do
    if :move in state.turn_actions_remaining do
      valid = valid_thief_destinations(state)

      if destination in valid do
        state = move_player(state, :thief, state.thief_player_id, destination, 3, MapSet.new())
        state = resolve_thief_landing(state)
        {:ok, state}
      else
        {:error, :invalid_move}
      end
    else
      {:error, :invalid_move}
    end
  end

  defp resolve_thief_landing(state) do
    pos = state.thief_position
    state = check_camera(state, pos)
    state = check_painting(state, pos)
    state
  end

  defp check_camera(state, pos) do
    case Enum.find(state.cameras, fn {_, v} -> v && v.pos == pos && v.status == :active end) do
      {id, cam} -> %{state | cameras: Map.put(state.cameras, id, %{cam | status: :disabled})}
      nil -> state
    end
  end

  defp check_painting(state, pos) do
    case state.paintings[pos] do
      :present ->
        %{state | paintings: Map.put(state.paintings, pos, :targeted), pending_steal: pos}

      _ ->
        state
    end
  end

  def resolve_pending_steal(%{pending_steal: nil} = state), do: state

  def resolve_pending_steal(%{pending_steal: pos} = state) do
    label = painting_label(state, pos)

    %{
      state
      | paintings: Map.put(state.paintings, pos, :removed),
        pending_steal: nil,
        stolen_count: state.stolen_count + 1,
        game_log: state.game_log ++ ["Artwork #{label} stolen."]
    }
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
  end

  # --- Detective Movement ---

  def valid_detective_destinations(state, detective_id) do
    {max_steps, _} = state.dice
    pos = state.detective_positions[detective_id]
    origin = movement_origin(state, pos)

    detective_cells =
      state.detective_positions
      |> Enum.reject(fn {id, detective_pos} -> id == detective_id or detective_pos == nil end)
      |> Enum.map(fn {_id, detective_pos} -> detective_pos end)
      |> MapSet.new()

    bfs_distances(origin, max_steps, detective_movement_blocked_cells(state))
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.delete(pos)
    |> MapSet.difference(detective_cells)
    |> MapSet.difference(detective_landing_blocked_cells(state))
    |> MapSet.to_list()
  end

  defp detective_movement_blocked_cells(state) do
    state
    |> hidden_thief_painting_cells()
    |> MapSet.union(MapSet.new(Board.external_door_cells()))
  end

  defp hidden_thief_painting_cells(%{chase_mode: true}), do: MapSet.new()

  defp hidden_thief_painting_cells(state) do
    state.paintings
    |> Enum.filter(fn {_pos, status} -> status == :targeted end)
    |> Enum.map(fn {pos, _status} -> pos end)
    |> MapSet.new()
  end

  defp detective_landing_blocked_cells(state) do
    state.paintings
    |> Enum.filter(fn {pos, status} -> painting_blocks_detective_landing?(state, pos, status) end)
    |> Enum.map(fn {pos, _status} -> pos end)
    |> MapSet.new()
  end

  defp painting_blocks_detective_landing?(_state, _pos, :removed), do: false

  defp painting_blocks_detective_landing?(
         %{chase_mode: true, thief_position: pos},
         pos,
         :targeted
       ),
       do: false

  defp painting_blocks_detective_landing?(_state, _pos, _status), do: true

  defp bfs_distances(start, max_steps, _blocked) when max_steps <= 0, do: %{start => 0}

  defp bfs_distances(start, max_steps, blocked) do
    Enum.reduce(1..max_steps, {[start], %{start => 0}}, fn step, {frontier, distances} ->
      new_cells =
        frontier
        |> Enum.flat_map(&Board.neighbors/1)
        |> Enum.reject(&Map.has_key?(distances, &1))
        |> Enum.reject(&MapSet.member?(blocked, &1))
        |> Enum.uniq()

      new_distances = Enum.reduce(new_cells, distances, &Map.put(&2, &1, step))
      {new_cells, new_distances}
    end)
    |> elem(1)
  end

  defp bfs_paths(start, max_steps, _blocked) when max_steps <= 0, do: %{start => [start]}

  defp bfs_paths(start, max_steps, blocked) do
    Enum.reduce(1..max_steps, {[start], %{start => [start]}}, fn _step, {frontier, paths} ->
      new_steps =
        frontier
        |> Enum.flat_map(fn current ->
          current
          |> Board.neighbors()
          |> Enum.map(fn neighbor -> {neighbor, current} end)
        end)
        |> Enum.reject(fn {cell, _previous} -> Map.has_key?(paths, cell) end)
        |> Enum.reject(fn {cell, _previous} -> MapSet.member?(blocked, cell) end)
        |> Enum.uniq_by(fn {cell, _previous} -> cell end)

      new_paths =
        Enum.reduce(new_steps, paths, fn {cell, previous}, paths ->
          Map.put(paths, cell, Map.fetch!(paths, previous) ++ [cell])
        end)

      new_frontier = Enum.map(new_steps, fn {cell, _previous} -> cell end)
      {new_frontier, new_paths}
    end)
    |> elem(1)
  end

  def move_detective(state, detective_id, destination) do
    if :move in state.turn_actions_remaining do
      valid = valid_detective_destinations(state, detective_id)

      if destination in valid do
        state =
          move_player(
            state,
            :detective,
            detective_id,
            destination,
            elem(state.dice, 0),
            detective_movement_blocked_cells(state)
          )

        {:ok, state}
      else
        {:error, :invalid_move}
      end
    else
      {:error, :invalid_move}
    end
  end

  defp move_player(state, role, player_id, destination, allowance, blocked) do
    current = player_position(state, role, player_id)
    origin = movement_origin(state, current)

    state =
      if destination == origin do
        %{state | movement_path: [], movement_spent: 0}
      else
        movement_path =
          origin
          |> bfs_paths(movement_limit(allowance), blocked)
          |> Map.fetch!(destination)

        %{state | movement_path: movement_path, movement_spent: length(movement_path) - 1}
      end

    state = put_player_position(state, role, player_id, destination)

    if state.movement_path == [] do
      clear_current_movement_event(state, player_id)
    else
      Replay.put_movement_event(state, role, player_id, state.movement_path)
    end
  end

  defp player_position(state, :thief, _player_id), do: state.thief_position
  defp player_position(state, :detective, player_id), do: state.detective_positions[player_id]

  defp put_player_position(state, :thief, _player_id, destination) do
    %{state | thief_position: destination}
  end

  defp put_player_position(state, :detective, player_id, destination) do
    %{state | detective_positions: Map.put(state.detective_positions, player_id, destination)}
  end

  defp movement_origin(%{movement_path: [origin | _path]}, _current), do: origin
  defp movement_origin(%{movement_path: []}, current), do: current

  defp clear_current_movement_event(state, actor_id) do
    case Enum.find_index(state.replay_events, fn event ->
           event.type == :move and event.turn_index == state.turn_index and
             event.actor_id == actor_id
         end) do
      nil -> state
      index -> %{state | replay_events: List.delete_at(state.replay_events, index)}
    end
  end

  defp movement_limit(allowance, max_steps \\ nil) do
    case max_steps do
      nil -> allowance
      max_steps -> min(allowance, max_steps)
    end
  end

  # --- Dice ---

  def roll_dice do
    number = Enum.random(1..6)
    picture = Enum.random([:eye, :eye, :eye, :eye, :camera_scan, :motion])
    {number, picture}
  end

  # --- Escape ---

  def try_escape(state, exit_id) do
    with %{} = entry <- Board.entry_by_id(exit_id) do
      adj_cell = Board.exit_adjacent_cell(entry)

      if state.thief_position == adj_cell do
        lock_result = Map.get(state.locks, exit_id, :open)

        state =
          Replay.append_event(state, %{
            type: :lock_check,
            actor_id: state.thief_player_id,
            actor_role: :thief,
            path: [state.thief_position],
            from: state.thief_position,
            to: state.thief_position,
            result: lock_result,
            label: "#{player_name(state, state.thief_player_id)} checked the #{entry.label} lock."
          })

        case lock_result do
          :open ->
            finish_escape(state, entry)

          :locked ->
            {:ok, :locked,
             state
             |> spend_movement()
             |> put_detective_result({:escape_locked, exit_id})}
        end
      else
        {:error, :not_adjacent}
      end
    else
      _ -> {:error, :invalid_entry}
    end
  end

  defp finish_escape(state, entry) do
    state =
      state
      |> commit_thief_movement()
      |> put_thief_exit_history(entry)
      |> resolve_pending_steal()
      |> Replay.append_event(%{
        type: :escape,
        actor_id: state.thief_player_id,
        actor_role: :thief,
        path: exit_path(state.thief_position, Board.exit_door_cell(entry)),
        from: state.thief_position,
        to: Board.exit_door_cell(entry),
        result: :escaped,
        label: "#{player_name(state, state.thief_player_id)} escaped through #{entry.label}."
      })

    if limited_escape_without_enough_art?(state) do
      {:ok, :escaped_without_enough_art,
       finish_round(state, :detectives, :escaped_without_enough_art)}
    else
      {:ok, :escaped, finish_round(state, :thief, :escaped)}
    end
  end

  defp limited_escape_without_enough_art?(%{game_mode: :limited, stolen_count: stolen_count}) do
    stolen_count < @limited_escape_stolen_count
  end

  defp limited_escape_without_enough_art?(_state), do: false

  # --- Turn Advancement ---

  def end_turn(state) do
    cond do
      :move in state.turn_actions_remaining and not movement_made?(state) ->
        {:error, :movement_required}

      true ->
        state =
          state
          |> resolve_power_room_turn_end()
          |> commit_thief_movement()

        if detective_caught_thief?(state) do
          {:ok, catch_thief(state)}
        else
          {:ok, advance_turn(state)}
        end
    end
  end

  defp resolve_power_room_turn_end(state) do
    cond do
      state.current_turn == state.thief_player_id ->
        turn_power_off_on_power_room(state, state.thief_position)

      Map.has_key?(state.detective_positions, state.current_turn) ->
        turn_power_on_from_detective_action(state, state.current_turn)

      true ->
        state
    end
  end

  defp turn_power_off_on_power_room(%{power_active: true} = state, pos) do
    if power_room?(pos) do
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
    else
      state
    end
  end

  defp turn_power_off_on_power_room(state, _pos), do: state

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

  defp power_room?(pos) do
    case Board.cell(pos) do
      %{type: :power_room} -> true
      _cell -> false
    end
  end

  defp detective_caught_thief?(state) do
    Map.get(state.detective_positions, state.current_turn) == state.thief_position
  end

  defp catch_thief(state) do
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
  end

  def advance_turn(state) do
    [_ | rest] = state.turn_order
    new_order = rest ++ [hd(state.turn_order)]
    next_player = hd(new_order)
    {actions, dice} = turn_setup(state, next_player)

    state = if thief_turn?(state, next_player), do: resolve_pending_steal(state), else: state

    %{
      state
      | turn_order: new_order,
        current_turn: next_player,
        turn_actions_remaining: actions,
        dice: dice,
        motion_detector_decision: nil,
        movement_path: [],
        movement_spent: 0,
        turn_index: state.turn_index + 1
    }
  end

  def start_next_round(
        %State{phase: :round_review, game_mode: :full, round_results: [_ | _] = round_results} =
          state
      ) do
    round_result = List.last(round_results)
    {:ok, start_next_full_round(state, state.artwork_scores, round_results, round_result)}
  end

  def start_next_round(_state), do: {:error, :invalid_phase}

  # --- Helpers ---

  defp turn_setup(state, player_id) do
    cond do
      thief_turn?(state, player_id) ->
        {[:move], nil}

      state.chase_mode ->
        {[:move], {roll_number_die(), nil}}

      true ->
        {[:move, :look], roll_dice()}
    end
  end

  defp movement_made?(state), do: state.movement_path != [] and state.movement_spent > 0

  defp roll_number_die, do: Enum.random(1..6)

  defp thief_turn?(state, player_id), do: player_id == state.thief_player_id

  defp finish_round(%{game_mode: :full} = state, outcome, reason) do
    state = put_round_end_replay_event(state, outcome, reason)
    scored_count = scored_stolen_count(outcome, state.stolen_count)

    artwork_scores =
      Map.update(state.artwork_scores, state.thief_player_id, scored_count, fn score ->
        score + scored_count
      end)

    round_result = %{
      round_number: state.round_number,
      thief_player_id: state.thief_player_id,
      stolen_count: scored_count,
      outcome: outcome,
      reason: reason,
      thief_history: state.thief_history,
      replay_events: state.replay_events
    }

    round_results = state.round_results ++ [round_result]

    if state.round_number >= length(state.thief_rotation) do
      winners = winning_player_ids(artwork_scores, state.thief_rotation)

      %{
        state
        | phase: :game_over,
          winner: full_game_winner(winners),
          game_over_reason: :all_thieves_played,
          artwork_scores: artwork_scores,
          round_results: round_results,
          winning_player_ids: winners,
          pending_steal: nil
      }
    else
      %{
        state
        | phase: :round_review,
          artwork_scores: artwork_scores,
          round_results: round_results,
          current_turn: nil,
          turn_actions_remaining: [],
          dice: nil,
          motion_detector_decision: nil,
          detective_result: nil,
          pending_steal: nil,
          movement_path: [],
          movement_spent: 0
      }
    end
  end

  defp finish_round(state, outcome, reason) do
    state = put_round_end_replay_event(state, outcome, reason)
    winner = if outcome == :thief, do: :thief, else: :detectives
    %{state | phase: :game_over, winner: winner, game_over_reason: reason}
  end

  defp scored_stolen_count(:thief, stolen_count), do: stolen_count
  defp scored_stolen_count(:detectives, _stolen_count), do: 0

  defp start_next_full_round(state, artwork_scores, round_results, round_result) do
    next_round_number = state.round_number + 1
    next_thief_id = Enum.at(state.thief_rotation, state.round_number)
    role_order = [next_thief_id | Enum.reject(state.thief_rotation, &(&1 == next_thief_id))]
    players = assign_round_roles(state.players, role_order, next_thief_id)

    State.new_game(players, role_order, state.host_player_id,
      game_mode: :full,
      thief_rotation: state.thief_rotation,
      round_number: next_round_number,
      artwork_scores: artwork_scores,
      round_results: round_results,
      game_log: next_round_log(state, round_result, next_round_number, next_thief_id)
    )
  end

  defp assign_round_roles(players, role_order, thief_id) do
    role_order
    |> Enum.with_index()
    |> Map.new(fn {player_id, index} ->
      player = players[player_id]
      role = if player_id == thief_id, do: :thief, else: :detective
      color = round_player_color(role, index)
      {player_id, %{player | role: role, color: color}}
    end)
  end

  defp round_player_color(:thief, _index), do: :grey

  defp round_player_color(:detective, index) do
    PawnColors.all()
    |> Enum.at(index - 1, PawnColors.default())
  end

  defp next_round_log(state, round_result, next_round_number, next_thief_id) do
    state.game_log ++
      [
        round_result_message(state, round_result),
        "#{player_name(state, next_thief_id)} is the thief for round #{next_round_number}."
      ]
  end

  defp round_result_message(
         state,
         %{round_number: round_number, stolen_count: stolen_count} = result
       ) do
    outcome =
      case result.outcome do
        :thief -> "escaped"
        :detectives -> "was caught"
      end

    "Round #{round_number}: #{player_name(state, result.thief_player_id)} stole #{stolen_count} #{artwork_word(stolen_count)} and #{outcome}."
  end

  defp winning_player_ids(scores, rotation) do
    max_score = scores |> Map.values() |> Enum.max(fn -> 0 end)
    Enum.filter(rotation, fn player_id -> Map.get(scores, player_id, 0) == max_score end)
  end

  defp full_game_winner([_player_id]), do: :player
  defp full_game_winner(_player_ids), do: :tie

  defp artwork_word(1), do: "artwork"
  defp artwork_word(_count), do: "artworks"

  defp player_name(state, player_id) do
    case Map.get(state.players, player_id) do
      %{name: name} -> name
      nil -> "Unknown player"
    end
  end

  defp put_thief_exit_history(state, entry) do
    exit = %{id: entry.id, label: entry.label, position: Board.exit_door_cell(entry)}
    put_in(state.thief_history.exit, exit)
  end

  defp thief_entry_history(entry, pos) do
    %{
      entry: %{id: entry.id, label: entry.label, position: pos},
      exit: nil,
      moves: []
    }
  end

  defp entry_path(%{type: :door} = entry, pos), do: [Board.exit_door_cell(entry), pos]
  defp entry_path(_entry, pos), do: [pos]

  defp exit_path(from, to) when from == to, do: [to]
  defp exit_path(from, to), do: [from, to]

  defp position_label({row, col}), do: "#{row}-#{col}"

  defp put_round_end_replay_event(state, outcome, reason) do
    Replay.append_event(state, %{
      type: :round_end,
      actor_id: state.thief_player_id,
      actor_role: :thief,
      path: [],
      from: nil,
      to: nil,
      result: reason,
      label:
        round_result_message(state, %{
          round_number: state.round_number,
          thief_player_id: state.thief_player_id,
          stolen_count: scored_stolen_count(outcome, state.stolen_count),
          outcome: outcome
        })
    })
  end

  defp commit_thief_movement(state) do
    if state.current_turn == state.thief_player_id and movement_made?(state) do
      update_in(state.thief_history.moves, &(&1 ++ [%{path: state.movement_path}]))
    else
      state
    end
  end

  defp lock_entry(state, entry_id) do
    locked_count = Enum.count(state.locks, fn {_id, status} -> status == :locked end)

    if locked_count < Board.lock_count() do
      locks = Map.put(state.locks, entry_id, :locked)
      setup_step = if locked_count + 1 >= Board.lock_count(), do: :paintings, else: :locks
      {:ok, %{state | locks: locks, setup_step: setup_step}}
    else
      {:error, :too_many_locks}
    end
  end

  defp thief_entry_turn_order(%{turn_order: [], thief_player_id: thief_id}), do: [thief_id]

  defp thief_entry_turn_order(%{turn_order: order, thief_player_id: thief_id}) do
    case Enum.reverse(order) do
      [^thief_id | rest] -> [thief_id | Enum.reverse(rest)]
      _ -> [thief_id | Enum.reject(order, &(&1 == thief_id))]
    end
  end

  defp motion_decision_pending?(state) do
    state.phase == :playing and state.dice != nil and elem(state.dice, 1) == :motion and
      :look in state.turn_actions_remaining and state.power_active and
      state.motion_snips_remaining > 0 and state.motion_detector_decision != :allowed
  end

  defp validate_painting_cell(pos) do
    if Board.painting_placeable_cell?(pos), do: :ok, else: {:error, :invalid_placement}
  end

  defp validate_painting_color_coverage(paintings) when map_size(paintings) < 9, do: :ok

  defp validate_painting_color_coverage(paintings) do
    painting_room_ids =
      paintings
      |> Map.keys()
      |> Enum.map(&Board.cell(&1).room_id)
      |> MapSet.new()

    if MapSet.subset?(Board.required_painting_room_ids(), painting_room_ids) do
      :ok
    else
      {:error, :missing_color_room}
    end
  end

  defp validate_unoccupied(state, pos, checks) do
    occupied =
      Enum.any?(checks, fn check ->
        case check do
          :paintings -> Map.has_key?(state.paintings, pos)
          :cameras -> Enum.any?(state.cameras, fn {_, v} -> v && v.pos == pos end)
          :detective_positions -> Enum.any?(state.detective_positions, fn {_, v} -> v == pos end)
        end
      end)

    if occupied, do: {:error, :cell_occupied}, else: :ok
  end

  # --- Look Actions ---

  def use_eye_action(state, detective_id) do
    pos = state.detective_positions[detective_id]

    state =
      state
      |> spend_eye_look()
      |> turn_power_on_from_detective_action(detective_id)

    if Board.can_see?(pos, state.thief_position) do
      {:ok, :chase_triggered, spot_thief(state, {:look_pawn, :chase_triggered})}
    else
      {:ok, :no_sighting, put_detective_result(state, {:look_pawn, :no_sighting})}
    end
  end

  def use_eye_on_camera(state, detective_id, camera_id) do
    state =
      state
      |> spend_eye_look()
      |> turn_power_on_from_detective_action(detective_id)

    if not state.power_active do
      {:ok, :power_off,
       state
       |> Map.put(:power_revealed, true)
       |> put_detective_result({:look_camera, :power_off})}
    else
      cam = state.cameras[camera_id]

      cond do
        cam == nil ->
          state = put_detective_result(state, {:look_camera, :camera_disabled})

          {:ok, :camera_disabled, state}

        cam.status == :disabled ->
          state =
            state
            |> Map.put(:cameras, Map.put(state.cameras, camera_id, Map.put(cam, :revealed, true)))
            |> put_detective_result({:look_camera, :camera_disabled})

          {:ok, :camera_disabled, state}

        Board.can_see?(cam.pos, state.thief_position) ->
          result = {:sighting, camera_id}
          {:ok, result, put_detective_result(state, {:look_camera, result})}

        true ->
          {:ok, :no_sighting,
           put_detective_result(state, {:look_camera, {:no_sighting, camera_id}})}
      end
    end
  end

  defp spend_eye_look(state) do
    if movement_made?(state) do
      spend_look_and_movement(state)
    else
      spend_look(state)
    end
  end

  defp spend_look_and_movement(state) do
    %{
      state
      | turn_actions_remaining:
          state.turn_actions_remaining
          |> List.delete(:look)
          |> List.delete(:move)
    }
  end

  defp spend_look(state) do
    %{state | turn_actions_remaining: List.delete(state.turn_actions_remaining, :look)}
  end

  defp spend_movement(state) do
    %{state | turn_actions_remaining: List.delete(state.turn_actions_remaining, :move)}
  end

  def use_camera_scan(state) do
    detective_id = state.current_turn

    state =
      state
      |> spend_look()
      |> turn_power_on_from_detective_action(detective_id)

    if not state.power_active do
      {:ok, :power_off,
       state
       |> Map.put(:power_revealed, true)
       |> put_detective_result({:camera_scan, :power_off})}
    else
      {disabled, active} =
        Enum.split_with(state.cameras, fn {_, v} -> v != nil and v.status == :disabled end)

      disabled_ids = Enum.map(disabled, &elem(&1, 0))

      cameras =
        Enum.reduce(disabled_ids, state.cameras, fn id, cameras ->
          case Map.get(cameras, id) do
            nil -> cameras
            camera -> Map.put(cameras, id, Map.put(camera, :revealed, true))
          end
        end)

      state = %{state | cameras: cameras}

      sighting_camera_ids =
        active
        |> Enum.filter(fn {_, cam} ->
          cam != nil and cam.status == :active and Board.can_see?(cam.pos, state.thief_position)
        end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      if sighting_camera_ids != [] do
        result = {:sighting, sighting_camera_ids}

        {:ok, disabled_ids, result,
         put_detective_result(state, {:camera_scan, disabled_ids, result})}
      else
        {:ok, disabled_ids, :no_sighting,
         put_detective_result(state, {:camera_scan, disabled_ids, :no_sighting})}
      end
    end
  end

  defp spot_thief(state, detective_result) do
    state = reveal_pending_steal_on_spot(state)

    state
    |> Map.put(:chase_mode, true)
    |> put_detective_result(detective_result)
  end

  defp reveal_pending_steal_on_spot(%{pending_steal: pos, thief_position: pos} = state) do
    resolve_pending_steal(state)
  end

  defp reveal_pending_steal_on_spot(state), do: state

  defp put_detective_result(state, result) do
    %{state | detective_result: result, detective_result_id: state.detective_result_id + 1}
  end

  def decide_motion_detector(state, player_id, decision) do
    cond do
      player_id != state.thief_player_id ->
        {:error, :not_thief}

      not motion_decision_pending?(state) ->
        {:error, :invalid_action}

      decision == :allow ->
        {:ok, :allowed,
         state
         |> Map.put(:motion_detector_decision, :allowed)
         |> put_detective_result({:motion, :allowed})}

      decision == :cut ->
        state =
          %{
            state
            | motion_snips_remaining: state.motion_snips_remaining - 1,
              motion_detector_decision: nil,
              turn_actions_remaining: List.delete(state.turn_actions_remaining, :look)
          }
          |> put_detective_result({:motion, :snipped})

        {:ok, :snipped, state}

      true ->
        {:error, :invalid_action}
    end
  end

  def use_motion_detector(state, opts \\ []) do
    if Keyword.get(opts, :snip, false) or motion_decision_pending?(state) do
      {:error, :motion_decision_pending}
    else
      read_motion_detector(state)
    end
  end

  defp read_motion_detector(state) do
    state = %{state | turn_actions_remaining: List.delete(state.turn_actions_remaining, :look)}

    if not state.power_active do
      {:ok, :power_off,
       state
       |> Map.put(:power_revealed, true)
       |> Map.put(:motion_detector_decision, nil)
       |> put_detective_result({:motion, :power_off})}
    else
      color = motion_detector_color(state.thief_position)

      {:ok, {:color, color},
       state
       |> Map.put(:motion_detector_decision, nil)
       |> put_detective_result({:motion, {:color, color}})}
    end
  end

  defp motion_detector_color(pos) do
    case Board.cell(pos) do
      %{room_id: room_id} when room_id in [:hall, :other_left, :other_right, :power_room] ->
        :gray

      %{color: color} ->
        color
    end
  end
end
