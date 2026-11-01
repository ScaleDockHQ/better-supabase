import { describe, expect, it } from "vitest";

import type {
  AuditAccountType,
  AuditFileAdapter,
  AuditImportPort,
  AuditLedgerSource,
} from "../../src/audit-files/index.ts";

import {
  exportAuditFile,
  importAuditFile,
  saftAdapter,
  xafAdapter,
} from "../../src/audit-files/index.ts";

const ok = <T>(data: T) => Promise.resolve({ ok: true as const, data });

interface Row {
  readonly hash: string;
  readonly data: Readonly<Record<string, unknown>>;
}

/**
 * A ledger that keeps import items by key and tells unchanged from new, like
 * `import_upsert_batch`.
 */
class FakeLedger {
  readonly tables = new Map<string, Map<string, Row>>();
  writes = 0;

  readonly port: AuditImportPort = {
    upsertBatch: ({ runId: _run, entity, items }) => {
      const table = this.tables.get(entity) ?? new Map<string, Row>();

      this.tables.set(entity, table);

      let inserted = 0;
      let updated = 0;
      let unchanged = 0;

      for (const item of items) {
        const hash = JSON.stringify(item.data);
        const seen = table.get(item.key);

        if (seen === undefined) {
          inserted += 1;
        } else if (seen.hash === hash) {
          unchanged += 1;
          continue;
        } else {
          updated += 1;
        }

        this.writes += 1;
        table.set(item.key, { hash, data: item.data });
      }

      return ok({ inserted, updated, unchanged, conflicted: 0, errors: [] });
    },
  };

  rows(entity: string): readonly [string, Row][] {
    return [...(this.tables.get(entity) ?? new Map<string, Row>())];
  }

  source(): AuditLedgerSource {
    const accounts = this.rows("accounting_account").map(([, row]) => ({
      id: String(row.data["code"]),
      code: String(row.data["code"]),
      name: String(row.data["name"]),
      // SAFETY: the importer only writes the five account types.
      type: row.data["type"] as AuditAccountType,
      active: true,
    }));

    return {
      accounts: () => ok(accounts),
      journalListing: () =>
        ok({
          journals: this.rows("accounting_journal").map(([code, journal]) => ({
            code,
            name: String(journal.data["name"]),
            type: String(journal.data["type"]),
            entries: this.rows("accounting_entry")
              .filter(([, entry]) => entry.data["journalCode"] === code)
              .map(([key, entry]) => ({
                id: key,
                entryDate: Temporal.PlainDate.from(
                  String(entry.data["entryDate"]),
                ),
                lines: entryLines(entry.data),
              })),
          })),
        }),
      openingBalances: () =>
        ok({
          posted: false,
          balances: this.rows("accounting_opening_balance").map(([, row]) => ({
            accountId: String(row.data["accountCode"]),
            amount: BigInt(String(row.data["amount"])),
          })),
        }),
    };
  }
}

function entryLines(data: Readonly<Record<string, unknown>>) {
  // SAFETY: the importer writes `lines` as an array of line records.
  const lines = data["lines"] as readonly Record<string, string>[];

  return lines.map((line) => ({
    accountCode: String(line["accountCode"]),
    debit: BigInt(line["debit"] ?? "0"),
    credit: BigInt(line["credit"] ?? "0"),
    taxAmount: BigInt(line["taxAmount"] ?? "0"),
  }));
}

/** Net balance per account and month, openings under `opening`. */
async function trialBalance(source: AuditLedgerSource) {
  const out: Record<string, bigint> = {};

  const add = (key: string, amount: bigint) => {
    out[key] = (out[key] ?? 0n) + amount;
  };

  const listing = await source.journalListing({
    organizationId: "org",
    since: Temporal.PlainDate.from("2026-01-01"),
    until: Temporal.PlainDate.from("2026-12-31"),
  });

  if (listing.ok) {
    for (const journal of listing.data.journals) {
      for (const entry of journal.entries) {
        for (const line of entry.lines) {
          add(
            `${line.accountCode} ${entry.entryDate.toString().slice(0, 7)}`,
            line.debit - line.credit,
          );
        }
      }
    }
  }

  const opening = await source.openingBalances({
    organizationId: "org",
    fiscalYear: 2026,
  });

  const accounts = await source.accounts({ organizationId: "org" });

  const codes = new Map(
    accounts.ok
      ? accounts.data.map((account) => [account.id, account.code])
      : [],
  );

  if (opening.ok) {
    for (const balance of opening.data.balances) {
      add(`${codes.get(balance.accountId)} opening`, balance.amount);
    }
  }

  return out;
}

