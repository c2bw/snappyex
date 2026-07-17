defmodule SnappyExTest do
  use ExUnit.Case
  doctest SnappyEx

  @fixture_expectations [
    {"testdata/alice29.txt", 152_089, 96_470, "642f365ba8cbc55afa724d30e4f0ba96273b24bbb90cc69acbcfa5f203ba06ba"},
    {"testdata/html", 102_400, 28_953, "af2a2e72d0c4f97fe8c31604c59d063581ab9a3bbbf7f506bfd91ddd7b0b3263"},
    {"testdata/urls.10K", 712_086, 376_692, "e2a0104a5f97dc04b65923df244b0b6069db9dd8be7cd5205c2e05dadfbcb331"}
  ]

  defp assert_compresses_to(input, expected) do
    assert SnappyEx.compress(input) == expected
    assert SnappyEx.decompress(expected) == {:ok, input}
    assert SnappyEx.decompress!(expected) == input
  end

  defp assert_roundtrips(input) do
    compressed = SnappyEx.compress(input)

    assert SnappyEx.decompress(compressed) == {:ok, input}
    assert SnappyEx.decompress!(compressed) == input

    compressed
  end

  defp assert_framed_roundtrips(input) do
    compressed = SnappyEx.compress_framed(input)

    assert SnappyEx.decompress_framed(compressed) == {:ok, input}
    assert SnappyEx.decompress_framed!(compressed) == input

    compressed
  end

  test "compresses and decompresses raw snappy blocks" do
    input = "banana bandana banana bandana"
    compressed = SnappyEx.compress(input)

    assert compressed != input
    assert SnappyEx.decompress(compressed) == {:ok, input}
    assert SnappyEx.decompress!(compressed) == input
  end

  test "roundtrips arbitrary byte binaries" do
    input = <<0, 1, 2, 255, 128, 0, 64, 250, 7, 8, 9>> <> :binary.copy(<<1, 2, 3, 4>>, 8)

    assert SnappyEx.decompress(SnappyEx.compress(input)) == {:ok, input}
  end

  test "compresses empty input to an empty raw snappy block" do
    assert_compresses_to("", <<0>>)
  end

  test "compresses short literal input to the expected raw snappy bytes" do
    assert_compresses_to("abc", <<3, 8, "abc">>)
  end

  test "compresses the largest short literal input to the expected raw snappy bytes" do
    input = for byte <- 0..59, into: <<>>, do: <<byte>>

    assert_compresses_to(input, <<60, 236, input::binary>>)
  end

  test "compresses varint preamble and extended literal length bytes" do
    input = for byte <- 0..129, into: <<>>, do: <<byte>>

    assert_compresses_to(input, <<0x82, 0x01, 0xF0, 0x81, input::binary>>)
  end

  test "compresses repeated input to literal and copy commands" do
    assert_compresses_to("abcabcabc", <<9, 12, "abca", 5, 3>>)
  end

  test "splits long copies into snappy-sized copy chunks" do
    input = :binary.copy("abcd", 21)

    assert_compresses_to(input, <<84, 12, "abcd", 254, 4, 0, 62, 4, 0>>)
  end

  test "uses copy-1 chunks instead of invalid tiny copy remainders" do
    assert_compresses_to(:binary.copy("abcd", 17) <> "a", <<69, 12, "abcd", 242, 4, 0, 1, 4>>)
    assert_compresses_to(:binary.copy("abcd", 17) <> "ab", <<70, 12, "abcd", 246, 4, 0, 1, 4>>)
    assert_compresses_to(:binary.copy("abcd", 17) <> "abc", <<71, 12, "abcd", 250, 4, 0, 1, 4>>)
  end

  test "roundtrips fixture files with expected compressed output" do
    Enum.each(@fixture_expectations, fn {path, input_size, compressed_size, compressed_sha256} ->
      input = File.read!(path)
      compressed = assert_roundtrips(input)

      assert byte_size(input) == input_size
      assert byte_size(compressed) == compressed_size
      assert Base.encode16(:crypto.hash(:sha256, compressed), case: :lower) == compressed_sha256
    end)
  end

  test "compression is deterministic across repeated calls" do
    input = :binary.copy("abcdefghijklmnopqrstuvwxyz0123456789", 128)
    expected = SnappyEx.compress(input)

    for _run <- 1..5 do
      assert SnappyEx.compress(input) == expected
    end
  end

  test "compression cleans its process dictionary match table" do
    keys_before = MapSet.new(:erlang.get_keys())

    assert_roundtrips(:binary.copy("abcdefghijklmnopqrstuvwxyz0123456789", 128))

    assert MapSet.new(:erlang.get_keys()) == keys_before
  end

  test "decompresses a raw snappy literal block" do
    assert SnappyEx.decompress(<<3, 8, "abc">>) == {:ok, "abc"}
  end

  test "decompresses copy commands with overlapping output" do
    assert SnappyEx.decompress(<<5, 0, "a", 1, 1>>) == {:ok, "aaaaa"}
  end

  test "decompresses copy commands with two-byte offsets" do
    # length preamble=9, literal "abc", copy 6 bytes from offset 3
    assert SnappyEx.decompress(<<9, 8, "abc", 22, 3, 0>>) == {:ok, "abcabcabc"}
  end

  test "decompresses copy commands with four-byte offsets" do
    assert SnappyEx.decompress(<<9, 8, "abc", 23, 3, 0, 0, 0>>) == {:ok, "abcabcabc"}
  end

  test "enforces uint32 bounds on the raw snappy length preamble" do
    assert SnappyEx.decompress(<<0xFF, 0xFF, 0xFF, 0xFF, 0x0F>>) == {:error, :invalid_length}
    assert SnappyEx.decompress(<<0x80, 0x80, 0x80, 0x80, 0x10>>) == {:error, :malformed_preamble}
  end

  test "rejects malformed raw snappy blocks" do
    assert SnappyEx.decompress(<<>>) == {:error, :empty_input}
    assert SnappyEx.decompress(<<0x80>>) == {:error, :malformed_preamble}
    assert SnappyEx.decompress(<<0x80, 0x80, 0x80, 0x80, 0x80, 0>>) == {:error, :malformed_preamble}
    assert SnappyEx.decompress(<<1>>) == {:error, :invalid_length}
    assert SnappyEx.decompress(<<2, 8, "abc">>) == {:error, :invalid_length}
    assert SnappyEx.decompress(<<1, 1, 0>>) == {:error, :invalid_offset}
    assert SnappyEx.decompress(<<3, 8, "a">>) == {:error, :truncated_literal}
    assert SnappyEx.decompress(<<3, 240>>) == {:error, :truncated_literal}
    assert SnappyEx.decompress(<<5, 0, "a", 1>>) == {:error, :truncated_copy}
    assert SnappyEx.decompress(<<5, 0, "a", 2, 1>>) == {:error, :truncated_copy}
    assert SnappyEx.decompress(<<5, 0, "a", 3, 1, 0, 0>>) == {:error, :truncated_copy}

    assert_raise ArgumentError, fn ->
      SnappyEx.decompress!(<<1, 1, 0>>)
    end
  end

  test "compresses empty input to an empty framed snappy stream" do
    assert SnappyEx.compress_framed("") == <<0xFF, 6::little-24, "sNaPpY">>
    assert SnappyEx.decompress_framed(<<0xFF, 6::little-24, "sNaPpY">>) == {:ok, ""}
  end

  test "compresses and decompresses framed snappy streams" do
    input = "banana bandana banana bandana"
    compressed = assert_framed_roundtrips(input)

    assert <<0xFF, 6::little-24, "sNaPpY", _chunks::binary>> = compressed
  end

  test "uses uncompressed framed chunks when raw compression would be larger" do
    compressed = assert_framed_roundtrips("abc")

    assert <<0xFF, 6::little-24, "sNaPpY", 0x01, 7::little-24, _checksum::little-32, "abc">> = compressed
  end

  test "uses compressed framed chunks when raw compression is smaller" do
    input = "abcabcabc"
    compressed = assert_framed_roundtrips(input)

    assert <<0xFF, 6::little-24, "sNaPpY", 0x00, 12::little-24, _checksum::little-32, raw::binary>> =
             compressed

    assert SnappyEx.decompress(raw) == {:ok, input}
  end

  test "splits framed streams into 64 KiB chunks" do
    input = :binary.copy("a", 65_537)
    compressed = assert_framed_roundtrips(input)

    assert <<0xFF, 6::little-24, "sNaPpY", first_type, first_length::little-24, first::binary-size(first_length), second_type,
             second_length::little-24, second::binary-size(second_length)>> = compressed

    assert first_type in [0x00, 0x01]
    assert second_type in [0x00, 0x01]
    assert byte_size(first) > 4
    assert byte_size(second) > 4
  end

  test "accepts compressed framed chunks at the 64 KiB limit" do
    input = :binary.copy("a", 65_536)
    compressed = assert_framed_roundtrips(input)

    assert <<0xFF, 6::little-24, "sNaPpY", 0x00, _chunk::binary>> = compressed
  end

  test "parallel framed compression preserves chunk order" do
    stream_identifier = <<0xFF, 6::little-24, "sNaPpY">>

    chunks = [
      :binary.copy(<<0x11>>, 65_536),
      :binary.copy(<<0x22>>, 65_536),
      :binary.copy(<<0x33>>, 65_536),
      :binary.copy(<<0x44>>, 65_536),
      :binary.copy(<<0x55>>, 257)
    ]

    input = IO.iodata_to_binary(chunks)

    encoded_chunks =
      Enum.map(chunks, fn chunk ->
        <<^stream_identifier::binary, encoded_chunk::binary>> = SnappyEx.compress_framed(chunk)
        encoded_chunk
      end)

    expected = IO.iodata_to_binary([stream_identifier | encoded_chunks])
    compressed = SnappyEx.compress_framed(input)

    assert compressed == expected
    assert SnappyEx.decompress_framed(compressed) == {:ok, input}
  end

  test "framed decompression skips skippable chunks and repeated stream identifiers" do
    stream_identifier = <<0xFF, 6::little-24, "sNaPpY">>
    <<^stream_identifier::binary, data_chunk::binary>> = SnappyEx.compress_framed("ok")

    framed = [
      stream_identifier,
      <<0x80, 3::little-24, "abc">>,
      stream_identifier,
      data_chunk
    ]

    assert SnappyEx.decompress_framed(IO.iodata_to_binary(framed)) == {:ok, "ok"}
  end

  test "rejects malformed framed snappy streams" do
    stream_identifier = <<0xFF, 6::little-24, "sNaPpY">>
    framed = SnappyEx.compress_framed("abc")
    bad_checksum = binary_part(framed, 0, byte_size(framed) - 1) <> <<0>>
    oversized_raw = <<0x81, 0x80, 0x04, 0x01, 0x00>>
    oversized_payload = <<0::little-32, oversized_raw::binary>>
    oversized_chunk = <<0x00, byte_size(oversized_payload)::little-24, oversized_payload::binary>>

    assert SnappyEx.decompress_framed(<<>>) == {:error, :missing_stream_identifier}
    assert SnappyEx.decompress_framed("abc") == {:error, :missing_stream_identifier}
    assert SnappyEx.decompress_framed(<<0xFF, 5::little-24, "sNaPp">>) == {:error, :invalid_stream_identifier}
    assert SnappyEx.decompress_framed(stream_identifier <> <<0x00, 1, 0>>) == {:error, :truncated_chunk_header}
    assert SnappyEx.decompress_framed(stream_identifier <> <<0x02, 0::little-24>>) == {:error, :unsupported_chunk}
    assert SnappyEx.decompress_framed(stream_identifier <> <<0x00, 3::little-24, "abc">>) == {:error, :invalid_chunk_length}
    assert SnappyEx.decompress_framed(stream_identifier <> oversized_chunk) == {:error, :invalid_chunk_length}
    assert SnappyEx.decompress_framed(bad_checksum) == {:error, :checksum_mismatch}

    assert_raise ArgumentError, fn ->
      SnappyEx.decompress_framed!(stream_identifier <> <<0x02, 0::little-24>>)
    end
  end
end
