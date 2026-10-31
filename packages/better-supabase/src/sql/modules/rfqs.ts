import type { RfqsEvents } from "../../blocks/rfqs/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { rfqsFunctions } from "./rfqs-functions.ts";
import { rfqsQuoteFunctions } from "./rfqs-quote-functions.ts";
import { rfqsSql } from "./rfqs-sql.ts";
import {
  RFQ_QUOTE_STATUSES,
  RFQ_STATUSES,
  RFQ_SUPPLIER_STATUSES,
} from "./rfqs-values.ts";

const rfq = {
  subject: "rfqs",
  payload: ["organizationId", "id", "number", "status"],
} as const;

const awarded = {
  subject: "rfqs",
  payload: [
    "organizationId",
    "id",
    "number",
    "status",
    "quoteId",
    "purchaseOrderId",
  ],
} as const;

const quote = {
  subject: "rfqs",
  payload: ["organizationId", "id", "rfqId", "invitationId", "total"],
} as const;

const EVENTS: BlockSqlEvents<RfqsEvents> = {
  "rfq.created": rfq,
  "rfq.opened": rfq,
  "rfq.closed": rfq,
  "rfq.awarded": awarded,
  "rfq.cancelled": rfq,
  "rfq_quote.submitted": quote,
  "rfq_quote.withdrawn": quote,
};

