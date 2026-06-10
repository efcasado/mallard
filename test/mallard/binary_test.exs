defmodule Mallard.BinaryTest do
  use ExUnit.Case, async: true

  alias Mallard.Binary, as: B

  describe "encode_uleb / decode_uleb" do
    test "zero" do
      assert B.encode_uleb(0) == <<0>>
      assert B.decode_uleb(<<0>>) == {0, <<>>}
    end

    test "single-byte value (< 128)" do
      assert B.encode_uleb(127) == <<127>>
      assert B.decode_uleb(<<127>>) == {127, <<>>}
    end

    test "two-byte value (128)" do
      assert B.encode_uleb(128) == <<0x80, 0x01>>
      assert B.decode_uleb(<<0x80, 0x01>>) == {128, <<>>}
    end

    test "OPTIONAL_INDEX_INVALID encodes to 10 bytes and round-trips" do
      val = B.optional_index_invalid()
      encoded = B.encode_uleb(val)
      assert byte_size(encoded) == 10
      assert B.decode_uleb(encoded) == {val, <<>>}
    end

    test "decode leaves trailing bytes intact" do
      assert B.decode_uleb(<<5, 99>>) == {5, <<99>>}
    end
  end

  describe "encode_sleb / decode_sleb" do
    test "zero" do
      assert B.encode_sleb(0) == <<0>>
      assert B.decode_sleb(<<0>>) == {0, <<>>}
    end

    test "positive value that fits in one byte (< 64)" do
      assert B.encode_sleb(63) == <<63>>
      assert B.decode_sleb(<<63>>) == {63, <<>>}
    end

    test "positive 64 needs two bytes (bit 6 would set the sign bit)" do
      assert B.encode_sleb(64) == <<0xC0, 0x00>>
      assert B.decode_sleb(<<0xC0, 0x00>>) == {64, <<>>}
    end

    test "-1 encodes to a single 0x7F byte" do
      assert B.encode_sleb(-1) == <<0x7F>>
      assert B.decode_sleb(<<0x7F>>) == {-1, <<>>}
    end

    test "-128 encodes to two bytes" do
      assert B.encode_sleb(-128) == <<0x80, 0x7F>>
      assert B.decode_sleb(<<0x80, 0x7F>>) == {-128, <<>>}
    end

    test "round-trips for a range of values" do
      for n <- [-32_768, -128, -64, -1, 0, 63, 64, 127, 128, 32_767] do
        {decoded, <<>>} = B.decode_sleb(B.encode_sleb(n))
        assert decoded == n
      end
    end
  end

  describe "encode_string / decode_string" do
    test "empty string" do
      assert B.encode_string("") == <<0>>
      assert B.decode_string(<<0>>) == {"", <<>>}
    end

    test "ASCII string" do
      assert B.encode_string("hi") == <<2, ?h, ?i>>
      assert B.decode_string(<<2, ?h, ?i>>) == {"hi", <<>>}
    end

    test "decode leaves trailing bytes intact" do
      assert B.decode_string(<<3, ?a, ?b, ?c, 99>>) == {"abc", <<99>>}
    end
  end

  describe "encode_object" do
    test "appends FIELD_END 0xFFFF terminator" do
      assert B.encode_object(<<>>) == <<0xFF, 0xFF>>
      assert B.encode_object(<<1, 2>>) == <<1, 2, 0xFF, 0xFF>>
    end
  end

  describe "encode_field" do
    test "prepends field ID as little-endian uint16" do
      assert B.encode_field(1, <<0x42>>) == <<0x01, 0x00, 0x42>>
      assert B.encode_field(0x0102, <<0xFF>>) == <<0x02, 0x01, 0xFF>>
    end
  end

  describe "read_optional_field" do
    test "reads and returns value when field ID matches" do
      binary = <<0x01, 0x00>> <> B.encode_uleb(42) <> <<0xFF, 0xFF>>
      {val, rest} = B.read_optional_field(1, binary, :missing, &B.decode_uleb/1)
      assert val == 42
      assert rest == <<0xFF, 0xFF>>
    end

    test "returns default when field ID does not match" do
      binary = <<0x02, 0x00, 0x0A, 0xFF, 0xFF>>
      {val, rest} = B.read_optional_field(1, binary, :missing, &B.decode_uleb/1)
      assert val == :missing
      assert rest == binary
    end
  end

  describe "read_required_field" do
    test "reads value when field ID matches" do
      binary = <<0x03, 0x00>> <> B.encode_uleb(7)
      {val, <<>>} = B.read_required_field(3, binary, &B.decode_uleb/1)
      assert val == 7
    end

    test "raises when field ID does not match" do
      binary = <<0x02, 0x00, 0x07>>

      assert_raise RuntimeError, ~r/Expected field 3, got field 2/, fn ->
        B.read_required_field(3, binary, &B.decode_uleb/1)
      end
    end
  end
end
