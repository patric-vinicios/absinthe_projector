defmodule AbsintheProjector.TestFields do
  @moduledoc """
  Builders for `Absinthe.Blueprint.Document.Field` nodes used by the projection
  engine unit tests.

  The engine consumes already-projected field nodes (as `Absinthe.Resolution.project/1`
  returns), reading only `schema_node.identifier` (to match associations) and
  `selections` (to recurse). These builders construct real blueprint field
  structs from an identifier plus child selections, so an engine test reads like
  the GraphQL selection it represents — without standing up Absinthe's execution
  pipeline.
  """

  alias Absinthe.Blueprint.Document.Field
  alias Absinthe.Type

  @doc """
  A projected field whose schema identifier is `identifier`, with optional
  `children` selections.

  A scalar field is just a `field/1` whose identifier is not an association
  (e.g. `field(:name)`); a `__typename` or unknown field is `field(:__typename)` /
  `field(:does_not_exist)`.
  """
  @spec field(atom(), [Field.t()]) :: Field.t()
  def field(identifier, children \\ []) when is_atom(identifier) do
    %Field{
      name: Atom.to_string(identifier),
      selections: children,
      schema_node: %Type.Field{identifier: identifier}
    }
  end

  @doc """
  Same as `field/2` but with a distinct response `name`/`alias`, simulating a
  GraphQL alias. The `schema_node.identifier` is unchanged, which is exactly why
  aliased requests of one association merge into a single entry.
  """
  @spec aliased(atom(), atom(), [Field.t()]) :: Field.t()
  def aliased(as, identifier, children \\ []) when is_atom(as) and is_atom(identifier) do
    %{field(identifier, children) | name: Atom.to_string(as), alias: Atom.to_string(as)}
  end

  @doc """
  A field node with no `schema_node` (as some introspection nodes have); the
  engine must skip it silently.
  """
  @spec no_schema_node(String.t()) :: Field.t()
  def no_schema_node(name \\ "orphan") do
    %Field{name: name, schema_node: nil}
  end
end
