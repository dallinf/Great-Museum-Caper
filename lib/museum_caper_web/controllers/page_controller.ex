defmodule MuseumCaperWeb.PageController do
  use MuseumCaperWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
