Logger.configure(level: :error)

testdata = [
  "testdata/alice29.txt",
  "testdata/html",
  "testdata/urls.10K"
]

warmup = System.get_env("BENCH_WARMUP", "0") |> String.to_integer()
time = System.get_env("BENCH_TIME", "1") |> String.to_integer()
memory_time = System.get_env("BENCH_MEMORY_TIME", "0") |> String.to_integer()

inputs =
  %{
    "lite corpus" =>
      testdata
      |> Enum.map(&File.read!/1)
      |> IO.iodata_to_binary()
  }

IO.puts("Input sizes")

Enum.each(testdata, fn path ->
  input = File.read!(path)
  IO.puts("  #{Path.basename(path)}: #{byte_size(input)} bytes")
end)

IO.puts("  combined: #{byte_size(inputs["lite corpus"])} bytes")

IO.puts("")
IO.puts("Compressed sizes")

compressed_inputs =
  inputs
  |> Enum.map(fn {name, input} ->
    IO.puts("  preparing #{name}...")

    snappyex_raw = SnappyEx.compress(input)
    snappyex_frame = SnappyEx.compress_framed(input)
    {:ok, snappyrex_raw} = Snappyrex.compress(input)
    {:ok, snappyrex_frame} = Snappyrex.compress(input, format: :frame)
    jhn_snappy_raw = :jhn_snappy.compress(input, [:binary])
    jhn_snappy_frame = :jhn_snappy.compress(input, [:binary, :frame])

    IO.puts(
      "  #{name}: SnappyEx raw=#{byte_size(snappyex_raw)} bytes, " <>
        "SnappyEx frame=#{byte_size(snappyex_frame)} bytes, " <>
        "snappyrex raw=#{byte_size(snappyrex_raw)} bytes, " <>
        "snappyrex frame=#{byte_size(snappyrex_frame)} bytes, " <>
        "jhn_snappy raw=#{byte_size(jhn_snappy_raw)} bytes, " <>
        "jhn_snappy frame=#{byte_size(jhn_snappy_frame)} bytes"
    )

    {name,
     %{
       original: input,
       snappyex_raw: snappyex_raw,
       snappyex_frame: snappyex_frame,
       snappyrex_raw: snappyrex_raw,
       snappyrex_frame: snappyrex_frame,
       jhn_snappy_raw: jhn_snappy_raw,
       jhn_snappy_frame: jhn_snappy_frame
     }}
  end)
  |> Map.new()

IO.puts("")
IO.puts("Compression")

Benchee.run(
  %{
    "SnappyEx.compress/1 raw" => fn input ->
      SnappyEx.compress(input)
    end,
    "SnappyEx.compress_framed/1 frame" => fn input ->
      SnappyEx.compress_framed(input)
    end,
    "Snappyrex.compress/1 raw" => fn input ->
      {:ok, compressed} = Snappyrex.compress(input)
      compressed
    end,
    "Snappyrex.compress/2 frame" => fn input ->
      {:ok, compressed} = Snappyrex.compress(input, format: :frame)
      compressed
    end,
    "jhn_snappy.compress/2 raw" => fn input ->
      :jhn_snappy.compress(input, [:binary])
    end,
    "jhn_snappy.compress/2 frame" => fn input ->
      :jhn_snappy.compress(input, [:binary, :frame])
    end
  },
  inputs: inputs,
  warmup: warmup,
  time: time,
  memory_time: memory_time,
  print: [fast_warning: false]
)

IO.puts("")
IO.puts("Decompression")

Benchee.run(
  %{
    "SnappyEx.decompress/1 raw" => fn %{snappyex_raw: compressed} ->
      {:ok, original} = SnappyEx.decompress(compressed)
      original
    end,
    "SnappyEx.decompress_framed/1 frame" => fn %{snappyex_frame: compressed} ->
      {:ok, original} = SnappyEx.decompress_framed(compressed)
      original
    end,
    "Snappyrex.decompress/1 raw" => fn %{snappyrex_raw: compressed} ->
      {:ok, original} = Snappyrex.decompress(compressed)
      original
    end,
    "Snappyrex.decompress/2 frame" => fn %{snappyrex_frame: compressed} ->
      {:ok, original} = Snappyrex.decompress(compressed, format: :frame)
      original
    end,
    "jhn_snappy.uncompress/2 raw" => fn %{jhn_snappy_raw: compressed} ->
      :jhn_snappy.uncompress(compressed, [:binary])
    end,
    "jhn_snappy.uncompress/2 frame" => fn %{jhn_snappy_frame: compressed} ->
      :jhn_snappy.uncompress(compressed, [:binary, :frame])
    end
  },
  inputs: compressed_inputs,
  warmup: warmup,
  time: time,
  memory_time: memory_time,
  print: [fast_warning: false]
)
