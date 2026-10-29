import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createAccounting } from "../../src/blocks/accounting/index.ts";
import { money } from "../../src/commerce/money.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "accounting"];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

describe.skipIf(!live)("accounting", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("posts balanced entries, reverses them and reports the books", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const clerk = await s.user("clerk");
      const outsider = await s.user("outsider");
      await s.install(MODULES);
      const org = await s.organization(owner, { member: clerk });
      const books = createAccounting({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const settings = await books
        .setup(org, { functionalCurrency: "EUR" })
        .orThrow();

      expect(settings).toMatchObject({
        functionalCurrency: "EUR",
        fiscalYearStartMonth: 1,
      });

      const accounts = await books.accounts(org).orThrow();
      const byCode = new Map(accounts.map((item) => [item.code, item]));

      expect(byCode.get("1200")?.roles).toEqual(["receivable"]);
      expect(byCode.get("3900")?.roles).toEqual(["retained_earnings"]);

      const journals = await books.journals(org).orThrow();
      const sales = journals.find((item) => item.code === "SAL")!;

      expect(journals.map((item) => item.code).toSorted()).toEqual([
        "BNK",
        "CSH",
        "GEN",
        "PUR",
        "SAL",
      ]);

      const periods = await books.openFiscalYear(org, 2026).orThrow();

      expect(periods).toHaveLength(12);
      expect(periods[0]?.startsOn.toString()).toBe("2026-01-01");
      expect(periods[11]?.endsOn.toString()).toBe("2026-12-31");

      const project = await books
        .saveDimension(org, "project", "Project")
        .orThrow();

      await books
        .saveDimensionValue(project.id, { code: "apollo", name: "Apollo" })
        .orThrow();

      const draft = await books
        .saveEntry({
          journalId: sales.id,
          entryDate: day("2026-01-15"),
          lines: [
            { accountCode: "1200", debit: money(12_100n, "EUR") },
            {
              accountCode: "4000",
              credit: 12_100n,
              dimensions: { project: "apollo" },
            },
          ],
          reference: "INV-42",
          sourceType: "invoice",
          sourceId: "inv-42",
        })
        .orThrow();

      expect(draft).toMatchObject({ status: "draft", total: 12_100n });
      expect(draft).not.toHaveProperty("number");

      const posted = await books.postEntry(draft.id).orThrow();

      expect(posted).toMatchObject({
        status: "posted",
        number: "SAL-2026-00001",
        fiscalYear: 2026,
      });
      expect(await books.postEntry(draft.id).then(hint)).toBe(
        "ACCOUNTING_ENTRY_POSTED",
      );
      expect(await books.deleteEntry(draft.id).then(hint)).toBe(
        "ACCOUNTING_ENTRY_POSTED",
      );

      const duplicate = await books.saveEntry({
        journalId: sales.id,
        entryDate: day("2026-01-16"),
        lines: [
          { accountCode: "1200", debit: 100n },
          { accountCode: "4000", credit: 100n },
        ],
        sourceType: "invoice",
        sourceId: "inv-42",
      });

      expect(hint(duplicate)).toBe("ACCOUNTING_ENTRY_DUPLICATE");

      const unbalanced = await books
        .saveEntry({
          journalId: sales.id,
          entryDate: day("2026-01-20"),
          lines: [
            { accountCode: "1200", debit: 500n },
            { accountCode: "4000", credit: 400n },
          ],
        })
        .orThrow();

      expect(await books.postEntry(unbalanced.id).then(hint)).toBe(
        "ACCOUNTING_ENTRY_UNBALANCED",
      );

      const badDimension = await books
        .saveEntry({
          journalId: sales.id,
          entryDate: day("2026-01-21"),
          lines: [
            { accountCode: "1200", debit: 100n },
            {
              accountCode: "4000",
              credit: 100n,
              dimensions: { project: "gemini" },
            },
          ],
        })
        .orThrow();

      expect(await books.postEntry(badDimension.id).then(hint)).toBe(
        "ACCOUNTING_DIMENSION_INVALID",
      );

      const outOfYear = await books
        .saveEntry({
          journalId: sales.id,
          entryDate: day("2027-02-01"),
          lines: [
            { accountCode: "1200", debit: 100n },
            { accountCode: "4000", credit: 100n },
          ],
        })
        .orThrow();

      expect(await books.postEntry(outOfYear.id).then(hint)).toBe(
        "ACCOUNTING_PERIOD_NOT_FOUND",
      );

      for (const id of [unbalanced.id, badDimension.id, outOfYear.id]) {
        await books.deleteEntry(id).orThrow();
      }

      const cost = await books
        .saveEntry({
          journalId: journals.find((item) => item.code === "PUR")!.id,
          entryDate: day("2026-02-10"),
          lines: [
            { accountCode: "6000", debit: 2000n },
            { accountCode: "2000", credit: 2000n },
          ],
        })
        .orThrow();

      await books.postEntry(cost.id).orThrow();

      const reversal = await books
        .reverseEntry(cost.id, day("2026-02-11"))
        .orThrow();

      expect(reversal).toMatchObject({
        status: "posted",
        reversesId: cost.id,
        number: "PUR-2026-00002",
      });
      expect((await books.getEntry(cost.id).orThrow())?.status).toBe(
        "reversed",
      );
      expect(await books.reverseEntry(cost.id).then(hint)).toBe(
        "ACCOUNTING_ENTRY_REVERSED",
      );

      const trial = await books
        .trialBalance(org, { until: day("2026-12-31") })
        .orThrow();

      expect(trial.totals.debit).toBe(trial.totals.credit);
      expect(trial.accounts.find((row) => row.code === "1200")?.closing).toBe(
        12_100n,
      );

      const pnl = await books
        .profitAndLoss(org, { since: day("2026-01-01") })
        .orThrow();

      expect(pnl).toMatchObject({
        totalIncome: 12_100n,
        totalExpenses: 0n,
        netIncome: 12_100n,
      });

      const filtered = await books
        .profitAndLoss(org, { dimensions: { project: "apollo" } })
        .orThrow();

      expect(filtered.totalIncome).toBe(12_100n);

      const sheet = await books
        .balanceSheet(org, { asOf: day("2026-12-31") })
        .orThrow();

      expect(sheet).toMatchObject({
        totalAssets: 12_100n,
        currentEarnings: 12_100n,
        balanced: true,
      });

      const ledger = await books
        .generalLedger(byCode.get("1200")!.id)
        .orThrow();

      expect(ledger.lines.map((line) => line.number)).toEqual([
        "SAL-2026-00001",
      ]);
      expect(ledger.closing).toBe(12_100n);

      await s.asRole(clerk);
      expect(await books.accounts(org).orThrow()).toEqual([]);
      expect(
        await books
          .saveAccount(org, { code: "9999", name: "Sneaky", type: "expense" })
          .then(hint),
      ).toBe("ACCOUNTING_ACCOUNT_FORBIDDEN");

      await s.asRole(outsider);
      expect((await books.trialBalance(org).orThrow()).accounts).toEqual([]);

      await s.as(owner);

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'accounting_%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set(["accounting_entry.posted", "accounting_entry.reversed"]),
      );
    } finally {
      await s.close();
    }
  });

  it("closes periods and the fiscal year into retained earnings", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install(MODULES);
      const org = await s.organization(owner);
      const books = createAccounting({ transport: sqlTransport(s.sql) });

      await s.as(owner);
      await books.setup(org).orThrow();

      const general = (await books.journals(org).orThrow()).find(
        (item) => item.code === "GEN",
      )!;

      const periods = await books.openFiscalYear(org, 2026).orThrow();
      const january = periods[0]!;

      const sale = await books
        .saveEntry({
          journalId: general.id,
          entryDate: day("2026-01-10"),
          lines: [
            { accountCode: "1000", debit: 50_000n },
            { accountCode: "4000", credit: 50_000n },
          ],
        })
        .orThrow();

      await books.postEntry(sale.id).orThrow();

      const late = await books
        .saveEntry({
          journalId: general.id,
          entryDate: day("2026-01-31"),
          lines: [
            { accountCode: "6000", debit: 10_000n },
            { accountCode: "1000", credit: 10_000n },
          ],
        })
        .orThrow();

      expect(await books.closeBlockers(january.id).orThrow()).toEqual([
        "draft_entries",
      ]);
      expect(await books.closePeriod(january.id).then(hint)).toBe(
        "ACCOUNTING_PERIOD_CLOSE_BLOCKED",
      );

      await books.postEntry(late.id).orThrow();
      expect(await books.closeBlockers(january.id).orThrow()).toEqual([]);

      const closed = await books.closePeriod(january.id).orThrow();

      expect(closed).toMatchObject({ status: "closed", closedBy: owner.id });

      const tooLate = await books
        .saveEntry({
          journalId: general.id,
          entryDate: day("2026-01-20"),
          lines: [
            { accountCode: "6000", debit: 100n },
            { accountCode: "1000", credit: 100n },
          ],
        })
        .orThrow();

      expect(await books.postEntry(tooLate.id).then(hint)).toBe(
        "ACCOUNTING_PERIOD_CLOSED",
      );

      const reopened = await books
        .reopenPeriod(january.id, "Late supplier invoice")
        .orThrow();

      expect(reopened.status).toBe("open");
      await books.postEntry(tooLate.id).orThrow();

      const year = await books.closeFiscalYear(org, 2026).orThrow();

      expect(year.closingEntryId).toBeDefined();
      expect(await books.closeFiscalYear(org, 2026).then(hint)).toBe(
        "FISCAL_YEAR_CLOSED",
      );

      const after = await books.periods(org, 2026).orThrow();

      expect(after.every((period) => period.status === "closed")).toBe(true);

      const sheet = await books
        .balanceSheet(org, { asOf: day("2026-12-31") })
        .orThrow();

      const retained = sheet.equity.find((line) => line.code === "3900");

      expect(retained?.amount).toBe(39_900n);
      expect(sheet).toMatchObject({ currentEarnings: 0n, balanced: true });

      const pnl = await books
        .profitAndLoss(org, {
          since: day("2026-01-01"),
          until: day("2026-12-31"),
        })
        .orThrow();

      expect(pnl.netIncome).toBe(39_900n);

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like any (array['accounting_period.%', 'fiscal_year.%'])",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "accounting_period.closed",
          "accounting_period.reopened",
          "fiscal_year.closed",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
