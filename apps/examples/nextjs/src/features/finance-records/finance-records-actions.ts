/* oxlint-disable anti-slop/no-conditional-empty-object-spread -- `exactOptionalPropertyTypes` rejects an explicit `undefined`, so an optional input is spread only when present; 11 findings */
"use server";

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
export const submitExpenseReport = bsb.blockAction(
  ({ db }) => db.expenses,
  "submit",
  {
    input: v.object({ reportId: Id }),
    requireTenant: true,
    permission: "expenses.submit",
    tags: () => TAGS,
    refresh: true,
    args: ({ reportId }) => [reportId],
  },
  (submitted) => submitted.id,
);

/** Approves or rejects a submitted report; the owner can't decide their own. */
export const decideExpenseReport = bsb.blockAction(
  ({ db }) => db.expenses,
  "decide",
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
    args: ({ reportId, approved, note }) => [
      {
        reportId,
        decision: { approved, ...(note === undefined ? {} : { note }) },
      },
    ],
  },
  (decided) => decided.id,
);

/** Pays an approved report out to the member. */
export const reimburseExpenseReport = bsb.blockAction(
  ({ db }) => db.expenses,
  "reimburse",
  {
    input: v.object({ reportId: Id }),
    requireTenant: true,
    permission: "expenses.manage",
    tags: () => TAGS,
    refresh: true,
  },
  (paid) => paid.id,
);

/** Records a payment on an issued invoice, in the invoice's currency. */
export const recordInvoicePayment = bsb.blockAction(
  ({ db }) => db.invoices,
  "recordPayment",
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
    args: ({ invoiceId, currency, amount }) => [
      {
        invoiceId,
        payment: { amount: parseMoney(amount, currency), method: "manual" },
      },
    ],
  },
  (paid) => paid.status,
);

