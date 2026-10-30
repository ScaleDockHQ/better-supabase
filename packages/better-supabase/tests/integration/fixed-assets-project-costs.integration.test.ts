import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createAccounting } from "../../src/blocks/accounting/index.ts";
import { createAssets } from "../../src/blocks/assets/index.ts";
import { createBillableTime } from "../../src/blocks/billable-time/index.ts";
import { createTasks } from "../../src/blocks/tasks/index.ts";
import {
  createTimeTracking,
  sqlTransport,
} from "../../src/blocks/time-tracking/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");
const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);
const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "notifications",
  "subjects",
  "rank",
  "relations",
  "pipelines",
  "approvals",
  "tasks",
  "assets",
  "accounting",
  "time-tracking",
  "invoices",
  "billable-time",
];

// The shared stack's work_items table references `work_projects`, the name
// the Next.js example gives it.
const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["tasks"], {}),
  modules: { tasks: { tables: { projects: "work_projects" } } },
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("fixed assets and project costing", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("depreciates an asset monthly, posts it, and books the gain on disposal", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner, { member: ada });
      const transport = sqlTransport(s.sql);
      const assets = createAssets({ transport, tenant });
      const books = createAccounting({ transport });

      await s.as(owner);
      await books.setup(tenant, { functionalCurrency: "EUR" }).orThrow();
      await books.openFiscalYear(tenant, 2026).orThrow();

      const { id } = await assets
        .createAsset({ kind: "van", name: "Van" })
        .orThrow();

      expect(
        hint(
          await assets.updateAsset(id, {
            acquisitionCost: eur(12_000n),
            depreciationMethod: "straight_line",
          }),
        ),
      ).toBe("ASSETS_DEPRECIATION_INVALID");

      const booked = await assets
        .updateAsset(id, {
          acquisitionCost: eur(12_000n),
          acquiredOn: day("2026-01-15"),
          usefulLifeMonths: 12,
          depreciationMethod: "straight_line",
        })
        .orThrow();

      expect(booked).toMatchObject({
        acquisitionCost: eur(12_000n),
        residualValue: eur(0n),
        depreciationMethod: "straight_line",
      });

      expect(hint(await assets.runDepreciation())).toBe("ASSETS_FORBIDDEN");

      await s.service();

      const run = await assets
        .runDepreciation({ organizationId: tenant, until: day("2026-03-31") })
        .orThrow();

      expect(run).toMatchObject({ assets: 1, months: 3 });
      expect(
        (await assets.runDepreciation({ until: day("2026-03-31") }).orThrow())
          .months,
      ).toBe(0);

      await s.as(owner);

      const months = await assets.depreciations(id).orThrow();

      expect(
        months.map((month) => [month.periodStart.toString(), month.amount]),
      ).toEqual([
        ["2026-01-01", eur(1000n)],
        ["2026-02-01", eur(1000n)],
        ["2026-03-01", eur(1000n)],
      ]);
      expect(months.every((month) => month.entryId !== undefined)).toBe(true);
      expect(
        hint(await assets.updateAsset(id, { acquisitionCost: eur(9000n) })),
      ).toBe("ASSETS_DEPRECIATION_STARTED");

      const disposed = await assets
        .dispose(id, { on: day("2026-05-10"), proceeds: eur(9000n) })
        .orThrow();

      expect(disposed).toMatchObject({
        status: "retired",
        accumulatedDepreciation: eur(4000n),
        bookValue: eur(8000n),
        disposalAmount: eur(9000n),
      });
      expect(disposed.disposedOn?.toString()).toBe("2026-05-10");
      expect(hint(await assets.dispose(id, { on: day("2026-06-01") }))).toBe(
        "ASSETS_DISPOSED",
      );

      await s.service();

      const postings = await s.rows<{
        source: string;
        code: string;
        debit: string;
        credit: string;
      }>(
        `select e.source_type as source, a.code, sum(l.debit)::text as debit, sum(l.credit)::text as credit
         from better_supabase.accounting_entries e
         join better_supabase.accounting_entry_lines l on l.entry_id = e.id
         join better_supabase.accounting_accounts a on a.id = l.account_id
         where e.tenant_id = $1 and e.status = 'posted' and e.source_type like 'asset_%'
         group by e.source_type, a.code order by e.source_type, a.code`,
        [tenant],
      );

      expect(postings).toEqual([
        {
          source: "asset_depreciation",
          code: "1510",
          debit: "0",
          credit: "4000",
        },
        {
          source: "asset_depreciation",
          code: "6800",
          debit: "4000",
          credit: "0",
        },
        { source: "asset_disposal", code: "1000", debit: "9000", credit: "0" },
        { source: "asset_disposal", code: "1500", debit: "0", credit: "12000" },
        { source: "asset_disposal", code: "1510", debit: "4000", credit: "0" },
        { source: "asset_disposal", code: "4910", debit: "0", credit: "1000" },
      ]);

      const [events] = await s.rows<{ depreciated: number; disposed: number }>(
        `select count(*) filter (where type = 'asset.depreciated')::integer as depreciated,
           count(*) filter (where type = 'asset.disposed')::integer as disposed
         from better_supabase.outbox_events where organization_id = $1`,
        [tenant],
      );

      expect(events).toEqual({ depreciated: 4, disposed: 1 });
    } finally {
      await s.close();
    }
  });

  it("sums a project's time at cost, billed time and dimension lines against its budget", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner, { member: ada });
      const transport = sqlTransport(s.sql);
      const books = createAccounting({ transport });
      const billing = createBillableTime({ transport, tenant });
      const time = createTimeTracking({ transport, tenant });
      const tasks = createTasks({ transport });

      await s.as(owner);
      await books.setup(tenant, { functionalCurrency: "EUR" }).orThrow();
      await books.openFiscalYear(tenant, 2026).orThrow();

      const project = await tasks
        .saveProject(tenant, {
          key: "apo",
          name: "Apollo",
          budget: eur(50_000n),
          budgetHours: 10,
        })
        .orThrow();

      expect(project).toMatchObject({ budget: eur(50_000n), budgetHours: 10 });

      const dimensions = await books.dimensions(tenant).orThrow();

      expect(dimensions.map((dimension) => dimension.key)).toContain("project");

      await billing
        .setRate({
          rate: eur(10_000n),
          cost: eur(6000n),
          effectiveFrom: day("2026-01-01"),
        })
        .orThrow();

      expect(
        hint(
          await billing.setRate({
            rate: eur(10_000n),
            cost: money(6000n, "USD"),
            effectiveFrom: day("2026-01-01"),
          }),
        ),
      ).toBe("CURRENCY_MISMATCH");

      const item = await tasks
        .create(tenant, { title: "Design", projectId: project.id })
        .orThrow();

      const subject = { type: "work_item", id: item.id };

      await time
        .log({
          startedAt: at("2026-10-06T09:00:00Z"),
          endedAt: at("2026-10-06T11:00:00Z"),
          subject,
          billable: true,
        })
        .orThrow();
      await time
        .log({
          startedAt: at("2026-10-07T09:00:00Z"),
          endedAt: at("2026-10-07T12:00:00Z"),
          subject,
          billable: true,
        })
        .orThrow();

      await s.as(ada);

      expect(hint(await billing.projectCosts(project.id))).toBe(
        "TASK_PROJECT_NOT_FOUND",
      );

      await s.as(owner);
      await billing.invoice({ subject, currency: "EUR" }).orThrow();

      const journals = await books.journals(tenant).orThrow();
      const general = journals.find((journal) => journal.code === "GEN")!;

      const entry = await books
        .saveEntry({
          journalId: general.id,
          entryDate: day("2026-10-08"),
          lines: [
            {
              accountCode: "6000",
              debit: 4000n,
              dimensions: { project: project.id },
            },
            { accountCode: "1000", credit: 4000n },
          ],
        })
        .orThrow();

      await books.postEntry(entry.id).orThrow();

      const costs = await billing.projectCosts(project.id).orThrow();

      expect(costs).toMatchObject({
        projectId: project.id,
        hours: 5,
        uncostedHours: 0,
        budget: eur(50_000n),
        budgetHours: 10,
        totals: [
          {
            currency: "EUR",
            timeCost: eur(30_000n),
            billed: eur(50_000n),
            expenses: eur(4000n),
            income: eur(0n),
            margin: eur(16_000n),
          },
        ],
      });
      expect(costs.budgetUsed).toEqual({ hours: 0.5, amount: 0.68 });
    } finally {
      await s.close();
    }
  });
});
