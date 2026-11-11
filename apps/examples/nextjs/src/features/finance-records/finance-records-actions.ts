"use server";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import { BANKING_TAG } from "@/features/banking/banking-cache";
import { BILLING_TAG } from "@/features/billing/billing-cache";
import { SHOP_TAG } from "@/features/shop/shop-cache";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { FINANCE_RECORDS_TAG } from "./finance-records-cache";

const Id = v.pipe(v.string(), v.uuid());

const Text = (max: number) =>
  v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(max));

const Day = v.pipe(v.string(), v.isoDate());

/** The tags every finance write expires: the lists and the domains they show. */
const TAGS = [FINANCE_RECORDS_TAG, BILLING_TAG, BANKING_TAG, SHOP_TAG];

/** Files a draft expense report for approval. */
export const submitExpenseReport = bsb.action(
  {
    input: v.object({ reportId: Id }),
    requireTenant: true,
    permission: "expenses.submit",
  },
  async ({ reportId }, { db, auth }) => {
    const submitted = await db.expenses.submit(reportId);

    if (!submitted.ok) {
      return submitted;
    }

    await refreshCaller(auth, TAGS);

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
  },
  async ({ reportId, approved, note }, { db, auth }) => {
    const decided = await db.expenses.decide({
      reportId,
      decision: { approved, ...(note === undefined ? {} : { note }) },
    });

    if (!decided.ok) {
      return decided;
    }

    await refreshCaller(auth, TAGS);

    return ok(decided.data.id);
  },
);

/** Pays an approved report out to the member. */
export const reimburseExpenseReport = bsb.action(
  {
    input: v.object({ reportId: Id }),
    requireTenant: true,
    permission: "expenses.manage",
  },
  async ({ reportId }, { db, auth }) => {
    const paid = await db.expenses.reimburse({ reportId });

    if (!paid.ok) {
      return paid;
    }

    await refreshCaller(auth, TAGS);

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
  },
  async ({ invoiceId, currency, amount }, { db, auth }) => {
    const paid = await db.invoices.recordPayment({
      invoiceId,
      payment: { amount: parseMoney(amount, currency), method: "manual" },
    });

    if (!paid.ok) {
      return paid;
    }

    await refreshCaller(auth, TAGS);

    return ok(paid.data.status);
  },
);

