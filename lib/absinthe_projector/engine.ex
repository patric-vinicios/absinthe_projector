defmodule AbsintheProjector.Engine do
  @moduledoc """
  Turns a projected GraphQL selection set into an exact `Repo.preload/2` tree.

  Given the list of `Absinthe.Blueprint.Document.Field` nodes returned by
  `Absinthe.Resolution.project/1` and the root Ecto schema of the field, the
  engine keeps only the fields that name a real association of the current
  schema — asking `AbsintheProjector.Introspection` (F01), never a whitelist —
  recurses into each match using the association's related schema, and merges
  duplicate or aliased requests of the same association by unioning their child
  selections.

  Association matching keys on `schema_node.identifier` (the schema field atom),
  so GraphQL aliases and repeated fields collapse to a single entry. Scalar
  fields, `__typename`, introspection nodes (`schema_node == nil`) and any
  identifier that is not an association are skipped silently. An association
  whose sub-selection contains no further associations is emitted as a bare atom
  (a leaf); otherwise it becomes a `{association, children}` keyword entry.

  The function is pure — no process state, no database access — and looks up a
  schema's associations once per recursion level.

  ## Examples

  Flat selection (scalars dropped, association-less children collapse to a leaf):

      # contact { name age bank { name } }
      project(fields, Contact) #=> [:bank]

  Nested selection:

      # contact { bank { name } installments { payments { account { number } } } }
      project(fields, Contact) #=> [:bank, installments: [payments: [:account]]]

  Aliased duplicates merge into one entry with the union of their children:

      # inst: installments { payments }  dup: installments { }
      project(fields, Contact) #=> [installments: [:payments]]

  A selection with no associations yields an empty, no-op tree:

      # contact { name age }
      project(fields, Contact) #=> []
  """

  alias AbsintheProjector.Introspection
  alias AbsintheProjector.Introspection.Association

  @doc """
  Projects `fields` against `schema`, returning the nested `Repo.preload/2` tree.

  `fields` is a list of `Absinthe.Blueprint.Document.Field` nodes; `schema` is
  the root Ecto schema module. Returns `[]` when the selection contains no
  associations. Raises `ArgumentError` (via `Introspection`) when `schema` is not
  an Ecto schema module.
  """
  @spec project([Absinthe.Blueprint.Document.Field.t()], module()) :: keyword() | [atom()]
  def project(fields, schema) do
    associations = Introspection.associations(schema)

    fields
    |> matched_groups(associations)
    |> Enum.map(fn {identifier, related, children} ->
      case project(children, related) do
        [] -> identifier
        subtree -> {identifier, subtree}
      end
    end)
  end

  # Selects the fields that match an association of the current schema and groups
  # them by identifier — preserving order of first appearance and concatenating
  # the child selections of every occurrence (aliases / duplicates) so recursion
  # sees their union. Returns `[{identifier, related_schema, child_fields}]`.
  defp matched_groups(fields, associations) do
    {reverse_order, grouped} =
      Enum.reduce(fields, {[], %{}}, fn field, {order, grouped} ->
        case associations[identifier(field)] do
          %Association{name: name, related: related} ->
            case grouped do
              %{^name => {_related, children}} ->
                {order, %{grouped | name => {related, children ++ field.selections}}}

              _ ->
                {[name | order], Map.put(grouped, name, {related, field.selections})}
            end

          _ ->
            {order, grouped}
        end
      end)

    reverse_order
    |> Enum.reverse()
    |> Enum.map(fn name ->
      {related, children} = grouped[name]
      {name, related, children}
    end)
  end

  # The schema-field identifier of a projected field, or `nil` when the field has
  # no `schema_node` (introspection nodes). `nil` never matches an association.
  defp identifier(%{schema_node: %{identifier: identifier}}), do: identifier
  defp identifier(_field), do: nil
end
