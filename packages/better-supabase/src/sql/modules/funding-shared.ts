import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { extraFieldsJson } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const WHERE = "blocks.funding.options";

/** Keys the award JSON uses, which extra columns can't take. */
export const AWARD_RESERVED = ["fields", "product", "usage"] as const;

export const UNITS = [
  "minute",
  "hour",
  "day_part",
  "day",
  "visit",
  "piece",
] as const;

export const PERIODS = ["week", "month", "total"] as const;

export const AWARD_STATUSES = [
  "requested",
  "active",
  "ended",
  "canceled",
] as const;

export const DELIVERY_SOURCES = ["time_entry", "booking", "manual"] as const;

export const DELIVERY_STATUSES = [
  "registered",
  "approved",
  "claimed",
  "rejected",
] as const;

export const CLAIM_STATUSES = [
  "draft",
  "sent",
  "accepted",
  "partially_accepted",
  "rejected",
] as const;

export const LINE_STATUSES = ["pending", "accepted", "rejected"] as const;

/** A claim format key: what a `FundingClaimFormat` names itself. */
export const FORMAT_PATTERN = "^[a-z0-9][a-z0-9_.-]{0,62}$";

/** `('a', 'b')` for an `in` list. */
export const sqlList = (values: readonly string[]): string =>
  `(${values.map((value) => sqlString(value)).join(", ")})`;

/**
 * `options.formats`: the claim format keys `build_funding_claim` accepts. Empty
 * accepts any well-formed key.
 */
export function claimFormats(ctx: BlockSqlContext): readonly string[] {
  const formats = ctx.list("formats", []);
  const pattern = new RegExp(FORMAT_PATTERN, "u");

  for (const format of formats) {
    if (!pattern.test(format)) {
      throw new TypeError(
        `${WHERE}.formats: "${format}" is not a format key (lowercase letters, digits, dots, dashes and underscores)`,
      );
    }
  }

  return formats;
}

/**
 * Whether `register_funding_deliveries_from_time` renders: time-tracking is
 * installed and manages its tables.
 */
export const fromTime = (ctx: BlockSqlContext): boolean =>
  ctx.installed("time-tracking") && ctx.of("time-tracking").mode !== "custom";

/**
 * `options.timeCategory`: the extra column of the time entries table whose
 * value names the product code an entry delivers. Undefined matches an entry to
 * the only active award of its record.
 */
export function timeCategory(ctx: BlockSqlContext): string | undefined {
  const column = ctx.option("timeCategory");

  if (column === undefined) {
    return undefined;
  }

  if (typeof column !== "string" || column === "") {
    throw new TypeError(
      `${WHERE}.timeCategory takes an extra column of the time entries table`,
    );
  }

  if (!fromTime(ctx)) {
    throw new TypeError(`${WHERE}.timeCategory needs the time-tracking block`);
  }

  const extras = ctx.of("time-tracking").extraColumns("entries");

  if (!extras.some((extra) => extra.name === column)) {
    throw new TypeError(
      `${WHERE}.timeCategory: "${column}" is not one of blocks.time-tracking.options.extraColumns`,
    );
  }

  return column;
}

/** The permission keys, as SQL literals. */
export function fundingKeys(ctx: BlockSqlContext): {
  readonly read: string;
  readonly write: string;
  readonly register: string;
  readonly approve: string;
  readonly claim: string;
  readonly manage: string;
} {
  const permissions = moduleOperations("funding");

  return {
    read: ctx.permission("read", permissions.read),
    write: ctx.permission("write", permissions.write),
    register: ctx.permission("register", permissions.register),
    approve: ctx.permission("approve", permissions.approve),
    claim: ctx.permission("claim", permissions.claim),
    manage: ctx.permission("manage", permissions.manage),
  };
}

/** `row.column`, or null when the app's table lacks the optional column. */
const optionalField = (
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
): string =>
  ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

