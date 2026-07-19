defmodule AbsintheProjector.Introspection.Association do
  @moduledoc """
  Metadata for a single Ecto association discovered via reflection.

  Produced by `AbsintheProjector.Introspection` and consumed by the projection
  engine. Each entry carries only what recursion needs: the association
  `name`, its `kind`, and the `related` schema module to continue into.

  For `:through` associations, `related` is resolved to the concrete schema at
  the **end** of the through-chain, so it is always directly preloadable.
  """

  @enforce_keys [:name, :kind, :related]
  defstruct [:name, :kind, :related]

  @typedoc "The association kind, as classified from Ecto reflection structs."
  @type kind :: :belongs_to | :has_one | :has_many | :many_to_many | :through

  @type t :: %__MODULE__{
          name: atom(),
          kind: kind(),
          related: module()
        }
end
