defmodule SnappyEx do
  @moduledoc """
  Public API for raw Snappy blocks.

  `compress/1` and `decompress/1` work with the standard raw Snappy block
  format: an uncompressed-size varint followed by literal and copy commands.

  `compress_framed/1` and `decompress_framed/1` work with the Snappy framed
  stream format. `compress_framed_stream/1` and `decompress_framed_stream/2`
  provide lazy, bounded-memory framed processing.
  """

  @type decompress_error ::
          :empty_input
          | :malformed_preamble
          | :truncated_literal
          | :truncated_copy
          | :invalid_offset
          | :invalid_length

  @type framed_decompress_error ::
          :missing_stream_identifier
          | :invalid_stream_identifier
          | :truncated_chunk_header
          | :truncated_chunk
          | :invalid_chunk_length
          | :unsupported_chunk
          | :checksum_mismatch
          | {:invalid_compressed_chunk, decompress_error()}

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
  Lazily compresses a binary or enumerable of iodata chunks into a Snappy framed stream.

  The returned stream yields binary frame fragments and begins with the stream
  identifier. Concatenating the fragments produces the same bytes as
  `compress_framed/1` for the same input.
  """
  @spec compress_framed_stream(binary | Enumerable.t()) :: Enumerable.t()
  defdelegate compress_framed_stream(input), to: SnappyEx.Framed, as: :compress_stream

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

  @doc """
  Lazily decompresses a binary or enumerable of iodata chunks containing a Snappy framed stream.

  Each yielded binary is a complete checksum-verified data chunk. Input may be
  split at arbitrary byte boundaries.

  ## Options

    * `:max_output_size` - maximum total number of uncompressed bytes to yield,
      or `:infinity` for no aggregate limit. Defaults to `:infinity`.

  Malformed input and output-limit violations raise `ArgumentError` when the
  returned stream reaches the offending chunk. Unread input is not validated.
  """
  @spec decompress_framed_stream(binary | Enumerable.t(), keyword) :: Enumerable.t()
  def decompress_framed_stream(input, opts \\ []), do: SnappyEx.Framed.decompress_stream(input, opts)
end
