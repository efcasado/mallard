defmodule Mallard.Protocol.SuccessResponse do
  @moduledoc false

  alias Mallard.Binary, as: B

  def decode(binary) do
    B.read_end_object(binary)
    {:ok, %{type: :success_response}}
  end
end
