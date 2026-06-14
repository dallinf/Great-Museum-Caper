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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header
      id="app-header"
      class="sticky top-0 z-30 h-16 border-b border-stone-800 bg-stone-950/95 text-stone-100 backdrop-blur"
    >
      <div class="mx-auto flex h-full max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <.link navigate={~p"/"} class="group flex items-center gap-3">
          <span class="grid size-9 place-items-center rounded-md border border-amber-300/40 bg-amber-300 text-sm font-black text-stone-950 shadow-lg shadow-amber-950/30">
            MC
          </span>
          <span>
            <span class="block text-sm font-black uppercase tracking-[0.18em] text-stone-50">
              Museum Caper
            </span>
            <span class="block text-xs text-stone-500 transition group-hover:text-stone-300">
              local prototype
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
          <% else %>
            <.link
              id="back-to-lobby-link"
              navigate={~p"/"}
              class="inline-flex h-9 items-center gap-2 rounded-md border border-stone-700 bg-stone-900 px-3 text-sm font-bold text-stone-200 transition hover:border-amber-300/70 hover:bg-stone-800 hover:text-amber-100"
            >
              <.icon name="hero-arrow-left" class="size-4" />
              <span>Back to lobby</span>
            </.link>
          <% end %>
          <.theme_toggle />
        </div>
      </div>
    </header>

    <main
      id="app-main"
      data-layout="header-offset"
      class="min-h-[calc(100dvh-4rem)] bg-stone-950 text-stone-100"
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

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative grid grid-cols-3 rounded-md border border-stone-700 bg-stone-900 p-1">
      <button
        type="button"
        class="grid size-8 place-items-center rounded text-stone-400 transition hover:bg-stone-800 hover:text-stone-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        type="button"
        class="grid size-8 place-items-center rounded text-stone-400 transition hover:bg-stone-800 hover:text-stone-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        type="button"
        class="grid size-8 place-items-center rounded text-stone-400 transition hover:bg-stone-800 hover:text-stone-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
