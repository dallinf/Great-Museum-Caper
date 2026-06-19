defmodule MuseumCaperWeb.PathPrefixTest do
  use MuseumCaperWeb.ConnCase

  test "root layout emits deployment-prefixed asset and live socket paths", %{conn: conn} do
    endpoint_config =
      :ets.tab2list(MuseumCaperWeb.Endpoint)
      |> Keyword.delete(:__config__)

    on_exit(fn ->
      MuseumCaperWeb.Endpoint.config_change(%{MuseumCaperWeb.Endpoint => endpoint_config}, [])
    end)

    MuseumCaperWeb.Endpoint.config_change(
      %{
        MuseumCaperWeb.Endpoint =>
          Keyword.put(endpoint_config, :url, host: "example.com", path: "/museum_caper")
      },
      []
    )

    document =
      conn
      |> get("/")
      |> html_response(200)
      |> LazyHTML.from_fragment()

    assert document
           |> LazyHTML.query("link[rel='stylesheet']")
           |> LazyHTML.attribute("href") == ["/museum_caper/assets/css/app.css"]

    script = LazyHTML.query(document, "script[type='text/javascript']")

    assert LazyHTML.attribute(script, "src") == ["/museum_caper/assets/js/app.js"]
    assert LazyHTML.attribute(script, "data-live-socket-path") == ["/museum_caper/live"]
  end
end
