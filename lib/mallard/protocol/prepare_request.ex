defmodule Mallard.Protocol.PrepareRequest do
  @moduledoc false

  alias Mallard.Binary, as: B

  @type_id 3

  def encode(connection_id, sql) do
    header =
      B.encode_object(
        B.encode_field(1, B.encode_uleb(@type_id)) <>
          B.encode_field(2, B.encode_string(connection_id)) <>
          B.encode_field(3, B.encode_uleb(B.optional_index_invalid()))
      )

    body = B.encode_object(B.encode_field(1, B.encode_string(sql)))
    header <> body
  end
end
