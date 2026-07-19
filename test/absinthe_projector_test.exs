defmodule AbsintheProjectorTest do
  use ExUnit.Case, async: true

  doctest AbsintheProjector

  import AbsintheProjector.TestFields
  import AbsintheProjector.TestResolutions

  alias AbsintheProjector.Engine
  alias AbsintheProjector.TestSchemas.{Contact, NotASchema}

  @context_key :absinthe_projector

  describe "call/2 — context storage" do
    test "stores the computed tree under the context key before the resolver runs" do
      # contact { name bank { name } installments { payments { account { number } } } }
      selections = [
        field(:name),
        field(:bank, [field(:name)]),
        field(:installments, [field(:payments, [field(:account, [field(:number)])])])
      ]

      result = AbsintheProjector.call(query(selections), schema: Contact)

      assert result.context[@context_key] == [:bank, installments: [payments: [:account]]]
    end

    test "the stored tree is byte-identical to the engine's output (F02 → F03)" do
      # A mix of scalars and associations, aliases, and nesting — the middleware
      # must store exactly what Engine.project/2 computes for the same selection.
      selections = [
        field(:name),
        aliased(:primary_bank, :bank, [field(:name)]),
        field(:tags, [field(:label)]),
        field(:installments, [field(:payments, [field(:account)])])
      ]

      result = AbsintheProjector.call(query(selections), schema: Contact)

      assert result.context[@context_key] == Engine.project(selections, Contact)
    end

    test "works identically on a mutation field" do
      selections = [
        field(:bank, [field(:name)]),
        field(:installments, [field(:payments)])
      ]

      query_tree =
        AbsintheProjector.call(query(selections), schema: Contact).context[@context_key]

      mutation_tree =
        AbsintheProjector.call(mutation(selections), schema: Contact).context[@context_key]

      assert mutation_tree == query_tree
    end

    test "a selection with zero associations stores [] (not nil)" do
      result = AbsintheProjector.call(query([field(:name), field(:age)]), schema: Contact)

      assert result.context[@context_key] == []
    end

    test "preserves unrelated context entries" do
      resolution = query([field(:bank)], context: %{current_user: :alice})

      result = AbsintheProjector.call(resolution, schema: Contact)

      assert result.context[:current_user] == :alice
      assert result.context[@context_key] == [:bank]
    end
  end

  describe "call/2 — eager, fail-loud validation" do
    test "missing :schema raises ArgumentError with usage guidance" do
      assert_raise ArgumentError,
                   ~r/:schema option.*middleware\(AbsintheProjector, schema:/s,
                   fn ->
                     AbsintheProjector.call(query([field(:bank)]), [])
                   end
    end

    test "non-Ecto :schema raises ArgumentError naming the module" do
      assert_raise ArgumentError, ~r/expected an Ecto schema module.*NotASchema/s, fn ->
        AbsintheProjector.call(query([field(:bank)]), schema: NotASchema)
      end
    end

    test "raises on misconfiguration even when the resolution already has errors" do
      errored = query([field(:bank)], errors: [%{message: "boom"}])

      assert_raise ArgumentError, fn -> AbsintheProjector.call(errored, []) end
      assert_raise ArgumentError, fn -> AbsintheProjector.call(errored, schema: NotASchema) end
    end
  end

  describe "call/2 — error pass-through" do
    test "a resolution with non-empty errors passes through unchanged" do
      errored =
        query([field(:bank, [field(:name)])],
          errors: [%{message: "boom"}],
          context: %{current_user: :alice}
        )

      result = AbsintheProjector.call(errored, schema: Contact)

      assert result == errored
      refute Map.has_key?(result.context, @context_key)
    end
  end

  describe "call/2 — idempotency" do
    test "reapplying overwrites the context key with the same value" do
      selections = [field(:bank, [field(:name)]), field(:installments, [field(:payments)])]

      once = AbsintheProjector.call(query(selections), schema: Contact)
      twice = AbsintheProjector.call(once, schema: Contact)

      assert twice.context[@context_key] == once.context[@context_key]
    end
  end

  describe "preloads/1 (F05)" do
    test "returns the exact tree the middleware stored" do
      selections = [
        field(:bank, [field(:name)]),
        field(:installments, [field(:payments, [field(:account)])])
      ]

      result = AbsintheProjector.call(query(selections), schema: Contact)

      # Reads back precisely what call/2 wrote under the context key.
      assert AbsintheProjector.preloads(result) == result.context[@context_key]
      assert AbsintheProjector.preloads(result) == [:bank, installments: [payments: [:account]]]
    end

    test "returns [] when the middleware never ran (context key absent)" do
      resolution = query([field(:bank)])

      # The projector never touched this resolution — no context key.
      refute Map.has_key?(resolution.context, @context_key)
      assert AbsintheProjector.preloads(resolution) == []
    end

    test "returns [] (not nil) when the middleware stored an association-free selection" do
      result = AbsintheProjector.call(query([field(:name), field(:age)]), schema: Contact)

      assert AbsintheProjector.preloads(result) == []
    end
  end

  describe "context_key/0 (F05)" do
    test "returns the key the middleware writes to" do
      result = AbsintheProjector.call(query([field(:bank)]), schema: Contact)

      assert AbsintheProjector.context_key() == @context_key
      assert Map.has_key?(result.context, AbsintheProjector.context_key())
      assert result.context[AbsintheProjector.context_key()] == [:bank]
    end
  end
end