/** The JSON of a funding product row; the rate is minor units as text. */
export function productJson(ctx: BlockSqlContext, row: string): string {
  const p = (column: string): string => `${row}.${ctx.col("products", column)}`;

  return `jsonb_build_object('id', ${p("id")}, 'organizationId', ${p("tenant")}, 'code', ${p("code")}, 'title', ${p("title")}, 'unit', ${p("unit")}, 'rate', ${p("rate")}::text, 'currency', ${p("currency")}, 'validFrom', ${p("validFrom")}, 'validUntil', ${p("validUntil")}, 'createdAt', ${optionalField(ctx, "products", row, "createdAt")}, 'updatedAt', ${optionalField(ctx, "products", row, "updatedAt")})`;
}

/** The JSON of a funding award row. */
export function awardJson(ctx: BlockSqlContext, row: string): string {
  const w = (column: string): string => `${row}.${ctx.col("awards", column)}`;

  return `jsonb_build_object('id', ${w("id")}, 'organizationId', ${w("tenant")}, 'subjectType', ${w("subjectType")}, 'subjectId', ${w("subjectId")}, 'funderId', ${w("funder")}, 'productId', ${w("product")}, 'units', ${w("units")}, 'period', ${w("period")}, 'startsOn', ${w("startsOn")}, 'endsOn', ${w("endsOn")}, 'reference', ${w("reference")}, 'status', ${w("status")}, 'createdBy', ${optionalField(ctx, "awards", row, "createdBy")}, 'createdAt', ${optionalField(ctx, "awards", row, "createdAt")}, 'updatedAt', ${optionalField(ctx, "awards", row, "updatedAt")}${extraFieldsJson(row, ctx.extraColumns("awards", AWARD_RESERVED))})`;
}

/** The JSON of a funding delivery row. */
export function deliveryJson(ctx: BlockSqlContext, row: string): string {
  const d = (column: string): string =>
    `${row}.${ctx.col("deliveries", column)}`;

  return `jsonb_build_object('id', ${d("id")}, 'organizationId', ${d("tenant")}, 'awardId', ${d("award")}, 'sourceType', ${d("sourceType")}, 'sourceId', ${d("sourceId")}, 'deliveredOn', ${d("deliveredOn")}, 'units', ${d("units")}, 'performerId', ${d("performer")}, 'status', ${d("status")}, 'claimLineId', ${d("claimLine")}, 'note', ${optionalField(ctx, "deliveries", row, "note")}, 'createdAt', ${optionalField(ctx, "deliveries", row, "createdAt")})`;
}

/** The JSON of a funding claim row; the total is minor units as text. */
export function claimJson(ctx: BlockSqlContext, row: string): string {
  const c = (column: string): string => `${row}.${ctx.col("claims", column)}`;

  return `jsonb_build_object('id', ${c("id")}, 'organizationId', ${c("tenant")}, 'funderId', ${c("funder")}, 'number', ${c("number")}, 'periodStart', ${c("periodStart")}, 'periodEnd', ${c("periodEnd")}, 'format', ${c("format")}, 'status', ${c("status")}, 'externalRef', ${c("externalRef")}, 'sentAt', ${c("sentAt")}, 'payloadSha256', ${c("payloadSha256")}, 'response', ${c("response")}, 'total', ${c("total")}::text, 'currency', ${c("currency")}, 'invoiceId', ${optionalField(ctx, "claims", row, "invoice")}, 'createdBy', ${optionalField(ctx, "claims", row, "createdBy")}, 'createdAt', ${optionalField(ctx, "claims", row, "createdAt")}, 'updatedAt', ${optionalField(ctx, "claims", row, "updatedAt")})`;
}

/** The JSON of a claim line row; the amount is minor units as text. */
export function lineJson(ctx: BlockSqlContext, row: string): string {
  const l = (column: string): string =>
    `${row}.${ctx.col("claimLines", column)}`;

  return `jsonb_build_object('id', ${l("id")}, 'claimId', ${l("claim")}, 'awardId', ${l("award")}, 'productId', ${l("product")}, 'units', ${l("units")}, 'amount', ${l("amount")}::text, 'status', ${l("status")}, 'rejectionCode', ${l("rejectionCode")})`;
}

