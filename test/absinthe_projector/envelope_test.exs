defmodule AbsintheProjector.EnvelopeTest do
  use ExUnit.Case, async: true

  doctest AbsintheProjector.Envelope

  import AbsintheProjector.TestFields
  import AbsintheProjector.TestResolutions

  alias AbsintheProjector.Engine
  alias AbsintheProjector.Envelope
  alias AbsintheProjector.TestSchemas.Contact

  @context_key :absinthe_projector

  # Association selections of Contact reused across the descent tests.
  defp inner_selection do
    [
      field(:name),
      field(:bank, [field(:name)]),
      field(:installments, [field(:payments, [field(:account, [field(:number)])])])
    ]
  end

  @inner_tree [:bank, installments: [payments: [:account]]]

  describe "call/2 — single-level envelope" do
    test "envelope: :data projects only from the data selection" do
      # data { name bank { name } installments { payments { account { number } } } }
      # meta { total }
      selections = data_envelope(inner_selection())

      result = AbsintheProjector.call(query(selections), schema: Contact, envelope: :data)

      # Tree comes only from data's selection; meta's `total` never appears.
      assert result.context[@context_key] == @inner_tree
    end

    test "a query that does not request the envelope field stores []" do
      result =
        AbsintheProjector.call(query(meta_only_envelope()), schema: Contact, envelope: :data)

      assert result.context[@context_key] == []
    end

    test "fields requested outside the envelope never appear in the tree" do
      # `tags` is a real Contact association, but requested as a sibling of `data`,
      # outside the envelope — it must be excluded from the tree.
      selections =
        data_envelope([field(:bank, [field(:name)])],
          siblings: [field(:tags, [field(:label)])]
        )

      result = AbsintheProjector.call(query(selections), schema: Contact, envelope: :data)

      assert result.context[@context_key] == [:bank]
    end

    test "aliased/duplicated envelope fields union their selections" do
      # d1: data { bank }   d2: data { installments }
      selections = [
        aliased(:d1, :data, [field(:bank, [field(:name)])]),
        aliased(:d2, :data, [field(:installments, [field(:payments)])]),
        field(:meta, [field(:total)])
      ]

      result = AbsintheProjector.call(query(selections), schema: Contact, envelope: :data)

      assert result.context[@context_key] == [:bank, installments: [:payments]]
    end
  end

  describe "call/2 — multi-level envelope" do
    test "a key-path envelope descends every level before projecting" do
      # page { entries { name bank { name } installments { payments { account { number } } } } }
      selections = page_entries_envelope(inner_selection())

      result =
        AbsintheProjector.call(query(selections), schema: Contact, envelope: [:page, :entries])

      assert result.context[@context_key] == @inner_tree
    end

    test "a key-path envelope stores [] when an inner level is absent" do
      # page { total }  — no `entries`
      selections = [field(:page, [field(:total)])]

      result =
        AbsintheProjector.call(query(selections), schema: Contact, envelope: [:page, :entries])

      assert result.context[@context_key] == []
    end
  end

  describe "call/2 — no-envelope regression (F03)" do
    test "without the envelope option, projection starts at the field root" do
      selections = inner_selection()

      with_option = AbsintheProjector.call(query(selections), schema: Contact)
      f03_tree = Engine.project(selections, Contact)

      assert with_option.context[@context_key] == f03_tree
      assert with_option.context[@context_key] == @inner_tree
    end
  end

  describe "call/2 — cross-feature parity (F03 -> F04)" do
    test "an inside-envelope selection projects identically to the same selection at a root" do
      inner = inner_selection()

      enveloped =
        AbsintheProjector.call(query(data_envelope(inner)), schema: Contact, envelope: :data)

      at_root = AbsintheProjector.call(query(inner), schema: Contact)

      # The envelope changes only the starting point: byte-identical trees.
      assert enveloped.context[@context_key] == at_root.context[@context_key]
      assert enveloped.context[@context_key] == Engine.project(inner, Contact)
    end
  end

  describe "call/2 — eager, fail-loud envelope validation" do
    test "a string envelope value raises ArgumentError naming the value" do
      assert_raise ArgumentError, ~r/:envelope.*"data"/s, fn ->
        AbsintheProjector.call(query([field(:bank)]), schema: Contact, envelope: "data")
      end
    end

    test "a list with a non-atom element raises ArgumentError naming the value" do
      assert_raise ArgumentError, ~r/:envelope.*"x"/s, fn ->
        AbsintheProjector.call(query([field(:bank)]), schema: Contact, envelope: [:page, "x"])
      end
    end

    test "raises eagerly even when the resolution already has errors" do
      errored = query([field(:bank)], errors: [%{message: "boom"}])

      assert_raise ArgumentError, fn ->
        AbsintheProjector.call(errored, schema: Contact, envelope: "data")
      end
    end
  end

  describe "Envelope.descend/2" do
    test "returns the fields unchanged for an empty path (no-envelope identity)" do
      fields = inner_selection()

      assert Envelope.descend(fields, []) == fields
    end

    test "returns the innermost selection for a matching single-level path" do
      inner = [field(:bank)]
      fields = data_envelope(inner)

      assert Envelope.descend(fields, [:data]) == inner
    end

    test "returns [] when a key matches no field" do
      assert Envelope.descend(meta_only_envelope(), [:data]) == []
    end

    test "unions the selections of every field matching the key at a level" do
      fields = [
        aliased(:d1, :data, [field(:bank)]),
        aliased(:d2, :data, [field(:installments)])
      ]

      assert Envelope.descend(fields, [:data]) == [field(:bank), field(:installments)]
    end
  end
end
