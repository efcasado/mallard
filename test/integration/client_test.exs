defmodule Mallard.Integration.ClientTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  # Start a DuckDB quack server before running these tests:
  #
  #   docker compose up -d
  #
  # Then run with:
  #
  #   mix test --include integration

  @host "localhost"
  @port 9494
  @token "secret"

  test "simple SELECT query" do
    assert {:ok, conn, _info} = Mallard.connect(@host, port: @port, auth_token: @token)
    assert {:ok, result} = Mallard.query(conn, "SELECT 42 AS answer, 'hello duckdb' AS greeting")
    assert [%{name: "answer"}, %{name: "greeting"}] = result.columns
    assert [[42, "hello duckdb"]] = result.rows
    assert :ok = Mallard.disconnect(conn)
  end

  test "connect and disconnect" do
    assert {:ok, conn, info} = Mallard.connect(@host, port: @port, auth_token: @token)
    assert is_binary(conn.connection_id)
    assert info.server_duckdb_version =~ "v1."
    assert info.quack_version == 1
    assert :ok = Mallard.disconnect(conn)
  end

  test "wrong auth token returns a server error" do
    assert {:error, {:server_error, msg}} =
             Mallard.connect(@host, port: @port, auth_token: "wrong-token")

    assert is_binary(msg)
  end

  test "unreachable host returns a transport error" do
    assert {:error, _reason} =
             Mallard.connect("localhost", port: 19_494)
  end
end
