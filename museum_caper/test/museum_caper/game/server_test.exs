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
    {:ok, pid} = Server.start_link(game_id: game_id, players: @players)
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

  test "players can join a lobby game before it starts" do
    game_id = "join-#{System.unique_integer()}"
    {:ok, pid} = Server.start_link(game_id: game_id, players: %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert :ok = Server.add_player(pid, "bob", "Bob")

    state = Server.get_state(pid)
    assert state.phase == :lobby
    assert state.players["alice"].role == :unassigned
    assert state.players["bob"].role == :unassigned
    assert state.turn_order == ["alice", "bob"]
  end

  test "empty lobby game requires two players before starting" do
    game_id = "empty-#{System.unique_integer()}"
    {:ok, pid} = Server.start_link(game_id: game_id, players: %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert {:error, :not_enough_players} = Server.start_game(pid, "alice")
  end

  test "only host can start the game" do
    game_id = "host-#{System.unique_integer()}"
    {:ok, pid} = Server.start_link(game_id: game_id, players: %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert :ok = Server.add_player(pid, "bob", "Bob")

    assert {:error, :not_host} = Server.start_game(pid, "bob")
    assert Server.get_state(pid).phase == :lobby
  end

  test "start_game randomly assigns one thief and all other players as detectives" do
    game_id = "lobby-#{System.unique_integer()}"
    {:ok, pid} = Server.start_link(game_id: game_id, players: %{})

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

  test "start_game preserves the original lobby host" do
    game_id = "preserve-host-#{System.unique_integer()}"
    {:ok, pid} = Server.start_link(game_id: game_id, players: %{})

    assert :ok = Server.add_player(pid, "alice", "Alice")
    assert :ok = Server.add_player(pid, "bob", "Bob")
    assert :ok = Server.add_player(pid, "cora", "Cora")

    assert {:ok, state} = Server.start_game(pid, "alice", shuffle: &Enum.reverse/1)
    assert state.host_player_id == "alice"
    assert state.thief_player_id == "cora"
  end

  test "existing players can reconnect after the game starts" do
    game_id = "rejoin-#{System.unique_integer()}"
    {:ok, pid} = Server.start_link(game_id: game_id, players: %{})

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
end
