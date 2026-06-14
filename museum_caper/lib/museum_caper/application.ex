defmodule MuseumCaper.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MuseumCaperWeb.Telemetry,
      {Phoenix.PubSub, name: MuseumCaper.PubSub},
      {Registry, keys: :unique, name: MuseumCaper.GameRegistry},
      {DynamicSupervisor, name: MuseumCaper.GameSupervisor, strategy: :one_for_one},
      MuseumCaper.Lobby.Server,
      MuseumCaperWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MuseumCaper.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MuseumCaperWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
