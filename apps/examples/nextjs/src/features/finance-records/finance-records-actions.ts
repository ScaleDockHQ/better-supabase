/* oxlint-disable anti-slop/no-conditional-empty-object-spread -- `exactOptionalPropertyTypes` rejects an explicit `undefined`, so an optional input is spread only when present; 11 findings */
"use server";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import { BILLING_TAG } from "@/features/billing/billing-cache";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

const Text = (max: number) =>
  v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(max));

const Day = v.pipe(v.string(), v.isoDate());

/** The tags every finance write expires: the lists and the domains they show. */
const TAGS = [tags.financeRecords(), BILLING_TAG, tags.banking(), tags.shop()];

/** Files a draft expense report for approval. */
export const submitExpenseReport = bsb.action(
  {
    input: v.object({ reportId: Id }),
    requireTenant: true,
    permission: "expenses.submit",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ reportId }, { db }) => {
    const submitted = await db.expenses.submit(reportId);

    if (!submitted.ok) {
      return submitted;
    }

    return ok(submitted.data.id);
  },
);

/** Approves or rejects a submitted report; the owner can't decide their own. */
export const decideExpenseReport = bsb.action(
  {
    input: v.object({
      reportId: Id,
      approved: v.boolean(),
      note: v.optional(Text(500)),
    }),
    requireTenant: true,
    permission: "expenses.approve",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ reportId, approved, note }, { db }) => {
    const decided = await db.expenses.decide({
      reportId,
      decision: { approved, ...(note === undefined ? {} : { note }) },
    });

    if (!decided.ok) {
      return decided;
    }

    return ok(decided.data.id);
  },
);

/** Pays an approved report out to the member. */
export const reimburseExpenseReport = bsb.action(
  {
    input: v.object({ reportId: Id }),
    requireTenant: true,
    permission: "expenses.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ reportId }, { db }) => {
    const paid = await db.expenses.reimburse({ reportId });

    if (!paid.ok) {
      return paid;
    }

    return ok(paid.data.id);
  },
);

/** Records a payment on an issued invoice, in the invoice's currency. */
export const recordInvoicePayment = bsb.action(
  {
    input: v.object({
      invoiceId: Id,
      currency: v.pipe(v.string(), v.regex(/^[A-Z]{3}$/)),
      amount: v.pipe(
        v.string(),
        v.trim(),
        v.regex(/^\d+(\.\d{1,2})?$/, "Enter an amount such as 190.00"),
      ),
    }),
    requireTenant: true,
    permission: "invoices.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ invoiceId, currency, amount }, { db }) => {
    const paid = await db.invoices.recordPayment({
      invoiceId,
      payment: { amount: parseMoney(amount, currency), method: "manual" },
    });

    if (!paid.ok) {
      return paid;
    }

    return ok(paid.data.status);
  },
);

