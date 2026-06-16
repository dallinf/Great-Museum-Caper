defmodule MuseumCaper.Game.PawnColors do
  @colors [:purple, :green, :blue, :white, :red, :yellow]

  def all, do: @colors
  def default, do: hd(@colors)

  def normalize(nil), do: {:ok, nil}
  def normalize(""), do: {:ok, nil}

  def normalize(color) when is_atom(color) do
    if color in @colors, do: {:ok, color}, else: {:error, :invalid_color}
  end

  def normalize(color) when is_binary(color) do
    case color do
      "purple" -> {:ok, :purple}
      "green" -> {:ok, :green}
      "blue" -> {:ok, :blue}
      "white" -> {:ok, :white}
      "red" -> {:ok, :red}
      "yellow" -> {:ok, :yellow}
      _ -> {:error, :invalid_color}
    end
  end

  def to_param(color) when is_atom(color), do: Atom.to_string(color)
  def to_param(color), do: color

  def label(:purple), do: "Purple"
  def label(:green), do: "Green"
  def label(:blue), do: "Blue"
  def label(:white), do: "White"
  def label(:red), do: "Red"
  def label(:yellow), do: "Yellow"

  def next_available(players) do
    taken =
      players
      |> Map.values()
      |> Enum.map(&Map.get(&1, :color))
      |> MapSet.new()

    Enum.find(@colors, &(not MapSet.member?(taken, &1)))
  end
end
