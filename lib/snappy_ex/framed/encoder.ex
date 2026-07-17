defmodule SnappyEx.Framed.Encoder do
  @moduledoc false

  alias SnappyEx.Framed.Checksum
  alias SnappyEx.Framed.StreamInput

  @max_uncompressed_chunk_size 65_536
  @parallel_compression_threshold @max_uncompressed_chunk_size * 4
  @max_parallel_chunks 4
  @stream_identifier <<0xFF, 6::little-24, "sNaPpY">>
  @compressed_data 0x00
  @uncompressed_data 0x01

  @compile {:inline, [compress: 1, encode_chunks_sequential: 1, encode_data_chunk: 1, encode_chunk: 2]}

  @spec compress(binary) :: binary
  def compress(input) when is_binary(input) do
    [@stream_identifier | encode_chunks(input)]
    |> IO.iodata_to_binary()
  end

  @spec compress_stream(binary | Enumerable.t()) :: Enumerable.t()
  def compress_stream(input) do
    end_marker = make_ref()

    encoded_chunks =
      input
      |> StreamInput.chunks(@max_uncompressed_chunk_size)
      |> Stream.concat([end_marker])
      |> Stream.transform({0, []}, fn
        ^end_marker, {0, []} ->
          {[], {0, []}}

        ^end_marker, {_buffered_size, buffered_parts} ->
          buffered = buffered_parts |> Enum.reverse() |> IO.iodata_to_binary()
          {[encode_stream_chunk(buffered)], {0, []}}

        chunk, buffered ->
          encode_stream_input_chunk(buffered, chunk)
      end)

    Stream.concat([@stream_identifier], encoded_chunks)
  end

  defp encode_stream_input_chunk({buffered_size, buffered_parts}, chunk) do
    needed = @max_uncompressed_chunk_size - buffered_size

    if byte_size(chunk) < needed do
      {[], {buffered_size + byte_size(chunk), [chunk | buffered_parts]}}
    else
      <<chunk_head::binary-size(^needed), rest::binary>> = chunk
      uncompressed = IO.iodata_to_binary([Enum.reverse(buffered_parts), chunk_head])
      rest_parts = if rest == <<>>, do: [], else: [rest]

      {[encode_stream_chunk(uncompressed)], {byte_size(rest), rest_parts}}
    end
  end

  defp encode_stream_chunk(uncompressed) do
    uncompressed
    |> encode_data_chunk()
    |> IO.iodata_to_binary()
  end

  defp encode_chunks(input) when byte_size(input) >= @parallel_compression_threshold do
    case parallel_concurrency() do
      1 ->
        encode_chunks_sequential(input)

      max_concurrency ->
        input
        |> chunk_stream()
        |> Task.async_stream(&encode_data_chunk/1,
          max_concurrency: max_concurrency,
          ordered: true,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, chunk} -> chunk end)
    end
  end

  defp encode_chunks(input), do: encode_chunks_sequential(input)

  defp encode_chunks_sequential(<<>>), do: []

  defp encode_chunks_sequential(<<chunk::binary-size(@max_uncompressed_chunk_size), rest::binary>>) do
    [encode_data_chunk(chunk) | encode_chunks_sequential(rest)]
  end

  defp encode_chunks_sequential(chunk), do: [encode_data_chunk(chunk)]

  defp chunk_stream(input) do
    Stream.unfold(input, fn
      <<>> -> nil
      <<chunk::binary-size(@max_uncompressed_chunk_size), rest::binary>> -> {chunk, rest}
      chunk -> {chunk, <<>>}
    end)
  end

  defp parallel_concurrency do
    System.schedulers_online()
    |> div(2)
    |> max(1)
    |> min(@max_parallel_chunks)
  end

  defp encode_data_chunk(uncompressed) do
    checksum = Checksum.masked(uncompressed)
    compressed = SnappyEx.Raw.compress(uncompressed)

    if byte_size(compressed) < byte_size(uncompressed) do
      encode_chunk(@compressed_data, <<checksum::little-32, compressed::binary>>)
    else
      encode_chunk(@uncompressed_data, <<checksum::little-32, uncompressed::binary>>)
    end
  end

  defp encode_chunk(type, data) do
    [<<type, byte_size(data)::little-24>>, data]
  end
end
