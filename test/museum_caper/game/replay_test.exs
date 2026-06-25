defmodule MuseumCaper.Game.ReplayTest do
  use ExUnit.Case, async: true

  alias MuseumCaper.Game.{Replay, State}

  @players %{
    "t" => %{name: "Theo", role: :thief, color: :grey},
    "d" => %{name: "Alice", role: :detective, color: :red}
  }

  @two_player_players %{
    "alice" => %{name: "Alice", role: :thief, color: :grey},
    "bob" => %{name: "Bob", role: :detective, color: :red}
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
               actor_color: "grey",
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

  test "payload_events uses stored actor colors from historical replay events" do
    state =
      @players
      |> State.new_game(["t", "d"], "t", game_mode: :full)
      |> Map.put(:players, %{
        "t" => %{name: "Theo", role: :detective, color: :yellow},
        "d" => %{name: "Alice", role: :thief, color: :grey}
      })

    historical_event = %{
      id: 1,
      round_number: 1,
      turn_index: 0,
      actor_id: "t",
      actor_role: :thief,
      actor_label: "Theo",
      actor_color: "grey",
      type: :enter,
      path: [{6, 1}, {6, 2}],
      from: {6, 1},
      to: {6, 2},
      result: nil,
      label: "Theo entered through D2."
    }

    assert [%{actor_color: "grey"}] = Replay.payload_events([historical_event], state)
  end

  test "append_event uses controlled detective pawn colors" do
    state =
      State.new_game(@two_player_players, ["alice", "bob"], "alice", game_mode: :full)

    state =
      Replay.append_event(state, %{
        type: :setup,
        actor_id: "bob:detective-1",
        actor_role: :detective,
        path: [{3, 9}],
        from: {3, 9},
        to: {3, 9},
        result: nil,
        label: nil
      })

    state =
      Replay.append_event(state, %{
        type: :setup,
        actor_id: "bob:detective-2",
        actor_role: :detective,
        path: [{9, 5}],
        from: {9, 5},
        to: {9, 5},
        result: nil,
        label: nil
      })

    assert [
             %{actor_id: "bob:detective-1", actor_color: "red"},
             %{actor_id: "bob:detective-2", actor_color: "purple"}
           ] = state.replay_events
  end

  test "payload_events includes replay object metadata" do
    state =
      @players
      |> State.new_game(["t", "d"], "t", game_mode: :full)
      |> Replay.append_event(%{
        type: :artwork,
        actor_id: "museum",
        actor_role: :museum,
        actor_label: "Museum",
        actor_color: :grey,
        object_id: "A1",
        object_label: "A1",
        path: [{3, 7}],
        from: {3, 7},
        to: {3, 7},
        result: :present,
        label: nil
      })

    assert [
             %{
               type: "artwork",
               actor_id: "museum",
               actor_role: "museum",
               object_id: "A1",
               object_label: "A1",
               result: "present"
             }
           ] = Replay.payload_events(state.replay_events, state)
  end
end
