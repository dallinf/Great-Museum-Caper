defmodule MuseumCaperWeb.Router do
  use MuseumCaperWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MuseumCaperWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MuseumCaperWeb do
    pipe_through :browser

    live "/", LobbyLive, :index
    live "/game/:game_id", GameLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MuseumCaperWeb do
  #   pipe_through :api
  # end
end
