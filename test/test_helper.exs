# F05 real-database integration harness (ADR-005): a test-only SQLite repo whose
# tables are created in-memory before the suite runs, exercised through
# `Ecto.Adapters.SQL.Sandbox`. The DB deps are `:test`-only, so the shipped
# library's runtime dependency set stays Ecto + Absinthe (ADR-002).
Application.put_env(:absinthe_projector, AbsintheProjector.TestRepo,
  database: ":memory:",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1,
  log: false
)

{:ok, _} = AbsintheProjector.TestRepo.start_link()

# In-memory SQLite lives on a single connection, so check it out here, create the
# tables on it, then hand that same connection to every test via shared mode.
Ecto.Adapters.SQL.Sandbox.mode(AbsintheProjector.TestRepo, :manual)
:ok = Ecto.Adapters.SQL.Sandbox.checkout(AbsintheProjector.TestRepo)
Ecto.Migrator.up(AbsintheProjector.TestRepo, 0, AbsintheProjector.TestMigrations, log: false)
Ecto.Adapters.SQL.Sandbox.mode(AbsintheProjector.TestRepo, {:shared, self()})

ExUnit.start()
