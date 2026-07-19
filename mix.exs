defmodule AbsintheProjector.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/patricvinicios/absinthe_projector"

  def project do
    [
      app: :absinthe_projector,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "AbsintheProjector",
      source_url: @source_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:absinthe, "~> 1.7"},
      {:ecto, "~> 3.10"},
      {:benchee, "~> 1.3", only: :dev},
      {:ecto_sql, "~> 3.10", only: :test},
      {:ecto_sqlite3, "~> 0.17", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Absinthe middleware that turns each GraphQL query's selection set into an " <>
      "exact Ecto preload tree — no N+1, no overfetch, no dataloader spread, " <>
      "no hand-maintained whitelists."
  end

  defp package do
    [
      files: ~w(lib mix.exs README.md LICENSE logo.png .formatter.exs),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Patric Vinicios"]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "logo.png",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
