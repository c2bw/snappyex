defmodule SnappyEx.Framed.StreamInput do
  @moduledoc false

  @spec chunks(binary | Enumerable.t(), pos_integer) :: Enumerable.t()
  def chunks(input, max_chunk_size) when is_integer(max_chunk_size) and max_chunk_size > 0 do
    input
    |> enumerable()
    |> Stream.flat_map(fn chunk ->
      chunk
      |> IO.iodata_to_binary()
      |> binary_chunks(max_chunk_size)
    end)
  end

  defp enumerable(input) when is_binary(input), do: [input]
  defp enumerable(input), do: input

  defp binary_chunks(binary, max_chunk_size) do
    Stream.unfold(binary, fn
      <<>> ->
        nil

      binary when byte_size(binary) <= max_chunk_size ->
        {binary, <<>>}

      <<chunk::binary-size(^max_chunk_size), rest::binary>> ->
        {chunk, rest}
    end)
  end
end
