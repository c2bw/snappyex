defmodule SnappyEx.Raw do
  @moduledoc false

  @type decompress_error :: SnappyEx.Raw.Decoder.decompress_error()

  @spec compress(binary) :: binary
  defdelegate compress(input), to: SnappyEx.Raw.Encoder

  @spec decompress(binary) :: {:ok, binary} | {:error, decompress_error}
  defdelegate decompress(compressed), to: SnappyEx.Raw.Decoder

  @spec decompress!(binary) :: binary
  defdelegate decompress!(compressed), to: SnappyEx.Raw.Decoder
end
