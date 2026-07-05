defmodule SnappyEx do
  @moduledoc """
  Public API for raw Snappy blocks.

  `compress/1` and `decompress/1` work with the standard raw Snappy block
  format: an uncompressed-size varint followed by literal and copy commands.

  `compress_framed/1` and `decompress_framed/1` work with the Snappy framed
  stream format.
  """

  @type decompress_error :: SnappyEx.Raw.decompress_error()
  @type framed_decompress_error :: SnappyEx.Framed.decompress_error()

  @doc """
  Compresses a binary into the raw Snappy block format.
  """
  @spec compress(binary) :: binary
  defdelegate compress(input), to: SnappyEx.Raw

  @doc """
  Decompresses a raw Snappy block.

  Returns `{:ok, binary}` on success or `{:error, reason}` for malformed input.
  """
  @spec decompress(binary) :: {:ok, binary} | {:error, decompress_error}
  defdelegate decompress(compressed), to: SnappyEx.Raw

  @doc """
  Decompresses a raw Snappy block, raising `ArgumentError` for malformed input.
  """
  @spec decompress!(binary) :: binary
  defdelegate decompress!(compressed), to: SnappyEx.Raw

  @doc """
  Compresses a binary into the Snappy framed stream format.
  """
  @spec compress_framed(binary) :: binary
  defdelegate compress_framed(input), to: SnappyEx.Framed, as: :compress

  @doc """
  Decompresses a Snappy framed stream.

  Returns `{:ok, binary}` on success or `{:error, reason}` for malformed input.
  """
  @spec decompress_framed(binary) :: {:ok, binary} | {:error, framed_decompress_error}
  defdelegate decompress_framed(compressed), to: SnappyEx.Framed, as: :decompress

  @doc """
  Decompresses a Snappy framed stream, raising `ArgumentError` for malformed input.
  """
  @spec decompress_framed!(binary) :: binary
  defdelegate decompress_framed!(compressed), to: SnappyEx.Framed, as: :decompress!
end
