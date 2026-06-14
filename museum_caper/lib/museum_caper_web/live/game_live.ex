defmodule MuseumCaperWeb.GameLive do
  use MuseumCaperWeb, :live_view
  alias MuseumCaper.Lobby.Server, as: LobbyServer
  alias MuseumCaper.Game.{Board, Rules, Server}

  @impl true
  def mount(%{"game_id" => game_id} = params, _session, socket) do
    case Registry.lookup(MuseumCaper.GameRegistry, game_id) do
      [] ->
        {:ok, push_navigate(socket, to: "/")}

      [{_pid, _}] ->
        player_name = params |> Map.get("player_name", "") |> String.trim()
        server = {:via, Registry, {MuseumCaper.GameRegistry, game_id}}
        player_id = player_id_for(player_name, socket.id)

        socket =
          socket
          |> assign(
            game_id: game_id,
            server: server,
            player_id: player_id,
            player_name: player_name,
            notification: nil,
            pending_escape_entry: nil,
            join_form: to_form(%{"player_name" => player_name}, as: :player)
          )
          |> maybe_join_game(player_name)

        game_state = Server.get_state(server)

        {:ok, assign(socket, game_state: game_state)}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:state_changed, game_state}, socket) do
    {:noreply, assign(socket, game_state: game_state)}
  end

  @impl true
  def handle_event("join_game", %{"player" => %{"player_name" => player_name}}, socket) do
    player_name = String.trim(player_name)

    if player_name == "" do
      {:noreply, put_notice(socket, "Enter a name to join this room.")}
    else
      player_id = player_id_for(player_name, socket.id)

      socket =
        socket
        |> assign(
          player_id: player_id,
          player_name: player_name,
          join_form: to_form(%{"player_name" => player_name}, as: :player)
        )
        |> join_current_player(player_name)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    case Server.start_game(socket.assigns.server, socket.assigns.player_id) do
      {:ok, _state} ->
        {:noreply, refresh_state(socket, "Game started. Detectives place the museum setup.")}

      {:error, :not_enough_players} ->
        {:noreply, put_notice(socket, "Invite at least two players before starting.")}

      {:error, :invalid_phase} ->
        {:noreply, put_notice(socket, "This game has already started.")}

      {:error, :not_host} ->
        {:noreply, put_notice(socket, "Only the host can start the game.")}
    end
  end

  @impl true
  def handle_event("return_to_lobby", _params, socket) do
    state = socket.assigns.game_state

    if host_leaving_open_game?(state, socket.assigns.player_id) do
      LobbyServer.close_game(socket.assigns.game_id)
    end

    {:noreply, push_navigate(socket, to: "/")}
  end

  @impl true
  def handle_event("board_click", %{"row" => row, "col" => col}, socket) do
    pos = {String.to_integer(row), String.to_integer(col)}

    case socket.assigns.game_state.phase do
      :setup -> handle_setup_click(socket, pos)
      :thief_entry -> handle_entry_click(socket, pos)
      :playing -> handle_playing_board_click(socket, pos)
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("enter_museum", %{"exit_id" => exit_id}, socket) do
    with {:ok, entry_id} <- parse_entry_id(exit_id),
         {:ok, _state} <- Server.enter_museum(socket.assigns.server, entry_id) do
      {:noreply, refresh_state(socket, "The thief has entered the museum.")}
    else
      _ -> {:noreply, put_notice(socket, "Choose a valid entry point.")}
    end
  end

  @impl true
  def handle_event("try_escape", %{"exit_id" => exit_id}, socket) do
    with {:ok, entry_id} <- parse_entry_id(exit_id),
         {:ok, result} <- Server.try_escape(socket.assigns.server, entry_id) do
      message =
        case result do
          :escaped -> "The thief escaped. Game over."
          :locked -> locked_escape_message(entry_id)
        end

      socket = assign(socket, :pending_escape_entry, nil)

      {:noreply, refresh_state(socket, message)}
    else
      _ -> {:noreply, put_notice(socket, "The thief must be next to that exit.")}
    end
  end

  @impl true
  def handle_event("confirm_escape", _params, socket) do
    case socket.assigns.pending_escape_entry do
      nil -> {:noreply, put_notice(socket, "Choose a door or window first.")}
      entry_id -> handle_escape(socket, entry_id)
    end
  end

  @impl true
  def handle_event("cancel_escape", _params, socket) do
    {:noreply, assign(socket, pending_escape_entry: nil, notification: nil)}
  end

  @impl true
  def handle_event("look_pawn", _params, socket) do
    case Server.use_eye_action(socket.assigns.server, socket.assigns.player_id) do
      {:ok, :chase_triggered} ->
        {:noreply, refresh_state(socket, "The detectives spotted the thief.")}

      {:ok, :no_sighting} ->
        {:noreply, refresh_state(socket, "No thief in that line of sight.")}
    end
  end

  @impl true
  def handle_event("look_camera", %{"camera_id" => camera_id}, socket) do
    case Server.use_eye_on_camera(
           socket.assigns.server,
           socket.assigns.player_id,
           String.to_integer(camera_id)
         ) do
      {:ok, {:sighting, camera_id}} ->
        {:noreply, refresh_state(socket, camera_sighting_message(camera_id))}

      {:ok, :camera_disabled} ->
        {:noreply, refresh_state(socket, "That camera was disabled.")}

      {:ok, :power_off} ->
        {:noreply, refresh_state(socket, "The power is off, so cameras cannot see.")}

      {:ok, :no_sighting} ->
        {:noreply, refresh_state(socket, "No thief in that camera line.")}
    end
  end

  @impl true
  def handle_event("camera_scan", _params, socket) do
    case Server.use_camera_scan(socket.assigns.server) do
      {:ok, disabled_ids, {:sighting, sighting_camera_ids}} ->
        {:noreply, refresh_state(socket, camera_scan_message(disabled_ids, sighting_camera_ids))}

      {:ok, disabled_ids, :no_sighting} ->
        {:noreply,
         refresh_state(
           socket,
           "Camera scan found #{length(disabled_ids)} disabled cameras. No sighting."
         )}

      {:ok, :power_off} ->
        {:noreply, refresh_state(socket, "The power is off, so camera scan cannot see.")}
    end
  end

  @impl true
  def handle_event("motion_detector", _params, socket) do
    case Server.use_motion_detector(socket.assigns.server) do
      {:ok, :power_off} ->
        {:noreply, refresh_state(socket, "The power is off, so motion detector cannot read.")}

      {:ok, {:color, color}} ->
        {:noreply, refresh_state(socket, "Motion detector reads #{color}.")}

      {:error, :motion_decision_pending} ->
        {:noreply, put_notice(socket, "Waiting for the thief to choose the motion reading.")}
    end
  end

  @impl true
  def handle_event("motion_detector_decision", %{"decision" => decision}, socket) do
    decision =
      case decision do
        "allow" -> :allow
        "cut" -> :cut
        _ -> :invalid
      end

    case Server.decide_motion_detector(socket.assigns.server, socket.assigns.player_id, decision) do
      {:ok, :allowed} ->
        {:noreply, refresh_state(socket, "The thief allowed the motion detector reading.")}

      {:ok, :snipped} ->
        {:noreply, refresh_state(socket, "The thief snipped a motion detector reading.")}

      {:error, :not_thief} ->
        {:noreply, put_notice(socket, "Only the thief can choose the motion reading.")}

      {:error, :invalid_action} ->
        {:noreply, put_notice(socket, "There is no motion reading to choose right now.")}
    end
  end

  @impl true
  def handle_event("end_turn", _params, socket) do
    case Server.end_turn(socket.assigns.server) do
      {:ok, _state} ->
        socket = assign(socket, :pending_escape_entry, nil)
        {:noreply, refresh_state(socket, "Turn advanced.")}

      {:error, :movement_required} ->
        {:noreply, put_notice(socket, "Move before ending your turn.")}

      _ ->
        {:noreply, put_notice(socket, "Could not advance the turn.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} back_to_lobby_event="return_to_lobby">
      <div
        id="game-shell"
        class="min-h-[calc(100dvh-4rem)] overflow-x-hidden overflow-y-auto bg-stone-950 text-stone-100 lg:h-[calc(100dvh-4rem)] lg:overflow-hidden"
      >
        <div
          id="game-layout"
          class="grid min-h-0 gap-4 overflow-visible p-3 lg:h-full lg:grid-cols-[19rem_minmax(0,1fr)] lg:overflow-hidden lg:p-5"
        >
          <aside
            id="game-sidebar"
            class="min-h-0 space-y-3 overflow-y-auto rounded-lg border border-stone-700 bg-stone-900/95 p-4 shadow-2xl shadow-black/30"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.22em] text-amber-300">
                  Museum Caper
                </p>
                <h1 class="mt-1 text-2xl font-black tracking-normal text-stone-50">Night Shift</h1>
              </div>
              <span class="rounded-md border border-stone-700 px-2 py-1 text-xs font-semibold capitalize text-stone-300">
                {@game_state.phase}
              </span>
            </div>

            <%= if needs_join?(@game_state, @player_id) do %>
              <div id="join-panel" class="rounded-lg border border-amber-300/30 bg-amber-200/10 p-3">
                <.form for={@join_form} id="join-game-form" phx-submit="join_game" class="space-y-3">
                  <.input field={@join_form[:player_name]} type="text" label="Your name" />
                  <button
                    id="join-game-button"
                    type="submit"
                    class="w-full rounded-md bg-amber-300 px-3 py-2 text-sm font-bold text-stone-950 transition hover:bg-amber-200"
                  >
                    Join room
                  </button>
                </.form>
              </div>
            <% end %>

            <%= if join_closed?(@game_state, @player_id) do %>
              <div
                id="join-closed-panel"
                class="rounded-lg border border-stone-700 bg-stone-800 p-3 text-sm text-stone-300"
              >
                This game is already in progress.
              </div>
            <% end %>

            <section id="player-panel" class="space-y-2">
              <h2 class="text-sm font-bold uppercase tracking-[0.18em] text-stone-400">Players</h2>
              <%= if map_size(@game_state.players) == 0 do %>
                <p class="rounded-md border border-dashed border-stone-700 p-3 text-sm text-stone-500">
                  Waiting for players.
                </p>
              <% else %>
                <ul id="player-list" class="space-y-2">
                  <%= for player_id <- player_order(@game_state) do %>
                    <% player = @game_state.players[player_id] %>
                    <li class={[
                      "flex items-center justify-between gap-3 rounded-md border px-3 py-2 text-sm",
                      if(player_id == @player_id,
                        do: "border-amber-300 bg-amber-300/10",
                        else: "border-stone-700 bg-stone-800/80"
                      )
                    ]}>
                      <span class="min-w-0 truncate font-semibold">{player.name}</span>
                      <span class="shrink-0 rounded bg-stone-950/80 px-2 py-1 text-[0.68rem] font-bold uppercase tracking-wide text-stone-300">
                        {player.role}
                      </span>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </section>

            <%= if @notification do %>
              <div
                id="game-notification"
                class="rounded-lg border border-amber-300/50 bg-amber-300/15 p-3 text-sm text-amber-100"
              >
                {@notification}
              </div>
            <% end %>

            <%= if detective_result_visible?(@game_state, @player_id) do %>
              <div
                id="detective-result-panel"
                class="rounded-lg border border-sky-300/50 bg-sky-300/15 p-3 text-sm text-sky-100"
              >
                {detective_result_message(@game_state.detective_result)}
              </div>
            <% end %>

            <%= if power_status_visible?(@game_state, @player_id) do %>
              <div
                id="power-status"
                class="rounded-lg border border-red-300/50 bg-red-400/15 p-3 text-sm font-semibold text-red-100"
              >
                Power off
              </div>
            <% end %>

            <%= if @game_state.game_log != [] do %>
              <section
                id="game-log"
                class="space-y-2 rounded-lg border border-stone-700 bg-stone-800 p-3"
              >
                <h2 class="text-sm font-black uppercase tracking-[0.18em] text-stone-200">Log</h2>
                <ul class="space-y-1 text-sm text-stone-300">
                  <%= for {entry, index} <- Enum.with_index(@game_state.game_log) do %>
                    <li id={"game-log-entry-#{index}"}>{entry}</li>
                  <% end %>
                </ul>
              </section>
            <% end %>

            <%= case @game_state.phase do %>
              <% :lobby -> %>
                <div
                  id="waiting-room"
                  class="space-y-3 rounded-lg border border-stone-700 bg-stone-800 p-3"
                >
                  <p class="text-sm text-stone-300">
                    Open this room in another browser tab or private window, join as a second player, then start.
                  </p>
                  <%= if host?(@game_state, @player_id) do %>
                    <button
                      id="start-game-button"
                      type="button"
                      phx-click="start_game"
                      class="inline-flex w-full items-center justify-center gap-2 rounded-md bg-emerald-400 px-3 py-2 text-sm font-black text-stone-950 transition hover:bg-emerald-300"
                    >
                      <.icon name="hero-play-solid" class="size-4" /> Start game
                    </button>
                  <% else %>
                    <p
                      id="waiting-for-host"
                      class="rounded-md border border-dashed border-stone-600 px-3 py-2 text-sm text-stone-400"
                    >
                      Waiting for the host to start.
                    </p>
                  <% end %>
                </div>
              <% :setup -> %>
                <.setup_panel game_state={@game_state} player_id={@player_id} />
              <% :thief_entry -> %>
                <.entry_panel />
              <% :playing -> %>
                <.turn_panel
                  game_state={@game_state}
                  player_id={@player_id}
                  pending_escape_entry={@pending_escape_entry}
                />
              <% :game_over -> %>
                <.game_over_panel game_state={@game_state} />
            <% end %>
          </aside>

          <main
            id="game-board-panel"
            class="min-h-0 min-w-0 overflow-visible rounded-lg border border-stone-700 bg-stone-900 p-3 shadow-2xl shadow-black/30 lg:overflow-hidden lg:p-5"
          >
            <div
              id="museum-board"
              class="grid w-full max-w-[min(100%,calc((100dvh-9.5rem)*1.09))] grid-cols-12 overflow-hidden rounded-md border-4 border-stone-700 bg-stone-800"
            >
              <%= for row <- 1..11, col <- 1..12 do %>
                <% pos = {row, col} %>
                <% cell = Board.cell(pos) %>
                <%= if cell do %>
                  <button
                    type="button"
                    id={cell_id(pos)}
                    data-board-feature={board_feature(pos)}
                    data-window-edge={window_edge(pos)}
                    data-external-door-opening={external_door_opening(pos)}
                    phx-click="board_click"
                    phx-value-row={row}
                    phx-value-col={col}
                    class={[
                      "relative aspect-square min-h-10 border text-[0.62rem] font-black transition",
                      cell_surface_class(cell, pos),
                      if(clickable_cell?(@game_state, @player_id, pos),
                        do: "cursor-pointer ring-2 ring-inset ring-amber-300 hover:brightness-110",
                        else: "cursor-default"
                      )
                    ]}
                    style={cell_borders(pos)}
                  >
                    <%= if power_cell?(cell) do %>
                      <span
                        data-power-symbol
                        class="absolute left-1 top-0 text-black opacity-90"
                      >
                        <.icon name="hero-bolt-solid" class="size-5 text-black" />
                      </span>
                    <% else %>
                      <span class={cell_label_class(cell)}>
                        {cell_label(cell)}
                      </span>
                    <% end %>
                    <%= if Board.external_door_cell?(pos) do %>
                      <.external_door_inset />
                    <% end %>
                    <%= if entry_label(pos) do %>
                      <span data-entry-label class={entry_label_class(pos)}>{entry_label(pos)}</span>
                    <% end %>
                    <%= for mark <- lock_marks(@game_state, @player_id, pos) do %>
                      <span data-board-mark="lock" class={lock_mark_class()}>{mark}</span>
                    <% end %>
                    <span class="relative z-10 flex h-full w-full flex-wrap items-center justify-center gap-0.5 p-1">
                      <%= for mark <- cell_marks(@game_state, @player_id, pos) do %>
                        <span
                          data-board-mark={mark_kind(mark)}
                          data-mark-status={mark_status(mark)}
                          class={mark_class(mark)}
                        >
                          {mark_label(mark)}
                        </span>
                      <% end %>
                    </span>
                  </button>
                <% else %>
                  <%= if Board.external_door_cell?(pos) do %>
                    <button
                      type="button"
                      id={cell_id(pos)}
                      data-board-feature="exit"
                      phx-click="board_click"
                      phx-value-row={row}
                      phx-value-col={col}
                      class={[
                        "relative grid aspect-square min-h-10 place-items-center border border-stone-800 bg-stone-700",
                        external_door_open_edge_class(pos),
                        if(clickable_cell?(@game_state, @player_id, pos),
                          do: "cursor-pointer ring-2 ring-inset ring-amber-300 hover:brightness-110",
                          else: "cursor-default"
                        )
                      ]}
                    >
                      <.external_door_inset />
                      <%= if entry_label(pos) do %>
                        <span data-entry-label class={entry_label_class(pos)}>
                          {entry_label(pos)}
                        </span>
                      <% end %>
                      <%= for mark <- lock_marks(@game_state, @player_id, pos) do %>
                        <span data-board-mark="lock" class={lock_mark_class()}>{mark}</span>
                      <% end %>
                      <span class="relative z-10 flex h-full w-full flex-wrap items-center justify-center gap-0.5 p-1">
                        <%= for mark <- cell_marks(@game_state, @player_id, pos) do %>
                          <span
                            data-board-mark={mark_kind(mark)}
                            data-mark-status={mark_status(mark)}
                            class={mark_class(mark)}
                          >
                            {mark_label(mark)}
                          </span>
                        <% end %>
                      </span>
                    </button>
                  <% else %>
                    <div class="aspect-square min-h-10 bg-stone-950"></div>
                  <% end %>
                <% end %>
              <% end %>
            </div>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def external_door_inset(assigns) do
    ~H"""
    <span
      data-board-feature="exit-inset"
      class="absolute left-1/2 top-1/2 block size-[45%] -translate-x-1/2 -translate-y-1/2 rounded-[3px] border border-stone-400/70 bg-stone-500 shadow-inner shadow-stone-950/50"
    >
    </span>
    """
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true

  def setup_panel(assigns) do
    ~H"""
    <div id="setup-panel" class="space-y-3 rounded-lg border border-sky-300/40 bg-sky-300/10 p-3">
      <h2 class="text-sm font-black uppercase tracking-[0.18em] text-sky-100">Setup</h2>
      <p id="setup-step" class="text-sm text-stone-200">
        {setup_instruction(@game_state, @player_id)}
      </p>
      <div class="grid grid-cols-4 gap-2 text-center text-xs">
        <div class="rounded-md bg-stone-950/70 p-2">
          <strong id="lock-count" class="block text-lg text-stone-50">
            {placed_lock_count(@game_state)}/{Board.lock_count()}
          </strong>
          Locks
        </div>
        <div class="rounded-md bg-stone-950/70 p-2">
          <strong id="painting-count" class="block text-lg text-stone-50">
            {map_size(@game_state.paintings)}
          </strong>
          Art
        </div>
        <div class="rounded-md bg-stone-950/70 p-2">
          <strong id="camera-count" class="block text-lg text-stone-50">
            {placed_camera_count(@game_state)}
          </strong>
          Cameras
        </div>
        <div class="rounded-md bg-stone-950/70 p-2">
          <strong id="pawn-count" class="block text-lg text-stone-50">
            {placed_detective_count(@game_state)}
          </strong>
          Pawns
        </div>
      </div>
    </div>
    """
  end

  def entry_panel(assigns) do
    ~H"""
    <div id="entry-panel" class="space-y-3 rounded-lg border border-amber-300/40 bg-amber-300/10 p-3">
      <h2 class="text-sm font-black uppercase tracking-[0.18em] text-amber-100">Thief Entry</h2>
      <p class="text-sm text-stone-300">The thief chooses an exterior door or window.</p>
    </div>
    """
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true
  attr :pending_escape_entry, :atom, default: nil

  def turn_panel(assigns) do
    ~H"""
    <div id="turn-panel" class="space-y-3 rounded-lg border border-stone-700 bg-stone-800 p-3">
      <h2 class="text-sm font-black uppercase tracking-[0.18em] text-stone-200">Turn</h2>
      <p class="text-sm text-stone-300">
        Current: <strong class="text-stone-50">{current_player_name(@game_state)}</strong>
      </p>
      <%= if @game_state.dice do %>
        <p id="dice-readout" class="rounded-md bg-stone-950/70 p-2 text-sm text-stone-200">
          Die: <strong>{elem(@game_state.dice, 0)}</strong>
          <%= if elem(@game_state.dice, 1) do %>
            , <strong>{elem(@game_state.dice, 1)}</strong>
          <% end %>
        </p>
      <% end %>

      <.motion_decision_buttons game_state={@game_state} player_id={@player_id} />

      <%= if my_turn?(@game_state, @player_id) do %>
        <div class="space-y-2">
          <p class="text-xs uppercase tracking-[0.16em] text-stone-400">
            Actions: {Enum.join(@game_state.turn_actions_remaining, ", ")}
          </p>
          <.look_buttons game_state={@game_state} player_id={@player_id} />
          <.escape_choice_panel
            game_state={@game_state}
            player_id={@player_id}
            pending_escape_entry={@pending_escape_entry}
          />
          <button
            id="end-turn-button"
            type="button"
            phx-click="end_turn"
            class="w-full rounded-md border border-stone-500 px-3 py-2 text-sm font-bold text-stone-100 transition hover:border-stone-300 hover:bg-stone-700"
          >
            End turn
          </button>
        </div>
      <% else %>
        <p class="rounded-md border border-dashed border-stone-700 p-3 text-sm text-stone-400">
          Waiting for another player.
        </p>
      <% end %>
    </div>
    """
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true
  attr :pending_escape_entry, :atom, default: nil

  def escape_choice_panel(assigns) do
    ~H"""
    <%= if escape_choice_visible?(@game_state, @player_id, @pending_escape_entry) do %>
      <div
        id="escape-choice-panel"
        class="space-y-2 rounded-lg border border-amber-300/40 bg-amber-300/10 p-3"
      >
        <p class="text-sm font-semibold text-amber-50">
          Check this {escape_entry_type(@pending_escape_entry)} lock?
        </p>
        <button
          id="confirm-escape-button"
          type="button"
          phx-click="confirm_escape"
          class="w-full rounded-md bg-amber-300 px-3 py-2 text-sm font-black text-stone-950 transition hover:bg-amber-200"
        >
          Check lock
        </button>
        <button
          id="cancel-escape-button"
          type="button"
          phx-click="cancel_escape"
          class="w-full rounded-md border border-amber-200/70 px-3 py-2 text-sm font-bold text-amber-50 transition hover:bg-amber-300/10"
        >
          Stay inside
        </button>
      </div>
    <% end %>
    """
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true

  def look_buttons(assigns) do
    ~H"""
    <%= if player_role(@game_state, @player_id) == :detective and :look in @game_state.turn_actions_remaining and @game_state.dice do %>
      <%= case elem(@game_state.dice, 1) do %>
        <% :eye -> %>
          <button
            id="look-pawn-button"
            type="button"
            phx-click="look_pawn"
            class="w-full rounded-md bg-sky-300 px-3 py-2 text-sm font-black text-stone-950 transition hover:bg-sky-200"
          >
            Look from pawn
          </button>
          <div class="grid grid-cols-2 gap-2">
            <%= for {camera_id, camera} <- @game_state.cameras, camera != nil do %>
              <button
                id={"look-camera-#{camera_id}"}
                type="button"
                phx-click="look_camera"
                phx-value-camera_id={camera_id}
                class="rounded-md border border-sky-300/60 px-2 py-2 text-xs font-bold text-sky-100 transition hover:bg-sky-300/10"
              >
                Camera {camera_id}
              </button>
            <% end %>
          </div>
        <% :camera_scan -> %>
          <button
            id="camera-scan-button"
            type="button"
            phx-click="camera_scan"
            class="w-full rounded-md bg-sky-300 px-3 py-2 text-sm font-black text-stone-950 transition hover:bg-sky-200"
          >
            Camera scan
          </button>
        <% :motion -> %>
          <%= if motion_decision_pending?(@game_state) do %>
            <p
              id="motion-decision-waiting"
              class="rounded-md border border-dashed border-stone-600 px-3 py-2 text-sm text-stone-400"
            >
              Waiting for the thief to choose the motion reading.
            </p>
          <% else %>
            <button
              id="motion-detector-button"
              type="button"
              phx-click="motion_detector"
              class="w-full rounded-md bg-sky-300 px-3 py-2 text-sm font-black text-stone-950 transition hover:bg-sky-200"
            >
              Motion detector
            </button>
          <% end %>
      <% end %>
    <% end %>
    """
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true

  def motion_decision_buttons(assigns) do
    ~H"""
    <%= if player_role(@game_state, @player_id) == :thief and motion_decision_pending?(@game_state) do %>
      <div
        id="motion-decision-panel"
        class="space-y-2 rounded-lg border border-cyan-300/40 bg-cyan-300/10 p-3"
      >
        <p class="text-sm font-semibold text-cyan-50">Motion detector choice</p>
        <button
          id="allow-motion-button"
          type="button"
          phx-click="motion_detector_decision"
          phx-value-decision="allow"
          class="w-full rounded-md bg-cyan-300 px-3 py-2 text-sm font-black text-stone-950 transition hover:bg-cyan-200"
        >
          Allow reading
        </button>
        <button
          id="snip-motion-button"
          type="button"
          phx-click="motion_detector_decision"
          phx-value-decision="cut"
          class="w-full rounded-md border border-cyan-200/70 px-3 py-2 text-sm font-bold text-cyan-50 transition hover:bg-cyan-300/10"
        >
          Cut reading ({@game_state.motion_snips_remaining})
        </button>
      </div>
    <% end %>
    """
  end

  attr :game_state, :map, required: true

  def game_over_panel(assigns) do
    ~H"""
    <div id="game-over-panel" class="rounded-lg border border-emerald-300/40 bg-emerald-300/10 p-3">
      <h2 class="text-sm font-black uppercase tracking-[0.18em] text-emerald-100">Game Over</h2>
      <p class="mt-2 text-sm text-stone-200">
        Winner: <strong class="capitalize text-stone-50">{@game_state.winner}</strong>
      </p>
      <p class="text-sm text-stone-400">Reason: {@game_state.game_over_reason}</p>
    </div>
    """
  end

  defp maybe_join_game(socket, player_name) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MuseumCaper.PubSub, "game:#{socket.assigns.game_id}")

      if player_name != "" do
        join_current_player(socket, player_name)
      else
        socket
      end
    else
      socket
    end
  end

  defp player_id_for("", fallback), do: fallback

  defp player_id_for(player_name, fallback) do
    player_name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> fallback
      slug -> "player-#{slug}"
    end
  end

  defp join_current_player(socket, player_name) do
    case Server.add_player(socket.assigns.server, socket.assigns.player_id, player_name) do
      :ok -> refresh_state(socket, nil)
      {:error, :room_full} -> put_notice(socket, "This room already has four players.")
      {:error, :game_started} -> put_notice(socket, "This game has already started.")
    end
  end

  defp handle_setup_click(socket, pos) do
    state = socket.assigns.game_state

    if player_role(state, socket.assigns.player_id) == :detective do
      {result, message} =
        case removable_setup_piece(state, pos) do
          :painting ->
            {Server.remove_painting(socket.assigns.server, pos), "Artwork removed."}

          :camera ->
            {Server.remove_camera_at(socket.assigns.server, pos), "Camera removed."}

          nil ->
            {place_setup_piece(socket, state, pos), setup_success_message(state.setup_step)}
        end

      case result do
        {:ok, _state} -> {:noreply, refresh_state(socket, message)}
        {:error, reason} -> {:noreply, put_notice(socket, setup_error_message(reason))}
      end
    else
      {:noreply, put_notice(socket, "Only detectives can place setup pieces.")}
    end
  end

  defp handle_entry_click(socket, pos) do
    state = socket.assigns.game_state

    if player_role(state, socket.assigns.player_id) == :thief do
      case Board.entries_for_cell(pos) do
        [%{id: entry_id}] ->
          case Server.enter_museum(socket.assigns.server, entry_id) do
            {:ok, _state} ->
              {:noreply, refresh_state(socket, "The thief has entered the museum.")}

            {:error, _reason} ->
              {:noreply, put_notice(socket, "Choose a valid entry point.")}
          end

        _ ->
          {:noreply, put_notice(socket, "Choose a valid entry point.")}
      end
    else
      {:noreply, put_notice(socket, "Only the thief can enter the museum.")}
    end
  end

  defp handle_playing_board_click(socket, pos) do
    state = socket.assigns.game_state

    case escape_entry_for_cell(state, socket.assigns.player_id, pos) do
      %{id: entry_id} ->
        {:noreply, assign(socket, pending_escape_entry: entry_id, notification: nil)}

      nil ->
        case movement_escape_entry_for_cell(state, socket.assigns.player_id, pos) do
          %{id: entry_id, adj_cell: adj_cell} ->
            handle_movement_escape_click(socket, adj_cell, entry_id)

          nil ->
            handle_move_click(socket, pos)
        end
    end
  end

  defp removable_setup_piece(state, pos) do
    cond do
      Map.has_key?(state.paintings, pos) -> :painting
      camera_at?(state, pos) -> :camera
      true -> nil
    end
  end

  defp place_setup_piece(socket, %{setup_step: :paintings}, pos) do
    Server.place_painting(socket.assigns.server, pos)
  end

  defp place_setup_piece(socket, %{setup_step: :locks}, pos) do
    case Board.entries_for_cell(pos) do
      [%{id: entry_id}] -> Server.toggle_lock(socket.assigns.server, entry_id)
      _ -> {:error, :invalid_placement}
    end
  end

  defp place_setup_piece(socket, %{setup_step: :cameras} = state, pos) do
    with {:ok, camera_id} <- next_camera_id(state) do
      Server.place_camera(socket.assigns.server, camera_id, pos)
    end
  end

  defp place_setup_piece(socket, %{setup_step: :pawns} = state, pos) do
    detective_id = socket.assigns.player_id

    with :ok <- validate_own_detective_pawn(state, detective_id) do
      Server.place_detective_pawn(socket.assigns.server, detective_id, pos)
    end
  end

  defp handle_move_click(socket, pos) do
    state = socket.assigns.game_state

    if state.current_turn != socket.assigns.player_id do
      {:noreply, put_notice(socket, "It is not your turn.")}
    else
      result =
        case player_role(state, socket.assigns.player_id) do
          :thief ->
            Server.move_thief(socket.assigns.server, pos)

          :detective ->
            Server.move_detective(socket.assigns.server, socket.assigns.player_id, pos)

          _ ->
            {:error, :not_a_player}
        end

      case result do
        {:ok, _state} ->
          pending_escape_entry =
            pending_window_escape_after_move(state, socket.assigns.player_id, pos)

          socket = assign(socket, :pending_escape_entry, pending_escape_entry)
          {:noreply, refresh_state(socket, "Move recorded.")}

        {:error, :invalid_move} ->
          {:noreply, put_notice(socket, "That move is not legal.")}

        {:error, _reason} ->
          {:noreply, put_notice(socket, "Could not move that piece.")}
      end
    end
  end

  defp handle_movement_escape_click(socket, adj_cell, entry_id) do
    case Server.move_thief(socket.assigns.server, adj_cell) do
      {:ok, _state} ->
        socket = assign(socket, pending_escape_entry: entry_id, notification: nil)
        {:noreply, refresh_state(socket, "Move recorded.")}

      {:error, :invalid_move} ->
        {:noreply, put_notice(socket, "That move is not legal.")}

      {:error, _reason} ->
        {:noreply, put_notice(socket, "Could not move that piece.")}
    end
  end

  defp handle_escape(socket, exit_id) do
    case Server.try_escape(socket.assigns.server, exit_id) do
      {:ok, result} ->
        message =
          case result do
            :escaped -> "The thief escaped. Game over."
            :locked -> locked_escape_message(exit_id)
          end

        socket = assign(socket, :pending_escape_entry, nil)

        {:noreply, refresh_state(socket, message)}

      {:error, _reason} ->
        {:noreply, put_notice(socket, "The thief must be at that door or window.")}
    end
  end

  defp refresh_state(socket, message) do
    assign(socket, game_state: Server.get_state(socket.assigns.server), notification: message)
  end

  defp put_notice(socket, message), do: assign(socket, notification: message)

  defp pending_window_escape_after_move(state, player_id, pos) do
    if player_role(state, player_id) == :thief do
      Board.entries_for_cell(pos)
      |> Enum.find(fn entry -> entry.type == :window end)
      |> case do
        nil -> nil
        entry -> entry.id
      end
    end
  end

  defp parse_entry_id(entry_id) do
    Board.entries()
    |> Enum.find(fn entry -> Atom.to_string(entry.id) == entry_id end)
    |> case do
      nil -> {:error, :invalid_entry}
      entry -> {:ok, entry.id}
    end
  end

  defp next_camera_id(state) do
    state.cameras
    |> Enum.find(fn {_id, camera} -> camera == nil end)
    |> case do
      nil -> {:error, :invalid_phase}
      {camera_id, _} -> {:ok, camera_id}
    end
  end

  defp validate_own_detective_pawn(state, detective_id) do
    case Map.fetch(state.detective_positions, detective_id) do
      {:ok, nil} -> :ok
      {:ok, _pos} -> {:error, :detective_already_placed}
      :error -> {:error, :not_detective}
    end
  end

  defp needs_join?(%{phase: :lobby} = state, player_id),
    do: player_id == nil or not Map.has_key?(state.players, player_id)

  defp needs_join?(_state, _player_id), do: false

  defp join_closed?(%{phase: :lobby}, _player_id), do: false

  defp join_closed?(state, player_id),
    do: player_id == nil or not Map.has_key?(state.players, player_id)

  defp player_order(%{phase: :lobby, turn_order: order}), do: order
  defp player_order(state), do: Enum.uniq(state.turn_order)

  defp host?(%{phase: :lobby, turn_order: [host_id | _]}, player_id), do: host_id == player_id
  defp host?(_state, _player_id), do: false

  defp host_leaving_open_game?(%{phase: :game_over}, _player_id), do: false

  defp host_leaving_open_game?(state, player_id), do: state.host_player_id == player_id

  defp player_role(state, player_id) do
    case Map.get(state.players, player_id) do
      nil -> nil
      player -> player.role
    end
  end

  defp detective_result_visible?(state, player_id) do
    Map.has_key?(state.players, player_id) and state.detective_result != nil
  end

  defp power_status_visible?(state, player_id) do
    player_role(state, player_id) == :detective and not state.power_active and
      state.power_revealed
  end

  defp detective_result_message({:look_pawn, :chase_triggered}),
    do: "The detectives spotted the thief."

  defp detective_result_message({:look_pawn, :no_sighting}),
    do: "No thief in that line of sight."

  defp detective_result_message({:look_camera, {:sighting, camera_id}}),
    do: camera_sighting_message(camera_id)

  defp detective_result_message({:look_camera, :camera_disabled}),
    do: "That camera was disabled."

  defp detective_result_message({:look_camera, :power_off}),
    do: "The power is off, so cameras cannot see."

  defp detective_result_message({:look_camera, :no_sighting}),
    do: "No thief in that camera line."

  defp detective_result_message({:camera_scan, disabled_ids, {:sighting, sighting_ids}}),
    do: camera_scan_message(disabled_ids, sighting_ids)

  defp detective_result_message({:camera_scan, disabled_ids, :no_sighting}),
    do: "Camera scan found #{length(disabled_ids)} disabled cameras. No sighting."

  defp detective_result_message({:camera_scan, :power_off}),
    do: "The power is off, so camera scan cannot see."

  defp detective_result_message({:motion, :power_off}),
    do: "The power is off, so motion detector cannot read."

  defp detective_result_message({:motion, {:color, color}}),
    do: "Motion detector reads #{color}."

  defp detective_result_message({:motion, :allowed}),
    do: "The thief allowed the motion detector reading."

  defp detective_result_message({:motion, :snipped}),
    do: "The thief snipped a motion detector reading."

  defp detective_result_message({:escape_locked, entry_id}),
    do: "The thief checked the #{entry_label(entry_id)} lock. It was locked."

  defp camera_sighting_message(camera_id), do: "#{camera_names([camera_id])} spotted the thief."

  defp camera_scan_message(disabled_ids, sighting_ids) do
    "Camera scan found #{length(disabled_ids)} disabled cameras and #{camera_names(sighting_ids)} spotted the thief."
  end

  defp camera_names([id]), do: "C#{id}"

  defp camera_names(ids) do
    ids
    |> Enum.map(&"C#{&1}")
    |> Enum.join(", ")
  end

  defp current_player_name(state) do
    case Map.get(state.players, state.current_turn) do
      nil -> "Nobody"
      player -> player.name
    end
  end

  defp my_turn?(state, player_id), do: state.current_turn == player_id

  defp motion_decision_pending?(state) do
    state.phase == :playing and state.dice != nil and elem(state.dice, 1) == :motion and
      :look in state.turn_actions_remaining and state.power_active and
      state.motion_snips_remaining > 0 and state.motion_detector_decision != :allowed
  end

  defp escape_choice_visible?(state, player_id, pending_escape_entry) do
    pending_escape_entry != nil and player_role(state, player_id) == :thief and
      state.current_turn == player_id
  end

  defp escape_entry_type(entry_id) do
    case Board.entry_by_id(entry_id) do
      %{type: :window} -> "window"
      %{type: :door} -> "door"
      _ -> "exit"
    end
  end

  defp setup_instruction(state, player_id) do
    if player_role(state, player_id) == :thief do
      "Wait patiently for the detectives to set up."
    else
      setup_instruction(state)
    end
  end

  defp setup_instruction(%{setup_step: :locks}) do
    "Place #{Board.lock_count()} locks on exterior doors or windows; the rest stay unlocked."
  end

  defp setup_instruction(%{setup_step: :paintings}) do
    "Place 9 artworks: cover each required room, away from windows and doors."
  end

  defp setup_instruction(%{setup_step: :cameras}), do: "Place 4 cameras anywhere occupiable."
  defp setup_instruction(%{setup_step: :pawns}), do: "Place your detective pawn."

  defp setup_success_message(:locks), do: "Lock placement updated."
  defp setup_success_message(:paintings), do: "Artwork placed."
  defp setup_success_message(:cameras), do: "Camera placed."
  defp setup_success_message(:pawns), do: "Detective placed."

  defp setup_error_message(:too_many_locks), do: "All locks are already placed."
  defp setup_error_message(:cell_occupied), do: "That cell is already occupied."
  defp setup_error_message(:invalid_placement), do: "That piece cannot be placed there."
  defp setup_error_message(:invalid_phase), do: "Setup has moved to the next step."
  defp setup_error_message(:detective_already_placed), do: "Your detective is already placed."
  defp setup_error_message(:not_detective), do: "Only detectives can place setup pieces."

  defp setup_error_message(:missing_color_room),
    do: "Place at least one artwork in each required room."

  defp setup_error_message(_reason), do: "That setup action is not allowed."

  defp placed_camera_count(state),
    do: Enum.count(state.cameras, fn {_id, camera} -> camera != nil end)

  defp placed_lock_count(state),
    do: Enum.count(state.locks, fn {_id, status} -> status == :locked end)

  defp placed_detective_count(state) do
    Enum.count(state.detective_positions, fn {_id, pos} -> pos != nil end)
  end

  defp clickable_cell?(state, player_id, pos) do
    cond do
      state.phase == :setup ->
        player_role(state, player_id) == :detective and setup_clickable?(state, player_id, pos)

      state.phase == :thief_entry ->
        player_role(state, player_id) == :thief and Board.entries_for_cell(pos) != []

      state.phase == :playing and state.current_turn == player_id ->
        pos in valid_destinations(state, player_id) or
          escape_entry_for_cell(state, player_id, pos) != nil or
          movement_escape_entry_for_cell(state, player_id, pos) != nil

      true ->
        false
    end
  end

  defp escape_entry_for_cell(state, player_id, pos) do
    if player_role(state, player_id) == :thief and state.current_turn == player_id do
      Enum.find(Board.entries_for_cell(pos), fn entry ->
        Board.exit_adjacent_cell(entry) == state.thief_position
      end)
    end
  end

  defp movement_escape_entry_for_cell(state, player_id, pos) do
    if player_role(state, player_id) == :thief and state.current_turn == player_id and
         :move in state.turn_actions_remaining do
      Enum.find(Board.entries_for_cell(pos), fn
        %{type: :door} = entry -> movement_escape_reachable?(state, entry)
        _entry -> false
      end)
    end
  end

  defp movement_escape_reachable?(state, %{door_cell: door_cell, adj_cell: adj_cell})
       when door_cell == adj_cell do
    adj_cell in Rules.valid_thief_destinations(state)
  end

  defp movement_escape_reachable?(state, %{adj_cell: adj_cell}) do
    adj_cell in Rules.valid_thief_destinations(state, 2)
  end

  defp setup_clickable?(state, player_id, pos) do
    cond do
      Map.has_key?(state.paintings, pos) or camera_at?(state, pos) ->
        true

      true ->
        case {state.setup_step, Board.cell(pos)} do
          {:locks, _cell} ->
            Board.entries_for_cell(pos) != []

          {:paintings, %{type: :room}} ->
            Board.painting_placeable_cell?(pos) and not occupied_for_setup?(state, pos)

          {:cameras, _cell} ->
            Board.camera_placeable_cell?(pos) and not occupied_for_setup?(state, pos)

          {:pawns, _cell} ->
            Board.detective_placeable_cell?(pos) and own_detective_unplaced?(state, player_id) and
              not occupied_for_setup?(state, pos)

          _ ->
            false
        end
    end
  end

  defp own_detective_unplaced?(state, player_id),
    do: Map.get(state.detective_positions, player_id) == nil

  defp occupied_for_setup?(state, pos) do
    Map.has_key?(state.paintings, pos) or
      camera_at?(state, pos) or
      Enum.any?(state.detective_positions, fn {_id, detective_pos} -> detective_pos == pos end)
  end

  defp camera_at?(state, pos) do
    Enum.any?(state.cameras, fn {_id, camera} -> camera != nil and camera.pos == pos end)
  end

  defp valid_destinations(state, player_id) do
    if :move in state.turn_actions_remaining do
      case player_role(state, player_id) do
        :thief -> Rules.valid_thief_destinations(state)
        :detective when state.dice != nil -> Rules.valid_detective_destinations(state, player_id)
        _ -> []
      end
    else
      []
    end
  end

  defp board_feature(pos) do
    cond do
      Board.window_cell?(pos) -> "window"
      Board.external_door_cell?(pos) -> "exit"
      true -> nil
    end
  end

  defp window_edge(pos), do: pos |> window_edges() |> List.first()

  defp window_edges({row, col} = pos) do
    if Board.window_cell?(pos) do
      [
        {"top", {row - 1, col}},
        {"bottom", {row + 1, col}},
        {"left", {row, col - 1}},
        {"right", {row, col + 1}}
      ]
      |> Enum.filter(fn {_edge, adjacent_pos} -> Board.cell(adjacent_pos) == nil end)
      |> Enum.map(fn {edge, _adjacent_pos} -> edge end)
    else
      []
    end
  end

  defp cell_id({row, col}), do: "cell-#{row}-#{col}"

  defp cell_surface_class(cell, pos) do
    if Board.external_door_cell?(pos), do: "bg-stone-700 text-stone-100", else: cell_class(cell)
  end

  defp external_door_open_edge_class({6, 1}), do: "border-r-0"
  defp external_door_open_edge_class({5, 12}), do: "border-l-0"
  defp external_door_open_edge_class(_pos), do: nil

  defp external_door_opening({6, 2}), do: "left"
  defp external_door_opening({5, 11}), do: "right"
  defp external_door_opening(_pos), do: nil

  defp cell_class(nil), do: "bg-gray-700"
  defp cell_class(%{type: :power_room}), do: utility_cell_class()
  defp cell_class(%{type: :corridor}), do: gray_cell_class()
  defp cell_class(%{room_id: :gallery_red}), do: "bg-red-300 text-stone-950"
  defp cell_class(%{room_id: :gallery_green}), do: "bg-emerald-300 text-stone-950"
  defp cell_class(%{room_id: :gallery_yellow}), do: "bg-yellow-200 text-stone-950"
  defp cell_class(%{room_id: :gallery_blue}), do: "bg-sky-300 text-stone-950"
  defp cell_class(%{room_id: :gallery_purple}), do: "bg-violet-300 text-stone-950"
  defp cell_class(%{room_id: :white_room}), do: "bg-zinc-50 text-stone-950"

  defp cell_class(%{room_id: room_id}) when room_id in [:other_left, :other_right],
    do: utility_cell_class()

  defp cell_class(_), do: "bg-orange-200 text-stone-950"

  defp gray_cell_class, do: "bg-stone-300 text-stone-950"
  defp utility_cell_class, do: "bg-stone-200 text-stone-950"

  defp cell_label_class(_cell),
    do: "absolute left-1 top-1 text-[0.55rem] font-bold uppercase opacity-45"

  defp cell_label(%{type: :corridor}), do: ""
  defp cell_label(%{room_id: room_id}) when room_id in [:other_left, :other_right], do: ""

  defp cell_label(%{room_id: room_id}),
    do: room_id |> Atom.to_string() |> String.replace("gallery_", "") |> String.first()

  defp cell_label(_), do: ""

  defp power_cell?(%{type: :power_room}), do: true
  defp power_cell?(_cell), do: false

  defp locked_escape_message(entry_id), do: "#{entry_label(entry_id)} lock is locked."

  defp entry_label(entry_id) when is_atom(entry_id) do
    case Board.entry_by_id(entry_id) do
      %{label: label} -> label
      _ -> "exit"
    end
  end

  defp entry_label(pos) do
    case Board.entries_for_cell(pos) do
      [%{label: label} | _entries] -> label
      _ -> nil
    end
  end

  defp entry_label_class(pos) do
    base =
      "absolute bottom-0.5 right-0.5 z-20 rounded-sm px-1 py-0.5 text-[0.55rem] font-black leading-none shadow-sm"

    if Board.external_door_cell?(pos) do
      "#{base} bg-stone-950/85 text-stone-50"
    else
      "#{base} bg-cyan-950/85 text-cyan-100"
    end
  end

  defp cell_marks(state, player_id, pos) do
    painting_marks(state, player_id, pos) ++
      camera_marks(state, player_id, pos) ++
      detective_marks(state, pos) ++
      thief_marks(state, player_id, pos)
  end

  defp lock_marks(state, player_id, pos) do
    if player_role(state, player_id) == :detective do
      state
      |> locked_entries_for_cell(pos)
      |> Enum.map(fn _entry -> "Lock" end)
    else
      []
    end
  end

  defp locked_entries_for_cell(state, pos) do
    Enum.filter(Board.entries_for_cell(pos), fn entry -> state.locks[entry.id] == :locked end)
  end

  defp painting_marks(state, player_id, pos) do
    label = painting_label(state, pos)

    case state.paintings[pos] do
      :present -> [{:painting, label, :present}]
      :targeted -> targeted_painting_marks(state, player_id, label)
      :removed -> [{:painting, label, :removed}]
      _ -> []
    end
  end

  defp targeted_painting_marks(state, player_id, label) do
    if player_role(state, player_id) == :thief,
      do: [{:painting, label, :targeted}],
      else: [{:painting, label, :present}]
  end

  defp painting_label(state, pos) do
    Map.get(state.painting_labels, pos) || fallback_painting_label(state.paintings, pos)
  end

  defp fallback_painting_label(paintings, pos) do
    index =
      paintings
      |> Map.keys()
      |> Enum.sort()
      |> Enum.find_index(&(&1 == pos))

    if index == nil, do: "Art", else: "A#{index + 1}"
  end

  defp camera_marks(state, player_id, pos) do
    state.cameras
    |> Enum.filter(fn {_id, camera} -> camera != nil and camera.pos == pos end)
    |> Enum.map(fn {id, camera} ->
      {:camera, id, visible_camera_status(state, player_id, camera)}
    end)
  end

  defp visible_camera_status(state, player_id, camera) do
    cond do
      player_role(state, player_id) == :thief ->
        camera.status

      camera.status == :disabled and Map.get(camera, :revealed, false) ->
        :disabled

      true ->
        :active
    end
  end

  defp detective_marks(state, pos) do
    state.detective_positions
    |> Enum.filter(fn {_id, detective_pos} -> detective_pos == pos end)
    |> Enum.map(fn {id, _pos} -> detective_label(state, id) end)
  end

  defp thief_marks(state, player_id, pos) do
    if state.thief_position == pos and
         (player_role(state, player_id) == :thief or state.chase_mode or state.phase == :game_over) do
      ["T"]
    else
      []
    end
  end

  defp detective_label(state, id) do
    case Map.get(state.players, id) do
      %{name: name} -> name
      nil -> "Detective"
    end
  end

  defp mark_class("T"),
    do: "rounded bg-stone-950 px-1.5 py-0.5 text-[0.65rem] font-black text-amber-200"

  defp mark_class({:painting, _label, :present}),
    do: "rounded bg-amber-900 px-1 py-0.5 text-[0.58rem] font-black text-amber-100"

  defp mark_class({:painting, _label, :targeted}),
    do: "rounded bg-rose-800 px-1 py-0.5 text-[0.58rem] font-black text-rose-100"

  defp mark_class({:painting, _label, :removed}),
    do:
      "rounded bg-zinc-500 px-1 py-0.5 text-[0.58rem] font-black text-stone-950 line-through decoration-2"

  defp mark_class({:camera, _id, :disabled}),
    do: "rounded bg-red-700 px-1 py-0.5 text-[0.58rem] font-black text-red-50"

  defp mark_class({:camera, _id, _status}),
    do: "rounded bg-sky-900 px-1 py-0.5 text-[0.58rem] font-black text-sky-100"

  defp mark_class(_),
    do:
      "max-w-full truncate rounded bg-emerald-900 px-1 py-0.5 text-[0.54rem] font-black text-emerald-100"

  defp mark_label({:painting, label, :targeted}), do: "#{label}*"
  defp mark_label({:painting, label, _status}), do: label
  defp mark_label({:camera, id, _status}), do: "C#{id}"
  defp mark_label(mark), do: mark

  defp mark_kind({:painting, _label, _status}), do: "painting"
  defp mark_kind({:camera, _id, _status}), do: "camera"
  defp mark_kind("T"), do: "thief"
  defp mark_kind(_mark), do: "piece"

  defp mark_status({:painting, _label, status}), do: status
  defp mark_status({:camera, _id, status}), do: status
  defp mark_status(_mark), do: nil

  defp lock_mark_class do
    "absolute left-1/2 top-1 z-20 -translate-x-1/2 rounded border border-stone-200/70 bg-stone-800 px-1 py-0.5 text-[0.52rem] font-black uppercase leading-none text-stone-100 shadow shadow-stone-950/40"
  end

  defp cell_borders({r, c} = pos) do
    window_edges = window_edges(pos)
    external_door_opening = external_door_opening(pos)

    [
      {"border-top", "top", {r - 1, c}},
      {"border-bottom", "bottom", {r + 1, c}},
      {"border-left", "left", {r, c - 1}},
      {"border-right", "right", {r, c + 1}}
    ]
    |> Enum.map_join(" ", fn {prop, edge, adj} ->
      cond do
        edge == external_door_opening ->
          "#{prop}:0;"

        edge in window_edges ->
          "#{prop}:4px solid rgb(34,211,238);"

        Board.passable?(pos, adj) ->
          "#{prop}:1px solid rgba(28,25,23,0.28);"

        true ->
          "#{prop}:3px solid rgb(28,25,23);"
      end
    end)
  end
end
