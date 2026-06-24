defmodule MuseumCaper.Game.State do
  alias MuseumCaper.Game.Board

  @empty_thief_history %{entry: nil, exit: nil, moves: []}

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
            winner: nil,
            game_over_reason: nil

  def new_game(players, player_order \\ nil, host_player_id \\ nil, opts \\ [])
      when is_map(players) do
    player_order = player_order || Map.keys(players)
    host_player_id = host_player_id || List.first(player_order)
    game_mode = Keyword.get(opts, :game_mode, :limited)

    thief_id =
      Enum.find(player_order, fn player_id -> players[player_id].role == :thief end)

    detective_player_ids =
      Enum.filter(player_order, fn player_id -> players[player_id].role == :detective end)

    detective_ids = detective_ids(game_mode, player_order, detective_player_ids)
    detective_controllers = detective_controllers(detective_ids, detective_player_ids)

    entry_ids = Board.entries() |> Enum.map(& &1.id)
    locks = Map.new(entry_ids, fn id -> {id, :open} end)

    cameras = Map.new(1..4, fn n -> {n, nil} end)
    detective_positions = Map.new(detective_ids, fn id -> {id, nil} end)
    turn_order = alternating_turn_order(detective_ids, thief_id)
    thief_rotation = Keyword.get(opts, :thief_rotation, default_thief_rotation(thief_id))

    %__MODULE__{
      players: players,
      turn_order: turn_order,
      host_player_id: host_player_id,
      game_mode: game_mode,
      thief_rotation: thief_rotation,
      round_number: Keyword.get(opts, :round_number, 1),
      artwork_scores: Keyword.get(opts, :artwork_scores, default_scores(thief_rotation)),
      round_results: Keyword.get(opts, :round_results, []),
      winning_player_ids: Keyword.get(opts, :winning_player_ids, []),
      game_log: Keyword.get(opts, :game_log, []),
      thief_history: Keyword.get(opts, :thief_history, @empty_thief_history),
      thief_player_id: thief_id,
      locks: locks,
      cameras: cameras,
      detective_positions: detective_positions,
      detective_controllers: detective_controllers,
      phase: :setup
    }
  end

  def empty_thief_history, do: @empty_thief_history

  def controlled_detective_ids(controller_id) do
    ["#{controller_id}:detective-1", "#{controller_id}:detective-2"]
  end

  defp detective_ids(_game_mode, player_order, [controller_id]) when length(player_order) == 2 do
    controlled_detective_ids(controller_id)
  end

  defp detective_ids(_game_mode, _player_order, detective_player_ids), do: detective_player_ids

  defp detective_controllers(detective_ids, [controller_id]) when length(detective_ids) == 2 do
    if Enum.all?(detective_ids, &String.starts_with?(&1, "#{controller_id}:detective-")) do
      Map.new(detective_ids, fn detective_id -> {detective_id, controller_id} end)
    else
      self_controlled_detectives(detective_ids)
    end
  end

  defp detective_controllers(detective_ids, _detective_player_ids) do
    self_controlled_detectives(detective_ids)
  end

  defp self_controlled_detectives(detective_ids) do
    Map.new(detective_ids, fn detective_id -> {detective_id, detective_id} end)
  end

  defp alternating_turn_order([], thief_id), do: [thief_id]

  defp alternating_turn_order(detective_ids, thief_id) do
    Enum.flat_map(detective_ids, fn detective_id -> [detective_id, thief_id] end)
  end

  defp default_thief_rotation(nil), do: []
  defp default_thief_rotation(thief_id), do: [thief_id]

  defp default_scores(player_ids), do: Map.new(player_ids, fn player_id -> {player_id, 0} end)
end