/** Voids an invoice that was issued by mistake; the reason stays in its history. */
export const voidInvoice = bsb.blockAction(
  ({ db }) => db.invoices,
  "void",
  {
    input: v.object({ invoiceId: Id, reason: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "invoices.write",
    tags: () => TAGS,
    refresh: true,
    args: ({ invoiceId, reason }) => [
      { invoiceId, ...(reason === undefined ? {} : { reason }) },
    ],
  },
  (voided) => voided.status,
);

/** Approves a purchase bill for payment at the caller's approval level. */
export const approvePayable = bsb.blockAction(
  ({ db }) => db.invoices,
  "approvePurchaseInvoice",
  {
    input: v.object({ invoiceId: Id, comment: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "invoices.approve",
    tags: () => TAGS,
    refresh: true,
    args: ({ invoiceId, comment }) => [
      { invoiceId, ...(comment === undefined ? {} : { comment }) },
    ],
  },
  (approved) => approved.status,
);

/** Stops writes into an open period without closing it. */
export const lockPeriod = bsb.blockAction(
  ({ db }) => db.periods,
  "lock",
  {
    input: v.object({ periodId: Id }),
    requireTenant: true,
    permission: "periods.write",
    tags: () => TAGS,
    refresh: true,
    args: ({ periodId }) => [periodId],
  },
  (locked) => locked.status,
);

/** Reopens a locked or closed period; the on-close steps are not undone. */
export const reopenPeriod = bsb.blockAction(
  ({ db }) => db.periods,
  "reopen",
  {
    input: v.object({ periodId: Id, reason: v.optional(Text(300)) }),
    requireTenant: true,
    permission: "periods.write",
    tags: () => TAGS,
    refresh: true,
    args: ({ periodId, reason }) => [
      { periodId, ...(reason === undefined ? {} : { reason }) },
    ],
  },
  (reopened) => reopened.status,
);

/** Builds, or rebuilds until it is filed, the return of a period. */
export const prepareTaxReturn = bsb.blockAction(
  ({ db }) => db.tax,
  "prepareReturn",
  {
    input: v.object({ since: Day, until: Day, period: v.optional(Text(50)) }),
    requireTenant: true,
    permission: "tax.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ since, until, period }) => [
      { since, until, ...(period === undefined ? {} : { period }) },
    ],
  },
  (prepared) => prepared.id,
);

/** Files a prepared return; a filed return can't be rebuilt. */
export const fileTaxReturn = bsb.blockAction(
  ({ db }) => db.tax,
  "fileReturn",
  {
    input: v.object({ returnId: Id }),
    requireTenant: true,
    permission: "tax.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ returnId }) => [returnId],
  },
  (filed) => filed.status,
);

/** Turns the unbilled time of the organization into one draft invoice. */
export const invoiceBillableTime = bsb.blockAction(
  ({ db }) => db.billableTime,
  "invoice",
  {
    input: v.object({ title: v.optional(Text(200)) }),
    requireTenant: true,
    permission: "billable_time.invoice",
    tags: () => TAGS,
    refresh: true,
    args: ({ title }) => [title === undefined ? {} : { title }],
  },
  (invoiced) => invoiced.invoiceId,
);

/** Collects a draft payroll run from the worked and leave hours of a period. */
export const createPayrollRun = bsb.blockAction(
  ({ db }) => db.payrollExport,
  "create",
  {
    input: v.object({ from: Day, to: Day, label: v.optional(Text(200)) }),
    requireTenant: true,
    permission: "payroll_export.export",
    tags: () => TAGS,
    refresh: true,
    args: ({ from, to, label }) => [
      {
        from: Temporal.PlainDate.from(from),
        to: Temporal.PlainDate.from(to),
        ...(label === undefined ? {} : { label }),
      },
    ],
  },
  (created) => created.id,
);

/** Collects a draft run's lines again, for time that changed since. */
export const refreshPayrollRun = bsb.blockAction(
  ({ db }) => db.payrollExport,
  "refresh",
  {
    input: v.object({ runId: Id }),
    requireTenant: true,
    permission: "payroll_export.export",
    tags: () => TAGS,
    refresh: true,
    args: ({ runId }) => [runId],
  },
  (refreshed) => refreshed.id,
);

/** Adds a company to the organization; the first one becomes its default. */
export const createLegalEntity = bsb.blockAction(
  ({ db }) => db.legalEntities,
  "create",
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
    args: ({ code, name, vatNumber, defaultCurrency }) => [
      {
        code,
        name,
        ...(vatNumber === undefined ? {} : { vatNumber }),
        ...(defaultCurrency === undefined ? {} : { defaultCurrency }),
      },
    ],
  },
  (created) => created.id,
);

/** Makes a legal entity the default for new documents. */
export const makeDefaultLegalEntity = bsb.blockAction(
  ({ db }) => db.legalEntities,
  "setDefault",
  {
    input: v.object({ entityId: Id }),
    requireTenant: true,
    permission: "legal_entities.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ entityId }) => [entityId],
  },
  (updated) => updated.id,
);

/** Archives a legal entity that is not the default. */
export const archiveLegalEntity = bsb.blockAction(
  ({ db }) => db.legalEntities,
  "archive",
  {
    input: v.object({ entityId: Id }),
    requireTenant: true,
    permission: "legal_entities.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ entityId }) => [entityId],
  },
  (archived) => archived.id,
);

/** Ends an award today, or cancels it. */
export const endFundingAward = bsb.blockAction(
  ({ db }) => db.funding,
  "endAward",
  {
    input: v.object({ awardId: Id, canceled: v.optional(v.boolean()) }),
    requireTenant: true,
    permission: "funding.write",
    tags: () => TAGS,
    refresh: true,
    args: ({ awardId, canceled }) => [
      { awardId, ...(canceled === undefined ? {} : { canceled }) },
    ],
  },
  (ended) => ended.status,
);

/** Adds a bank account; the first one in a currency becomes its primary. */
export const createBankAccount = bsb.blockAction(
  ({ db }) => db.banking,
  "saveAccount",
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
    args: ({ name, iban, currency, holder }) => [
      {
        input: {
          name,
          currency,
          ...(iban === undefined ? {} : { iban }),
          ...(holder === undefined ? {} : { holder }),
        },
      },
    ],
  },
  (saved) => saved.id,
);
