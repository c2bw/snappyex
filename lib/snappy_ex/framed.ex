defmodule SnappyEx.Framed do
  @moduledoc false

  @type decompress_error :: SnappyEx.Framed.Decoder.decompress_error()

  @spec compress(binary) :: binary
  defdelegate compress(input), to: SnappyEx.Framed.Encoder

  @spec compress_stream(binary | Enumerable.t()) :: Enumerable.t()
  defdelegate compress_stream(input), to: SnappyEx.Framed.Encoder

  @spec decompress(binary, keyword) :: {:ok, binary} | {:error, decompress_error}
  def decompress(compressed, opts \\ []), do: SnappyEx.Framed.Decoder.decompress(compressed, opts)

  @spec decompress!(binary, keyword) :: binary
  def decompress!(compressed, opts \\ []), do: SnappyEx.Framed.Decoder.decompress!(compressed, opts)

  @spec decompress_stream(binary | Enumerable.t(), keyword) :: Enumerable.t()
  def decompress_stream(input, opts \\ []), do: SnappyEx.Framed.Decoder.decompress_stream(input, opts)
end