/**
 * The record of award `row` for `event`, with `extra` (`, 'key', value` pairs)
 * after the shared keys.
 */
export function awardRecord(
  ctx: BlockSqlContext,
  event: string,
  row: string,
  extra: string,
  summary: string,
): string {
  const w = (column: string): string => `${row}.${ctx.col("awards", column)}`;

  return ctx.record({
    type: event,
    payload: `jsonb_build_object('organizationId', ${w("tenant")}, 'fundingAwardId', ${w("id")}, 'fundingProductId', ${w("product")}, 'funderId', ${w("funder")}, 'subjectType', ${w("subjectType")}, 'subjectId', ${w("subjectId")}, 'status', ${w("status")}${extra})`,
    subject: `'funding-awards/' || ${w("id")}::text`,
    tenant: w("tenant"),
    audit: {
      category: "data",
      targetType: "funding_award",
      recordId: `${w("id")}::text`,
      summary: sqlString(summary),
    },
  });
}

/** The record of claim `row` for `event`, with `extra` after the shared keys. */
export function claimRecord(
  ctx: BlockSqlContext,
  event: string,
  row: string,
  extra: string,
  summary: string,
): string {
  const c = (column: string): string => `${row}.${ctx.col("claims", column)}`;

  return ctx.record({
    type: event,
    payload: `jsonb_build_object('organizationId', ${c("tenant")}, 'fundingClaimId', ${c("id")}, 'funderId', ${c("funder")}, 'number', ${c("number")}, 'status', ${c("status")}, 'periodStart', ${c("periodStart")}, 'periodEnd', ${c("periodEnd")}, 'total', ${c("total")}::text, 'currency', ${c("currency")}${extra})`,
    subject: `'funding-claims/' || ${c("id")}::text`,
    tenant: c("tenant"),
    audit: {
      category: "data",
      targetType: "funding_claim",
      recordId: `${c("id")}::text`,
      summary: sqlString(summary),
    },
  });
}

/**
 * The first day of the award period `day` falls in: its week (Monday), month,
 * or the award's start for a `total` award. `award` is an awards row.
 */
export function periodStart(
  ctx: BlockSqlContext,
  award: string,
  day: string,
): string {
  const w = (column: string): string => `${award}.${ctx.col("awards", column)}`;

  return `(case ${w("period")} when 'week' then date_trunc('week', ${day})::date when 'month' then date_trunc('month', ${day})::date else ${w("startsOn")} end)`;
}

/** The day after the period that starts on `start` (an expression). */
export function periodEnd(
  ctx: BlockSqlContext,
  award: string,
  start: string,
): string {
  const w = (column: string): string => `${award}.${ctx.col("awards", column)}`;

  return `(case ${w("period")} when 'week' then (${start} + 7) when 'month' then (${start} + interval '1 month')::date else coalesce(${w("endsOn")} + 1, 'infinity'::date) end)`;
}

/**
 * PL/pgSQL that notifies the members holding `permission` (a SQL literal) about
 * the record behind an award, or nothing without the notifications module. The
 * function declares `v_claims text`.
 */
export function notifyFunding(
  ctx: BlockSqlContext,
  options: {
    readonly type: string;
    readonly tenant: string;
    readonly subjectType: string;
    readonly subjectId: string;
    readonly permission: string;
    readonly summary: string;
    readonly key: string;
    readonly data: string;
  },
): string {
  if (!ctx.installed("notifications")) {
    return "";
  }

  return ctx.notify(
    `jsonb_build_object(
      'type', ${sqlString(options.type)},
      'tenant', ${options.tenant},
      'actor', (select auth.uid()),
      'subject_type', ${options.subjectType},
      'subject_id', ${options.subjectId}::text,
      'summary', ${options.summary},
      'permission', ${options.permission},
      'watchers', false,
      'key', ${options.key},
      'data', ${options.data}
    )`,
    { indent: "    " },
  );
}
