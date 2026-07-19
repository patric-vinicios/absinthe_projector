defmodule AbsintheProjector.TestMigrations do
  @moduledoc """
  Table definitions backing the `AbsintheProjector.TestSchemas` associations the
  F05 integration test loads through `Repo.preload/2`.

  Run once against the in-memory SQLite database from `test/test_helper.exs` via
  `Ecto.Migrator`. Only the tables the integration test exercises are created —
  `contacts`, `banks`, `accounts`, `profiles`, `installments`, `payments`,
  `tags`, and the `contacts_tags` join table — mirroring the field/association
  definitions already declared in `test/support/schemas.ex`.
  """
  use Ecto.Migration

  def up do
    create table(:banks) do
      add(:name, :string)
    end

    create table(:accounts) do
      add(:number, :string)
    end

    create table(:contacts) do
      add(:name, :string)
      add(:age, :integer)
      add(:bank_id, references(:banks))
      # Embed columns declared by the Contact schema (embeds_one/embeds_many);
      # they load with the parent row and never appear in the preload tree.
      add(:settings, :map)
      add(:notes, {:array, :map})
    end

    create table(:profiles) do
      add(:bio, :string)
      add(:contact_id, references(:contacts))
    end

    create table(:installments) do
      add(:due_on, :date)
      add(:contact_id, references(:contacts))
    end

    create table(:payments) do
      add(:amount, :integer)
      add(:installment_id, references(:installments))
      add(:account_id, references(:accounts))
    end

    create table(:tags) do
      add(:label, :string)
    end

    create table(:contacts_tags, primary_key: false) do
      add(:contact_id, references(:contacts))
      add(:tag_id, references(:tags))
    end
  end
end
