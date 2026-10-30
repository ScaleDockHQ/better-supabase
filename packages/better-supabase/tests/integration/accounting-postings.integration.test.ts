import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { createAccounting } from "../../src/blocks/accounting/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createDonations } from "../../src/blocks/donations/index.ts";
import { createExpenses } from "../../src/blocks/expenses/index.ts";
import { createInvoices } from "../../src/blocks/invoices/index.ts";
import { createLeases } from "../../src/blocks/leases/index.ts";
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
  "attachments",
  "approvals",
  "subjects",
  "relations",
  "contacts",
  "assets",
  "ledger",
  "catalog",
  "accounting",
  "invoices",
  "expenses",
  "inventory",
  "leases",
  "donations",
];

interface Booked {
  readonly status: string;
  readonly total: string;
}

describe.skipIf(!live)("accounting postings", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  let s: BlockSession;
  let owner: TestUser;
  let ada: TestUser;
  let tenant: string;

  const booked = async (
    sourceType: string,
    sourceId: string,
  ): Promise<Booked[]> => {
    await s.service();

    const rows = await s.rows<Booked>(
      `select e.status, coalesce((select sum(l.debit) from better_supabase.accounting_entry_lines l where l.entry_id = e.id), 0)::text as total
       from better_supabase.accounting_entries e
       where e.tenant_id = $1 and e.source_type = $2 and e.source_id = $3
       order by e.number, e.id`,
      [tenant, sourceType, sourceId],
    );

    await s.as(owner);

    return rows;
  };

  const reversals = async (sourceType: string): Promise<number> => {
    await s.service();

    const [row] = await s.rows<{ count: number }>(
      `select count(*)::integer as count from better_supabase.accounting_entries r
       join better_supabase.accounting_entries e on e.id = r.reverses_id
       where e.tenant_id = $1 and e.source_type = $2`,
      [tenant, sourceType],
    );

    await s.as(owner);

    return row?.count ?? 0;
  };

  beforeAll(async () => {
    s = await BlockSession.open(pool);
    owner = await s.user("owner");
    ada = await s.user("ada");
    await s.install(MODULES, {
      subjects: withBlockSubjects({}, ["contacts"], {}),
    });
    tenant = await s.organization(owner, { member: ada });
    await s.as(owner);

    const books = createAccounting({ transport: sqlTransport(s.sql) });
    await books.setup(tenant, { functionalCurrency: "EUR" }).orThrow();
    await books.openFiscalYear(tenant, 2026).orThrow();
    const accounts = await books.accounts(tenant).orThrow();
    await books
      .saveTaxCode(tenant, {
        code: "VAT21",
        name: "VAT 21%",
        rateBps: 2100,
        kind: "sales",
        accountId: accounts.find((account) => account.code === "2100")!.id,
        reportBoxes: ["1a"],
      })
      .orThrow();
  });

  afterAll(async () => {
    await s.close();
    await pool.end();
  });

  it("books an issued invoice and its payment once, and reverses them on void", async () => {
    const transport = sqlTransport(s.sql);
    const invoices = createInvoices({ transport });
    const books = createAccounting({ transport });

    const draft = await invoices
      .create(tenant, { title: "Work" }, [
        { description: "Work", unitAmount: eur(1000n), taxRateBps: 2100 },
      ])
      .orThrow();

    expect(await booked("invoice", draft.id)).toEqual([]);

    const invoice = await invoices.issue(draft.id).orThrow();

    expect(await booked("invoice", invoice.id)).toEqual([
      { status: "posted", total: "1210" },
    ]);

    const again = await books.postSource("invoice", invoice.id).orThrow();

    expect(again?.status).toBe("posted");
    expect(await booked("invoice", invoice.id)).toHaveLength(1);

    const today = Temporal.Now.plainDateISO("UTC");

    const report = await books
      .taxReport(tenant, day("2026-01-01"), today)
      .orThrow();

    expect(report.boxes).toEqual([{ box: "1a", base: 1000n, tax: 210n }]);
    expect(report.netTax).toBe(210n);

    await invoices.recordPayment(invoice.id, { amount: eur(500n) }).orThrow();

    await s.service();

    const [payment] = await s.rows<{ id: string }>(
      "select id::text from better_supabase.ledger_transactions where tenant_id = $1 and metadata ->> 'invoiceId' = $2",
      [tenant, invoice.id],
    );

    await s.as(owner);

    expect(await booked("invoice_payment", payment!.id)).toEqual([
      { status: "posted", total: "500" },
    ]);

    const other = await invoices
      .create(tenant, { title: "Mistake" }, [
        { description: "Oops", unitAmount: eur(300n) },
      ])
      .orThrow();

    await invoices.issue(other.id).orThrow();
    await invoices.void(other.id, "mistake").orThrow();

    expect(await booked("invoice", other.id)).toEqual([
      { status: "reversed", total: "300" },
    ]);
    expect(await reversals("invoice")).toBe(1);
  });

  it("books an expense report on approval and its reimbursement", async () => {
    const expenses = createExpenses({ transport: sqlTransport(s.sql), tenant });

    const meals = await expenses
      .saveCategory({ key: "meals", name: "Meals" })
      .orThrow();

    await s.as(ada);

    const report = await expenses
      .create({ title: "Lunch", currency: "EUR" })
      .orThrow();

    await expenses
      .addLine(report.id, {
        categoryId: meals.id,
        spentOn: day("2026-10-01"),
        amount: eur(4000n),
        description: "Lunch",
      })
      .orThrow();
    const submitted = await expenses.submit(report.id).orThrow();

    await s.as(owner);
    expect(await booked("expense_report", report.id)).toEqual([]);
    await s.value("better_supabase.decide_approval($1, 'approved')", [
      submitted.approvalId,
    ]);

    expect(await booked("expense_report", report.id)).toEqual([
      { status: "posted", total: "4000" },
    ]);

    await expenses.reimburse(report.id, { reference: "SEPA-1" }).orThrow();

    expect(await booked("expense_reimbursement", report.id)).toEqual([
      { status: "posted", total: "4000" },
    ]);
  });

  it("books stock value movements under average costing", async () => {
    const product = await s.value<{ id: string }>(
      "better_supabase.save_product($1, null, 'TEE', null, null, 'physical')",
      [tenant],
    );

    const variant = await s.value<{ id: string }>(
      "better_supabase.save_variant($1, null, 'TEE', '{}'::uuid[], null, null, null, true, false)",
      [product.id],
    );

    const location = await s.value<{ id: string }>(
      "better_supabase.save_location($1, null, 'WH', 'WH', 'warehouse')",
      [tenant],
    );

    await s.value(
      "better_supabase.set_stock_item($1, null, null, null, null, 'average', 'EUR')",
      [variant.id],
    );
    await s.value(
      `better_supabase.adjust_stock($1, $2, 10, 'receipt', null, '{"unitCost":"450","currency":"EUR"}'::jsonb)`,
      [variant.id, location.id],
    );
    await s.value("better_supabase.adjust_stock($1, $2, -2, 'damage', null)", [
      variant.id,
      location.id,
    ]);

    await s.service();

    const movements = await s.rows<{ status: string; total: string }>(
      `select e.status, (select sum(l.debit) from better_supabase.accounting_entry_lines l where l.entry_id = e.id)::text as total
       from better_supabase.accounting_entries e
       where e.tenant_id = $1 and e.source_type = 'stock_movement'
       order by e.number, e.id`,
      [tenant],
    );

    await s.as(owner);

    expect(movements).toEqual([
      { status: "posted", total: "4500" },
      { status: "posted", total: "900" },
    ]);
  });

  it("books lease rent and payments", async () => {
    const transport = sqlTransport(s.sql);
    const leases = createLeases({ transport, tenant });

    const company = await createContacts({ transport })
      .saveCompany(tenant, { name: "Acme" })
      .orThrow();

    const unit = await s.value<{ id: string }>(
      "better_supabase.create_asset($1, 'unit', 'Flat 2A')",
      [tenant],
    );

    const lease = await leases
      .create({
        unitId: unit.id,
        party: { type: "company", id: company.id },
        startsOn: day("2026-01-01"),
        rent: eur(100_000n),
      })
      .orThrow();

    await leases.activate(lease.id).orThrow();
    await leases.postDueRent({ through: day("2026-02-15") }).orThrow();

    const charges = await leases.charges(lease.id).orThrow();

    for (const charge of charges) {
      expect(await booked("lease_rent", charge.id)).toEqual([
        { status: "posted", total: "100000" },
      ]);
    }

    await leases
      .recordPayment(lease.id, { amount: eur(150_000n), reference: "bank-1" })
      .orThrow();

    await s.service();

    const [payment] = await s.rows<{ total: string }>(
      `select (select sum(l.debit) from better_supabase.accounting_entry_lines l where l.entry_id = e.id)::text as total
       from better_supabase.accounting_entries e where e.tenant_id = $1 and e.source_type = 'lease_payment'`,
      [tenant],
    );

    await s.as(owner);

    expect(payment?.total).toBe("150000");
  });

  it("books a posted gift and reverses it on refund", async () => {
    const transport = sqlTransport(s.sql);
    const donations = createDonations({ transport, tenant });

    const company = await createContacts({ transport })
      .saveCompany(tenant, { name: "Donor" })
      .orThrow();

    const gift = await donations
      .recordGift({
        donor: { type: "company", id: company.id },
        amount: eur(25_000n),
        receivedOn: day("2026-03-01"),
        method: "bank",
      })
      .orThrow();

    expect(await booked("gift", gift.id)).toEqual([
      { status: "posted", total: "25000" },
    ]);

    await s.service();
    await s.value("better_supabase.donation_settle($1, 'refunded')", [gift.id]);
    await s.as(owner);

    expect(await booked("gift", gift.id)).toEqual([
      { status: "reversed", total: "25000" },
    ]);
  });
});
