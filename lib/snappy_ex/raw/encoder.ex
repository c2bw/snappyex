defmodule SnappyEx.Raw.Encoder do
  @moduledoc false

  import Bitwise

  @compile {:inline,
            [
              copy_chunk_length: 2,
              encode_copy: 2,
              match_key: 2,
              match_length: 4,
              remember_match_tail: 4
            ]}

  @min_match 4
  @max_offset 65_535
  @skip_growth 64

  @spec compress(binary) :: binary
  def compress(input) when is_binary(input) do
    [encode_preamble(byte_size(input)), encode_commands(input)]
    |> IO.iodata_to_binary()
  end

  defp encode_preamble(size) when size >= 0, do: encode_unsigned_varint(size, [])

  defp encode_unsigned_varint(size, acc) when size < 0x80, do: Enum.reverse([size | acc])

  defp encode_unsigned_varint(size, acc) do
    encode_unsigned_varint(size >>> 7, [bor(band(size, 0x7F), 0x80) | acc])
  end

  defp encode_commands(input) when byte_size(input) < @min_match, do: encode_literal(input)

  defp encode_commands(input) do
    table_ref = make_ref()

    try do
      compress_from(input, byte_size(input), 0, 0, table_ref, [], 32)
    after
      clear_match_table(table_ref)
    end
  end

  defp compress_from(input, size, position, anchor, table_ref, acc, skip)
       when position + @min_match <= size do
    candidate = remember_position(table_ref, input, position)

    case candidate do
      candidate when is_integer(candidate) and candidate < position and candidate >= position - @max_offset ->
        emit_match(input, size, position, anchor, table_ref, acc, candidate)

      _candidate ->
        compress_from(input, size, position + (skip >>> 5), anchor, table_ref, acc, skip + @skip_growth)
    end
  end

  defp compress_from(input, size, _position, anchor, _table_ref, acc, _skip) do
    tail = binary_part(input, anchor, size - anchor)

    if tail == <<>> do
      Enum.reverse(acc)
    else
      Enum.reverse([encode_literal(tail) | acc])
    end
  end

  defp emit_match(input, size, position, anchor, table_ref, acc, candidate) do
    match_length = match_length(input, candidate, position, size)
    match_end = position + match_length
    copy = emit_copy(position - candidate, match_length)
    acc = prepend_copy_and_literal(input, anchor, position, copy, acc)

    if match_length >= 16 do
      remember_match_tail(table_ref, input, size, match_end)
    end

    compress_from(input, size, match_end, match_end, table_ref, acc, 32)
  end

  defp prepend_copy_and_literal(_input, anchor, position, copy, acc) when position == anchor do
    [copy | acc]
  end

  defp prepend_copy_and_literal(input, anchor, position, copy, acc) do
    literal = binary_part(input, anchor, position - anchor)
    [copy, encode_literal(literal) | acc]
  end

  defp match_key(input, position) do
    <<_::binary-size(^position), key::little-32, _::binary>> = input
    key
  end

  defp remember_position(table_ref, input, position) do
    :erlang.put({table_ref, match_key(input, position)}, position)
  end

  defp match_length(input, candidate, position, size) do
    candidate_at = candidate + @min_match
    position_at = position + @min_match
    remaining = size - position_at

    candidate_tail = binary_part(input, candidate_at, remaining)
    position_tail = binary_part(input, position_at, remaining)

    @min_match + :binary.longest_common_prefix([candidate_tail, position_tail])
  end

  defp remember_match_tail(table_ref, input, size, match_end) when match_end - 1 + @min_match <= size do
    :erlang.put({table_ref, match_key(input, match_end - 1)}, match_end - 1)
    :ok
  end

  defp remember_match_tail(_table_ref, _input, _size, _match_end), do: :ok

  defp clear_match_table(table_ref) do
    Enum.each(:erlang.get_keys(), fn
      {^table_ref, _key} = key -> :erlang.erase(key)
      _key -> :ok
    end)
  end

  defp encode_literal(<<>>), do: []

  defp encode_literal(data) do
    length_minus_one = byte_size(data) - 1

    cond do
      length_minus_one < 60 -> [<<length_minus_one <<< 2::8>>, data]
      length_minus_one <= 0xFF -> [<<60 <<< 2::8>>, <<length_minus_one>>, data]
      length_minus_one <= 0xFFFF -> [<<61 <<< 2::8>>, <<length_minus_one::little-16>>, data]
      length_minus_one <= 0xFFFFFF -> [<<62 <<< 2::8>>, <<length_minus_one::little-24>>, data]
      true -> [<<63 <<< 2::8>>, <<length_minus_one::little-32>>, data]
    end
  end

  defp emit_copy(offset, length) when length <= 64 do
    encode_copy(offset, length)
  end

  defp emit_copy(offset, length) do
    chunk_length = copy_chunk_length(offset, length)
    [encode_copy(offset, chunk_length) | emit_copy(offset, length - chunk_length)]
  end

  defp copy_chunk_length(offset, length) when offset < 2048 do
    case rem(length, 64) do
      1 -> 61
      2 -> 62
      3 -> 63
      _remainder -> 64
    end
  end

  defp copy_chunk_length(_offset, _length) do
    64
  end

  defp encode_copy(offset, length) when length >= 4 and length <= 11 and offset < 2048 do
    [<<(offset >>> 8) <<< 5 ||| (length - 4) <<< 2 ||| 0b01::8>>, <<offset &&& 0xFF>>]
  end

  defp encode_copy(offset, length) when offset <= 0xFFFF do
    [<<(length - 1) <<< 2 ||| 0b10::8>>, <<offset::little-16>>]
  end

  defp encode_copy(offset, length) do
    [<<(length - 1) <<< 2 ||| 0b11::8>>, <<offset::little-32>>]
  end
end
