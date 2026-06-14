defmodule MuseumCaper.Game.ProjectionTest do
  use ExUnit.Case, async: true
  alias MuseumCaper.Game.{Projection, State}

  @players %{
    "t" => %{name: "Thief", role: :thief, color: :grey},
    "d1" => %{name: "Det1", role: :detective, color: :red},
    "d2" => %{name: "Det2", role: :detective, color: :blue}
  }

  def playing_state do
    %{
      State.new_game(@players)
      | phase: :playing,
        thief_position: {4, 5},
        detective_positions: %{"d1" => {1, 1}, "d2" => {7, 7}},
        cameras: %{
          1 => %{pos: {4, 4}, status: :disabled},
          2 => %{pos: {2, 6}, status: :active},
          3 => nil,
          4 => nil
        },
        paintings: %{{2, 2} => :present, {5, 5} => :removed},
        painting_labels: %{{2, 2} => "A1", {5, 5} => "A2"},
        stolen_count: 1,
        current_turn: "d1"
    }
  end

  describe "project_state/2 for thief" do
    test "thief sees their own position" do
      view = Projection.project_state(playing_state(), "t")
      assert view.my_position == {4, 5}
    end

    test "thief sees all camera statuses" do
      view = Projection.project_state(playing_state(), "t")
      assert view.cameras[1].status == :disabled
      assert view.cameras[2].status == :active
    end

    test "thief sees motion_snips_remaining" do
      view = Projection.project_state(playing_state(), "t")
      assert view.motion_snips_remaining == 2
    end

    test "thief sees targeted painting status" do
      state = %{playing_state() | paintings: %{{3, 3} => :targeted}}
      view = Projection.project_state(state, "t")
      assert view.paintings[{3, 3}] == :targeted
    end

    test "thief sees removed paintings so stolen artwork stays on board" do
      view = Projection.project_state(playing_state(), "t")
      assert view.paintings[{5, 5}] == :removed
      assert view.painting_labels[{5, 5}] == "A2"
    end
  end

  describe "project_state/2 for detective" do
    test "detective does NOT see thief position (non-chase)" do
      view = Projection.project_state(playing_state(), "d1")
      assert view.thief_position == nil
    end

    test "detective sees thief position in chase mode" do
      state = %{playing_state() | chase_mode: true}
      view = Projection.project_state(state, "d1")
      assert view.thief_position == {4, 5}
    end

    test "detective does not see disabled camera status until revealed" do
      view = Projection.project_state(playing_state(), "d1")
      # Camera 1 is disabled but detective hasn't confirmed it yet — still shows as active
      assert view.cameras[1].status == :active
    end

    test "detective sees disabled camera status after it is revealed" do
      state =
        put_in(playing_state().cameras[1], %{pos: {4, 4}, status: :disabled, revealed: true})

      view = Projection.project_state(state, "d1")
      assert view.cameras[1].status == :disabled
    end

    test "nil cameras (confirmed removed) are nil for detectives too" do
      view = Projection.project_state(playing_state(), "d1")
      assert view.cameras[3] == nil
    end

    test "detective sees paintings that are :present" do
      view = Projection.project_state(playing_state(), "d1")
      assert view.paintings[{2, 2}] == :present
    end

    test "detective sees removed paintings so stolen artwork stays on board" do
      view = Projection.project_state(playing_state(), "d1")
      assert view.paintings[{5, 5}] == :removed
      assert view.painting_labels[{5, 5}] == "A2"
    end

    test "detective sees targeted paintings as present until the steal is confirmed" do
      state = %{playing_state() | paintings: %{{3, 3} => :targeted}}
      view = Projection.project_state(state, "d1")
      assert view.paintings[{3, 3}] == :present
    end

    test "detective sees their own valid destinations when it's their turn" do
      state = %{
        playing_state()
        | current_turn: "d1",
          dice: {3, :eye},
          turn_actions_remaining: [:move, :look]
      }

      view = Projection.project_state(state, "d1")
      assert is_list(view.valid_destinations)
    end
  end
end
