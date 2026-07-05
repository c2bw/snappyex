defmodule SnappyEx.Framed do
  @moduledoc false

  @type decompress_error :: SnappyEx.Framed.Decoder.decompress_error()

  @spec compress(binary) :: binary
  defdelegate compress(input), to: SnappyEx.Framed.Encoder

  @spec decompress(binary) :: {:ok, binary} | {:error, decompress_error}
  defdelegate decompress(compressed), to: SnappyEx.Framed.Decoder

  @spec decompress!(binary) :: binary
  defdelegate decompress!(compressed), to: SnappyEx.Framed.Decoder
end
