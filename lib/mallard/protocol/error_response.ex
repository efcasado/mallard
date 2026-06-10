defmodule Mallard.Protocol.ErrorResponse do
  @moduledoc false

  alias Mallard.Binary, as: B

  def decode(binary) do
    {message, rest} = B.read_optional_field(1, binary, "", &B.decode_string/1)
    B.read_end_object(rest)
    {:error, {:server_error, message}}
  end
end
