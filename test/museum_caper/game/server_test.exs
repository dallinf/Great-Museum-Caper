defmodule MuseumCaper.Game.ServerTest do
  use ExUnit.Case, async: true
  alias MuseumCaper.Game.{Board, Server}

  @players %{
    "t" => %{name: "Thief", role: :thief, color: :grey},
    "d1" => %{name: "Det1", role: :detective, color: :red},
    "d2" => %{name: "Det2", role: :detective, color: :blue}
  }

  setup do
    game_id = "test-#{System.unique_integer()}"
    pid = start_game_server!(game_id, @players)
    {:ok, pid: pid, game_id: game_id}
  end

  test "starts with setup phase", %{pid: pid} do
    state = Server.get_state(pid)
    assert state.phase == :setup
    assert state.setup_step == :locks
  end

  test "toggle_lock updates state", %{pid: pid} do
    {:ok, _} = Server.toggle_lock(pid, :exit_w1)
    state = Server.get_state(pid)
    assert state.locks[:exit_w1] == :locked
  end

  test "place_painting updates state", %{pid: pid} do
    advance_to_paintings(pid)
    {:ok, _} = Server.place_painting(pid, {1, 4})
    state = Server.get_state(pid)
    assert state.paintings[{1, 4}] == :present
    assert state.painting_labels[{1, 4}] == "A1"
  end

  test "returns error for invalid painting placement", %{pid: pid} do
    advance_to_paintings(pid)
    assert {:error, :invalid_placement} = Server.place_painting(pid, {3, 5})
  end

  test "broadcasts state_changed after each action", %{pid: pid, game_id: game_id} do
    Phoenix.PubSub.subscribe(MuseumCaper.PubSub, "game:#{game_id}")
    Server.toggle_lock(pid, :exit_w1)
    assert_receive {:state_changed, _state}, 500
  end

  test "ends detective turn after moved detective uses pawn look", %{pid: pid} do
    set_moved_detective_look_turn!(pid, {1, :eye})

    assert {:ok, _state} = Server.move_detective(pid, "d1", {3, 8})
    assert {:ok, :no_sighting} = Server.use_eye_action(pid, "d1")

    state = Server.get_state(pid)
    assert state.current_turn == "t"
    assert state.turn_order == ["t", "d2", "t", "d1"]
    assert state.turn_actions_remaining == [:move]
    assert state.dice == nil
    assert state.detective_result == {:look_pawn, :no_sighting}
  end

  test "ends detective turn after moved detective uses camera scan", %{pid: pid} do
    set_moved_detective_look_turn!(pid, {1, :camera_scan})

    assert {:ok, _state} = Server.move_detective(pid, "d1", {3, 8})
    assert {:ok, [], :no_sighting} = Server.use_camera_scan(pid)

    state = Server.get_state(pid)
    assert state.current_turn == "t"
    assert state.turn_order == ["t", "d2", "t", "d1"]
    assert state.turn_actions_remaining == [:move]
    assert state.dice == nil
    assert state.detective_result == {:camera_scan, [], :no_sighting}
  end

  test "players can join a lobby game before it starts" do
    game_id = "join-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert :ok = Server.add_player(pid, "bob", "Bob")

    state = Server.get_state(pid)
    assert state.phase == :lobby
    assert state.players["alice"].role == :unassigned
    assert state.players["bob"].role == :unassigned
    assert state.turn_order == ["alice", "bob"]
  end

  test "players can choose an available pawn color when joining" do
    game_id = "join-color-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice", :purple)

    state = Server.get_state(pid)
    assert state.players["alice"].color == :purple
  end

  test "players cannot choose a pawn color already taken in the lobby" do
    game_id = "duplicate-color-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice", :purple)
    assert {:error, :color_taken} = Server.add_player(pid, "bob", "Bob", :purple)

    state = Server.get_state(pid)
    refute Map.has_key?(state.players, "bob")
  end

  test "players cannot choose a pawn color outside the allowed set" do
    game_id = "invalid-color-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert {:error, :invalid_color} = Server.add_player(pid, "alice", "Alice", :orange)
    assert Server.get_state(pid).players == %{}
  end

  test "empty lobby game requires two players before starting" do
    game_id = "empty-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert {:error, :not_enough_players} = Server.start_game(pid, "alice")
  end

  test "only host can start the game" do
    game_id = "host-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert :ok = Server.add_player(pid, "bob", "Bob")

    assert {:error, :not_host} = Server.start_game(pid, "bob")
    assert Server.get_state(pid).phase == :lobby
  end

  test "start_game randomly assigns one thief and all other players as detectives" do
    game_id = "lobby-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert :ok = Server.add_player(pid, "bob", "Bob")
    assert :ok = Server.add_player(pid, "cora", "Cora")

    assert {:ok, state} = Server.start_game(pid, "alice", shuffle: &Enum.reverse/1)
    assert state.phase == :setup
    assert state.thief_player_id == "cora"
    assert state.players["cora"].role == :thief
    assert state.players["alice"].role == :detective
    assert state.players["bob"].role == :detective
    assert state.turn_order == ["bob", "cora", "alice", "cora"]
  end

  test "start_game preserves detective pawn colors and assigns gray to the thief" do
    game_id = "lobby-colors-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice", :purple)
    assert :ok = Server.add_player(pid, "bob", "Bob", :green)
    assert :ok = Server.add_player(pid, "cora", "Cora", :yellow)

    assert {:ok, state} = Server.start_game(pid, "alice", shuffle: &Enum.reverse/1)
    assert state.players["cora"].role == :thief
    assert state.players["cora"].color == :grey
    assert state.players["bob"].role == :detective
    assert state.players["bob"].color == :green
    assert state.players["alice"].role == :detective
    assert state.players["alice"].color == :purple
  end

  test "start_game preserves the original lobby host" do
    game_id = "preserve-host-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert :ok = Server.add_player(pid, "bob", "Bob")
    assert :ok = Server.add_player(pid, "cora", "Cora")

    assert {:ok, state} = Server.start_game(pid, "alice", shuffle: &Enum.reverse/1)
    assert state.host_player_id == "alice"
    assert state.thief_player_id == "cora"
  end

  test "existing players can reconnect after the game starts" do
    game_id = "rejoin-#{System.unique_integer()}"
    pid = start_game_server!(game_id, %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert :ok = Server.add_player(pid, "bob", "Bob")
    assert {:ok, _state} = Server.start_game(pid, "alice")

    assert :ok = Server.add_player(pid, "alice", "Alice Back")
    state = Server.get_state(pid)
    assert state.players["alice"].name == "Alice Back"
    assert state.players["alice"].role in [:thief, :detective]
  end

  defp advance_to_paintings(pid) do
    Board.entries()
    |> Enum.take(Board.lock_count())
    |> Enum.each(fn %{id: entry_id} ->
      assert {:ok, _state} = Server.toggle_lock(pid, entry_id)
    end)
  end

  defp start_game_server!(game_id, players) do
    start_supervised!(%{
      id: {Server, game_id},
      start: {Server, :start_link, [[game_id: game_id, players: players]]}
    })
  end

  defp set_moved_detective_look_turn!(pid, dice) do
    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | phase: :playing,
          current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          thief_position: {1, 4},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          dice: dice,
          turn_actions_remaining: [:move, :look],
          movement_path: [],
          movement_spent: 0
      }

      %{server_state | game_state: game_state}
    end)
  end
end
