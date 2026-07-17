defmodule SnappyEx.Raw.Decoder do
  @moduledoc false

  import Bitwise

  @type decompress_error ::
          :empty_input
          | :malformed_preamble
          | :truncated_literal
          | :truncated_copy
          | :invalid_offset
          | :invalid_length

  @spec decompress(binary) :: {:ok, binary} | {:error, decompress_error}
  def decompress(compressed) when is_binary(compressed) do
    with {:ok, expected_size, commands} <- decode_preamble(compressed),
         {:ok, output} <- decode_commands(commands, expected_size, <<>>, 0) do
      {:ok, output}
    end
  end

  @spec decompress!(binary) :: binary
  def decompress!(compressed) when is_binary(compressed) do
    case decompress(compressed) do
      {:ok, output} -> output
      {:error, reason} -> raise ArgumentError, "invalid snappy block: #{reason}"
    end
  end

  defp decode_preamble(<<>>), do: {:error, :empty_input}
  defp decode_preamble(<<size, commands::binary>>) when size < 0x80, do: {:ok, size, commands}

  defp decode_preamble(<<byte1, byte2, commands::binary>>) when byte2 < 0x80 do
    {:ok, band(byte1, 0x7F) ||| byte2 <<< 7, commands}
  end

  defp decode_preamble(binary), do: decode_preamble(binary, 0, 0)

  defp decode_preamble(<<byte, rest::binary>>, size, 28) when byte <= 0x0F do
    {:ok, size ||| byte <<< 28, rest}
  end

  defp decode_preamble(_binary, _size, 28), do: {:error, :malformed_preamble}

  defp decode_preamble(<<byte, rest::binary>>, size, shift) do
    size = size ||| band(byte, 0x7F) <<< shift

    if band(byte, 0x80) == 0 do
      {:ok, size, rest}
    else
      decode_preamble(rest, size, shift + 7)
    end
  end

  defp decode_preamble(<<>>, _size, _shift), do: {:error, :malformed_preamble}

  defp decode_commands(<<>>, expected_size, output, output_size) do
    if output_size == expected_size, do: {:ok, output}, else: {:error, :invalid_length}
  end

  defp decode_commands(<<length_code::6, 0b00::2, rest::binary>>, expected_size, output, output_size)
       when length_code < 60 do
    decode_literal(length_code + 1, rest, expected_size, output, output_size)
  end

  defp decode_commands(<<length_code::6, 0b00::2, rest::binary>>, expected_size, output, output_size) do
    decode_extended_literal(length_code, rest, expected_size, output, output_size)
  end

  defp decode_commands(
         <<offset_high::3, length_code::3, 0b01::2, offset_low, rest::binary>>,
         expected_size,
         output,
         output_size
       ) do
    offset = offset_high <<< 8 ||| offset_low
    length = length_code + 4

    decode_copy(rest, expected_size, output, output_size, offset, length)
  end

  defp decode_commands(<<_offset_high::3, _length_code::3, 0b01::2>>, _expected_size, _output, _output_size) do
    {:error, :truncated_copy}
  end

  defp decode_commands(
         <<length_code::6, 0b10::2, offset::little-16, rest::binary>>,
         expected_size,
         output,
         output_size
       ) do
    decode_copy(rest, expected_size, output, output_size, offset, length_code + 1)
  end

  defp decode_commands(<<_length_code::6, 0b10::2, _rest::binary>>, _expected_size, _output, _output_size) do
    {:error, :truncated_copy}
  end

  defp decode_commands(
         <<length_code::6, 0b11::2, offset::little-32, rest::binary>>,
         expected_size,
         output,
         output_size
       ) do
    decode_copy(rest, expected_size, output, output_size, offset, length_code + 1)
  end

  defp decode_commands(<<_length_code::6, 0b11::2, _rest::binary>>, _expected_size, _output, _output_size) do
    {:error, :truncated_copy}
  end

  defp decode_extended_literal(length_code, rest, expected_size, output, output_size) do
    bytes_to_read = length_code - 59

    if byte_size(rest) < bytes_to_read do
      {:error, :truncated_literal}
    else
      <<length_bytes::binary-size(^bytes_to_read), literal_rest::binary>> = rest
      decode_literal(decode_little_unsigned(length_bytes) + 1, literal_rest, expected_size, output, output_size)
    end
  end

  defp decode_literal(length, rest, expected_size, output, output_size) do
    cond do
      byte_size(rest) < length ->
        {:error, :truncated_literal}

      output_size + length > expected_size ->
        {:error, :invalid_length}

      true ->
        <<literal::binary-size(^length), command_rest::binary>> = rest
        decode_commands(command_rest, expected_size, <<output::binary, literal::binary>>, output_size + length)
    end
  end

  defp decode_copy(rest, expected_size, output, output_size, offset, length) do
    cond do
      offset < 1 or offset > output_size ->
        {:error, :invalid_offset}

      output_size + length > expected_size ->
        {:error, :invalid_length}

      true ->
        output = append_copy(output, output_size, offset, length)
        decode_commands(rest, expected_size, output, output_size + length)
    end
  end

  defp append_copy(output, output_size, offset, length) when offset >= length do
    source_at = output_size - offset
    copy = binary_part(output, source_at, length)

    <<output::binary, copy::binary>>
  end

  defp append_copy(output, output_size, offset, length) do
    source_at = output_size - offset
    seed = binary_part(output, source_at, offset)
    copy = repeat_to_length(seed, length)

    <<output::binary, copy::binary>>
  end

  defp repeat_to_length(seed, length) when byte_size(seed) >= length do
    binary_part(seed, 0, length)
  end

  defp repeat_to_length(seed, length) do
    repeat_to_length(<<seed::binary, seed::binary>>, length)
  end

  defp decode_little_unsigned(<<byte>>), do: byte

  defp decode_little_unsigned(<<byte1, byte2>>) do
    byte1 ||| byte2 <<< 8
  end

  defp decode_little_unsigned(<<byte1, byte2, byte3>>) do
    byte1 ||| byte2 <<< 8 ||| byte3 <<< 16
  end

  defp decode_little_unsigned(<<byte1, byte2, byte3, byte4>>) do
    byte1 ||| byte2 <<< 8 ||| byte3 <<< 16 ||| byte4 <<< 24
  end
end
