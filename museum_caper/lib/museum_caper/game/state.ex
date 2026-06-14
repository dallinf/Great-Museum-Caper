defmodule MuseumCaper.Game.State do
  alias MuseumCaper.Game.Board

  defstruct players: %{},
            turn_order: [],
            current_turn: nil,
            phase: :lobby,
            setup_step: :locks,
            host_player_id: nil,
            thief_player_id: nil,
            thief_position: nil,
            motion_snips_remaining: 2,
            motion_detector_decision: nil,
            detective_result: nil,
            game_log: [],
            pending_steal: nil,
            stolen_count: 0,
            locks: %{},
            paintings: %{},
            painting_labels: %{},
            cameras: %{},
            detective_positions: %{},
            power_active: true,
            power_revealed: false,
            chase_mode: false,
            dice: nil,
            turn_actions_remaining: [],
            winner: nil,
            game_over_reason: nil

  def new_game(players, player_order \\ nil, host_player_id \\ nil) when is_map(players) do
    player_order = player_order || Map.keys(players)
    host_player_id = host_player_id || List.first(player_order)

    thief_id =
      Enum.find(player_order, fn player_id -> players[player_id].role == :thief end)

    detective_ids =
      Enum.filter(player_order, fn player_id -> players[player_id].role == :detective end)

    entry_ids = Board.entries() |> Enum.map(& &1.id)
    locks = Map.new(entry_ids, fn id -> {id, :open} end)

    cameras = Map.new(1..4, fn n -> {n, nil} end)
    detective_positions = Map.new(detective_ids, fn id -> {id, nil} end)
    turn_order = alternating_turn_order(detective_ids, thief_id)

    %__MODULE__{
      players: players,
      turn_order: turn_order,
      host_player_id: host_player_id,
      thief_player_id: thief_id,
      locks: locks,
      cameras: cameras,
      detective_positions: detective_positions,
      phase: :setup
    }
  end

  defp alternating_turn_order([], thief_id), do: [thief_id]

  defp alternating_turn_order(detective_ids, thief_id) do
    Enum.flat_map(detective_ids, fn detective_id -> [detective_id, thief_id] end)
  end
end
