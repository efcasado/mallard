defmodule Mallard.Protocol.ConnectionResponse do
  @moduledoc false

  alias Mallard.Binary, as: B

  def decode(header, binary) do
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
end
