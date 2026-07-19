defmodule AbsintheProjector.TestSchemas do
  @moduledoc """
  Example Ecto schemas exercising every association kind, embeds, and scalars.

  Used by the introspection unit tests as fixtures. Namespaced under a single
  parent module to keep the test support surface tidy.
  """

  defmodule Bank do
    use Ecto.Schema

    schema "banks" do
      field(:name, :string)
    end
  end

  defmodule Account do
    use Ecto.Schema

    schema "accounts" do
      field(:number, :string)
    end
  end

  defmodule Profile do
    use Ecto.Schema

    schema "profiles" do
      field(:bio, :string)
      belongs_to(:contact, AbsintheProjector.TestSchemas.Contact)
    end
  end

  defmodule Payment do
    use Ecto.Schema

    schema "payments" do
      field(:amount, :integer)
      belongs_to(:installment, AbsintheProjector.TestSchemas.Installment)
      belongs_to(:account, Account)
    end
  end

  defmodule Installment do
    use Ecto.Schema

    schema "installments" do
      field(:due_on, :date)
      belongs_to(:contact, AbsintheProjector.TestSchemas.Contact)
      has_many(:payments, Payment)
    end
  end

  defmodule Tag do
    use Ecto.Schema

    schema "tags" do
      field(:label, :string)

      many_to_many(:contacts, AbsintheProjector.TestSchemas.Contact,
        join_through: "contacts_tags"
      )
    end
  end

  defmodule Settings do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:theme, :string)
    end
  end

  defmodule Note do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:body, :string)
    end
  end

  defmodule Contact do
    use Ecto.Schema

    schema "contacts" do
      # Scalar fields — must never appear in introspection metadata.
      field(:name, :string)
      field(:age, :integer)

      # All five association kinds.
      belongs_to(:bank, Bank)
      has_one(:profile, Profile)
      has_many(:installments, Installment)
      many_to_many(:tags, Tag, join_through: "contacts_tags")
      has_many(:payments, through: [:installments, :payments])

      # Embeds — must never appear in introspection metadata.
      embeds_one(:settings, Settings)
      embeds_many(:notes, Note)
    end
  end

  defmodule NoAssociations do
    use Ecto.Schema

    schema "no_associations" do
      field(:value, :string)
    end
  end

  defmodule Node do
    @moduledoc """
    Self-referential schema — a `children` association whose related schema is
    itself — used to exercise arbitrarily deep (e.g. 5-level) projection with a
    single recursive shape.
    """
    use Ecto.Schema

    schema "nodes" do
      field(:label, :string)
      belongs_to(:parent, AbsintheProjector.TestSchemas.Node)
      has_many(:children, AbsintheProjector.TestSchemas.Node, foreign_key: :parent_id)
    end
  end

  defmodule NotASchema do
    @moduledoc "A plain module that is not an Ecto schema (negative case)."
    def hello, do: :world
  end
end
