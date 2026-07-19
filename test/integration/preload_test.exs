defmodule AbsintheProjector.Integration.PreloadTest do
  @moduledoc """
  End-to-end F05 integration test against a real (in-memory SQLite) database.

  Proves the full library flow the PRD is built around round-trips through a real
  `Repo.preload/2`: the middleware (`call/2`) projects the selection set into a
  tree, `preloads/1` hands it back, and `Repo.preload/2` loads exactly the
  requested associations — for both a single-record field and an envelope-based
  list field — with none of the unrequested ones forced.
  """
  # Shared sandbox connection (in-memory SQLite) — not safe to run concurrently.
  use ExUnit.Case, async: false

  import AbsintheProjector.TestFields
  import AbsintheProjector.TestResolutions

  alias AbsintheProjector.TestRepo
  alias AbsintheProjector.TestSchemas.{Account, Bank, Contact, Installment, Payment}

  setup do
    # Seed one fully-associated Contact: bank, and installments → payments → account.
    bank = TestRepo.insert!(%Bank{name: "Acme Bank"})
    account = TestRepo.insert!(%Account{number: "0001"})
    contact = TestRepo.insert!(%Contact{name: "Ada", age: 37, bank_id: bank.id})
    installment = TestRepo.insert!(%Installment{contact_id: contact.id})

    _payment =
      TestRepo.insert!(%Payment{
        amount: 100,
        installment_id: installment.id,
        account_id: account.id
      })

    %{contact_id: contact.id}
  end

  # The nested association selection both cases project against `Contact`:
  # `bank { name } installments { payments { account { number } } }`.
  defp contact_selections do
    [
      field(:name),
      field(:bank, [field(:name)]),
      field(:installments, [field(:payments, [field(:account, [field(:number)])])])
    ]
  end

  test "Repo.preload/2 accepts preloads/1 output for a single-record field", %{contact_id: id} do
    resolution = AbsintheProjector.call(query(contact_selections()), schema: Contact)
    preloads = AbsintheProjector.preloads(resolution)

    assert preloads == [:bank, installments: [payments: [:account]]]

    contact = TestRepo.get!(Contact, id) |> TestRepo.preload(preloads)

    # Every requested association loaded, all the way down.
    assert %Bank{name: "Acme Bank"} = contact.bank
    assert [%Installment{} = installment] = contact.installments
    assert [%Payment{} = payment] = installment.payments
    assert %Account{number: "0001"} = payment.account

    # An unrequested association is never forced.
    refute Ecto.assoc_loaded?(contact.profile)
  end

  test "Repo.preload/2 accepts preloads/1 output for an envelope list field", %{contact_id: id} do
    selections = data_envelope(contact_selections())

    resolution = AbsintheProjector.call(query(selections), schema: Contact, envelope: :data)
    preloads = AbsintheProjector.preloads(resolution)

    # Only `data`'s selections drive the tree — `meta` never contributes.
    assert preloads == [:bank, installments: [payments: [:account]]]

    # The same tree loads the associations on records fetched as a list.
    [contact] = TestRepo.preload([TestRepo.get!(Contact, id)], preloads)

    assert %Bank{name: "Acme Bank"} = contact.bank
    assert [%Installment{payments: [%Payment{account: %Account{}}]}] = contact.installments
  end
end
