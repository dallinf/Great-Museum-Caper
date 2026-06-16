defmodule MuseumCaper.Game.Rules do
  alias MuseumCaper.Game.{Board, State}

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
      state = %{state | detective_positions: det_positions}
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
          phase: :playing,
          turn_order: turn_order,
          current_turn: next_player,
          turn_actions_remaining: actions,
          dice: dice
      }

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
    state = check_power_room(state, pos)
    state = check_camera(state, pos)
    state = check_painting(state, pos)
    state
  end

  defp check_power_room(%{power_active: true} = state, pos) do
    if Board.cell(pos).type == :power_room,
      do: %{state | power_active: false},
      else: state
  end

  defp check_power_room(state, _pos), do: state

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

    bfs_distances(origin, max_steps, blocking_painting_cells(state))
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.delete(pos)
    |> MapSet.difference(detective_cells)
    |> MapSet.to_list()
  end

  defp active_painting_cells(state) do
    state.paintings
    |> Enum.reject(fn {_pos, status} -> status == :removed end)
    |> Enum.map(fn {pos, _status} -> pos end)
    |> MapSet.new()
  end

  defp blocking_painting_cells(state) do
    blocked = active_painting_cells(state)

    if state.chase_mode and state.paintings[state.thief_position] == :targeted do
      MapSet.delete(blocked, state.thief_position)
    else
      blocked
    end
  end

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
            blocking_painting_cells(state)
          )

        {:ok, check_detective_power_room(state, destination)}
      else
        {:error, :invalid_move}
      end
    else
      {:error, :invalid_move}
    end
  end

  defp check_detective_power_room(%{power_active: false} = state, pos) do
    if Board.cell(pos).type == :power_room,
      do: %{state | power_active: true, power_revealed: false},
      else: state
  end

  defp check_detective_power_room(state, _), do: state

  defp move_player(state, role, player_id, destination, allowance, blocked) do
    current = player_position(state, role, player_id)
    origin = movement_origin(state, current)

    state =
      if destination == origin do
        %{state | movement_path: [], movement_spent: 0}
      else
        distance =
          origin
          |> bfs_distances(movement_limit(allowance), blocked)
          |> Map.fetch!(destination)

        %{state | movement_path: [origin, destination], movement_spent: distance}
      end

    put_player_position(state, role, player_id, destination)
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
        case Map.get(state.locks, exit_id, :open) do
          :open ->
            {:ok, :escaped,
             %{state | phase: :game_over, winner: :thief, game_over_reason: :escaped}}

          :locked ->
            {:ok, :locked, put_detective_result(state, {:escape_locked, exit_id})}
        end
      else
        {:error, :not_adjacent}
      end
    else
      _ -> {:error, :invalid_entry}
    end
  end

  # --- Turn Advancement ---

  def end_turn(state) do
    cond do
      :move in state.turn_actions_remaining and not movement_made?(state) ->
        {:error, :movement_required}

      detective_caught_thief?(state) ->
        {:ok, catch_thief(state)}

      true ->
        {:ok, advance_turn(state)}
    end
  end

  defp detective_caught_thief?(state) do
    case Map.get(state.players, state.current_turn) do
      %{role: :detective} ->
        Map.get(state.detective_positions, state.current_turn) == state.thief_position

      _player ->
        false
    end
  end

  defp catch_thief(state) do
    %{state | phase: :game_over, winner: :detectives, game_over_reason: :caught}
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
        movement_spent: 0
    }
  end

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
    state = spend_look_and_movement(state)

    if Board.can_see?(pos, state.thief_position) do
      {:ok, :chase_triggered, spot_thief(state, {:look_pawn, :chase_triggered})}
    else
      {:ok, :no_sighting, put_detective_result(state, {:look_pawn, :no_sighting})}
    end
  end

  def use_eye_on_camera(state, _detective_id, camera_id) do
    state = spend_camera_eye_look(state)

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

  defp spend_camera_eye_look(state) do
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

  def use_camera_scan(state) do
    state = spend_look(state)

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
