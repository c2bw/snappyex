defmodule SnappyEx.Framed.Encoder do
  @moduledoc false

  alias SnappyEx.Framed.Checksum

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
