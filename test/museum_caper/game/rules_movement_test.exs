defmodule MuseumCaper.Game.RulesMovementTest do
  use ExUnit.Case, async: true
  alias MuseumCaper.Game.{Board, Rules, State}

  @players %{
    "t" => %{name: "Thief", role: :thief, color: :grey},
    "d1" => %{name: "Det1", role: :detective, color: :red},
    "d2" => %{name: "Det2", role: :detective, color: :blue}
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

  # New board positions (11 rows x 12 cols):
  #   hall cells: {3,4}-{3,9}, {4,4},{4,9}, {5,4},{5,9}-{5,11},
  #               {6,2}-{6,4},{6,9}, {7,4},{7,9}, {8,4},{8,9},
  #               {9,4}-{9,9}, {10,6},{10,7}, {11,6},{11,7}
  #   gallery_red: rows 1-2, cols 4-9
  #   gallery_yellow: rows 7-9, cols 1-3
  #   power_room: {11,9}
  def base_state do
    state = State.new_game(@players)

    %{
      state
      | phase: :playing,
        thief_position: {3, 6},
        detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
        turn_actions_remaining: [:move]
    }
  end

  def painting_setup_state do
    %{State.new_game(@players) | setup_step: :paintings}
  end

  describe "enter_museum/2" do
    test "starts the thief's first turn at the chosen entrance" do
      state = %{State.new_game(@players) | phase: :thief_entry}

      assert {:ok, state} = Rules.enter_museum(state, :exit_w1)
      assert state.phase == :playing
      assert state.thief_position == {6, 2}
      assert state.current_turn == "t"
      assert state.turn_order == ["t", "d1", "t", "d2"]
      assert state.turn_actions_remaining == [:move]
      assert state.dice == nil
    end

    test "starts the thief inside a bottom door entrance" do
      state = %{State.new_game(@players) | phase: :thief_entry}

      assert {:ok, state} = Rules.enter_museum(state, :exit_s1)
      assert state.thief_position == {10, 6}
      assert state.turn_actions_remaining == [:move]
    end

    test "lets the thief enter through a window" do
      state = %{State.new_game(@players) | phase: :thief_entry}

      assert {:ok, state} = Rules.enter_museum(state, :window_1_5)
      assert state.phase == :playing
      assert state.thief_position == {1, 5}
      assert state.current_turn == "t"
      assert state.turn_actions_remaining == [:move]
    end
  end

  describe "toggle_lock/2" do
    test "locks a door or window during the first setup step" do
      state = State.new_game(@players)

      assert {:ok, state} = Rules.toggle_lock(state, :exit_w1)
      assert state.locks[:exit_w1] == :locked
      assert state.setup_step == :locks

      assert {:ok, state} = Rules.toggle_lock(state, :window_1_5)
      assert state.locks[:window_1_5] == :locked
    end

    test "clicking a locked entry toggles it back open" do
      state = State.new_game(@players)

      assert {:ok, state} = Rules.toggle_lock(state, :exit_w1)
      assert {:ok, state} = Rules.toggle_lock(state, :exit_w1)

      assert state.locks[:exit_w1] == :open
      assert state.setup_step == :locks
    end

    test "advances setup to paintings after the required locks are placed" do
      state = State.new_game(@players)

      state =
        Board.entries()
        |> Enum.take(Board.lock_count())
        |> Enum.reduce(state, fn %{id: entry_id}, state ->
          {:ok, state} = Rules.toggle_lock(state, entry_id)
          state
        end)

      assert Enum.count(state.locks, fn {_id, status} -> status == :locked end) ==
               Board.lock_count()

      assert state.setup_step == :paintings
    end

    test "rejects non-entry lock placement" do
      state = State.new_game(@players)
      assert {:error, :invalid_placement} = Rules.toggle_lock(state, :not_an_entry)
    end

    test "does not allow paintings before lock setup is complete" do
      state = State.new_game(@players)
      assert {:error, :invalid_phase} = Rules.place_painting(state, {1, 4})
    end
  end

  describe "place_painting/2" do
    test "places painting in a room cell" do
      state = painting_setup_state()
      {:ok, new_state} = Rules.place_painting(state, {1, 4})
      assert new_state.paintings[{1, 4}] == :present
      assert new_state.painting_labels[{1, 4}] == "A1"
    end

    test "rejects painting in corridor (hall)" do
      state = painting_setup_state()
      assert {:error, :invalid_placement} = Rules.place_painting(state, {3, 5})
    end

    test "rejects painting in power room" do
      state = painting_setup_state()
      assert {:error, :invalid_placement} = Rules.place_painting(state, {11, 9})
    end

    test "rejects painting in the room with power" do
      state = painting_setup_state()
      assert {:error, :invalid_placement} = Rules.place_painting(state, {11, 8})
      assert {:error, :invalid_placement} = Rules.place_painting(state, {10, 9})
    end

    test "rejects painting in front of windows" do
      state = painting_setup_state()

      for pos <- [{4, 1}, {8, 1}, {9, 2}, {1, 5}, {1, 8}, {3, 11}, {8, 12}] do
        assert {:error, :invalid_placement} = Rules.place_painting(state, pos)
      end
    end

    test "rejects painting right inside room doors" do
      state = painting_setup_state()

      door_cells = [
        {2, 5},
        {2, 8},
        {4, 6},
        {4, 7},
        {4, 10},
        {5, 3},
        {6, 8},
        {7, 5},
        {8, 3},
        {8, 6},
        {8, 7},
        {8, 10},
        {10, 5},
        {10, 8}
      ]

      for pos <- door_cells do
        assert {:error, :invalid_placement} = Rules.place_painting(state, pos)
      end
    end

    test "rejects painting on already-occupied cell" do
      state = painting_setup_state()
      {:ok, state} = Rules.place_painting(state, {1, 4})
      assert {:error, :cell_occupied} = Rules.place_painting(state, {1, 4})
    end

    test "advances setup_step to :cameras after 9 paintings" do
      state = painting_setup_state()

      state =
        Enum.reduce(@valid_painting_cells, state, fn pos, s ->
          {:ok, s2} = Rules.place_painting(s, pos)
          s2
        end)

      assert state.setup_step == :cameras
    end

    test "rejects ninth painting unless every required room has artwork" do
      state = painting_setup_state()
      cells = [{1, 4}, {1, 6}, {1, 7}, {1, 9}, {2, 4}, {2, 6}, {2, 7}, {2, 9}]

      state =
        Enum.reduce(cells, state, fn pos, s ->
          {:ok, s2} = Rules.place_painting(s, pos)
          s2
        end)

      assert {:error, :missing_color_room} = Rules.place_painting(state, {3, 1})
    end

    test "does not require artwork in optional room at {10, 4}" do
      state = painting_setup_state()
      cells = [{1, 4}, {3, 1}, {3, 10}, {7, 1}, {6, 11}, {4, 5}, {2, 4}, {1, 6}]

      state =
        Enum.reduce(cells, state, fn pos, s ->
          {:ok, s2} = Rules.place_painting(s, pos)
          s2
        end)

      assert {:ok, state} = Rules.place_painting(state, {6, 12})
      assert state.setup_step == :cameras
      refute Map.has_key?(state.paintings, {10, 4})
    end

    test "does not require artwork in the room with power" do
      state = painting_setup_state()
      cells = [{1, 4}, {3, 1}, {3, 10}, {7, 1}, {6, 11}, {4, 5}, {10, 4}, {1, 6}]

      state =
        Enum.reduce(cells, state, fn pos, s ->
          {:ok, s2} = Rules.place_painting(s, pos)
          s2
        end)

      assert {:ok, state} = Rules.place_painting(state, {6, 12})
      assert state.setup_step == :cameras
      refute Map.has_key?(state.paintings, {11, 8})
    end

    test "removes existing painting and returns setup to paintings" do
      state = %{
        State.new_game(@players)
        | setup_step: :cameras,
          paintings: Map.new(@valid_painting_cells, fn pos -> {pos, :present} end),
          painting_labels:
            @valid_painting_cells
            |> Enum.with_index(1)
            |> Map.new(fn {pos, index} -> {pos, "A#{index}"} end)
      }

      assert {:ok, new_state} = Rules.remove_painting(state, {1, 4})
      refute Map.has_key?(new_state.paintings, {1, 4})
      refute Map.has_key?(new_state.painting_labels, {1, 4})
      assert new_state.setup_step == :paintings
    end
  end

  describe "place_camera/3" do
    test "places camera on any occupiable cell" do
      state = %{State.new_game(@players) | setup_step: :cameras}
      {:ok, new_state} = Rules.place_camera(state, 1, {4, 6})
      assert new_state.cameras[1] == %{pos: {4, 6}, status: :active}
    end

    test "rejects camera on already-occupied cell" do
      state = %{State.new_game(@players) | setup_step: :cameras}
      {:ok, state} = Rules.place_camera(state, 1, {4, 6})
      assert {:error, :cell_occupied} = Rules.place_camera(state, 2, {4, 6})
    end

    test "rejects camera on power and bottom external door cells" do
      state = %{State.new_game(@players) | setup_step: :cameras}

      assert {:error, :invalid_placement} = Rules.place_camera(state, 1, {11, 9})
      assert {:error, :invalid_placement} = Rules.place_camera(state, 1, {11, 6})
      assert {:error, :invalid_placement} = Rules.place_camera(state, 1, {11, 7})
    end

    test "advances setup_step to :pawns after 4 cameras" do
      state = %{State.new_game(@players) | setup_step: :cameras}
      positions = [{4, 6}, {4, 7}, {3, 5}, {3, 8}]

      state =
        positions
        |> Enum.with_index(1)
        |> Enum.reduce(state, fn {pos, id}, s ->
          {:ok, s2} = Rules.place_camera(s, id, pos)
          s2
        end)

      assert state.setup_step == :pawns
    end

    test "removes existing camera and returns setup to cameras" do
      state = %{
        State.new_game(@players)
        | setup_step: :pawns,
          cameras: %{
            1 => %{pos: {4, 6}, status: :active},
            2 => %{pos: {4, 7}, status: :active},
            3 => %{pos: {3, 5}, status: :active},
            4 => %{pos: {3, 8}, status: :active}
          }
      }

      assert {:ok, new_state} = Rules.remove_camera_at(state, {4, 6})
      assert new_state.cameras[1] == nil
      assert new_state.setup_step == :cameras
    end
  end

  describe "place_detective_pawn/3" do
    test "places detective pawn on unoccupied cell" do
      state = %{State.new_game(@players) | setup_step: :pawns}
      {:ok, new_state} = Rules.place_detective_pawn(state, "d1", {1, 4})
      assert new_state.detective_positions["d1"] == {1, 4}
    end

    test "rejects pawn on painting cell" do
      state = %{State.new_game(@players) | setup_step: :pawns, paintings: %{{1, 4} => :present}}
      assert {:error, :cell_occupied} = Rules.place_detective_pawn(state, "d1", {1, 4})
    end

    test "rejects pawn on bottom external door cells" do
      state = %{State.new_game(@players) | setup_step: :pawns}

      assert {:error, :cell_occupied} = Rules.place_detective_pawn(state, "d1", {11, 6})
      assert {:error, :cell_occupied} = Rules.place_detective_pawn(state, "d1", {11, 7})
    end

    test "transitions to :thief_entry when all pawns placed" do
      state = %{State.new_game(@players) | setup_step: :pawns}
      {:ok, state} = Rules.place_detective_pawn(state, "d1", {1, 4})
      {:ok, state} = Rules.place_detective_pawn(state, "d2", {7, 1})
      assert state.phase == :thief_entry
    end
  end

  describe "valid_thief_destinations/1" do
    test "returns cells reachable in 1-3 steps from hall" do
      # Thief at {3,6} (hall). 1-step: {3,5},{3,7},{4,6}(via doorway)
      # 3-step: {4,4}(via {3,5}->{3,4}->{4,4})
      state = base_state()
      destinations = Rules.valid_thief_destinations(state)
      assert {3, 5} in destinations
      assert {3, 7} in destinations
      # via doorway into white_room
      assert {4, 6} in destinations
      # via the corrected red doorway after moving through hall {3,5}
      assert {2, 5} in destinations
      # 3 steps: {3,6}->{3,5}->{3,4}->{4,4}
      assert {4, 4} in destinations
      # starting cell excluded
      refute {3, 6} in destinations
    end

    test "can pass through a detective but cannot land on their cell" do
      state = %{
        base_state()
        | thief_position: {3, 6},
          detective_positions: %{"d1" => {3, 7}, "d2" => {9, 5}}
      }

      destinations = Rules.valid_thief_destinations(state, 2)

      refute {3, 7} in destinations
      assert {3, 8} in destinations
    end

    test "cannot revisit start in same turn" do
      state = base_state()
      destinations = Rules.valid_thief_destinations(state)
      refute {3, 6} in destinations
    end

    test "can limit thief destinations to fewer steps" do
      state = base_state()
      destinations = Rules.valid_thief_destinations(state, 2)

      assert {3, 4} in destinations
      refute {4, 4} in destinations
    end

    test "can still reach cells when detectives stand nearby" do
      # Thief at {2,5} (gallery_red). d1 stands at {2,4}, d2 stands at {2,6}.
      # Can still go north {1,5} and south {3,5} via doorway.
      state = %{
        base_state()
        | thief_position: {2, 5},
          detective_positions: %{"d1" => {2, 4}, "d2" => {2, 6}}
      }

      destinations = Rules.valid_thief_destinations(state)
      assert {1, 5} in destinations
      # hall, via doorway
      assert {3, 5} in destinations
    end
  end

  describe "move_thief/2" do
    test "valid move updates thief position" do
      state = base_state()
      {:ok, new_state} = Rules.move_thief(state, {3, 7})
      assert new_state.thief_position == {3, 7}
    end

    test "thief can revise final movement destination until ending turn" do
      state = base_state()

      assert {:ok, state} = Rules.move_thief(state, {3, 7})
      assert state.turn_actions_remaining == [:move]
      assert {:ok, _advanced_state} = Rules.end_turn(state)

      assert {:ok, state} = Rules.move_thief(state, {3, 8})
      assert state.thief_position == {3, 8}

      assert {:ok, state} = Rules.move_thief(state, {4, 4})
      assert state.thief_position == {4, 4}
      assert state.movement_spent == 3
    end

    test "rejects move to invalid destination" do
      state = base_state()
      assert {:error, :invalid_move} = Rules.move_thief(state, {1, 1})
    end

    test "landing on camera disables it" do
      state = %{
        base_state()
        | cameras: %{1 => %{pos: {3, 7}, status: :active}, 2 => nil, 3 => nil, 4 => nil}
      }

      {:ok, new_state} = Rules.move_thief(state, {3, 7})
      assert new_state.cameras[1].status == :disabled
    end

    test "landing on painting sets pending_steal" do
      state = %{base_state() | paintings: %{{3, 7} => :present}}
      {:ok, new_state} = Rules.move_thief(state, {3, 7})
      assert new_state.pending_steal == {3, 7}
      assert new_state.paintings[{3, 7}] == :targeted
    end

    test "landing on power room disables power" do
      # other_right {10,9} is same zone as power_room {11,9}
      state = %{base_state() | thief_position: {10, 9}}
      {:ok, new_state} = Rules.move_thief(state, {11, 9})
      assert new_state.power_active == false
    end
  end

  describe "try_escape/2" do
    test "lets thief escape through an unlocked window" do
      state = %{
        base_state()
        | thief_position: {1, 5},
          locks: Map.put(base_state().locks, :window_1_5, :open)
      }

      assert {:ok, :escaped, state} = Rules.try_escape(state, :window_1_5)
      assert state.phase == :game_over
      assert state.winner == :thief
      assert state.game_over_reason == :escaped
    end

    test "lets thief escape through an unlocked bottom door from the inside square" do
      state = %{
        base_state()
        | thief_position: {10, 6},
          locks: Map.put(base_state().locks, :exit_s1, :open)
      }

      assert {:ok, :escaped, state} = Rules.try_escape(state, :exit_s1)
      assert state.phase == :game_over
      assert state.winner == :thief
      assert state.game_over_reason == :escaped
    end

    test "locked window does not start chase or end the game" do
      state = %{
        base_state()
        | thief_position: {1, 5},
          locks: Map.put(base_state().locks, :window_1_5, :locked)
      }

      assert {:ok, :locked, state} = Rules.try_escape(state, :window_1_5)
      refute state.chase_mode
      assert state.phase == :playing
      assert state.detective_result == {:escape_locked, :window_1_5}
    end

    test "rejects escape attempts when thief is not at that door or window" do
      state = %{base_state() | thief_position: {3, 6}}
      assert {:error, :not_adjacent} = Rules.try_escape(state, :window_1_5)
    end
  end

  describe "valid_detective_destinations/2" do
    test "returns cells within dice roll distance" do
      # d1 at {3,8} (hall). Doorway north to gallery_red at {2,8}.
      state = %{
        base_state()
        | dice: {3, :eye},
          detective_positions: %{"d1" => {3, 8}, "d2" => {9, 5}}
      }

      destinations = Rules.valid_detective_destinations(state, "d1")
      # 1 step west
      assert {3, 7} in destinations
      # 1 step via doorway into gallery_red
      assert {2, 8} in destinations
      # 1 step east
      assert {3, 9} in destinations
    end

    test "cannot land on another detective" do
      state = %{
        base_state()
        | dice: {3, :eye},
          detective_positions: %{"d1" => {3, 9}, "d2" => {4, 9}}
      }

      destinations = Rules.valid_detective_destinations(state, "d1")
      refute {4, 9} in destinations
    end

    test "can pass through another detective" do
      state = %{
        base_state()
        | dice: {2, :eye},
          thief_position: {1, 4},
          detective_positions: %{"d1" => {3, 6}, "d2" => {3, 7}}
      }

      destinations = Rules.valid_detective_destinations(state, "d1")

      refute {3, 7} in destinations
      assert {3, 8} in destinations
    end

    test "can land on and move through active painting cells" do
      state = %{
        base_state()
        | dice: {5, :eye},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          paintings: %{{3, 8} => :present}
      }

      destinations = Rules.valid_detective_destinations(state, "d1")

      assert {3, 8} in destinations
      assert {3, 7} in destinations
    end

    test "can cross artwork spaces inside the white room" do
      state = %{
        base_state()
        | dice: {6, :eye},
          detective_positions: %{"d1" => {6, 6}, "d2" => {9, 5}},
          paintings: %{{4, 5} => :present}
      }

      destinations = Rules.valid_detective_destinations(state, "d1")

      assert {4, 5} in destinations
      assert {4, 6} in destinations
    end

    test "can use a painting space after the thief removes it" do
      state = %{
        base_state()
        | dice: {5, :eye},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          paintings: %{{3, 8} => :removed}
      }

      destinations = Rules.valid_detective_destinations(state, "d1")

      assert {3, 8} in destinations
      assert {3, 7} in destinations
    end

    test "cannot land on a targeted painting while the thief is hidden there" do
      state = %{
        base_state()
        | dice: {1, :eye},
          thief_position: {3, 8},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          paintings: %{{3, 8} => :targeted},
          chase_mode: false
      }

      destinations = Rules.valid_detective_destinations(state, "d1")

      refute {3, 8} in destinations
    end

    test "can land on a known thief on a targeted painting" do
      state = %{
        base_state()
        | dice: {1, :eye},
          thief_position: {3, 8},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          paintings: %{{3, 8} => :targeted},
          chase_mode: true
      }

      destinations = Rules.valid_detective_destinations(state, "d1")

      assert {3, 8} in destinations
    end

    test "can land on and move through camera cells" do
      state = %{
        base_state()
        | dice: {5, :eye},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          cameras: %{1 => %{pos: {3, 8}, status: :active}, 2 => nil, 3 => nil, 4 => nil}
      }

      destinations = Rules.valid_detective_destinations(state, "d1")

      assert {3, 8} in destinations
      assert {3, 7} in destinations
    end

    test "cannot land on or move through external door cells" do
      for {inside_cell, door_cell} <- [
            {{10, 6}, {11, 6}},
            {{10, 7}, {11, 7}},
            {{5, 11}, {5, 12}},
            {{6, 2}, {6, 1}}
          ] do
        state = %{
          base_state()
          | dice: {1, :eye},
            detective_positions: %{"d1" => inside_cell, "d2" => {9, 5}}
        }

        destinations = Rules.valid_detective_destinations(state, "d1")

        refute door_cell in destinations
      end
    end
  end

  describe "move_detective/3" do
    test "valid move updates detective position" do
      state = %{base_state() | dice: {3, :eye}, turn_actions_remaining: [:move, :look]}
      {:ok, new_state} = Rules.move_detective(state, "d1", {3, 8})
      assert new_state.detective_positions["d1"] == {3, 8}
      assert :move in new_state.turn_actions_remaining
    end

    test "rejects moves onto external door cells" do
      state = %{
        base_state()
        | dice: {1, :eye},
          turn_actions_remaining: [:move, :look],
          detective_positions: %{"d1" => {10, 6}, "d2" => {9, 5}}
      }

      assert {:error, :invalid_move} = Rules.move_detective(state, "d1", {11, 6})
    end

    test "detective can keep moving with remaining die movement" do
      state = %{
        base_state()
        | current_turn: "d1",
          dice: {6, :eye},
          thief_position: {1, 4},
          turn_actions_remaining: [:move, :look]
      }

      assert {:ok, state} = Rules.move_detective(state, "d1", {3, 7})
      assert state.detective_positions["d1"] == {3, 7}
      assert :move in state.turn_actions_remaining
      assert {4, 4} in Rules.valid_detective_destinations(state, "d1")
      assert {:ok, _state} = Rules.end_turn(state)

      assert {:ok, state} = Rules.move_detective(state, "d1", {4, 4})
      assert state.detective_positions["d1"] == {4, 4}
      assert {:ok, _state} = Rules.end_turn(state)
    end

    test "detective keeps original legal destinations open until ending turn" do
      state = %{
        base_state()
        | current_turn: "d1",
          dice: {6, :eye},
          thief_position: {1, 4},
          turn_actions_remaining: [:move, :look]
      }

      assert {:ok, state} = Rules.move_detective(state, "d1", {3, 7})
      assert state.detective_positions["d1"] == {3, 7}
      assert {9, 9} in Rules.valid_detective_destinations(state, "d1")

      assert {:ok, state} = Rules.move_detective(state, "d1", {9, 9})
      assert state.detective_positions["d1"] == {9, 9}
      assert state.movement_spent == 6
    end

    test "detective can undo to the turn start and regain full movement" do
      state = %{
        base_state()
        | current_turn: "d1",
          dice: {6, :eye},
          thief_position: {1, 4},
          turn_actions_remaining: [:move, :look]
      }

      assert {:ok, state} = Rules.move_detective(state, "d1", {3, 7})
      assert {3, 9} in Rules.valid_detective_destinations(state, "d1")

      assert {:ok, state} = Rules.move_detective(state, "d1", {3, 9})
      assert state.detective_positions["d1"] == {3, 9}
      assert {:error, :movement_required} = Rules.end_turn(state)
      assert {4, 4} in Rules.valid_detective_destinations(state, "d1")
    end

    test "landing on thief waits for end turn before capture" do
      # d1 at {3,9}, thief at {3,8} (1 step west)
      state = %{
        base_state()
        | dice: {3, :eye},
          current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          thief_position: {3, 8},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          chase_mode: false,
          turn_actions_remaining: [:move, :look]
      }

      {:ok, state} = Rules.move_detective(state, "d1", {3, 8})
      assert state.phase == :playing
      assert state.winner == nil
      assert state.game_over_reason == nil

      assert {:ok, state} = Rules.end_turn(state)
      assert state.phase == :game_over
      assert state.winner == :detectives
      assert state.game_over_reason == :caught
    end

    test "landing on a known thief on a targeted painting waits for end turn before capture" do
      state = %{
        base_state()
        | dice: {1, :eye},
          current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          thief_position: {3, 8},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          paintings: %{{3, 8} => :targeted},
          chase_mode: true,
          turn_actions_remaining: [:move, :look]
      }

      assert {:ok, state} = Rules.move_detective(state, "d1", {3, 8})
      assert state.phase == :playing
      assert state.winner == nil
      assert state.game_over_reason == nil

      assert {:ok, state} = Rules.end_turn(state)
      assert state.phase == :game_over
      assert state.winner == :detectives
      assert state.game_over_reason == :caught
    end

    test "undoing a thief landing before end turn avoids capture" do
      state = %{
        base_state()
        | dice: {3, :eye},
          current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          thief_position: {3, 8},
          detective_positions: %{"d1" => {3, 9}, "d2" => {9, 5}},
          chase_mode: true,
          turn_actions_remaining: [:move, :look]
      }

      assert {:ok, state} = Rules.move_detective(state, "d1", {3, 8})
      assert state.detective_positions["d1"] == {3, 8}

      assert {:ok, state} = Rules.move_detective(state, "d1", {3, 9})
      assert state.detective_positions["d1"] == {3, 9}
      assert {:error, :movement_required} = Rules.end_turn(state)
      assert state.phase == :playing
    end
  end

  describe "advance_turn/1" do
    test "end_turn rejects turns that still have movement available" do
      state = %{base_state() | current_turn: "t", turn_actions_remaining: [:move]}

      assert {:error, :movement_required} = Rules.end_turn(state)
    end

    test "end_turn advances after movement has been spent" do
      state = %{
        base_state()
        | current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          turn_actions_remaining: [:look],
          dice: {5, :eye}
      }

      assert {:ok, state} = Rules.end_turn(state)
      assert state.current_turn == "t"
      assert state.turn_order == ["t", "d2", "t", "d1"]
    end

    test "alternates detective, thief, next detective, thief" do
      state = %{
        base_state()
        | current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          turn_actions_remaining: [:move, :look],
          dice: {5, :eye}
      }

      state = Rules.advance_turn(state)
      assert state.current_turn == "t"
      assert state.turn_order == ["t", "d2", "t", "d1"]
      assert state.turn_actions_remaining == [:move]
      assert state.dice == nil

      state = Rules.advance_turn(state)
      assert state.current_turn == "d2"
      assert state.turn_order == ["d2", "t", "d1", "t"]
      assert state.turn_actions_remaining == [:move, :look]
      assert match?({number, _picture} when number in 1..6, state.dice)

      state = Rules.advance_turn(state)
      assert state.current_turn == "t"
      assert state.turn_order == ["t", "d1", "t", "d2"]
      assert state.turn_actions_remaining == [:move]
      assert state.dice == nil
    end

    test "detectives only roll the numbered die once the thief is visible" do
      state = %{
        base_state()
        | chase_mode: true,
          current_turn: "t",
          turn_order: ["t", "d1", "t", "d2"],
          turn_actions_remaining: [:move],
          dice: nil
      }

      state = Rules.advance_turn(state)

      assert state.current_turn == "d1"
      assert state.turn_actions_remaining == [:move]
      assert match?({number, nil} when number in 1..6, state.dice)
    end
  end
end
