defmodule Mallard.Protocol do
  @moduledoc """
  Quack protocol message encoding and decoding.

  Encodes outbound messages and dispatches inbound responses to the
  appropriate message-specific decoder based on the header type field.
  """

  alias Mallard.Binary, as: B
  alias Mallard.Protocol.ConnectionRequest
  alias Mallard.Protocol.ConnectionResponse
  alias Mallard.Protocol.DisconnectMessage
  alias Mallard.Protocol.ErrorResponse
  alias Mallard.Protocol.PrepareRequest
  alias Mallard.Protocol.PrepareResponse
  alias Mallard.Protocol.SuccessResponse

  @type_connection_response 2
  @type_prepare_response 4
  @type_success_response 10
  @type_error_response 100

  def encode({:connection_request, opts}), do: ConnectionRequest.encode(opts)
  def encode({:disconnect_message, connection_id, query_id}), do: DisconnectMessage.encode(connection_id, query_id)
  def encode({:prepare_request, connection_id, sql}), do: PrepareRequest.encode(connection_id, sql)

  def decode(binary) do
    {header, rest} = decode_header(binary)
    decode_body(header, rest)
  end

  defp decode_body(%{type: @type_connection_response} = header, binary), do: ConnectionResponse.decode(header, binary)
  defp decode_body(%{type: @type_prepare_response} = header, binary), do: PrepareResponse.decode(header, binary)
  defp decode_body(%{type: @type_success_response}, binary), do: SuccessResponse.decode(binary)
  defp decode_body(%{type: @type_error_response}, binary), do: ErrorResponse.decode(binary)
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
end
