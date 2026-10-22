import type { QuotesEvents } from "../../blocks/quotes/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { QuoteNames } from "./quotes-functions.ts";

import {
  lineTableSpec,
  TOTAL_COLUMNS,
  totalColumnsSql,
} from "../line-items-sql.ts";
import { addExtraColumns, lockTable, schemaPreamble } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import { quoteFunctions } from "./quotes-functions.ts";

const QUOTE = [
  "organizationId",
  "quoteId",
  "subjectType",
  "subjectId",
  "identifier",
] as const;

const EVENTS: BlockSqlEvents<QuotesEvents> = {
  "quote.created": { subject: "quotes", payload: [...QUOTE] },
  "quote.updated": { subject: "quotes", payload: [...QUOTE] },
  "quote.sent": { subject: "quotes", payload: [...QUOTE] },
  "quote.viewed": { subject: "quotes", payload: [...QUOTE] },
  "quote.accepted": {
    subject: "quotes",
    payload: [...QUOTE, "total", "currency", "byName"],
  },
  "quote.rejected": { subject: "quotes", payload: [...QUOTE, "note"] },
  "quote.changes_requested": { subject: "quotes", payload: [...QUOTE, "note"] },
  "quote.expired": { subject: "quotes", payload: [...QUOTE] },
  "quote.revised": { subject: "quotes", payload: [...QUOTE, "revisionId"] },
};

const NAMES: BlockSqlNames = {
  entities: {
    quote: {
      table: "quotes",
      singular: "quote",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
  },
  events: EVENTS,
  hooks: [
    "before_quote_send",
    "after_quote_send",
    "before_quote_accept",
    "after_quote_accept",
  ],
  options: ["company", "contact", "prefix", "validDays", "extraColumns"],
  tables: {
    quotes: {
      name: "quotes",
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        identifier: "identifier",
        revision: "revision",
        supersedes: "supersedes_id",
        title: "title",
        companyType: "company_type",
        companyId: "company_id",
        contactType: "contact_type",
        contactId: "contact_id",
        owner: "owner_user_id",
        currency: "currency",
        status: "status",
        validUntil: "valid_until",
        terms: "terms",
        note: "note",
        originType: "origin_type",
        originId: "origin_id",
        tokenHash: "token_hash",
        sentAt: "sent_at",
        viewedAt: "viewed_at",
        decidedAt: "decided_at",
        decidedBy: "decided_by",
        decisionNote: "decision_note",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        ...TOTAL_COLUMNS,
      },
    },
    lines: lineTableSpec("quote_lines"),
  },
};

function tables(ctx: BlockSqlContext, n: QuoteNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = n;
  const q = (column: string): string => c("quotes", column);

  return `
create table if not exists ${t("quotes")} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${ctx.idType} not null,
  ${q("number")} bigint not null,
  ${q("identifier")} text not null,
  ${q("revision")} integer not null default 1,
  ${q("supersedes")} uuid references ${t("quotes")} (${q("id")}) on delete set null,
  ${q("title")} text not null check (length(${q("title")}) between 1 and 300),
  ${q("companyType")} text,
  ${q("companyId")} text,
  ${q("contactType")} text,
  ${q("contactId")} text,
  ${q("owner")} uuid,
  ${q("currency")} char(3) not null check (${q("currency")} ~ '^[A-Z]{3}$'),
  ${q("status")} text not null default 'draft' check (${q("status")} in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')),
  ${q("validUntil")} date,
  ${q("terms")} text,
  ${q("note")} text,
  ${q("originType")} text,
  ${q("originId")} text,
  ${q("tokenHash")} text unique,
  ${q("sentAt")} timestamptz,
  ${q("viewedAt")} timestamptz,
  ${q("decidedAt")} timestamptz,
  ${q("decidedBy")} text,
  ${q("decisionNote")} text,
  ${q("createdBy")} uuid,
  ${q("createdAt")} timestamptz not null default now(),
  ${q("updatedAt")} timestamptz not null default now(),
  ${totalColumnsSql(ctx, "quotes")},
  unique (${q("tenant")}, ${q("number")}, ${q("revision")}),
  check ((${q("companyType")} is null) = (${q("companyId")} is null)),
  check ((${q("originType")} is null) = (${q("originId")} is null))
);
create index if not exists ${ctx.naming.rename("quotes_tenant_status_idx")} on ${t("quotes")} (${q("tenant")}, ${q("status")}, ${q("createdAt")} desc);
create index if not exists ${ctx.naming.rename("quotes_origin_idx")} on ${t("quotes")} (${q("originType")}, ${q("originId")});
create index if not exists ${ctx.naming.rename("quotes_supersedes_idx")} on ${t("quotes")} (${q("supersedes")});${addExtraColumns(t("quotes"), n.extras)}
${lockTable(t("quotes"), { read: true })}
drop policy if exists ${ctx.naming.rename("quotes_read")} on ${t("quotes")};
create policy ${ctx.naming.rename("quotes_read")} on ${t("quotes")} for select to authenticated
using (${ctx.scope.check(q("tenant"), n.read)});
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("quotes");
  const validDays = ctx.number("validDays", 30);

  if (!Number.isInteger(validDays) || validDays < 1) {
    throw new TypeError(
      "blocks.quotes.options.validDays must be a positive integer",
    );
  }

  const n: QuoteNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    manage: ctx.permission("manage", keys.manage),
    company: ctx.text("company", "company"),
    contact: ctx.text("contact", "person"),
    prefix: ctx.text("prefix", "Q-"),
    validDays,
    service: "(auth.role() = 'service_role')",
    // The keys a quote read returns next to its columns.
    extras: ctx.extraColumns("quotes", ["lines", "token", "fields"]),
  };

  return `${schemaPreamble(ctx)}
-- Quotes: line items and totals, a revision chain, sending with a public
-- link the customer accepts, rejects or asks changes through, and expiry.
${tables(ctx, n)}${quoteFunctions(ctx, n)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_quote",
      args: ["{id}", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    { name: "update_quote", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "set_quote_lines", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "send_quote", args: ["uuid"], returns: "jsonb" },
    {
      name: "decide_quote",
      args: ["uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "revise_quote", args: ["uuid"], returns: "jsonb" },
    { name: "public_quote", args: ["text"], returns: "jsonb" },
    {
      name: "respond_to_quote",
      args: ["text", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "expire_quotes", args: [], returns: "integer" },
    ...(ctx.installed("deals")
      ? [{ name: "quote_from_deal", args: ["uuid"], returns: "jsonb" }]
      : []),
  ];
}

export const QUOTES: BlockSqlDefinition = {
  name: "quotes",
  scopes: ["tenant"],
  title: "Quotes",
  description:
    "Quotes with line items and totals, a revision chain, a public link the customer accepts, rejects or asks changes through, expiry, and quotes from deals.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["outbox", "notifications", "numbering", "deals", "relations"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
