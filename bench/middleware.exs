# Overhead benchmark for AbsintheProjector.call/2 (PRD F03 criterion:
# < 1 ms p95 per operation for a 50-field / 5-level selection).
#
# Run with:  mix run bench/middleware.exs
#
# The library's test-support fixtures live under test/support and are not
# compiled in :dev, so this script defines its own self-referential Ecto schema
# and builds its own blueprint selection and resolution — enough to drive
# `Absinthe.Resolution.project/1` and the engine against a `BenchNode`-shaped schema
# (self-referential `children`, giving unbounded depth) with wide sibling
# selections at the root.

alias Absinthe.Blueprint.Document.Field, as: DocField
alias Absinthe.Type

defmodule BenchNode do
  @moduledoc "Self-referential Ecto schema mirroring the example `BenchNode` fixture."
  use Ecto.Schema

  schema "nodes" do
    field(:label, :string)
    belongs_to(:parent, BenchNode)
    has_many(:children, BenchNode, foreign_key: :parent_id)
  end
end

# A projected blueprint field whose schema identifier is `identifier`.
field = fn identifier, children ->
  %DocField{
    name: Atom.to_string(identifier),
    alias: nil,
    selections: children,
    schema_node: %Type.Field{identifier: identifier, name: Atom.to_string(identifier)}
  }
end

# A 5-level-deep chain of `children` (BenchNode -> BenchNode -> ... 5 levels).
deep_children =
  Enum.reduce(1..5, [], fn _level, acc -> [field.(:children, acc)] end)
  |> hd()

# Pad the root selection with distinct scalar fields to reach 50 field nodes:
# 44 scalars + :parent + the 5-node deep children chain = 50.
scalars =
  for i <- 1..44 do
    node = field.(:label, [])
    %{node | name: "label_#{i}", alias: "label_#{i}"}
  end

root_selections = scalars ++ [field.(:parent, []), deep_children]

total_nodes =
  Enum.reduce(root_selections, 0, fn selection, acc ->
    count = fn selection, count ->
      Enum.reduce(selection.selections, 1, fn child, n -> n + count.(child, count) end)
    end

    acc + count.(selection, count)
  end)

IO.puts("Benchmark selection: #{total_nodes} field nodes, 5 nesting levels, schema BenchNode")

# The minimal Absinthe type context project/1 needs: the field-return type as a
# Type.Object whose `fields` map resolves every top-level selection identifier.
fields_map =
  root_selections
  |> Enum.map(& &1.schema_node.identifier)
  |> Enum.uniq()
  |> Map.new(fn id -> {id, %Type.Field{identifier: id, name: Atom.to_string(id)}} end)

parent_type = %Type.Object{identifier: :node, name: "BenchNode", fields: fields_map}

resolution = %Absinthe.Resolution{
  definition: %DocField{
    name: "node",
    alias: nil,
    selections: root_selections,
    schema_node: %Type.Field{identifier: :node, name: "node", type: parent_type}
  },
  context: %{},
  errors: [],
  path: [],
  fragments: %{},
  fields_cache: %{},
  schema: nil
}

# Sanity check that the tree actually descends 5 levels before benchmarking.
tree = AbsintheProjector.call(resolution, schema: BenchNode).context[:absinthe_projector]
IO.inspect(tree, label: "computed preload tree")

%{scenarios: [scenario]} =
  Benchee.run(
    %{
      "AbsintheProjector.call/2 (50 fields / 5 levels)" => fn ->
        AbsintheProjector.call(resolution, schema: BenchNode)
      end
    },
    time: 5,
    warmup: 2,
    percentiles: [50, 95, 99],
    print: [fast_warning: false]
  )

# Report the p95 against the 1 ms budget.
p95_ns = scenario.run_time_data.statistics.percentiles[95]
p95_ms = p95_ns / 1_000_000

IO.puts("\np95: #{Float.round(p95_ms, 4)} ms (budget: < 1 ms)")

if p95_ms < 1.0 do
  IO.puts("PASS — within the F03 overhead budget.")
else
  IO.puts("FAIL — exceeds the 1 ms p95 overhead budget.")
  System.at_exit(fn _ -> exit({:shutdown, 1}) end)
end
