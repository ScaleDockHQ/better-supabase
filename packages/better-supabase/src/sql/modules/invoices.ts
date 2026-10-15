import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import {
  lineTableSpec,
  TOTAL_COLUMNS,
  totalColumnsSql,
} from "../line-items-sql.ts";
import {
  addExtraColumns,
  lockTable,
  schemaPreamble,
  tenantIn,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import { invoiceFunctions, type InvoiceNames } from "./invoices-functions.ts";

const INVOICE = [
  "organizationId",
  "invoiceId",
  "subjectType",
  "subjectId",
  "identifier",
] as const;

const EVENTS: ModuleEvents = {
  "invoice.created": { subject: "invoices", payload: [...INVOICE] },
  "invoice.issued": {
    subject: "invoices",
    payload: [...INVOICE, "total", "currency", "dueOn"],
  },
  "invoice.payment_recorded": {
    subject: "invoices",
    payload: [...INVOICE, "paymentId", "amount", "balance"],
  },
  "invoice.paid": { subject: "invoices", payload: [...INVOICE, "total"] },
  "invoice.credited": {
    subject: "invoices",
    payload: [...INVOICE, "creditNoteId", "amount"],
  },
  "invoice.voided": { subject: "invoices", payload: [...INVOICE, "reason"] },
  "invoice.uncollected": {
    subject: "invoices",
    payload: [...INVOICE, "balance"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_invoice_issue",
    "after_invoice_issue",
    "before_invoice_payment",
    "after_invoice_payment",
  ],
  options: [
    "company",
    "contact",
    "prefix",
    "creditPrefix",
    "termsDays",
    "extraColumns",
  ],
  tables: {
    invoices: {
      name: "invoices",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        number: "number",
        identifier: "identifier",
        original: "original_id",
        title: "title",
        companyType: "company_type",
        companyId: "company_id",
        contactType: "contact_type",
        contactId: "contact_id",
        currency: "currency",
        status: "status",
        termsDays: "terms_days",
        issuedOn: "issued_on",
        dueOn: "due_on",
        paidTotal: "paid_total",
        creditedTotal: "credited_total",
        paidAt: "paid_at",
        voidedAt: "voided_at",
        voidReason: "void_reason",
        note: "note",
        originType: "origin_type",
        originId: "origin_id",
        depositBps: "deposit_bps",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        ...TOTAL_COLUMNS,
      },
    },
    lines: lineTableSpec("invoice_lines"),
    payments: {
      name: "invoice_payments",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        invoice: "invoice_id",
        amount: "amount",
        paidAt: "paid_at",
        method: "method",
        reference: "reference",
        recordedBy: "recorded_by",
        createdAt: "created_at",
      },
    },
  },
};

