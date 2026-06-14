defmodule MuseumCaperWeb.GameLiveTest do
  use MuseumCaperWeb.ConnCase
  import Phoenix.LiveViewTest

  alias MuseumCaper.Lobby.Server, as: LobbyServer
  alias MuseumCaper.Game.Board
  alias MuseumCaper.Game.Server, as: GameServer

  @setup_players %{
    "player-theo" => %{name: "Theo", role: :thief, color: :grey},
    "player-alice" => %{name: "Alice", role: :detective, color: :red},
    "player-bob" => %{name: "Bob", role: :detective, color: :blue}
  }

  @valid_painting_cells [
    {1, 4},
    {3, 1},
    {3, 10},
    {7, 1},
    {6, 11},
    {4, 5},
    {10, 4},
    {1, 6},
    {6, 12}
  ]

  @camera_cells [{3, 4}, {3, 5}, {3, 6}, {3, 7}]

  setup do
    on_exit(fn ->
      LobbyServer.list_rooms()
      |> Enum.each(fn r -> LobbyServer.close_room(r.name) end)
    end)

    game_id = "test-game-#{System.unique_integer([:positive])}"
    {:ok, game_id: game_id}
  end

  test "redirects to lobby for unknown game", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, "/game/unknown-game-id-#{System.unique_integer()}")
  end

  test "renders join screen for new player", %{conn: conn, game_id: game_id} do
    # Start a game server directly for this test
    {:ok, _pid} =
      MuseumCaper.Game.Server.start_link(
        game_id: game_id,
        players: %{
          "t" => %{name: "Thief", role: :thief, color: :grey},
          "d1" => %{name: "Det1", role: :detective, color: :red}
        }
      )

    {:ok, _view, html} = live(conn, "/game/#{game_id}")
    assert html =~ "Museum Caper" or html =~ "Join" or html =~ "Game"
  end

  test "joined player sees waiting room controls", %{conn: conn, game_id: game_id} do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

    {:ok, view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    assert has_element?(view, "#waiting-room")
    assert has_element?(view, "#player-list")
    assert has_element?(view, "#start-game-button")
  end

  test "non-host joined player does not see start control", %{conn: conn, game_id: game_id} do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

    {:ok, _alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")

    assert has_element?(bob_view, "#waiting-room")
    refute has_element?(bob_view, "#start-game-button")
  end

  test "new player cannot join after game has started", %{conn: conn, game_id: game_id} do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: @setup_players)

    {:ok, view, _html} = live(conn, "/game/#{game_id}?player_name=Cora")

    assert has_element?(view, "#game-notification", "This game has already started.")
    assert has_element?(view, "#join-closed-panel")
    refute has_element?(view, "#join-panel")
    refute has_element?(view, "#player-list", "Cora")
  end

  test "start game reports when fewer than two players joined", %{conn: conn, game_id: game_id} do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

    {:ok, view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    render_click(element(view, "#start-game-button"))

    assert has_element?(view, "#game-notification")
  end

  test "two joined players can start into setup", %{conn: conn, game_id: game_id} do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, _bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")

    render_click(element(alice_view, "#start-game-button"))

    assert has_element?(alice_view, "#setup-panel")
    assert has_element?(alice_view, "#museum-board")
  end

  test "game screen allows mobile scroll below the header", %{conn: conn, game_id: game_id} do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, _bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")
    render_click(element(alice_view, "#start-game-button"))

    assert has_element?(alice_view, "#app-header.h-16")
    assert has_element?(alice_view, "#app-header > div.h-full")
    assert has_element?(alice_view, "#app-main[data-layout='header-offset']")
    refute has_element?(alice_view, "#app-main.min-h-screen")
    assert has_element?(alice_view, "#game-shell.overflow-y-auto[class*='lg:overflow-hidden']")
    assert has_element?(alice_view, "#game-layout.overflow-visible[class*='lg:overflow-hidden']")
    assert has_element?(alice_view, "#game-sidebar.overflow-y-auto")

    assert has_element?(
             alice_view,
             "#game-board-panel.overflow-visible[class*='lg:overflow-hidden']"
           )
  end

  test "game header links back to the lobby", %{conn: conn, game_id: game_id} do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

    {:ok, view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    assert has_element?(view, "#back-to-lobby-link[href='/']", "Back to lobby")
  end

  test "host back-to-lobby link removes the game from the lobby", %{conn: conn} do
    {:ok, game_id} = LobbyServer.create_room("Host Exit Room", "Alice")

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, _bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")

    render_click(element(alice_view, "#start-game-button"))
    assert Enum.any?(LobbyServer.list_rooms(), &(&1.game_id == game_id))

    assert {:error, {:live_redirect, %{to: "/"}}} =
             render_click(element(alice_view, "#back-to-lobby-link"))

    refute Enum.any?(LobbyServer.list_rooms(), &(&1.game_id == game_id))
  end

  test "non-host back-to-lobby link leaves the game in the lobby", %{conn: conn} do
    {:ok, game_id} = LobbyServer.create_room("Guest Exit Room", "Alice")

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")

    render_click(element(alice_view, "#start-game-button"))

    assert {:error, {:live_redirect, %{to: "/"}}} =
             render_click(element(bob_view, "#back-to-lobby-link"))

    assert Enum.any?(LobbyServer.list_rooms(), &(&1.game_id == game_id))
  end

  test "setup board shows window frames and external door spaces", %{conn: conn, game_id: game_id} do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, _bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")
    render_click(element(alice_view, "#start-game-button"))

    assert has_element?(
             alice_view,
             "#cell-1-5[data-board-feature='window'][data-window-edge='top']"
           )

    assert has_element?(
             alice_view,
             "#cell-4-1[data-board-feature='window'][data-window-edge='left']"
           )

    assert has_element?(
             alice_view,
             "#cell-8-12[data-board-feature='window'][data-window-edge='right']"
           )

    assert has_element?(alice_view, "#cell-1-5 [data-entry-label]", "W1")
    assert has_element?(alice_view, "#cell-4-1 [data-entry-label]", "W4")
    assert has_element?(alice_view, "#cell-8-12 [data-entry-label]", "W6")
    refute has_element?(alice_view, "#cell-1-5.ring-cyan-400")
    refute has_element?(alice_view, "#cell-2-6[data-board-feature='doorway']")
    refute has_element?(alice_view, "#cell-2-6 [data-board-feature='doorway']")

    assert has_element?(alice_view, "#cell-11-6[data-board-feature='exit'].bg-stone-700")
    assert has_element?(alice_view, "#cell-6-1[data-board-feature='exit'].bg-stone-700")
    assert has_element?(alice_view, "#cell-5-12[data-board-feature='exit'].bg-stone-700")
    assert has_element?(alice_view, "#cell-6-1[data-board-feature='exit'].border-r-0")
    assert has_element?(alice_view, "#cell-5-12[data-board-feature='exit'].border-l-0")
    assert has_element?(alice_view, "#cell-5-12 [data-entry-label]", "D1")
    assert has_element?(alice_view, "#cell-6-1 [data-entry-label]", "D2")
    assert has_element?(alice_view, "#cell-11-6 [data-entry-label]", "D3")
    assert has_element?(alice_view, "#cell-6-2[data-external-door-opening='left']")
    assert has_element?(alice_view, "#cell-5-11[data-external-door-opening='right']")
    assert has_element?(alice_view, "#cell-11-6 [data-board-feature='exit-inset']")
    assert has_element?(alice_view, "#cell-6-1 [data-board-feature='exit-inset']")
    assert has_element?(alice_view, "#cell-5-12 [data-board-feature='exit-inset']")
    refute has_element?(alice_view, "#cell-6-2[data-board-feature='exit']")
    refute has_element?(alice_view, "#cell-5-11[data-board-feature='exit']")

    refute has_element?(alice_view, "#map-cues")
  end

  test "setup board renders corrected internal door edges and room background colors", %{
    conn: conn,
    game_id: game_id
  } do
    {:ok, _pid} = MuseumCaper.Game.Server.start_link(game_id: game_id, players: %{})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, _bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")
    render_click(element(alice_view, "#start-game-button"))

    assert has_element?(
             alice_view,
             ~s|#cell-10-5[style*="border-top:1px solid rgba(28,25,23,0.28);"][style*="border-right:3px solid rgb(28,25,23);"]|
           )

    assert has_element?(
             alice_view,
             ~s|#cell-4-10[style*="border-left:1px solid rgba(28,25,23,0.28);"][style*="border-bottom:3px solid rgb(28,25,23);"]|
           )

    assert has_element?(alice_view, "#cell-3-4.bg-stone-300")
    assert has_element?(alice_view, "#cell-7-1.bg-yellow-200")
    assert has_element?(alice_view, "#cell-10-4.bg-stone-200")
    assert has_element?(alice_view, "#cell-10-8.bg-stone-200")
    assert has_element?(alice_view, "#cell-11-9.bg-stone-200")
    refute has_element?(alice_view, "#cell-10-4.bg-stone-300")
    refute has_element?(alice_view, "#cell-10-8.bg-stone-300")
    refute has_element?(alice_view, "#cell-11-9.bg-stone-300")
    refute has_element?(alice_view, "#cell-10-4.bg-orange-200")
    refute has_element?(alice_view, "#cell-10-8.bg-orange-200")
    refute has_element?(alice_view, "#cell-11-9.bg-amber-300")
    refute has_element?(alice_view, "#cell-10-4 > span.absolute.left-1.top-1", "o")
    refute has_element?(alice_view, "#cell-10-8 > span.absolute.left-1.top-1", "o")
    refute has_element?(alice_view, "#cell-11-9 > span.absolute.left-1.top-1", "P")

    assert has_element?(
             alice_view,
             "#cell-11-9 > span[data-power-symbol].text-black > span.hero-bolt-solid.size-5.text-black"
           )
  end

  test "detectives place locks on doors and windows before artwork setup", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    assert has_element?(alice_view, "#setup-step", "Place 5 locks")
    assert has_element?(alice_view, "#lock-count", "0/5")
    assert has_element?(alice_view, "#cell-6-1.cursor-pointer")
    assert has_element?(alice_view, "#cell-1-5.cursor-pointer")

    render_click(element(alice_view, "#cell-6-1"))

    state = GameServer.get_state(pid)
    assert state.locks[:exit_w1] == :locked
    assert has_element?(alice_view, "#lock-count", "1/5")
    assert has_element?(alice_view, "#cell-6-1", "Lock")

    render_click(element(alice_view, "#cell-6-1"))
    assert GameServer.get_state(pid).locks[:exit_w1] == :open
    assert has_element?(alice_view, "#lock-count", "0/5")
  end

  test "thief setup panel asks them to wait instead of showing detective instructions", %{
    conn: conn,
    game_id: game_id
  } do
    start_fixed_setup_game!(game_id)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(
             thief_view,
             "#setup-step",
             "Wait patiently for the detectives to set up."
           )

    refute has_element?(thief_view, "#setup-step", "Place 5 locks")
  end

  test "lock badges sit at the top above door insets", %{conn: conn, game_id: game_id} do
    start_fixed_setup_game!(game_id)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    for cell_id <- ["#cell-6-1", "#cell-11-6", "#cell-1-5"] do
      render_click(element(alice_view, cell_id))
    end

    assert has_element?(
             alice_view,
             ~s|#cell-6-1 > [data-board-mark='lock'].absolute.top-1.z-20|
           )

    assert has_element?(
             alice_view,
             ~s|#cell-11-6 > [data-board-mark='lock'].absolute.top-1.z-20|
           )

    assert has_element?(
             alice_view,
             ~s|#cell-1-5 > [data-board-mark='lock'].absolute.top-1.z-20|
           )
  end

  test "required lock placements advance setup to artwork", %{conn: conn, game_id: game_id} do
    pid = start_fixed_setup_game!(game_id)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    Board.entries()
    |> Enum.take(Board.lock_count())
    |> Enum.each(fn entry ->
      {row, col} = Board.exit_door_cell(entry)
      render_click(element(alice_view, "#cell-#{row}-#{col}"))
    end)

    state = GameServer.get_state(pid)
    assert state.setup_step == :paintings
    assert has_element?(alice_view, "#setup-step", "Place 9 artworks")
  end

  test "setup board click places artwork", %{conn: conn, game_id: game_id} do
    pid = start_fixed_setup_game!(game_id)
    advance_to_paintings(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    render_click(element(alice_view, "#cell-1-4"))

    state = GameServer.get_state(pid)
    assert state.paintings[{1, 4}] == :present
  end

  test "setup board click removes existing artwork", %{conn: conn, game_id: game_id} do
    pid = start_fixed_setup_game!(game_id)
    advance_to_paintings(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    render_click(element(alice_view, "#cell-1-4"))
    render_click(element(alice_view, "#cell-1-4"))

    state = GameServer.get_state(pid)
    refute Map.has_key?(state.paintings, {1, 4})
  end

  test "setup board click removes existing camera", %{conn: conn, game_id: game_id} do
    pid = start_fixed_setup_game!(game_id)
    advance_to_paintings(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    for cell_id <- [
          "#cell-1-4",
          "#cell-3-1",
          "#cell-3-10",
          "#cell-7-1",
          "#cell-6-11",
          "#cell-4-5",
          "#cell-10-4",
          "#cell-1-6",
          "#cell-6-12"
        ] do
      render_click(element(alice_view, cell_id))
    end

    render_click(element(alice_view, "#cell-3-4"))
    assert GameServer.get_state(pid).cameras[1].pos == {3, 4}

    render_click(element(alice_view, "#cell-3-4"))
    assert GameServer.get_state(pid).cameras[1] == nil
  end

  test "camera setup does not allow power or bottom external door cells", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_cameras(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    refute has_element?(alice_view, "#cell-11-9.cursor-pointer")
    refute has_element?(alice_view, "#cell-11-6.cursor-pointer")
    refute has_element?(alice_view, "#cell-11-7.cursor-pointer")

    render_click(element(alice_view, "#cell-11-9"))
    render_click(element(alice_view, "#cell-11-6"))
    render_click(element(alice_view, "#cell-11-7"))

    state = GameServer.get_state(pid)
    assert Enum.all?(state.cameras, fn {_id, camera} -> camera == nil end)
  end

  test "thief cannot place setup pieces", %{conn: conn, game_id: game_id} do
    lock_pid = start_fixed_setup_game!("#{game_id}-lock")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}-lock?player_name=Theo")

    render_click(element(thief_view, "#cell-6-1"))
    assert GameServer.get_state(lock_pid).locks[:exit_w1] == :open

    painting_pid = start_fixed_setup_game!("#{game_id}-painting")
    advance_to_paintings(painting_pid)
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}-painting?player_name=Theo")

    render_click(element(thief_view, "#cell-2-4"))
    refute Map.has_key?(GameServer.get_state(painting_pid).paintings, {2, 4})

    camera_pid = start_fixed_setup_game!("#{game_id}-camera")
    advance_to_cameras(camera_pid)
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}-camera?player_name=Theo")

    render_click(element(thief_view, "#cell-3-4"))
    assert GameServer.get_state(camera_pid).cameras[1] == nil

    pawn_pid = start_fixed_setup_game!("#{game_id}-pawn")
    advance_to_pawns(pawn_pid)
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}-pawn?player_name=Theo")

    render_click(element(thief_view, "#cell-1-4"))
    assert GameServer.get_state(pawn_pid).detective_positions["player-alice"] == nil
    assert GameServer.get_state(pawn_pid).detective_positions["player-bob"] == nil
  end

  test "each detective places only their own pawn and board uses names", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_pawns(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")

    render_click(element(alice_view, "#cell-2-4"))
    state = GameServer.get_state(pid)
    assert state.detective_positions["player-alice"] == {2, 4}
    assert state.detective_positions["player-bob"] == nil
    assert has_element?(alice_view, "#cell-2-4", "Alice")
    refute has_element?(alice_view, "#cell-2-4", "Dpl")

    render_click(element(alice_view, "#cell-2-5"))
    assert GameServer.get_state(pid).detective_positions["player-bob"] == nil

    render_click(element(bob_view, "#cell-7-2"))
    assert GameServer.get_state(pid).detective_positions["player-bob"] == {7, 2}
    assert has_element?(bob_view, "#cell-7-2", "Bob")
  end

  test "detective setup does not allow bottom external door cells", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_pawns(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    refute has_element?(alice_view, "#cell-11-6.cursor-pointer")
    refute has_element?(alice_view, "#cell-11-7.cursor-pointer")

    render_click(element(alice_view, "#cell-11-6"))
    render_click(element(alice_view, "#cell-11-7"))

    state = GameServer.get_state(pid)
    assert state.detective_positions["player-alice"] == nil
    assert state.phase == :setup
    assert state.setup_step == :pawns
  end

  test "thief enters the museum by clicking an entry cell", %{conn: conn, game_id: game_id} do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(thief_view, "#entry-panel")
    refute has_element?(thief_view, "#enter-exit_s1")
    assert has_element?(thief_view, "#cell-6-1.cursor-pointer")
    assert has_element?(thief_view, "#cell-5-12.cursor-pointer")
    assert has_element?(thief_view, "#cell-1-5.cursor-pointer")
    refute has_element?(thief_view, "#cell-6-2.cursor-pointer")
    refute has_element?(thief_view, "#cell-5-11.cursor-pointer")

    render_click(element(thief_view, "#cell-6-1"))

    state = GameServer.get_state(pid)
    assert state.phase == :playing
    assert state.thief_position == {6, 2}
    assert state.current_turn == "player-theo"
    assert state.turn_order == ["player-theo", "player-alice", "player-theo", "player-bob"]
    assert state.turn_actions_remaining == [:move]
    assert has_element?(thief_view, "#cell-6-3.cursor-pointer")
  end

  test "thief enters the museum by clicking a window", %{conn: conn, game_id: game_id} do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(thief_view, "#cell-1-5.cursor-pointer")
    render_click(element(thief_view, "#cell-1-5"))

    state = GameServer.get_state(pid)
    assert state.phase == :playing
    assert state.thief_position == {1, 5}
    assert state.current_turn == "player-theo"
  end

  test "thief cannot end turn before moving", %{conn: conn, game_id: game_id} do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    render_click(element(thief_view, "#cell-6-1"))
    render_click(element(thief_view, "#end-turn-button"))

    state = GameServer.get_state(pid)
    assert state.current_turn == "player-theo"
    assert state.turn_actions_remaining == [:move]
    assert has_element?(thief_view, "#game-notification", "Move before ending your turn.")
  end

  test "player list shows each player once when thief repeats in turn order", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    players =
      alice_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#player-list > li")

    assert Enum.count(players) == 3

    player_names =
      players
      |> LazyHTML.query("span:first-child")
      |> Enum.map(&LazyHTML.text/1)

    assert player_names == ["Theo", "Alice", "Bob"]
  end

  test "detectives see lock status during play but thief does not", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)

    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | locks: Map.put(server_state.game_state.locks, :exit_w1, :locked)
      }

      %{server_state | game_state: game_state}
    end)

    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_s1)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(alice_view, "#cell-6-1 > [data-board-mark='lock']", "Lock")
    refute has_element?(thief_view, "#cell-6-1 > [data-board-mark='lock']", "Lock")
  end

  test "camera board labels only show disabled status to the thief", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    disable_camera!(pid, 2)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(
             alice_view,
             "#cell-3-4 [data-board-mark='camera'][data-mark-status='active']",
             "C1"
           )

    assert has_element?(
             thief_view,
             "#cell-3-4 [data-board-mark='camera'][data-mark-status='active']",
             "C1"
           )

    assert has_element?(
             alice_view,
             "#cell-3-5 [data-board-mark='camera'][data-mark-status='active']",
             "C2"
           )

    refute has_element?(
             alice_view,
             "#cell-3-5 [data-board-mark='camera'][data-mark-status='disabled']",
             "C2"
           )

    assert has_element?(
             thief_view,
             "#cell-3-5 [data-board-mark='camera'][data-mark-status='disabled']",
             "C2"
           )

    refute has_element?(alice_view, "#cell-3-4", "C1:a")
    refute has_element?(thief_view, "#cell-3-4", "C1:a")
    refute has_element?(alice_view, "#cell-3-5", "C2:d")
    refute has_element?(thief_view, "#cell-3-5", "C2:d")
  end

  test "detectives see disabled cameras after checking them", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    disable_camera!(pid, 2)
    set_detective_turn!(pid, {4, :eye})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    assert has_element?(
             alice_view,
             "#cell-3-5 [data-board-mark='camera'][data-mark-status='active']",
             "C2"
           )

    render_click(element(alice_view, "#look-camera-2"))

    state = GameServer.get_state(pid)
    assert state.cameras[2].status == :disabled
    assert state.cameras[2].revealed

    assert has_element?(
             alice_view,
             "#cell-3-5 [data-board-mark='camera'][data-mark-status='disabled']",
             "C2"
           )

    assert has_element?(alice_view, "#detective-result-panel", "That camera was disabled.")
  end

  test "detectives see power is off only after using a powered tool", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    set_power_room_thief_turn!(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    refute has_element?(alice_view, "#power-status")

    render_click(element(thief_view, "#cell-11-9"))

    assert GameServer.get_state(pid).power_active == false
    refute GameServer.get_state(pid).power_revealed
    refute has_element?(alice_view, "#power-status")

    set_detective_turn!(pid, {4, :camera_scan}, 0, power_active: false)
    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    render_click(element(alice_view, "#camera-scan-button"))

    assert GameServer.get_state(pid).power_revealed
    assert has_element?(alice_view, "#power-status", "Power off")
  end

  test "all players see a motion detector result", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_motion_turn!(pid, 0)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    render_click(element(alice_view, "#motion-detector-button"))

    assert has_element?(alice_view, "#detective-result-panel", "Motion detector reads gray.")
    assert has_element?(bob_view, "#detective-result-panel", "Motion detector reads gray.")
    assert has_element?(thief_view, "#detective-result-panel", "Motion detector reads gray.")
  end

  test "all players see camera scan results", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_detective_turn!(pid, {4, :camera_scan})
    set_thief_position!(pid, {4, 4})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    render_click(element(alice_view, "#camera-scan-button"))

    state = GameServer.get_state(pid)
    refute state.chase_mode

    assert has_element?(
             alice_view,
             "#detective-result-panel",
             "Camera scan found 0 disabled cameras and C1 spotted the thief."
           )

    assert has_element?(
             bob_view,
             "#detective-result-panel",
             "Camera scan found 0 disabled cameras and C1 spotted the thief."
           )

    assert has_element?(
             thief_view,
             "#detective-result-panel",
             "Camera scan found 0 disabled cameras and C1 spotted the thief."
           )

    refute has_element?(alice_view, "#cell-4-4", "T")
    assert has_element?(thief_view, "#cell-4-4", "T")
  end

  test "all players see detective pawn look results", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_detective_turn!(pid, {4, :eye})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    render_click(element(alice_view, "#look-pawn-button"))

    assert has_element?(alice_view, "#detective-result-panel", "No thief in that line of sight.")
    assert has_element?(bob_view, "#detective-result-panel", "No thief in that line of sight.")
    assert has_element?(thief_view, "#detective-result-panel", "No thief in that line of sight.")
  end

  test "detective cannot end turn after looking before moving", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_detective_turn!(pid, {4, :eye})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    render_click(element(alice_view, "#look-pawn-button"))
    render_click(element(alice_view, "#end-turn-button"))

    state = GameServer.get_state(pid)
    assert state.current_turn == "player-alice"
    assert state.turn_actions_remaining == [:move]
    assert has_element?(alice_view, "#game-notification", "Move before ending your turn.")
  end

  test "all players see camera look results", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_detective_turn!(pid, {4, :eye})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    render_click(element(alice_view, "#look-camera-1"))

    assert has_element?(alice_view, "#detective-result-panel", "No thief in that camera line.")
    assert has_element?(bob_view, "#detective-result-panel", "No thief in that camera line.")
    assert has_element?(thief_view, "#detective-result-panel", "No thief in that camera line.")
  end

  test "camera look does not reveal the thief on the board", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_detective_turn!(pid, {4, :eye})
    set_thief_position!(pid, {4, 4})

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    render_click(element(alice_view, "#look-camera-1"))

    state = GameServer.get_state(pid)
    refute state.chase_mode
    assert has_element?(alice_view, "#detective-result-panel", "C1 spotted the thief.")
    refute has_element?(alice_view, "#cell-4-4", "T")
    assert has_element?(thief_view, "#cell-4-4", "T")
  end

  test "visible thief turns only show the numbered die", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    set_chase_detective_turn!(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    assert has_element?(alice_view, "#dice-readout", "Die: 4")
    refute has_element?(alice_view, "#dice-readout", "eye")
    refute has_element?(alice_view, "#look-pawn-button")
    refute has_element?(alice_view, "#camera-scan-button")
    refute has_element?(alice_view, "#motion-detector-button")
  end

  test "detective can move through another detective but cannot land there", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)

    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | current_turn: "player-alice",
          dice: {2, :eye},
          turn_actions_remaining: [:move, :look],
          thief_position: {1, 4},
          detective_positions: %{"player-alice" => {3, 6}, "player-bob" => {3, 7}}
      }

      %{server_state | game_state: game_state}
    end)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    refute has_element?(alice_view, "#cell-3-7.cursor-pointer")
    assert has_element?(alice_view, "#cell-3-8.cursor-pointer")

    render_click(element(alice_view, "#cell-3-8"))

    assert GameServer.get_state(pid).detective_positions["player-alice"] == {3, 8}
  end

  test "motion dice lets the thief decide before the detective reads", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_motion_turn!(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(alice_view, "#motion-decision-waiting")
    refute has_element?(alice_view, "#motion-detector-button")
    refute has_element?(alice_view, "#snip-motion-button")

    assert has_element?(thief_view, "#allow-motion-button")
    assert has_element?(thief_view, "#snip-motion-button")

    render_click(element(thief_view, "#allow-motion-button"))

    assert has_element?(alice_view, "#motion-detector-button")
    refute has_element?(alice_view, "#snip-motion-button")

    render_click(element(alice_view, "#motion-detector-button"))
    assert has_element?(alice_view, "#game-notification", "Motion detector reads")
  end

  test "motion cut controls disappear after two cuts are spent", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_motion_turn!(pid, 0)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    refute has_element?(thief_view, "#motion-decision-panel")
    refute has_element?(thief_view, "#snip-motion-button")
    refute has_element?(alice_view, "#motion-decision-waiting")
    assert has_element?(alice_view, "#motion-detector-button")
  end

  test "detectives cannot enter the thief by clicking an entry cell", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    refute has_element?(alice_view, "#cell-6-1.cursor-pointer")
    render_click(element(alice_view, "#cell-6-1"))

    state = GameServer.get_state(pid)
    assert state.phase == :thief_entry
    assert state.thief_position == nil
  end

  test "thief chooses whether to check a side exit lock before escaping", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")
    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, bob_view, _html} = live(conn, "/game/#{game_id}?player_name=Bob")

    refute has_element?(thief_view, "#escape-exit_w1")
    assert has_element?(thief_view, "#cell-6-1.cursor-pointer")
    render_click(element(thief_view, "#cell-6-1"))

    state = GameServer.get_state(pid)
    assert state.phase == :playing
    refute state.chase_mode
    assert has_element?(thief_view, "#escape-choice-panel")
    assert has_element?(thief_view, "#confirm-escape-button", "Check lock")
    assert has_element?(thief_view, "#cancel-escape-button")

    render_click(element(thief_view, "#confirm-escape-button"))

    state = GameServer.get_state(pid)
    assert state.phase == :playing
    refute state.chase_mode
    assert has_element?(thief_view, "#game-notification", "D2 lock is locked.")
    refute has_element?(thief_view, "#game-notification", "Chase mode is on.")

    assert has_element?(
             alice_view,
             "#detective-result-panel",
             "The thief checked the D2 lock."
           )

    assert has_element?(alice_view, "#detective-result-panel", "It was locked.")

    assert has_element?(
             bob_view,
             "#detective-result-panel",
             "The thief checked the D2 lock."
           )

    refute has_element?(alice_view, "#detective-result-panel", "west door")
  end

  test "clicking a reachable external door moves there and asks about the lock", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_thief_position!(pid, {6, 4})

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(thief_view, "#cell-6-1.cursor-pointer")
    render_click(element(thief_view, "#cell-6-1"))

    state = GameServer.get_state(pid)
    assert state.thief_position == {6, 2}
    assert state.turn_actions_remaining == []
    assert state.phase == :playing
    assert has_element?(thief_view, "#escape-choice-panel")
    assert has_element?(thief_view, "#escape-choice-panel", "Check this door lock?")
    assert has_element?(thief_view, "#confirm-escape-button", "Check lock")
    assert has_element?(thief_view, "#cancel-escape-button")
  end

  test "clicking a bottom door from the inside square asks about the lock", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_thief_position!(pid, {10, 6})

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(thief_view, "#cell-11-6.cursor-pointer")
    render_click(element(thief_view, "#cell-11-6"))

    state = GameServer.get_state(pid)
    assert state.thief_position == {10, 6}
    assert state.phase == :playing
    assert has_element?(thief_view, "#escape-choice-panel")
    assert has_element?(thief_view, "#escape-choice-panel", "Check this door lock?")
  end

  test "detectives see which window lock the thief checked when it is locked", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)

    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | locks: Map.put(server_state.game_state.locks, :window_1_5, :locked)
      }

      %{server_state | game_state: game_state}
    end)

    assert {:ok, _state} = GameServer.enter_museum(pid, :window_1_5)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")
    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    render_click(element(thief_view, "#cell-1-5"))
    render_click(element(thief_view, "#confirm-escape-button"))

    state = GameServer.get_state(pid)
    assert state.phase == :playing
    refute state.chase_mode
    assert has_element?(thief_view, "#game-notification", "W1 lock is locked.")
    assert has_element?(alice_view, "#detective-result-panel", "The thief checked the W1 lock.")
    assert has_element?(alice_view, "#detective-result-panel", "It was locked.")
    refute has_element?(alice_view, "#detective-result-panel", "window at row 1, column 5")
  end

  test "thief chooses whether to check a window lock before escaping", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)

    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | locks: Map.put(server_state.game_state.locks, :window_1_5, :open)
      }

      %{server_state | game_state: game_state}
    end)

    assert {:ok, _state} = GameServer.enter_museum(pid, :window_1_5)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(thief_view, "#cell-1-5.cursor-pointer")
    render_click(element(thief_view, "#cell-1-5"))

    state = GameServer.get_state(pid)
    assert state.phase == :playing
    assert state.winner == nil
    assert has_element?(thief_view, "#escape-choice-panel")
    assert has_element?(thief_view, "#confirm-escape-button", "Check lock")

    render_click(element(thief_view, "#confirm-escape-button"))

    state = GameServer.get_state(pid)
    assert state.phase == :game_over
    assert state.winner == :thief
  end

  test "clicking a reachable window space immediately asks the thief about the lock", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_thief_position!(pid, {1, 4})

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(thief_view, "#cell-1-5.cursor-pointer")
    render_click(element(thief_view, "#cell-1-5"))

    state = GameServer.get_state(pid)
    assert state.thief_position == {1, 5}
    assert state.phase == :playing
    assert state.winner == nil
    assert has_element?(thief_view, "#escape-choice-panel")
    assert has_element?(thief_view, "#escape-choice-panel", "Check this window lock?")
    assert has_element?(thief_view, "#confirm-escape-button", "Check lock")
    assert has_element?(thief_view, "#cancel-escape-button")
  end

  test "thief can decline checking a window lock", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :window_1_5)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    render_click(element(thief_view, "#cell-1-5"))
    assert has_element?(thief_view, "#escape-choice-panel")

    render_click(element(thief_view, "#cancel-escape-button"))

    assert GameServer.get_state(pid).phase == :playing
    refute has_element?(thief_view, "#escape-choice-panel")
  end

  test "thief cannot move again after spending their move action", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_s1)

    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert GameServer.get_state(pid).thief_position == {10, 6}
    assert has_element?(thief_view, "#cell-10-7.cursor-pointer")
    render_click(element(thief_view, "#cell-10-7"))

    assert GameServer.get_state(pid).thief_position == {10, 7}
    refute has_element?(thief_view, "#cell-10-6.cursor-pointer")

    render_click(element(thief_view, "#cell-10-6"))

    assert GameServer.get_state(pid).thief_position == {10, 7}
  end

  test "detectives do not see stolen painting mark until the thief next turn", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    advance_to_thief_entry(pid)
    assert {:ok, _state} = GameServer.enter_museum(pid, :exit_w1)
    set_pending_steal_turn!(pid)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")
    {:ok, thief_view, _html} = live(conn, "/game/#{game_id}?player_name=Theo")

    assert has_element?(
             alice_view,
             "#cell-3-7 [data-board-mark='painting'][data-mark-status='present']",
             "A4"
           )

    assert has_element?(
             thief_view,
             "#cell-3-7 [data-board-mark='painting'][data-mark-status='present']",
             "A4"
           )

    render_click(element(thief_view, "#cell-3-7"))

    state = GameServer.get_state(pid)
    assert state.pending_steal == {3, 7}
    assert state.paintings[{3, 7}] == :targeted
    refute has_element?(alice_view, "#game-log", "Artwork A4 stolen.")

    assert has_element?(
             alice_view,
             "#cell-3-7 [data-board-mark='painting'][data-mark-status='present']",
             "A4"
           )

    refute has_element?(
             alice_view,
             "#cell-3-7 [data-board-mark='painting'][data-mark-status='targeted']",
             "A4*"
           )

    assert has_element?(
             thief_view,
             "#cell-3-7 [data-board-mark='painting'][data-mark-status='targeted']",
             "A4*"
           )

    render_click(element(thief_view, "#end-turn-button"))

    assert GameServer.get_state(pid).pending_steal == {3, 7}
    refute has_element?(alice_view, "#game-log", "Artwork A4 stolen.")

    assert has_element?(
             alice_view,
             "#cell-3-7 [data-board-mark='painting'][data-mark-status='present']",
             "A4"
           )

    refute has_element?(
             alice_view,
             "#cell-3-7 [data-board-mark='painting'][data-mark-status='targeted']",
             "A4*"
           )

    render_click(element(alice_view, "#cell-2-5"))
    assert GameServer.get_state(pid).detective_positions["player-alice"] == {2, 5}

    render_click(element(alice_view, "#end-turn-button"))

    state = GameServer.get_state(pid)
    assert state.pending_steal == nil
    assert state.paintings[{3, 7}] == :removed

    assert has_element?(
             alice_view,
             "#cell-3-7 [data-board-mark='painting'][data-mark-status='removed']",
             "A4"
           )

    assert has_element?(alice_view, "#game-log", "Artwork A4 stolen.")
  end

  test "detective cannot click hidden thief on targeted painting", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    set_detective_targeted_art_capture!(pid, false)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    refute has_element?(alice_view, "#cell-3-8.cursor-pointer")

    render_click(element(alice_view, "#cell-3-8"))

    state = GameServer.get_state(pid)
    assert state.phase == :playing
    assert state.detective_positions["player-alice"] == {3, 9}
  end

  test "spotting thief on targeted painting removes artwork immediately", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    set_detective_targeted_art_capture!(pid, false)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    assert has_element?(
             alice_view,
             "#cell-3-8 [data-board-mark='painting'][data-mark-status='present']",
             "A7"
           )

    render_click(element(alice_view, "#look-pawn-button"))

    state = GameServer.get_state(pid)
    assert state.chase_mode
    assert state.pending_steal == nil
    assert state.paintings[{3, 8}] == :removed
    assert state.stolen_count == 1

    assert has_element?(
             alice_view,
             "#cell-3-8 [data-board-mark='painting'][data-mark-status='removed']",
             "A7"
           )

    assert has_element?(alice_view, "#cell-3-8", "T")
    assert has_element?(alice_view, "#game-log", "Artwork A7 stolen.")
  end

  test "detective can click known thief on targeted painting to capture", %{
    conn: conn,
    game_id: game_id
  } do
    pid = start_fixed_setup_game!(game_id)
    set_detective_targeted_art_capture!(pid, true)

    {:ok, alice_view, _html} = live(conn, "/game/#{game_id}?player_name=Alice")

    assert has_element?(alice_view, "#cell-3-8.cursor-pointer")

    render_click(element(alice_view, "#cell-3-8"))

    state = GameServer.get_state(pid)
    assert state.phase == :game_over
    assert state.winner == :detectives
    assert state.game_over_reason == :caught
  end

  defp start_fixed_setup_game!(game_id) do
    start_supervised!(%{
      id: {:game_server, game_id},
      start: {GameServer, :start_link, [[game_id: game_id, players: @setup_players]]}
    })
  end

  defp advance_to_paintings(pid) do
    Board.entries()
    |> Enum.take(Board.lock_count())
    |> Enum.each(fn %{id: entry_id} ->
      assert {:ok, _state} = GameServer.toggle_lock(pid, entry_id)
    end)
  end

  defp advance_to_cameras(pid) do
    advance_to_paintings(pid)

    Enum.each(@valid_painting_cells, fn pos ->
      assert {:ok, _state} = GameServer.place_painting(pid, pos)
    end)
  end

  defp advance_to_pawns(pid) do
    advance_to_cameras(pid)

    @camera_cells
    |> Enum.with_index(1)
    |> Enum.each(fn {pos, camera_id} ->
      assert {:ok, _state} = GameServer.place_camera(pid, camera_id, pos)
    end)
  end

  defp advance_to_thief_entry(pid) do
    advance_to_pawns(pid)

    assert {:ok, _state} = GameServer.place_detective_pawn(pid, "player-alice", {2, 4})
    assert {:ok, _state} = GameServer.place_detective_pawn(pid, "player-bob", {7, 2})
  end

  defp set_motion_turn!(pid, motion_snips_remaining \\ 2) do
    set_detective_turn!(pid, {4, :motion}, motion_snips_remaining)
  end

  defp set_detective_turn!(pid, dice, motion_snips_remaining \\ 2, opts \\ []) do
    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | current_turn: "player-alice",
          dice: dice,
          turn_actions_remaining: [:move, :look],
          power_active: Keyword.get(opts, :power_active, true),
          power_revealed: Keyword.get(opts, :power_revealed, false),
          motion_snips_remaining: motion_snips_remaining
      }

      %{server_state | game_state: game_state}
    end)
  end

  defp set_thief_position!(pid, pos) do
    :sys.replace_state(pid, fn server_state ->
      game_state = %{server_state.game_state | thief_position: pos}
      %{server_state | game_state: game_state}
    end)
  end

  defp set_chase_detective_turn!(pid) do
    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | phase: :playing,
          chase_mode: true,
          current_turn: "player-alice",
          thief_position: {4, 4},
          dice: {4, nil},
          turn_actions_remaining: [:move]
      }

      %{server_state | game_state: game_state}
    end)
  end

  defp disable_camera!(pid, camera_id) do
    :sys.replace_state(pid, fn server_state ->
      camera = server_state.game_state.cameras[camera_id]

      game_state = %{
        server_state.game_state
        | cameras:
            Map.put(server_state.game_state.cameras, camera_id, %{camera | status: :disabled})
      }

      %{server_state | game_state: game_state}
    end)
  end

  defp set_power_room_thief_turn!(pid) do
    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | phase: :playing,
          current_turn: "player-theo",
          thief_position: {10, 9},
          turn_actions_remaining: [:move],
          power_active: true
      }

      %{server_state | game_state: game_state}
    end)
  end

  defp set_pending_steal_turn!(pid) do
    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | current_turn: "player-theo",
          turn_order: ["player-theo", "player-alice"],
          thief_position: {3, 6},
          turn_actions_remaining: [:move],
          dice: nil,
          cameras: Map.new(1..4, fn camera_id -> {camera_id, nil} end),
          paintings: %{{3, 7} => :present},
          painting_labels: %{{3, 7} => "A4"}
      }

      %{server_state | game_state: game_state}
    end)
  end

  defp set_detective_targeted_art_capture!(pid, chase_mode) do
    :sys.replace_state(pid, fn server_state ->
      game_state = %{
        server_state.game_state
        | phase: :playing,
          current_turn: "player-alice",
          thief_position: {3, 8},
          detective_positions: %{"player-alice" => {3, 9}, "player-bob" => {9, 5}},
          paintings: %{{3, 8} => :targeted},
          painting_labels: %{{3, 8} => "A7"},
          pending_steal: {3, 8},
          chase_mode: chase_mode,
          dice: {1, :eye},
          turn_actions_remaining: [:move, :look]
      }

      %{server_state | game_state: game_state}
    end)
  end
end
