import type { InvoicesEvents } from "../../blocks/invoices/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { InvoiceNames } from "./invoices-functions.ts";

import { guestOr } from "../guest-sql.ts";
import {
  lineTableSpec,
  TOTAL_COLUMNS,
  totalColumnsSql,
} from "../line-items-sql.ts";
import { addExtraColumns, schemaPreamble } from "../shared.ts";
import {
  invoiceFunctions,
  invoiceOrigin,
  invoiceParty,
} from "./invoices-functions.ts";
import { invoicePaymentsUpgrade } from "./invoices-ledger.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const INVOICE = [
  "organizationId",
  "invoiceId",
  "subjectType",
  "subjectId",
  "identifier",
] as const;

const EVENTS: BlockSqlEvents<InvoicesEvents> = {
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

const NAMES: BlockSqlNames = {
  entities: {
    invoice: {
      table: "invoices",
      singular: "invoice",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
  },
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
      app: {},
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
      optional: [
        "companyType",
        "companyId",
        "contactType",
        "contactId",
        "voidReason",
        "note",
        "originType",
        "originId",
        "depositBps",
        "createdBy",
      ],
      typed: ["status", "kind"],
    },
    lines: lineTableSpec("invoice_lines"),
  },
};

function tables(ctx: BlockSqlContext, n: InvoiceNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = n;
  const i = (column: string): string => c("invoices", column);
  const company = invoiceParty(ctx, "company");
  const contact = invoiceParty(ctx, "contact");
  const origin = invoiceOrigin(ctx);

  // A column definition, left out when the app maps the column to null.
  const column = (logical: string, definition: string): string =>
    ctx.has("invoices", logical) ? `\n  ${i(logical)} ${definition},` : "";

  const index = (name: string, columns: readonly string[]): string =>
    `\ncreate index if not exists ${ctx.naming.rename(name)} on ${t("invoices")} (${columns.map(i).join(", ")});`;

  return `
create table if not exists ${t("invoices")} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("kind")} text not null default 'invoice' check (${i("kind")} in ('invoice', 'credit_note')),
  ${i("number")} bigint,
  ${i("identifier")} text,
  ${i("original")} uuid references ${t("invoices")} (${i("id")}),
  ${i("title")} text not null check (length(${i("title")}) between 1 and 300),${column("companyType", "text")}${column("companyId", "text")}${column("contactType", "text")}${column("contactId", "text")}
  ${i("currency")} char(3) not null check (${i("currency")} ~ '^[A-Z]{3}$'),
  ${i("status")} text not null default 'draft' check (${i("status")} in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible')),
  ${i("termsDays")} integer not null default 30 check (${i("termsDays")} >= 0),
  ${i("issuedOn")} date,
  ${i("dueOn")} date,
  ${i("paidTotal")} bigint not null default 0,
  ${i("creditedTotal")} bigint not null default 0,
  ${i("paidAt")} timestamptz,
  ${i("voidedAt")} timestamptz,${column("voidReason", "text")}${column("note", "text")}${column("originType", "text")}${column("originId", "text")}${ctx.has("invoices", "depositBps") ? `\n  ${i("depositBps")} integer check (${i("depositBps")} > 0 and ${i("depositBps")} < 10000),` : ""}${column("createdBy", "uuid")}
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now(),
  ${totalColumnsSql(ctx, "invoices")},
  unique (${i("tenant")}, ${i("kind")}, ${i("number")}),
  check ((${i("kind")} = 'credit_note') = (${i("original")} is not null)),
  check (${i("status")} <> 'draft' or ${i("number")} is null),
  check (${i("status")} in ('draft', 'void') or ${i("number")} is not null)${company ? `,\n  check ((${i("companyType")} is null) = (${i("companyId")} is null))` : ""}
);
create index if not exists ${ctx.naming.rename("invoices_tenant_status_idx")} on ${t("invoices")} (${i("tenant")}, ${i("status")}, ${i("dueOn")});${origin ? index("invoices_origin_idx", ["originType", "originId"]) : ""}${index("invoices_original_idx", ["original"])}${company ? index("invoices_company_idx", ["companyType", "companyId"]) : ""}${addExtraColumns(t("invoices"), n.extras)}${appUniqueIndex(ctx, "invoices", ["tenant", "kind", "number"])}
${lockModuleTable(ctx, "invoices", { read: true })}
drop policy if exists ${ctx.naming.rename("invoices_read")} on ${t("invoices")};
create policy ${ctx.naming.rename("invoices_read")} on ${t("invoices")} for select to authenticated
using (${guestOr(ctx.scope.check(i("tenant"), n.read), [
    ctx.scope.guest(i("tenant"), "'invoice'", `${i("id")}::text`, "read"),
    ...(company
      ? [ctx.scope.guestParty(i("tenant"), i("companyType"), i("companyId"))]
      : []),
    ...(contact
      ? [ctx.scope.guestParty(i("tenant"), i("contactType"), i("contactId"))]
      : []),
  ])});

`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("invoices");
  const termsDays = ctx.number("termsDays", 30);

  if (!Number.isInteger(termsDays) || termsDays < 0) {
    throw new TypeError(
      "blocks.invoices.options.termsDays must be 0 or a positive integer",
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
    extras: ctx.extraColumns("invoices", [
      "lines",
      "payments",
      "balance",
      "overdue",
    ]),
  };

  return `${schemaPreamble(ctx)}
-- Invoices an organization sends its own customers: drafts with lines, a
-- number on issue, payments, credit notes, void and write-off, and aging.
${tables(ctx, n)}${invoiceFunctions(ctx, n)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
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
      args: ["uuid", "bigint", "text", "timestamptz", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "credit_invoice",
      args: ["uuid", "jsonb", "text"],
      returns: "jsonb",
    },
    { name: "void_invoice", args: ["uuid", "text"], returns: "jsonb" },
    { name: "write_off_invoice", args: ["uuid"], returns: "jsonb" },
    { name: "invoice_aging", args: ["{id}", "text", "date"], returns: "jsonb" },
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

export const INVOICES: BlockSqlDefinition = {
  name: "invoices",
  scopes: ["tenant"],
  title: "Invoices",
  description:
    "Invoices an organization sends its own customers: drafts with lines, a gapless number on issue, payments, credit notes, void and write-off, overdue and aging per currency, and invoices from accepted quotes.",
  requires: ["memberships", "permissions", "subjects", "ledger"],
  integrates: [
    "outbox",
    "audit",
    "notifications",
    "numbering",
    "quotes",
    "relations",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Moves invoice_payments onto ledger transactions with the same ids and drops the table.",
      sql: invoicePaymentsUpgrade,
    },
  ],
  names: NAMES,
  contract,
  build,
};
