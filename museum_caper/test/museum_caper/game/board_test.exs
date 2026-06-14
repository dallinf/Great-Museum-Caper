defmodule MuseumCaper.Game.BoardTest do
  use ExUnit.Case, async: true
  alias MuseumCaper.Game.Board

  describe "cell/1" do
    test "returns hall (corridor) cell" do
      cell = Board.cell({3, 4})
      assert cell.room_id == :hall
      assert cell.type == :corridor
      assert cell.occupiable == true
    end

    test "returns power room cell at {11, 9}" do
      cell = Board.cell({11, 9})
      assert cell.type == :power_room
      assert cell.room_id == :power_room
      assert cell.color == :orange
    end

    test "returns gallery_red cell at {1, 4}" do
      cell = Board.cell({1, 4})
      assert cell.type == :room
      assert cell.room_id == :gallery_red
      assert cell.color == :red
    end

    test "returns gallery_purple cell at {3, 1}" do
      cell = Board.cell({3, 1})
      assert cell.type == :room
      assert cell.room_id == :gallery_purple
      assert cell.color == :purple
    end

    test "returns gallery_yellow cell at {7, 1}" do
      cell = Board.cell({7, 1})
      assert cell.type == :room
      assert cell.room_id == :gallery_yellow
      assert cell.color == :yellow
    end

    test "returns gallery_green cell at {6, 10}" do
      cell = Board.cell({6, 10})
      assert cell.type == :room
      assert cell.room_id == :gallery_green
    end

    test "returns gallery_blue cell at {3, 10}" do
      cell = Board.cell({3, 10})
      assert cell.type == :room
      assert cell.room_id == :gallery_blue
    end

    test "returns white_room cell at {4, 5}" do
      cell = Board.cell({4, 5})
      assert cell.type == :room
      assert cell.room_id == :white_room
    end

    test "returns other_left cell at {10, 4}" do
      cell = Board.cell({10, 4})
      assert cell.type == :room
      assert cell.room_id == :other_left
      assert cell.color == :orange
    end

    test "returns other_right cell at {10, 8}" do
      cell = Board.cell({10, 8})
      assert cell.type == :room
      assert cell.room_id == :other_right
      assert cell.color == :orange
    end

    test "returns nil for non-playable boundary cells" do
      # Row 1 corners
      assert Board.cell({1, 1}) == nil
      assert Board.cell({1, 2}) == nil
      assert Board.cell({1, 3}) == nil
      # Row 5, col 12
      assert Board.cell({5, 12}) == nil
      # Row 6, col 1
      assert Board.cell({6, 1}) == nil
    end

    test "returns nil for out-of-bounds" do
      assert Board.cell({0, 0}) == nil
      assert Board.cell({12, 1}) == nil
      assert Board.cell({1, 0}) == nil
      assert Board.cell({1, 13}) == nil
    end
  end

  describe "passable?/2" do
    test "adjacent hall cells are passable" do
      # Row 3 halls
      assert Board.passable?({3, 4}, {3, 5})
      assert Board.passable?({3, 5}, {3, 6})
    end

    test "hall connects to power room zone (other_right)" do
      # other_right and power_room share a zone
      assert Board.passable?({11, 8}, {11, 9})
    end

    test "within same gallery room is passable" do
      # gallery_red
      assert Board.passable?({1, 4}, {1, 5})
      assert Board.passable?({1, 4}, {2, 4})
      # gallery_yellow
      assert Board.passable?({7, 1}, {8, 1})
    end

    test "room-to-hall only passable at doorway" do
      # Doorway: gallery_red {2,5} <-> hall {3,5}
      assert Board.passable?({2, 5}, {3, 5})
      refute Board.passable?({2, 6}, {3, 6})
      refute Board.passable?({2, 9}, {3, 9})
      # Not a doorway: {1,4} -> {1,3} (nil cell)
      refute Board.passable?({1, 4}, {1, 3})
    end

    test "white_room to hall at valid doorways" do
      # White north: {4,6} and {4,7} <-> row 3 hall
      assert Board.passable?({4, 6}, {3, 6})
      assert Board.passable?({4, 7}, {3, 7})
      refute Board.passable?({4, 8}, {3, 8})
      # White south: {8,6} and {8,7} <-> row 9 hall
      assert Board.passable?({8, 6}, {9, 6})
      assert Board.passable?({8, 7}, {9, 7})
      refute Board.passable?({8, 8}, {9, 8})
      # White west: {7,5} <-> {7,4}
      assert Board.passable?({7, 5}, {7, 4})
    end

    test "gallery_purple to hall at doorway {5,3}<->{5,4}" do
      assert Board.passable?({5, 3}, {5, 4})
      # Other purple borders not passable
      refute Board.passable?({3, 3}, {3, 4})
    end

    test "gallery_blue to hall at doorway {4,10}<->{4,9}" do
      assert Board.passable?({4, 10}, {4, 9})
      refute Board.passable?({4, 10}, {5, 10})
      refute Board.passable?({4, 11}, {5, 11})
    end

    test "gallery_green to hall at doorway {8,9}<->{8,10}" do
      assert Board.passable?({8, 9}, {8, 10})
      refute Board.passable?({6, 9}, {6, 10})
    end

    test "gallery_yellow to hall at doorway {8,3}<->{8,4}" do
      assert Board.passable?({8, 3}, {8, 4})
      refute Board.passable?({7, 3}, {7, 4})
    end

    test "other_left to hall at doorway {10,5}<->{9,5}" do
      assert Board.passable?({10, 5}, {9, 5})
      refute Board.passable?({10, 5}, {10, 6})
    end

    test "other_right to hall at doorway {10,8}<->{9,8}" do
      assert Board.passable?({10, 8}, {9, 8})
      refute Board.passable?({10, 9}, {9, 9})
    end

    test "different rooms are not directly passable" do
      refute Board.passable?({1, 4}, {1, 9})
    end

    test "non-adjacent cells are not passable" do
      refute Board.passable?({3, 4}, {3, 6})
    end

    test "out-of-bounds / nil cells are not passable" do
      refute Board.passable?({1, 4}, {1, 3})
      refute Board.passable?({6, 1}, {6, 2})
    end
  end

  describe "neighbors/1" do
    test "hall cell {3,5} connects to adjacent halls and red via doorway" do
      neighbors = Board.neighbors({3, 5})
      assert {3, 4} in neighbors
      assert {3, 6} in neighbors
      # Red gallery via doorway
      assert {2, 5} in neighbors
    end

    test "gallery_red {2,5} has neighbor in hall via doorway" do
      neighbors = Board.neighbors({2, 5})
      assert {3, 5} in neighbors
      # Also within gallery_red
      assert {1, 5} in neighbors
      assert {2, 4} in neighbors
      assert {2, 6} in neighbors
    end

    test "white_room cell {5,6} connects only to adjacent white_room cells" do
      neighbors = Board.neighbors({5, 6})
      assert {4, 6} in neighbors
      assert {5, 5} in neighbors
      assert {5, 7} in neighbors
      assert {6, 6} in neighbors
      refute {5, 4} in neighbors
    end
  end

  describe "exits/0" do
    test "returns 4 exits" do
      assert length(Board.exits()) == 4
    end

    test "each exit has required fields" do
      Enum.each(Board.exits(), fn exit ->
        assert Map.has_key?(exit, :id)
        assert Map.has_key?(exit, :type)
        assert Map.has_key?(exit, :lock_id)
        assert Map.has_key?(exit, :adj_cell)
      end)
    end

    test "exits have correct adjacent cells" do
      exits = Board.exits()
      adj_cells = Enum.map(exits, & &1.adj_cell)
      assert {10, 6} in adj_cells
      assert {10, 7} in adj_cells
      assert {5, 11} in adj_cells
      assert {6, 2} in adj_cells
    end
  end

  describe "exit_adjacent_cell/1" do
    test "returns adj_cell from exit struct" do
      exit = Enum.find(Board.exits(), &(&1.id == :exit_s1))
      assert Board.exit_adjacent_cell(exit) == {10, 6}
    end

    test "east exit adj cell is {5, 11}" do
      exit = Enum.find(Board.exits(), &(&1.id == :exit_e1))
      assert Board.exit_adjacent_cell(exit) == {5, 11}
    end
  end

  describe "exits_for_cell/1" do
    test "returns exit for south exit inside cell {10,6}" do
      exits = Board.exits_for_cell({10, 6})
      assert length(exits) == 1
      assert hd(exits).id == :exit_s1
    end

    test "returns exit for east exit cell {5,11}" do
      exits = Board.exits_for_cell({5, 11})
      assert length(exits) == 1
      assert hd(exits).id == :exit_e1
    end

    test "returns empty list for non-exit-adjacent cell" do
      assert Board.exits_for_cell({4, 5}) == []
      assert Board.exits_for_cell({3, 6}) == []
    end
  end

  describe "exits_for_door_cell/1" do
    test "returns exits for exterior door cells" do
      assert [%{id: :exit_w1, label: "D2"}] = Board.exits_for_door_cell({6, 1})
      assert [%{id: :exit_e1, label: "D1"}] = Board.exits_for_door_cell({5, 12})
      assert [%{id: :exit_s1, label: "D3"}] = Board.exits_for_door_cell({11, 6})
      assert [%{id: :exit_s2, label: "D4"}] = Board.exits_for_door_cell({11, 7})
    end

    test "returns entries for window cells" do
      assert [%{id: :window_1_5, type: :window, label: "W1"}] =
               Board.entries_for_cell({1, 5})

      assert [%{id: :window_8_12, type: :window, label: "W6"}] =
               Board.entries_for_cell({8, 12})
    end

    test "does not treat side-door interior cells as exterior door cells" do
      assert Board.exits_for_door_cell({6, 2}) == []
      assert Board.exits_for_door_cell({5, 11}) == []
    end
  end

  describe "entries/0" do
    test "includes all external doors and windows as lockable entry points" do
      entry_ids = Enum.map(Board.entries(), & &1.id)

      assert length(entry_ids) == 11
      assert :exit_w1 in entry_ids
      assert :exit_e1 in entry_ids
      assert :window_1_5 in entry_ids
      assert :window_8_12 in entry_ids
    end

    test "uses the existing half-locked rule for detective lock placement" do
      assert Board.lock_count() == 5
      assert Board.lock_count() == div(length(Board.entries()), 2)
    end
  end

  describe "los_cells_in_direction/2" do
    test "can see along hall eastward" do
      # From {3,4} looking east through row 3 halls
      cells = Board.los_cells_in_direction({3, 4}, :east)
      assert {3, 5} in cells
      assert {3, 6} in cells
      assert {3, 7} in cells
      assert {3, 8} in cells
      assert {3, 9} in cells
    end

    test "LOS stops at room wall (non-doorway)" do
      # From gallery_red {1,4} looking west — hits nil cell
      cells = Board.los_cells_in_direction({1, 4}, :west)
      assert cells == []
    end

    test "LOS travels through doorway from hall into gallery_red" do
      # From hall {3,5} looking north: crosses doorway into red {2,5}, {1,5}
      cells = Board.los_cells_in_direction({3, 5}, :north)
      assert {2, 5} in cells
      assert {1, 5} in cells
    end

    test "LOS stops at room boundary when no doorway" do
      # From hall {3,7} looking south — hits white room {4,7} via doorway, continues in white
      cells = Board.los_cells_in_direction({3, 7}, :south)
      assert {4, 7} in cells
      assert {5, 7} in cells
    end
  end

  describe "can_see?/2" do
    test "two hall cells in same row can see each other" do
      assert Board.can_see?({3, 4}, {3, 8})
    end

    test "hall cell can see into gallery via doorway" do
      assert Board.can_see?({3, 5}, {1, 5})
    end

    test "cannot see through walls" do
      # gallery_red {1,4} cannot see hall {3,4} directly (not adjacent via doorway in same line)
      # They are in same column but {2,4} is a hall — actually let's check
      # {1,4} south -> {2,4} (red, same room) -> {3,4} is hall (doorway? No doorway at {2,4}<->{3,4})
      refute Board.can_see?({1, 4}, {3, 4})
    end
  end
end
