defmodule SnappyEx.StreamTest do
  use ExUnit.Case

  @stream_identifier <<0xFF, 6::little-24, "sNaPpY">>

  test "streaming compression is lazy and matches one-shot framing" do
    parent = self()

    source =
      Stream.map(["abc"], fn chunk ->
        send(parent, :compression_source_read)
        chunk
      end)

    compressed_stream = SnappyEx.compress_framed_stream(source)

    assert Enum.take(compressed_stream, 1) == [@stream_identifier]
    refute_received :compression_source_read

    input = :binary.copy("abcdefghijklmnopqrstuvwxyz0123456789", 10_000)
    input_chunks = binary_chunks(input, 8_191)
    fragments = input_chunks |> SnappyEx.compress_framed_stream() |> Enum.to_list()

    assert Enum.all?(fragments, &is_binary/1)
    assert IO.iodata_to_binary(fragments) == SnappyEx.compress_framed(input)
  end

  test "streaming compression accepts binary and nested iodata input chunks" do
    input_chunks = ["ab", [99, [<<100>>, 101]], <<102>>]
    expected_input = IO.iodata_to_binary(input_chunks)

    assert input_chunks
           |> SnappyEx.compress_framed_stream()
           |> stream_to_binary() == SnappyEx.compress_framed(expected_input)

    assert "abcdef"
           |> SnappyEx.compress_framed_stream()
           |> stream_to_binary() == SnappyEx.compress_framed("abcdef")
  end

  test "streaming compression handles byte-sized source chunks" do
    input = :binary.copy("abcd", 16_385)

    assert input
           |> binary_chunks(1)
           |> SnappyEx.compress_framed_stream()
           |> stream_to_binary() == SnappyEx.compress_framed(input)
  end

  test "streaming decompression handles arbitrary input boundaries" do
    input = :binary.copy("banana bandana ", 20_000)
    compressed = SnappyEx.compress_framed(input)

    output_chunks =
      compressed
      |> binary_chunks(3)
      |> SnappyEx.decompress_framed_stream()
      |> Enum.to_list()

    assert Enum.all?(output_chunks, &(byte_size(&1) <= 65_536))
    assert IO.iodata_to_binary(output_chunks) == input
    assert compressed |> SnappyEx.decompress_framed_stream() |> stream_to_binary() == input
  end

  test "streaming decompression applies backpressure between data chunks" do
    <<@stream_identifier::binary, first_chunk::binary>> = SnappyEx.compress_framed("first")
    <<@stream_identifier::binary, second_chunk::binary>> = SnappyEx.compress_framed("second")
    parent = self()

    source =
      [@stream_identifier <> first_chunk, second_chunk]
      |> Stream.with_index()
      |> Stream.map(fn {chunk, index} ->
        send(parent, {:decompression_source_read, index})
        chunk
      end)

    assert source |> SnappyEx.decompress_framed_stream() |> Enum.take(1) == ["first"]
    assert_received {:decompression_source_read, 0}
    refute_received {:decompression_source_read, 1}
  end

  test "streaming decompression does not inspect a following frame until demanded" do
    <<@stream_identifier::binary, first_chunk::binary>> = SnappyEx.compress_framed("first")
    framed = @stream_identifier <> first_chunk <> <<0x02, 0::little-24>>
    parent = self()

    source =
      Stream.resource(
        fn -> framed end,
        fn
          <<>> -> {:halt, <<>>}
          data -> {[data], <<>>}
        end,
        fn _state -> send(parent, :decompression_source_closed) end
      )

    assert source |> SnappyEx.decompress_framed_stream() |> Enum.take(1) == ["first"]
    assert_received :decompression_source_closed
    refute_received :decompression_source_closed

    assert_raise ArgumentError, ~r/unsupported_chunk/, fn ->
      framed |> SnappyEx.decompress_framed_stream() |> Enum.to_list()
    end
  end

  test "streaming decompression enforces the aggregate output limit" do
    input = :binary.copy("a", 65_537)
    compressed = SnappyEx.compress_framed(input)

    assert compressed
           |> SnappyEx.decompress_framed_stream(max_output_size: byte_size(input))
           |> stream_to_binary() == input

    assert_raise ArgumentError, ~r/output_limit_exceeded/, fn ->
      compressed
      |> SnappyEx.decompress_framed_stream(max_output_size: byte_size(input) - 1)
      |> Enum.to_list()
    end

    assert_raise ArgumentError, ~r/max_output_size/, fn ->
      SnappyEx.decompress_framed_stream(compressed, max_output_size: -1)
    end

    assert_raise ArgumentError, ~r/unknown keys \[:unknown\]/, fn ->
      SnappyEx.decompress_framed_stream(compressed, unknown: true)
    end

    assert_raise ArgumentError, ~r/duplicate keys \[:max_output_size\]/, fn ->
      SnappyEx.decompress_framed_stream(compressed, max_output_size: 1, max_output_size: 2)
    end

    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      SnappyEx.decompress_framed_stream(compressed, [:invalid])
    end
  end

  test "streaming decompression rejects compressed chunks larger than the framed limit" do
    raw = SnappyEx.compress(:binary.copy("a", 65_537))
    payload = <<0::little-32, raw::binary>>
    framed = <<@stream_identifier::binary, 0x00, byte_size(payload)::little-24, payload::binary>>

    assert_raise ArgumentError, ~r/invalid_chunk_length/, fn ->
      framed
      |> binary_chunks(5)
      |> SnappyEx.decompress_framed_stream()
      |> Enum.to_list()
    end
  end

  test "streaming decompression rejects invalid payload lengths before reading payload data" do
    parent = self()

    identifier_payload =
      Stream.map(["ignored"], fn chunk ->
        send(parent, :identifier_payload_read)
        chunk
      end)

    identifier_source = Stream.concat([<<0xFF, 7::little-24>>], identifier_payload)

    assert_raise ArgumentError, ~r/invalid_stream_identifier/, fn ->
      identifier_source
      |> SnappyEx.decompress_framed_stream()
      |> Enum.to_list()
    end

    refute_received :identifier_payload_read

    compressed_payload =
      Stream.map(["ignored"], fn chunk ->
        send(parent, :compressed_payload_read)
        chunk
      end)

    compressed_source =
      Stream.concat(
        [@stream_identifier <> <<0x00, 0xFFFFFF::little-24>>],
        compressed_payload
      )

    assert_raise ArgumentError, ~r/invalid_chunk_length/, fn ->
      compressed_source
      |> SnappyEx.decompress_framed_stream()
      |> Enum.to_list()
    end

    refute_received :compressed_payload_read
  end

  test "streaming decompression raises for corrupt and truncated input" do
    compressed = SnappyEx.compress_framed("abc")
    corrupted = binary_part(compressed, 0, byte_size(compressed) - 1) <> <<0>>
    truncated = binary_part(compressed, 0, byte_size(compressed) - 1)
    parent = self()

    corrupt_source =
      Stream.resource(
        fn -> corrupted end,
        fn
          <<>> -> {:halt, <<>>}
          data -> {[data], <<>>}
        end,
        fn _state -> send(parent, :corrupt_source_closed) end
      )

    assert_raise ArgumentError, ~r/checksum_mismatch/, fn ->
      Enum.to_list(SnappyEx.decompress_framed_stream(corrupt_source))
    end

    assert_received :corrupt_source_closed
    refute_received :corrupt_source_closed

    assert_raise ArgumentError, ~r/truncated_chunk/, fn ->
      truncated
      |> binary_chunks(1)
      |> SnappyEx.decompress_framed_stream()
      |> Enum.to_list()
    end

    assert_raise ArgumentError, ~r/missing_stream_identifier/, fn ->
      Enum.to_list(SnappyEx.decompress_framed_stream("abc"))
    end
  end

  test "streaming decompression skips extension chunks and repeated identifiers" do
    <<@stream_identifier::binary, data_chunk::binary>> = SnappyEx.compress_framed("ok")

    compressed =
      IO.iodata_to_binary([
        @stream_identifier,
        <<0x80, 3::little-24, "abc">>,
        @stream_identifier,
        data_chunk
      ])

    assert compressed
           |> binary_chunks(1)
           |> SnappyEx.decompress_framed_stream()
           |> stream_to_binary() == "ok"
  end

  test "empty streaming input produces and consumes an empty framed stream" do
    assert Enum.to_list(SnappyEx.compress_framed_stream([])) == [@stream_identifier]
    assert Enum.to_list(SnappyEx.decompress_framed_stream([])) == []
    assert Enum.to_list(SnappyEx.decompress_framed_stream(<<>>)) == []
    assert Enum.to_list(SnappyEx.decompress_framed_stream(@stream_identifier)) == []
    assert Enum.to_list(SnappyEx.decompress_framed_stream(<<>>, max_output_size: 0)) == []
    assert Enum.to_list(SnappyEx.decompress_framed_stream(@stream_identifier, max_output_size: 0)) == []
  end

  defp binary_chunks(binary, chunk_size) do
    Stream.unfold(binary, fn
      <<>> -> nil
      binary when byte_size(binary) <= chunk_size -> {binary, <<>>}
      <<chunk::binary-size(^chunk_size), rest::binary>> -> {chunk, rest}
    end)
  end

  defp stream_to_binary(stream) do
    stream
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end
end
