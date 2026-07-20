defmodule AbsintheProjector.Integration.GraphQLSchema do
  use Absinthe.Schema

  alias AbsintheProjector.TestSchemas.Contact

  interface :entity do
    field(:name, :string)
    resolve_type(fn _, _ -> :contact end)
  end

  object :account do
    field(:number, :string)
  end

  object :payment do
    field(:account, :account)
  end

  object :installment do
    field(:payments, list_of(:payment))
  end

  object :bank do
    field(:name, :string)
  end

  object :contact do
    interface(:entity)
    field(:name, :string)
    field(:bank, :bank)
    field(:installments, list_of(:installment))
    field(:related_entity, :entity)
  end

  object :contact_with_abstract_bank do
    field(:bank, :entity)
  end

  object :contact_page do
    field(:data, list_of(:contact))
    field(:total, :integer)
  end

  union :search_result do
    types([:contact, :bank])
    resolve_type(fn %{type: type}, _ -> type end)
  end

  query do
    field :contact, :contact do
      middleware(AbsintheProjector, schema: Contact)
      resolve(&resolve_contact/2)
    end

    field :contacts, :contact_page do
      middleware(AbsintheProjector, schema: Contact, envelope: :data)

      resolve(fn _, resolution ->
        capture_preloads(resolution)
        {:ok, %{data: [contact()], total: 1}}
      end)
    end

    field :entity, :entity do
      middleware(AbsintheProjector, schema: Contact)
      resolve(&resolve_contact/2)
    end

    field :search, list_of(:search_result) do
      middleware(AbsintheProjector, schema: Contact)
      resolve(&resolve_contact/2)
    end

    field :abstract_bank_contact, :contact_with_abstract_bank do
      middleware(AbsintheProjector, schema: Contact)
      resolve(&resolve_contact/2)
    end
  end

  defp resolve_contact(_, resolution) do
    capture_preloads(resolution)
    {:ok, contact()}
  end

  defp capture_preloads(resolution) do
    identifier = resolution.definition.schema_node.identifier
    send(self(), {:preloads, identifier, AbsintheProjector.preloads(resolution)})
  end

  defp contact do
    %{
      type: :contact,
      name: "Ada",
      bank: %{type: :bank, name: "Acme"},
      related_entity: %{type: :contact, name: "Grace"},
      installments: [%{payments: [%{account: %{number: "0001"}}]}]
    }
  end
end

defmodule AbsintheProjector.Integration.AbsintheTest do
  use ExUnit.Case, async: true

  alias AbsintheProjector.Integration.GraphQLSchema

  test "normalizes an inline fragment nested below an association" do
    query = """
    {
      contact {
        installments {
          ... on Installment {
            payments { account { number } }
          }
        }
      }
    }
    """

    assert {:ok, %{data: %{"contact" => %{"installments" => [_]}}}} =
             Absinthe.run(query, GraphQLSchema)

    assert_receive {:preloads, :contact, [installments: [payments: [:account]]]}
  end

  test "normalizes a named fragment nested below an association" do
    query = """
    query {
      contact { installments { ...PaymentFields } }
    }

    fragment PaymentFields on Installment {
      payments { account { number } }
    }
    """

    assert {:ok, %{data: %{"contact" => %{"installments" => [_]}}}} =
             Absinthe.run(query, GraphQLSchema)

    assert_receive {:preloads, :contact, [installments: [payments: [:account]]]}
  end

  test "applies @skip and @include at nested levels" do
    query = """
    {
      contact {
        installments {
          skipped: payments @skip(if: true) { account { number } }
          excluded: payments @include(if: false) { account { number } }
        }
      }
    }
    """

    assert {:ok, %{data: %{"contact" => %{"installments" => [%{}]}}}} =
             Absinthe.run(query, GraphQLSchema)

    assert_receive {:preloads, :contact, [:installments]}
  end

  test "keeps nested fields selected by @skip(false) and @include(true)" do
    query = """
    {
      contact {
        installments {
          kept: payments @skip(if: false) { account { number } }
          included: payments @include(if: true) { account { number } }
        }
      }
    }
    """

    assert {:ok, %{data: %{"contact" => %{"installments" => [_]}}}} =
             Absinthe.run(query, GraphQLSchema)

    assert_receive {:preloads, :contact, [installments: [payments: [:account]]]}
  end

  test "normalizes fragments after descending an envelope" do
    query = """
    query {
      contacts { data { ...ContactFields } total }
    }

    fragment ContactFields on Contact {
      bank { name }
    }
    """

    assert {:ok, %{data: %{"contacts" => %{"data" => [_], "total" => 1}}}} =
             Absinthe.run(query, GraphQLSchema)

    assert_receive {:preloads, :contacts, [:bank]}
  end

  test "rejects an abstract interface before the resolver runs" do
    assert_raise ArgumentError,
                 ~r/cannot project abstract GraphQL type :entity at entity/,
                 fn -> Absinthe.run("{ entity { name } }", GraphQLSchema) end

    refute_receive {:preloads, :entity, _}
  end

  test "rejects an abstract union before the resolver runs" do
    query = "{ search { ... on Contact { name } } }"

    assert_raise ArgumentError,
                 ~r/cannot project abstract GraphQL type :search_result at search/,
                 fn -> Absinthe.run(query, GraphQLSchema) end

    refute_receive {:preloads, :search, _}
  end

  test "rejects an abstract type used by a nested Ecto association" do
    query = "{ abstractBankContact { bank { name } } }"

    assert_raise ArgumentError,
                 ~r/abstract GraphQL type :entity at abstract_bank_contact.bank/,
                 fn -> Absinthe.run(query, GraphQLSchema) end

    refute_receive {:preloads, :abstract_bank_contact, _}
  end

  test "ignores an abstract GraphQL field that is not an Ecto association" do
    query = "{ contact { relatedEntity { name } } }"

    assert {:ok, %{data: %{"contact" => %{"relatedEntity" => %{"name" => "Grace"}}}}} =
             Absinthe.run(query, GraphQLSchema)

    assert_receive {:preloads, :contact, []}
  end
end
