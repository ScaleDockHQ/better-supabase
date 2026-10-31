import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createAccounting } from "../../src/blocks/accounting/index.ts";
import { createBillableTime } from "../../src/blocks/billable-time/index.ts";
import { createExpenses } from "../../src/blocks/expenses/index.ts";
import { createInvoices } from "../../src/blocks/invoices/index.ts";
import { createTasks } from "../../src/blocks/tasks/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");
const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

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
  "attachments",
  "tasks",
  "accounting",
  "time-tracking",
  "invoices",
  "billable-time",
  "expenses",
];

// The shared stack's work_items table references `work_projects`, the name
// the Next.js example gives it.
const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["tasks"], {}),
  modules: { tasks: { tables: { projects: "work_projects" } } },
};

describe.skipIf(!live)("purchase costs by project", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("books bill lines and expense lines on their own project dimension", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner, { member: ada });
      const transport = sqlTransport(s.sql);
      const books = createAccounting({ transport });
      const billing = createBillableTime({ transport, tenant });
      const tasks = createTasks({ transport });
      const invoices = createInvoices({ transport });
      const expenses = createExpenses({ transport, tenant });

      await s.as(owner);
      await books.setup(tenant, { functionalCurrency: "EUR" }).orThrow();
      await books.openFiscalYear(tenant, 2026).orThrow();

      const apollo = await tasks
        .saveProject(tenant, { key: "apo", name: "Apollo" })
        .orThrow();

      const gemini = await tasks
        .saveProject(tenant, { key: "gem", name: "Gemini" })
        .orThrow();

      const draft = await invoices
        .create(
          tenant,
          {
            title: "Parts",
            direction: "purchase",
            supplierReference: "S-1",
            dimensions: { project: gemini.id },
          },
          [
            {
              description: "Antenna",
              quantity: 1,
              unitAmount: eur(3000n),
              dimensions: { project: apollo.id },
            },
            { description: "Cable", quantity: 2, unitAmount: eur(500n) },
          ],
        )
        .orThrow();

      expect(draft.lines[0]?.dimensions).toEqual({ project: apollo.id });
      expect(draft.lines[1]?.dimensions).toBeUndefined();

      await invoices.issue(draft.id).orThrow();

      const category = await expenses
        .saveCategory({ key: "travel", name: "Travel" })
        .orThrow();

      await s.as(ada);

      const report = await expenses
        .create({ title: "Site visit", currency: "EUR" })
        .orThrow();

      const withProject = await expenses
        .addLine(report.id, {
          categoryId: category.id,
          spentOn: day("2026-10-02"),
          amount: eur(2500n),
          description: "Train",
          dimensions: { project: apollo.id },
        })
        .orThrow();

      expect(withProject.dimensions).toEqual({ project: apollo.id });

      await expenses
        .addLine(report.id, {
          categoryId: category.id,
          spentOn: day("2026-10-02"),
          amount: eur(700n),
          description: "Lunch",
        })
        .orThrow();

      const moved = await expenses
        .updateLine(withProject.id, { dimensions: { project: gemini.id } })
        .orThrow();

      expect(moved.dimensions).toEqual({ project: gemini.id });
      await expenses
        .updateLine(withProject.id, { dimensions: { project: apollo.id } })
        .orThrow();

      const submitted = await expenses.submit(report.id).orThrow();

      await s.as(owner);
      await s.value("better_supabase.decide_approval($1, 'approved')", [
        submitted.approvalId,
      ]);

      await s.service();

      const lines = await s.rows<{
        source: string;
        code: string;
        debit: string;
        project: string | null;
      }>(
        `select e.source_type as source, a.code, l.debit::text as debit, l.dimensions ->> 'project' as project
         from better_supabase.accounting_entries e
         join better_supabase.accounting_entry_lines l on l.entry_id = e.id
         join better_supabase.accounting_accounts a on a.id = l.account_id
         where e.tenant_id = $1 and e.status = 'posted' and l.debit > 0
           and e.source_type in ('invoice', 'expense_report')
         order by e.source_type, l.debit desc`,
        [tenant],
      );

      const named = new Map([
        [apollo.id, "apollo"],
        [gemini.id, "gemini"],
      ]);

      expect(
        lines.map((line) => [
          line.source,
          line.debit,
          line.project === null ? null : named.get(line.project),
        ]),
      ).toEqual([
        ["expense_report", "2500", "apollo"],
        ["expense_report", "700", null],
        ["invoice", "3000", "apollo"],
        ["invoice", "1000", "gemini"],
      ]);

      await s.as(owner);

      const costs = await billing.projectCosts(apollo.id).orThrow();

      expect(costs.totals).toMatchObject([
        { currency: "EUR", expenses: eur(5500n) },
      ]);

      const other = await billing.projectCosts(gemini.id).orThrow();

      expect(other.totals).toMatchObject([
        { currency: "EUR", expenses: eur(1000n) },
      ]);
    } finally {
      await s.close();
    }
  });
});