/** Voids an invoice that was issued by mistake; the reason stays in its history. */
export const voidInvoice = bsb.action(
  {
    input: v.object({ invoiceId: Id, reason: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "invoices.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ invoiceId, reason }, { db }) => {
    const voided = await db.invoices.void({
      invoiceId,
      ...(reason === undefined ? {} : { reason }),
    });

    if (!voided.ok) {
      return voided;
    }

    return ok(voided.data.status);
  },
);

/** Approves a purchase bill for payment at the caller's approval level. */
export const approvePayable = bsb.action(
  {
    input: v.object({ invoiceId: Id, comment: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "invoices.approve",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ invoiceId, comment }, { db }) => {
    const approved = await db.invoices.approvePurchaseInvoice({
      invoiceId,
      ...(comment === undefined ? {} : { comment }),
    });

    if (!approved.ok) {
      return approved;
    }

    return ok(approved.data.status);
  },
);

/** Stops writes into an open period without closing it. */
export const lockPeriod = bsb.action(
  {
    input: v.object({ periodId: Id }),
    requireTenant: true,
    permission: "periods.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ periodId }, { db }) => {
    const locked = await db.periods.lock(periodId);

    if (!locked.ok) {
      return locked;
    }

    return ok(locked.data.status);
  },
);

/** Reopens a locked or closed period; the on-close steps are not undone. */
export const reopenPeriod = bsb.action(
  {
    input: v.object({ periodId: Id, reason: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "periods.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ periodId, reason }, { db }) => {
    const reopened = await db.periods.reopen({
      periodId,
      ...(reason === undefined ? {} : { reason }),
    });

    if (!reopened.ok) {
      return reopened;
    }

    return ok(reopened.data.status);
  },
);

/** Builds, or rebuilds until it is filed, the return of a period. */
export const prepareTaxReturn = bsb.action(
  {
    input: v.object({ since: Day, until: Day, period: v.optional(Text(50)) }),
    requireTenant: true,
    permission: "tax.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ since, until, period }, { db }) => {
    const prepared = await db.tax.prepareReturn({
      since,
      until,
      ...(period === undefined ? {} : { period }),
    });

    if (!prepared.ok) {
      return prepared;
    }

    return ok(prepared.data.id);
  },
);

/** Files a prepared return; a filed return can't be rebuilt. */
export const fileTaxReturn = bsb.action(
  {
    input: v.object({ returnId: Id }),
    requireTenant: true,
    permission: "tax.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ returnId }, { db }) => {
    const filed = await db.tax.fileReturn(returnId);

    if (!filed.ok) {
      return filed;
    }

    return ok(filed.data.status);
  },
);

/** Turns the unbilled time of the organization into one draft invoice. */
export const invoiceBillableTime = bsb.action(
  {
    input: v.object({ title: v.optional(Text(200)) }),
    requireTenant: true,
    permission: "billable_time.invoice",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ title }, { db }) => {
    const invoiced = await db.billableTime.invoice(
      title === undefined ? {} : { title },
    );

    if (!invoiced.ok) {
      return invoiced;
    }

    return ok(invoiced.data.invoiceId);
  },
);

/** Collects a draft payroll run from the worked and leave hours of a period. */
export const createPayrollRun = bsb.action(
  {
    input: v.object({ from: Day, to: Day, label: v.optional(Text(200)) }),
    requireTenant: true,
    permission: "payroll_export.export",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ from, to, label }, { db }) => {
    const created = await db.payrollExport.create({
      from: Temporal.PlainDate.from(from),
      to: Temporal.PlainDate.from(to),
      ...(label === undefined ? {} : { label }),
    });

    if (!created.ok) {
      return created;
    }

    return ok(created.data.id);
  },
);

/** Collects a draft run's lines again, for time that changed since. */
export const refreshPayrollRun = bsb.action(
  {
    input: v.object({ runId: Id }),
    requireTenant: true,
    permission: "payroll_export.export",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ runId }, { db }) => {
    const refreshed = await db.payrollExport.refresh(runId);

    if (!refreshed.ok) {
      return refreshed;
    }

    return ok(refreshed.data.id);
  },
);

/** Adds a company to the organization; the first one becomes its default. */
export const createLegalEntity = bsb.action(
  {
    input: v.object({
      code: v.pipe(Text(32), v.regex(/^[A-Za-z0-9][A-Za-z0-9_.-]*$/)),
      name: Text(200),
      vatNumber: v.optional(Text(50)),
      defaultCurrency: v.optional(v.pipe(v.string(), v.regex(/^[A-Z]{3}$/))),
    }),
    requireTenant: true,
    permission: "legal_entities.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ code, name, vatNumber, defaultCurrency }, { db }) => {
    const created = await db.legalEntities.create({
      code,
      name,
      ...(vatNumber === undefined ? {} : { vatNumber }),
      ...(defaultCurrency === undefined ? {} : { defaultCurrency }),
    });

    if (!created.ok) {
      return created;
    }

    return ok(created.data.id);
  },
);

/** Makes a legal entity the default for new documents. */
export const makeDefaultLegalEntity = bsb.action(
  {
    input: v.object({ entityId: Id }),
    requireTenant: true,
    permission: "legal_entities.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ entityId }, { db }) => {
    const updated = await db.legalEntities.setDefault(entityId);

    if (!updated.ok) {
      return updated;
    }

    return ok(updated.data.id);
  },
);

/** Archives a legal entity that is not the default. */
export const archiveLegalEntity = bsb.action(
  {
    input: v.object({ entityId: Id }),
    requireTenant: true,
    permission: "legal_entities.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ entityId }, { db }) => {
    const archived = await db.legalEntities.archive(entityId);

    if (!archived.ok) {
      return archived;
    }

    return ok(archived.data.id);
  },
);

/** Ends an award today, or cancels it. */
export const endFundingAward = bsb.action(
  {
    input: v.object({ awardId: Id, canceled: v.optional(v.boolean()) }),
    requireTenant: true,
    permission: "funding.write",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ awardId, canceled }, { db }) => {
    const ended = await db.funding.endAward({
      awardId,
      ...(canceled === undefined ? {} : { canceled }),
    });

    if (!ended.ok) {
      return ended;
    }

    return ok(ended.data.status);
  },
);

/** Adds a bank account; the first one in a currency becomes its primary. */
export const createBankAccount = bsb.action(
  {
    input: v.object({
      name: Text(200),
      iban: v.optional(Text(34)),
      currency: v.pipe(v.string(), v.regex(/^[A-Z]{3}$/)),
      holder: v.optional(Text(200)),
    }),
    requireTenant: true,
    permission: "banking.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ name, iban, currency, holder }, { db }) => {
    const saved = await db.banking.saveAccount({
      input: {
        name,
        currency,
        ...(iban === undefined ? {} : { iban }),
        ...(holder === undefined ? {} : { holder }),
      },
    });

    if (!saved.ok) {
      return saved;
    }

    return ok(saved.data.id);
  },
);
