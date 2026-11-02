import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import {
  createExpenses,
  sqlTransport,
} from "../../src/blocks/expenses/index.ts";
import { money } from "../../src/commerce/money.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "attachments",
  "approvals",
  "ledger",
  "expenses",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

describe.skipIf(!live)("expenses", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("checks the spend policy on submit, books the approval on the ledger and reimburses it", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, {});
      const tenant = await s.organization(owner, { member: ada });

      const expenses = createExpenses({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.as(owner);

      const travel = await expenses
        .saveCategory({
          key: "travel",
          name: "Travel",
          limit: money(50_000n, "EUR"),
          receiptOver: money(20_000n, "EUR"),
        })
        .orThrow();

      const meals = await expenses
        .saveCategory({ key: "meals", name: "Meals" })
        .orThrow();

      await s.as(ada);
      expect(
        await expenses.saveCategory({ key: "gifts", name: "Gifts" }).then(hint),
      ).toBe("EXPENSES_FORBIDDEN");

      const report = await expenses
        .create({ title: "Berlin trip", currency: "EUR" })
        .orThrow();

      const train = await expenses
        .addLine({
          reportId: report.id,
          line: {
            categoryId: travel.id,
            spentOn: day("2026-10-01"),
            amount: money(30_000n, "EUR"),
            description: "Train",
          },
        })
        .orThrow();

      await expenses
        .addLine({
          reportId: report.id,
          line: {
            categoryId: meals.id,
            spentOn: day("2026-10-01"),
            amount: money(4000n, "EUR"),
            description: "Dinner",
          },
        })
        .orThrow();
      expect(
        await expenses
          .addLine({
            reportId: report.id,
            line: {
              categoryId: meals.id,
              spentOn: day("2026-10-02"),
              amount: money(1000n, "USD"),
              description: "Taxi",
            },
          })
          .then(hint),
      ).toBe("EXPENSE_CURRENCY_MISMATCH");
      expect(
        (await expenses.check(report.id).orThrow()).map((v) => v.kind),
      ).toEqual(["receipt"]);
      expect(await expenses.submit(report.id).then(hint)).toBe(
        "EXPENSE_POLICY_VIOLATION",
      );

      await s.service();
      await s.rows(
        `insert into better_supabase.attachments (organization_id, subject_type, subject_id, name, mime_type, size, status, uploaded_at)
         values ($1, 'expense_line', $2, 'ticket.pdf', 'application/pdf', 1024, 'clean', now())`,
        [tenant, train.id],
      );
      await s.as(ada);

      expect(await expenses.check(report.id).orThrow()).toEqual([]);

      const submitted = await expenses.submit(report.id).orThrow();

      expect(submitted).toMatchObject({
        status: "submitted",
        total: money(34_000n, "EUR"),
      });
      expect(
        submitted.lines.find((line) => line.id === train.id)?.receipts,
      ).toBe(1);
      expect(await expenses.reimburse({ reportId: report.id }).then(hint)).toBe(
        "EXPENSES_FORBIDDEN",
      );

      await s.as(owner);
      await s.value("better_supabase.decide_approval($1, 'approved')", [
        submitted.approvalId,
      ]);

      const approved = await expenses.get(report.id).orThrow();

      expect(approved.status).toBe("approved");
      expect(approved.approvalTransactionId).toBeDefined();

      const reimbursed = await expenses
        .reimburse({ reportId: report.id, input: { reference: "SEPA-1" } })
        .orThrow();

      expect(reimbursed.status).toBe("reimbursed");

      const balances = await s.rows<{ code: string; balance: string }>(
        `select a.code, b.balance::text as balance
         from better_supabase.ledger_accounts a
         join better_supabase.ledger_balances b on b.account_id = a.id
         where a.tenant_id = $1 order by a.code`,
        [tenant],
      );

      expect(balances).toEqual([
        { code: "expenses:cash:EUR", balance: "-34000" },
        { code: "expenses:category:meals:EUR", balance: "4000" },
        { code: "expenses:category:travel:EUR", balance: "30000" },
        { code: `expenses:payable:${ada.id}:EUR`, balance: "0" },
      ]);

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'expense_report.%' order by position",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual([
        "expense_report.created",
        "expense_report.submitted",
        "expense_report.approved",
        "expense_report.reimbursed",
      ]);
    } finally {
      await s.close();
    }
  });

  it("lets the member fix a rejected report and submit it again", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, {});
      const tenant = await s.organization(owner, { member: ada });

      const expenses = createExpenses({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.as(owner);

      const meals = await expenses
        .saveCategory({ key: "meals", name: "Meals" })
        .orThrow();

      await s.as(ada);

      const report = await expenses
        .create({ title: "Lunch", currency: "EUR" })
        .orThrow();

      await expenses
        .addLine({
          reportId: report.id,
          line: {
            categoryId: meals.id,
            spentOn: day("2026-10-01"),
            amount: money(2500n, "EUR"),
            description: "Lunch",
          },
        })
        .orThrow();

      const submitted = await expenses.submit(report.id).orThrow();

      await s.as(owner);
      await s.value(
        "better_supabase.decide_approval($1, 'rejected', 'No receipt')",
        [submitted.approvalId],
      );

      await s.as(ada);
      expect((await expenses.get(report.id).orThrow()).status).toBe("rejected");

      const resubmitted = await expenses.submit(report.id).orThrow();

      expect(resubmitted.status).toBe("submitted");
      expect(resubmitted.approvalId).not.toBe(submitted.approvalId);
      expect((await expenses.cancel(report.id).orThrow()).status).toBe(
        "cancelled",
      );
    } finally {
      await s.close();
    }
  });
});
