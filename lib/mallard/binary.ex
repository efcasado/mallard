defmodule Mallard.Binary do
  @moduledoc """
  DuckDB BinarySerializer primitives for the Quack wire protocol.

  Each message is two back-to-back objects (header + body). An object is a
  sequence of (field_id::LE-uint16, value) pairs terminated by FIELD_END
  (0xFFFF). Integer values use LEB128; strings are ULEB128-length-prefixed
  UTF-8 bytes.
  """

  import Bitwise

  @field_end 0xFFFF
  # Sentinel used by the protocol for absent optional indices.
  @optional_index_invalid 0xFFFF_FFFF_FFFF_FFFF

  def optional_index_invalid, do: @optional_index_invalid

  # ── Encoding ─────────────────────────────────────────────────────────────

  @doc "Wrap encoded fields binary with the FIELD_END (0xFFFF) terminator."
  def encode_object(fields) when is_binary(fields) do
    fields <> <<@field_end::little-16>>
  end

  @doc "Prepend a 2-byte little-endian field ID to a value binary."
  def encode_field(id, value) when is_integer(id) and is_binary(value) do
    <<id::little-16>> <> value
  end

  @doc "Encode a non-negative integer as unsigned LEB128."
  def encode_uleb(n) when is_integer(n) and n >= 0, do: do_encode_uleb(n)

  defp do_encode_uleb(n) when n < 128, do: <<n>>
  defp do_encode_uleb(n), do: <<(n &&& 0x7F) ||| 0x80>> <> do_encode_uleb(n >>> 7)

  @doc "Encode a signed integer as signed LEB128."
  def encode_sleb(n) when is_integer(n), do: do_encode_sleb(n)

  defp do_encode_sleb(n) do
    byte = n &&& 0x7F
    shifted = n >>> 7
    sign_bit = byte &&& 0x40
    done = (shifted == 0 and sign_bit == 0) or (shifted == -1 and sign_bit != 0)
    if done, do: <<byte>>, else: <<byte ||| 0x80>> <> do_encode_sleb(shifted)
  end

  @doc "Encode a UTF-8 string with a ULEB128 length prefix."
  def encode_string(s) when is_binary(s), do: encode_uleb(byte_size(s)) <> s

  # ── Decoding ─────────────────────────────────────────────────────────────

  @doc "Decode an unsigned LEB128 integer. Returns `{value, rest}`."
  def decode_uleb(binary), do: do_decode_uleb(binary, 0, 0)

  defp do_decode_uleb(<<b, rest::binary>>, acc, shift) when (b &&& 0x80) == 0 do
    {acc ||| b <<< shift, rest}
  end

  defp do_decode_uleb(<<b, rest::binary>>, acc, shift) do
    do_decode_uleb(rest, acc ||| (b &&& 0x7F) <<< shift, shift + 7)
  end

  @doc "Decode a signed LEB128 integer. Returns `{value, rest}`."
  def decode_sleb(binary), do: do_decode_sleb(binary, 0, 0)

  defp do_decode_sleb(<<byte, rest::binary>>, acc, shift) do
    new_acc = acc ||| (byte &&& 0x7F) <<< shift
    new_shift = shift + 7

    if (byte &&& 0x80) == 0 do
      signed =
        if (byte &&& 0x40) == 0,
          do: new_acc,
          else: new_acc ||| bnot(0) <<< new_shift

      {signed, rest}
    else
      do_decode_sleb(rest, new_acc, new_shift)
    end
  end

  @doc "Decode a UTF-8 string with a ULEB128 length prefix. Returns `{string, rest}`."
  def decode_string(binary) do
    {len, rest} = decode_uleb(binary)
    {binary_part(rest, 0, len), binary_part(rest, len, byte_size(rest) - len)}
  end

  @doc "Peek at the next 2-byte field ID without consuming it."
  def peek_field_id(<<id::little-16, _::binary>>), do: id

  @doc "Consume and return the next 2-byte field ID."
  def read_field_id(<<id::little-16, rest::binary>>), do: {id, rest}

  @doc "Consume the FIELD_END (0xFFFF) terminator and return the remaining binary."
  def read_end_object(<<0xFF, 0xFF, rest::binary>>), do: rest

  @doc """
  Read an optional field if the next field ID matches; otherwise return `default`.

  `decode_fn` receives the binary after the field ID and must return `{value, rest}`.
  """
  def read_optional_field(field_id, binary, default, decode_fn) do
    if peek_field_id(binary) == field_id do
      {_id, rest} = read_field_id(binary)
      decode_fn.(rest)
    else
      {default, binary}
    end
  end

  @doc """
  Read a required field, raising if the next field ID does not match.

  `decode_fn` receives the binary after the field ID and must return `{value, rest}`.
  """
  def read_required_field(field_id, binary, decode_fn) do
    case read_field_id(binary) do
      {^field_id, rest} -> decode_fn.(rest)
      {other, _} -> raise "Expected field #{field_id}, got field #{other}"
    end
  end
end
