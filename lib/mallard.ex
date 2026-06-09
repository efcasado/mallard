defmodule Mallard do
  @moduledoc """
  Elixir client for DuckDB's Quack remote protocol.

  Start a DuckDB Quack server (DuckDB v1.5.3+):

      INSTALL quack;
      LOAD quack;
      CALL quack_serve('quack:127.0.0.1:9494', token=>'my-secret-token');

  Then connect and disconnect:

      {:ok, conn, _info} = Mallard.connect("localhost", auth_token: "my-secret-token")
      :ok = Mallard.disconnect(conn)
  """

  defdelegate connect(host, opts \\ []), to: Mallard.Client
  defdelegate disconnect(conn), to: Mallard.Client
end