function seeded(): AuditLedgerSource {
  const date = (value: string) => Temporal.PlainDate.from(value);

  return {
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
          code: "2000",
          name: "Equity",
          type: "equity" as const,
          active: true,
        },
        {
          id: "a3",
          code: "4000",
          name: "Sales",
          type: "income" as const,
          active: true,
        },
      ]),
    journalListing: () =>
      ok({
        journals: [
          {
            code: "BANK",
            name: "Bank",
            type: "bank",
            entries: [
              {
                id: "e1",
                number: "1",
                entryDate: date("2026-01-15"),
                memo: "January sale",
                lines: [
                  {
                    accountCode: "1000",
                    debit: 10_000n,
                    credit: 0n,
                    taxAmount: 0n,
                  },
                  {
                    accountCode: "4000",
                    debit: 0n,
                    credit: 10_000n,
                    taxAmount: 0n,
                  },
                ],
              },
              {
                id: "e2",
                number: "2",
                entryDate: date("2026-03-02"),
                lines: [
                  {
                    accountCode: "1000",
                    debit: 2500n,
                    credit: 0n,
                    taxAmount: 0n,
                  },
                  {
                    accountCode: "4000",
                    debit: 0n,
                    credit: 2500n,
                    taxAmount: 0n,
                  },
                ],
              },
            ],
          },
        ],
      }),
    openingBalances: () =>
      ok({
        posted: false,
        balances: [
          { accountId: "a1", amount: 7000n },
          { accountId: "a2", amount: -7000n },
        ],
      }),
  };
}

const company = { name: "Acme B.V." };

describe.each<[string, AuditFileAdapter]>([
  ["saft", saftAdapter({})],
  [
    "xaf",
    xafAdapter({
      accountType: ({ code }) =>
        code === "1000" ? "asset" : code === "2000" ? "equity" : "income",
    }),
  ],
])("%s round trip", (_name, adapter) => {
  it("rebuilds the trial balance in an empty ledger and then writes nothing", async () => {
    const source = seeded();

    const exported = await exportAuditFile(adapter, source, {
      organizationId: "org",
      company,
      currency: "EUR",
      selection: { year: 2026 },
    });

    const target = new FakeLedger();

    const first = await importAuditFile(adapter, exported.xml, {
      run: "run-1",
      imports: target.port,
    });

    expect(first.ok).toBe(true);
    expect(first.counts["accounting_entry"]?.inserted).toBe(2);
    expect(await trialBalance(target.source())).toEqual(
      await trialBalance(source),
    );

    const writes = target.writes;

    const second = await importAuditFile(adapter, exported.xml, {
      run: "run-2",
      imports: target.port,
    });

    expect(target.writes).toBe(writes);
    expect(second.counts["accounting_entry"]).toMatchObject({
      inserted: 0,
      updated: 0,
      unchanged: 2,
    });
    expect(second.counts["accounting_opening_balance"]).toMatchObject({
      inserted: 0,
      unchanged: 2,
    });
  });
});

describe("importAuditFile", () => {
  it("writes accounts before journals, openings and entries", async () => {
    const order: string[] = [];

    const port: AuditImportPort = {
      upsertBatch: ({ entity, items }) => {
        order.push(entity);

        return ok({
          inserted: items.length,
          updated: 0,
          unchanged: 0,
          conflicted: 0,
          errors: [],
        });
      },
    };

    const exported = await exportAuditFile(saftAdapter({}), seeded(), {
      organizationId: "org",
      company,
      currency: "EUR",
      selection: { year: 2026 },
    });

    await importAuditFile(saftAdapter({}), exported.xml, {
      run: "r",
      imports: port,
      batchSize: 1,
    });

    expect(order.indexOf("accounting_account")).toBeLessThan(
      order.indexOf("accounting_journal"),
    );
    expect(order.indexOf("accounting_journal")).toBeLessThan(
      order.indexOf("accounting_entry"),
    );
    expect(order.indexOf("accounting_opening_balance")).toBeLessThan(
      order.indexOf("accounting_entry"),
    );
  });

  it("reports parties it cannot store instead of dropping them silently", async () => {
    const exported = await exportAuditFile(saftAdapter({}), seeded(), {
      organizationId: "org",
      company,
      currency: "EUR",
      selection: { year: 2026 },
      parties: [{ kind: "customer", code: "C1", name: "Client" }],
    });

    const result = await importAuditFile(saftAdapter({}), exported.xml, {
      run: "r",
      imports: new FakeLedger().port,
    });

    expect(result.warnings).toContainEqual(
      expect.objectContaining({ code: "AUDIT_PARTY_NOT_IMPORTED", count: 1 }),
    );
  });

  it("flags a database refusal in the result", async () => {
    const port: AuditImportPort = {
      upsertBatch: () =>
        ok({
          inserted: 0,
          updated: 0,
          unchanged: 0,
          conflicted: 0,
          errors: [{ key: "1000", code: "bad", message: "no" }],
        }),
    };

    const exported = await exportAuditFile(saftAdapter({}), seeded(), {
      organizationId: "org",
      company,
      currency: "EUR",
      selection: { year: 2026 },
    });

    const result = await importAuditFile(saftAdapter({}), exported.xml, {
      run: "r",
      imports: port,
    });

    expect(result.ok).toBe(false);
    expect(result.errors[0]).toMatchObject({ key: "1000", code: "bad" });
  });
});
