defmodule MuseumCaper.Game.BotTest do
  use ExUnit.Case, async: true
  alias MuseumCaper.Game.{Board, Bot, Rules, Server, State}

  test "chooses lock placement during detective setup" do
    state = bot_setup_state("human")

    assert {:toggle_lock, entry_id} = Bot.next_action(state)
    assert entry_id in Enum.map(Board.entries(), & &1.id)
  end

  test "does not choose setup actions when a human detective can set up" do
    state = bot_setup_state("bot-1")

    assert Bot.next_action(state) == nil
  end

  test "chooses thief entry when bot thief is entering" do
    state = %{bot_setup_state("bot-1") | phase: :thief_entry}

    assert {:enter_museum, entry_id} = Bot.next_action(state)
    assert Board.entry_by_id(entry_id) != nil
  end

  test "chooses detective movement during a bot detective turn" do
    detective_id = "bot-1:detective-1"

    state =
      bot_playing_state()
      |> Map.put(:current_turn, detective_id)
      |> Map.put(:turn_actions_remaining, [:move])
      |> Map.put(:dice, {1, nil})

    assert {:move_detective, ^detective_id, destination} = Bot.next_action(state)
    assert destination in Rules.valid_detective_destinations(state, detective_id)
  end

  test "chooses to end a bot thief turn after moving" do
    state =
      bot_setup_state("bot-1")
      |> Map.merge(%{
        phase: :playing,
        current_turn: "bot-1",
        thief_position: {7, 6},
        detective_positions: %{"human:detective-1" => {2, 4}, "human:detective-2" => {7, 2}},
        turn_order: ["bot-1", "human:detective-1", "bot-1", "human:detective-2"],
        turn_actions_remaining: [:move],
        movement_path: [{10, 6}, {7, 6}],
        movement_spent: 3
      })

    assert Bot.next_action(state) == :end_turn
  end

  test "chooses to allow motion detector readings when the thief is a bot" do
    state =
      bot_setup_state("bot-1")
      |> Map.merge(%{
        phase: :playing,
        current_turn: "human:detective-1",
        thief_position: {1, 4},
        detective_positions: %{"human:detective-1" => {3, 9}, "human:detective-2" => {9, 5}},
        dice: {3, :motion},
        turn_actions_remaining: [:move, :look]
      })

    assert {:decide_motion_detector, "bot-1", :allow} = Bot.next_action(state)
  end

  test "server automatically advances bot setup actions after bot start" do
    game_id = "bot-auto-#{System.unique_integer()}"
    pid = start_game_server!(game_id)

    Phoenix.PubSub.subscribe(MuseumCaper.PubSub, "game:#{game_id}")

    assert :ok = Server.add_player(pid, "alice", "Alice", :purple)

    assert {:ok, _state} =
             Server.start_game(pid, "alice",
               with_bots?: true,
               shuffle: fn _order -> ["alice", "bot-1"] end
             )

    state = assert_state_changed_until(&(&1.phase == :thief_entry))

    assert Enum.count(state.locks, fn {_id, status} -> status == :locked end) ==
             Board.lock_count()

    assert map_size(state.paintings) == 9
    assert Enum.count(state.cameras, fn {_id, camera} -> camera != nil end) == 4
    assert Enum.all?(state.detective_positions, fn {_id, pos} -> pos != nil end)
  end

  test "server leaves setup for the human when the human is a detective" do
    game_id = "bot-human-setup-#{System.unique_integer()}"
    pid = start_game_server!(game_id)

    assert :ok = Server.add_player(pid, "alice", "Alice", :purple)

    Phoenix.PubSub.subscribe(MuseumCaper.PubSub, "game:#{game_id}")

    assert {:ok, _state} =
             Server.start_game(pid, "alice",
               with_bots?: true,
               shuffle: fn _order -> ["bot-1", "alice"] end
             )

    assert_receive {:state_changed, %{phase: :setup}}
    refute_receive {:state_changed, _state}, 100

    state = Server.get_state(pid)
    assert state.players["alice"].role == :detective

    assert MapSet.new(Map.keys(state.detective_positions)) ==
             MapSet.new(["alice:detective-1", "alice:detective-2"])

    assert Enum.count(state.locks, fn {_id, status} -> status == :locked end) == 0
    assert state.paintings == %{}
    assert Enum.all?(state.cameras, fn {_id, camera} -> camera == nil end)
    assert Enum.all?(state.detective_positions, fn {_id, pos} -> pos == nil end)
  end

  test "server advances a bot thief turn after human-led setup completes" do
    game_id = "bot-thief-after-setup-#{System.unique_integer()}"
    pid = start_game_server!(game_id)

    assert :ok = Server.add_player(pid, "alice", "Alice", :purple)

    Phoenix.PubSub.subscribe(MuseumCaper.PubSub, "game:#{game_id}")

    assert {:ok, _state} =
             Server.start_game(pid, "alice",
               with_bots?: true,
               shuffle: fn _order -> ["bot-1", "alice"] end
             )

    place_complete_setup!(pid, ["alice:detective-1", "alice:detective-2"])

    state =
      assert_state_changed_until(fn state ->
        state.phase == :playing and state.current_turn == "alice:detective-1" and
          state.thief_player_id == "bot-1" and state.thief_position != nil
      end)

    assert state.current_turn == "alice:detective-1"
    assert state.players["alice"].role == :detective
  end

  test "server automatically advances a scheduled bot detective turn" do
    game_id = "bot-turn-#{System.unique_integer()}"

    players = %{
      "alice" => %{name: "Alice", role: :thief, color: :grey, bot?: false},
      "bot-1" => %{name: "Bot 1", role: :detective, color: :green, bot?: true}
    }

    pid = start_game_server!(game_id, players)

    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | phase: :playing,
          current_turn: "bot-1:detective-1",
          turn_order: ["bot-1:detective-1", "alice", "bot-1:detective-2", "alice"],
          thief_position: {1, 4},
          detective_positions: %{
            "bot-1:detective-1" => {3, 9},
            "bot-1:detective-2" => {9, 5}
          },
          detective_controllers: %{
            "bot-1:detective-1" => "bot-1",
            "bot-1:detective-2" => "bot-1"
          },
          dice: {1, nil},
          turn_actions_remaining: [:move]
      }

      %{server_state | game_state: game_state}
    end)

    Phoenix.PubSub.subscribe(MuseumCaper.PubSub, "game:#{game_id}")

    send(pid, :run_bots)

    state =
      assert_state_changed_until(fn state ->
        state.phase == :playing and state.current_turn == "alice" and
          state.detective_positions["bot-1:detective-1"] != {3, 9}
      end)

    assert state.current_turn == "alice"
  end

  defp bot_setup_state(thief_id) do
    player_ids = ["human", "bot-1"]
    order = [thief_id | Enum.reject(player_ids, &(&1 == thief_id))]

    players =
      Map.new(player_ids, fn player_id ->
        role = if player_id == thief_id, do: :thief, else: :detective
        color = if role == :thief, do: :grey, else: player_color(player_id)

        {player_id,
         %{
           name: player_name(player_id),
           role: role,
           color: color,
           bot?: String.starts_with?(player_id, "bot-")
         }}
      end)

    State.new_game(players, order)
  end

  defp bot_playing_state do
    %{
      bot_setup_state("human")
      | phase: :playing,
        thief_position: {1, 4},
        detective_positions: %{
          "bot-1:detective-1" => {3, 9},
          "bot-1:detective-2" => {9, 5}
        },
        turn_order: ["bot-1:detective-1", "human", "bot-1:detective-2", "human"]
    }
  end

  defp player_name("human"), do: "Human"
  defp player_name("bot-1"), do: "Bot 1"

  defp player_color("human"), do: :purple
  defp player_color("bot-1"), do: :green

  defp start_game_server!(game_id, players \\ %{}) do
    start_supervised!(%{
      id: {Server, game_id},
      start: {Server, :start_link, [[game_id: game_id, players: players]]}
    })
  end

  defp place_complete_setup!(pid, detective_ids) do
    Board.entries()
    |> Enum.take(Board.lock_count())
    |> Enum.each(fn %{id: entry_id} ->
      assert {:ok, _state} = Server.toggle_lock(pid, entry_id)
    end)

    Enum.each(painting_candidates(), fn pos ->
      assert {:ok, _state} = Server.place_painting(pid, pos)
    end)

    [{3, 4}, {3, 5}, {3, 6}, {3, 7}]
    |> Enum.with_index(1)
    |> Enum.each(fn {pos, camera_id} ->
      assert {:ok, _state} = Server.place_camera(pid, camera_id, pos)
    end)

    [{2, 4}, {7, 2}]
    |> Enum.zip(detective_ids)
    |> Enum.each(fn {pos, detective_id} ->
      assert {:ok, _state} = Server.place_detective_pawn(pid, detective_id, pos)
    end)
  end

  defp painting_candidates do
    [{1, 4}, {3, 1}, {3, 10}, {7, 1}, {6, 11}, {4, 5}, {10, 4}, {1, 6}, {6, 12}]
  end

  defp assert_state_changed_until(predicate, attempts \\ 40)

  defp assert_state_changed_until(_predicate, 0) do
    flunk("expected matching bot state change")
  end

  defp assert_state_changed_until(predicate, attempts) do
    assert_receive {:state_changed, state}, 1_000

    if predicate.(state) do
      state
    else
      assert_state_changed_until(predicate, attempts - 1)
    end
  end
end
