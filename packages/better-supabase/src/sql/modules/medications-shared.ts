import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { extraFieldsJson, fail } from "../shared.ts";
import { caseKindsOf } from "./cases-sql.ts";
import { moduleOperations } from "./permissions-model.ts";

const WHERE = "blocks.medications.options";

/** Keys the order JSON uses, which extra columns can't take. */
export const ORDER_RESERVED = ["fields", "medication"] as const;

export const CODE_SYSTEMS = ["gtin", "hpk", "atc", "rxnorm", "custom"] as const;

export const ORDER_SOURCES = ["prescriber", "pharmacy", "import"] as const;

export const ORDER_STATUSES = ["active", "paused", "stopped"] as const;

export const ADMINISTRATION_STATUSES = [
  "planned",
  "given",
  "refused",
  "skipped",
  "missed",
] as const;

/** The longest range plan_medication_administrations covers, in days. */
export const PLAN_DAYS = 31;

/** `('a', 'b')` for an `in` list. */
export const sqlList = (values: readonly string[]): string =>
  `(${values.map((value) => sqlString(value)).join(", ")})`;

/**
 * `options.missedAfterMinutes`: how long a planned dose waits before it's
 * missed.
 */
export function missedAfterMinutes(ctx: BlockSqlContext): number {
  const minutes = ctx.number("missedAfterMinutes", 60);

  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 1440) {
    throw new TypeError(`${WHERE}.missedAfterMinutes takes 1 to 1440 minutes`);
  }

  return minutes;
}

/**
 * `options.missedCaseKind`: the case kind a missed dose opens, when the cases
 * block is installed in managed mode. Undefined opens no case.
 */
export function missedCaseKind(ctx: BlockSqlContext): string | undefined {
  const key = ctx.option("missedCaseKind");

  if (key === undefined) {
    return undefined;
  }

  if (typeof key !== "string" || key === "") {
    throw new TypeError(`${WHERE}.missedCaseKind takes a case kind key`);
  }

  if (!ctx.installed("cases") || ctx.of("cases").mode === "custom") {
    return undefined;
  }

  if (!caseKindsOf(ctx.of("cases")).some((kind) => kind.key === key)) {
    throw new TypeError(
      `${WHERE}.missedCaseKind: "${key}" is not one of blocks.cases.options.kinds`,
    );
  }

  return key;
}

/** `options.timeZone`: the IANA zone schedule times and chart days are in. */
export function medicationTimeZone(ctx: BlockSqlContext): string {
  const zone = ctx.text("timeZone", "UTC");

  try {
    Intl.DateTimeFormat("en", { timeZone: zone });
  } catch {
    throw new TypeError(`${WHERE}.timeZone: "${zone}" is not a time zone`);
  }

  return zone;
}

