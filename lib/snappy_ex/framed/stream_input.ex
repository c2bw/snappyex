defmodule SnappyEx.Framed.StreamInput do
  @moduledoc false

  @spec chunks(binary | Enumerable.t(), pos_integer) :: Enumerable.t()
  def chunks(input, max_chunk_size) when is_integer(max_chunk_size) and max_chunk_size > 0 do
    input
    |> enumerable()
    |> Stream.flat_map(&iodata_chunks(&1, max_chunk_size))
  end

  defp enumerable(input) when is_binary(input), do: [input]
  defp enumerable(input), do: input

  defp iodata_chunks(iodata, max_chunk_size) when is_binary(iodata) or is_list(iodata) do
    Stream.unfold([iodata], &next_iodata_chunk(&1, max_chunk_size))
  end

  defp iodata_chunks(invalid, _max_chunk_size), do: invalid_iodata!(invalid)

  defp next_iodata_chunk([], _max_chunk_size), do: nil

  defp next_iodata_chunk([item | rest], max_chunk_size) do
    case item do
      empty when empty in [<<>>, []] ->
        next_iodata_chunk(rest, max_chunk_size)

      binary when is_binary(binary) ->
        take_binary(binary, rest, max_chunk_size)

      byte when is_integer(byte) and byte in 0..255 ->
        {<<byte>>, rest}

      [head | tail] when is_list(tail) or is_binary(tail) ->
        pending = if tail in [<<>>, []], do: rest, else: [tail | rest]
        next_iodata_chunk([head | pending], max_chunk_size)

      invalid ->
        invalid_iodata!(invalid)
    end
  end

  defp take_binary(binary, rest, max_chunk_size) when byte_size(binary) <= max_chunk_size do
    {binary, rest}
  end

  defp take_binary(binary, rest, max_chunk_size) do
    <<chunk::binary-size(^max_chunk_size), binary_rest::binary>> = binary
    {chunk, [binary_rest | rest]}
  end

  defp invalid_iodata!(invalid) do
    IO.iodata_to_binary(invalid)
  end
end
