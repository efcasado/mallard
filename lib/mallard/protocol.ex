defmodule Mallard.Protocol do
  @moduledoc """
  Quack protocol message encoding and decoding.

  Each POST to /quack carries exactly one message (header object + body object)
  and receives exactly one response back. This module covers the subset needed
  for connection management: CONNECTION_REQUEST, CONNECTION_RESPONSE,
  DISCONNECT_MESSAGE, SUCCESS_RESPONSE, and ERROR_RESPONSE.
  """

  alias Mallard.Binary, as: B

  @quack_version 1

  @type_connection_request 1
  @type_connection_response 2
  @type_disconnect_message 11
  @type_success_response 10
  @type_error_response 100

  # ── Encoding ─────────────────────────────────────────────────────────────

  @doc """
  Encode a CONNECTION_REQUEST message.

  Options:
    - `:auth_string`      — authentication token (optional)
    - `:client_platform`  — advertised platform string (default: "mallard-elixir")
  """
  def encode_connection_request(opts \\ []) do
    auth_string = Keyword.get(opts, :auth_string)
    client_platform = Keyword.get(opts, :client_platform, "mallard-elixir")

    header =
      B.encode_object(
        B.encode_field(1, B.encode_uleb(@type_connection_request)) <>
          B.encode_field(3, B.encode_uleb(B.optional_index_invalid()))
      )

    body =
      B.encode_object(
        maybe_string_field(1, auth_string) <>
          maybe_string_field(3, client_platform) <>
          B.encode_field(4, B.encode_uleb(@quack_version)) <>
          B.encode_field(5, B.encode_uleb(@quack_version))
      )

    header <> body
  end

  @doc """
  Encode a DISCONNECT_MESSAGE for the given connection and query ID.
  """
  def encode_disconnect_message(connection_id, query_id) do
    header =
      B.encode_object(
        B.encode_field(1, B.encode_uleb(@type_disconnect_message)) <>
          B.encode_field(2, B.encode_string(connection_id)) <>
          B.encode_field(3, B.encode_uleb(query_id))
      )

    body = B.encode_object(<<>>)

    header <> body
  end

  # ── Decoding ─────────────────────────────────────────────────────────────

  @doc """
  Decode a raw binary response from the server.

  Returns one of:
    - `{:ok, %{type: :connection_response, connection_id: ..., ...}}`
    - `{:ok, %{type: :success_response}}`
    - `{:error, {:server_error, message}}`
    - `{:error, {:unsupported_message_type, type}}`
  """
  def decode_response(binary) do
    {header, rest} = decode_header(binary)
    decode_body(header, rest)
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp decode_body(%{type: @type_connection_response} = header, binary),
    do: decode_connection_response_body(header, binary)

  defp decode_body(%{type: @type_success_response}, binary), do: decode_success_response_body(binary)
  defp decode_body(%{type: @type_error_response}, binary), do: decode_error_response_body(binary)
  defp decode_body(%{type: type}, _binary), do: {:error, {:unsupported_message_type, type}}

  defp decode_header(binary) do
    {type, rest} = B.read_required_field(1, binary, &B.decode_uleb/1)
    {connection_id, rest} = B.read_optional_field(2, rest, nil, &B.decode_string/1)
    {query_id_raw, rest} = B.read_required_field(3, rest, &B.decode_uleb/1)
    rest = B.read_end_object(rest)

    query_id =
      if query_id_raw == B.optional_index_invalid(), do: nil, else: query_id_raw

    {%{type: type, connection_id: connection_id, query_id: query_id}, rest}
  end

  defp decode_connection_response_body(header, binary) do
    {server_version, rest} = B.read_optional_field(1, binary, nil, &B.decode_string/1)
    {server_platform, rest} = B.read_optional_field(2, rest, nil, &B.decode_string/1)
    {quack_version, rest} = B.read_optional_field(3, rest, nil, &B.decode_uleb/1)
    B.read_end_object(rest)

    {:ok,
     %{
       type: :connection_response,
       connection_id: header.connection_id,
       server_duckdb_version: server_version,
       server_platform: server_platform,
       quack_version: quack_version
     }}
  end

  defp decode_success_response_body(binary) do
    B.read_end_object(binary)
    {:ok, %{type: :success_response}}
  end

  defp decode_error_response_body(binary) do
    {message, rest} = B.read_optional_field(1, binary, "", &B.decode_string/1)
    B.read_end_object(rest)
    {:error, {:server_error, message}}
  end

  defp maybe_string_field(_id, nil), do: <<>>
  defp maybe_string_field(_id, ""), do: <<>>
  defp maybe_string_field(id, value), do: B.encode_field(id, B.encode_string(value))
end
