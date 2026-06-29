defmodule MuseumCaperWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MuseumCaperWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :back_to_lobby_event, :string,
    default: nil,
    doc: "optional LiveView click event fired before returning to the lobby"

  attr :compact, :boolean,
    default: false,
    doc: "render compact overlay navigation instead of the full application banner"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @compact do %>
      <details id="app-menu" class="fixed right-2 top-2 z-50 text-stone-100 md:right-3 md:top-3">
        <summary
          id="app-menu-button"
          class="grid size-10 cursor-pointer list-none place-items-center rounded-md border border-stone-700 bg-stone-950/90 shadow-xl shadow-black/30 backdrop-blur transition hover:border-amber-300/70 hover:text-amber-100 md:size-12 lg:size-14 [&::-webkit-details-marker]:hidden"
          aria-label="Open game menu"
        >
          <.icon name="hero-bars-3" class="size-5 md:size-6 lg:size-7" />
        </summary>
        <div class="absolute right-0 mt-2 w-72 max-w-[calc(100vw-1rem)] rounded-lg border border-stone-700 bg-stone-950/95 p-2 shadow-2xl shadow-black/40 backdrop-blur md:w-80">
          <button
            id="game-audio-toggle"
            type="button"
            phx-hook="GameAudioPreferenceHook"
            phx-update="ignore"
            aria-pressed="false"
            data-audio-storage-key="museum_caper.game_audio_enabled"
            class="group flex w-full items-center justify-between gap-3 rounded-md border border-transparent px-3 py-2 text-left text-sm font-bold text-stone-200 transition hover:border-amber-300/40 hover:bg-stone-900 hover:text-amber-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-200"
          >
            <span class="flex min-w-0 items-center gap-2">
              <span class="grid size-7 shrink-0 place-items-center rounded-md border border-stone-700 bg-stone-900 text-stone-300 transition group-hover:border-amber-300/50 group-hover:text-amber-100">
                <span data-audio-disabled-icon>
                  <.icon name="hero-speaker-x-mark" class="size-4" />
                </span>
                <span data-audio-enabled-icon class="hidden">
                  <.icon name="hero-speaker-wave" class="size-4" />
                </span>
              </span>
              <span class="truncate">Game audio</span>
            </span>
            <span
              data-audio-state-label
              class="rounded-full border border-stone-700 bg-stone-900 px-2 py-0.5 text-xs font-black uppercase tracking-[0.12em] text-stone-400 transition"
            >
              Off
            </span>
          </button>
          <%= if @back_to_lobby_event do %>
            <.link
              id="back-to-lobby-link"
              href={~p"/"}
              phx-click={@back_to_lobby_event}
              class="flex items-center gap-2 rounded-md px-3 py-2 text-sm font-bold text-stone-200 transition hover:bg-stone-800 hover:text-amber-100"
            >
              <.icon name="hero-arrow-left" class="size-4" />
              <span>Back to lobby</span>
            </.link>
          <% end %>
        </div>
      </details>
    <% else %>
      <header
        id="app-header"
        class="sticky top-0 z-30 h-16 border-b border-stone-800 bg-stone-950/95 text-stone-100 backdrop-blur"
      >
        <div class="mx-auto flex h-full max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
          <.link navigate={~p"/"} class="group flex items-center gap-3">
            <span class="grid size-9 place-items-center rounded-md border border-amber-300/40 bg-amber-300 text-xs font-black text-stone-950 shadow-lg shadow-amber-950/30">
              GMC
            </span>
            <span>
              <span class="block text-sm font-black tracking-normal text-stone-50 sm:uppercase sm:tracking-[0.08em]">
                The Great Museum Caper
              </span>
              <span class="block text-xs text-stone-500 transition group-hover:text-stone-300">
                Online game
              </span>
            </span>
          </.link>
          <div class="flex items-center gap-2">
            <%= if @back_to_lobby_event do %>
              <.link
                id="back-to-lobby-link"
                href={~p"/"}
                phx-click={@back_to_lobby_event}
                class="inline-flex h-9 items-center gap-2 rounded-md border border-stone-700 bg-stone-900 px-3 text-sm font-bold text-stone-200 transition hover:border-amber-300/70 hover:bg-stone-800 hover:text-amber-100"
              >
                <.icon name="hero-arrow-left" class="size-4" />
                <span>Back to lobby</span>
              </.link>
            <% end %>
          </div>
        </div>
      </header>
    <% end %>

    <main
      id="app-main"
      data-layout={if(@compact, do: "full-screen", else: "header-offset")}
      class={[
        "bg-stone-950 text-stone-100",
        if(@compact, do: "min-h-dvh", else: "min-h-[calc(100dvh-4rem)]")
      ]}
    >
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
