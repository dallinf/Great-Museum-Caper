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

  def put_movement_event(state, _role, _actor_id, path) when length(path) < 2 do
    state
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
      label:
        "#{actor_label(state, actor_id)} moved #{length(path) - 1} #{space_word(length(path) - 1)}."
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
