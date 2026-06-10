defmodule Mallard.Protocol.PrepareResponse do
  @moduledoc false

  alias Mallard.Binary, as: B

  @logical_type_integer 13
  @logical_type_varchar 25

  def decode(_header, binary) do
    {result_types, rest} = B.read_optional_field(1, binary, [], &decode_logical_type_list/1)
    {result_names, rest} = B.read_optional_field(2, rest, [], &decode_string_list/1)
    {_needs_more, rest} = B.read_optional_field(3, rest, false, &B.decode_bool/1)
    {chunks, rest} = B.read_optional_field(4, rest, [], &decode_chunk_wrapper_list(&1, result_types))
    {_uuid, rest} = B.read_optional_field(5, rest, nil, &decode_hugeint/1)
    B.read_end_object(rest)

    rows =
      Enum.flat_map(chunks, fn {row_count, columns} ->
        if row_count == 0, do: [], else: columns |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
      end)

    columns =
      result_names
      |> Enum.zip(result_types)
      |> Enum.map(fn {name, type} -> %{name: name, type: type} end)

    {:ok, %{type: :prepare_response, columns: columns, rows: rows}}
  end

  defp decode_string_list(binary), do: B.decode_list(binary, &B.decode_string/1)
  defp decode_logical_type_list(binary), do: B.decode_list(binary, &decode_logical_type/1)

  defp decode_logical_type(binary) do
    {id, rest} = B.read_required_field(100, binary, &B.decode_uleb/1)
    {_info, rest} = B.read_optional_field(101, rest, nil, &decode_type_info/1)
    rest = B.read_end_object(rest)
    {id, rest}
  end

  defp decode_type_info(binary) do
    {discriminator, rest} = B.read_required_field(100, binary, &B.decode_uleb/1)
    {_alias, rest} = B.read_optional_field(101, rest, nil, &B.decode_string/1)
    rest = skip_type_info_extras(discriminator, rest)
    {nil, rest}
  end

  # STRING type info (discriminator 3): has field 200 = collation string
  defp skip_type_info_extras(3, binary) do
    {_collation, rest} = B.read_optional_field(200, binary, "", &B.decode_string/1)
    B.read_end_object(rest)
  end

  defp skip_type_info_extras(_disc, binary), do: B.read_end_object(binary)

  defp decode_hugeint(binary) do
    {upper, rest} = B.decode_sleb(binary)
    {lower, rest} = B.decode_uleb(rest)
    {{upper, lower}, rest}
  end

  # DuckDB serializes optional lists as bool (present?) + ULEB128 count + elements.
  defp decode_chunk_wrapper_list(binary, result_types) do
    {_present, rest} = B.decode_bool(binary)
    B.decode_list(rest, &decode_chunk_wrapper(&1, result_types))
  end

  defp decode_chunk_wrapper(binary, result_types) do
    {chunk, rest} = B.read_required_field(300, binary, &decode_chunk(&1, result_types))
    rest = B.read_end_object(rest)
    {chunk, rest}
  end

  defp decode_chunk(binary, outer_types) do
    {row_count, rest} = B.read_required_field(100, binary, &B.decode_uleb/1)
    {_types, rest} = B.read_optional_field(101, rest, [], &decode_logical_type_list/1)
    {columns, rest} = B.read_optional_field(102, rest, [], &decode_columns(&1, outer_types, row_count))
    rest = B.read_end_object(rest)
    {{row_count, columns}, rest}
  end

  defp decode_columns(binary, types, row_count) do
    {_count, rest} = B.decode_uleb(binary)

    {cols_rev, rest} =
      Enum.reduce(types, {[], rest}, fn type, {acc, bin} ->
        {values, bin} = decode_vector(bin, type, row_count)
        {[values | acc], bin}
      end)

    {Enum.reverse(cols_rev), rest}
  end

  defp decode_vector(binary, type_id, row_count) do
    {_vec_type, rest} = B.read_optional_field(90, binary, 0, &B.decode_uleb/1)
    {has_validity, rest} = B.read_optional_field(100, rest, false, &B.decode_bool/1)

    {_validity, rest} =
      if has_validity,
        do: B.read_required_field(101, rest, &B.decode_string/1),
        else: {nil, rest}

    {values, rest} = B.read_required_field(102, rest, &decode_flat_data(&1, type_id, row_count))
    rest = B.read_end_object(rest)
    {values, rest}
  end

  defp decode_flat_data(binary, @logical_type_integer, _row_count) do
    {blob, rest} = B.decode_string(binary)
    {for(<<n::little-signed-32 <- blob>>, do: n), rest}
  end

  defp decode_flat_data(binary, @logical_type_varchar, _row_count) do
    B.decode_list(binary, &B.decode_string/1)
  end
end
