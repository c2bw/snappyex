defmodule SnappyEx.Framed.Decoder do
  @moduledoc false

  alias SnappyEx.Framed.Checksum
  alias SnappyEx.Framed.StreamInput
  alias SnappyEx.Raw.Decoder, as: RawDecoder

  @max_uncompressed_chunk_size 65_536
  @checksum_size 4
  # A valid raw block can use a five-byte preamble and encode each output byte
  # as a one-byte literal with a four-byte extended length.
  @max_compressed_chunk_size 5 + @max_uncompressed_chunk_size * 6 + @checksum_size
  @stream_identifier "sNaPpY"
  @stream_identifier_size byte_size(@stream_identifier)
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
          | :output_limit_exceeded
          | {:invalid_compressed_chunk, SnappyEx.Raw.decompress_error()}

  @spec decompress(binary, keyword) :: {:ok, binary} | {:error, decompress_error}
  def decompress(compressed, opts \\ []) when is_binary(compressed) do
    max_output_size = max_output_size(opts)

    with {:ok, rest} <- decode_initial_stream_identifier(compressed),
         {:ok, output} <- decode_chunks(rest, [], 0, max_output_size) do
      {:ok, output}
    end
  end

  @spec decompress!(binary, keyword) :: binary
  def decompress!(compressed, opts \\ []) when is_binary(compressed) do
    case decompress(compressed, opts) do
      {:ok, output} -> output
      {:error, reason} -> raise ArgumentError, "invalid snappy framed stream: #{inspect(reason)}"
    end
  end

  @spec decompress_stream(binary | Enumerable.t(), keyword) :: Enumerable.t()
  def decompress_stream(input, opts \\ []) do
    max_output_size = max_output_size(opts)

    parser = %{
      phase: :header,
      pending: <<>>,
      seen_identifier: false,
      output_size: 0,
      max_output_size: max_output_size
    }

    source = input |> StreamInput.chunks(@max_uncompressed_chunk_size) |> then(&{:enumerable, &1})

    Stream.resource(
      fn -> %{source: source, input: <<>>, parser: parser} end,
      &next_stream_chunk/1,
      &close_stream_source/1
    )
  end

  defp max_output_size(opts) do
    opts = Keyword.validate!(opts, max_output_size: :infinity)

    case Keyword.fetch!(opts, :max_output_size) do
      :infinity -> :infinity
      size when is_integer(size) and size >= 0 -> size
      value -> raise ArgumentError, "expected :max_output_size to be a non-negative integer or :infinity, got: #{inspect(value)}"
    end
  end

  defp raise_stream_error(reason) do
    raise ArgumentError, "invalid snappy framed stream: #{inspect(reason)}"
  end

  defp next_stream_chunk(%{input: input, parser: parser} = stream) do
    case consume_stream_data(input, parser) do
      {:emit, decoded, rest, parser} ->
        {[decoded], %{stream | input: rest, parser: parser}}

      {:need_input, parser} ->
        case pull_stream_source(stream.source) do
          {:ok, chunk, source} ->
            next_stream_chunk(%{stream | source: source, input: chunk, parser: parser})

          :done ->
            case finish_stream(parser) do
              :ok -> {:halt, %{stream | source: :done, input: <<>>, parser: parser}}
              {:error, reason} -> raise_stream_error(reason)
            end
        end

      {:error, reason} ->
        halt_stream_source(stream.source)
        raise_stream_error(reason)
    end
  end

  defp pull_stream_source({:enumerable, source}) do
    source
    |> Enumerable.reduce({:cont, nil}, fn chunk, _acc -> {:suspend, chunk} end)
    |> decode_stream_source_result()
  end

  defp pull_stream_source({:continuation, continuation}) do
    continuation.({:cont, nil})
    |> decode_stream_source_result()
  end

  defp decode_stream_source_result({:suspended, chunk, continuation}) do
    {:ok, chunk, {:continuation, continuation}}
  end

  defp decode_stream_source_result({:done, _acc}), do: :done
  defp decode_stream_source_result({:halted, _acc}), do: :done

  defp close_stream_source(%{source: source}), do: halt_stream_source(source)

  defp halt_stream_source({:continuation, continuation}) do
    _ = continuation.({:halt, nil})
    :ok
  end

  defp halt_stream_source(_source), do: :ok

  defp consume_stream_data(data, %{phase: {:payload, type, 0, parts}} = state) do
    payload = parts |> Enum.reverse() |> IO.iodata_to_binary()
    state = %{state | phase: :header, pending: <<>>}

    case complete_stream_payload(type, payload, state) do
      {:continue, state} -> consume_stream_data(data, state)
      {:emit, decoded, state} -> {:emit, decoded, data, state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp consume_stream_data(data, %{phase: {:skip, 0}} = state) do
    consume_stream_data(data, %{state | phase: :header, pending: <<>>})
  end

  defp consume_stream_data(<<>>, state), do: {:need_input, state}

  defp consume_stream_data(data, %{phase: :header, pending: pending} = state) do
    needed = 4 - byte_size(pending)

    if byte_size(data) < needed do
      {:need_input, %{state | pending: <<pending::binary, data::binary>>}}
    else
      <<header_tail::binary-size(^needed), rest::binary>> = data
      <<type, length::little-24>> = <<pending::binary, header_tail::binary>>
      state = %{state | pending: <<>>}

      case begin_stream_chunk(state, type, length) do
        {:ok, state} -> consume_stream_data(rest, state)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp consume_stream_data(data, %{phase: {:payload, type, remaining, parts}} = state) do
    take = min(byte_size(data), remaining)
    <<part::binary-size(^take), rest::binary>> = data

    state = %{
      state
      | phase: {:payload, type, remaining - take, [part | parts]}
    }

    consume_stream_data(rest, state)
  end

  defp consume_stream_data(data, %{phase: {:skip, remaining}} = state) do
    take = min(byte_size(data), remaining)
    <<_skipped::binary-size(^take), rest::binary>> = data
    consume_stream_data(rest, %{state | phase: {:skip, remaining - take}})
  end

  defp begin_stream_chunk(%{seen_identifier: false}, type, _length) when type != @stream_identifier_chunk do
    {:error, :missing_stream_identifier}
  end

  defp begin_stream_chunk(state, @stream_identifier_chunk, length) when length == @stream_identifier_size do
    {:ok, %{state | phase: {:payload, @stream_identifier_chunk, length, []}}}
  end

  defp begin_stream_chunk(_state, @stream_identifier_chunk, _length), do: {:error, :invalid_stream_identifier}

  defp begin_stream_chunk(state, @compressed_data, length)
       when length >= @checksum_size and length <= @max_compressed_chunk_size do
    {:ok, %{state | phase: {:payload, @compressed_data, length, []}}}
  end

  defp begin_stream_chunk(_state, @compressed_data, _length), do: {:error, :invalid_chunk_length}

  defp begin_stream_chunk(state, @uncompressed_data, length)
       when length >= @checksum_size and length <= @max_uncompressed_chunk_size + @checksum_size do
    {:ok, %{state | phase: {:payload, @uncompressed_data, length, []}}}
  end

  defp begin_stream_chunk(_state, @uncompressed_data, _length), do: {:error, :invalid_chunk_length}

  defp begin_stream_chunk(state, type, length) when type >= 0x80 and type <= 0xFE do
    {:ok, %{state | phase: {:skip, length}}}
  end

  defp begin_stream_chunk(_state, _type, _length), do: {:error, :unsupported_chunk}

  defp complete_stream_payload(type, payload, state) do
    case decode_chunk(type, payload) do
      {:ok, []} ->
        state = if type == @stream_identifier_chunk, do: %{state | seen_identifier: true}, else: state
        {:continue, state}

      {:ok, decoded} ->
        prepare_stream_output(state, decoded)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_stream_output(state, <<>>), do: {:continue, state}

  defp prepare_stream_output(state, decoded) do
    output_size = state.output_size + byte_size(decoded)

    if state.max_output_size == :infinity or output_size <= state.max_output_size do
      {:emit, decoded, %{state | output_size: output_size}}
    else
      {:error, :output_limit_exceeded}
    end
  end

  defp finish_stream(%{seen_identifier: false, phase: :header, pending: <<>>}), do: :ok
  defp finish_stream(%{seen_identifier: false, phase: :header}), do: {:error, :missing_stream_identifier}
  defp finish_stream(%{phase: :header, pending: <<>>}), do: :ok
  defp finish_stream(%{phase: :header}), do: {:error, :truncated_chunk_header}
  defp finish_stream(_state), do: {:error, :truncated_chunk}

  defp decode_initial_stream_identifier(<<>>), do: {:ok, <<>>}

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

  defp decode_chunks(<<>>, acc, _output_size, _max_output_size) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp decode_chunks(compressed, _acc, _output_size, _max_output_size) when byte_size(compressed) < 4 do
    {:error, :truncated_chunk_header}
  end

  defp decode_chunks(<<type, length::little-24, rest::binary>>, acc, output_size, max_output_size) do
    if byte_size(rest) < length do
      {:error, :truncated_chunk}
    else
      <<payload::binary-size(^length), chunk_rest::binary>> = rest

      with {:ok, decoded} <- decode_chunk(type, payload),
           {:ok, output_size} <- add_output_size(output_size, decoded, max_output_size) do
        decode_chunks(chunk_rest, [decoded | acc], output_size, max_output_size)
      end
    end
  end

  defp add_output_size(output_size, decoded, max_output_size) do
    output_size = output_size + decoded_size(decoded)

    if max_output_size == :infinity or output_size <= max_output_size do
      {:ok, output_size}
    else
      {:error, :output_limit_exceeded}
    end
  end

  defp decoded_size([]), do: 0
  defp decoded_size(decoded), do: byte_size(decoded)

  defp decode_chunk(@compressed_data, payload) when byte_size(payload) > @max_compressed_chunk_size do
    {:error, :invalid_chunk_length}
  end

  defp decode_chunk(@compressed_data, <<expected_checksum::little-32, compressed::binary>>) do
    with {:ok, uncompressed} <- decode_raw_chunk(compressed),
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
    case RawDecoder.decompress_limited(compressed, @max_uncompressed_chunk_size) do
      {:ok, uncompressed} -> {:ok, uncompressed}
      {:error, :output_limit_exceeded} -> {:error, :invalid_chunk_length}
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
