defmodule MuseumCaperWeb.LobbyLiveTest do
  use MuseumCaperWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    # Clean up any rooms created during test
    on_exit(fn ->
      MuseumCaper.Lobby.Server.list_rooms()
      |> Enum.each(fn r -> MuseumCaper.Lobby.Server.close_room(r.name) end)
    end)

    :ok
  end

  test "renders lobby page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#create-room-form")
    assert has_element?(view, "#empty-rooms")
  end

  test "create room redirects on success", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert {:error, {:live_redirect, %{to: "/game/" <> _}}} =
             view
             |> form("#create-room-form", %{room: %{name: "Test Room", player_name: "Alice"}})
             |> render_submit()
  end

  test "renders newest rooms first", %{conn: conn} do
    {:ok, lobby_view, _html} = live(conn, "/")

    {:ok, _oldest_id} = MuseumCaper.Lobby.Server.create_room("Oldest Room", "Alice")
    {:ok, _middle_id} = MuseumCaper.Lobby.Server.create_room("Middle Room", "Bob")
    {:ok, _newest_id} = MuseumCaper.Lobby.Server.create_room("Newest Room", "Cora")

    room_names =
      lobby_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#room-list article h3")
      |> Enum.map(&LazyHTML.text/1)

    assert room_names == ["Newest Room", "Middle Room", "Oldest Room"]
  end

  test "requires room name to create", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#create-room-form", %{room: %{name: "", player_name: "Alice"}})
    |> render_submit()

    assert has_element?(view, "#lobby-error")
  end

  test "room card reflects players who joined the game room", %{conn: conn} do
    {:ok, lobby_view, _html} = live(conn, "/")
    {:ok, game_id} = MuseumCaper.Lobby.Server.create_room("Roster Room", "Alice")

    assert has_element?(lobby_view, "#room-#{game_id}", "1/4 players")

    {:ok, _alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, _bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")
    {:ok, _cora_view, _html} = live(conn, "/game/#{game_id}?player_name=Cora")

    assert has_element?(lobby_view, "#room-#{game_id}", "3/4 players")
  end

  test "does not offer join controls for games already in progress", %{conn: conn} do
    {:ok, lobby_view, _html} = live(conn, "/")
    {:ok, game_id} = MuseumCaper.Lobby.Server.create_room("Started Room", "Alice")
    server = {:via, Registry, {MuseumCaper.GameRegistry, game_id}}

    :ok = MuseumCaper.Game.Server.add_player(server, "player-alice", "Alice")
    :ok = MuseumCaper.Game.Server.add_player(server, "player-bob", "Bob")
    {:ok, _state} = MuseumCaper.Game.Server.start_game(server, "player-alice")

    assert has_element?(lobby_view, "#room-#{game_id}", "setup")
    assert has_element?(lobby_view, "#room-#{game_id} [data-room-status='locked']", "In progress")
    refute has_element?(lobby_view, "#show-join-#{game_id}")
  end
end
