import type { FundingEvents } from "../../blocks/funding/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, schemaPreamble } from "../shared.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { fundingClaimFunctions, invoicesClaims } from "./funding-claims.ts";
import { fundingFunctions } from "./funding-functions.ts";
import {
  AWARD_RESERVED,
  AWARD_STATUSES,
  CLAIM_STATUSES,
  claimFormats,
  DELIVERY_SOURCES,
  DELIVERY_STATUSES,
  fromTime,
  fundingKeys,
  LINE_STATUSES,
  PERIODS,
  sqlList,
  timeCategory,
  UNITS,
} from "./funding-shared.ts";
import { fundingTimeFunctions } from "./funding-time.ts";
import { lockModuleTable } from "./over-app.ts";

const AWARD = [
  "organizationId",
  "fundingAwardId",
  "fundingProductId",
  "funderId",
  "subjectType",
  "subjectId",
  "status",
] as const;

const CLAIM = [
  "organizationId",
  "fundingClaimId",
  "funderId",
  "number",
  "status",
  "periodStart",
  "periodEnd",
  "total",
  "currency",
] as const;

const EVENTS: BlockSqlEvents<FundingEvents> = {
  "funding_award.created": { subject: "funding-awards", payload: AWARD },
  "funding_award.updated": { subject: "funding-awards", payload: AWARD },
  "funding_award.ended": {
    subject: "funding-awards",
    payload: [...AWARD, "endsOn"],
  },
  "funding_award.exceeded": {
    subject: "funding-awards",
    payload: [...AWARD, "periodStart", "awarded", "used"],
  },
  "funding_delivery.registered": {
    subject: "funding-awards",
    payload: [
      "organizationId",
      "fundingAwardId",
      "fundingDeliveryId",
      "subjectType",
      "subjectId",
      "sourceType",
      "sourceId",
      "deliveredOn",
      "units",
    ],
  },
  "funding_claim.created": { subject: "funding-claims", payload: CLAIM },
  "funding_claim.sent": {
    subject: "funding-claims",
    payload: [...CLAIM, "externalRef"],
  },
  "funding_claim.responded": { subject: "funding-claims", payload: CLAIM },
  "funding_claim.deleted": { subject: "funding-claims", payload: CLAIM },
};

