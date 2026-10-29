import type { QuotesEvents } from "../../blocks/quotes/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { QuoteNames } from "./quotes-functions.ts";

import { QUOTE_TO_ORDER } from "../../blocks/quotes/automations.ts";
import { sqlString } from "../../core/template.ts";
import { guestOr } from "../guest-sql.ts";
import {
  lineExtraColumns,
  lineTableSpec,
  TOTAL_COLUMNS,
  totalColumnsSql,
} from "../line-items-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  fail,
  schemaPreamble,
  triggerGrant,
} from "../shared.ts";
import { shippedAutomation } from "./automation-defaults.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";
import {
  quoteFunctions,
  quoteGuest,
  quoteOrigin,
  quoteParty,
} from "./quotes-functions.ts";
import { versionLinesOn } from "./quotes-kit.ts";

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
  "quote.sent": { subject: "quotes", payload: [...QUOTE, "revision"] },
  "quote.viewed": { subject: "quotes", payload: [...QUOTE] },
  "quote.accepted": {
    subject: "quotes",
    payload: [
      ...QUOTE,
      "total",
      "currency",
      "byName",
      "revision",
      "depositDue",
    ],
  },
  "quote.rejected": { subject: "quotes", payload: [...QUOTE, "note"] },
  "quote.changes_requested": { subject: "quotes", payload: [...QUOTE, "note"] },
  "quote.expired": { subject: "quotes", payload: [...QUOTE] },
  "quote.revised": { subject: "quotes", payload: [...QUOTE, "revision"] },
  "quote.withdrawn": { subject: "quotes", payload: [...QUOTE, "revision"] },
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
  options: [
    "company",
    "contact",
    "prefix",
    "validDays",
    "extraColumns",
    "lineExtraColumns",
    "lineRates",
    "workingCopy",
    "versionLines",
    "versionLineExtraColumns",
    "totals",
    "resend",
    "notifications",
  ],
  tables: {
    quotes: {
      name: "quotes",
      app: {},
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        identifier: "identifier",
        revision: "revision",
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
        decidedUser: "decided_user_id",
        decidedIp: "decided_ip",
        decidedUserAgent: "decided_user_agent",
        pricesIncludeTax: "prices_include_tax",
        discountBps: "discount_bps",
        discountAmount: "discount_amount",
        depositBps: "deposit_bps",
        depositAmount: "deposit_amount",
        depositRequired: "deposit_required",
        depositDue: "deposit_due",
        unpublishedChanges: "unpublished_changes",
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
        "terms",
        "note",
        "originType",
        "originId",
        "viewedAt",
        "decisionNote",
        "decidedUser",
        "decidedIp",
        "decidedUserAgent",
        "pricesIncludeTax",
        "discountBps",
        "discountAmount",
        "depositBps",
        "depositAmount",
        "depositRequired",
        "depositDue",
        "unpublishedChanges",
        "createdBy",
        "listTotal",
        "discountTotal",
      ],
      typed: ["status"],
    },
    lines: lineTableSpec("quote_lines", { document: true }),
    versions: {
      name: "quote_versions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        quote: "quote_id",
        revision: "revision",
        snapshot: "snapshot",
        total: "total",
        currency: "currency",
        publishedBy: "published_by",
        publishedAt: "published_at",
      },
      optional: ["publishedBy"],
    },
    versionLines: {
      name: "quote_version_lines",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        version: "version_id",
        position: "position",
        description: "description",
        quantity: "quantity",
        unitAmount: "unit_amount",
        periods: "periods",
        discountBps: "discount_bps",
        taxRateBps: "tax_rate_bps",
        taxCode: "tax_code",
        section: "section",
        optional: "optional",
        selected: "selected",
        productType: "product_type",
        productId: "product_id",
      },
      optional: [
        "periods",
        "discountBps",
        "taxRateBps",
        "taxCode",
        "section",
        "optional",
        "selected",
        "productType",
        "productId",
      ],
      typed: ["productType"],
    },
    taxLines: {
      name: "quote_tax_lines",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        parent: "parent_id",
        taxRateBps: "tax_rate_bps",
        taxCode: "tax_code",
        net: "net",
        tax: "tax",
        gross: "gross",
        discount: "discount",
      },
      optional: ["taxCode", "discount"],
    },
  },
};

