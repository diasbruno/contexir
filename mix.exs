defmodule Contexir.MixProject do
  use Mix.Project

  def project do
    [
      name: "Contexir",
      source_url: "https://github.com/diasbruno/contexir",
      version: "0.1.1",
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

  def application do
    []
  end

  defp deps do
    []
  end
end