const NAMES: BlockSqlNames = {
  entities: {
    rfq: {
      table: "rfqs",
      singular: "rfq",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
    rfq_line: { table: "lines", singular: "rfq_line" },
    rfq_supplier: { table: "suppliers", singular: "rfq_supplier" },
    rfq_quote: { table: "quotes", singular: "rfq_quote" },
    rfq_quote_line: { table: "quoteLines", singular: "rfq_quote_line" },
  },
  events: EVENTS,
  hooks: [
    "before_rfq_create",
    "after_rfq_create",
    "before_rfq_quote_record",
    "after_rfq_quote_record",
    "before_rfq_award",
    "after_rfq_award",
  ],
  options: [],
  tables: {
    rfqs: {
      name: "rfqs",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        sequence: "sequence",
        title: "title",
        status: "status",
        currency: "currency",
        dueAt: "due_at",
        notes: "notes",
        awardedQuote: "awarded_quote_id",
        purchaseOrder: "purchase_order_id",
        cancelReason: "cancel_reason",
        openedAt: "opened_at",
        closedAt: "closed_at",
        awardedAt: "awarded_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    lines: {
      name: "rfq_lines",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        rfq: "rfq_id",
        ordinal: "ordinal",
        description: "description",
        variant: "variant_id",
        quantity: "quantity",
        unit: "unit",
      },
    },
    suppliers: {
      name: "rfq_suppliers",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        rfq: "rfq_id",
        supplierType: "supplier_type",
        supplierId: "supplier_id",
        status: "status",
        invitedAt: "invited_at",
        respondedAt: "responded_at",
      },
    },
    quotes: {
      name: "rfq_quotes",
      app: {},
      lifecycle: { tenant: "tenant", user: "submittedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        rfq: "rfq_id",
        invitation: "invitation_id",
        status: "status",
        total: "total_amount",
        leadTimeDays: "lead_time_days",
        validUntil: "valid_until",
        notes: "notes",
        revision: "revision",
        submittedBy: "submitted_by",
        submittedAt: "submitted_at",
        updatedAt: "updated_at",
      },
    },
    quoteLines: {
      name: "rfq_quote_lines",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        quote: "quote_id",
        line: "line_id",
        unitAmount: "unit_amount",
        leadTimeDays: "lead_time_days",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const sql = rfqsSql(ctx);
  const { q, l, s, k, u } = sql;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  // A cascading foreign key, unless the parent is an adopted app table.
  const ref = (parent: string, id: string): string =>
    ctx.owns(parent)
      ? ` references ${ctx.table(parent)} (${id}) on delete cascade`
      : "";

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, sql.read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  return `
-- A request for quotation sent to suppliers. The number is RFQ-1, RFQ-2 and so
-- on, or the numbering block's format. awarded_quote_id and purchase_order_id
-- are set when the request is awarded.
create table if not exists ${sql.rfqs} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${ctx.idType} not null,
  ${q("number")} text not null,
  ${q("sequence")} bigint not null,
  ${q("title")} text not null check (length(${q("title")}) between 1 and 200),
  ${q("status")} text not null default 'draft' check (${q("status")} in (${list(RFQ_STATUSES)})),
  ${q("currency")} text not null check (${q("currency")} ~ '^[A-Z]{3}$'),
  ${q("dueAt")} timestamptz,
  ${q("notes")} text check (${q("notes")} is null or length(${q("notes")}) <= 4000),
  ${q("awardedQuote")} uuid,
  ${q("purchaseOrder")} uuid,
  ${q("cancelReason")} text check (${q("cancelReason")} is null or length(${q("cancelReason")}) <= 500),
  ${q("openedAt")} timestamptz,
  ${q("closedAt")} timestamptz,
  ${q("awardedAt")} timestamptz,
  ${q("createdBy")} uuid,
  ${q("createdAt")} timestamptz not null default now(),
  ${q("updatedAt")} timestamptz not null default now(),
  unique (${q("tenant")}, ${q("sequence")})
);${appKey("rfqs", "tenant_id", `${q("tenant")}, ${q("id")}`)}
create index if not exists ${name("rfqs", "status_idx")} on ${sql.rfqs} (${q("tenant")}, ${q("status")});
${lockTable(sql.rfqs, { read: true })}
${readPolicy("rfqs", q("tenant"))}

-- What is requested: a description, optionally a product variant of the
-- inventory block (needed to award into a purchase order), and a quantity.
create table if not exists ${sql.lines} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("rfq")} uuid not null${ref("rfqs", q("id"))},
  ${l("ordinal")} integer not null check (${l("ordinal")} > 0),
  ${l("description")} text not null check (length(${l("description")}) between 1 and 500),
  ${l("variant")} uuid,
  ${l("quantity")} numeric not null check (${l("quantity")} > 0),
  ${l("unit")} text check (${l("unit")} is null or length(${l("unit")}) <= 40),
  unique (${l("rfq")}, ${l("ordinal")})
);${appKey("lines", "tenant_id", `${l("tenant")}, ${l("id")}`)}
${lockTable(sql.lines, { read: true })}
${readPolicy("lines", l("tenant"))}

-- A supplier invited to quote. supplier_type and supplier_id name a contacts
-- party (or another config.subjects record without the contacts block).
create table if not exists ${sql.suppliers} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("rfq")} uuid not null${ref("rfqs", q("id"))},
  ${s("supplierType")} text not null check (length(${s("supplierType")}) between 1 and 100),
  ${s("supplierId")} text not null check (length(${s("supplierId")}) between 1 and 200),
  ${s("status")} text not null default 'invited' check (${s("status")} in (${list(RFQ_SUPPLIER_STATUSES)})),
  ${s("invitedAt")} timestamptz not null default now(),
  ${s("respondedAt")} timestamptz,
  unique (${s("rfq")}, ${s("supplierType")}, ${s("supplierId")})
);${appKey("suppliers", "tenant_id", `${s("tenant")}, ${s("id")}`)}
${lockTable(sql.suppliers, { read: true })}
${readPolicy("suppliers", s("tenant"))}

-- A supplier's answer. One quote per invitation; recording again replaces its
-- prices and raises the revision. total_amount is minor units of the request's
-- currency.
create table if not exists ${sql.quotes} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("rfq")} uuid not null${ref("rfqs", q("id"))},
  ${k("invitation")} uuid not null${ref("suppliers", s("id"))},
  ${k("status")} text not null default 'submitted' check (${k("status")} in (${list(RFQ_QUOTE_STATUSES)})),
  ${k("total")} bigint not null check (${k("total")} >= 0),
  ${k("leadTimeDays")} integer check (${k("leadTimeDays")} is null or ${k("leadTimeDays")} >= 0),
  ${k("validUntil")} date,
  ${k("notes")} text check (${k("notes")} is null or length(${k("notes")}) <= 4000),
  ${k("revision")} integer not null default 1,
  ${k("submittedBy")} uuid,
  ${k("submittedAt")} timestamptz not null default now(),
  ${k("updatedAt")} timestamptz not null default now(),
  unique (${k("rfq")}, ${k("invitation")})
);${appKey("quotes", "tenant_id", `${k("tenant")}, ${k("id")}`)}
${lockTable(sql.quotes, { read: true })}
${readPolicy("quotes", k("tenant"))}

-- The unit price of one requested line in a quote, in minor units. A quote
-- need not price every line, but only a complete quote can be awarded.
create table if not exists ${sql.quoteLines} (
  ${u("id")} uuid primary key default gen_random_uuid(),
  ${u("tenant")} ${ctx.idType} not null,
  ${u("quote")} uuid not null${ref("quotes", k("id"))},
  ${u("line")} uuid not null${ref("lines", l("id"))},
  ${u("unitAmount")} bigint not null check (${u("unitAmount")} >= 0),
  ${u("leadTimeDays")} integer check (${u("leadTimeDays")} is null or ${u("leadTimeDays")} >= 0),
  unique (${u("quote")}, ${u("line")})
);${appKey("quoteLines", "tenant_id", `${u("tenant")}, ${u("id")}`)}
${lockTable(sql.quoteLines, { read: true })}
${readPolicy("quoteLines", u("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Requests for quotation: lines to price, invited suppliers, their quotes, a
-- comparison and an award that can create the purchase order.
${tables(ctx)}
${rfqsFunctions(ctx)}
${rfqsQuoteFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "create_rfq", args: ["{id}", "jsonb", "jsonb"], returns: "jsonb" },
    { name: "update_rfq", args: ["uuid", "jsonb", "jsonb"], returns: "jsonb" },
    { name: "get_rfq", args: ["uuid"], returns: "jsonb" },
    { name: "list_rfqs", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "invite_rfq_supplier",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "decline_rfq_supplier", args: ["uuid"], returns: "jsonb" },
    { name: "open_rfq", args: ["uuid"], returns: "jsonb" },
    {
      name: "record_rfq_quote",
      args: ["uuid", "uuid", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    { name: "withdraw_rfq_quote", args: ["uuid"], returns: "jsonb" },
    { name: "close_rfq", args: ["uuid"], returns: "jsonb" },
    { name: "compare_rfq", args: ["uuid"], returns: "jsonb" },
    { name: "award_rfq", args: ["uuid", "uuid", "uuid"], returns: "jsonb" },
    { name: "cancel_rfq", args: ["uuid", "text"], returns: "jsonb" },
  ];
}

export const RFQS: BlockSqlDefinition = {
  name: "rfqs",
  scopes: ["tenant"],
  title: "Requests for quotation",
  description:
    "Requests for quotation to invited suppliers, their quotes per line, a side by side comparison and an award that marks the winner and can create the purchase order.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["contacts", "inventory", "numbering", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