function tables(ctx: BlockSqlContext, n: QuoteNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = n;
  const q = (column: string): string => c("quotes", column);
  const company = quoteParty(ctx, "company");
  const origin = quoteOrigin(ctx);

  // A column definition, left out when the app maps the column to null.
  const column = (
    logical: string,
    definition: string | ((name: string) => string),
  ): string =>
    ctx.has("quotes", logical)
      ? `\n  ${q(logical)} ${typeof definition === "string" ? definition : definition(q(logical))},`
      : "";

  // Columns a later version added, for quotes tables made before it.
  const later: readonly (readonly [string, (name: string) => string])[] = [
    ["depositAmount", (name) => `bigint check (${name} > 0)`],
    ["depositRequired", () => "boolean not null default false"],
    ["unpublishedChanges", () => "boolean not null default false"],
  ];

  const added = later
    .filter(([logical]) => ctx.has("quotes", logical))
    .map(
      ([logical, type]) =>
        `alter table ${t("quotes")} add column if not exists ${q(logical)} ${type(q(logical))};\n`,
    )
    .join("");

  const constraints = [
    `unique (${q("tenant")}, ${q("number")}, ${q("revision")})`,
    ...(company === "pair"
      ? [`check ((${q("companyType")} is null) = (${q("companyId")} is null))`]
      : []),
    ...(origin
      ? [`check ((${q("originType")} is null) = (${q("originId")} is null))`]
      : []),
  ];

  return `
create table if not exists ${t("quotes")} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${ctx.idType} not null,
  ${q("number")} bigint not null,
  ${q("identifier")} text not null,
  ${q("revision")} integer not null default 1,
  ${q("title")} text not null check (length(${q("title")}) between 1 and 300),${column("companyType", "text")}${column("companyId", "text")}${column("contactType", "text")}${column("contactId", "text")}
  ${q("owner")} uuid,
  ${q("currency")} char(3) not null check (${q("currency")} ~ '^[A-Z]{3}$'),
  ${q("status")} text not null default 'draft' check (${q("status")} in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')),
  ${q("validUntil")} date,${column("terms", "text")}${column("note", "text")}${column("originType", "text")}${column("originId", "text")}
  ${q("tokenHash")} text unique,
  ${q("sentAt")} timestamptz,${column("viewedAt", "timestamptz")}
  ${q("decidedAt")} timestamptz,
  ${q("decidedBy")} text,${column("decisionNote", "text")}${column("decidedUser", "uuid")}${column("decidedIp", "text")}${column("decidedUserAgent", "text")}${column("pricesIncludeTax", "boolean not null default false")}${column("discountBps", (bps) => `integer not null default 0 check (${bps} >= 0 and ${bps} <= 10000)`)}${column("discountAmount", (amount) => `bigint not null default 0 check (${amount} >= 0)`)}${column("depositBps", (bps) => `integer check (${bps} > 0 and ${bps} < 10000)`)}${column("depositAmount", (amount) => `bigint check (${amount} > 0)`)}${column("depositRequired", "boolean not null default false")}${column("depositDue", "bigint not null default 0")}${column("unpublishedChanges", "boolean not null default false")}${column("createdBy", "uuid")}
  ${q("createdAt")} timestamptz not null default now(),
  ${q("updatedAt")} timestamptz not null default now(),
  ${totalColumnsSql(ctx, "quotes")},
  ${constraints.join(",\n  ")}
);
${added}create index if not exists ${ctx.naming.rename("quotes_tenant_status_idx")} on ${t("quotes")} (${q("tenant")}, ${q("status")}, ${q("createdAt")} desc);${origin ? `\ncreate index if not exists ${ctx.naming.rename("quotes_origin_idx")} on ${t("quotes")} (${q("originType")}, ${q("originId")});` : ""}
${addExtraColumns(t("quotes"), n.extras)}${appUniqueIndex(ctx, "quotes", ["tokenHash"])}
${lockModuleTable(ctx, "quotes", { read: true })}
${renderPolicy(makePolicy({ table: t("quotes"), name: ctx.naming.rename("quotes_read"), command: "select", roles: ["authenticated"], using: guestOr(ctx.scope.check(q("tenant"), n.read), [quoteGuest(ctx, n, "")]) }), { drop: true, target: t("quotes") })}
${childTables(ctx, n)}`;
}

