defmodule MuseumCaper.Lobby.Server do
  use GenServer

  @table :lobby_rooms

  # --- Public API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list_rooms do
    GenServer.call(__MODULE__, :list_rooms)
  end

  def create_room(name, creator_name) do
    GenServer.call(__MODULE__, {:create_room, name, creator_name})
  end

  def join_room(name, game_id, player_name) do
    GenServer.call(__MODULE__, {:join_room, name, game_id, player_name})
  end

  def close_room(name) do
    GenServer.call(__MODULE__, {:close_room, name})
  end

  def close_game(game_id) do
    GenServer.call(__MODULE__, {:close_game, game_id})
  end

  def sync_game(game_id, game_state) do
    GenServer.call(__MODULE__, {:sync_game, game_id, game_state})
  end

  # --- Callbacks ---

  @impl true
  def init(_) do
    # Use :ets.whereis to check if table already exists (e.g., from a crash restart)
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public])
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call(:list_rooms, _from, state) do
    {:reply, rooms_from_table(), state}
  end

  @impl true
  def handle_call({:create_room, name, creator_name}, _from, state) do
    if :ets.member(@table, name) do
      {:reply, {:error, :name_taken}, state}
    else
      game_id = "game-#{System.unique_integer([:positive])}"

      room = %{
        name: name,
        game_id: game_id,
        creator: creator_name,
        created_at: DateTime.utc_now(),
        created_order: System.unique_integer([:monotonic, :positive]),
        player_count: 1,
        players: %{},
        phase: :lobby
      }

      :ets.insert(@table, {name, room})

      DynamicSupervisor.start_child(
        MuseumCaper.GameSupervisor,
        {MuseumCaper.Game.Server, [game_id: game_id, players: %{}]}
      )

      broadcast_lobby()
      {:reply, {:ok, game_id}, state}
    end
  end

  @impl true
  def handle_call({:join_room, name, game_id, _player_name}, _from, state) do
    case :ets.lookup(@table, name) do
      [{^name, %{game_id: ^game_id, phase: :lobby} = room}] ->
        updated = %{room | player_count: room.player_count + 1}
        :ets.insert(@table, {name, updated})
        broadcast_lobby()
        {:reply, :ok, state}

      [{^name, %{game_id: ^game_id}}] ->
        {:reply, {:error, :game_started}, state}

      [{^name, _room}] ->
        {:reply, {:error, :not_found}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:sync_game, game_id, game_state}, _from, state) do
    case find_room_by_game_id(game_id) do
      {name, _room} when game_state.phase == :game_over ->
        :ets.delete(@table, name)
        broadcast_lobby()
        {:reply, :ok, state}

      {name, room} ->
        updated =
          Map.merge(room, %{
            player_count: map_size(game_state.players),
            players: game_state.players,
            phase: game_state.phase
          })

        :ets.insert(@table, {name, updated})
        broadcast_lobby()
        {:reply, :ok, state}

      nil ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:close_room, name}, _from, state) do
    :ets.delete(@table, name)
    broadcast_lobby()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:close_game, game_id}, _from, state) do
    case find_room_by_game_id(game_id) do
      {name, _room} ->
        :ets.delete(@table, name)
        broadcast_lobby()

      nil ->
        :ok
    end

    {:reply, :ok, state}
  end

  defp broadcast_lobby do
    Phoenix.PubSub.broadcast(MuseumCaper.PubSub, "lobby", {:lobby_updated, rooms_from_table()})
  end

  defp find_room_by_game_id(game_id) do
    Enum.find(:ets.tab2list(@table), fn {_name, room} -> room.game_id == game_id end)
  end

  defp rooms_from_table do
    @table
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(&Map.get(&1, :created_order, 0), :desc)
  end
end
