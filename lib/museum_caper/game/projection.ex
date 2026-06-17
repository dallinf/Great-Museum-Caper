defmodule MuseumCaper.Game.Projection do
  alias MuseumCaper.Game.Rules

  def project_state(state, player_id) do
    role = state.players[player_id].role

    base = %{
      phase: state.phase,
      setup_step: state.setup_step,
      current_turn: state.current_turn,
      turn_order: state.turn_order,
      players: state.players,
      game_mode: state.game_mode,
      thief_rotation: state.thief_rotation,
      round_number: state.round_number,
      artwork_scores: state.artwork_scores,
      round_results: state.round_results,
      winning_player_ids: state.winning_player_ids,
      detective_positions: state.detective_positions,
      paintings: filter_paintings(state.paintings, role),
      painting_labels: state.painting_labels,
      stolen_count: state.stolen_count,
      chase_mode: state.chase_mode,
      dice: state.dice,
      turn_actions_remaining: state.turn_actions_remaining,
      power_active: state.power_active,
      power_revealed: state.power_revealed,
      winner: state.winner,
      game_over_reason: state.game_over_reason,
      my_player_id: player_id,
      my_role: role
    }

    case role do
      :thief -> project_thief(state, player_id, base)
      :detective -> project_detective(state, player_id, base)
    end
  end

  defp project_thief(state, player_id, base) do
    valid_destinations =
      if state.current_turn == player_id and :move in state.turn_actions_remaining do
        Rules.valid_thief_destinations(state)
      else
        []
      end

    Map.merge(base, %{
      my_position: state.thief_position,
      thief_position: state.thief_position,
      cameras: state.cameras,
      motion_snips_remaining: state.motion_snips_remaining,
      pending_steal: state.pending_steal,
      valid_destinations: valid_destinations,
      exits: MuseumCaper.Game.Board.exits()
    })
  end

  defp project_detective(state, player_id, base) do
    thief_position = if state.chase_mode, do: state.thief_position, else: nil

    detective_cameras =
      Map.new(state.cameras, fn
        {id, nil} -> {id, nil}
        {id, %{status: :disabled, revealed: true} = cam} -> {id, cam}
        {id, cam} -> {id, %{cam | status: :active}}
      end)

    valid_destinations =
      if state.current_turn == player_id and :move in state.turn_actions_remaining and
           state.dice != nil do
        Rules.valid_detective_destinations(state, player_id)
      else
        []
      end

    Map.merge(base, %{
      thief_position: thief_position,
      cameras: detective_cameras,
      valid_destinations: valid_destinations
    })
  end

  defp filter_paintings(paintings, :thief), do: paintings

  defp filter_paintings(paintings, :detective) do
    paintings
    |> Map.new(fn
      {pos, :targeted} -> {pos, :present}
      painting -> painting
    end)
  end
end
