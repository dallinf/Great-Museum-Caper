defmodule MuseumCaper.Game.Bot do
  alias MuseumCaper.Game.{Board, Rules}

  @painting_candidates [
    {1, 4},
    {3, 1},
    {3, 10},
    {7, 1},
    {6, 11},
    {4, 5},
    {10, 4},
    {1, 6},
    {6, 12}
  ]

  @camera_candidates [{3, 4}, {3, 5}, {3, 6}, {3, 7}]
  @detective_candidates [{2, 4}, {7, 2}, {3, 8}, {9, 5}]

  def next_action(%{phase: :setup} = state), do: setup_action(state)

  def next_action(%{phase: :thief_entry} = state) do
    if bot_player?(state, state.thief_player_id) do
      Board.entries()
      |> List.first()
      |> case do
        %{id: entry_id} -> {:enter_museum, entry_id}
        nil -> nil
      end
    end
  end

  def next_action(%{phase: :playing} = state) do
    cond do
      motion_decision_pending?(state) and bot_player?(state, state.thief_player_id) ->
        {:decide_motion_detector, state.thief_player_id, :allow}

      not bot_turn?(state) ->
        nil

      state.current_turn == state.thief_player_id ->
        thief_action(state)

      Map.has_key?(state.detective_positions, state.current_turn) ->
        detective_action(state, state.current_turn)

      true ->
        nil
    end
  end

  def next_action(_state), do: nil

  defp setup_action(%{setup_step: :locks} = state) do
    if bot_led_setup?(state) do
      state
      |> unlocked_entries()
      |> List.first()
      |> case do
        %{id: entry_id} -> {:toggle_lock, entry_id}
        nil -> nil
      end
    end
  end

  defp setup_action(%{setup_step: :paintings} = state) do
    if bot_led_setup?(state) do
      @painting_candidates
      |> Enum.find(&painting_placeable?(state, &1))
      |> case do
        nil -> nil
        pos -> {:place_painting, pos}
      end
    end
  end

  defp setup_action(%{setup_step: :cameras} = state) do
    with true <- bot_led_setup?(state),
         {:ok, camera_id} <- next_camera_id(state),
         pos when not is_nil(pos) <- Enum.find(@camera_candidates, &camera_placeable?(state, &1)) do
      {:place_camera, camera_id, pos}
    else
      _ -> nil
    end
  end

  defp setup_action(%{setup_step: :pawns} = state) do
    with true <- bot_led_setup?(state),
         detective_id when not is_nil(detective_id) <- next_unplaced_bot_detective_id(state),
         pos when not is_nil(pos) <-
           Enum.find(@detective_candidates, &detective_placeable?(state, &1)) do
      {:place_detective_pawn, detective_id, pos}
    else
      _ -> nil
    end
  end

  defp setup_action(_state), do: nil

  defp thief_action(state) do
    cond do
      :move in state.turn_actions_remaining and state.movement_spent == 0 ->
        state
        |> Rules.valid_thief_destinations()
        |> preferred_thief_destination(state)
        |> case do
          nil -> nil
          destination -> {:move_thief, destination}
        end

      turn_can_end?(state) ->
        :end_turn

      true ->
        nil
    end
  end

  defp detective_action(state, detective_id) do
    cond do
      :move in state.turn_actions_remaining and state.movement_spent == 0 ->
        state
        |> Rules.valid_detective_destinations(detective_id)
        |> Enum.sort()
        |> List.first()
        |> case do
          nil -> nil
          destination -> {:move_detective, detective_id, destination}
        end

      :look in state.turn_actions_remaining and state.dice != nil ->
        look_action(state, detective_id)

      turn_can_end?(state) ->
        :end_turn

      true ->
        nil
    end
  end

  defp look_action(state, detective_id) do
    case elem(state.dice, 1) do
      :eye -> {:use_eye_action, detective_id}
      :camera_scan -> :use_camera_scan
      :motion -> :use_motion_detector
      _action -> nil
    end
  end

  defp preferred_thief_destination([], _state), do: nil

  defp preferred_thief_destination(destinations, state) do
    destinations = Enum.sort(destinations)

    Enum.find(destinations, &(Map.get(state.paintings, &1) == :present)) ||
      List.first(destinations)
  end

  defp unlocked_entries(state) do
    locked_count = Enum.count(state.locks, fn {_id, status} -> status == :locked end)

    if locked_count < Board.lock_count() do
      Enum.filter(Board.entries(), fn %{id: entry_id} ->
        Map.get(state.locks, entry_id) == :open
      end)
    else
      []
    end
  end

  defp next_camera_id(state) do
    case Enum.find(state.cameras, fn {_id, camera} -> camera == nil end) do
      {camera_id, nil} -> {:ok, camera_id}
      nil -> {:error, :all_cameras_placed}
    end
  end

  defp next_unplaced_bot_detective_id(state) do
    state.detective_positions
    |> Map.keys()
    |> Enum.sort()
    |> Enum.find(fn detective_id ->
      Map.get(state.detective_positions, detective_id) == nil and
        detective_bot?(state, detective_id)
    end)
  end

  defp bot_led_setup?(state) do
    detective_controller_ids = detective_controller_ids(state)

    detective_controller_ids != [] and
      Enum.all?(detective_controller_ids, &bot_player?(state, &1))
  end

  defp detective_controller_ids(state) do
    state.detective_positions
    |> Map.keys()
    |> Enum.map(&controller_player_id(state, &1))
    |> Enum.uniq()
  end

  defp detective_bot?(state, detective_id) do
    state
    |> controller_player_id(detective_id)
    |> then(&bot_player?(state, &1))
  end

  defp bot_turn?(state) do
    state
    |> controller_player_id(state.current_turn)
    |> then(&bot_player?(state, &1))
  end

  defp bot_player?(state, player_id) do
    case Map.get(state.players, player_id) do
      nil -> false
      player -> Map.get(player, :bot?, false)
    end
  end

  defp controller_player_id(_state, nil), do: nil

  defp controller_player_id(state, turn_id) do
    state
    |> Map.get(:detective_controllers, %{})
    |> Map.get(turn_id, turn_id)
  end

  defp painting_placeable?(state, pos) do
    Board.painting_placeable_cell?(pos) and not occupied_for_setup?(state, pos)
  end

  defp camera_placeable?(state, pos) do
    Board.camera_placeable_cell?(pos) and not occupied_for_setup?(state, pos)
  end

  defp detective_placeable?(state, pos) do
    Board.detective_placeable_cell?(pos) and not occupied_for_setup?(state, pos)
  end

  defp occupied_for_setup?(state, pos) do
    Map.has_key?(state.paintings, pos) or camera_at?(state, pos) or
      Enum.any?(state.detective_positions, fn {_id, detective_pos} -> detective_pos == pos end)
  end

  defp camera_at?(state, pos) do
    Enum.any?(state.cameras, fn {_id, camera} -> camera != nil and camera.pos == pos end)
  end

  defp turn_can_end?(state) do
    not (:move in state.turn_actions_remaining and state.movement_spent == 0)
  end

  defp motion_decision_pending?(state) do
    state.phase == :playing and state.dice != nil and elem(state.dice, 1) == :motion and
      :look in state.turn_actions_remaining and state.power_active and
      state.motion_snips_remaining > 0 and state.motion_detector_decision != :allowed
  end
end