function tables(ctx: ModuleContext, n: InvoiceNames): string {
  if (!ctx.manages) return "";
  const { t, c } = n;
  const i = (column: string): string => c("invoices", column);
  const p = (column: string): string => c("payments", column);
  return `
create table if not exists ${t("invoices")} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("kind")} text not null default 'invoice' check (${i("kind")} in ('invoice', 'credit_note')),
  ${i("number")} bigint,
  ${i("identifier")} text,
  ${i("original")} uuid references ${t("invoices")} (${i("id")}),
  ${i("title")} text not null check (length(${i("title")}) between 1 and 300),
  ${i("companyType")} text,
  ${i("companyId")} text,
  ${i("contactType")} text,
  ${i("contactId")} text,
  ${i("currency")} char(3) not null check (${i("currency")} ~ '^[A-Z]{3}$'),
  ${i("status")} text not null default 'draft' check (${i("status")} in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible')),
  ${i("termsDays")} integer not null default 30 check (${i("termsDays")} >= 0),
  ${i("issuedOn")} date,
  ${i("dueOn")} date,
  ${i("paidTotal")} bigint not null default 0,
  ${i("creditedTotal")} bigint not null default 0,
  ${i("paidAt")} timestamptz,
  ${i("voidedAt")} timestamptz,
  ${i("voidReason")} text,
  ${i("note")} text,
  ${i("originType")} text,
  ${i("originId")} text,
  ${i("depositBps")} integer check (${i("depositBps")} > 0 and ${i("depositBps")} < 10000),
  ${i("createdBy")} uuid,
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now(),
  ${totalColumnsSql(ctx, "invoices")},
  unique (${i("tenant")}, ${i("kind")}, ${i("number")}),
  check ((${i("kind")} = 'credit_note') = (${i("original")} is not null)),
  check (${i("status")} <> 'draft' or ${i("number")} is null),
  check (${i("status")} in ('draft', 'void') or ${i("number")} is not null),
  check ((${i("companyType")} is null) = (${i("companyId")} is null))
);
create index if not exists invoices_tenant_status_idx on ${t("invoices")} (${i("tenant")}, ${i("status")}, ${i("dueOn")});
create index if not exists invoices_origin_idx on ${t("invoices")} (${i("originType")}, ${i("originId")});
create index if not exists invoices_original_idx on ${t("invoices")} (${i("original")});
create index if not exists invoices_company_idx on ${t("invoices")} (${i("companyType")}, ${i("companyId")});${addExtraColumns(t("invoices"), ctx.extraColumns("invoices"))}
${lockTable(t("invoices"), { read: true })}
drop policy if exists invoices_read on ${t("invoices")};
create policy invoices_read on ${t("invoices")} for select to authenticated
using (${tenantIn(i("tenant"), n.read)});

create table if not exists ${t("payments")} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("invoice")} uuid not null references ${t("invoices")} (${i("id")}) on delete cascade,
  ${p("amount")} bigint not null check (${p("amount")} <> 0),
  ${p("paidAt")} timestamptz not null default now(),
  ${p("method")} text,
  ${p("reference")} text,
  ${p("recordedBy")} uuid,
  ${p("createdAt")} timestamptz not null default now()
);
create index if not exists invoice_payments_invoice_idx on ${t("payments")} (${p("invoice")}, ${p("paidAt")});
create unique index if not exists invoice_payments_reference_idx on ${t("payments")} (${p("tenant")}, ${p("reference")}) where ${p("reference")} is not null;
${lockTable(t("payments"), { read: true })}
drop policy if exists invoice_payments_read on ${t("payments")};
create policy invoice_payments_read on ${t("payments")} for select to authenticated
using (${tenantIn(p("tenant"), n.read)});
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const keys = moduleOperations("invoices");
  const termsDays = ctx.number("termsDays", 30);
  if (!Number.isInteger(termsDays) || termsDays < 0) {
    throw new TypeError(
      "sql.modules.invoices.options.termsDays must be 0 or a positive integer",
    );
  }
  const n: InvoiceNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    manage: ctx.permission("manage", keys.manage),
    company: ctx.text("company", "company"),
    contact: ctx.text("contact", "person"),
    prefix: ctx.text("prefix", "INV-"),
    creditPrefix: ctx.text("creditPrefix", "CN-"),
    termsDays,
    service: "(auth.role() = 'service_role')",
  };
  return `${schemaPreamble(ctx)}
-- Invoices an organization sends its own customers: drafts with lines, a
-- number on issue, payments, credit notes, void and write-off, and aging.
${tables(ctx, n)}${invoiceFunctions(ctx, n)}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    {
      name: "create_invoice",
      args: ["{id}", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    { name: "set_invoice_lines", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "issue_invoice", args: ["uuid", "date"], returns: "jsonb" },
    {
      name: "record_invoice_payment",
      args: ["uuid", "bigint", "timestamptz", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "credit_invoice",
      args: ["uuid", "jsonb", "text"],
      returns: "jsonb",
    },
    { name: "void_invoice", args: ["uuid", "text"], returns: "jsonb" },
    { name: "write_off_invoice", args: ["uuid"], returns: "jsonb" },
    {
      name: "invoice_aging",
      args: ["{id}", "text", "date"],
      returns: "jsonb",
    },
    ...(ctx.installed("quotes")
      ? [
          {
            name: "invoice_from_quote",
            args: ["uuid", "integer"],
            returns: "jsonb",
          },
        ]
      : []),
  ];
}

export const INVOICES: ModuleDefinition = {
  name: "invoices",
  title: "Invoices",
  description:
    "Invoices an organization sends its own customers: drafts with lines, a gapless number on issue, payments, credit notes, void and write-off, overdue and aging per currency, and invoices from accepted quotes.",
  requires: ["tenant", "access", "subjects"],
  integrates: [
    "outbox",
    "audit",
    "notifications",
    "number-sequences",
    "quotes",
    "relations",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
