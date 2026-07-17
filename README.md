# SnappyEx

**`SnappyEx`** is a pure Elixir implementation for raw Snappy block and framed Snappy
stream compression/decompression.


As shown in the benchmark results below, SnappyEx is slower than the *Rust-based NIF* [`Snappyrex`](https://github.com/c2bw/snappyrex).
*Only use SnappyEx if you need a pure Elixir implementation or performance is not crucial to your application.* 


## Usage

Compress and decompress Snappy blocks:

```elixir
input = "banana bandana"
compressed = SnappyEx.compress(input)

SnappyEx.decompress(compressed)
#=> {:ok, "banana bandana"}

SnappyEx.decompress!(compressed)
#=> "banana bandana"
```

Compress and decompress Snappy framed streams:

```elixir
input = "banana bandana"
compressed = SnappyEx.compress_framed(input)

SnappyEx.decompress_framed(compressed)
#=> {:ok, "banana bandana"}
```

When decompressing untrusted input, bound the returned data with
`max_output_size`, expressed in uncompressed bytes. Raw blocks are rejected
from their declared size before decoding, while framed streams enforce the
limit across all chunks:

```elixir
SnappyEx.decompress(SnappyEx.compress(input), max_output_size: 1_000_000)
SnappyEx.decompress_framed(SnappyEx.compress_framed(input), max_output_size: 1_000_000)
```

Process framed streams lazily when the complete input or output should not be kept in
memory:

```elixir
output =
  ["banana ", ["ban", "dana"]]
  |> SnappyEx.compress_framed_stream()
  |> SnappyEx.decompress_framed_stream(max_output_size: 1_000_000)
  |> Enum.to_list()
  |> IO.iodata_to_binary()

output
#=> "banana bandana"
```

Both streaming functions accept arbitrarily split iodata enumerables. They produce
lazy streams, so errors from framed decompression are raised while the result is
enumerated. If a consumer stops early, unread input is not consumed or validated.

## Development

Run the test suite:

```shell
mix test
```

Run the Benchee benchmark against Snappyrex and `jhn_stdlib`:

```shell
mix run bench/bench.exs
```

The default run uses every file in `testdata/`, skips warmup, and skips memory timing
so it returns quickly. Use `BENCH_FILES`, `BENCH_WARMUP`, `BENCH_TIME`, and
`BENCH_MEMORY_TIME` to change the corpus or timing window:

```shell
BENCH_FILES=testdata/alice29.txt BENCH_TIME=3 BENCH_MEMORY_TIME=1 mix run bench/bench.exs
```

### Lite Benchmark Results

`mix run bench/bench_lite.exs`:

```
Input sizes
  alice29.txt: 152089 bytes
  html: 102400 bytes
  urls.10K: 712086 bytes
  combined: 966575 bytes

Compressed sizes
  preparing lite corpus...
  lite corpus: SnappyEx raw=498357 bytes, SnappyEx frame=598217 bytes, snappyrex raw=448735 bytes, snappyrex frame=448907 bytes, jhn_snappy raw=632955 bytes, jhn_snappy frame=652665 bytes

Benchmark suite executing with the following configuration:
warmup: 0 ns
time: 1 s
memory time: 0 ns
reduction time: 0 ns
parallel: 1
inputs: lite corpus
Estimated total run time: 5 s
Excluding outliers: false

##### With input lite corpus #####
Name                                       ips        average  deviation         median         99th %
Snappyrex.compress/1 raw                682.39        1.47 ms     ±9.84%        1.43 ms        1.95 ms
Snappyrex.compress/2 frame              662.11        1.51 ms     ±7.27%        1.54 ms        1.95 ms
SnappyEx.compress_framed/1 frame         63.51       15.75 ms     ±6.02%       15.67 ms       19.46 ms
SnappyEx.compress/1 raw                  16.11       62.08 ms    ±11.57%       61.95 ms       73.83 ms
jhn_snappy.compress/2 frame               1.51      662.17 ms     ±2.88%      662.17 ms      675.64 ms
jhn_snappy.compress/2 raw                 1.05      951.19 ms     ±5.24%      951.19 ms      986.42 ms

Comparison:
Snappyrex.compress/1 raw                682.39
Snappyrex.compress/2 frame              662.11 - 1.03x slower +0.0449 ms
SnappyEx.compress_framed/1 frame         63.51 - 10.74x slower +14.28 ms
SnappyEx.compress/1 raw                  16.11 - 42.36x slower +60.61 ms
jhn_snappy.compress/2 frame               1.51 - 451.86x slower +660.70 ms
jhn_snappy.compress/2 raw                 1.05 - 649.09x slower +949.73 ms

##### With input lite corpus #####
Name                                         ips        average  deviation         median         99th %
Snappyrex.decompress/1 raw               1526.69        0.66 ms    ±13.66%        0.61 ms        0.82 ms
Snappyrex.decompress/2 frame              999.32        1.00 ms    ±14.07%        1.02 ms        1.43 ms
SnappyEx.decompress/1 raw                 167.58        5.97 ms     ±7.09%        5.94 ms        8.39 ms
SnappyEx.decompress_framed/1 frame        129.90        7.70 ms     ±7.72%        7.58 ms       11.55 ms
jhn_snappy.uncompress/2 raw                87.56       11.42 ms     ±8.20%       11.57 ms       14.95 ms
jhn_snappy.uncompress/2 frame              73.25       13.65 ms    ±18.10%       12.65 ms       25.19 ms

Comparison:
Snappyrex.decompress/1 raw               1526.69
Snappyrex.decompress/2 frame              999.32 - 1.53x slower +0.35 ms
SnappyEx.decompress/1 raw                 167.58 - 9.11x slower +5.31 ms
SnappyEx.decompress_framed/1 frame        129.90 - 11.75x slower +7.04 ms
jhn_snappy.uncompress/2 raw                87.56 - 17.44x slower +10.77 ms
jhn_snappy.uncompress/2 frame              73.25 - 20.84x slower +13.00 ms
```
