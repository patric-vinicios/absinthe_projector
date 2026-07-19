<p align="center">
  <img src="logo.png" alt="AbsintheProjector" width="420">
</p>

<h1 align="center">AbsintheProjector</h1>

<p align="center">
  <a href="https://hex.pm/packages/absinthe_projector"><img src="https://img.shields.io/hexpm/v/absinthe_projector.svg" alt="Hex.pm"></a>
  <a href="https://hexdocs.pm/absinthe_projector"><img src="https://img.shields.io/badge/hexdocs-docs-8e7ce6.svg" alt="HexDocs"></a>
  <a href="https://hex.pm/packages/absinthe_projector"><img src="https://img.shields.io/hexpm/l/absinthe_projector.svg" alt="License"></a>
</p>

<p align="center">
  Your GraphQL client already says exactly which associations it wants.<br>
  Why does your resolver pretend it didn't hear?
</p>

---

**AbsintheProjector** is an [Absinthe](https://hexdocs.pm/absinthe) middleware that converts each query's selection set into an exact Ecto preload tree — discovered from your Ecto schemas by reflection, never a hand-maintained list — ready to drop into a single `Repo.preload/2`.

```graphql
{
  contact {
    name
    bank { name }
    installments { payments { account { number } } }
  }
}
```

becomes, automatically:

```elixir
[:bank, installments: [payments: [:account]]]
```

No association N+1. No association overfetch. No rewriting resolvers. No spreading dataloader across your schema.

## Why

Every Absinthe + Ecto API picks one of two defaults:

- **Fixed preloads in the resolver** — you preload everything any client *might* ask for, on every request. Most of it is wasted queries.
- **Dataloader** — solves N+1 by batching, but asks you to restructure your schema with per-field resolvers, which fights the common "domain service returns a fully-loaded struct" architecture.

There is a third option hiding in plain sight: Absinthe already knows exactly what the client selected (`Absinthe.Resolution.project/1`), and Ecto already knows which fields are associations (`__schema__(:associations)`). AbsintheProjector just introduces them to each other.

|                          | Fixed preloads | Dataloader        | AbsintheProjector    |
| ------------------------ | -------------- | ----------------- | -------------------- |
| Loads only what's asked  | ❌             | ✅                | ✅                   |
| Keeps thin resolvers     | ✅             | ❌ per-field      | ✅ one middleware    |
| Works with domain services returning loaded structs | ✅ | ❌ | ✅ |
| Config per association   | none           | source per type   | none (reflection)    |

Dataloader is still the right tool for batching across *many parent records resolved independently*. AbsintheProjector shines when your resolver loads a record (or a page of records) at the top and wants its associations preloaded in one shot — the dominant shape in service-layer architectures.

## Installation

```elixir
def deps do
  [
    {:absinthe_projector, "~> 0.1.0"}
  ]
end
```

Requires Elixir ~> 1.14, `absinthe ~> 1.7`, `ecto ~> 3.10`.

## Quick start

Declare the middleware on a field, naming the root Ecto schema of that field's return type:

```elixir
query do
  field :contact, :contact do
    arg(:id, non_null(:id))
    middleware(AbsintheProjector, schema: MyApp.Contact)
    resolve(&Resolvers.get_contact/2)
  end
end
```

Read the computed preload tree in the resolver and pass it down as plain data:

```elixir
def get_contact(%{id: id}, resolution) do
  preloads = AbsintheProjector.preloads(resolution)
  Contacts.get(id, preloads)
end
```

Your domain code stays Absinthe-free — the tree is an ordinary keyword list that ends up in `Repo.preload/2` (or a `preload(^tree)` query composition):

```elixir
def get(id, preloads \\ []) do
  case Repo.get(Contact, id) do
    nil -> {:error, :not_found}
    contact -> {:ok, Repo.preload(contact, preloads)}
  end
end
```

That's the whole integration. Scalar fields, `__typename`, aliases, fragments and duplicate selections are all handled; anything that isn't a real association of the schema is ignored.

## Pagination envelopes

List fields that wrap entities in a pagination envelope ([Flop](https://hexdocs.pm/flop)'s `data`, or a custom `page { entries }`) declare where the entities live with `:envelope`:

```elixir
field :contacts, :contact_page do
  middleware(AbsintheProjector, schema: MyApp.Contact, envelope: :data)
  resolve(&Resolvers.list_contacts/2)
end
```

`:envelope` takes an atom (`:data`) or a list descended in order (`[:page, :entries]`). Sibling fields outside the envelope (`meta`, `totalCount`, …) are never projected, and a query that skips the envelope entirely yields `[]` — always a safe no-op for `Repo.preload/2`.

## How it works

1. `Absinthe.Resolution.project/1` gives the middleware the client's selection set, already normalized — fragments expanded, `@skip`/`@include` applied, each field carrying its schema identifier.
2. The optional envelope path is descended structurally.
3. The engine walks the selection recursively, asking Ecto's reflection API at every level: *is this field a real association, and which schema do I recurse into?* — including `has_through` chains. Adding an association to a schema makes it projectable automatically; there is no whitelist to maintain, so there is no whitelist to drift.
4. The resulting tree is stored on `resolution.context`; `AbsintheProjector.preloads/1` reads it back (`[]` when the middleware didn't run, so shared resolver helpers can call it unconditionally).

Everything is pure: no process state, no database access, no configuration.

### Fail-loud by design

Static misconfiguration surfaces immediately instead of degrading into an empty preload:

- missing `:schema` → `ArgumentError` with usage guidance;
- `:schema` that isn't an Ecto schema module → `ArgumentError` naming the module;
- malformed `:envelope` → `ArgumentError` naming the value.

A resolution that already carries errors passes through untouched — upstream failures are never masked.

## Troubleshooting

**Installed the middleware and preloads come back empty?** Force a recompile:

```bash
mix compile --force
```

Absinthe compiles your schema's imported type modules into a cached blueprint; swapping middleware inside an `import_types` module doesn't always invalidate it. This is an Absinthe compilation quirk, not specific to this library — one `--force` after wiring the middleware and you're done.

## License

MIT — see [LICENSE](https://github.com/patric-vinicios/absinthe_projector/blob/main/LICENSE).
