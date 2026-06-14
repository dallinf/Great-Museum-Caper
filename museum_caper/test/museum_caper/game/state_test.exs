defmodule MuseumCaper.Game.StateTest do
  use ExUnit.Case, async: true
  alias MuseumCaper.Game.{Board, State}

  @players %{
    "thief-1" => %{name: "Alice", role: :thief, color: :grey},
    "det-1" => %{name: "Bob", role: :detective, color: :red},
    "det-2" => %{name: "Carol", role: :detective, color: :blue}
  }

  describe "new_game/1" do
    setup do
      {:ok, state: State.new_game(@players, ["thief-1", "det-1", "det-2"])}
    end

    test "sets phase to :setup", %{state: state} do
      assert state.phase == :setup
    end

    test "assigns thief player", %{state: state} do
      assert state.thief_player_id == "thief-1"
    end

    test "turn order alternates detectives and thief", %{state: state} do
      assert state.turn_order == ["det-1", "thief-1", "det-2", "thief-1"]
    end

    test "initializes unlocked locks for all doors and windows", %{state: state} do
      entry_ids = Enum.map(Board.entries(), & &1.id)
      assert Enum.sort(Map.keys(state.locks)) == Enum.sort(entry_ids)

      Enum.each(state.locks, fn {_id, status} ->
        assert status == :open
      end)
    end

    test "initializes cameras as nil (unplaced)", %{state: state} do
      assert Enum.sort(Map.keys(state.cameras)) == [1, 2, 3, 4]
      Enum.each(state.cameras, fn {_id, val} -> assert val == nil end)
    end

    test "initializes detective positions as nil", %{state: state} do
      assert state.detective_positions["det-1"] == nil
      assert state.detective_positions["det-2"] == nil
    end

    test "thief starts with 2 motion snips", %{state: state} do
      assert state.motion_snips_remaining == 2
    end

    test "power is active", %{state: state} do
      assert state.power_active == true
    end

    test "setup_step is :locks", %{state: state} do
      assert state.setup_step == :locks
    end
  end
end
