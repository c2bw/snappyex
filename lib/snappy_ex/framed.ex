defmodule SnappyEx.Framed do
  @moduledoc false

  @type decompress_error :: SnappyEx.Framed.Decoder.decompress_error()

  @spec compress(binary) :: binary
  defdelegate compress(input), to: SnappyEx.Framed.Encoder

  @spec compress_stream(binary | Enumerable.t()) :: Enumerable.t()
  defdelegate compress_stream(input), to: SnappyEx.Framed.Encoder

  @spec decompress(binary) :: {:ok, binary} | {:error, decompress_error}
  defdelegate decompress(compressed), to: SnappyEx.Framed.Decoder

  @spec decompress!(binary) :: binary
  defdelegate decompress!(compressed), to: SnappyEx.Framed.Decoder

  @spec decompress_stream(binary | Enumerable.t(), keyword) :: Enumerable.t()
  def decompress_stream(input, opts \\ []), do: SnappyEx.Framed.Decoder.decompress_stream(input, opts)
end
