defmodule Mallard.Protocol.ConnectionRequest do
  @moduledoc false

  alias Mallard.Binary, as: B

  @type_id 1
  @quack_version 1

  def encode(opts \\ []) do
    auth_string = Keyword.get(opts, :auth_string)
    client_platform = Keyword.get(opts, :client_platform, "mallard-elixir")

    header =
      B.encode_object(
        B.encode_field(1, B.encode_uleb(@type_id)) <>
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

  defp maybe_string_field(_id, nil), do: <<>>
  defp maybe_string_field(_id, ""), do: <<>>
  defp maybe_string_field(id, value), do: B.encode_field(id, B.encode_string(value))
end
