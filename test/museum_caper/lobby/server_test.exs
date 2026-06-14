defmodule MuseumCaper.Lobby.ServerTest do
  use ExUnit.Case, async: false

  alias MuseumCaper.Game.State
  alias MuseumCaper.Lobby.Server, as: LobbyServer

  setup do
    on_exit(fn ->
      LobbyServer.list_rooms() |> Enum.each(fn r -> LobbyServer.close_room(r.name) end)
    end)

    :ok
  end

  test "list_rooms returns empty when no rooms created" do
    assert LobbyServer.list_rooms() == []
  end

  test "create_room adds room to list" do
    {:ok, _game_id} = LobbyServer.create_room("Test Room", "Alice")
    rooms = LobbyServer.list_rooms()
    assert Enum.any?(rooms, &(&1.name == "Test Room"))
  end

  test "list_rooms returns newest rooms first" do
    {:ok, _oldest_id} = LobbyServer.create_room("Oldest Room", "Alice")
    {:ok, _middle_id} = LobbyServer.create_room("Middle Room", "Bob")
    {:ok, _newest_id} = LobbyServer.create_room("Newest Room", "Cora")

    room_names = Enum.map(LobbyServer.list_rooms(), & &1.name)

    assert room_names == ["Newest Room", "Middle Room", "Oldest Room"]
  end

  test "create_room returns error for duplicate name" do
    {:ok, _} = LobbyServer.create_room("Dupe", "Alice")
    assert {:error, :name_taken} = LobbyServer.create_room("Dupe", "Bob")
  end

  test "join_room increments player count" do
    {:ok, game_id} = LobbyServer.create_room("Join Test", "Alice")
    :ok = LobbyServer.join_room("Join Test", game_id, "Bob")
    room = Enum.find(LobbyServer.list_rooms(), &(&1.name == "Join Test"))
    assert room.player_count == 2
  end

  test "join_room rejects games already in progress" do
    {:ok, game_id} = LobbyServer.create_room("Started Join", "Alice")

    :ok =
      LobbyServer.sync_game(game_id, %State{
        phase: :setup,
        players: %{
          "alice" => %{name: "Alice", role: :detective, color: :red},
          "bob" => %{name: "Bob", role: :thief, color: :grey}
        }
      })

    assert {:error, :game_started} = LobbyServer.join_room("Started Join", game_id, "Cora")

    room = Enum.find(LobbyServer.list_rooms(), &(&1.name == "Started Join"))
    assert room.player_count == 2
  end

  test "game joins keep lobby player count synced with actual roster" do
    {:ok, game_id} = LobbyServer.create_room("Sync Test", "Alice")
    server = {:via, Registry, {MuseumCaper.GameRegistry, game_id}}

    :ok = MuseumCaper.Game.Server.add_player(server, "alice", "Alice")
    :ok = MuseumCaper.Game.Server.add_player(server, "bob", "Bob")
    :ok = MuseumCaper.Game.Server.add_player(server, "cora", "Cora")

    room = Enum.find(LobbyServer.list_rooms(), &(&1.name == "Sync Test"))
    assert room.player_count == 3
  end

  test "close_room removes it from list" do
    {:ok, _} = LobbyServer.create_room("Close Me", "Alice")
    LobbyServer.close_room("Close Me")
    rooms = LobbyServer.list_rooms()
    refute Enum.any?(rooms, &(&1.name == "Close Me"))
  end

  test "close_game removes a room by game id" do
    {:ok, game_id} = LobbyServer.create_room("Close Game", "Alice")

    assert :ok = LobbyServer.close_game(game_id)

    rooms = LobbyServer.list_rooms()
    refute Enum.any?(rooms, &(&1.game_id == game_id))
  end

  test "sync_game removes rooms that have reached game over" do
    {:ok, game_id} = LobbyServer.create_room("Finished Game", "Alice")

    :ok =
      LobbyServer.sync_game(game_id, %State{
        phase: :game_over,
        players: %{
          "alice" => %{name: "Alice", role: :detective, color: :red},
          "bob" => %{name: "Bob", role: :thief, color: :grey}
        }
      })

    rooms = LobbyServer.list_rooms()
    refute Enum.any?(rooms, &(&1.game_id == game_id))
  end
end
