import { describe, expect, it } from "vitest";

import type {
  AuditImportItem,
  AuditImportPort,
  AuditLedgerSource,
} from "../../src/audit-files/index.ts";

import {
  xafAdapter,
  booksFromLedger,
  exportAuditFile,
  importAuditFile,
  saftAdapter,
} from "../../src/audit-files/index.ts";

const ok = <T>(data: T) => Promise.resolve({ ok: true as const, data });

const fail = (message: string) =>
  Promise.resolve({ ok: false as const, error: { message } });

const company = { name: "Acme" };

const source = (
  overrides: Partial<AuditLedgerSource> = {},
): AuditLedgerSource => ({
  accounts: () =>
    ok([
      {
        id: "a1",
        code: "1000",
        name: "Bank",
        type: "asset" as const,
        active: true,
      },
      {
        id: "a2",
        code: "4000",
        name: "Sales",
        type: "income" as const,
        active: true,
      },
      {
        id: "a3",
        code: "9999",
        name: "Old",
        type: "expense" as const,
        active: false,
      },
    ]),
  journalListing: () =>
    ok({
      journals: [
        {
          code: "X",
          name: "Odd",
          type: "mystery",
          entries: [
            {
              id: "uuid-1",
              entryDate: Temporal.PlainDate.from("2026-02-01"),
              reference: "R1",
              memo: "m",
              lines: [
                {
                  accountCode: "1000",
                  debit: 100n,
                  credit: 0n,
                  taxAmount: 21n,
                  partyId: "P1",
                  description: "d",
                },
                { accountCode: "4000", debit: 0n, credit: 100n, taxAmount: 0n },
              ],
            },
          ],
        },
      ],
    }),
  openingBalances: () =>
    ok({
      posted: false,
      balances: [{ accountId: "a1", partyId: "P1", amount: 5n }],
    }),
  ...overrides,
});

const options = {
  organizationId: "org",
  company,
  currency: "EUR",
  selection: { year: 2026 },
};

describe("booksFromLedger", () => {
  it("maps the ledger reads to books", async () => {
    const { books } = await booksFromLedger(source(), {
      ...options,
      software: { name: "app" },
      parties: [{ kind: "customer", code: "P1", name: "P" }],
      taxCodes: [{ code: "H", description: "High", type: "sales" }],
    });

    expect(books.accounts.map((account) => account.code)).toEqual([
      "1000",
      "4000",
    ]);
    expect(books.journals[0]?.type).toBe("general");
    expect(books.entries[0]).toMatchObject({
      id: "uuid-1",
      reference: "R1",
      description: "m",
    });
    expect(books.entries[0]?.lines[0]).toMatchObject({
      partyCode: "P1",
      taxAmount: 21n,
    });
    expect(books.openingBalances[0]).toMatchObject({
      accountCode: "1000",
      partyCode: "P1",
    });
    expect(books.header.software).toEqual({ name: "app" });
  });

  it("uses explicit dates for a fiscal year that is not the calendar year", async () => {
    const { books } = await booksFromLedger(source(), {
      ...options,
      selection: {
        year: 2026,
        from: Temporal.PlainDate.from("2026-04-01"),
        to: Temporal.PlainDate.from("2027-03-31"),
      },
    });

    expect(books.header).toMatchObject({
      startDate: "2026-04-01",
      endDate: "2027-03-31",
    });
  });

  it("leaves posted opening balances to the journals and says so", async () => {
    const { books, warnings } = await booksFromLedger(
      source({
        openingBalances: () =>
          ok({ posted: true, balances: [{ accountId: "a1", amount: 5n }] }),
      }),
      options,
    );

    expect(books.openingBalances).toEqual([]);
    expect(warnings).toContainEqual(
      expect.objectContaining({ code: "AUDIT_EXPORT_OMITTED" }),
    );
  });

  it("refuses an opening balance on an unknown account", async () => {
    await expect(
      booksFromLedger(
        source({
          openingBalances: () =>
            ok({ posted: false, balances: [{ accountId: "zz", amount: 1n }] }),
        }),
        options,
      ),
    ).rejects.toMatchObject({ code: "AUDIT_FILE_INVALID" });
  });

  it("names the failed read", async () => {
    await expect(
      booksFromLedger(source({ accounts: () => fail("denied") }), options),
    ).rejects.toThrow(/reading the accounts failed: denied/);
  });
});

