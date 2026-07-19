defmodule AbsintheProjector.TestRepo do
  @moduledoc """
  Test-only Ecto repo backing the F05 end-to-end integration test.

  Runs on the SQLite3 adapter against an in-memory database (configured in
  `test/test_helper.exs`), so the "real database" acceptance criterion is met
  with zero external infrastructure. The `ecto_sql`/`ecto_sqlite3` dependencies
  are `:test`-only (ADR-005), so the shipped library's runtime dependency set
  stays Ecto + Absinthe (ADR-002).
  """
  use Ecto.Repo,
    otp_app: :absinthe_projector,
    adapter: Ecto.Adapters.SQLite3
end
