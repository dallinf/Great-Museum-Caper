defmodule MuseumCaperWeb.PageControllerTest do
  use MuseumCaperWeb.ConnCase

  test "GET / renders lobby", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Museum Caper"
  end
end
