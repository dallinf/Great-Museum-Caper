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
    refute has_element?(view, "#back-to-lobby-link")
    refute has_element?(view, "[data-phx-theme]")
  end

  test "renders production lobby copy", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#app-header", "The Great Museum Caper")

    assert has_element?(
             view,
             "#lobby-intro-copy",
             "Create a room and share it with players. Start the game when everyone has joined."
           )

    refute has_element?(view, "#app-header", "local prototype")
    refute has_element?(view, "#lobby-intro-copy", "local room")
    refute has_element?(view, "#lobby-intro-copy", "private window")
    refute has_element?(view, "#lobby-intro-copy", "second player")
  end

  test "lobby text inputs use the fixed app theme", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#room_name.bg-stone-50.text-stone-950")
    assert has_element?(view, "#room_name.placeholder\\:text-stone-500")
    assert has_element?(view, "#room_player_name.bg-stone-50.text-stone-950")
    assert has_element?(view, "#room_player_name.placeholder\\:text-stone-500")
  end

  test "create room form offers pawn color swatches", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    for color <- ~w(purple green blue white red yellow) do
      assert has_element?(
               view,
               "#create-room-form input[name='room[player_color]'][value='#{color}']"
             )

      assert has_element?(view, "#create-player-color-#{color}[data-pawn-color='#{color}']")
    end
  end

  test "create room redirects on success", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert {:error, {:live_redirect, %{to: "/game/" <> _ = to}}} =
             view
             |> form("#create-room-form", %{
               room: %{name: "Test Room", player_name: "Alice", player_color: "purple"}
             })
             |> render_submit()

    params = redirected_query_params(to)
    assert params["player_name"] == "Alice"
    assert params["player_color"] == "purple"
    assert params["player_id"] =~ ~r/^player-alice-[A-Za-z0-9_-]+$/
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

  test "join room form sends the chosen pawn color to the game", %{conn: conn} do
    {:ok, lobby_view, _html} = live(conn, "/")
    {:ok, game_id} = MuseumCaper.Lobby.Server.create_room("Color Room", "Alice")

    render_click(element(lobby_view, "#show-join-#{game_id}"))

    for color <- ~w(purple green blue white red yellow) do
      assert has_element?(
               lobby_view,
               "#join-room-form-#{game_id} input[name='join[player_color]'][value='#{color}']"
             )
    end

    assert {:error, {:live_redirect, %{to: to}}} =
             lobby_view
             |> form("#join-room-form-#{game_id}", %{
               join: %{game_id: game_id, player_name: "Bob", player_color: "green"}
             })
             |> render_submit()

    assert to =~ "player_name=Bob"
    assert to =~ "player_color=green"

    params = redirected_query_params(to)
    assert params["player_id"] =~ ~r/^player-bob-[A-Za-z0-9_-]+$/
  end

  test "join room form keeps typed values when another player joins", %{conn: conn} do
    {:ok, alice_lobby_view, _html} = live(conn, "/")
    {:ok, bob_lobby_view, _html} = live(conn, "/")
    {:ok, game_id} = MuseumCaper.Lobby.Server.create_room("Race Room", "Alice")

    render_click(element(alice_lobby_view, "#show-join-#{game_id}"))
    render_click(element(bob_lobby_view, "#show-join-#{game_id}"))

    bob_lobby_view
    |> form("#join-room-form-#{game_id}", %{
      join: %{game_id: game_id, player_name: "Bob", player_color: "green"}
    })
    |> render_change()

    assert has_element?(
             bob_lobby_view,
             "#join-room-form-#{game_id} input[name='join[player_name]'][value='Bob']"
           )

    assert {:error, {:live_redirect, %{to: to}}} =
             alice_lobby_view
             |> form("#join-room-form-#{game_id}", %{
               join: %{game_id: game_id, player_name: "Cora", player_color: "purple"}
             })
             |> render_submit()

    {:ok, _cora_view, _html} = live(conn, to)

    assert has_element?(
             bob_lobby_view,
             "#join-room-form-#{game_id} input[name='join[player_name]'][value='Bob']"
           )

    assert has_element?(bob_lobby_view, "#join-player-color-#{game_id}-green input[checked]")
  end

  test "join room form disables pawn colors already chosen", %{conn: conn} do
    {:ok, lobby_view, _html} = live(conn, "/")
    {:ok, game_id} = MuseumCaper.Lobby.Server.create_room("Taken Color Room", "Alice")

    {:ok, _alice_view, _html} =
      live(conn, "/game/#{game_id}?player_name=Alice&player_color=purple")

    render_click(element(lobby_view, "#show-join-#{game_id}"))

    assert has_element?(
             lobby_view,
             "#join-player-color-#{game_id}-purple[data-pawn-color-status='taken'] input[disabled]"
           )

    refute has_element?(lobby_view, "#join-player-color-#{game_id}-purple input[checked]")

    assert has_element?(
             lobby_view,
             "#join-player-color-#{game_id}-green[data-pawn-color-status='available'] input[checked]"
           )
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

    assert has_element?(
             lobby_view,
             "#rejoin-#{game_id}.hidden[data-rejoin-link][data-game-id='#{game_id}'][data-room-player-ids~='player-alice']",
             "Rejoin"
           )

    refute has_element?(lobby_view, "#show-join-#{game_id}")
  end

  defp redirected_query_params(path) do
    path
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
