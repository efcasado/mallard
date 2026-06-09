defmodule Mallard.Client do
  @moduledoc """
  Quack protocol client.

  ## Example

      {:ok, conn} = Mallard.Client.connect("localhost", auth_token: "my-secret-token")
      :ok = Mallard.Client.disconnect(conn)
  """

  alias Mallard.Protocol

  @default_port 9494
  @quack_endpoint "/quack"
  @duckdb_mime "application/duckdb"

  defstruct [:base_url, :connection_id, :next_query_id, :req]

  @type t :: %__MODULE__{
          base_url: String.t(),
          connection_id: String.t(),
          next_query_id: non_neg_integer(),
          req: Req.Request.t()
        }

  @doc """
  Open a Quack connection to `host`.

  Options:
    - `:port`            — TCP port (default: #{@default_port})
    - `:ssl`             — use HTTPS (default: false)
    - `:auth_token`      — authentication token sent in the handshake
    - `:client_platform` — platform string advertised to the server
    - `:req_opts`        — extra options forwarded to `Req.new/1`

  Returns `{:ok, conn}` on success where `conn.server_info` holds the
  version and platform strings reported by the server.
  """
  def connect(host, opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)
    ssl = Keyword.get(opts, :ssl, false)
    auth_token = Keyword.get(opts, :auth_token)
    client_platform = Keyword.get(opts, :client_platform, "mallard-elixir")
    req_opts = Keyword.get(opts, :req_opts, [])

    scheme = if ssl, do: "https", else: "http"
    base_url = "#{scheme}://#{host}:#{port}"

    req =
      Req.new(
        [
          base_url: base_url,
          headers: [{"content-type", @duckdb_mime}, {"accept", @duckdb_mime}]
        ] ++ req_opts
      )

    msg_opts =
      [client_platform: client_platform] ++
        if(auth_token, do: [auth_string: auth_token], else: [])

    body = Protocol.encode_connection_request(msg_opts)

    with {:ok, %{status: 200, body: raw}} <- Req.post(req, url: @quack_endpoint, body: body),
         {:ok, %{type: :connection_response, connection_id: id} = info}
         when not is_nil(id) <- Protocol.decode_response(raw) do
      conn = %__MODULE__{
        base_url: base_url,
        connection_id: id,
        next_query_id: 1,
        req: req
      }

      server_info = Map.take(info, [:server_duckdb_version, :server_platform, :quack_version])
      {:ok, conn, server_info}
    else
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:ok, %{type: :connection_response}} -> {:error, :missing_connection_id}
      {:error, _} = err -> err
    end
  end

  @doc """
  Close an open Quack connection.

  Sends a DISCONNECT_MESSAGE and expects a SUCCESS_RESPONSE.
  Safe to call even if the server is unreachable — connection errors are
  returned but the connection struct is not reusable afterwards regardless.
  """
  def disconnect(%__MODULE__{} = conn) do
    body = Protocol.encode_disconnect_message(conn.connection_id, conn.next_query_id)

    with {:ok, %{status: 200, body: raw}} <- Req.post(conn.req, url: @quack_endpoint, body: body),
         {:ok, %{type: :success_response}} <- Protocol.decode_response(raw) do
      :ok
    else
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, _} = err -> err
    end
  end
end
