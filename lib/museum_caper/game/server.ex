defmodule MuseumCaper.Game.Server do
  use GenServer
  alias MuseumCaper.Game.{PawnColors, Rules, State}
  alias Phoenix.PubSub

  # --- Public API ---

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    players = Keyword.fetch!(opts, :players)

    GenServer.start_link(__MODULE__, {game_id, players},
      name: {:via, Registry, {MuseumCaper.GameRegistry, game_id}}
    )
  end

  def get_state(server), do: GenServer.call(server, :get_state)

  def add_player(server, player_id, name, color \\ nil),
    do: GenServer.call(server, {:add_player, player_id, name, color})

  def start_game(server, player_id, opts \\ []),
    do: GenServer.call(server, {:start_game, player_id, opts})

  def toggle_lock(server, entry_id), do: GenServer.call(server, {:toggle_lock, entry_id})

  def place_painting(server, pos), do: GenServer.call(server, {:place_painting, pos})
  def remove_painting(server, pos), do: GenServer.call(server, {:remove_painting, pos})

  def place_camera(server, camera_id, pos),
    do: GenServer.call(server, {:place_camera, camera_id, pos})

  def remove_camera_at(server, pos), do: GenServer.call(server, {:remove_camera_at, pos})

  def place_detective_pawn(server, detective_id, pos),
    do: GenServer.call(server, {:place_detective_pawn, detective_id, pos})

  def enter_museum(server, exit_id), do: GenServer.call(server, {:enter_museum, exit_id})
  def move_thief(server, destination), do: GenServer.call(server, {:move_thief, destination})

  def move_detective(server, detective_id, destination),
    do: GenServer.call(server, {:move_detective, detective_id, destination})

  def use_eye_action(server, detective_id),
    do: GenServer.call(server, {:use_eye_action, detective_id})

  def use_eye_on_camera(server, detective_id, camera_id),
    do: GenServer.call(server, {:use_eye_on_camera, detective_id, camera_id})

  def use_camera_scan(server), do: GenServer.call(server, :use_camera_scan)

  def use_motion_detector(server, opts \\ []),
    do: GenServer.call(server, {:use_motion_detector, opts})

  def decide_motion_detector(server, player_id, decision),
    do: GenServer.call(server, {:decide_motion_detector, player_id, decision})

  def try_escape(server, exit_id), do: GenServer.call(server, {:try_escape, exit_id})
  def end_turn(server), do: GenServer.call(server, :end_turn)

  # --- GenServer Callbacks ---

  @impl true
  def init({game_id, players}) do
    state = if map_size(players) > 0, do: State.new_game(players), else: %State{phase: :lobby}
    {:ok, %{game_id: game_id, game_state: state}}
  end

  @impl true
  def handle_call(:get_state, _from, server_state) do
    {:reply, server_state.game_state, server_state}
  end

  @impl true
  def handle_call({:add_player, player_id, name, color}, _from, server_state) do
    case add_lobby_player(server_state.game_state, player_id, name, color) do
      {:ok, new_game_state} ->
        server_state = %{server_state | game_state: new_game_state}
        broadcast(server_state)
        {:reply, :ok, server_state}

      error ->
        {:reply, error, server_state}
    end
  end

  @impl true
  def handle_call({:start_game, player_id, opts}, _from, server_state) do
    case start_lobby_game(server_state.game_state, player_id, opts) do
      {:ok, new_game_state} ->
        server_state = %{server_state | game_state: new_game_state}
        broadcast(server_state)
        {:reply, {:ok, new_game_state}, server_state}

      error ->
        {:reply, error, server_state}
    end
  end

  @impl true
  def handle_call({:toggle_lock, entry_id}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.toggle_lock(gs, entry_id) end)
  end

  @impl true
  def handle_call({:place_painting, pos}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.place_painting(gs, pos) end)
  end

  @impl true
  def handle_call({:remove_painting, pos}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.remove_painting(gs, pos) end)
  end

  @impl true
  def handle_call({:place_camera, camera_id, pos}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.place_camera(gs, camera_id, pos) end)
  end

  @impl true
  def handle_call({:remove_camera_at, pos}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.remove_camera_at(gs, pos) end)
  end

  @impl true
  def handle_call({:place_detective_pawn, detective_id, pos}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.place_detective_pawn(gs, detective_id, pos) end)
  end

  @impl true
  def handle_call({:enter_museum, exit_id}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.enter_museum(gs, exit_id) end)
  end

  @impl true
  def handle_call({:move_thief, destination}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.move_thief(gs, destination) end)
  end

  @impl true
  def handle_call({:move_detective, detective_id, destination}, _from, server_state) do
    handle_mutation(server_state, fn gs -> Rules.move_detective(gs, detective_id, destination) end)
  end

  @impl true
  def handle_call({:use_eye_action, detective_id}, _from, server_state) do
    handle_look(server_state, fn gs -> Rules.use_eye_action(gs, detective_id) end)
  end

  @impl true
  def handle_call({:use_eye_on_camera, detective_id, camera_id}, _from, server_state) do
    handle_look(server_state, fn gs -> Rules.use_eye_on_camera(gs, detective_id, camera_id) end)
  end

  @impl true
  def handle_call(:use_camera_scan, _from, server_state) do
    case Rules.use_camera_scan(server_state.game_state) do
      {:ok, disabled_ids, result, new_game_state} ->
        new_game_state = maybe_end_turn_after_look(new_game_state)
        server_state = %{server_state | game_state: new_game_state}
        broadcast(server_state)
        {:reply, {:ok, disabled_ids, result}, server_state}

      {:ok, :power_off, new_game_state} ->
        new_game_state = maybe_end_turn_after_look(new_game_state)
        server_state = %{server_state | game_state: new_game_state}
        broadcast(server_state)
        {:reply, {:ok, :power_off}, server_state}
    end
  end

  @impl true
  def handle_call({:use_motion_detector, opts}, _from, server_state) do
    handle_look(server_state, fn gs -> Rules.use_motion_detector(gs, opts) end)
  end

  @impl true
  def handle_call({:decide_motion_detector, player_id, decision}, _from, server_state) do
    handle_look(server_state, fn gs -> Rules.decide_motion_detector(gs, player_id, decision) end)
  end

  @impl true
  def handle_call({:try_escape, exit_id}, _from, server_state) do
    case Rules.try_escape(server_state.game_state, exit_id) do
      {:ok, result, new_game_state} ->
        server_state = %{server_state | game_state: new_game_state}
        broadcast(server_state)
        {:reply, {:ok, result}, server_state}

      error ->
        {:reply, error, server_state}
    end
  end

  @impl true
  def handle_call(:end_turn, _from, server_state) do
    case Rules.end_turn(server_state.game_state) do
      {:ok, new_game_state} ->
        server_state = %{server_state | game_state: new_game_state}
        broadcast(server_state)
        {:reply, {:ok, new_game_state}, server_state}

      error ->
        {:reply, error, server_state}
    end
  end

  # --- Helpers ---

  defp handle_mutation(server_state, fun) do
    case fun.(server_state.game_state) do
      {:ok, new_game_state} ->
        server_state = %{server_state | game_state: new_game_state}
        broadcast(server_state)
        {:reply, {:ok, new_game_state}, server_state}

      error ->
        {:reply, error, server_state}
    end
  end

  defp handle_look(server_state, fun) do
    case fun.(server_state.game_state) do
      {:ok, result, new_game_state} ->
        new_game_state = maybe_end_turn_after_look(new_game_state)
        server_state = %{server_state | game_state: new_game_state}
        broadcast(server_state)
        {:reply, {:ok, result}, server_state}

      error ->
        {:reply, error, server_state}
    end
  end

  defp maybe_end_turn_after_look(game_state) do
    if detective_finished_look_after_moving?(game_state) do
      case Rules.end_turn(game_state) do
        {:ok, new_game_state} -> new_game_state
        {:error, _reason} -> game_state
      end
    else
      game_state
    end
  end

  defp detective_finished_look_after_moving?(game_state) do
    case Map.get(game_state.players, game_state.current_turn) do
      %{role: :detective} ->
        :look not in game_state.turn_actions_remaining and game_state.movement_path != [] and
          game_state.movement_spent > 0

      _player ->
        false
    end
  end

  defp broadcast(%{game_id: game_id, game_state: game_state}) do
    MuseumCaper.Lobby.Server.sync_game(game_id, game_state)
    PubSub.broadcast(MuseumCaper.PubSub, "game:#{game_id}", {:state_changed, game_state})
  end

  defp add_lobby_player(%State{phase: :lobby} = game_state, player_id, name, color) do
    already_joined? = Map.has_key?(game_state.players, player_id)

    cond do
      not already_joined? and map_size(game_state.players) >= 4 ->
        {:error, :room_full}

      already_joined? ->
        with {:ok, color} <- resolve_player_color(game_state, player_id, color) do
          player = %{game_state.players[player_id] | name: name, color: color}
          {:ok, %{game_state | players: Map.put(game_state.players, player_id, player)}}
        end

      true ->
        with {:ok, color} <- resolve_player_color(game_state, player_id, color) do
          player = %{
            name: name,
            role: :unassigned,
            color: color
          }

          {:ok,
           %{
             game_state
             | players: Map.put(game_state.players, player_id, player),
               host_player_id: game_state.host_player_id || player_id,
               turn_order: game_state.turn_order ++ [player_id]
           }}
        end
    end
  end

  defp add_lobby_player(%State{} = game_state, player_id, name, _color) do
    case Map.get(game_state.players, player_id) do
      nil ->
        {:error, :game_started}

      player ->
        {:ok,
         %{game_state | players: Map.put(game_state.players, player_id, %{player | name: name})}}
    end
  end

  defp start_lobby_game(
         %State{phase: :lobby, turn_order: turn_order} = game_state,
         player_id,
         opts
       ) do
    cond do
      length(turn_order) < 2 ->
        {:error, :not_enough_players}

      player_id != hd(turn_order) ->
        {:error, :not_host}

      true ->
        shuffle = Keyword.get(opts, :shuffle, &Enum.shuffle/1)
        shuffled_order = shuffle.(turn_order)

        players =
          shuffled_order
          |> Enum.with_index()
          |> Map.new(fn {assigned_player_id, index} ->
            role = if index == 0, do: :thief, else: :detective
            player = game_state.players[assigned_player_id]
            color = if role == :thief, do: :grey, else: player.color
            {assigned_player_id, %{player | role: role, color: color}}
          end)

        {:ok,
         State.new_game(players, shuffled_order, game_state.host_player_id || hd(turn_order))}
    end
  end

  defp start_lobby_game(_game_state, _player_id, _opts), do: {:error, :invalid_phase}

  defp resolve_player_color(game_state, player_id, requested_color) do
    with {:ok, color} <- PawnColors.normalize(requested_color) do
      color = color || current_or_next_color(game_state, player_id)

      cond do
        color == nil -> {:error, :room_full}
        color_available?(game_state, player_id, color) -> {:ok, color}
        true -> {:error, :color_taken}
      end
    end
  end

  defp current_or_next_color(game_state, player_id) do
    case Map.get(game_state.players, player_id) do
      %{color: color} -> color
      _player -> PawnColors.next_available(game_state.players)
    end
  end

  defp color_available?(game_state, player_id, color) do
    Enum.all?(game_state.players, fn {id, player} -> id == player_id or player.color != color end)
  end
end
