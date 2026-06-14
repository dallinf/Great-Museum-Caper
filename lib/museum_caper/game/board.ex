defmodule MuseumCaper.Game.Board do
  @moduledoc "Static board definition for Museum Caper."

  # Grid: 11 rows × 12 columns. nil = non-playable (outside museum boundary).
  #
  # Parsed from user-provided map:
  #   ...RRRRRR...   row 1
  #   ...RRRRRR...   row 2
  #   PPPHHHHHHBBB   row 3
  #   PPPHWWWWHBBB   row 4
  #   PPPHWWWWHHH.   row 5
  #   .HHHWWWWHGGG   row 6
  #   YYYHWWWWHGGG   row 7
  #   YYYHWWWWHGGG   row 8
  #   YYYHHHHHHGGG   row 9
  #   ...OOHHOO...   row 10
  #   ...OOHHOP...   row 11  (P at col 9 = power room)
  #
  # R=gallery_red  P=gallery_purple  H=hall  B=gallery_blue
  # W=white_room   Y=gallery_yellow  G=gallery_green
  # O=other (two separate rooms: other_left cols 4-5, other_right cols 8-9)
  # P(11,9)=power_room  .=non-playable

  @grid [
    # row 1
    [
      nil,
      nil,
      nil,
      :gallery_red,
      :gallery_red,
      :gallery_red,
      :gallery_red,
      :gallery_red,
      :gallery_red,
      nil,
      nil,
      nil
    ],
    # row 2
    [
      nil,
      nil,
      nil,
      :gallery_red,
      :gallery_red,
      :gallery_red,
      :gallery_red,
      :gallery_red,
      :gallery_red,
      nil,
      nil,
      nil
    ],
    # row 3
    [
      :gallery_purple,
      :gallery_purple,
      :gallery_purple,
      :hall,
      :hall,
      :hall,
      :hall,
      :hall,
      :hall,
      :gallery_blue,
      :gallery_blue,
      :gallery_blue
    ],
    # row 4
    [
      :gallery_purple,
      :gallery_purple,
      :gallery_purple,
      :hall,
      :white_room,
      :white_room,
      :white_room,
      :white_room,
      :hall,
      :gallery_blue,
      :gallery_blue,
      :gallery_blue
    ],
    # row 5
    [
      :gallery_purple,
      :gallery_purple,
      :gallery_purple,
      :hall,
      :white_room,
      :white_room,
      :white_room,
      :white_room,
      :hall,
      :hall,
      :hall,
      nil
    ],
    # row 6
    [
      nil,
      :hall,
      :hall,
      :hall,
      :white_room,
      :white_room,
      :white_room,
      :white_room,
      :hall,
      :gallery_green,
      :gallery_green,
      :gallery_green
    ],
    # row 7
    [
      :gallery_yellow,
      :gallery_yellow,
      :gallery_yellow,
      :hall,
      :white_room,
      :white_room,
      :white_room,
      :white_room,
      :hall,
      :gallery_green,
      :gallery_green,
      :gallery_green
    ],
    # row 8
    [
      :gallery_yellow,
      :gallery_yellow,
      :gallery_yellow,
      :hall,
      :white_room,
      :white_room,
      :white_room,
      :white_room,
      :hall,
      :gallery_green,
      :gallery_green,
      :gallery_green
    ],
    # row 9
    [
      :gallery_yellow,
      :gallery_yellow,
      :gallery_yellow,
      :hall,
      :hall,
      :hall,
      :hall,
      :hall,
      :hall,
      :gallery_green,
      :gallery_green,
      :gallery_green
    ],
    # row 10
    [
      nil,
      nil,
      nil,
      :other_left,
      :other_left,
      :hall,
      :hall,
      :other_right,
      :other_right,
      nil,
      nil,
      nil
    ],
    # row 11
    [
      nil,
      nil,
      nil,
      :other_left,
      :other_left,
      :hall,
      :hall,
      :other_right,
      :power_room,
      nil,
      nil,
      nil
    ]
  ]

  @room_colors %{
    gallery_red: :red,
    gallery_purple: :purple,
    gallery_blue: :blue,
    white_room: :white,
    gallery_yellow: :yellow,
    gallery_green: :green,
    other_left: :orange,
    other_right: :orange,
    power_room: :orange,
    hall: :tan
  }

  @cells @grid
         |> Enum.with_index(1)
         |> Enum.flat_map(fn {row_data, row} ->
           row_data
           |> Enum.with_index(1)
           |> Enum.reject(fn {room_id, _col} -> is_nil(room_id) end)
           |> Enum.map(fn {room_id, col} ->
             type =
               case room_id do
                 :hall -> :corridor
                 :power_room -> :power_room
                 _ -> :room
               end

             color = Map.fetch!(@room_colors, room_id)
             {{row, col}, %{type: type, room_id: room_id, color: color, occupiable: true}}
           end)
         end)
         |> Map.new()

  # Interior doorways: adjacent cell pairs where zone-crossing is allowed.
  # User-specified positions (1-based row, col):
  #   (2,5)  (2,8)  — Red south to Hall
  #   (4,6)  (4,7)  — White north to Hall
  #   (4,10)         — Blue west to Hall
  #   (5,3)          — Purple east to Hall
  #   (8,10)         — Green west to Hall
  #   (8,3)          — Yellow east to Hall
  #   (8,6)  (8,7)  — White south to Hall
  #   (10,5)         — OtherLeft north to Hall
  #   (10,8)         — OtherRight to Hall
  #
  # White's west and east doorways are unchanged from the earlier board pass.
  @doorways MapSet.new([
              # Red ↔ Hall (south)
              {{2, 5}, {3, 5}},
              {{2, 8}, {3, 8}},
              # White ↔ Hall (north)
              {{4, 6}, {3, 6}},
              {{4, 7}, {3, 7}},
              # Blue ↔ Hall (west)
              {{4, 10}, {4, 9}},
              # Purple ↔ Hall (east)
              {{5, 3}, {5, 4}},
              # Green ↔ Hall (west)
              {{8, 9}, {8, 10}},
              # Yellow ↔ Hall (east)
              {{8, 3}, {8, 4}},
              # White ↔ Hall (west)
              {{7, 5}, {7, 4}},
              # White ↔ Hall (east)
              {{6, 8}, {6, 9}},
              # White ↔ Hall (south)
              {{8, 6}, {9, 6}},
              {{8, 7}, {9, 7}},
              # OtherLeft ↔ Hall (north)
              {{10, 5}, {9, 5}},
              # OtherRight ↔ Hall (north)
              {{10, 8}, {9, 8}}
            ])

  @window_cell_positions [
    {4, 1},
    {8, 1},
    {9, 2},
    {1, 5},
    {1, 8},
    {3, 11},
    {8, 12}
  ]

  @window_cells MapSet.new(@window_cell_positions)

  @window_labels @window_cell_positions
                 |> Enum.sort()
                 |> Enum.with_index(1)
                 |> Map.new(fn {pos, index} -> {pos, "W#{index}"} end)

  # Exterior exits. door_cell is the visible exterior door space on the board.
  # adj_cell is the interior cell where the thief stands after entering and from which
  # the thief can attempt escape.
  # User-specified (1-based):
  #   (11,6) and (11,7) — bottom exits; interior adj cells are (10,6) and (10,7)
  #   (5,12)             — right wall exit; interior adj cell is (5,11)
  #   (6,1)              — left wall exit; interior adj cell is (6,2)
  @external_door_cells MapSet.new([
                         {6, 1},
                         {5, 12},
                         {11, 6},
                         {11, 7}
                       ])

  @exits [
    %{
      id: :exit_s1,
      type: :door,
      label: "D3",
      door_cell: {11, 6},
      adj_cell: {10, 6},
      lock_id: :lock_1
    },
    %{
      id: :exit_s2,
      type: :door,
      label: "D4",
      door_cell: {11, 7},
      adj_cell: {10, 7},
      lock_id: :lock_2
    },
    %{
      id: :exit_e1,
      type: :door,
      label: "D1",
      door_cell: {5, 12},
      adj_cell: {5, 11},
      lock_id: :lock_3
    },
    %{
      id: :exit_w1,
      type: :door,
      label: "D2",
      door_cell: {6, 1},
      adj_cell: {6, 2},
      lock_id: :lock_4
    }
  ]

  @window_entries Enum.map(@window_cell_positions, fn {row, col} = pos ->
                    %{
                      id: :"window_#{row}_#{col}",
                      type: :window,
                      label: @window_labels[pos],
                      door_cell: pos,
                      adj_cell: pos
                    }
                  end)

  @entries @exits ++ @window_entries

  @doorway_room_cells @doorways
                      |> Enum.flat_map(fn {pos_a, pos_b} ->
                        cell_a = Map.get(@cells, pos_a)
                        cell_b = Map.get(@cells, pos_b)

                        cond do
                          cell_a && cell_a.type == :room && cell_b && cell_b.type == :corridor ->
                            [pos_a]

                          cell_b && cell_b.type == :room && cell_a && cell_a.type == :corridor ->
                            [pos_b]

                          true ->
                            []
                        end
                      end)
                      |> MapSet.new()

  @external_door_inside_cells @exits
                              |> Enum.map(& &1.adj_cell)
                              |> MapSet.new()

  @blocked_painting_cells MapSet.union(@window_cells, @doorway_room_cells)
                          |> MapSet.union(@external_door_inside_cells)

  @optional_artwork_room_ids MapSet.new([:other_left])
  @no_artwork_room_ids MapSet.new([:other_right])

  @required_painting_room_ids @cells
                              |> Map.values()
                              |> Enum.filter(fn cell ->
                                cell.type == :room and cell.room_id != :power_room and
                                  not MapSet.member?(@optional_artwork_room_ids, cell.room_id) and
                                  not MapSet.member?(@no_artwork_room_ids, cell.room_id)
                              end)
                              |> Enum.map(& &1.room_id)
                              |> MapSet.new()

  def cell({r, c}) when r in 1..11 and c in 1..12, do: Map.get(@cells, {r, c})
  def cell(_), do: nil

  def exits, do: @exits

  def entries, do: @entries

  def lock_count, do: div(length(@entries), 2)

  def entry_by_id(entry_id), do: Enum.find(@entries, &(&1.id == entry_id))

  def exit_adjacent_cell(%{adj_cell: pos}), do: pos

  def exit_door_cell(%{door_cell: pos}), do: pos

  def window_cells, do: MapSet.to_list(@window_cells)

  def window_cell?(pos), do: MapSet.member?(@window_cells, pos)

  def external_door_cells, do: MapSet.to_list(@external_door_cells)

  def external_door_cell?(pos), do: MapSet.member?(@external_door_cells, pos)

  def exit_cell?(pos), do: MapSet.member?(@external_door_inside_cells, pos)

  def doorway_room_cells, do: MapSet.to_list(@doorway_room_cells)

  def doorway_room_cell?(pos), do: MapSet.member?(@doorway_room_cells, pos)

  def required_painting_room_ids, do: @required_painting_room_ids

  def painting_placeable_cell?(pos) do
    case cell(pos) do
      %{type: :room, room_id: room_id} ->
        not MapSet.member?(@blocked_painting_cells, pos) and
          not MapSet.member?(@no_artwork_room_ids, room_id)

      _ ->
        false
    end
  end

  def camera_placeable_cell?(pos) do
    case cell(pos) do
      %{occupiable: true, type: type} ->
        type != :power_room and not external_door_cell?(pos)

      _ ->
        false
    end
  end

  def detective_placeable_cell?(pos) do
    case cell(pos) do
      %{occupiable: true} -> not external_door_cell?(pos)
      _ -> false
    end
  end

  def exits_for_cell(pos) do
    Enum.filter(@exits, fn exit -> exit.adj_cell == pos end)
  end

  def exits_for_door_cell(pos) do
    Enum.filter(@exits, fn exit -> exit.door_cell == pos end)
  end

  def entries_for_cell(pos) do
    Enum.filter(@entries, fn entry -> entry.door_cell == pos end)
  end

  def passable?(pos_a, pos_b) do
    with %{} = cell_a <- cell(pos_a),
         %{} = cell_b <- cell(pos_b),
         true <- adjacent?(pos_a, pos_b) do
      movement_allowed?(cell_a, pos_a, cell_b, pos_b)
    else
      _ -> false
    end
  end

  def neighbors(pos) do
    {r, c} = pos

    [{r - 1, c}, {r + 1, c}, {r, c - 1}, {r, c + 1}]
    |> Enum.filter(&passable?(pos, &1))
  end

  def los_cells_in_direction(pos, direction) do
    Stream.unfold(pos, fn current ->
      next = step(current, direction)
      if passable?(current, next), do: {next, next}, else: nil
    end)
    |> Enum.to_list()
  end

  def can_see?(from_pos, target_pos) do
    [:north, :south, :east, :west]
    |> Enum.any?(fn dir ->
      target_pos in los_cells_in_direction(from_pos, dir)
    end)
  end

  def all_cells, do: @cells

  defp adjacent?({r1, c1}, {r2, c2}) do
    (abs(r1 - r2) == 1 and c1 == c2) or (r1 == r2 and abs(c1 - c2) == 1)
  end

  defp movement_allowed?(cell_a, pos_a, cell_b, pos_b) do
    a_zone = zone(cell_a)
    b_zone = zone(cell_b)

    cond do
      # Hall cells freely interconnect
      a_zone == :corridor and b_zone == :corridor -> true
      # Same zone: same gallery room, or other_right+power_room, or other_left
      a_zone == b_zone -> true
      # Any other zone boundary requires an explicit doorway
      true -> doorway?({pos_a, pos_b})
    end
  end

  # Zones for movement grouping:
  # :corridor         — Hall cells, freely interconnected
  # :other_right_zone — other_right + power_room share a zone (freely passable between them)
  # :other_left_zone  — other_left cells
  # {:room, id}       — each gallery is its own zone
  defp zone(%{type: :corridor}), do: :corridor
  defp zone(%{type: :power_room}), do: :other_right_zone
  defp zone(%{room_id: :other_right}), do: :other_right_zone
  defp zone(%{room_id: :other_left}), do: :other_left_zone
  defp zone(%{room_id: r}), do: {:room, r}

  defp doorway?({a, b}) do
    MapSet.member?(@doorways, {a, b}) or MapSet.member?(@doorways, {b, a})
  end

  defp step({r, c}, :north), do: {r - 1, c}
  defp step({r, c}, :south), do: {r + 1, c}
  defp step({r, c}, :east), do: {r, c + 1}
  defp step({r, c}, :west), do: {r, c - 1}
end
