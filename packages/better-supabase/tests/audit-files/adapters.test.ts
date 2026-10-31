import { describe, expect, it } from "vitest";

import type {
  AuditBooks,
  AuditFileAdapter,
  AuditRecord,
} from "../../src/audit-files/index.ts";

import {
  AuditFileError,
  defineAuditFileAdapter,
  saftAdapter,
  xafAdapter,
} from "../../src/audit-files/index.ts";

const books: AuditBooks = {
  header: {
    fiscalYear: 2026,
    startDate: "2026-01-01",
    endDate: "2026-12-31",
    currency: "EUR",
    company: { name: "Acme & Sons B.V.", registrationNumber: "12345678" },
  },
  accounts: [
    { code: "1000", name: "Bank", type: "asset" },
    { code: "2000", name: "Payables", type: "liability" },
    { code: "4000", name: "Sales", type: "income" },
  ],
  parties: [{ kind: "customer", code: "C1", name: "Client <1>" }],
  taxCodes: [
    { code: "H21", description: "High 21%", rateBps: 2100, type: "sales" },
  ],
  journals: [{ code: "BANK", name: "Bank", type: "bank" }],
  openingBalances: [
    { fiscalYear: 2026, accountCode: "1000", amount: 5000n },
    { fiscalYear: 2026, accountCode: "2000", amount: -5000n },
  ],
  entries: [
    {
      journalCode: "BANK",
      id: "1",
      date: "2026-02-03",
      description: "Invoice 1",
      lines: [
        { accountCode: "1000", debit: 12_100n, credit: 0n },
        { accountCode: "4000", debit: 0n, credit: 12_100n, taxAmount: 2100n },
      ],
    },
  ],
};

async function collect(
  adapter: AuditFileAdapter,
  xml: string,
  options?: Parameters<AuditFileAdapter["parse"]>[1],
): Promise<AuditRecord[]> {
  const records: AuditRecord[] = [];

  for await (const record of adapter.parse(xml, options)) {
    records.push(record);
  }

  return records;
}

const kinds = (records: readonly AuditRecord[], kind: AuditRecord["kind"]) =>
  records.filter((record) => record.kind === kind);

describe.each([
  ["saft", saftAdapter({})],
  [
    "xaf",
    xafAdapter({
      accountType: ({ code }) =>
        code === "1000" ? "asset" : code === "2000" ? "liability" : "income",
    }),
  ],
])("%s adapter", (_name, adapter) => {
  it("writes and reads the same books", async () => {
    const xml = [...adapter.export(books)].join("");
    const records = await collect(adapter, xml);

    expect(kinds(records, "entry")).toHaveLength(1);

    const entry = records.find((record) => record.kind === "entry");

    expect(entry?.kind === "entry" && entry.entry.lines).toEqual([
      expect.objectContaining({ accountCode: "1000", debit: 12_100n }),
      expect.objectContaining({ accountCode: "4000", credit: 12_100n }),
    ]);

    const header = records.find((record) => record.kind === "header");

    expect(header?.kind === "header" && header.header.company.name).toBe(
      "Acme & Sons B.V.",
    );

    const accounts = kinds(records, "account");

    expect(accounts).toHaveLength(3);

    const opening = records
      .flatMap((record) =>
        record.kind === "openingBalance" ? [record.balance] : [],
      )
      .reduce((sum, balance) => sum + balance.amount, 0n);

    expect(opening).toBe(0n);
    expect(
      records.filter(
        (record) =>
          record.kind === "warning" &&
          record.warning.code === "AUDIT_CONTROL_TOTAL_MISMATCH",
      ),
    ).toHaveLength(0);
  });

  it("reads a file delivered in small chunks", async () => {
    const xml = [...adapter.export(books)].join("");
    const chunks = xml.match(/[\s\S]{1,7}/g) ?? [];
    const records: AuditRecord[] = [];

    for await (const record of adapter.parse(chunks)) {
      records.push(record);
    }

    expect(kinds(records, "entry")).toHaveLength(1);
  });

  it("refuses a doctype with an internal subset", async () => {
    await expect(
      collect(
        adapter,
        '<?xml version="1.0"?><!DOCTYPE a [<!ENTITY x "y">]><a/>',
      ),
    ).rejects.toMatchObject({ code: "AUDIT_XML_UNSUPPORTED" });
  });

  it("refuses unknown entities and broken markup", async () => {
    await expect(collect(adapter, "<a>&bomb;</a>")).rejects.toBeInstanceOf(
      AuditFileError,
    );
    await expect(collect(adapter, "<a><b></a>")).rejects.toBeInstanceOf(
      AuditFileError,
    );
  });

  it("stops at the depth limit", async () => {
    await expect(
      collect(adapter, `${"<a>".repeat(20)}x${"</a>".repeat(20)}`, {
        maxDepth: 5,
      }),
    ).rejects.toMatchObject({ code: "AUDIT_XML_LIMIT" });
  });
});

describe("saft adapter", () => {
  it("reports an unmapped element as a warning", async () => {
    const xml = [...saftAdapter({}).export(books)]
      .join("")
      .replace("<Header>", "<Header><Mystery><Inner>1</Inner></Mystery>");

    const records = await collect(saftAdapter({}), xml);

    const warnings = records.flatMap((record) =>
      record.kind === "warning" ? [record.warning] : [],
    );

    expect(warnings).toContainEqual(
      expect.objectContaining({ code: "AUDIT_ELEMENT_UNMAPPED" }),
    );
  });

  it("warns when the control totals do not match", async () => {
    const xml = [...saftAdapter({}).export(books)]
      .join("")
      .replace(
        /<TotalDebit>[^<]*<\/TotalDebit>/,
        "<TotalDebit>1.00</TotalDebit>",
      );

    const records = await collect(saftAdapter({}), xml);

    expect(
      records.some(
        (record) =>
          record.kind === "warning" &&
          record.warning.code === "AUDIT_CONTROL_TOTAL_MISMATCH",
      ),
    ).toBe(true);
  });
});

describe("xaf adapter", () => {
  it("warns when it has to assume an account type", async () => {
    const xml = [...xafAdapter({}).export(books)].join("");
    const records = await collect(xafAdapter({}), xml);

    expect(
      records.some(
        (record) =>
          record.kind === "warning" &&
          record.warning.code === "AUDIT_ACCOUNT_TYPE_ASSUMED",
      ),
    ).toBe(true);
  });
});

describe("defineAuditFileAdapter", () => {
  it("refuses an unknown apiVersion", () => {
    const adapter: unknown = { ...saftAdapter({}), apiVersion: 2 };

    expect(() =>
      // SAFETY: the test passes a version the type forbids, to check the guard.
      defineAuditFileAdapter(adapter as AuditFileAdapter),
    ).toThrow(/apiVersion 2/);
  });
});
