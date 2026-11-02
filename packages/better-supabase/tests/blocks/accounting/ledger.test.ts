import { describe, expect, it } from "vitest";

import { createAccounting } from "../../../src/blocks/accounting/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";

const PERIOD = {
  id: "p1",
  organizationId: "org-1",
  fiscalYear: 2026,
  number: 1,
  startsOn: "2026-01-01",
  endsOn: "2026-01-31",
  status: "locked",
  closedAt: AT,
  closedBy: "u1",
  lockedAt: AT,
  lockedBy: "u2",
};

const OPENING = {
  id: "o1",
  organizationId: "org-1",
  fiscalYear: 2026,
  accountId: "a1",
  partyId: "c1",
  amount: "12100",
  source: "imported",
};

describe("accounting ledger client", () => {
  it("locks and unlocks a period", async () => {
    const t = fieldsTransport({
      lock_accounting_period: () => PERIOD,
      unlock_accounting_period: () => ({ ...PERIOD, status: "closed" }),
    });

    const books = createAccounting({ transport: t });
    const locked = await books.lockPeriod("p1").orThrow();

    const unlocked = await books
      .unlockPeriod({ periodId: "p1", reason: "late invoice" })
      .orThrow();

    expect(locked.status).toBe("locked");
    expect(unlocked.status).toBe("closed");
    expect(t.calls).toEqual([
      ["lock_accounting_period", { period_id: "p1" }],
      ["unlock_accounting_period", { period_id: "p1", reason: "late invoice" }],
    ]);
  });

  it("saves, lists and posts opening balances", async () => {
    const t = fieldsTransport({
      save_accounting_opening_balances: () => ({ balances: [OPENING] }),
      list_accounting_opening_balances: () => ({
        organizationId: "org-1",
        fiscalYear: 2026,
        posted: false,
        balances: [OPENING, { ...OPENING, id: "o2", amount: "-12100" }],
        total: "0",
      }),
      post_accounting_opening_balances: () => ({
        id: "e1",
        organizationId: "org-1",
        journalId: "j1",
        fiscalYear: 2026,
        entryDate: "2026-01-01",
        status: "posted",
        total: "12100",
        createdAt: AT,
        updatedAt: AT,
      }),
    });

    const books = createAccounting({ transport: t });

    const saved = await books
      .saveOpeningBalances({
        organizationId: "org-1",
        fiscalYear: 2026,
        balances: [{ accountCode: "1300", partyId: "c1", amount: 12_100n }],
      })
      .orThrow();

    const listed = await books
      .openingBalances({ organizationId: "org-1", fiscalYear: 2026 })
      .orThrow();

    const entry = await books
      .postOpeningBalances({ organizationId: "org-1", fiscalYear: 2026 })
      .orThrow();

    expect(saved[0]?.amount).toBe(12_100n);
    expect(listed.total).toBe(0n);
    expect(listed.balances).toHaveLength(2);
    expect(entry.status).toBe("posted");
    expect(t.calls[0]).toEqual([
      "save_accounting_opening_balances",
      {
        tenant: "org-1",
        fiscal_year: 2026,
        balances: [{ amount: "12100", accountCode: "1300", partyId: "c1" }],
      },
    ]);
    expect(t.calls[2]).toEqual([
      "post_accounting_opening_balances",
      { tenant: "org-1", fiscal_year: 2026, journal_id: null },
    ]);
  });

  it("reads the column balance and the journal listing", async () => {
    const t = fieldsTransport({
      accounting_column_balance: () => ({
        accounts: [
          {
            accountId: "a1",
            code: "1300",
            name: "Receivable",
            type: "asset",
            level: 1,
            openingDebit: "100",
            openingCredit: "0",
            debit: "50",
            credit: "20",
            closingDebit: "130",
            closingCredit: "0",
          },
        ],
        totals: {
          openingDebit: "100",
          openingCredit: "0",
          debit: "50",
          credit: "20",
          closingDebit: "130",
          closingCredit: "0",
        },
      }),
      accounting_journal_listing: () => ({
        journals: [
          {
            journalId: "j1",
            code: "SAL",
            name: "Sales",
            type: "sales",
            totalDebit: "50",
            totalCredit: "50",
            entries: [
              {
                id: "e1",
                number: "SAL-1",
                entryDate: "2026-01-02",
                status: "posted",
                lines: [
                  {
                    accountId: "a1",
                    accountCode: "1300",
                    accountName: "Receivable",
                    debit: "50",
                    credit: "0",
                    taxAmount: "9",
                  },
                ],
              },
            ],
          },
        ],
      }),
    });

    const books = createAccounting({ transport: t });

    const columns = await books
      .columnBalance({ organizationId: "org-1", rollup: true })
      .orThrow();

    const listing = await books
      .journalListing({ organizationId: "org-1" })
      .orThrow();

    expect(columns.accounts[0]?.closingDebit).toBe(130n);
    expect(columns.totals.debit).toBe(50n);
    expect(listing.journals[0]?.entries[0]?.lines[0]?.taxAmount).toBe(9n);
    expect(listing.journals[0]?.entries[0]?.entryDate.toString()).toBe(
      "2026-01-02",
    );
    expect(t.calls[0]?.[1]).toMatchObject({ rollup: true, dimensions: {} });
  });

  it("sends the report options and decodes optional fields", async () => {
    const t = fieldsTransport({
      accounting_column_balance: () => ({
        accounts: [
          {
            accountId: "a2",
            code: "1310",
            name: "Child",
            type: "asset",
            parentId: "a1",
            level: 2,
            openingDebit: "0",
            openingCredit: "5",
            debit: "0",
            credit: "0",
            closingDebit: "0",
            closingCredit: "5",
          },
        ],
        totals: {
          openingDebit: "0",
          openingCredit: "5",
          debit: "0",
          credit: "0",
          closingDebit: "0",
          closingCredit: "5",
        },
      }),
      accounting_journal_listing: () => ({
        journals: [
          {
            journalId: "j1",
            code: "GEN",
            name: "General",
            type: "general",
            totalDebit: "1",
            totalCredit: "1",
            entries: [
              {
                id: "e1",
                entryDate: "2026-01-02",
                status: "reversed",
                reference: "R1",
                memo: "m",
                lines: [
                  {
                    accountId: "a1",
                    accountCode: "1300",
                    accountName: "Receivable",
                    debit: "1",
                    credit: "0",
                    taxAmount: "0",
                    partyId: "c1",
                    description: "d",
                  },
                ],
              },
            ],
          },
        ],
      }),
      save_accounting_opening_balances: () => ({}),
      post_accounting_opening_balances: () => ({
        id: "e1",
        organizationId: "org-1",
        journalId: "j9",
        fiscalYear: 2026,
        entryDate: "2026-01-01",
        status: "posted",
        total: "0",
        createdAt: AT,
        updatedAt: AT,
      }),
    });

    const books = createAccounting({ transport: t });

    const columns = await books
      .columnBalance({
        organizationId: "org-1",
        since: Temporal.PlainDate.from("2026-01-01"),
        until: Temporal.PlainDate.from("2026-12-31"),
        dimensions: { project: "x" },
      })
      .orThrow();

    const listing = await books
      .journalListing({
        organizationId: "org-1",
        since: Temporal.PlainDate.from("2026-01-01"),
        until: Temporal.PlainDate.from("2026-12-31"),
        journalId: "j1",
      })
      .orThrow();

    const saved = await books
      .saveOpeningBalances({
        organizationId: "org-1",
        fiscalYear: 2026,
        balances: [{ accountId: "a1", amount: -5n }],
      })
      .orThrow();

    await books
      .postOpeningBalances({
        organizationId: "org-1",
        fiscalYear: 2026,
        journalId: "j9",
      })
      .orThrow();

    const line = listing.journals[0]?.entries[0]?.lines[0];

    expect(columns.accounts[0]?.parentId).toBe("a1");
    expect(columns.accounts[0]?.openingCredit).toBe(5n);
    expect(line?.partyId).toBe("c1");
    expect(line?.description).toBe("d");
    expect(listing.journals[0]?.entries[0]).toMatchObject({
      status: "reversed",
      reference: "R1",
      memo: "m",
    });
    expect(saved).toEqual([]);
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      since: "2026-01-01",
      until: "2026-12-31",
      dimensions: { project: "x" },
      rollup: false,
    });
    expect(t.calls[1]?.[1]).toMatchObject({ journal_id: "j1" });
    expect(t.calls[2]?.[1]).toMatchObject({
      balances: [{ amount: "-5", accountId: "a1" }],
    });
    expect(t.calls[3]?.[1]).toMatchObject({ journal_id: "j9" });
  });

  it("reads a period trial balance", async () => {
    const t = fieldsTransport({
      accounting_period_trial_balance: () => ({
        accounts: [],
        totals: { opening: "0", debit: "0", credit: "0", closing: "0" },
      }),
    });

    const result = await createAccounting({ transport: t }).periodTrialBalance({
      periodId: "p1",
    });

    expect(t.calls[0]).toEqual([
      "accounting_period_trial_balance",
      { period_id: "p1", dimensions: {} },
    ]);
    expect(result.ok).toBe(true);
  });
});
