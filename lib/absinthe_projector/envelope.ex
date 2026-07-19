defmodule AbsintheProjector.Envelope do
  @moduledoc """
  Walks a projected GraphQL selection down a pagination-envelope key path,
  returning the innermost selection that `AbsintheProjector.Engine` (F02) should
  project against the declared `:schema`.

  A Flop-style list query wraps the real entities inside a `data` field
  (`data { … } meta { … }`); custom wrappers may nest deeper
  (`page { entries { … } }`). The `envelope` option on the middleware names that
  wrapper as a key path — a single atom (`:data`) or a list of atoms
  (`[:page, :entries]`) — and this module descends it before projection so only
  the entity selection reaches the engine.

  The descent is deliberately schema-agnostic: at each level it matches the key
  against `schema_node.identifier` (the same structural matching the engine uses),
  never against an Ecto association, so wrapper types (`data`/`meta`,
  `page`/`entries`) need no schema. The sub-selections of **every** field whose
  identifier matches the key are unioned (order of appearance), so aliased or
  duplicated envelope wrappers collapse the same way the engine dedups
  associations.

  An empty path is the no-envelope identity — the selection is returned unchanged,
  so a field without the `envelope` option projects from its root exactly as under
  F03. When a key matches no field at some level, the descent returns `[]`, so a
  meta-only list query (only `meta { total }` requested) yields an empty preload
  tree and downstream `Repo.preload/2` stays a safe no-op.

  The function is pure — no schema lookup, no database access, no process state.

  ## Examples

  Single-level Flop envelope (only `data`'s selection survives):

      # data { bank { name } } meta { total }
      descend(fields, [:data]) #=> [ %Field{schema_node: %{identifier: :bank}, …} ]

  Multi-level envelope descends every level in order:

      # page { entries { bank } }
      descend(fields, [:page, :entries]) #=> [ %Field{… :bank …} ]

  Missing envelope field yields an empty selection:

      # meta { total }   (no `data`)
      descend(fields, [:data]) #=> []

  Empty path is the no-envelope identity:

      descend(fields, []) #=> fields
  """

  @doc """
  Descends `fields` down the normalized key `path`, returning the innermost
  selection.

  With an empty `path`, returns `fields` unchanged (the no-envelope identity).
  Otherwise, for each key in order, keeps the unioned `.selections` of every field
  whose `schema_node.identifier` matches the key; returns `[]` as soon as a key
  matches no field.
  """
  @spec descend([struct()], [atom()]) :: [struct()]
  def descend(fields, []), do: fields

  def descend(fields, path) when is_list(path) do
    Enum.reduce_while(path, fields, fn key, selection ->
      case matching_selections(selection, key) do
        [] -> {:halt, []}
        inner -> {:cont, inner}
      end
    end)
  end

  # Unions the child selections of every field at this level whose identifier
  # matches `key`, preserving order of appearance. A single match is the trivial
  # case; no match yields `[]`, which halts the descent.
  defp matching_selections(fields, key) do
    Enum.flat_map(fields, fn field ->
      if identifier(field) == key, do: field.selections, else: []
    end)
  end

  # The schema-field identifier of a projected field, or `nil` when the field has
  # no `schema_node` (introspection nodes). `nil` never matches an envelope key.
  defp identifier(%{schema_node: %{identifier: identifier}}), do: identifier
  defp identifier(_field), do: nil
end
