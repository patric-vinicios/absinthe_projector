defmodule AbsintheProjector.Introspection do
  @moduledoc """
  Discovers the associations of an Ecto schema through Ecto's compile-time
  reflection API — never a hand-maintained whitelist.

  This module is the single source of truth the projection engine (F02) asks,
  at every recursion level: *"is this field name a real association of the
  current schema, and if so, what schema do I recurse into?"* It answers with
  zero configuration and zero drift — adding an association to a consumer schema
  makes it projectable automatically.

  It is pure and database-free: only `__schema__/1` and `__schema__/2`
  reflection is used, so it can be exhaustively unit-tested without a repo and
  sits comfortably under the middleware's per-operation overhead budget.

  ## Example

      iex> AbsintheProjector.Introspection.associations(MyApp.Contact)
      %{
        bank: %AbsintheProjector.Introspection.Association{
          name: :bank, kind: :belongs_to, related: MyApp.Bank
        },
        # ...
      }

  `embeds_one`/`embeds_many` fields and scalar columns never appear — Ecto's
  `__schema__(:associations)` already omits them.
  """

  alias AbsintheProjector.Introspection.Association

  @doc """
  Returns a map of `%Association{}` metadata keyed by association name for the
  given Ecto schema module.

  Returns an empty map (`%{}`) when the schema declares no associations.

  Raises `ArgumentError` when `schema` is not an Ecto schema module.
  """
  @spec associations(module()) :: %{atom() => Association.t()}
  def associations(schema) do
    ensure_ecto_schema!(schema)

    for name <- schema.__schema__(:associations), into: %{} do
      {name, build(schema, name)}
    end
  end

  @doc """
  Returns the `%Association{}` entry for `name` on `schema`, or `nil` when
  `name` is not an association (e.g. a scalar field or an unknown identifier).

  Raises `ArgumentError` when `schema` is not an Ecto schema module.
  """
  @spec association(module(), atom()) :: Association.t() | nil
  def association(schema, name) do
    ensure_ecto_schema!(schema)

    case schema.__schema__(:association, name) do
      nil -> nil
      _reflection -> build(schema, name)
    end
  end

  # --- internal ---------------------------------------------------------------

  defp build(schema, name) do
    reflection = schema.__schema__(:association, name)
    {kind, related} = classify(reflection)
    %Association{name: name, kind: kind, related: related}
  end

  # Classifies an Ecto association reflection struct into `{kind, related}`.
  defp classify(%Ecto.Association.BelongsTo{related: related}),
    do: {:belongs_to, related}

  defp classify(%Ecto.Association.Has{cardinality: :one, related: related}),
    do: {:has_one, related}

  defp classify(%Ecto.Association.Has{cardinality: :many, related: related}),
    do: {:has_many, related}

  defp classify(%Ecto.Association.ManyToMany{related: related}),
    do: {:many_to_many, related}

  defp classify(%Ecto.Association.HasThrough{owner: owner, through: through}),
    do: {:through, resolve_through(owner, through)}

  # Walks a `:through` chain from `owner`, advancing to the related schema at
  # each step, and returns the concrete schema at the end of the chain.
  # Intermediate steps that are themselves `:through` recurse.
  defp resolve_through(owner, [step | rest]) do
    related =
      case owner.__schema__(:association, step) do
        %Ecto.Association.HasThrough{owner: step_owner, through: step_through} ->
          resolve_through(step_owner, step_through)

        reflection ->
          elem(classify(reflection), 1)
      end

    case rest do
      [] -> related
      _ -> resolve_through(related, rest)
    end
  end

  defp ensure_ecto_schema!(module) do
    if ecto_schema?(module) do
      :ok
    else
      raise ArgumentError,
            "expected an Ecto schema module, got: #{inspect(module)}"
    end
  end

  defp ecto_schema?(module) do
    is_atom(module) and
      Code.ensure_loaded?(module) and
      function_exported?(module, :__schema__, 1)
  end
end
