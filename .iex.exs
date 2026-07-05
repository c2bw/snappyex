#input = File.read!("testdata/asyoulik.txt")
#input = File.read!("testdata/Icet10.txt")
#input = File.read!("testdata/urls10K.txt")
#input = File.read!("testdata/plarbn12.txt")
input = File.read!("testdata/alice29.txt")

snappy_roundtrip = fn name, input ->
  {compress_us, compressed} = :timer.tc(fn -> SnappyEx.compress(input) end)
  {:ok, decompressed} = SnappyEx.decompress(compressed)
  result = %{
    input_size: byte_size(input),
    compressed_size: byte_size(compressed),
    compress_us: compress_us,
    ok?: input == decompressed
  }

  IO.puts(
    "SnappyEx #{name}: #{result.ok?} uncompressed: #{result.input_size} compressed: #{result.compressed_size} compress: #{result.compress_us} us"
  )

  result
end

_alice = snappy_roundtrip.("alice29", input)
html = File.read!("testdata/html")
_html = snappy_roundtrip.("html", html)
