defmodule Mallard.Protocol.DisconnectMessage do
  @moduledoc false

  alias Mallard.Binary, as: B

  @type_id 11

  def encode(connection_id, query_id) do
    header =
      B.encode_object(
        B.encode_field(1, B.encode_uleb(@type_id)) <>
          B.encode_field(2, B.encode_string(connection_id)) <>
          B.encode_field(3, B.encode_uleb(query_id))
      )

    body = B.encode_object(<<>>)
    header <> body
  end
end
