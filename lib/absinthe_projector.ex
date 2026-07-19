defmodule AbsintheProjector do
  @moduledoc """
  Absinthe middleware that projects an incoming query's selection set into an
  exact `Repo.preload/2` tree.

  Declare it per field, naming the root Ecto schema of the field's return type:

      query do
        field :order, :order do
          middleware(AbsintheProjector, schema: MyApp.Order)
          resolve(&Resolvers.order/3)
        end
      end

  Before the resolver runs, the middleware obtains the projected child fields via
  `Absinthe.Resolution.project/1`, feeds them plus the declared schema to
  `AbsintheProjector.Engine.project/2`, and stores the resulting nested
  preload tree in `resolution.context[:absinthe_projector]`. The resolver then
  hands that tree to its domain service (via `AbsintheProjector.preloads/1`):

      def order(_parent, %{id: id}, resolution) do
        preloads = AbsintheProjector.preloads(resolution)
        {:ok, Orders.get_order!(id, preloads)}
      end

  The middleware behaves identically on query and mutation fields, and is
  idempotent — reapplying it recomputes and overwrites the same context key with
  the same value.

  ## Pagination envelopes

  List/paginated fields whose entities live inside a wrapper (Flop's `data`, or a
  multi-level `page { entries }`) add the opt-in `:envelope` option so projection
  starts inside that wrapper instead of at the field root:

      field :orders, :order_page do
        middleware(AbsintheProjector, schema: MyApp.Order, envelope: :data)
        resolve(&Resolvers.list_orders/3)
      end

  `:envelope` accepts a single atom (`:data`), a list of atoms
  (`[:page, :entries]`) descended in order, or is absent (no envelope — projection
  from the field root). Only the innermost selection is projected against
  `:schema`; sibling fields outside the envelope (`meta`, `total`) are never
  projected, and a query that omits the envelope field stores `[]`. See
  `AbsintheProjector.Envelope` for the descent contract. Everything else — context
  key, tree format, error pass-through, idempotency — is identical to a
  single-record field.

  ## Validation

  The `:schema` option is validated eagerly and fail-loud at the top of `call/2`,
  before any error pass-through, so a static misconfiguration never hides behind
  an unrelated runtime error:

    * omitting `:schema` raises `ArgumentError` with the declaration usage;
    * passing a module that is not an Ecto schema raises `ArgumentError` naming
      the module (delegated to `AbsintheProjector.Introspection`, the single
      validation point);
    * an `:envelope` value that is neither an atom, `nil`, nor a list of atoms
      raises `ArgumentError` naming the received value, so a mistyped envelope
      path never silently degrades to an empty preload tree.

  ## Error pass-through

  When the incoming resolution already carries errors (`resolution.errors != []`),
  the middleware is a strict pass-through: it returns the resolution unchanged,
  with no projection and no context write, so upstream failures are never masked
  or reordered.

  ## Empty result

  When the selection contains no associations, the stored tree is `[]` (never
  `nil`), so a downstream `Repo.preload/2` is always a safe no-op.
  """

  @behaviour Absinthe.Middleware

  alias AbsintheProjector.{Engine, Envelope, Introspection}

  @typedoc """
  A nested Ecto preload tree, in the exact shape accepted by `Repo.preload/2`:
  a list whose entries are bare association names (leaves) or
  `{association, subtree}` pairs, e.g. `[:customer, items: [product: [:supplier]]]`.
  """
  @type preload_tree :: [atom() | {atom(), preload_tree()}]

  @context_key :absinthe_projector

  @missing_schema_message "AbsintheProjector requires a :schema option with the root Ecto schema module, e.g. middleware(AbsintheProjector, schema: MyApp.Order)"

  @doc """
  Middleware entry point. See the module documentation for the full contract.

  Validates the `:schema` option eagerly, passes an already-errored resolution
  through untouched, and otherwise stores the projected preload tree under the
  `#{inspect(@context_key)}` context key.
  """
  @impl Absinthe.Middleware
  @spec call(Absinthe.Resolution.t(), keyword()) :: Absinthe.Resolution.t()
  def call(%Absinthe.Resolution{} = resolution, opts) do
    schema = validate_schema!(opts)
    envelope_path = normalize_envelope!(opts)

    case resolution.errors do
      [] ->
        tree =
          resolution
          |> Absinthe.Resolution.project()
          |> Envelope.descend(envelope_path)
          |> Engine.project(schema)

        %{resolution | context: Map.put(resolution.context, @context_key, tree)}

      _errors ->
        resolution
    end
  end

  @doc """
  Returns the preload tree the middleware stored on `resolution`.

  Reads `resolution.context[#{inspect(@context_key)}]`, the tree computed by
  `call/2` from the operation's projected selection set, and returns it
  unmodified — ready to pass straight to `Repo.preload/2` or an Ecto
  `preload(^tree)` composition:

      def order(_parent, %{id: id}, resolution) do
        preloads = AbsintheProjector.preloads(resolution)
        {:ok, Orders.get_order!(id, preloads)}
      end

  When the middleware never ran on this field (the context key is absent), it
  returns `[]`. That makes the read side safe for shared resolver helpers, which
  can call `preloads/1` unconditionally and behave identically on projected and
  non-projected fields — and, because `call/2` always stores a list (`[]` for a
  selection with no associations, never `nil`), the result is always a valid,
  safe-no-op argument to `Repo.preload/2`.

      iex> resolution = %Absinthe.Resolution{context: %{absinthe_projector: [:customer]}}
      iex> AbsintheProjector.preloads(resolution)
      [:customer]

      iex> AbsintheProjector.preloads(%Absinthe.Resolution{context: %{}})
      []
  """
  @spec preloads(Absinthe.Resolution.t()) :: preload_tree()
  def preloads(%Absinthe.Resolution{context: context}) do
    Map.get(context, @context_key, [])
  end

  @doc """
  Returns the namespaced context key the middleware writes the preload tree to.

  The same atom `call/2` stores under and `preloads/1` reads from — exposed so
  advanced consumers (Absinthe plugins, telemetry wrappers) can read the context
  directly without hardcoding the atom:

      iex> AbsintheProjector.context_key()
      :absinthe_projector
  """
  @spec context_key() :: atom()
  def context_key, do: @context_key

  # Eager, fail-loud validation of the `:schema` option. A missing option raises
  # a guidance message; a present-but-non-Ecto module reuses the single
  # validation point (`Introspection.associations/1`), which raises naming the
  # offending value. Returns the validated schema module.
  defp validate_schema!(opts) do
    case Keyword.get(opts, :schema) do
      nil ->
        raise ArgumentError, @missing_schema_message

      schema ->
        # Delegates the Ecto-schema check to Introspection; the associations
        # lookup the engine repeats on the happy path is negligible under the
        # overhead budget.
        _ = Introspection.associations(schema)
        schema
    end
  end

  # Eager, fail-loud normalization of the `:envelope` option into a key path for
  # `Envelope.descend/2`. Runs before the errors pass-through, so a
  # mistyped path surfaces as a static developer error rather than a silently
  # empty preload tree:
  #
  #   * absent / `nil` -> `[]` (no descent — projection from the field root);
  #   * an atom (`:data`) -> `[:data]` (single-level descent);
  #   * a list of atoms (`[:page, :entries]`) -> the path as given;
  #   * anything else -> `ArgumentError` naming the received value.
  defp normalize_envelope!(opts) do
    case Keyword.get(opts, :envelope) do
      nil -> []
      atom when is_atom(atom) -> [atom]
      list when is_list(list) -> validate_path!(list)
      other -> raise ArgumentError, invalid_envelope_message(other)
    end
  end

  defp validate_path!(list) do
    if Enum.all?(list, &is_atom/1) do
      list
    else
      raise ArgumentError, invalid_envelope_message(list)
    end
  end

  defp invalid_envelope_message(value) do
    "AbsintheProjector :envelope option must be an atom or a list of atoms, e.g. " <>
      "envelope: :data or envelope: [:page, :entries], got: #{inspect(value)}"
  end
end