// The versions and tax lines of a quote, read through the quote's own policy.
// A version never changes once published.
function childTables(ctx: BlockSqlContext, n: QuoteNames): string {
  const { t, c } = n;
  const v = (column: string): string => c("versions", column);
  const x = (column: string): string => c("taxLines", column);

  const readable = (table: string, parent: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: ctx.naming.rename(`${ctx.tableName(table).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: `exists (select 1 from ${t("quotes")} q where q.${c("quotes", "id")} = ${parent})`,
      }),
      { drop: true, target: t(table) },
    );

  const frozen = ctx.trigger("quote_versions_frozen");
  const frozenFn = `better_supabase.${frozen.replaceAll('"', "")}()`;
  const vl = (column: string): string => c("versionLines", column);

  const vlColumn = (logical: string, definition: string): string =>
    ctx.has("versionLines", logical) ? `\n  ${vl(logical)} ${definition},` : "";

  const versionLines = versionLinesOn(ctx)
    ? `
create table if not exists ${t("versionLines")} (
  ${vl("id")} uuid primary key default gen_random_uuid(),
  ${vl("tenant")} ${ctx.idType} not null,
  ${vl("version")} uuid not null references ${t("versions")} (${v("id")}) on delete cascade,
  ${vl("position")} integer not null,
  ${vl("description")} text not null,
  ${vl("quantity")} numeric(18, 4) not null,
  ${vl("unitAmount")} bigint not null,${vlColumn("periods", "integer not null default 1")}${vlColumn("discountBps", "integer not null default 0")}${vlColumn("taxRateBps", "integer not null default 0")}${vlColumn("taxCode", "text")}${vlColumn("section", "text")}${vlColumn("optional", "boolean not null default false")}${vlColumn("selected", "boolean not null default true")}${vlColumn("productType", "text")}${vlColumn("productId", "text")}
  unique (${vl("version")}, ${vl("position")})
);${addExtraColumns(t("versionLines"), n.versionLineExtras)}
${lockModuleTable(ctx, "versionLines", { read: true })}
${renderPolicy(
  makePolicy({
    table: t("versionLines"),
    name: ctx.naming.rename(`${ctx.tableName("versionLines").name}_read`),
    command: "select",
    roles: ["authenticated"],
    using: `exists (select 1 from ${t("versions")} v where v.${v("id")} = ${vl("version")})`,
  }),
  { drop: true, target: t("versionLines") },
)}
drop trigger if exists ${frozen} on ${t("versionLines")};
create trigger ${frozen} before update on ${t("versionLines")}
for each row execute function ${frozenFn};
`
    : "";

  const taxLines = ctx.hasTable("taxLines")
    ? `
create table if not exists ${t("taxLines")} (
  ${x("id")} uuid primary key default gen_random_uuid(),
  ${x("tenant")} ${ctx.idType} not null,
  ${x("parent")} uuid not null references ${t("quotes")} (${c("quotes", "id")}) on delete cascade,
  ${x("taxRateBps")} integer not null,${ctx.has("taxLines", "taxCode") ? `\n  ${x("taxCode")} text,` : ""}
  ${x("net")} bigint not null,
  ${x("tax")} bigint not null,
  ${x("gross")} bigint not null${ctx.has("taxLines", "discount") ? `,\n  ${x("discount")} bigint not null default 0` : ""}
);
create index if not exists ${ctx.naming.rename("quote_tax_lines_parent_idx")} on ${t("taxLines")} (${x("parent")});
${lockModuleTable(ctx, "taxLines", { read: true })}
${readable("taxLines", x("parent"))}
`
    : "";

  return `
create table if not exists ${t("versions")} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("tenant")} ${ctx.idType} not null,
  ${v("quote")} uuid not null references ${t("quotes")} (${c("quotes", "id")}) on delete cascade,
  ${v("revision")} integer not null,
  ${v("snapshot")} jsonb not null,
  ${v("total")} bigint not null,
  ${v("currency")} char(3) not null,${ctx.has("versions", "publishedBy") ? `\n  ${v("publishedBy")} uuid,` : ""}
  ${v("publishedAt")} timestamptz not null default now(),
  unique (${v("quote")}, ${v("revision")})
);
${lockModuleTable(ctx, "versions", { read: true })}
${readable("versions", v("quote"))}
create or replace function better_supabase.${frozen.replaceAll('"', "")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  ${fail("QUOTE_VERSION_FROZEN", "a published quote version never changes", "55000")}
end;
$$;
${triggerGrant(`better_supabase.${frozen.replaceAll('"', "")}()`)}
drop trigger if exists ${frozen} on ${t("versions")};
create trigger ${frozen} before update on ${t("versions")}
for each row execute function better_supabase.${frozen.replaceAll('"', "")}();
${versionLines}${taxLines}`;
}

/** `options.totals`: who keeps a quote's totals. */
function quoteTotals(ctx: BlockSqlContext): "block" | "app" {
  const totals = ctx.text("totals", "block");

  if (totals !== "block" && totals !== "app") {
    throw new TypeError(
      'blocks.quotes.options.totals must be "block" or "app"',
    );
  }

  return totals;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("quotes");

  const finer = (action: string): string =>
    sqlString(
      ctx.config.permissions[action] ?? ctx.permissionKey("write", keys.write),
    );

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
    send: finer("send"),
    decide: finer("decide"),
    withdraw: finer("withdraw"),
    company: ctx.text("company", "company"),
    contact: ctx.text("contact", "person"),
    prefix: ctx.text("prefix", "Q-"),
    validDays,
    service: "(auth.role() = 'service_role')",
    // The keys a quote read returns next to its columns.
    extras: ctx.extraColumns("quotes", ["lines", "token", "fields"]),
    lineExtras: lineExtraColumns(ctx),
    versionLineExtras: versionLinesOn(ctx)
      ? ctx.extraColumns("versionLines", [], "versionLineExtraColumns")
      : [],
    appTotals: quoteTotals(ctx) === "app",
    resend: ctx.flag("resend", false),
  };

  return `${schemaPreamble(ctx)}
-- Quotes: line items, sections, optional lines, discounts and tax per rate,
-- published versions, sending with a public link or to the signed-in portal
-- the customer accepts, rejects or asks changes through, and expiry.
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
    { name: "send_quote", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "decide_quote",
      args: ["uuid", "text", "text", "text", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    { name: "revise_quote", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "withdraw_quote",
      args: ["uuid", "jsonb", "text"],
      returns: "jsonb",
    },
    { name: "quote_versions", args: ["uuid"], returns: "jsonb" },
    { name: "quote_version", args: ["uuid", "integer"], returns: "jsonb" },
    { name: "portal_quote", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "respond_to_portal_quote",
      args: ["uuid", "text", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "public_quote", args: ["text"], returns: "jsonb" },
    {
      name: "respond_to_quote",
      args: ["text", "text", "text", "text", "jsonb"],
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
    "Quotes with sections, optional lines, discounts, prices with or without tax, tax per rate and a deposit; published versions; a public link or the signed-in portal the customer accepts, rejects or asks changes through; expiry; and quotes from deals. With catalog, a line that names a product variant takes its price and title.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: [
    "outbox",
    "notifications",
    "numbering",
    "deals",
    "relations",
    "catalog",
    "automations",
    "orders",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "With catalog, set_quote_lines prices a line that names a product variant and has no unitAmount from the catalog, in the quote's currency, and titles it when it has no description.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "A quote is one working copy: send_quote publishes an immutable snapshot to quote_versions and revise_quote reopens the same quote at the next revision, so supersedes_id goes and an accepted quote can't be revised (QUOTE_ACCEPTED). Quotes gain prices_include_tax, a document discount (discount_bps, discount_amount), a deposit (deposit_bps, deposit_due) and the answer's user, address and browser; lines gain section, optional and selected; quote_tax_lines keeps the tax per rate. decide_quote and respond_to_quote take the selected optional lines, and portal_quote and respond_to_portal_quote serve signed-in guests. Earlier revisions made before the upgrade stay as their own quotes.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
  data: (ctx) =>
    shippedAutomation(ctx, QUOTE_TO_ORDER, {
      module: "orders",
      singular: "order",
    }),
};
