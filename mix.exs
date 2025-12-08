defmodule Contexir.MixProject do
  use Mix.Project

  def project do
    [
      name: "Contexir",
      source_url: "https://github.com/diasbruno/contexir",
      version: "0.1.3",
      elixir: "~> 1.18",
      app: :contexir,
      description: description(),
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps()
    ]
  end

  defp description() do
    "Context-oriented programming in Elixir"
  end

  defp package() do
    [
      name: "contexir",
      files: ~w(lib .formatter.exs mix.exs readme* license*),
      licenses: ["Unlicense"],
      links: %{"GitHub" => "https://github.com/diasbruno/contexir"}
    ]
  end

  def application do
    []
  end

  defp deps do
    []
  end
end
