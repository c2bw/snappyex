defmodule SnappyEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @url "https://github.com/c2bw/snappyex"

  def project do
    [
      app: :snappyex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      description: "Pure Elixir implementation of raw Snappy block and framed Snappy stream compression."
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 1.5", only: :dev, runtime: false},
      {:ex_doc, "~> 0.37.3", only: :dev, runtime: false},
      {:snappyrex, "~> 0.1.1", only: :dev},
      {:jhn_stdlib, "~> 5.12", only: :dev},
      {:excrc32c, "~> 0.2"}
    ]
  end

  defp package do
    [
      name: "snappyex",
      source_url: @url,
      files: ["lib", "mix.exs", "mix.lock", "README.md", "LICENSE"],
      licenses: ["MIT"],
      links: %{"GitHub" => @url}
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "SnappyEx",
      canonical: "https://hexdocs.pm/snappyex",
      source_url: @url,
      extras: ["README.md", "LICENSE"]
    ]
  end
end
