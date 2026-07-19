defmodule AbsintheProjector.TestResolutions do
  @moduledoc """
  Builders for `%Absinthe.Resolution{}` structs used by the middleware unit tests.

  `AbsintheProjector.call/2` obtains its selection through
  `Absinthe.Resolution.project/1`, so exercising it directly (without
  `Absinthe.run/2`) means assembling the minimal Absinthe type context that
  `project/1` needs:

    * `definition.schema_node.type` — a `%Absinthe.Type.Object{}` carrying the
      field-return type's `identifier` and a `fields` map. `project/1` looks the
      type up (returning the struct as-is) and the projector reads each top-level
      selection's `schema_node.identifier` out of that `fields` map;
    * `definition.selections` — the projected child fields, built with
      `AbsintheProjector.TestFields` so a resolution reads like the GraphQL
      selection it represents;
    * `path: []`, `fragments: %{}`, `fields_cache: %{}` — enough for `project/1`
      to collect a flat object selection with no fragments.

  The `fields` map is derived automatically from the top-level selections, so any
  identifier the projector needs to resolve is present. `query/2` and
  `mutation/2` differ only in the root field name — the middleware treats them
  identically, which is exactly the parity the tests assert.
  """

  import AbsintheProjector.TestFields, only: [field: 2]

  alias Absinthe.Blueprint.Document.Field, as: DocField
  alias Absinthe.Type

  @doc """
  A query resolution whose projected selection is `selections`.

  Options:

    * `:context` — the resolution context (default `%{}`);
    * `:errors` — the resolution errors list (default `[]`);
    * `:root` — the root field identifier (default `:contact`).
  """
  @spec query([DocField.t()], keyword()) :: Absinthe.Resolution.t()
  def query(selections, opts \\ []) do
    build(selections, Keyword.put_new(opts, :root, :contact))
  end

  @doc """
  A mutation resolution whose projected selection is `selections`.

  Behaviorally identical to `query/2` — only the root field name differs — so a
  test can assert that the middleware projects mutations exactly like queries.
  Accepts the same options as `query/2` (`:root` default `:create_contact`).
  """
  @spec mutation([DocField.t()], keyword()) :: Absinthe.Resolution.t()
  def mutation(selections, opts \\ []) do
    build(selections, Keyword.put_new(opts, :root, :create_contact))
  end

  @doc """
  Wraps `inner` in a Flop-style single-level envelope selection,
  `data { inner } meta { total }`, so `call/2` with `envelope: :data` descends
  into `data` and never projects `meta`.

  Options:

    * `:siblings` — extra top-level fields placed **outside** the envelope
      (alongside `data`/`meta`), used to assert that fields outside the envelope
      are never projected. Default `[]`.
  """
  @spec data_envelope([DocField.t()], keyword()) :: [DocField.t()]
  def data_envelope(inner, opts \\ []) do
    siblings = Keyword.get(opts, :siblings, [])
    [field(:data, inner)] ++ siblings ++ [field(:meta, [field(:total, [])])]
  end

  @doc """
  Wraps `inner` in a multi-level envelope selection, `page { entries { inner } }`,
  so `call/2` with `envelope: [:page, :entries]` descends both levels before
  projecting.
  """
  @spec page_entries_envelope([DocField.t()]) :: [DocField.t()]
  def page_entries_envelope(inner) do
    [field(:page, [field(:entries, inner)])]
  end

  @doc """
  A meta-only envelope selection, `meta { total }`, with no `data` field — used to
  assert that a query omitting the envelope field stores `[]`.
  """
  @spec meta_only_envelope() :: [DocField.t()]
  def meta_only_envelope do
    [field(:meta, [field(:total, [])])]
  end

  defp build(selections, opts) do
    context = Keyword.get(opts, :context, %{})
    errors = Keyword.get(opts, :errors, [])
    root = Keyword.get(opts, :root, :contact)

    parent_type = %Type.Object{
      identifier: root,
      name: root |> to_string() |> Macro.camelize(),
      fields: fields_map(selections)
    }

    definition = %DocField{
      name: to_string(root),
      alias: nil,
      selections: selections,
      schema_node: %Type.Field{identifier: root, name: to_string(root), type: parent_type}
    }

    %Absinthe.Resolution{
      definition: definition,
      context: context,
      errors: errors,
      path: [],
      fragments: %{},
      fields_cache: %{},
      schema: nil
    }
  end

  # The projector resolves each non-introspection top-level selection's
  # identifier against the parent type's `fields` map. Build that map from the
  # selections themselves so every identifier the projector looks up is present;
  # `__typename` (and other `__`-prefixed fields) are skipped there.
  defp fields_map(selections) do
    for %{name: name, schema_node: %{identifier: identifier}} <- selections,
        not introspection_name?(name),
        into: %{} do
      {identifier, %Type.Field{identifier: identifier, name: to_string(identifier)}}
    end
  end

  defp introspection_name?("__" <> _), do: true
  defp introspection_name?(_), do: false
end
