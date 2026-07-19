defmodule AbsintheProjector.EngineTest do
  use ExUnit.Case, async: true

  import AbsintheProjector.TestFields

  alias AbsintheProjector.Engine

  alias AbsintheProjector.TestSchemas.{Contact, Node}

  describe "project/2 — matching and scalars" do
    test "a flat selection keeps only associations and drops scalar fields" do
      # contact { name age nickname bank { name } tags { label } }
      fields = [
        field(:name),
        field(:age),
        field(:nickname),
        field(:bank, [field(:name)]),
        field(:tags, [field(:label)])
      ]

      assert Engine.project(fields, Contact) == [:bank, :tags]
    end

    test "a selection with no association fields returns []" do
      assert Engine.project([field(:name), field(:age)], Contact) == []
    end

    test "__typename and unknown identifiers are never present in the output" do
      # contact { __typename bank { name } not_a_field }
      fields = [field(:__typename), field(:bank, [field(:name)]), field(:not_a_field)]

      assert Engine.project(fields, Contact) == [:bank]
    end

    test "fields with a nil schema_node are skipped" do
      assert Engine.project([no_schema_node(), field(:bank)], Contact) == [:bank]
    end
  end

  describe "project/2 — nesting and shape" do
    test "an association whose children hold no associations collapses to a bare atom" do
      # contact { installments { due_on } }
      result = Engine.project([field(:installments, [field(:due_on)])], Contact)

      assert result == [:installments]
      refute match?([{:installments, _}], result)
    end

    test "a nested selection produces a valid Repo.preload keyword tree" do
      # contact { bank { name } installments { payments { account { number } } } }
      fields = [
        field(:bank, [field(:name)]),
        field(:installments, [field(:payments, [field(:account, [field(:number)])])])
      ]

      assert Engine.project(fields, Contact) == [:bank, installments: [payments: [:account]]]
    end

    test "a 5-level nested selection produces a 5-level nested keyword tree" do
      # node { children { children { children { children { children } } } } }
      five_deep =
        field(:children, [
          field(:children, [
            field(:children, [
              field(:children, [
                field(:children)
              ])
            ])
          ])
        ])

      assert Engine.project([five_deep], Node) ==
               [children: [children: [children: [children: [:children]]]]]
    end
  end

  describe "project/2 — deduplication and ordering" do
    test "two aliased requests of one association merge into a single union entry" do
      # a: installments { payments }  b: installments { payments { account } }
      fields = [
        aliased(:a, :installments, [field(:payments)]),
        aliased(:b, :installments, [field(:payments, [field(:account)])])
      ]

      result = Engine.project(fields, Contact)

      assert result == [installments: [payments: [:account]]]
      assert length(result) == 1
    end

    test "output order matches order of first appearance in the selection" do
      forward = [field(:installments), field(:bank), field(:tags)]
      reversed = [field(:tags), field(:bank), field(:installments)]

      assert Engine.project(forward, Contact) == [:installments, :bank, :tags]
      assert Engine.project(reversed, Contact) == [:tags, :bank, :installments]
    end
  end

  describe "project/2 — F01 → F02 integration (zero configuration)" do
    test "reflection alone drives matching: scalars excluded, any association projectable without config" do
      # `Node` is a schema the engine never special-cases; its associations
      # (`children`, `parent`) project purely from Ecto reflection (F01), while
      # its scalar `label` is excluded — no whitelist, no per-association config.
      # node { label children { label } parent }
      fields = [field(:label), field(:children, [field(:label)]), field(:parent)]

      result = Engine.project(fields, Node)

      assert result == [:children, :parent]
      refute Enum.any?(result, &match?({:label, _}, &1))
      refute :label in result
    end
  end
end
