defmodule MuseumCaperWeb.PageControllerTest do
  use MuseumCaperWeb.ConnCase

  test "GET / renders lobby", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "The Great Museum Caper"
    refute html =~ "Phoenix Framework"
  end

  test "GET / renders the fixed app theme", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ ~s|<html lang="en" data-theme="dark">|
  end
end