const NAMES: BlockSqlNames = {
  entities: {
    funding_product: { table: "products", singular: "funding_product" },
    funding_award: {
      table: "awards",
      singular: "funding_award",
      primary: true,
    },
    funding_delivery: { table: "deliveries", singular: "funding_delivery" },
    funding_claim: { table: "claims", singular: "funding_claim" },
    funding_claim_line: { table: "claimLines", singular: "funding_claim_line" },
  },
  events: EVENTS,
  hooks: [
    "before_funding_award_save",
    "after_funding_award_save",
    "before_funding_delivery_register",
    "after_funding_delivery_register",
    "before_funding_claim_build",
    "after_funding_claim_build",
  ],
  options: ["formats", "timeCategory", "extraColumns"],
  tables: {
    products: {
      name: "funding_products",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        code: "code",
        title: "title",
        unit: "unit",
        rate: "rate",
        currency: "currency",
        validFrom: "valid_from",
        validUntil: "valid_until",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["createdAt", "updatedAt"],
    },
    awards: {
      name: "funding_awards",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        funder: "funder_id",
        product: "product_id",
        units: "units",
        period: "period",
        startsOn: "starts_on",
        endsOn: "ends_on",
        reference: "reference",
        status: "status",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["createdBy", "createdAt", "updatedAt"],
    },
    deliveries: {
      name: "funding_deliveries",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        award: "award_id",
        sourceType: "source_type",
        sourceId: "source_id",
        deliveredOn: "delivered_on",
        units: "units",
        performer: "performer_id",
        status: "status",
        claimLine: "claim_line_id",
        note: "note",
        createdAt: "created_at",
      },
      optional: ["note", "createdAt"],
    },
    claims: {
      name: "funding_claims",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        funder: "funder_id",
        number: "number",
        periodStart: "period_start",
        periodEnd: "period_end",
        format: "format",
        status: "status",
        externalRef: "external_ref",
        sentAt: "sent_at",
        payloadSha256: "payload_sha256",
        response: "response",
        total: "total",
        currency: "currency",
        invoice: "invoice_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["invoice", "createdBy", "createdAt", "updatedAt"],
    },
    claimLines: {
      name: "funding_claim_lines",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        claim: "claim_id",
        award: "award_id",
        product: "product_id",
        units: "units",
        amount: "amount",
        status: "status",
        rejectionCode: "rejection_code",
      },
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const products = ctx.table("products");
  const awards = ctx.table("awards");
  const deliveries = ctx.table("deliveries");
  const claims = ctx.table("claims");
  const lines = ctx.table("claimLines");
  const p = (column: string): string => ctx.col("products", column);
  const w = (column: string): string => ctx.col("awards", column);
  const d = (column: string): string => ctx.col("deliveries", column);
  const c = (column: string): string => ctx.col("claims", column);
  const l = (column: string): string => ctx.col("claimLines", column);
  const { read } = fundingKeys(ctx);
  const canSubject = ctx.of("subjects").fn("can_subject");

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const stamps = (logical: string, columns: readonly string[]): string =>
    columns
      .map((column) =>
        opt(
          logical,
          column,
          () =>
            `${ctx.col(logical, column)} timestamptz not null default now()`,
        ),
      )
      .join("");

  const readPolicy = (logical: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  return `
create table if not exists ${products} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  -- The funder's product code, such as 45A48 for a Wlz product.
  ${p("code")} text not null check (length(${p("code")}) between 1 and 50),
  ${p("title")} text not null check (length(${p("title")}) between 1 and 300),
  ${p("unit")} text not null check (${p("unit")} in ${sqlList(UNITS)}),
  -- The price of one unit, in minor units of currency.
  ${p("rate")} bigint not null check (${p("rate")} >= 0),
  ${p("currency")} char(3) not null check (${p("currency")} ~ '^[A-Z]{3}$'),
  ${p("validFrom")} date,
  ${p("validUntil")} date,${stamps("products", ["createdAt", "updatedAt"])}
  check (${p("validUntil")} is null or ${p("validFrom")} is null or ${p("validUntil")} >= ${p("validFrom")}),
  unique (${p("tenant")}, ${p("id")})
);${appKey("products", "tenant_id", `${p("tenant")}, ${p("id")}`)}
create unique index if not exists ${name("products", "code_idx")} on ${products} (${p("tenant")}, ${p("code")});
${lockModuleTable(ctx, "products", { read: true })}
${readPolicy("products", ctx.scope.check(p("tenant"), read))}

create table if not exists ${awards} (
  ${w("id")} uuid primary key default gen_random_uuid(),
  ${w("tenant")} ${ctx.idType} not null,
  -- The record the award is for, a type in config.subjects.
  ${w("subjectType")} text not null,
  ${w("subjectId")} text not null,
  -- The contacts company or person that pays, holding the funder role.
  ${w("funder")} uuid not null,
  ${w("product")} uuid not null,
  -- The units awarded per period.
  ${w("units")} numeric not null check (${w("units")} > 0),
  ${w("period")} text not null check (${w("period")} in ${sqlList(PERIODS)}),
  ${w("startsOn")} date not null,
  ${w("endsOn")} date,
  -- The funder's reference for the award, such as an indication number.
  ${w("reference")} text check (${w("reference")} is null or length(${w("reference")}) <= 200),
  ${w("status")} text not null default 'active' check (${w("status")} in ${sqlList(AWARD_STATUSES)}),${opt("awards", "createdBy", () => `${w("createdBy")} uuid`)}${stamps("awards", ["createdAt", "updatedAt"])}
  check (${w("endsOn")} is null or ${w("endsOn")} >= ${w("startsOn")}),
  unique (${w("tenant")}, ${w("id")}),
  foreign key (${w("tenant")}, ${w("product")}) references ${products} (${p("tenant")}, ${p("id")})
);${addExtraColumns(awards, ctx.extraColumns("awards", AWARD_RESERVED))}${appKey("awards", "tenant_id", `${w("tenant")}, ${w("id")}`)}
create index if not exists ${name("awards", "product_idx")} on ${awards} (${w("tenant")}, ${w("product")});
create index if not exists ${name("awards", "subject_idx")} on ${awards} (${w("subjectType")}, ${w("subjectId")});
create index if not exists ${name("awards", "funder_idx")} on ${awards} (${w("tenant")}, ${w("funder")}, ${w("status")});
${lockModuleTable(ctx, "awards", { read: true })}
${readPolicy("awards", `${ctx.scope.check(w("tenant"), read)} and coalesce(${canSubject}(${w("subjectType")}, ${w("subjectId")}, 'read'), false)`)}

create table if not exists ${claims} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("funder")} uuid not null,
  ${c("number")} text not null check (length(${c("number")}) between 1 and 100),
  ${c("periodStart")} date not null,
  ${c("periodEnd")} date not null,
  -- The FundingClaimFormat key that renders the claim, such as iwlz-aw319.
  ${c("format")} text not null check (${c("format")} ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  ${c("status")} text not null default 'draft' check (${c("status")} in ${sqlList(CLAIM_STATUSES)}),
  -- The funder's or the channel's reference for the sent claim.
  ${c("externalRef")} text check (${c("externalRef")} is null or length(${c("externalRef")}) <= 200),
  ${c("sentAt")} timestamptz,
  -- The SHA-256 of the rendered file that was sent, in hex.
  ${c("payloadSha256")} text check (${c("payloadSha256")} is null or ${c("payloadSha256")} ~ '^[0-9a-f]{64}$'),
  -- The funder's response as the format parsed it.
  ${c("response")} jsonb,
  ${c("total")} bigint not null default 0,
  ${c("currency")} char(3) not null check (${c("currency")} ~ '^[A-Z]{3}$'),${opt("claims", "invoice", () => `${c("invoice")} uuid`)}${opt("claims", "createdBy", () => `${c("createdBy")} uuid`)}${stamps("claims", ["createdAt", "updatedAt"])}
  check (${c("periodEnd")} >= ${c("periodStart")}),
  unique (${c("tenant")}, ${c("id")})
);${appKey("claims", "tenant_id", `${c("tenant")}, ${c("id")}`)}
create unique index if not exists ${name("claims", "number_idx")} on ${claims} (${c("tenant")}, ${c("number")});
create index if not exists ${name("claims", "funder_idx")} on ${claims} (${c("tenant")}, ${c("funder")}, ${c("status")});
${lockModuleTable(ctx, "claims", { read: true })}
${readPolicy("claims", ctx.scope.check(c("tenant"), read))}

create table if not exists ${lines} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("claim")} uuid not null,
  ${l("award")} uuid not null,
  ${l("product")} uuid not null,
  ${l("units")} numeric not null check (${l("units")} > 0),
  -- The units times the product rate, in minor units of the claim currency.
  ${l("amount")} bigint not null,
  ${l("status")} text not null default 'pending' check (${l("status")} in ${sqlList(LINE_STATUSES)}),
  -- The funder's code for a rejected line.
  ${l("rejectionCode")} text check (${l("rejectionCode")} is null or length(${l("rejectionCode")}) <= 100),
  foreign key (${l("tenant")}, ${l("claim")}) references ${claims} (${c("tenant")}, ${c("id")}) on delete cascade,
  foreign key (${l("tenant")}, ${l("award")}) references ${awards} (${w("tenant")}, ${w("id")}),
  foreign key (${l("tenant")}, ${l("product")}) references ${products} (${p("tenant")}, ${p("id")})
);
create index if not exists ${name("claimLines", "claim_idx")} on ${lines} (${l("tenant")}, ${l("claim")});
create index if not exists ${name("claimLines", "award_idx")} on ${lines} (${l("tenant")}, ${l("award")});
create index if not exists ${name("claimLines", "product_idx")} on ${lines} (${l("tenant")}, ${l("product")});
${lockModuleTable(ctx, "claimLines", { read: true })}
${readPolicy("claimLines", ctx.scope.check(l("tenant"), read))}

create table if not exists ${deliveries} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("award")} uuid not null,
  -- Where the delivery came from; source_id is the time entry or booking id.
  ${d("sourceType")} text not null default 'manual' check (${d("sourceType")} in ${sqlList(DELIVERY_SOURCES)}),
  ${d("sourceId")} text check (${d("sourceId")} is null or length(${d("sourceId")}) <= 200),
  ${d("deliveredOn")} date not null,
  ${d("units")} numeric not null check (${d("units")} > 0),
  ${d("performer")} uuid,
  ${d("status")} text not null default 'registered' check (${d("status")} in ${sqlList(DELIVERY_STATUSES)}),
  -- The claim line that claims it, once a claim gathered it.
  ${d("claimLine")} uuid references ${lines} (${l("id")}) on delete set null,${opt("deliveries", "note", () => `${d("note")} text check (${d("note")} is null or length(${d("note")}) <= 2000)`)}${stamps("deliveries", ["createdAt"])}
  check (${d("sourceType")} = 'manual' or ${d("sourceId")} is not null),
  foreign key (${d("tenant")}, ${d("award")}) references ${awards} (${w("tenant")}, ${w("id")}) on delete cascade
);
create index if not exists ${name("deliveries", "award_idx")} on ${deliveries} (${d("tenant")}, ${d("award")}, ${d("deliveredOn")});
create index if not exists ${name("deliveries", "status_idx")} on ${deliveries} (${d("tenant")}, ${d("status")}, ${d("deliveredOn")});
create index if not exists ${name("deliveries", "claim_line_idx")} on ${deliveries} (${d("claimLine")});
create unique index if not exists ${name("deliveries", "source_idx")} on ${deliveries} (${d("tenant")}, ${d("sourceType")}, ${d("sourceId")}) where ${d("sourceId")} is not null;
${lockModuleTable(ctx, "deliveries", { read: true })}
${readPolicy("deliveries", `${ctx.scope.check(d("tenant"), read)} and exists (select 1 from ${awards} x where x.${w("tenant")} = ${d("tenant")} and x.${w("id")} = ${d("award")} and coalesce(${canSubject}(x.${w("subjectType")}, x.${w("subjectId")}, 'read'), false))`)}
`;
}

/** Moves the awards of a merged record to the record it merged into. */
function awardMerges(ctx: BlockSqlContext): string {
  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  return subjectMergeHandler(
    ctx,
    subjects,
    moveSubjectRows(
      {
        table: ctx.table("awards"),
        type: ctx.col("awards", "subjectType"),
        id: ctx.col("awards", "subjectId"),
      },
      "v_type",
    ),
  );
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  claimFormats(ctx);
  timeCategory(ctx);

  return `${schemaPreamble(ctx)}
-- Funding: the products a funder pays for, awards of units per period to a
-- record, the care delivered against them, and claims to the funder with its
-- response per line.
${tables(ctx)}${fundingFunctions(ctx)}${fundingTimeFunctions(ctx)}${fundingClaimFunctions(ctx)}${awardMerges(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_funding_product",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "bigint",
        "text",
        "date",
        "date",
        "uuid",
      ],
      returns: "jsonb",
    },
    {
      name: "list_funding_products",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "save_funding_award",
      args: ["{id}", "text", "text", "jsonb", "uuid"],
      returns: "jsonb",
    },
    {
      name: "end_funding_award",
      args: ["uuid", "date", "boolean"],
      returns: "jsonb",
    },
    {
      name: "list_funding_awards",
      args: ["{id}", "text", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "funding_award_usage", args: ["uuid"], returns: "jsonb" },
    {
      name: "register_funding_delivery",
      args: ["uuid", "date", "numeric", "text", "text", "uuid", "text"],
      returns: "jsonb",
    },
    ...(fromTime(ctx)
      ? [
          {
            name: "register_funding_deliveries_from_time",
            args: ["{id}", "date", "date"],
            returns: "jsonb",
          },
        ]
      : []),
    {
      name: "approve_funding_deliveries",
      args: ["uuid[]", "boolean"],
      returns: "integer",
    },
    {
      name: "list_funding_deliveries",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "build_funding_claim",
      args: ["{id}", "uuid", "date", "date", "text"],
      returns: "jsonb",
    },
    { name: "get_funding_claim", args: ["uuid"], returns: "jsonb" },
    {
      name: "mark_funding_claim_sent",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "record_funding_claim_response",
      args: ["uuid", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_funding_claim", args: ["uuid"], returns: "boolean" },
    ...(invoicesClaims(ctx)
      ? [
          {
            name: "invoice_funding_claim",
            args: ["uuid", "jsonb"],
            returns: "jsonb",
          },
        ]
      : []),
    {
      name: "list_funding_claims",
      args: ["{id}", "text", "uuid"],
      returns: "jsonb",
    },
  ];
}

export const FUNDING: BlockSqlDefinition = {
  name: "funding",
  scopes: ["tenant"],
  title: "Funding",
  description:
    "Products a funder pays for, awards of units per period to a record from a funder in contacts, care delivered against an award from time entries, bookings or by hand, usage against the award per period, and claims per funder and period with the funder's response per line, rendered and sent through app-supplied formats and channels.",
  requires: ["memberships", "permissions", "subjects", "contacts"],
  integrates: [
    "time-tracking",
    "bookings",
    "invoices",
    "numbering",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
