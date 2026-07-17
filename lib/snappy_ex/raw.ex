defmodule SnappyEx.Raw do
  @moduledoc false

  @type decompress_error :: SnappyEx.Raw.Decoder.decompress_error()

  @spec compress(binary) :: binary
  defdelegate compress(input), to: SnappyEx.Raw.Encoder

  @spec decompress(binary, keyword) :: {:ok, binary} | {:error, decompress_error}
  def decompress(compressed, opts \\ []), do: SnappyEx.Raw.Decoder.decompress(compressed, opts)

  @spec decompress!(binary, keyword) :: binary
  def decompress!(compressed, opts \\ []), do: SnappyEx.Raw.Decoder.decompress!(compressed, opts)
end