describe("exportAuditFile", () => {
  it("warns when party openings are written per account", async () => {
    const result = await exportAuditFile(saftAdapter({}), source(), options);

    expect(result.warnings).toContainEqual(
      expect.objectContaining({ code: "AUDIT_OPENING_PARTY_MERGED" }),
    );
  });
});

const recording = () => {
  const calls: { entity: string; items: readonly AuditImportItem[] }[] = [];

  const port: AuditImportPort = {
    upsertBatch: (_run, entity, items) => {
      calls.push({ entity, items });

      return ok({
        inserted: items.length,
        updated: 0,
        unchanged: 0,
        conflicted: 0,
        errors: [],
        warnings: [{ key: null, code: "W", message: "from the database" }],
      });
    },
  };

  return { calls, port };
};

describe("importAuditFile", () => {
  it("reports links it cannot store and merged openings", async () => {
    const { xml } = await exportAuditFile(saftAdapter({}), source(), {
      ...options,
      taxCodes: [
        { code: "H", description: "High", rateBps: 2100, type: "sales" },
      ],
      parties: [
        { kind: "customer", code: "P1", name: "P", accountCode: "1000" },
      ],
    });

    const { calls, port } = recording();
    const progress: string[] = [];

    const result = await importAuditFile(saftAdapter({}), xml, {
      run: "r",
      imports: port,
      entities: { party: "contact", account: "chart" },
      taxRateValidFrom: "2026-01-01",
      onBatch: ({ entity }) => progress.push(entity),
    });

    const codes = result.warnings.map((warning) => warning.code);

    expect(codes).toContain("AUDIT_PARTY_LINK_DROPPED");
    expect(calls.map((call) => call.entity)).toEqual(
      expect.arrayContaining(["chart", "contact", "tax_code"]),
    );
    expect(progress).toHaveLength(calls.length);
    expect(result.warnings).toContainEqual(
      expect.objectContaining({ code: "AUDIT_DATABASE_WARNING" }),
    );
  });

  it("adds up opening balances kept per party and says so", async () => {
    const xaf = xafAdapter({ accountType: () => "asset" });
    const { xml } = await exportAuditFile(xaf, source(), options);
    const { calls, port } = recording();
    const result = await importAuditFile(xaf, xml, { run: "r", imports: port });

    const opening = calls.find(
      (call) => call.entity === "accounting_opening_balance",
    );

    expect(opening?.items[0]?.data["amount"]).toBe("5");
    expect(result.warnings.map((warning) => warning.code)).toContain(
      "AUDIT_OPENING_PARTY_MERGED",
    );
  });

  it("reports a tax link that is not stored", async () => {
    const { xml } = await exportAuditFile(saftAdapter({}), source(), options);
    const books = await booksFromLedger(source(), options);

    const withTax = [
      ...saftAdapter({}).export({
        ...books.books,
        entries: books.books.entries.map((entry) => ({
          ...entry,
          lines: entry.lines.map((line) => ({ ...line, taxCode: "H" })),
        })),
      }),
    ].join("");

    const result = await importAuditFile(saftAdapter({}), withTax, {
      run: "r",
      imports: recording().port,
    });

    expect(xml).not.toBe("");
    expect(result.warnings.map((warning) => warning.code)).toContain(
      "AUDIT_TAX_CODE_NOT_IMPORTED",
    );
  });

  it("stops and reports when the port fails", async () => {
    const { xml } = await exportAuditFile(saftAdapter({}), source(), options);

    const result = await importAuditFile(saftAdapter({}), xml, {
      run: "r",
      imports: { upsertBatch: () => fail("run is closed") },
    });

    expect(result.ok).toBe(false);
    expect(result.errors[0]).toMatchObject({
      code: "AUDIT_IMPORT_PORT_FAILED",
      message: expect.stringContaining("run is closed"),
    });
  });

  it("batches by size", async () => {
    const { xml } = await exportAuditFile(saftAdapter({}), source(), options);
    const { calls, port } = recording();

    await importAuditFile(saftAdapter({}), xml, {
      run: "r",
      imports: port,
      batchSize: 1,
    });

    expect(
      calls.filter((call) => call.entity === "accounting_account"),
    ).toHaveLength(2);
  });

  it("lets a parse error through", async () => {
    await expect(
      importAuditFile(saftAdapter({}), "<a><b></a>", {
        run: "r",
        imports: recording().port,
      }),
    ).rejects.toMatchObject({ name: "AuditFileError" });
  });
});