/** The permission keys, as SQL literals. */
export function medicationKeys(ctx: BlockSqlContext): {
  readonly read: string;
  readonly prescribe: string;
  readonly administer: string;
  readonly manage: string;
} {
  const permissions = moduleOperations("medications");

  return {
    read: ctx.permission("read", permissions.read),
    prescribe: ctx.permission("prescribe", permissions.prescribe),
    administer: ctx.permission("administer", permissions.administer),
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

/** The JSON of a medications row. */
export function medicationJson(ctx: BlockSqlContext, row: string): string {
  const m = (column: string): string =>
    `${row}.${ctx.col("medications", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "medications", row, column);

  return `jsonb_build_object('id', ${m("id")}, 'organizationId', ${m("tenant")}, 'name', ${m("name")}, 'codeSystem', ${m("codeSystem")}, 'code', ${m("code")}, 'form', ${field("form")}, 'strength', ${field("strength")}, 'unit', ${m("unit")}, 'highRisk', ${m("highRisk")}, 'archivedAt', ${m("archivedAt")}, 'createdAt', ${field("createdAt")}, 'updatedAt', ${field("updatedAt")})`;
}

/** The JSON of a medication order row. */
export function orderJson(ctx: BlockSqlContext, row: string): string {
  const o = (column: string): string => `${row}.${ctx.col("orders", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "orders", row, column);

  return `jsonb_build_object('id', ${o("id")}, 'organizationId', ${o("tenant")}, 'subjectType', ${o("subjectType")}, 'subjectId', ${o("subjectId")}, 'medicationId', ${o("medication")}, 'dose', ${o("dose")}, 'doseUnit', ${o("doseUnit")}, 'route', ${o("route")}, 'schedule', ${o("schedule")}, 'asNeeded', ${o("asNeeded")}, 'asNeededReason', ${o("asNeededReason")}, 'maxPerDay', ${o("maxPerDay")}, 'startsOn', ${o("startsOn")}, 'endsOn', ${o("endsOn")}, 'prescriber', ${field("prescriber")}, 'source', ${o("source")}, 'externalId', ${o("externalId")}, 'requiresDoubleCheck', ${o("requiresDoubleCheck")}, 'status', ${o("status")}, 'stoppedReason', ${o("stoppedReason")}, 'createdBy', ${field("createdBy")}, 'createdAt', ${field("createdAt")}, 'updatedAt', ${field("updatedAt")}${extraFieldsJson(row, ctx.extraColumns("orders", ORDER_RESERVED))})`;
}

/** The JSON of a medication administration row. */
export function administrationJson(ctx: BlockSqlContext, row: string): string {
  const a = (column: string): string =>
    `${row}.${ctx.col("administrations", column)}`;

  return `jsonb_build_object('id', ${a("id")}, 'organizationId', ${a("tenant")}, 'orderId', ${a("order")}, 'scheduledAt', ${a("scheduledAt")}, 'administeredAt', ${a("administeredAt")}, 'status', ${a("status")}, 'dose', ${a("dose")}, 'performerId', ${a("performer")}, 'checkedBy', ${a("checkedBy")}, 'reason', ${a("reason")}, 'note', ${optionalField(ctx, "administrations", row, "note")})`;
}

/**
 * The record of order `row` (an orders row) for `event`, with `extra` (`,
 * 'key', value` pairs) after the shared keys.
 */
export function orderRecord(
  ctx: BlockSqlContext,
  event: string,
  row: string,
  extra: string,
  summary: string,
): string {
  const o = (column: string): string => `${row}.${ctx.col("orders", column)}`;

  return ctx.record({
    type: event,
    payload: `jsonb_build_object('organizationId', ${o("tenant")}, 'medicationOrderId', ${o("id")}, 'medicationId', ${o("medication")}, 'subjectType', ${o("subjectType")}, 'subjectId', ${o("subjectId")}, 'status', ${o("status")}${extra})`,
    subject: `'medication-orders/' || ${o("id")}::text`,
    tenant: o("tenant"),
    audit: {
      category: "data",
      targetType: "medication_order",
      recordId: `${o("id")}::text`,
      summary: sqlString(summary),
    },
  });
}

/** The record of administration `row` for `event`; `order` is its orders row. */
export function administrationRecord(
  ctx: BlockSqlContext,
  event: string,
  row: string,
  order: string,
  summary: string,
): string {
  const a = (column: string): string =>
    `${row}.${ctx.col("administrations", column)}`;

  const o = (column: string): string => `${order}.${ctx.col("orders", column)}`;

  return ctx.record({
    type: event,
    payload: `jsonb_build_object('organizationId', ${a("tenant")}, 'medicationOrderId', ${a("order")}, 'medicationAdministrationId', ${a("id")}, 'subjectType', ${o("subjectType")}, 'subjectId', ${o("subjectId")}, 'status', ${a("status")}, 'scheduledAt', ${a("scheduledAt")}, 'administeredAt', ${a("administeredAt")})`,
    subject: `'medication-orders/' || ${a("order")}::text`,
    tenant: a("tenant"),
    audit: {
      category: "data",
      targetType: "medication_administration",
      recordId: `${a("id")}::text`,
      summary: sqlString(summary),
    },
  });
}

/**
 * PL/pgSQL that notifies the members holding `permission` (a SQL literal) about
 * the record behind an order, or nothing without the notifications module. The
 * function declares `v_claims text`.
 */
export function notifyMedication(
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

/**
 * PL/pgSQL that refuses a dose without a valid second check: when `needed` (a
 * boolean expression) holds, `checker` is another member of `tenant` holding
 * `administer`.
 */
export function doubleCheck(
  ctx: BlockSqlContext,
  options: {
    readonly needed: string;
    readonly checker: string;
    readonly tenant: string;
  },
): string {
  const { administer } = medicationKeys(ctx);

  return `if ${options.needed} then
    if ${options.checker} is null then
      ${fail("MEDICATION_DOUBLE_CHECK_REQUIRED", "this dose needs a second member to check it", "22023")}
    end if;
    if ${options.checker} = (select auth.uid()) then
      ${fail("MEDICATION_DOUBLE_CHECK_SELF", "the second check is by another member", "22023")}
    end if;
    if not coalesce(${ctx.scope.canUser(options.checker, options.tenant, administer)}, false) then
      ${fail("MEDICATION_DOUBLE_CHECK_REQUIRED", "the member who checks may administer medication in this organization", "22023")}
    end if;
  end if;`;
}

/**
 * PL/pgSQL that refuses a schedule (a jsonb expression) unless it is null or an
 * object with `times` ("HH:MM" strings) or `everyHours` (1 to 24, from
 * `startTime`), and optional ISO `weekdays`.
 */
export function scheduleCheck(schedule: string): string {
  const invalid = (message: string): string =>
    fail("MEDICATION_ORDER_INVALID", message, "22023");

  return `if ${schedule} is not null then
    if jsonb_typeof(${schedule}) <> 'object' or not (${schedule} ? 'times' or ${schedule} ? 'everyHours') then
      ${invalid("a schedule is an object with times or everyHours")}
    end if;
    if ${schedule} ? 'times' and (jsonb_typeof(${schedule} -> 'times') <> 'array' or jsonb_array_length(${schedule} -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(${schedule} -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      ${invalid("schedule times are HH:MM strings")}
    end if;
    if ${schedule} ? 'everyHours' and (jsonb_typeof(${schedule} -> 'everyHours') <> 'number' or (${schedule} ->> 'everyHours') !~ '^[0-9]+$' or (${schedule} ->> 'everyHours')::integer not between 1 and 24) then
      ${invalid("schedule everyHours is a whole number of hours from 1 to 24")}
    end if;
    if ${schedule} ? 'startTime' and (jsonb_typeof(${schedule} -> 'startTime') <> 'string' or (${schedule} ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      ${invalid("schedule startTime is an HH:MM string")}
    end if;
    if ${schedule} ? 'weekdays' and (jsonb_typeof(${schedule} -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(${schedule} -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      ${invalid("schedule weekdays are 1 (Monday) to 7 (Sunday)")}
    end if;
  end if;`;
}
