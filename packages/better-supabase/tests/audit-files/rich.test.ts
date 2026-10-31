import { describe, expect, it } from "vitest";

import type {
  AuditBooks,
  AuditFileAdapter,
  AuditRecord,
} from "../../src/audit-files/index.ts";

import { saftAdapter, xafAdapter } from "../../src/audit-files/index.ts";

const books: AuditBooks = {
  header: {
    fiscalYear: 2026,
    startDate: "2026-04-01",
    endDate: "2027-03-31",
    currency: "USD",
    company: {
      name: "Acme",
      registrationNumber: "98765",
      taxId: "NL123456789B01",
      country: "NL",
    },
    software: { name: "better-supabase", version: "1.2" },
  },
  accounts: [
    { code: "1000", name: "Bank", type: "asset" },
    { code: "1300", name: "Receivable", type: "asset" },
    { code: "1600", name: "Payable", type: "liability" },
    { code: "3000", name: "Capital", type: "equity" },
    { code: "4000", name: "Sales", type: "income" },
    { code: "7000", name: "Costs", type: "expense" },
  ],
  parties: [
    {
      kind: "customer",
      code: "C1",
      name: "Client",
      taxId: "BE0123",
      country: "BE",
      accountCode: "1300",
    },
    { kind: "supplier", code: "S1", name: "Vendor", accountCode: "1600" },
  ],
  taxCodes: [
    { code: "H21", description: "High", rateBps: 2100, type: "sales" },
    { code: "I9", description: "Input", rateBps: 900, type: "purchase" },
    { code: "Z", description: "Zero", type: "sales" },
  ],
  journals: [
    { code: "VK", name: "Sales", type: "sales" },
    { code: "IK", name: "Purchases", type: "purchase" },
    { code: "BK", name: "Bank", type: "bank" },
    { code: "KS", name: "Cash", type: "cash" },
    { code: "MEM", name: "General", type: "general" },
  ],
  openingBalances: [
    { fiscalYear: 2026, accountCode: "1300", partyCode: "C1", amount: 600n },
    { fiscalYear: 2026, accountCode: "1300", partyCode: "C2", amount: 400n },
    { fiscalYear: 2026, accountCode: "1600", partyCode: "S1", amount: -1000n },
    { fiscalYear: 2026, accountCode: "1000", amount: 0n },
  ],
  entries: [
    {
      journalCode: "VK",
      id: "10",
      date: "2026-05-01",
      description: "Sale",
      reference: "INV-10",
      lines: [
        {
          accountCode: "1300",
          debit: 12_100n,
          credit: 0n,
          partyCode: "C1",
          description: "Receivable",
        },
        {
          accountCode: "4000",
          debit: 0n,
          credit: 10_000n,
          taxCode: "H21",
          taxAmount: 2100n,
        },
        { accountCode: "1600", debit: 0n, credit: 2100n },
      ],
    },
    {
      journalCode: "IK",
      id: "11",
      date: "2026-06-01",
      lines: [
        { accountCode: "7000", debit: 100n, credit: 0n },
        { accountCode: "1600", debit: 0n, credit: 100n, partyCode: "S1" },
      ],
    },
  ],
};

async function collect(adapter: AuditFileAdapter, xml: string) {
  const records: AuditRecord[] = [];

  for await (const record of adapter.parse(xml)) {
    records.push(record);
  }

  return records;
}

describe.each<[string, AuditFileAdapter]>([
  ["saft", saftAdapter({})],
  [
    "xaf",
    xafAdapter({
      accountType: ({ code }) =>
        books.accounts.find((account) => account.code === code)?.type ??
        "asset",
    }),
  ],
])("%s with a rich ledger", (_name, adapter) => {
  it("keeps the header, parties, tax codes, journals and entries", async () => {
    const records = await collect(adapter, [...adapter.export(books)].join(""));

    const header = records.find((record) => record.kind === "header");

    expect(header?.kind === "header" && header.header).toMatchObject({
      fiscalYear: 2026,
      startDate: "2026-04-01",
      endDate: "2027-03-31",
    });

    expect(records.filter((record) => record.kind === "party")).toHaveLength(2);
    expect(records.filter((record) => record.kind === "taxCode")).toHaveLength(
      3,
    );

    const journals = records.flatMap((record) =>
      record.kind === "journal" ? [record.journal] : [],
    );

    expect(journals.map((journal) => journal.type)).toEqual([
      "sales",
      "purchase",
      "bank",
      "cash",
      "general",
    ]);

    const entries = records.flatMap((record) =>
      record.kind === "entry" ? [record.entry] : [],
    );

    expect(entries).toHaveLength(2);
    expect(entries[0]?.reference).toBe("INV-10");
    expect(entries[0]?.lines[1]).toMatchObject({
      accountCode: "4000",
      credit: 10_000n,
    });

    const accounts = records.flatMap((record) =>
      record.kind === "account" ? [record.account.type] : [],
    );

    expect(accounts).toHaveLength(6);
  });

  it("keeps per-party opening balances that add up per account", async () => {
    const records = await collect(adapter, [...adapter.export(books)].join(""));

    const total = records
      .flatMap((record) =>
        record.kind === "openingBalance" ? [record.balance.amount] : [],
      )
      .reduce((sum, amount) => sum + amount, 0n);

    expect(total).toBe(0n);
  });
});
