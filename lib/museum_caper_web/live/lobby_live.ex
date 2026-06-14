defmodule MuseumCaperWeb.LobbyLive do
  use MuseumCaperWeb, :live_view
  alias MuseumCaper.Lobby.Server, as: LobbyServer

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MuseumCaper.PubSub, "lobby")
    end

    {:ok,
     assign(socket,
       rooms: LobbyServer.list_rooms(),
       error: nil,
       joining: nil,
       create_form: to_form(%{"name" => "", "player_name" => ""}, as: :room)
     )}
  end

  @impl true
  def handle_event("create_room", params, socket) do
    %{"name" => name, "player_name" => player_name} = room_params(params)
    name = String.trim(name)
    player_name = String.trim(player_name)

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "name is required")}

      player_name == "" ->
        {:noreply, assign(socket, error: "player name is required")}

      true ->
        case LobbyServer.create_room(name, player_name) do
          {:ok, game_id} ->
            {:noreply,
             push_navigate(socket, to: "/game/#{game_id}?player_name=#{URI.encode(player_name)}")}

          {:error, :name_taken} ->
            {:noreply, assign(socket, error: "room name already taken")}
        end
    end
  end

  @impl true
  def handle_event("show_join", %{"game_id" => game_id}, socket) do
    case room_by_game_id(socket.assigns.rooms, game_id) do
      %{phase: :lobby} ->
        {:noreply, assign(socket, joining: game_id, error: nil)}

      _room ->
        {:noreply, assign(socket, joining: nil, error: "game already in progress")}
    end
  end

  @impl true
  def handle_event("cancel_join", _params, socket) do
    {:noreply, assign(socket, joining: nil, error: nil)}
  end

  @impl true
  def handle_event("join_room", params, socket) do
    %{"game_id" => game_id, "player_name" => player_name} = join_params(params)
    player_name = String.trim(player_name)

    cond do
      player_name == "" ->
        {:noreply, assign(socket, error: "player name is required")}

      not joinable_room?(socket.assigns.rooms, game_id) ->
        {:noreply, assign(socket, joining: nil, error: "game already in progress")}

      true ->
        {:noreply,
         push_navigate(socket, to: "/game/#{game_id}?player_name=#{URI.encode(player_name)}")}
    end
  end

  @impl true
  def handle_info({:lobby_updated, rooms}, socket) do
    {:noreply, assign(socket, rooms: rooms)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto grid min-h-[calc(100vh-4rem)] max-w-6xl gap-6 px-4 py-8 lg:grid-cols-[24rem_minmax(0,1fr)] lg:px-8">
        <section class="rounded-lg border border-stone-700 bg-stone-900 p-5 shadow-2xl shadow-black/30">
          <p class="text-xs font-black uppercase tracking-[0.22em] text-amber-300">Private room</p>
          <h1 class="mt-2 text-4xl font-black tracking-normal text-stone-50">Set the caper.</h1>
          <p class="mt-3 text-sm leading-6 text-stone-400">
            Create a local room, open it in another browser or private window, and join as the second player.
          </p>

          <.form
            for={@create_form}
            id="create-room-form"
            phx-submit="create_room"
            class="mt-6 space-y-4"
          >
            <.input
              field={@create_form[:name]}
              type="text"
              label="Room name"
              placeholder="Friday night heist"
            />
            <.input
              field={@create_form[:player_name]}
              type="text"
              label="Your name"
              placeholder="Alice"
            />
            <%= if @error && @joining == nil do %>
              <p
                id="lobby-error"
                class="rounded-md border border-rose-300/40 bg-rose-300/10 px-3 py-2 text-sm text-rose-100"
              >
                {@error}
              </p>
            <% end %>
            <button
              id="create-room-button"
              type="submit"
              class="inline-flex w-full items-center justify-center gap-2 rounded-md bg-amber-300 px-4 py-3 text-sm font-black text-stone-950 transition hover:bg-amber-200"
            >
              <.icon name="hero-plus-solid" class="size-4" /> Create room
            </button>
          </.form>
        </section>

        <section class="min-w-0 rounded-lg border border-stone-700 bg-stone-900 p-5 shadow-2xl shadow-black/30">
          <div class="flex items-center justify-between gap-4">
            <div>
              <p class="text-xs font-black uppercase tracking-[0.22em] text-stone-500">Open rooms</p>
              <h2 class="mt-1 text-2xl font-black text-stone-50">Join a table</h2>
            </div>
            <span class="rounded-md border border-stone-700 px-3 py-1 text-sm font-bold text-stone-400">
              {length(@rooms)} open
            </span>
          </div>

          <%= if @rooms == [] do %>
            <div
              id="empty-rooms"
              class="mt-6 rounded-lg border border-dashed border-stone-700 p-8 text-center text-stone-500"
            >
              No rooms yet.
            </div>
          <% else %>
            <div id="room-list" class="mt-6 grid gap-3">
              <%= for room <- @rooms do %>
                <article
                  id={"room-#{room.game_id}"}
                  class="rounded-lg border border-stone-700 bg-stone-800 p-4"
                >
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <h3 class="font-black text-stone-50">{room.name}</h3>
                      <p class="mt-1 text-sm text-stone-400">
                        {room.player_count}/4 players · {room.phase}
                      </p>
                    </div>
                    <%= cond do %>
                      <% room.phase != :lobby -> %>
                        <span
                          data-room-status="locked"
                          class="rounded-md border border-stone-600 px-4 py-2 text-sm font-bold text-stone-400"
                        >
                          In progress
                        </span>
                      <% @joining != room.game_id -> %>
                        <button
                          type="button"
                          id={"show-join-#{room.game_id}"}
                          phx-click="show_join"
                          phx-value-game_id={room.game_id}
                          class="rounded-md bg-emerald-400 px-4 py-2 text-sm font-black text-stone-950 transition hover:bg-emerald-300"
                        >
                          Join
                        </button>
                      <% true -> %>
                    <% end %>
                  </div>

                  <%= if @joining == room.game_id and room.phase == :lobby do %>
                    <% join_form =
                      to_form(%{"game_id" => room.game_id, "player_name" => ""}, as: :join) %>
                    <.form
                      for={join_form}
                      id={"join-room-form-#{room.game_id}"}
                      phx-submit="join_room"
                      class="mt-4 grid gap-3 sm:grid-cols-[1fr_auto_auto]"
                    >
                      <.input field={join_form[:game_id]} type="hidden" value={room.game_id} />
                      <.input field={join_form[:player_name]} type="text" placeholder="Your name" />
                      <button
                        type="submit"
                        class="rounded-md bg-emerald-400 px-4 py-2 text-sm font-black text-stone-950 transition hover:bg-emerald-300"
                      >
                        Go
                      </button>
                      <button
                        type="button"
                        phx-click="cancel_join"
                        class="rounded-md border border-stone-600 px-4 py-2 text-sm font-bold text-stone-200 transition hover:bg-stone-700"
                      >
                        Cancel
                      </button>
                    </.form>
                    <%= if @error do %>
                      <p class="mt-2 text-sm text-rose-200">{@error}</p>
                    <% end %>
                  <% end %>
                </article>
              <% end %>
            </div>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp room_params(%{"room" => room}), do: Map.take(room, ["name", "player_name"])
  defp room_params(params), do: Map.take(params, ["name", "player_name"])

  defp join_params(%{"join" => join}), do: Map.take(join, ["game_id", "player_name"])
  defp join_params(params), do: Map.take(params, ["game_id", "player_name"])

  defp joinable_room?(rooms, game_id) do
    match?(%{phase: :lobby}, room_by_game_id(rooms, game_id))
  end

  defp room_by_game_id(rooms, game_id) do
    Enum.find(rooms, &(&1.game_id == game_id))
  end
end
