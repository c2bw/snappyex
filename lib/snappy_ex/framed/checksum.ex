defmodule SnappyEx.Framed.Checksum do
  @moduledoc false

  import Bitwise

  @mask_delta 0xA282EAD8
  @uint32_mask 0xFFFFFFFF

  @compile {:inline, mask: 1}

  @spec masked(binary) :: non_neg_integer
  def masked(data) when is_binary(data) do
    data
    |> Excrc32c.crc32c()
    |> mask()
  end

  defp mask(crc) do
    (crc >>> 15 ||| crc <<< 17) + @mask_delta &&& @uint32_mask
  end
end
