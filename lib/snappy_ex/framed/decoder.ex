defmodule SnappyEx.Framed.Decoder do
  @moduledoc false

  alias SnappyEx.Framed.Checksum

  @max_uncompressed_chunk_size 65_536
  @stream_identifier "sNaPpY"
  @compressed_data 0x00
  @uncompressed_data 0x01
  @stream_identifier_chunk 0xFF

  @type decompress_error ::
          :missing_stream_identifier
          | :invalid_stream_identifier
          | :truncated_chunk_header
          | :truncated_chunk
          | :invalid_chunk_length
          | :unsupported_chunk
          | :checksum_mismatch
          | {:invalid_compressed_chunk, SnappyEx.Raw.decompress_error()}

  @spec decompress(binary) :: {:ok, binary} | {:error, decompress_error}
  def decompress(compressed) when is_binary(compressed) do
    with {:ok, rest} <- decode_initial_stream_identifier(compressed),
         {:ok, output} <- decode_chunks(rest, []) do
      {:ok, output}
    end
  end

  @spec decompress!(binary) :: binary
  def decompress!(compressed) when is_binary(compressed) do
    case decompress(compressed) do
      {:ok, output} -> output
      {:error, reason} -> raise ArgumentError, "invalid snappy framed stream: #{inspect(reason)}"
    end
  end

  defp decode_initial_stream_identifier(<<@stream_identifier_chunk, 6::little-24, @stream_identifier, rest::binary>>) do
    {:ok, rest}
  end

  defp decode_initial_stream_identifier(<<@stream_identifier_chunk, length::little-24, rest::binary>>) do
    if byte_size(rest) < length do
      {:error, :truncated_chunk}
    else
      {:error, :invalid_stream_identifier}
    end
  end

  defp decode_initial_stream_identifier(compressed) when byte_size(compressed) < 4 do
    {:error, :missing_stream_identifier}
  end

  defp decode_initial_stream_identifier(_compressed), do: {:error, :missing_stream_identifier}

  defp decode_chunks(<<>>, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  defp decode_chunks(compressed, _acc) when byte_size(compressed) < 4 do
    {:error, :truncated_chunk_header}
  end

  defp decode_chunks(<<type, length::little-24, rest::binary>>, acc) do
    if byte_size(rest) < length do
      {:error, :truncated_chunk}
    else
      <<payload::binary-size(^length), chunk_rest::binary>> = rest

      with {:ok, decoded} <- decode_chunk(type, payload) do
        decode_chunks(chunk_rest, [decoded | acc])
      end
    end
  end

  defp decode_chunk(@compressed_data, <<expected_checksum::little-32, compressed::binary>>) do
    with {:ok, uncompressed} <- decode_raw_chunk(compressed),
         :ok <- validate_uncompressed_size(uncompressed),
         :ok <- validate_checksum(uncompressed, expected_checksum) do
      {:ok, uncompressed}
    end
  end

  defp decode_chunk(@compressed_data, _payload), do: {:error, :invalid_chunk_length}

  defp decode_chunk(@uncompressed_data, <<expected_checksum::little-32, uncompressed::binary>>) do
    with :ok <- validate_uncompressed_size(uncompressed),
         :ok <- validate_checksum(uncompressed, expected_checksum) do
      {:ok, uncompressed}
    end
  end

  defp decode_chunk(@uncompressed_data, _payload), do: {:error, :invalid_chunk_length}

  defp decode_chunk(@stream_identifier_chunk, @stream_identifier), do: {:ok, []}
  defp decode_chunk(@stream_identifier_chunk, _payload), do: {:error, :invalid_stream_identifier}

  defp decode_chunk(type, _payload) when type >= 0x80 and type <= 0xFE, do: {:ok, []}
  defp decode_chunk(_type, _payload), do: {:error, :unsupported_chunk}

  defp decode_raw_chunk(compressed) do
    case SnappyEx.Raw.decompress(compressed) do
      {:ok, uncompressed} -> {:ok, uncompressed}
      {:error, reason} -> {:error, {:invalid_compressed_chunk, reason}}
    end
  end

  defp validate_uncompressed_size(uncompressed) do
    if byte_size(uncompressed) <= @max_uncompressed_chunk_size do
      :ok
    else
      {:error, :invalid_chunk_length}
    end
  end

  defp validate_checksum(uncompressed, expected_checksum) do
    if Checksum.masked(uncompressed) == expected_checksum do
      :ok
    else
      {:error, :checksum_mismatch}
    end
  end
end
