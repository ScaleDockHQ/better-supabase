import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { AuditFileAdapter } from "../../src/audit-files/index.ts";
import type { TrialBalance } from "../../src/blocks/accounting/index.ts";

import {
  exportAuditFile,
  importAuditFile,
  saftAdapter,
  xafAdapter,
} from "../../src/audit-files/index.ts";
import { createAccounting } from "../../src/blocks/accounting/index.ts";
import { createImports } from "../../src/blocks/imports/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

// ERP import acceptance 6 (ADR 0141, 0144): after a ledger import the trial
// balance equals the source's, an SAF-T or XAF file written from the source
// ledger rebuilds it in an empty organization on the real stack, a second
// import of the same file writes nothing, and the open items imported next to
// it add up to the receivables account.

const live = await reachable();
const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "subjects",
  "relations",
  "contacts",
  "ledger",
  "tax",
  "accounting",
  "invoices",
  "imports",
];

const OPEN_ITEMS = [
  {
    key: "open-9001",
    data: {
      number: "INV-9001",
      issuedOn: "2026-01-15",
      dueOn: "2026-02-14",
      currency: "EUR",
      balance: 12_100,
    },
  },
  {
    key: "open-9002",
    data: {
      number: "INV-9002",
      issuedOn: "2026-03-02",
      dueOn: "2026-04-01",
      currency: "EUR",
      balance: 24_200,
    },
  },
] as const;

/**
 * Per account code: opening, debit, credit and closing, empty accounts left
 * out.
 */
function figures(balance: TrialBalance): Record<string, string> {
  return Object.fromEntries(
    balance.accounts
      .filter(
        (row) =>
          row.opening !== 0n ||
          row.debit !== 0n ||
          row.credit !== 0n ||
          row.closing !== 0n,
      )
      .map((row) => [
        row.code,
        `${row.opening}/${row.debit}/${row.credit}/${row.closing}`,
      ]),
  );
}

describe.skipIf(!live)("ERP import: ledger and audit file round trip", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  let s: BlockSession;
  let owner: Awaited<ReturnType<BlockSession["user"]>>;
  let source: string;

  const books = () => createAccounting({ transport: sqlTransport(s.sql) });
  const imports = () => createImports({ transport: sqlTransport(s.sql) });

  const trial = async (organization: string): Promise<TrialBalance> => {
    await s.as(owner);

    return books()
      .trialBalance(organization, {
        since: day("2026-01-01"),
        until: day("2026-12-31"),
      })
      .orThrow();
  };

  /** Runs `work` inside one import run of `organization`. */
  const inRun = async <T>(
    organization: string,
    name: string,
    work: (run: string) => Promise<T>,
  ): Promise<T> => {
    await s.as(owner);

    const { id } = await imports().runs.start(organization, name).orThrow();

    await s.service();
    await imports().markRunning(id).orThrow();

    const result = await work(id);

    await imports().finish(id).orThrow();
    await s.as(owner);

    return result;
  };

  beforeAll(async () => {
    s = await BlockSession.open(pool);
    owner = await s.user("owner");
    await s.install(MODULES, {});
    source = await s.organization(owner);
    await s.as(owner);

    const ledger = books();

    await ledger.setup(source, { functionalCurrency: "EUR" }).orThrow();
    await ledger.openFiscalYear(source, 2026).orThrow();
    await ledger
      .saveOpeningBalances(source, 2026, [
        { accountCode: "1000", amount: 7000n },
        { accountCode: "3000", amount: -7000n },
      ])
      .orThrow();
    await ledger.postOpeningBalances(source, 2026).orThrow();

    const journals = await ledger.journals(source).orThrow();
    const sales = journals.find((item) => item.code === "SAL")!;
    const general = journals.find((item) => item.code === "GEN")!;

    const entries = [
      { journal: sales.id, date: "2026-01-15", amount: 12_100n, memo: "A" },
      { journal: sales.id, date: "2026-03-02", amount: 24_200n, memo: "B" },
      { journal: general.id, date: "2026-03-20", amount: 500n, memo: "C" },
    ];

    for (const entry of entries) {
      const draft = await ledger
        .saveEntry({
          journalId: entry.journal,
          entryDate: day(entry.date),
          memo: entry.memo,
          lines: [
            {
              accountCode: entry.memo === "C" ? "1000" : "1200",
              debit: entry.amount,
            },
            { accountCode: "4000", credit: entry.amount },
          ],
        })
        .orThrow();

      await ledger.postEntry(draft.id).orThrow();
    }
  });

  afterAll(async () => {
    await s.close();
    await pool.end();
  });

  it.each<[string, AuditFileAdapter]>([
    ["SAF-T", saftAdapter({})],
    [
      "XAF",
      xafAdapter({
        accountType: ({ code }) =>
          code.startsWith("1")
            ? "asset"
            : code.startsWith("3")
              ? "equity"
              : "income",
      }),
    ],
  ])(
    "rebuilds the trial balance from a %s file in an empty organization and then writes nothing",
    async (name, adapter) => {
      await s.as(owner);

      const exported = await exportAuditFile(adapter, books(), {
        organizationId: source,
        company: { name: "Acme B.V." },
        currency: "EUR",
        selection: { year: 2026 },
      });

      const target = await s.organization(owner);

      await s.as(owner);
      await books().setup(target, { functionalCurrency: "EUR" }).orThrow();
      await books().openFiscalYear(target, 2026).orThrow();

      await s.service();

      const first = await inRun(target, `audit-${name}`, async (run) => {
        await s.service();

        const result = await importAuditFile(adapter, exported.xml, {
          run,
          imports: imports(),
        });

        await imports().upsertBatch(run, "open_item", OPEN_ITEMS).orThrow();

        return result;
      });

      expect(first.ok).toBe(true);
      expect(first.counts["accounting_entry"]?.inserted).toBeGreaterThan(2);

      // The opening balances travel as the opening entry of the journal listing.
      const expected = figures(await trial(source));
      const actual = figures(await trial(target));

      expect(actual).toEqual(expected);
      expect(expected["1200"]).toBe("0/36300/0/36300");

      await s.service();

      const [items] = await s.rows<{ total: string }>(
        `select coalesce(sum((i ->> 'balance')::bigint), 0)::text as total
         from jsonb_array_elements(better_supabase.open_items_for_party($1, null, null, null)) i`,
        [target],
      );

      expect(items?.total).toBe("36300");

      // The same file again: nothing is inserted, updated or conflicted.
      const second = await inRun(target, `audit-${name}`, async (run) => {
        await s.service();

        const result = await importAuditFile(adapter, exported.xml, {
          run,
          imports: imports(),
        });

        const again = await imports()
          .upsertBatch(run, "open_item", OPEN_ITEMS)
          .orThrow();

        return { result, again };
      });

      expect(second.result.counts["accounting_entry"]).toMatchObject({
        inserted: 0,
        updated: 0,
        unchanged: first.counts["accounting_entry"]?.inserted,
        conflicted: 0,
      });
      expect(second.again).toMatchObject({
        inserted: 0,
        updated: 0,
        unchanged: 2,
      });
      expect(figures(await trial(target))).toEqual(expected);
    },
    60_000,
  );
});
