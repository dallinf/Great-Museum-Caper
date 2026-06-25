defmodule MuseumCaperWeb.GameLive do
  use MuseumCaperWeb, :live_view
  alias MuseumCaper.Lobby.Server, as: LobbyServer
  alias MuseumCaper.Game.{Board, PawnColors, Replay, Rules, Server}

  @impl true
  def mount(%{"game_id" => game_id} = params, _session, socket) do
    case Registry.lookup(MuseumCaper.GameRegistry, game_id) do
      [] ->
        {:ok, push_navigate(socket, to: ~p"/")}

      [{_pid, _}] ->
        player_name = params |> Map.get("player_name", "") |> String.trim()
        player_color = Map.get(params, "player_color")
        server = {:via, Registry, {MuseumCaper.GameRegistry, game_id}}
        player_id = player_id_for(player_name, socket.id)
        game_state = Server.get_state(server)
        join_form_player_color = available_join_pawn_color(game_state, player_id, player_color)

        socket =
          socket
          |> assign(
            game_id: game_id,
            server: server,
            player_id: player_id,
            player_name: player_name,
            player_color: player_color,
            notification: nil,
            notification_id: nil,
            artwork_reveal_toast: nil,
            pending_escape_entry: nil,
            turn_banner_key: nil,
            revealed_mark_keys: [],
            animated_mark_keys: %{},
            selected_revealed_round: nil,
            revealed_route_marks: %{},
            join_form:
              to_form(
                %{
                  "player_name" => player_name,
                  "player_color" => join_form_player_color
                },
                as: :player
              )
          )
          |> maybe_join_game(player_name, player_color)

        game_state = Server.get_state(server)
        selected_revealed_round = latest_revealed_round_number(game_state)

        replay_payload = selected_replay_payload(game_state, selected_revealed_round)

        {:ok,
         assign(socket,
           game_state: game_state,
           selected_revealed_round: selected_revealed_round,
           revealed_route_marks: revealed_route_marks(game_state, selected_revealed_round),
           replay_payload: replay_payload
         )}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:state_changed, game_state}, socket) do
    previous_state = socket.assigns.game_state
    previous_turn = banner_turn_player(previous_state)
    revealed_mark_keys = next_revealed_mark_keys(socket, previous_state, game_state)
    animated_mark_keys = next_animated_mark_keys(socket, previous_state, game_state)

    selected_revealed_round =
      selected_revealed_round(socket.assigns.selected_revealed_round, previous_state, game_state)

    replay_payload = selected_replay_payload(game_state, selected_revealed_round)

    socket =
      socket
      |> assign(
        game_state: game_state,
        revealed_mark_keys: revealed_mark_keys,
        animated_mark_keys: animated_mark_keys,
        selected_revealed_round: selected_revealed_round,
        revealed_route_marks: revealed_route_marks(game_state, selected_revealed_round),
        replay_payload: replay_payload,
        artwork_reveal_toast: next_artwork_reveal_toast(socket, previous_state, game_state)
      )
      |> maybe_show_turn_banner(previous_turn, game_state)

    {:noreply, socket}
  end

  @impl true
  def handle_event("join_game", %{"player" => player_params}, socket) do
    player_name = Map.get(player_params, "player_name", "")
    player_name = String.trim(player_name)

    if player_name == "" do
      {:noreply, put_notice(socket, "Enter a name to join this room.")}
    else
      player_id = player_id_for(player_name, socket.id)

      player_color =
        player_params
        |> Map.get("player_color")
        |> requested_or_default_pawn_color(socket.assigns.game_state, player_id)

      socket =
        socket
        |> assign(
          player_id: player_id,
          player_name: player_name,
          player_color: player_color,
          join_form:
            to_form(%{"player_name" => player_name, "player_color" => player_color}, as: :player)
        )
        |> join_current_player(player_name, player_color)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_join_form", %{"player" => player_params}, socket) do
    {:noreply, assign(socket, :join_form, to_form(player_params, as: :player))}
  end

  @impl true
  def handle_event("start_game", params, socket) do
    game_mode = start_game_mode(params)

    case Server.start_game(socket.assigns.server, socket.assigns.player_id, game_mode: game_mode) do
      {:ok, _state} ->
        {:noreply, refresh_state(socket, start_game_message(game_mode))}

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

    {:noreply, push_navigate(socket, to: ~p"/")}
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
      message = escape_result_message(result, entry_id)

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
  def handle_event("select_route_round", %{"round" => round}, socket) do
    game_state = socket.assigns.game_state

    selected_revealed_round =
      case Integer.parse(round) do
        {round_number, ""} ->
          selectable_revealed_round(game_state, round_number)

        _ ->
          socket.assigns.selected_revealed_round
      end

    replay_payload = selected_replay_payload(game_state, selected_revealed_round)

    {:noreply,
     assign(socket,
       selected_revealed_round: selected_revealed_round,
       revealed_route_marks: revealed_route_marks(game_state, selected_revealed_round),
       replay_payload: replay_payload
     )}
  end

  @impl true
  def handle_event("start_next_round", _params, socket) do
    case Server.start_next_round(socket.assigns.server, socket.assigns.player_id) do
      {:ok, _state} ->
        {:noreply, refresh_state(socket, "Next round setup started.")}

      {:error, :not_host} ->
        {:noreply, put_notice(socket, "Only the host can start the next round.")}

      {:error, :invalid_phase} ->
        {:noreply, put_notice(socket, "Round review has already ended.")}
    end
  end

  @impl true
  def handle_event("look_pawn", _params, socket) do
    detective_id = active_detective_id(socket.assigns.game_state, socket.assigns.player_id)

    case Server.use_eye_action(socket.assigns.server, detective_id) do
      {:ok, :chase_triggered} ->
        {:noreply, refresh_state(socket, "The detectives spotted the thief.")}

      {:ok, :no_sighting} ->
        {:noreply, refresh_state(socket, "Pawn cannot see the thief.")}
    end
  end

  @impl true
  def handle_event("look_camera", %{"camera_id" => camera_id}, socket) do
    camera_id = String.to_integer(camera_id)
    detective_id = active_detective_id(socket.assigns.game_state, socket.assigns.player_id)

    case Server.use_eye_on_camera(
           socket.assigns.server,
           detective_id,
           camera_id
         ) do
      {:ok, {:sighting, camera_id}} ->
        {:noreply, refresh_state(socket, camera_sighting_message(camera_id))}

      {:ok, :camera_disabled} ->
        {:noreply, refresh_state(socket, "That camera was disabled.")}

      {:ok, :power_off} ->
        {:noreply, refresh_state(socket, "The power is off, so cameras cannot see.")}

      {:ok, :no_sighting} ->
        {:noreply, refresh_state(socket, camera_no_sighting_message(camera_id))}
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
    <Layouts.app
      flash={@flash}
      back_to_lobby_event={back_to_lobby_event(@game_state)}
      compact={true}
      recent_result={latest_detective_result(@game_state, @player_id)}
    >
      <div
        id="game-shell"
        class="h-dvh overflow-hidden bg-stone-950 text-stone-100"
      >
        <div
          id="game-layout"
          class="grid h-full min-h-0 grid-rows-[auto_minmax(0,1fr)] gap-2 overflow-hidden p-2 lg:grid-cols-[19rem_minmax(0,1fr)] lg:grid-rows-1 lg:gap-4 lg:p-5"
        >
          <aside
            id="game-sidebar"
            data-mobile-density="compact"
            class="order-last min-h-0 space-y-2 overflow-y-auto rounded-lg border border-stone-700 bg-stone-900/95 p-2 shadow-2xl shadow-black/30 lg:order-none lg:space-y-3 lg:p-4"
          >
            <%= if needs_join?(@game_state, @player_id) do %>
              <div id="join-panel" class="rounded-lg border border-amber-300/30 bg-amber-200/10 p-3">
                <.form
                  for={@join_form}
                  id="join-game-form"
                  phx-change="change_join_form"
                  phx-submit="join_game"
                  class="space-y-3"
                >
                  <.input field={@join_form[:player_name]} type="text" label="Your name" />
                  <.pawn_color_picker
                    field={@join_form[:player_color]}
                    id_prefix="join-player-color"
                    taken_colors={taken_pawn_colors(@game_state, @player_id)}
                  />
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

            <section id="player-panel" data-mobile-density="compact" class="space-y-1 lg:space-y-2">
              <h2 class="text-[0.68rem] font-bold uppercase leading-none tracking-[0.18em] text-stone-400 lg:text-sm">
                Players
              </h2>
              <%= if map_size(@game_state.players) == 0 do %>
                <p class="rounded-md border border-dashed border-stone-700 p-3 text-sm text-stone-500">
                  Waiting for players.
                </p>
              <% else %>
                <ul
                  id="player-list"
                  data-mobile-layout="compact-grid"
                  class="grid grid-cols-[repeat(auto-fit,minmax(4.5rem,1fr))] gap-1 lg:block lg:space-y-2"
                >
                  <%= for player_id <- player_order(@game_state) do %>
                    <% player = @game_state.players[player_id] %>
                    <% current_turn? = current_turn_player?(@game_state, player_id) %>
                    <% display_color = player_display_color(@game_state, player_id, player.color) %>
                    <% setup_thief? = setup_thief_player?(@game_state, player_id) %>
                    <li
                      class={[
                        "flex min-h-9 items-center justify-between gap-1 rounded-md border px-2 py-1 text-xs transition-colors lg:min-h-0 lg:gap-3 lg:px-3 lg:py-2 lg:text-sm",
                        cond do
                          current_turn? ->
                            "border-amber-300 bg-amber-300/15 shadow-sm shadow-amber-950/30"

                          setup_thief? ->
                            "border-stone-300/80 bg-stone-700/90 shadow-sm shadow-stone-950/40"

                          true ->
                            "border-stone-700 bg-stone-800/80"
                        end
                      ]}
                      id={"player-row-#{player_id}"}
                      data-turn-status={if(current_turn?, do: "current", else: "waiting")}
                      data-setup-role={if(setup_thief?, do: "thief")}
                    >
                      <span class="flex min-w-0 items-center gap-1 lg:gap-2">
                        <span
                          data-player-color={player_color_status(display_color)}
                          class={[
                            "block size-3 shrink-0 rounded-full border-2 lg:size-3.5",
                            pawn_color_class(display_color)
                          ]}
                        >
                        </span>
                        <span data-player-name class="min-w-0 truncate font-semibold">
                          {player.name}
                        </span>
                      </span>
                      <span class="flex shrink-0 items-center gap-0.5 lg:gap-1">
                        <%= if current_turn? do %>
                          <span
                            data-turn-badge="compact"
                            class="rounded bg-amber-300 px-1 py-0.5 text-[0.58rem] font-black uppercase leading-none tracking-normal text-stone-950 lg:px-2 lg:py-1 lg:text-[0.68rem] lg:tracking-wide"
                          >
                            Turn
                          </span>
                        <% end %>
                        <span
                          data-player-role-badge={
                            if(setup_thief?, do: "setup-thief", else: "compact")
                          }
                          class={[
                            "rounded px-2 py-1 text-[0.68rem] font-bold uppercase tracking-wide",
                            if(setup_thief?,
                              do: "hidden bg-stone-100 text-stone-950 lg:inline-flex",
                              else: "hidden bg-stone-950/80 text-stone-300 lg:inline-flex"
                            )
                          ]}
                        >
                          {player_role_label(player.role)}
                        </span>
                      </span>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </section>

            <%= if full_game?(@game_state) do %>
              <.full_game_scoreboard
                game_state={@game_state}
                selected_revealed_round={@selected_revealed_round}
                replay_payload={@replay_payload}
              />
            <% end %>

            <% power_status = known_power_status(@game_state, @player_id) %>
            <%= if power_status do %>
              <div
                id="power-status"
                data-power-status={power_status_value(power_status)}
                class={power_status_class(power_status)}
              >
                <.icon name={power_status_icon(power_status)} class="size-4 shrink-0" />
                <span>{power_status_label(power_status)}</span>
              </div>
            <% end %>

            <%= case @game_state.phase do %>
              <% :lobby -> %>
                <div
                  id="waiting-room"
                  class="space-y-3 rounded-lg border border-stone-700 bg-stone-800 p-3"
                >
                  <p id="waiting-room-copy" class="text-sm text-stone-300">
                    Invite players to this room, then start the game when everyone has joined.
                  </p>
                  <%= if host?(@game_state, @player_id) do %>
                    <% start_enabled? = start_game_enabled?(@game_state) %>
                    <div class="grid gap-2">
                      <button
                        id="start-game-button"
                        type="button"
                        phx-click="start_game"
                        phx-value-mode="limited"
                        disabled={!start_enabled?}
                        class={[
                          "inline-flex w-full items-center justify-center gap-2 rounded-md px-3 py-2 text-sm font-black transition",
                          if(start_enabled?,
                            do: "bg-emerald-400 text-stone-950 hover:bg-emerald-300",
                            else:
                              "cursor-not-allowed border border-stone-600 bg-stone-700 text-stone-400"
                          )
                        ]}
                      >
                        <.icon name="hero-play-solid" class="size-4" /> Start Limited Game
                      </button>
                      <button
                        id="start-full-game-button"
                        type="button"
                        phx-click="start_game"
                        phx-value-mode="full"
                        disabled={!start_enabled?}
                        class={[
                          "inline-flex w-full items-center justify-center gap-2 rounded-md border px-3 py-2 text-sm font-black transition",
                          if(start_enabled?,
                            do:
                              "border-amber-300/70 bg-amber-300/10 text-amber-100 hover:border-amber-200 hover:bg-amber-300/20",
                            else: "cursor-not-allowed border-stone-600 bg-stone-700 text-stone-400"
                          )
                        ]}
                      >
                        <.icon name="hero-trophy-solid" class="size-4" /> Start Full Game
                      </button>
                    </div>
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
              <% :round_review -> %>
                <.round_review_panel game_state={@game_state} player_id={@player_id} />
              <% :game_over -> %>
                <.game_over_panel
                  game_state={@game_state}
                  selected_revealed_round={@selected_revealed_round}
                  replay_payload={@replay_payload}
                />
            <% end %>
          </aside>

          <main
            id="game-board-panel"
            class="order-first flex min-h-0 min-w-0 items-start justify-center overflow-hidden rounded-lg border border-stone-700 bg-stone-900 p-2 shadow-2xl shadow-black/30 lg:order-none lg:items-center lg:p-5"
          >
            <div
              id="museum-board"
              class="grid aspect-[12/11] w-full max-w-[min(100%,calc((100dvh-10rem)*1.09))] grid-cols-12 overflow-hidden rounded-md border-2 border-stone-700 bg-stone-800 md:border-4 lg:max-w-[min(100%,calc((100dvh-3rem)*1.09))]"
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
                      "relative aspect-square min-h-0 border text-[0.62rem] font-black transition",
                      cell_surface_class(cell, pos),
                      if(clickable_cell?(@game_state, @player_id, pos),
                        do:
                          "cursor-pointer ring-1 ring-inset ring-amber-300 hover:brightness-110 md:ring-2",
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
                    <.thief_route_cell_overlay route_marks={Map.get(@revealed_route_marks, pos, [])} />
                    <.board_mark_stack
                      marks={cell_marks(@game_state, @player_id, pos)}
                      revealed_mark_keys={@revealed_mark_keys}
                      animated_mark_keys={@animated_mark_keys}
                      movement_path={@game_state.movement_path}
                    />
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
                        "relative grid aspect-square min-h-0 place-items-center border border-stone-800 bg-stone-700",
                        external_door_open_edge_class(pos),
                        if(clickable_cell?(@game_state, @player_id, pos),
                          do:
                            "cursor-pointer ring-1 ring-inset ring-amber-300 hover:brightness-110 md:ring-2",
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
                      <.thief_route_cell_overlay route_marks={Map.get(@revealed_route_marks, pos, [])} />
                      <.board_mark_stack
                        marks={cell_marks(@game_state, @player_id, pos)}
                        revealed_mark_keys={@revealed_mark_keys}
                        animated_mark_keys={@animated_mark_keys}
                        movement_path={@game_state.movement_path}
                      />
                    </button>
                  <% else %>
                    <div class="aspect-square min-h-0 bg-stone-950"></div>
                  <% end %>
                <% end %>
              <% end %>
            </div>
          </main>
        </div>
        <% latest_result = latest_detective_result(@game_state, @player_id) %>
        <% latest_result_key = latest_detective_result_key(@game_state) %>
        <%= if @notification || latest_result || @artwork_reveal_toast do %>
          <div
            id="game-toast-stack"
            class="pointer-events-none fixed inset-x-3 bottom-3 z-40 flex flex-col gap-2 sm:inset-x-auto sm:right-4 sm:w-96 md:bottom-6 md:right-6 md:w-[28rem] md:gap-3 lg:w-[32rem]"
          >
            <%= if @notification do %>
              <div
                id="game-notification"
                phx-hook="ToastHook"
                data-toast-key={"notice:#{@notification_id}"}
                role="status"
                class="translate-y-2 rounded-lg border border-amber-300/50 bg-stone-950/95 p-3 text-sm font-semibold text-amber-100 opacity-0 shadow-2xl shadow-black/40 backdrop-blur transition-[opacity,transform] md:p-4 md:text-base lg:p-5 lg:text-lg"
              >
                {@notification}
              </div>
            <% end %>
            <%= if latest_result do %>
              <div
                id="game-result-toast"
                phx-hook="ToastHook"
                data-toast-key={result_toast_key(@game_id, @game_state, latest_result_key)}
                role="status"
                class="translate-y-2 rounded-lg border border-sky-300/40 bg-stone-950/95 p-3 text-sm text-sky-100 opacity-0 shadow-2xl shadow-black/40 backdrop-blur transition-[opacity,transform] md:p-4 md:text-base lg:p-5 lg:text-lg"
              >
                <span class="block font-semibold">{latest_result}</span>
              </div>
            <% end %>
            <%= if @artwork_reveal_toast do %>
              <div
                id="artwork-reveal-toast"
                phx-hook="ToastHook"
                data-toast-key={
                  artwork_reveal_toast_key(@game_id, @game_state, @artwork_reveal_toast)
                }
                role="status"
                class="translate-y-2 rounded-lg border border-amber-300/50 bg-stone-950/95 p-3 text-sm font-semibold text-amber-100 opacity-0 shadow-2xl shadow-black/40 backdrop-blur transition-[opacity,transform] md:p-4 md:text-base lg:p-5 lg:text-lg"
              >
                {@artwork_reveal_toast.message}
              </div>
            <% end %>
          </div>
        <% end %>
        <%= if @turn_banner_key do %>
          <div
            id="turn-banner"
            phx-hook="TurnBannerHook"
            data-turn-banner-key={@turn_banner_key}
            data-turn-banner-duration="3000"
            data-turn-banner-chime="loud"
            role="status"
            aria-live="assertive"
            class="pointer-events-none fixed inset-0 z-50 flex items-center justify-center px-4"
          >
            <div
              data-turn-banner-panel
              data-turn-banner-dismissible="true"
              data-turn-banner-size="massive"
              tabindex="-1"
              aria-label="Dismiss your turn banner"
              class="pointer-events-none max-w-full translate-y-4 scale-95 cursor-pointer rounded-lg border-4 border-amber-200 bg-stone-950/90 px-6 py-5 text-center text-[clamp(3rem,18vw,10rem)] font-black uppercase leading-none tracking-normal text-amber-100 opacity-0 shadow-2xl shadow-amber-950/50 backdrop-blur-sm transition-[opacity,transform] duration-200 sm:px-10 sm:py-7"
            >
              Your Turn
            </div>
          </div>
        <% end %>
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

  def round_review_panel(assigns) do
    assigns = assign(assigns, :round_result, List.last(assigns.game_state.round_results))

    ~H"""
    <section
      id="round-review-panel"
      class="space-y-3 rounded-lg border border-amber-300/40 bg-amber-300/10 p-3"
    >
      <h2 class="text-sm font-black uppercase tracking-[0.18em] text-amber-100">
        Round {@game_state.round_number} review
      </h2>
      <p :if={@round_result} id="round-review-summary" class="text-sm text-stone-200">
        {player_name(@game_state, @round_result.thief_player_id)} stole {@round_result.stolen_count} {artwork_word(
          @round_result.stolen_count
        )}.
      </p>
      <p class="text-xs font-semibold text-stone-400">
        Review the thief route before setup begins for the next round.
      </p>
      <button
        :if={review_host?(@game_state, @player_id)}
        id="start-next-round-button"
        type="button"
        phx-click="start_next_round"
        class="inline-flex w-full items-center justify-center gap-2 rounded-md bg-amber-300 px-3 py-2 text-sm font-black text-stone-950 transition hover:bg-amber-200 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-200"
      >
        <.icon name="hero-arrow-right-circle-solid" class="size-4" /> Start next round
      </button>
      <p
        :if={!review_host?(@game_state, @player_id)}
        id="round-review-waiting"
        class="rounded-md border border-dashed border-stone-600 px-3 py-2 text-sm text-stone-400"
      >
        Waiting for host to start the next round.
      </p>
    </section>
    """
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true
  attr :pending_escape_entry, :atom, default: nil

  def turn_panel(assigns) do
    ~H"""
    <%= if turn_panel_visible?(@game_state, @player_id, @pending_escape_entry) do %>
      <div
        id="turn-panel"
        data-mobile-density="compact"
        class="space-y-2 rounded-lg border border-stone-700 bg-stone-900/80 p-1.5 lg:space-y-3 lg:p-2"
      >
        <%= if @game_state.dice do %>
          <.dice_readout dice={@game_state.dice} />
        <% end %>

        <.motion_decision_buttons game_state={@game_state} player_id={@player_id} />

        <%= if my_turn?(@game_state, @player_id) do %>
          <% can_end_turn? = turn_can_end?(@game_state) %>
          <div class="space-y-1.5 lg:space-y-2">
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
              disabled={!can_end_turn?}
              class={[
                "w-full rounded-md border px-3 py-1.5 text-xs font-bold transition lg:py-2 lg:text-sm",
                if(can_end_turn?,
                  do:
                    "border-amber-200 bg-amber-300 text-stone-950 shadow-lg shadow-amber-950/30 hover:border-amber-100 hover:bg-amber-200 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-200",
                  else: "cursor-not-allowed border-stone-700 bg-stone-900 text-stone-500"
                )
              ]}
            >
              {if(can_end_turn?, do: "End turn", else: "Move first")}
            </button>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  attr :dice, :any, required: true

  def dice_readout(assigns) do
    ~H"""
    <div
      id="dice-readout"
      data-dice-readout="visual"
      data-mobile-density="compact"
      class="flex items-center justify-center gap-1.5 rounded-md border border-stone-700 bg-stone-950/75 p-1.5 lg:gap-2 lg:p-2"
    >
      <.movement_die value={elem(@dice, 0)} />
      <.action_die :if={elem(@dice, 1)} action={elem(@dice, 1)} />
    </div>
    """
  end

  attr :value, :integer, required: true

  def movement_die(assigns) do
    ~H"""
    <div
      id="movement-die"
      data-die-kind="movement"
      data-die-value={@value}
      data-mobile-size="compact"
      aria-label={"Movement die: #{@value}"}
      class="relative size-9 rounded-md border-2 border-stone-200 bg-stone-50 shadow-lg shadow-black/30 lg:size-12 lg:rounded-lg xl:size-14"
    >
      <%= for position <- die_pip_positions(@value) do %>
        <span data-die-pip={@value} data-pip-position={position} class={die_pip_class(position)}>
        </span>
      <% end %>
    </div>
    """
  end

  attr :action, :atom, required: true

  def action_die(assigns) do
    ~H"""
    <div
      id="action-die"
      data-die-kind="action"
      data-die-action={action_die_value(@action)}
      data-mobile-size="compact"
      aria-label={"Action die: #{action_die_label(@action)}"}
      class="grid size-9 place-items-center rounded-md border-2 border-amber-200 bg-amber-100 text-stone-950 shadow-lg shadow-black/30 lg:size-12 lg:rounded-lg xl:size-14"
    >
      <span data-die-icon={action_die_value(@action)} class="grid place-items-center">
        <.icon name={action_die_icon(@action)} class="size-5 lg:size-7 xl:size-8" />
      </span>
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
        class="space-y-1.5 rounded-lg border border-amber-300/40 bg-amber-300/10 p-2 lg:space-y-2 lg:p-3"
      >
        <p class="text-xs font-semibold text-amber-50 lg:text-sm">
          Check this {escape_entry_type(@pending_escape_entry)} lock?
        </p>
        <button
          id="confirm-escape-button"
          type="button"
          phx-click="confirm_escape"
          class="w-full rounded-md bg-amber-300 px-3 py-1.5 text-xs font-black text-stone-950 transition hover:bg-amber-200 lg:py-2 lg:text-sm"
        >
          Check lock
        </button>
        <button
          id="cancel-escape-button"
          type="button"
          phx-click="cancel_escape"
          class="w-full rounded-md border border-amber-200/70 px-3 py-1.5 text-xs font-bold text-amber-50 transition hover:bg-amber-300/10 lg:py-2 lg:text-sm"
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
            data-mobile-density="compact"
            type="button"
            phx-click="look_pawn"
            class="w-full rounded-md bg-sky-300 px-3 py-1.5 text-xs font-black text-stone-950 transition hover:bg-sky-200 lg:py-2 lg:text-sm"
          >
            Look from pawn
          </button>
          <div
            id="camera-look-grid"
            data-mobile-layout="four-up"
            class="grid grid-cols-4 gap-1 lg:grid-cols-2 lg:gap-2"
          >
            <%= for {camera_id, camera} <- selectable_look_cameras(@game_state, @player_id) do %>
              <button
                id={"look-camera-#{camera_id}"}
                data-mobile-density="compact"
                type="button"
                phx-click="look_camera"
                phx-value-camera_id={camera_id}
                class="rounded-md border border-sky-300/60 px-1 py-1.5 text-[0.68rem] font-bold leading-tight text-sky-100 transition hover:bg-sky-300/10 lg:px-2 lg:py-2 lg:text-xs"
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
            class="w-full rounded-md bg-sky-300 px-3 py-1.5 text-xs font-black text-stone-950 transition hover:bg-sky-200 lg:py-2 lg:text-sm"
          >
            Camera scan
          </button>
        <% :motion -> %>
          <%= if motion_decision_pending?(@game_state) do %>
            <p
              id="motion-decision-waiting"
              class="rounded-md border border-dashed border-stone-600 px-3 py-1.5 text-xs text-stone-400 lg:py-2 lg:text-sm"
            >
              Waiting for the thief to choose the motion reading.
            </p>
          <% else %>
            <button
              id="motion-detector-button"
              type="button"
              phx-click="motion_detector"
              class="w-full rounded-md bg-sky-300 px-3 py-1.5 text-xs font-black text-stone-950 transition hover:bg-sky-200 lg:py-2 lg:text-sm"
            >
              Motion detector
            </button>
          <% end %>
      <% end %>
    <% end %>
    """
  end

  defp selectable_look_cameras(state, player_id) do
    state.cameras
    |> Enum.filter(fn {_camera_id, camera} ->
      camera != nil and visible_camera_status(state, player_id, camera) == :active
    end)
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true

  def motion_decision_buttons(assigns) do
    ~H"""
    <%= if motion_decision_buttons_visible?(@game_state, @player_id) do %>
      <div
        id="motion-decision-panel"
        class="space-y-1.5 rounded-lg border border-cyan-300/40 bg-cyan-300/10 p-2 lg:space-y-2 lg:p-3"
      >
        <p class="text-xs font-semibold text-cyan-50 lg:text-sm">Motion detector choice</p>
        <button
          id="allow-motion-button"
          type="button"
          phx-click="motion_detector_decision"
          phx-value-decision="allow"
          class="w-full rounded-md bg-cyan-300 px-3 py-1.5 text-xs font-black text-stone-950 transition hover:bg-cyan-200 lg:py-2 lg:text-sm"
        >
          Allow reading
        </button>
        <button
          id="snip-motion-button"
          type="button"
          phx-click="motion_detector_decision"
          phx-value-decision="cut"
          class="w-full rounded-md border border-cyan-200/70 px-3 py-1.5 text-xs font-bold text-cyan-50 transition hover:bg-cyan-300/10 lg:py-2 lg:text-sm"
        >
          Cut reading ({@game_state.motion_snips_remaining})
        </button>
      </div>
    <% end %>
    """
  end

  attr :game_state, :map, required: true
  attr :selected_revealed_round, :integer, default: nil
  attr :replay_payload, :list, default: []

  def full_game_scoreboard(assigns) do
    ~H"""
    <section
      id="full-game-scoreboard"
      class="space-y-2 rounded-lg border border-amber-300/40 bg-amber-300/10 p-2 lg:space-y-3 lg:p-3"
    >
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-[0.68rem] font-black uppercase leading-none tracking-[0.18em] text-amber-100 lg:text-sm">
          Full game
        </h2>
        <span
          id="round-status"
          class="shrink-0 rounded bg-stone-950/70 px-2 py-1 text-[0.68rem] font-bold text-stone-200"
        >
          {round_status(@game_state)}
        </span>
      </div>
      <ul class="grid grid-cols-[repeat(auto-fit,minmax(5.5rem,1fr))] gap-1 lg:block lg:space-y-2">
        <%= for player_id <- score_order(@game_state) do %>
          <li
            id={"score-#{player_id}"}
            class={[
              "flex min-h-9 items-center justify-between gap-2 rounded-md border px-2 py-1 text-xs lg:px-3 lg:py-2 lg:text-sm",
              if(player_id == @game_state.thief_player_id and @game_state.phase != :game_over,
                do: "border-amber-300 bg-amber-300/15",
                else: "border-stone-700 bg-stone-950/50"
              )
            ]}
          >
            <span class="min-w-0 truncate font-semibold text-stone-100">
              {player_name(@game_state, player_id)}
            </span>
            <span class="shrink-0 font-black text-amber-100">
              <span data-score-format="compact" class="lg:hidden">
                {score_count(@game_state, player_id)}
              </span>
              <span data-score-format="full" class="hidden lg:inline">
                {score_for(@game_state, player_id)}
              </span>
            </span>
          </li>
        <% end %>
      </ul>
      <.route_round_selector
        :if={
          @game_state.phase == :round_review and thief_histories_present?(@game_state.round_results)
        }
        game_state={@game_state}
        selected_revealed_round={@selected_revealed_round}
      />
      <.replay_panel
        :if={@game_state.phase == :round_review}
        game_state={@game_state}
        selected_revealed_round={@selected_revealed_round}
        replay_payload={@replay_payload}
      />
    </section>
    """
  end

  attr :game_state, :map, required: true
  attr :selected_revealed_round, :integer, default: nil
  attr :replay_payload, :list, default: []

  def game_over_panel(assigns) do
    ~H"""
    <div id="game-over-panel" class="rounded-lg border border-emerald-300/40 bg-emerald-300/10 p-3">
      <h2 class="text-sm font-black uppercase tracking-[0.18em] text-emerald-100">Game Over</h2>
      <%= if full_game?(@game_state) do %>
        <p id="full-game-winner" class="mt-2 text-sm text-stone-200">
          Winner: <strong class="text-stone-50">{winner_names(@game_state)}</strong>
        </p>
        <.route_round_selector
          :if={thief_histories_present?(@game_state.round_results)}
          game_state={@game_state}
          selected_revealed_round={@selected_revealed_round}
        />
        <.replay_panel
          game_state={@game_state}
          selected_revealed_round={@selected_revealed_round}
          replay_payload={@replay_payload}
        />
        <ul id="round-report" class="mt-3 space-y-1 text-sm text-stone-300">
          <%= for result <- @game_state.round_results do %>
            <li id={"round-report-#{result.round_number}"} class="space-y-2">
              <p>
                Round {result.round_number}: {player_name(@game_state, result.thief_player_id)} stole {result.stolen_count} {artwork_word(
                  result.stolen_count
                )}.
              </p>
            </li>
          <% end %>
        </ul>
      <% else %>
        <p class="mt-2 text-sm text-stone-200">
          Winner: <strong class="capitalize text-stone-50">{@game_state.winner}</strong>
        </p>
        <p class="text-sm text-stone-400">
          Reason: {game_over_reason_label(@game_state.game_over_reason)}
        </p>
        <.thief_route_history history={@game_state.thief_history} />
        <.replay_panel
          game_state={@game_state}
          selected_revealed_round={@selected_revealed_round}
          replay_payload={@replay_payload}
        />
      <% end %>
    </div>
    """
  end

  attr :game_state, :map, required: true
  attr :selected_revealed_round, :integer, default: nil
  attr :replay_payload, :list, default: []

  def replay_panel(assigns) do
    ~H"""
    <section
      :if={@replay_payload != []}
      id="replay-panel"
      class="space-y-3 rounded-lg border border-sky-300/25 bg-slate-950/70 p-3 shadow-[0_0.65rem_1.5rem_rgba(2,6,23,0.2)] backdrop-blur-sm"
    >
      <div class="flex items-center justify-between gap-2">
        <h3 class="text-[0.68rem] font-black uppercase tracking-[0.16em] text-sky-100/90">
          Replay
        </h3>
      </div>
      <div
        id="replay-playback"
        phx-hook="ReplayPlaybackHook"
        phx-update="ignore"
        data-replay-events={replay_events_json(@replay_payload)}
        data-replay-event-count={length(@replay_payload)}
        class="space-y-2.5"
      >
        <div
          id="replay-review-mode-toggle"
          class="grid grid-cols-2 gap-1 rounded-md border border-sky-200/25 bg-slate-950 p-1"
        >
          <button
            type="button"
            data-replay-mode="path"
            aria-pressed="true"
            class="min-h-8 rounded px-2 text-xs font-black text-sky-100 transition hover:bg-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-100"
          >
            Finished path
          </button>
          <button
            type="button"
            data-replay-mode="replay"
            aria-pressed="false"
            class="min-h-8 rounded px-2 text-xs font-black text-sky-100 transition hover:bg-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-100"
          >
            Replay
          </button>
        </div>
        <p
          data-replay-caption
          class="min-h-5 text-sm font-semibold leading-5 text-sky-50/95"
        >
        </p>
        <div class="flex flex-wrap items-center gap-1.5">
          <button
            type="button"
            aria-label="Step back"
            data-replay-command="back"
            class={replay_control_class()}
          >
            <.icon name="hero-backward" class="size-4" />
          </button>
          <button
            type="button"
            aria-label="Play replay"
            data-replay-command="play"
            class={replay_control_class()}
          >
            <span data-replay-play-icon>
              <.icon name="hero-play" class="size-4" />
            </span>
            <span data-replay-pause-icon class="hidden">
              <.icon name="hero-pause" class="size-4" />
            </span>
          </button>
          <button
            type="button"
            aria-label="Step forward"
            data-replay-command="forward"
            class={replay_control_class()}
          >
            <.icon name="hero-forward" class="size-4" />
          </button>
          <button
            type="button"
            aria-label="Restart replay"
            data-replay-command="restart"
            class={replay_control_class()}
          >
            <.icon name="hero-arrow-path" class="size-4" />
          </button>
          <select
            aria-label="Replay speed"
            data-replay-speed
            class="min-h-8 rounded-md border border-sky-200/35 bg-slate-950 px-2 py-1 text-xs font-bold text-sky-50 transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-100"
          >
            <option value="0.5">0.5x</option>
            <option value="1" selected>1x</option>
            <option value="2">2x</option>
          </select>
        </div>
      </div>
    </section>
    """
  end

  attr :game_state, :map, required: true
  attr :selected_revealed_round, :integer, default: nil

  def route_round_selector(assigns) do
    ~H"""
    <div id="route-round-selector" class="space-y-2 border-t border-amber-300/20 pt-2">
      <h3 class="text-[0.62rem] font-black uppercase tracking-[0.16em] text-amber-100">
        Revealed route
      </h3>
      <div class="grid grid-cols-[repeat(auto-fit,minmax(4.75rem,1fr))] gap-1">
        <%= for result <- route_selectable_results(@game_state) do %>
          <button
            id={"select-route-round-#{result.round_number}"}
            type="button"
            phx-click="select_route_round"
            phx-value-round={result.round_number}
            aria-pressed={to_string(result.round_number == @selected_revealed_round)}
            class={[
              "rounded-md border px-2 py-1 text-xs font-black transition",
              if(result.round_number == @selected_revealed_round,
                do: "border-sky-200 bg-sky-300 text-stone-950",
                else:
                  "border-stone-700 bg-stone-950/60 text-stone-200 hover:border-sky-200 hover:text-sky-100"
              )
            ]}
          >
            Round {result.round_number}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :route_marks, :list, default: []

  def thief_route_cell_overlay(assigns) do
    ~H"""
    <span
      :if={@route_marks != []}
      data-thief-route-cell
      class="pointer-events-none absolute inset-0 z-[18]"
    >
      <span
        :for={mark <- @route_marks}
        data-thief-route={mark.kind}
        data-route-round={mark.round}
        data-route-direction={Map.get(mark, :direction)}
        data-thief-route-stop={Map.get(mark, :stop)}
        data-thief-route-stop-dot={if(mark.kind == "stop", do: "")}
        data-thief-route-arrow-outline={if(mark.kind == "path", do: "")}
        data-thief-route-label={route_label_kind(mark)}
        class={route_mark_class(mark)}
      >
        <span class="sr-only">Thief route {mark.kind}</span>
        {route_mark_label_text(mark)}
      </span>
    </span>
    """
  end

  attr :history, :map, required: true
  attr :id, :string, default: "thief-route-history"
  attr :title, :string, default: "Thief route"

  def thief_route_history(assigns) do
    ~H"""
    <section
      :if={thief_history_present?(@history)}
      id={@id}
      class="mt-3 rounded-md border border-sky-300/30 bg-sky-300/10 p-3 text-sm"
    >
      <h3 class="text-[0.68rem] font-black uppercase tracking-[0.16em] text-sky-100">
        {@title}
      </h3>
      <p
        :if={@history.entry}
        id={route_summary_dom_id(@id)}
        class="mt-2 flex flex-wrap items-center gap-1.5 text-stone-200"
      >
        <span class="text-xs font-black uppercase tracking-[0.12em] text-stone-400">Entry</span>
        <span
          id={route_entry_dom_id(@id)}
          class="rounded bg-stone-950/70 px-2 py-1 text-xs font-black text-sky-100"
        >
          {route_entry_label(@history.entry)}
        </span>
        <span class="text-xs font-black uppercase tracking-[0.12em] text-stone-500">to</span>
        <span class="rounded border border-stone-700 bg-stone-950/50 px-2 py-1 text-xs font-bold text-stone-300">
          {route_summary_final_label(@history)}
        </span>
      </p>
    </section>
    """
  end

  defp thief_histories_present?(round_results) do
    Enum.any?(round_results, fn result ->
      thief_history_present?(Map.get(result, :thief_history))
    end)
  end

  defp route_selectable_results(game_state) do
    Enum.filter(game_state.round_results, fn result ->
      revealed_route_round_available?(result)
    end)
  end

  defp thief_history_present?(%{entry: entry, moves: moves}), do: entry != nil or moves != []
  defp thief_history_present?(_history), do: false

  defp revealed_route_round_available?(result) when is_map(result) do
    thief_history_present?(Map.get(result, :thief_history))
  end

  defp revealed_route_round_available?(_result), do: false

  defp replay_events_present?(%{replay_events: events}) when is_list(events), do: events != []
  defp replay_events_present?(_result), do: false

  defp selected_revealed_round(_selected_round, nil, game_state) do
    latest_revealed_round_number(game_state)
  end

  defp selected_revealed_round(selected_round, previous_state, game_state) do
    previous_latest = latest_revealed_round_number(previous_state)
    latest = latest_revealed_round_number(game_state)

    cond do
      latest != previous_latest -> latest
      selectable_revealed_round?(game_state, selected_round) -> selected_round
      true -> latest
    end
  end

  defp selectable_revealed_round(game_state, round_number) do
    if selectable_revealed_round?(game_state, round_number) do
      round_number
    else
      latest_revealed_round_number(game_state)
    end
  end

  defp selectable_revealed_round?(game_state, round_number) when is_integer(round_number) do
    Enum.any?(game_state.round_results, fn result ->
      result.round_number == round_number and
        revealed_route_round_available?(result)
    end)
  end

  defp selectable_revealed_round?(_game_state, _round_number), do: false

  defp latest_revealed_round_number(game_state) do
    game_state.round_results
    |> Enum.filter(&revealed_route_round_available?/1)
    |> List.last()
    |> case do
      nil -> nil
      result -> result.round_number
    end
  end

  defp revealed_route_marks(%{phase: phase} = game_state, selected_round)
       when phase in [:round_review, :game_over] and is_integer(selected_round) do
    game_state.round_results
    |> Enum.find(&(&1.round_number == selected_round))
    |> case do
      nil -> %{}
      result -> route_marks(Map.get(result, :thief_history), selected_round)
    end
  end

  defp revealed_route_marks(%{phase: :game_over, thief_history: history}, nil) do
    if thief_history_present?(history) do
      route_marks(history, "current")
    else
      %{}
    end
  end

  defp revealed_route_marks(_game_state, _selected_round), do: %{}

  defp selected_replay_payload(%{phase: :round_review} = game_state, selected_round) do
    game_state
    |> replay_events_for_selected_round(selected_round)
    |> Replay.payload_events(game_state)
  end

  defp selected_replay_payload(
         %{phase: :game_over, game_mode: :full} = game_state,
         selected_round
       ) do
    game_state
    |> replay_events_for_selected_round(selected_round)
    |> Replay.payload_events(game_state)
  end

  defp selected_replay_payload(
         %{phase: :game_over, game_mode: :limited} = game_state,
         _selected_round
       ) do
    Replay.payload_events(game_state.replay_events, game_state)
  end

  defp selected_replay_payload(_game_state, _selected_round), do: []

  defp replay_events_for_selected_round(game_state, selected_round)
       when is_integer(selected_round),
       do: replay_events_for_round(game_state, selected_round)

  defp replay_events_for_selected_round(game_state, _selected_round),
    do: replay_events_for_round(game_state, latest_replay_round_number(game_state))

  defp latest_replay_round_number(game_state) do
    game_state.round_results
    |> Enum.filter(&replay_events_present?/1)
    |> List.last()
    |> case do
      nil -> nil
      result -> result.round_number
    end
  end

  defp replay_events_for_round(game_state, selected_round) when is_integer(selected_round) do
    game_state.round_results
    |> Enum.find(&(&1.round_number == selected_round))
    |> case do
      %{replay_events: events} when is_list(events) -> events
      _result -> []
    end
  end

  defp replay_events_for_round(_game_state, _selected_round), do: []

  defp replay_control_class do
    "inline-flex min-h-8 items-center justify-center rounded-md border border-sky-200/35 bg-slate-950 px-2 text-xs font-black text-sky-100 transition duration-150 hover:border-sky-100 hover:bg-slate-900 hover:text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sky-100 disabled:cursor-not-allowed disabled:opacity-45"
  end

  defp replay_events_json(payload) do
    Phoenix.json_library().encode!(payload)
  end

  defp route_marks(history, round) when is_map(history) do
    round = to_string(round)
    positions = thief_route_positions(history)

    []
    |> add_path_marks(positions, round)
    |> add_stop_marks(history, round)
    |> add_entry_mark(history, round)
    |> add_exit_mark(history, round)
    |> Enum.group_by(& &1.position, &Map.delete(&1, :position))
  end

  defp route_marks(_history, _round), do: %{}

  defp add_path_marks(marks, positions, round) do
    positions
    |> Enum.zip(Enum.drop(positions, 1))
    |> Enum.reduce(marks, fn {position, next_position}, marks ->
      direction = route_direction(position, next_position)

      [
        %{
          kind: "path",
          round: round,
          position: position,
          direction: direction,
          label: route_direction_glyph(direction)
        }
        | marks
      ]
    end)
  end

  defp add_stop_marks(marks, %{moves: moves}, round) when is_list(moves) do
    moves
    |> Enum.with_index(1)
    |> Enum.reduce(marks, fn {move, index}, marks ->
      case move |> Map.get(:path, []) |> List.last() do
        nil ->
          marks

        position ->
          [
            %{
              kind: "stop",
              round: round,
              position: position,
              stop: index,
              label: Integer.to_string(index)
            }
            | marks
          ]
      end
    end)
  end

  defp add_stop_marks(marks, _history, _round), do: marks

  defp add_entry_mark(marks, %{entry: %{position: position} = entry}, round) do
    [
      %{
        kind: "entry",
        round: round,
        position: route_entry_marker_position(entry, position),
        label: "ENTRY #{route_entry_label(entry)}"
      }
      | marks
    ]
  end

  defp add_entry_mark(marks, _history, _round), do: marks

  defp add_exit_mark(marks, %{exit: %{label: label, position: position}}, round) do
    [%{kind: "exit", round: round, position: position, label: "EXIT #{label}"} | marks]
  end

  defp add_exit_mark(marks, _history, _round), do: marks

  defp route_entry_marker_position(%{id: id}, fallback_position) do
    case Board.entry_by_id(id) do
      nil -> fallback_position
      entry -> Board.exit_door_cell(entry)
    end
  end

  defp route_entry_marker_position(_entry, fallback_position), do: fallback_position

  defp thief_route_positions(%{entry: %{position: entry_pos}} = history) do
    history
    |> Map.get(:moves, [])
    |> Enum.flat_map(&Map.get(&1, :path, []))
    |> prepend_entry_position(entry_pos)
    |> Enum.dedup()
  end

  defp thief_route_positions(_history), do: []

  defp prepend_entry_position([], entry_pos), do: [entry_pos]
  defp prepend_entry_position([entry_pos | _rest] = positions, entry_pos), do: positions
  defp prepend_entry_position(positions, entry_pos), do: [entry_pos | positions]

  defp route_direction({row, col}, {row, next_col}) when next_col == col + 1, do: "east"
  defp route_direction({row, col}, {row, next_col}) when next_col == col - 1, do: "west"
  defp route_direction({row, col}, {next_row, col}) when next_row == row + 1, do: "south"
  defp route_direction({row, col}, {next_row, col}) when next_row == row - 1, do: "north"
  defp route_direction(_position, _next_position), do: nil

  defp route_direction_glyph("east"), do: "→"
  defp route_direction_glyph("west"), do: "←"
  defp route_direction_glyph("north"), do: "↑"
  defp route_direction_glyph("south"), do: "↓"
  defp route_direction_glyph(_direction), do: ""

  defp route_mark_label_text(%{label: label}), do: label
  defp route_mark_label_text(_mark), do: ""

  defp route_label_kind(%{kind: kind}) when kind in ["entry", "exit"], do: kind
  defp route_label_kind(_mark), do: nil

  defp route_mark_class(%{kind: "entry"}) do
    "absolute left-0.5 top-0.5 rounded bg-sky-300 px-1 py-0.5 text-[0.48rem] font-black leading-none text-stone-950 shadow"
  end

  defp route_mark_class(%{kind: "exit"}) do
    "absolute bottom-0.5 left-0.5 rounded bg-amber-300 px-1 py-0.5 text-[0.48rem] font-black leading-none text-stone-950 shadow"
  end

  defp route_mark_class(%{kind: "stop"}) do
    "absolute right-0.5 top-0.5 grid size-5 place-items-center rounded-full border-2 border-stone-950 bg-amber-100 text-[0.68rem] font-black leading-none text-stone-950 shadow-[0_0_0.55rem_rgba(251,191,36,0.65)]"
  end

  defp route_mark_class(%{kind: "path"}) do
    "route-path-arrow absolute inset-0 grid place-items-center text-[1.35rem] font-black leading-none"
  end

  defp route_entry_dom_id("thief-route-history"), do: "thief-route-entry"
  defp route_entry_dom_id(id), do: "#{id}-entry"

  defp route_summary_dom_id("thief-route-history"), do: "thief-route-summary"
  defp route_summary_dom_id(id), do: "#{id}-summary"

  defp route_entry_label(%{label: label}), do: label
  defp route_entry_label(%{id: id}), do: entry_label(id)
  defp route_entry_label(_entry), do: "Entry"

  defp route_summary_final_label(history) do
    history
    |> thief_route_positions()
    |> List.last()
    |> case do
      nil -> "Unknown"
      pos -> position_label(pos)
    end
  end

  defp position_label(pos), do: position_key(pos)

  defp maybe_join_game(socket, player_name, player_color) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MuseumCaper.PubSub, "game:#{socket.assigns.game_id}")

      if player_name != "" do
        join_current_player(socket, player_name, player_color)
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

  defp available_join_pawn_color(state, player_id, requested_color) do
    case PawnColors.normalize(requested_color) do
      {:ok, nil} ->
        default_pawn_color(state, player_id)

      {:ok, color} ->
        if pawn_color_taken?(state, player_id, color) do
          default_pawn_color(state, player_id)
        else
          PawnColors.to_param(color)
        end

      {:error, :invalid_color} ->
        requested_color
    end
  end

  defp requested_or_default_pawn_color(requested_color, state, player_id) do
    case PawnColors.normalize(requested_color) do
      {:ok, nil} -> default_pawn_color(state, player_id)
      _result -> requested_color
    end
  end

  defp default_pawn_color(state, player_id) do
    state.players
    |> Map.delete(player_id)
    |> PawnColors.next_available()
    |> case do
      nil -> PawnColors.default()
      color -> color
    end
    |> PawnColors.to_param()
  end

  defp pawn_color_taken?(state, player_id, color) do
    Enum.any?(state.players, fn {id, player} -> id != player_id and player.color == color end)
  end

  defp taken_pawn_colors(state, player_id) do
    state.players
    |> Enum.reject(fn {id, _player} -> id == player_id end)
    |> Enum.map(fn {_id, player} -> player.color end)
  end

  defp join_current_player(socket, player_name, player_color) do
    case Server.add_player(
           socket.assigns.server,
           socket.assigns.player_id,
           player_name,
           player_color
         ) do
      :ok -> refresh_state(socket, nil)
      {:error, :room_full} -> put_notice(socket, "This room already has four players.")
      {:error, :game_started} -> put_notice(socket, "This game has already started.")
      {:error, :color_taken} -> put_notice(socket, "That pawn color is already taken.")
      {:error, :invalid_color} -> put_notice(socket, "Choose a valid pawn color.")
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

    case current_external_door_escape_entry_for_cell(state, socket.assigns.player_id, pos) do
      %{id: entry_id} ->
        {:noreply, assign(socket, pending_escape_entry: entry_id, notification: nil)}

      nil ->
        handle_non_current_escape_click(socket, state, pos)
    end
  end

  defp handle_non_current_escape_click(socket, state, pos) do
    if current_space_before_move?(state, socket.assigns.player_id, pos) do
      {:noreply, put_notice(socket, "Choose a different space.")}
    else
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
    detective_id = next_unplaced_detective_id(state, socket.assigns.player_id)

    with :ok <- validate_own_detective_pawn(state, detective_id) do
      Server.place_detective_pawn(socket.assigns.server, detective_id, pos)
    end
  end

  defp handle_move_click(socket, pos) do
    state = socket.assigns.game_state

    if not my_turn?(state, socket.assigns.player_id) do
      {:noreply, put_notice(socket, "It is not your turn.")}
    else
      result =
        case player_role(state, socket.assigns.player_id) do
          :thief ->
            Server.move_thief(socket.assigns.server, pos)

          :detective ->
            detective_id = active_detective_id(state, socket.assigns.player_id)
            Server.move_detective(socket.assigns.server, detective_id, pos)

          _ ->
            {:error, :not_a_player}
        end

      case result do
        {:ok, _state} ->
          pending_escape_entry =
            pending_escape_after_move(state, socket.assigns.player_id, pos)

          socket = assign(socket, :pending_escape_entry, pending_escape_entry)
          {:noreply, refresh_state(socket, nil)}

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
        {:noreply, refresh_state(socket, nil)}

      {:error, :invalid_move} ->
        {:noreply, put_notice(socket, "That move is not legal.")}

      {:error, _reason} ->
        {:noreply, put_notice(socket, "Could not move that piece.")}
    end
  end

  defp handle_escape(socket, exit_id) do
    case Server.try_escape(socket.assigns.server, exit_id) do
      {:ok, result} ->
        message = escape_result_message(result, exit_id)

        socket = assign(socket, :pending_escape_entry, nil)

        {:noreply, refresh_state(socket, message)}

      {:error, _reason} ->
        {:noreply, put_notice(socket, "The thief must be at that door or window.")}
    end
  end

  defp refresh_state(socket, message) do
    previous_state = Map.get(socket.assigns, :game_state)
    game_state = Server.get_state(socket.assigns.server)
    previous_turn = assigned_banner_turn(previous_state, game_state)

    selected_revealed_round =
      selected_revealed_round(socket.assigns.selected_revealed_round, previous_state, game_state)

    replay_payload = selected_replay_payload(game_state, selected_revealed_round)

    socket
    |> assign(
      game_state: game_state,
      revealed_mark_keys:
        revealed_mark_keys(previous_state, game_state, socket.assigns.player_id),
      animated_mark_keys:
        animated_mark_keys(previous_state, game_state, socket.assigns.player_id),
      selected_revealed_round: selected_revealed_round,
      revealed_route_marks: revealed_route_marks(game_state, selected_revealed_round),
      replay_payload: replay_payload,
      artwork_reveal_toast:
        artwork_reveal_toast(previous_state, game_state, socket.assigns.player_id)
    )
    |> maybe_show_turn_banner(previous_turn, game_state)
    |> put_notification(notification_message(message, game_state))
  end

  defp maybe_show_turn_banner(socket, previous_turn, game_state) do
    current_turn = banner_turn_player(game_state)
    player_id = socket.assigns.player_id

    cond do
      current_turn == player_id and current_turn != previous_turn and
          Map.has_key?(game_state.players, player_id) ->
        assign(socket, :turn_banner_key, System.unique_integer([:positive]))

      current_turn != player_id ->
        assign(socket, :turn_banner_key, nil)

      true ->
        socket
    end
  end

  defp assigned_banner_turn(previous_state, fallback_state) do
    case previous_state do
      nil -> banner_turn_player(fallback_state)
      state -> banner_turn_player(state)
    end
  end

  defp banner_turn_player(%{phase: :thief_entry, thief_player_id: thief_id}), do: thief_id
  defp banner_turn_player(state), do: turn_player_id(state)

  defp revealed_mark_keys(nil, _game_state, _player_id), do: []

  defp revealed_mark_keys(previous_state, game_state, player_id) do
    if player_role(game_state, player_id) == :detective do
      painting_reveal_keys(previous_state, game_state, player_id) ++
        camera_reveal_keys(previous_state, game_state, player_id)
    else
      []
    end
  end

  defp next_revealed_mark_keys(socket, previous_state, game_state) do
    if previous_state == game_state do
      socket.assigns.revealed_mark_keys
    else
      revealed_mark_keys(previous_state, game_state, socket.assigns.player_id)
    end
  end

  defp next_artwork_reveal_toast(socket, previous_state, game_state) do
    if previous_state == game_state do
      socket.assigns.artwork_reveal_toast
    else
      artwork_reveal_toast(previous_state, game_state, socket.assigns.player_id)
    end
  end

  defp animated_mark_keys(nil, _game_state, _player_id), do: %{}

  defp animated_mark_keys(previous_state, game_state, player_id) do
    if pawn_movement_animation_enabled?(previous_state, game_state, player_id) do
      previous_state
      |> detective_movement_animation_keys(game_state)
      |> Map.merge(thief_movement_animation_keys(previous_state, game_state, player_id))
    else
      %{}
    end
  end

  defp next_animated_mark_keys(socket, previous_state, game_state) do
    if previous_state == game_state do
      socket.assigns.animated_mark_keys
    else
      animated_mark_keys(previous_state, game_state, socket.assigns.player_id)
    end
  end

  defp pawn_movement_animation_enabled?(previous_state, game_state, player_id) do
    previous_state.phase == :playing and game_state.phase == :playing and
      Map.has_key?(game_state.players, player_id)
  end

  defp detective_movement_animation_keys(previous_state, game_state) do
    Enum.reduce(game_state.detective_positions, %{}, fn {detective_id, new_pos}, keys ->
      previous_pos = Map.get(previous_state.detective_positions, detective_id)

      if moved_position?(previous_pos, new_pos) do
        Map.put(
          keys,
          pawn_animation_identity({:detective, detective_id}),
          pawn_movement_animation_key({:detective, detective_id}, previous_pos, new_pos)
        )
      else
        keys
      end
    end)
  end

  defp thief_movement_animation_keys(previous_state, game_state, player_id) do
    if thief_visible_to?(previous_state, player_id) and thief_visible_to?(game_state, player_id) and
         moved_position?(previous_state.thief_position, game_state.thief_position) do
      %{
        pawn_animation_identity(:thief) =>
          pawn_movement_animation_key(
            :thief,
            previous_state.thief_position,
            game_state.thief_position
          )
      }
    else
      %{}
    end
  end

  defp moved_position?(nil, _new_pos), do: false
  defp moved_position?(_previous_pos, nil), do: false
  defp moved_position?(pos, pos), do: false
  defp moved_position?(_previous_pos, _new_pos), do: true

  defp thief_visible_to?(state, player_id) do
    player_role(state, player_id) == :thief or state.chase_mode or state.phase == :game_over
  end

  defp pawn_animation_identity({:detective, detective_id}), do: "detective:#{detective_id}"
  defp pawn_animation_identity(:thief), do: "thief"

  defp pawn_movement_animation_key({:detective, detective_id}, previous_pos, new_pos) do
    "move:detective:#{detective_id}:#{position_key(previous_pos)}:#{position_key(new_pos)}"
  end

  defp pawn_movement_animation_key(:thief, previous_pos, new_pos) do
    "move:thief:#{position_key(previous_pos)}:#{position_key(new_pos)}"
  end

  defp position_key({row, col}), do: "#{row}-#{col}"

  defp painting_reveal_keys(previous_state, game_state, player_id) do
    previous_state
    |> painting_reveal_entries(game_state, player_id)
    |> Enum.map(fn {_pos, label} ->
      mark_reveal_key({:painting, label, :removed})
    end)
  end

  defp artwork_reveal_toast(nil, _game_state, _player_id), do: nil

  defp artwork_reveal_toast(previous_state, game_state, player_id) do
    if player_role(game_state, player_id) == :detective do
      previous_state
      |> painting_reveal_entries(game_state, player_id)
      |> List.first()
      |> case do
        nil ->
          nil

        {_pos, label} ->
          %{
            key: mark_reveal_key({:painting, label, :removed}),
            message: "Artwork #{label} stolen."
          }
      end
    end
  end

  defp painting_reveal_entries(previous_state, game_state, player_id) do
    game_state.paintings
    |> Enum.filter(fn {pos, status} ->
      status == :removed and visible_painting_status(previous_state, player_id, pos) != :removed
    end)
    |> Enum.map(fn {pos, _status} ->
      {pos, painting_label(game_state, pos)}
    end)
  end

  defp camera_reveal_keys(previous_state, game_state, player_id) do
    game_state.cameras
    |> Enum.filter(fn {camera_id, camera} ->
      camera != nil and visible_camera_status(game_state, player_id, camera) == :disabled and
        visible_camera_status_for_id(previous_state, player_id, camera_id) != :disabled
    end)
    |> Enum.map(fn {camera_id, _camera} -> mark_reveal_key({:camera, camera_id, :disabled}) end)
  end

  defp visible_painting_status(state, player_id, pos) do
    case Map.get(state.paintings, pos) do
      :targeted ->
        if player_role(state, player_id) == :thief, do: :targeted, else: :present

      status ->
        status
    end
  end

  defp visible_camera_status_for_id(state, player_id, camera_id) do
    case Map.get(state.cameras, camera_id) do
      nil -> nil
      camera -> visible_camera_status(state, player_id, camera)
    end
  end

  defp put_notice(socket, message), do: put_notification(socket, message)

  defp put_notification(socket, nil), do: assign(socket, notification: nil, notification_id: nil)

  defp put_notification(socket, message) do
    assign(socket, notification: message, notification_id: System.unique_integer([:positive]))
  end

  defp notification_message(nil, _state), do: nil

  defp notification_message(message, state) do
    if latest_detective_result(state) == message, do: nil, else: message
  end

  defp pending_escape_after_move(state, player_id, pos) do
    if player_role(state, player_id) == :thief do
      pos
      |> post_move_escape_entries()
      |> List.first()
      |> case do
        nil -> nil
        entry -> entry.id
      end
    end
  end

  defp post_move_escape_entries(pos) do
    Enum.filter(Board.entries_for_cell(pos), fn entry -> entry.type == :window end) ++
      Board.exits_for_cell(pos)
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

  defp validate_own_detective_pawn(_state, nil), do: {:error, :detective_already_placed}

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

  defp start_game_mode(%{"mode" => "full"}), do: :full
  defp start_game_mode(_params), do: :limited

  defp start_game_message(:full), do: "Full game started. Round 1 setup begins."
  defp start_game_message(:limited), do: "Game started. Detectives place the museum setup."

  defp player_order(%{phase: :lobby, turn_order: order}), do: order

  defp player_order(%{game_mode: :full, thief_rotation: [_player_id | _]} = state) do
    Enum.filter(state.thief_rotation, &Map.has_key?(state.players, &1))
  end

  defp player_order(state) do
    state.turn_order
    |> Enum.map(&controller_player_id(state, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp full_game?(%{game_mode: :full}), do: true
  defp full_game?(_state), do: false

  defp round_status(%{phase: :game_over}), do: "Final report"

  defp round_status(state) do
    "Round #{state.round_number} of #{max(length(state.thief_rotation), 1)}"
  end

  defp score_order(%{thief_rotation: []} = state), do: player_order(state)
  defp score_order(state), do: state.thief_rotation

  defp score_count(state, player_id), do: Map.get(state.artwork_scores, player_id, 0)

  defp score_for(state, player_id) do
    count = score_count(state, player_id)
    "#{count} #{artwork_word(count)}"
  end

  defp winner_names(%{winning_player_ids: []}), do: "No winner"

  defp winner_names(state) do
    state.winning_player_ids
    |> Enum.map(&player_name(state, &1))
    |> Enum.join(", ")
  end

  defp player_name(state, player_id) do
    case Map.get(state.players, player_id) do
      %{name: name} -> name
      nil -> "Unknown player"
    end
  end

  defp artwork_word(1), do: "artwork"
  defp artwork_word(_count), do: "artworks"

  defp current_turn_player?(state, player_id), do: turn_player_id(state) == player_id

  defp setup_thief_player?(%{phase: :setup} = state, player_id),
    do: player_role(state, player_id) == :thief

  defp setup_thief_player?(_state, _player_id), do: false

  defp back_to_lobby_event(%{phase: :lobby}), do: nil
  defp back_to_lobby_event(_state), do: "return_to_lobby"

  defp turn_player_id(%{phase: :thief_entry, thief_player_id: thief_id}), do: thief_id

  defp turn_player_id(%{phase: :playing, current_turn: current_turn} = state),
    do: controller_player_id(state, current_turn)

  defp turn_player_id(_state), do: nil

  defp controller_player_id(_state, nil), do: nil

  defp controller_player_id(state, turn_id) do
    state
    |> Map.get(:detective_controllers, %{})
    |> Map.get(turn_id, turn_id)
  end

  defp active_detective_id(state, player_id) do
    cond do
      controller_player_id(state, state.current_turn) == player_id and
          Map.has_key?(state.detective_positions, state.current_turn) ->
        state.current_turn

      Map.has_key?(state.detective_positions, player_id) ->
        player_id

      true ->
        nil
    end
  end

  defp next_unplaced_detective_id(state, player_id) do
    state
    |> controlled_detective_ids(player_id)
    |> Enum.find(&(Map.get(state.detective_positions, &1) == nil))
  end

  defp controlled_detective_ids(state, player_id) do
    state.detective_positions
    |> Map.keys()
    |> Enum.filter(&(controller_player_id(state, &1) == player_id))
  end

  defp host?(%{phase: :lobby, turn_order: [host_id | _]}, player_id), do: host_id == player_id
  defp host?(_state, _player_id), do: false

  defp review_host?(state, player_id), do: state.host_player_id == player_id

  defp start_game_enabled?(state), do: map_size(state.players) >= 2

  defp host_leaving_open_game?(%{phase: :game_over}, _player_id), do: false

  defp host_leaving_open_game?(state, player_id), do: state.host_player_id == player_id

  defp player_role(state, player_id) do
    case Map.get(state.players, player_id) do
      nil -> nil
      player -> player.role
    end
  end

  defp player_role_label(:thief), do: "Thief"
  defp player_role_label(:detective), do: "Detective"
  defp player_role_label(role), do: role

  defp player_display_color(state, player_id, player_color) do
    if current_turn_player?(state, player_id) and player_role(state, player_id) == :detective do
      case active_detective_id(state, player_id) do
        nil -> player_color
        detective_id -> detective_color(state, detective_id)
      end
    else
      player_color
    end
  end

  defp latest_detective_result(state, player_id) do
    if Map.has_key?(state.players, player_id), do: latest_detective_result(state)
  end

  defp latest_detective_result(%{detective_result: nil}), do: nil
  defp latest_detective_result(%{detective_result: result}), do: detective_result_message(result)

  defp latest_detective_result_key(%{detective_result: nil}), do: nil
  defp latest_detective_result_key(%{detective_result_id: result_id}), do: result_id

  defp result_toast_key(game_id, state, result_id) do
    "result:#{game_id}:round-#{state.round_number}:#{result_id}"
  end

  defp artwork_reveal_toast_key(game_id, state, %{key: key}) do
    "artwork-reveal:#{game_id}:round-#{state.round_number}:#{key}"
  end

  defp known_power_status(state, player_id) do
    case player_role(state, player_id) do
      :thief ->
        if state.power_active, do: :on, else: :off

      :detective ->
        if not state.power_active and state.power_revealed, do: :off

      _role ->
        nil
    end
  end

  defp power_status_value(:on), do: "on"
  defp power_status_value(:off), do: "off"

  defp power_status_label(:on), do: "Power on"
  defp power_status_label(:off), do: "Power off"

  defp power_status_icon(:on), do: "hero-bolt-solid"
  defp power_status_icon(:off), do: "hero-bolt-slash-solid"

  defp power_status_class(:on) do
    "flex items-center gap-2 rounded-lg border border-emerald-300/50 bg-emerald-400/15 p-3 text-sm font-semibold text-emerald-100"
  end

  defp power_status_class(:off) do
    "flex items-center gap-2 rounded-lg border border-red-300/50 bg-red-400/15 p-3 text-sm font-semibold text-red-100"
  end

  defp detective_result_message({:look_pawn, :chase_triggered}),
    do: "The detectives spotted the thief."

  defp detective_result_message({:look_pawn, :no_sighting}),
    do: "Pawn cannot see the thief."

  defp detective_result_message({:look_camera, {:sighting, camera_id}}),
    do: camera_sighting_message(camera_id)

  defp detective_result_message({:look_camera, :camera_disabled}),
    do: "That camera was disabled."

  defp detective_result_message({:look_camera, :power_off}),
    do: "The power is off, so cameras cannot see."

  defp detective_result_message({:look_camera, {:no_sighting, camera_id}}),
    do: camera_no_sighting_message(camera_id)

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

  defp camera_no_sighting_message(camera_id), do: "Camera #{camera_id} cannot see the thief."

  defp camera_scan_message(disabled_ids, sighting_ids) do
    "Camera scan found #{length(disabled_ids)} disabled cameras and #{camera_names(sighting_ids)} spotted the thief."
  end

  defp camera_names([id]), do: "C#{id}"

  defp camera_names(ids) do
    ids
    |> Enum.map(&"C#{&1}")
    |> Enum.join(", ")
  end

  defp die_pip_positions(1), do: [:center]
  defp die_pip_positions(2), do: [:top_left, :bottom_right]
  defp die_pip_positions(3), do: [:top_left, :center, :bottom_right]
  defp die_pip_positions(4), do: [:top_left, :top_right, :bottom_left, :bottom_right]

  defp die_pip_positions(5),
    do: [:top_left, :top_right, :center, :bottom_left, :bottom_right]

  defp die_pip_positions(6),
    do: [:top_left, :middle_left, :bottom_left, :top_right, :middle_right, :bottom_right]

  defp die_pip_positions(_value), do: []

  defp die_pip_class(position) do
    [
      "absolute block size-1.5 rounded-full bg-stone-950 shadow-sm lg:size-2 xl:size-2.5",
      die_pip_position_class(position)
    ]
  end

  defp die_pip_position_class(:top_left),
    do: "left-1.5 top-1.5 lg:left-2 lg:top-2 xl:left-2.5 xl:top-2.5"

  defp die_pip_position_class(:top_right),
    do: "right-1.5 top-1.5 lg:right-2 lg:top-2 xl:right-2.5 xl:top-2.5"

  defp die_pip_position_class(:middle_left),
    do: "left-1.5 top-1/2 -translate-y-1/2 lg:left-2 xl:left-2.5"

  defp die_pip_position_class(:middle_right),
    do: "right-1.5 top-1/2 -translate-y-1/2 lg:right-2 xl:right-2.5"

  defp die_pip_position_class(:center),
    do: "left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2"

  defp die_pip_position_class(:bottom_left),
    do: "bottom-1.5 left-1.5 lg:bottom-2 lg:left-2 xl:bottom-2.5 xl:left-2.5"

  defp die_pip_position_class(:bottom_right),
    do: "bottom-1.5 right-1.5 lg:bottom-2 lg:right-2 xl:bottom-2.5 xl:right-2.5"

  defp action_die_value(action), do: action |> Atom.to_string() |> String.replace("_", "-")

  defp action_die_label(:camera_scan), do: "camera scan"
  defp action_die_label(action), do: action_die_value(action)

  defp action_die_icon(:eye), do: "hero-eye-solid"
  defp action_die_icon(:camera_scan), do: "hero-camera-solid"
  defp action_die_icon(:motion), do: "hero-signal-solid"

  defp turn_panel_visible?(state, player_id, pending_escape_entry) do
    state.dice != nil or my_turn?(state, player_id) or
      motion_decision_buttons_visible?(state, player_id) or
      escape_choice_visible?(state, player_id, pending_escape_entry)
  end

  defp my_turn?(state, player_id), do: turn_player_id(state) == player_id

  defp motion_decision_buttons_visible?(state, player_id) do
    player_role(state, player_id) == :thief and motion_decision_pending?(state)
  end

  defp motion_decision_pending?(state) do
    state.phase == :playing and state.dice != nil and elem(state.dice, 1) == :motion and
      :look in state.turn_actions_remaining and state.power_active and
      state.motion_snips_remaining > 0 and state.motion_detector_decision != :allowed
  end

  defp escape_choice_visible?(state, player_id, pending_escape_entry) do
    pending_escape_entry != nil and player_role(state, player_id) == :thief and
      my_turn?(state, player_id)
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

  defp setup_success_message(:locks), do: nil
  defp setup_success_message(:paintings), do: nil
  defp setup_success_message(:cameras), do: nil
  defp setup_success_message(:pawns), do: nil

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

      state.phase == :playing and my_turn?(state, player_id) ->
        current_external_door_escape_entry_for_cell(state, player_id, pos) != nil or
          (not current_space_before_move?(state, player_id, pos) and
             (pos in valid_destinations(state, player_id) or
                escape_entry_for_cell(state, player_id, pos) != nil or
                movement_escape_entry_for_cell(state, player_id, pos) != nil))

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

  defp current_external_door_escape_entry_for_cell(state, player_id, pos) do
    if player_role(state, player_id) == :thief and state.current_turn == player_id and
         state.thief_position == pos do
      Enum.find(Board.exits_for_cell(pos), fn entry ->
        Board.exit_adjacent_cell(entry) == state.thief_position
      end)
    end
  end

  defp movement_escape_entry_for_cell(state, player_id, pos) do
    if player_role(state, player_id) == :thief and state.current_turn == player_id and
         :move in state.turn_actions_remaining do
      pos
      |> movement_escape_entries_for_cell()
      |> Enum.find(fn
        %{type: :door} = entry -> movement_escape_reachable?(state, entry)
        _entry -> false
      end)
    end
  end

  defp movement_escape_entries_for_cell(pos) do
    Board.entries_for_cell(pos) ++ Board.exits_for_cell(pos)
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
            Board.detective_placeable_cell?(pos) and
              controlled_detective_unplaced?(state, player_id) and
              not occupied_for_setup?(state, pos)

          _ ->
            false
        end
    end
  end

  defp controlled_detective_unplaced?(state, player_id),
    do: next_unplaced_detective_id(state, player_id) != nil

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
        :detective when state.dice != nil -> detective_destinations_for_player(state, player_id)
        _ -> []
      end
    else
      []
    end
  end

  defp current_space_before_move?(state, player_id, pos) do
    turn_needs_move?(state) and current_player_position(state, player_id) == pos
  end

  defp turn_can_end?(state), do: not turn_needs_move?(state)

  defp turn_needs_move?(state),
    do: :move in state.turn_actions_remaining and state.movement_spent == 0

  defp current_player_position(state, player_id) do
    case player_role(state, player_id) do
      :thief -> state.thief_position
      :detective -> Map.get(state.detective_positions, active_detective_id(state, player_id))
      _ -> nil
    end
  end

  defp detective_destinations_for_player(state, player_id) do
    case active_detective_id(state, player_id) do
      nil -> []
      detective_id -> Rules.valid_detective_destinations(state, detective_id)
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

  defp power_cell?(%{type: :power_room}), do: true
  defp power_cell?(_cell), do: false

  defp locked_escape_message(entry_id), do: "#{entry_label(entry_id)} lock is locked."

  defp escape_result_message(:escaped, _entry_id), do: "The thief escaped. Game over."
  defp escape_result_message(:locked, entry_id), do: locked_escape_message(entry_id)

  defp escape_result_message(:escaped_without_enough_art, _entry_id),
    do: "The thief escaped with fewer than 3 artworks. Detectives win."

  defp game_over_reason_label(:escaped_without_enough_art),
    do: "Escaped with fewer than 3 artworks"

  defp game_over_reason_label(reason) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp game_over_reason_label(reason), do: reason

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

  defp board_mark_stack(assigns) do
    assigns =
      assigns
      |> assign(:object_marks, object_marks(assigns.marks))
      |> assign(:pawn_marks, pawn_marks(assigns.marks))
      |> assign_new(:revealed_mark_keys, fn -> [] end)
      |> assign_new(:animated_mark_keys, fn -> %{} end)
      |> assign_new(:movement_path, fn -> [] end)

    ~H"""
    <span
      :if={@object_marks != [] or @pawn_marks != []}
      data-board-mark-stack="stacked"
      class="pointer-events-none absolute inset-0 z-10"
    >
      <span
        :if={@object_marks != []}
        data-board-mark-layer="objects"
        class={object_mark_layer_class(@pawn_marks)}
      >
        <%= for mark <- @object_marks do %>
          <% reveal_key = mark_reveal_key(mark) %>
          <% reveal_active = reveal_key in @revealed_mark_keys %>
          <span
            id={if(reveal_active, do: mark_reveal_dom_id(mark))}
            phx-hook={if(reveal_active, do: "BoardRevealHook")}
            data-board-mark={mark_kind(mark)}
            data-mark-status={mark_status(mark)}
            data-reveal-key={if(reveal_active, do: reveal_key)}
            data-reveal-layer={if(reveal_active, do: "above-turn-banner")}
            data-reveal-duration={if(reveal_active, do: "3000")}
            class={[mark_class(mark), reveal_active && "board-reveal-mark"]}
          >
            {mark_label(mark)}
          </span>
        <% end %>
      </span>
      <span
        :if={@pawn_marks != []}
        data-board-mark-layer="pawns"
        class="absolute inset-0 z-20 flex h-full w-full flex-wrap items-center justify-center gap-0.5 p-0.5"
      >
        <%= for mark <- @pawn_marks do %>
          <% animation_key = Map.get(@animated_mark_keys, mark_animation_identity(mark)) %>
          <% movement_active = animation_key != nil %>
          <span
            id={if(movement_active, do: mark_animation_dom_id(animation_key))}
            phx-hook={if(movement_active, do: "BoardRevealHook")}
            data-board-mark={mark_kind(mark)}
            data-mark-status={mark_status(mark)}
            data-animation-kind={if(movement_active, do: "move")}
            data-move-animation-key={if(movement_active, do: animation_key)}
            data-move-path={if(movement_active, do: movement_path_attr(@movement_path))}
            data-reveal-key={if(movement_active, do: animation_key)}
            data-reveal-once={if(movement_active, do: "false")}
            data-reveal-duration={if(movement_active, do: "1200")}
            class={[mark_class(mark), movement_active && "board-move-mark"]}
          >
            {mark_label(mark)}
          </span>
        <% end %>
      </span>
    </span>
    """
  end

  defp object_marks(marks), do: Enum.reject(marks, &pawn_mark?/1)
  defp pawn_marks(marks), do: Enum.filter(marks, &pawn_mark?/1)

  defp pawn_mark?({:detective, _id, _color}), do: true
  defp pawn_mark?({:thief, _color}), do: true
  defp pawn_mark?(_mark), do: false

  defp mark_reveal_key({:painting, label, :removed}), do: "painting:#{label}:removed"
  defp mark_reveal_key({:camera, id, :disabled}), do: "camera:#{id}:disabled"
  defp mark_reveal_key(_mark), do: nil

  defp mark_animation_identity({:detective, id, _color}),
    do: pawn_animation_identity({:detective, id})

  defp mark_animation_identity({:thief, _color}), do: pawn_animation_identity(:thief)
  defp mark_animation_identity(_mark), do: nil

  defp mark_animation_dom_id(animation_key) do
    key = String.replace(animation_key, ~r/[^a-zA-Z0-9_-]+/, "-")
    "board-animation-#{key}"
  end

  defp movement_path_attr(path) do
    Enum.map_join(path, " ", &position_key/1)
  end

  defp mark_reveal_dom_id(mark) do
    key =
      mark
      |> mark_reveal_key()
      |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")

    "board-reveal-#{key}"
  end

  defp object_mark_layer_class([]) do
    "absolute inset-0 z-10 flex h-full w-full flex-wrap items-center justify-center gap-0.5 p-1"
  end

  defp object_mark_layer_class(_pawn_marks) do
    "absolute inset-x-0 bottom-0 z-10 flex w-full flex-wrap items-end justify-center gap-0.5 px-0.5 pb-0.5"
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
    |> Enum.map(fn {id, _pos} -> {:detective, id, detective_color(state, id)} end)
  end

  defp thief_marks(state, player_id, pos) do
    if state.thief_position == pos and
         (player_role(state, player_id) == :thief or state.chase_mode or state.phase == :game_over) do
      [{:thief, :grey}]
    else
      []
    end
  end

  defp detective_color(state, id) do
    case Map.get(state.players, id) do
      %{color: color} ->
        color

      nil ->
        controlled_detective_color(state, id)
    end
  end

  defp controlled_detective_color(state, id) do
    controller_id = controller_player_id(state, id)

    case Map.get(state.players, controller_id) do
      %{color: color} ->
        controlled_detective_color(state, controller_id, id, color)

      nil ->
        PawnColors.default()
    end
  end

  defp controlled_detective_color(state, controller_id, id, controller_color) do
    index =
      state
      |> controlled_detective_ids(controller_id)
      |> Enum.find_index(&(&1 == id))

    case index do
      0 ->
        controller_color

      nil ->
        PawnColors.default()

      index ->
        PawnColors.all()
        |> Enum.reject(&(&1 == controller_color))
        |> Enum.at(index - 1, PawnColors.default())
    end
  end

  defp mark_class({:painting, _label, status}),
    do: object_mark_class("artwork", status)

  defp mark_class({:camera, _id, status}),
    do: object_mark_class("camera", status)

  defp mark_class({:detective, _id, color}),
    do: pawn_mark_class(color)

  defp mark_class({:thief, color}), do: pawn_mark_class(color)

  defp mark_class(_),
    do:
      "max-w-full truncate rounded bg-emerald-900 px-1 py-0.5 text-[0.54rem] font-black text-emerald-100"

  defp object_mark_class(kind, status) do
    "board-object-mark board-object-mark-#{kind} board-object-mark-#{status}"
  end

  defp mark_label({:painting, label, :targeted}), do: "#{label}*"
  defp mark_label({:painting, label, _status}), do: label
  defp mark_label({:camera, id, _status}), do: "C#{id}"
  defp mark_label({:detective, _id, _color}), do: ""
  defp mark_label({:thief, _color}), do: ""
  defp mark_label(mark), do: mark

  defp mark_kind({:painting, _label, _status}), do: "painting"
  defp mark_kind({:camera, _id, _status}), do: "camera"
  defp mark_kind({:detective, _id, _color}), do: "detective"
  defp mark_kind({:thief, _color}), do: "thief"
  defp mark_kind(_mark), do: "piece"

  defp mark_status({:painting, _label, status}), do: status
  defp mark_status({:camera, _id, status}), do: status
  defp mark_status({:detective, _id, color}), do: player_color_status(color)
  defp mark_status({:thief, color}), do: player_color_status(color)
  defp mark_status(_mark), do: nil

  defp player_color_status(:grey), do: "gray"
  defp player_color_status(:gray), do: "gray"
  defp player_color_status(color) when is_atom(color), do: Atom.to_string(color)
  defp player_color_status(color), do: color

  defp pawn_mark_class(color) do
    "block size-3.5 rounded-full border-2 shadow-sm md:size-5 lg:size-6 " <>
      pawn_color_class(color)
  end

  defp pawn_color_class(:purple), do: "border-purple-200 bg-purple-500 shadow-purple-950/40"
  defp pawn_color_class(:green), do: "border-green-200 bg-green-500 shadow-green-950/40"
  defp pawn_color_class(:blue), do: "border-blue-200 bg-blue-500 shadow-blue-950/40"
  defp pawn_color_class(:white), do: "border-stone-300 bg-stone-50 shadow-stone-950/40"
  defp pawn_color_class(:red), do: "border-red-200 bg-red-500 shadow-red-950/40"
  defp pawn_color_class(:yellow), do: "border-yellow-100 bg-yellow-300 shadow-yellow-950/40"
  defp pawn_color_class(:grey), do: "border-stone-300 bg-stone-500 shadow-stone-950/40"
  defp pawn_color_class(:gray), do: pawn_color_class(:grey)
  defp pawn_color_class(_color), do: pawn_color_class(PawnColors.default())

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
          "#{prop}:var(--museum-window-border);"

        Board.passable?(pos, adj) ->
          "#{prop}:var(--museum-passable-border);"

        true ->
          "#{prop}:var(--museum-wall-border);"
      end
    end)
  end
end
