defmodule MuseumCaper.Game.RulesActionsTest do
  use ExUnit.Case, async: true
  alias MuseumCaper.Game.{Rules, State}

  @players %{
    "t" => %{name: "Thief", role: :thief, color: :grey},
    "d1" => %{name: "Det1", role: :detective, color: :red},
    "d2" => %{name: "Det2", role: :detective, color: :blue}
  }

  def base_state do
    %{
      State.new_game(@players)
      | phase: :playing,
        thief_position: {4, 7},
        detective_positions: %{"d1" => {4, 5}, "d2" => {1, 1}},
        cameras: %{
          1 => %{pos: {4, 6}, status: :active},
          2 => %{pos: {2, 7}, status: :active},
          3 => %{pos: {1, 9}, status: :disabled},
          4 => nil
        },
        power_active: true,
        turn_actions_remaining: [:move, :look]
    }
  end

  def pending_steal_state do
    %{
      base_state()
      | paintings: %{{4, 7} => :targeted},
        painting_labels: %{{4, 7} => "A5"},
        pending_steal: {4, 7}
    }
  end

  describe "use_eye_action/2 (eyes)" do
    test "returns :no_sighting when thief not in LOS" do
      state = base_state()
      # d2 at {1,1} looking in all directions — thief at {4,7} not in LOS
      {:ok, :no_sighting, new_state} = Rules.use_eye_action(state, "d2")
      refute new_state.chase_mode
      refute :look in new_state.turn_actions_remaining
    end

    test "keeps detective movement available after looking from pawn before moving" do
      state = %{
        base_state()
        | current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          dice: {4, :eye},
          thief_position: {1, 6}
      }

      {:ok, :no_sighting, new_state} = Rules.use_eye_action(state, "d1")

      refute :look in new_state.turn_actions_remaining
      assert :move in new_state.turn_actions_remaining
      assert new_state.movement_spent == 0
      assert {:error, :movement_required} = Rules.end_turn(new_state)
      assert {:ok, moved_state} = Rules.move_detective(new_state, "d1", {3, 8})
      assert moved_state.detective_positions["d1"] == {3, 8}
    end

    test "spends remaining detective movement after looking from pawn after moving" do
      state = %{
        base_state()
        | current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          dice: {4, :eye},
          thief_position: {1, 6}
      }

      {:ok, moved_state} = Rules.move_detective(state, "d1", {3, 8})
      {:ok, :no_sighting, new_state} = Rules.use_eye_action(moved_state, "d1")

      refute :look in new_state.turn_actions_remaining
      refute :move in new_state.turn_actions_remaining
      assert {:error, :invalid_move} = Rules.move_detective(new_state, "d1", {4, 9})
      assert {:ok, advanced_state} = Rules.end_turn(new_state)
      assert advanced_state.current_turn == "t"
    end

    test "triggers chase when thief is in LOS" do
      # d1 at {4,5}, thief at {4,7}: east ray from d1 hits {4,6} (corridor) then {4,7} (thief!)
      state = base_state()
      {:ok, :chase_triggered, new_state} = Rules.use_eye_action(state, "d1")
      assert new_state.chase_mode == true
    end

    test "spotting thief on targeted artwork removes it immediately" do
      {:ok, :chase_triggered, new_state} = Rules.use_eye_action(pending_steal_state(), "d1")

      assert_steal_revealed(new_state)
      assert new_state.detective_result == {:artwork_stolen, "A5"}
    end

    test "turns power on when looking from a detective on the power room" do
      state = %{
        base_state()
        | current_turn: "d1",
          detective_positions: %{"d1" => {11, 9}, "d2" => {1, 1}},
          thief_position: {1, 4},
          power_active: false,
          power_revealed: true
      }

      {:ok, :no_sighting, new_state} = Rules.use_eye_action(state, "d1")

      assert new_state.power_active
      refute new_state.power_revealed
    end
  end

  describe "use_eye_on_camera/3 (single camera)" do
    test "returns :camera_disabled and leaves disabled camera revealed" do
      state = base_state()
      {:ok, :camera_disabled, new_state} = Rules.use_eye_on_camera(state, "d1", 3)
      assert new_state.cameras[3].status == :disabled
      assert new_state.cameras[3].revealed
      assert new_state.detective_result == {:look_camera, {:camera_disabled, 3}}
    end

    test "returns :no_sighting when active camera can't see thief" do
      # Camera 1 at {4,6}, thief moved to {1,6} — not in LOS from {4,6}
      state = %{base_state() | thief_position: {1, 6}}
      {:ok, :no_sighting, new_state} = Rules.use_eye_on_camera(state, "d1", 1)
      assert new_state.detective_result == {:look_camera, {:no_sighting, 1}}
    end

    test "reports sighting without revealing thief when active camera has LOS" do
      # Camera 1 at {4,6}, thief at {4,7}: looking east from {4,6}
      state = base_state()
      {:ok, {:sighting, 1}, new_state} = Rules.use_eye_on_camera(state, "d1", 1)
      refute new_state.chase_mode
      assert new_state.detective_result == {:look_camera, {:sighting, 1}}
    end

    test "camera sighting does not reveal targeted artwork immediately" do
      {:ok, {:sighting, 1}, new_state} =
        Rules.use_eye_on_camera(pending_steal_state(), "d1", 1)

      refute new_state.chase_mode
      assert new_state.pending_steal == {4, 7}
      assert new_state.paintings[{4, 7}] == :targeted
      assert new_state.stolen_count == 0
    end

    test "returns :power_off when power is disabled" do
      state = %{base_state() | power_active: false}
      {:ok, :power_off, new_state} = Rules.use_eye_on_camera(state, "d1", 1)
      assert new_state.power_revealed
    end

    test "turns power on before looking through a camera from the power room" do
      state = %{
        base_state()
        | current_turn: "d1",
          detective_positions: %{"d1" => {11, 9}, "d2" => {1, 1}},
          power_active: false,
          power_revealed: true
      }

      {:ok, {:sighting, 1}, new_state} = Rules.use_eye_on_camera(state, "d1", 1)

      assert new_state.power_active
      refute new_state.power_revealed
    end

    test "keeps detective movement available after looking through a camera before moving" do
      state = %{
        base_state()
        | current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          dice: {4, :eye},
          thief_position: {1, 6}
      }

      {:ok, :no_sighting, new_state} = Rules.use_eye_on_camera(state, "d1", 1)

      refute :look in new_state.turn_actions_remaining
      assert :move in new_state.turn_actions_remaining
      assert new_state.movement_spent == 0
      assert {:error, :movement_required} = Rules.end_turn(new_state)
      assert {:ok, moved_state} = Rules.move_detective(new_state, "d1", {3, 8})
      assert moved_state.detective_positions["d1"] == {3, 8}
    end

    test "spends remaining detective movement after looking through a camera after moving" do
      state = %{
        base_state()
        | current_turn: "d1",
          turn_order: ["d1", "t", "d2", "t"],
          dice: {4, :eye},
          thief_position: {1, 6}
      }

      {:ok, moved_state} = Rules.move_detective(state, "d1", {3, 8})
      {:ok, :no_sighting, new_state} = Rules.use_eye_on_camera(moved_state, "d1", 1)

      refute :look in new_state.turn_actions_remaining
      refute :move in new_state.turn_actions_remaining
      assert {:error, :invalid_move} = Rules.move_detective(new_state, "d1", {4, 9})
      assert {:ok, advanced_state} = Rules.end_turn(new_state)
      assert advanced_state.current_turn == "t"
    end
  end

  describe "use_camera_scan/1" do
    test "reveals all disabled cameras and reports" do
      state = base_state()
      {:ok, disabled_ids, _result, new_state} = Rules.use_camera_scan(state)
      assert 3 in disabled_ids
      assert new_state.cameras[3].status == :disabled
      assert new_state.cameras[3].revealed
    end

    test "reports which active camera sees thief without revealing thief" do
      # Camera 1 at {4,6}, thief at {4,7} — camera 1 can see thief
      state = base_state()
      {:ok, _, {:sighting, [1]}, new_state} = Rules.use_camera_scan(state)
      refute new_state.chase_mode
      assert new_state.detective_result == {:camera_scan, [3], {:sighting, [1]}}
    end

    test "camera scan sighting does not reveal targeted artwork immediately" do
      {:ok, _disabled_ids, {:sighting, [1]}, new_state} =
        Rules.use_camera_scan(pending_steal_state())

      refute new_state.chase_mode
      assert new_state.pending_steal == {4, 7}
      assert new_state.paintings[{4, 7}] == :targeted
      assert new_state.stolen_count == 0
    end

    test "returns :power_off when power is disabled" do
      state = %{base_state() | power_active: false}
      {:ok, :power_off, new_state} = Rules.use_camera_scan(state)
      assert new_state.power_revealed
    end

    test "turns power on before camera scan from the power room" do
      state = %{
        base_state()
        | current_turn: "d1",
          detective_positions: %{"d1" => {11, 9}, "d2" => {1, 1}},
          power_active: false,
          power_revealed: true
      }

      {:ok, [3], {:sighting, [1]}, new_state} = Rules.use_camera_scan(state)

      assert new_state.power_active
      refute new_state.power_revealed
    end
  end

  describe "use_motion_detector/1" do
    test "waits for thief decision before reading a motion roll" do
      state = %{base_state() | current_turn: "d1", dice: {4, :motion}}

      assert {:error, :motion_decision_pending} = Rules.use_motion_detector(state)
    end

    test "returns thief's cell color" do
      # thief at {4,7} = white_room = :white
      state = base_state()
      {:ok, {:color, :white}, new_state} = Rules.use_motion_detector(state)
      refute :look in new_state.turn_actions_remaining
    end

    test "reports hallways and utility rooms as gray" do
      for pos <- [{3, 4}, {10, 4}, {10, 8}, {11, 9}] do
        state = %{base_state() | thief_position: pos}
        assert {:ok, {:color, :gray}, _new_state} = Rules.use_motion_detector(state)
      end
    end

    test "detective cannot decide to cut a motion detector reading" do
      state = %{base_state() | current_turn: "d1", dice: {4, :motion}}

      assert {:error, :not_thief} = Rules.decide_motion_detector(state, "d1", :cut)
    end

    test "thief can snip to block — decrements snip count" do
      state = %{base_state() | current_turn: "d1", dice: {4, :motion}}

      {:ok, :snipped, new_state} = Rules.decide_motion_detector(state, "t", :cut)
      assert new_state.motion_snips_remaining == 1
      refute :look in new_state.turn_actions_remaining
    end

    test "thief cannot cut after two motion cuts are spent" do
      state = %{base_state() | current_turn: "d1", dice: {4, :motion}, motion_snips_remaining: 0}

      assert {:error, :invalid_action} = Rules.decide_motion_detector(state, "t", :cut)
      assert {:ok, {:color, :white}, new_state} = Rules.use_motion_detector(state)
      assert new_state.motion_snips_remaining == 0
    end

    test "thief can allow the detective to use the motion detector" do
      state = %{base_state() | current_turn: "d1", dice: {4, :motion}}

      assert {:ok, :allowed, allowed_state} = Rules.decide_motion_detector(state, "t", :allow)
      assert allowed_state.motion_detector_decision == :allowed
      assert :look in allowed_state.turn_actions_remaining

      assert {:ok, {:color, :white}, new_state} = Rules.use_motion_detector(allowed_state)
      assert new_state.motion_detector_decision == nil
      refute :look in new_state.turn_actions_remaining
    end

    test "returns color when snips are exhausted" do
      state = %{base_state() | motion_snips_remaining: 0}
      {:ok, {:color, _}, _} = Rules.use_motion_detector(state)
    end

    test "returns :power_off when power is disabled" do
      state = %{base_state() | power_active: false}
      {:ok, :power_off, new_state} = Rules.use_motion_detector(state)
      assert new_state.power_revealed
    end
  end

  describe "resolve_pending_steal/1" do
    test "stores stolen artwork as the latest detective result" do
      new_state = Rules.resolve_pending_steal(pending_steal_state())

      assert new_state.pending_steal == nil
      assert new_state.paintings[{4, 7}] == :removed
      assert new_state.stolen_count == 1
      assert "Artwork A5 stolen." in new_state.game_log
      assert new_state.detective_result == {:artwork_stolen, "A5"}
      assert new_state.detective_result_id == pending_steal_state().detective_result_id + 1
    end
  end

  defp assert_steal_revealed(state) do
    assert state.chase_mode
    assert state.pending_steal == nil
    assert state.paintings[{4, 7}] == :removed
    assert state.stolen_count == 1
    assert "Artwork A5 stolen." in state.game_log
  end
end