/** Voids an invoice that was issued by mistake; the reason stays in its history. */
export const voidInvoice = bsb.action(
  {
    input: v.object({ invoiceId: Id, reason: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "invoices.write",
  },
  async ({ invoiceId, reason }, { db, auth }) => {
    const voided = await db.invoices.void({
      invoiceId,
      ...(reason === undefined ? {} : { reason }),
    });

    if (!voided.ok) {
      return voided;
    }

    await refreshCaller(auth, TAGS);

    return ok(voided.data.status);
  },
);

/** Approves a purchase bill for payment at the caller's approval level. */
export const approvePayable = bsb.action(
  {
    input: v.object({ invoiceId: Id, comment: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "invoices.approve",
  },
  async ({ invoiceId, comment }, { db, auth }) => {
    const approved = await db.invoices.approvePurchaseInvoice({
      invoiceId,
      ...(comment === undefined ? {} : { comment }),
    });

    if (!approved.ok) {
      return approved;
    }

    await refreshCaller(auth, TAGS);

    return ok(approved.data.status);
  },
);

/** Stops writes into an open period without closing it. */
export const lockPeriod = bsb.action(
  {
    input: v.object({ periodId: Id }),
    requireTenant: true,
    permission: "periods.write",
  },
  async ({ periodId }, { db, auth }) => {
    const locked = await db.periods.lock(periodId);

    if (!locked.ok) {
      return locked;
    }

    await refreshCaller(auth, TAGS);

    return ok(locked.data.status);
  },
);

/** Closes a period when no block names a blocker. */
export const closePeriod = bsb.action(
  {
    input: v.object({ periodId: Id }),
    requireTenant: true,
    permission: "periods.write",
  },
  async ({ periodId }, { db, auth }) => {
    const closed = await db.periods.close(periodId);

    if (!closed.ok) {
      return closed;
    }

    await refreshCaller(auth, TAGS);

    return ok(closed.data.status);
  },
);

/** Reopens a locked or closed period; the on-close steps are not undone. */
export const reopenPeriod = bsb.action(
  {
    input: v.object({ periodId: Id, reason: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "periods.write",
  },
  async ({ periodId, reason }, { db, auth }) => {
    const reopened = await db.periods.reopen({
      periodId,
      ...(reason === undefined ? {} : { reason }),
    });

    if (!reopened.ok) {
      return reopened;
    }

    await refreshCaller(auth, TAGS);

    return ok(reopened.data.status);
  },
);

/** Builds, or rebuilds until it is filed, the return of a period. */
export const prepareTaxReturn = bsb.action(
  {
    input: v.object({ since: Day, until: Day, period: v.optional(Text(50)) }),
    requireTenant: true,
    permission: "tax.manage",
  },
  async ({ since, until, period }, { db, auth }) => {
    const prepared = await db.tax.prepareReturn({
      since,
      until,
      ...(period === undefined ? {} : { period }),
    });

    if (!prepared.ok) {
      return prepared;
    }

    await refreshCaller(auth, TAGS);

    return ok(prepared.data.id);
  },
);

/** Files a prepared return; a filed return can't be rebuilt. */
export const fileTaxReturn = bsb.action(
  {
    input: v.object({ returnId: Id }),
    requireTenant: true,
    permission: "tax.manage",
  },
  async ({ returnId }, { db, auth }) => {
    const filed = await db.tax.fileReturn(returnId);

    if (!filed.ok) {
      return filed;
    }

    await refreshCaller(auth, TAGS);

    return ok(filed.data.status);
  },
);

/** Turns the unbilled time of the organization into one draft invoice. */
export const invoiceBillableTime = bsb.action(
  {
    input: v.object({ title: v.optional(Text(200)) }),
    requireTenant: true,
    permission: "billable_time.invoice",
  },
  async ({ title }, { db, auth }) => {
    const invoiced = await db.billableTime.invoice(
      title === undefined ? {} : { title },
    );

    if (!invoiced.ok) {
      return invoiced;
    }

    await refreshCaller(auth, TAGS);

    return ok(invoiced.data.invoiceId);
  },
);

/** Collects a draft payroll run from the worked and leave hours of a period. */
export const createPayrollRun = bsb.action(
  {
    input: v.object({ from: Day, to: Day, label: v.optional(Text(200)) }),
    requireTenant: true,
    permission: "payroll_export.export",
  },
  async ({ from, to, label }, { db, auth }) => {
    const created = await db.payrollExport.create({
      from: Temporal.PlainDate.from(from),
      to: Temporal.PlainDate.from(to),
      ...(label === undefined ? {} : { label }),
    });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, TAGS);

    return ok(created.data.id);
  },
);

/** Collects a draft run's lines again, for time that changed since. */
export const refreshPayrollRun = bsb.action(
  {
    input: v.object({ runId: Id }),
    requireTenant: true,
    permission: "payroll_export.export",
  },
  async ({ runId }, { db, auth }) => {
    const refreshed = await db.payrollExport.refresh(runId);

    if (!refreshed.ok) {
      return refreshed;
    }

    await refreshCaller(auth, TAGS);

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
  },
  async ({ code, name, vatNumber, defaultCurrency }, { db, auth }) => {
    const created = await db.legalEntities.create({
      code,
      name,
      ...(vatNumber === undefined ? {} : { vatNumber }),
      ...(defaultCurrency === undefined ? {} : { defaultCurrency }),
    });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, TAGS);

    return ok(created.data.id);
  },
);

/** Makes a legal entity the default for new documents. */
export const makeDefaultLegalEntity = bsb.action(
  {
    input: v.object({ entityId: Id }),
    requireTenant: true,
    permission: "legal_entities.manage",
  },
  async ({ entityId }, { db, auth }) => {
    const updated = await db.legalEntities.setDefault(entityId);

    if (!updated.ok) {
      return updated;
    }

    await refreshCaller(auth, TAGS);

    return ok(updated.data.id);
  },
);

/** Archives a legal entity that is not the default. */
export const archiveLegalEntity = bsb.action(
  {
    input: v.object({ entityId: Id }),
    requireTenant: true,
    permission: "legal_entities.manage",
  },
  async ({ entityId }, { db, auth }) => {
    const archived = await db.legalEntities.archive(entityId);

    if (!archived.ok) {
      return archived;
    }

    await refreshCaller(auth, TAGS);

    return ok(archived.data.id);
  },
);

/** Ends an award today, or cancels it. */
export const endFundingAward = bsb.action(
  {
    input: v.object({ awardId: Id, canceled: v.optional(v.boolean()) }),
    requireTenant: true,
    permission: "funding.write",
  },
  async ({ awardId, canceled }, { db, auth }) => {
    const ended = await db.funding.endAward({
      awardId,
      ...(canceled === undefined ? {} : { canceled }),
    });

    if (!ended.ok) {
      return ended;
    }

    await refreshCaller(auth, TAGS);

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
  },
  async ({ name, iban, currency, holder }, { db, auth }) => {
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

    await refreshCaller(auth, TAGS);

    return ok(saved.data.id);
  },
);
