defmodule AbsintheProjector.IntrospectionTest do
  use ExUnit.Case, async: true

  alias AbsintheProjector.Introspection
  alias AbsintheProjector.Introspection.Association

  alias AbsintheProjector.TestSchemas.{
    Bank,
    Contact,
    Installment,
    NoAssociations,
    NotASchema,
    Payment,
    Profile,
    Tag
  }

  describe "associations/1" do
    test "returns every association with correct kind and related for all 5 kinds" do
      assocs = Introspection.associations(Contact)

      assert %Association{name: :bank, kind: :belongs_to, related: Bank} = assocs[:bank]
      assert %Association{name: :profile, kind: :has_one, related: Profile} = assocs[:profile]

      assert %Association{name: :installments, kind: :has_many, related: Installment} =
               assocs[:installments]

      assert %Association{name: :tags, kind: :many_to_many, related: Tag} = assocs[:tags]
      assert %Association{name: :payments, kind: :through, related: Payment} = assocs[:payments]
    end

    test "resolves a :through association to its final related schema" do
      # Contact.payments = through: [:installments, :payments]
      # Contact -> Installment -> Payment
      assert %Association{kind: :through, related: Payment} =
               Introspection.associations(Contact)[:payments]
    end

    test "excludes embeds_one and embeds_many fields" do
      keys = Introspection.associations(Contact) |> Map.keys()

      refute :settings in keys
      refute :notes in keys
    end

    test "excludes scalar fields" do
      keys = Introspection.associations(Contact) |> Map.keys()

      refute :name in keys
      refute :age in keys
    end

    test "returns an empty map for a schema with no associations" do
      assert Introspection.associations(NoAssociations) == %{}
    end

    test "raises ArgumentError naming a non-Ecto module" do
      assert_raise ArgumentError, ~r/NotASchema/, fn ->
        Introspection.associations(NotASchema)
      end
    end
  end

  describe "association/2" do
    test "returns a single entry by name" do
      assert %Association{name: :bank, kind: :belongs_to, related: Bank} =
               Introspection.association(Contact, :bank)
    end

    test "returns nil for a scalar or unknown name" do
      assert Introspection.association(Contact, :name) == nil
      assert Introspection.association(Contact, :does_not_exist) == nil
    end

    test "raises ArgumentError on a non-Ecto module" do
      assert_raise ArgumentError, ~r/NotASchema/, fn ->
        Introspection.association(NotASchema, :whatever)
      end
    end
  end
end
