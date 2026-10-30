import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { extraFieldsJson } from "../shared.ts";
import { teamIdType } from "./teams.ts";

const WHERE = "blocks.shifts.options";

/** The keys the shift reads return next to the extra columns. */
export const SHIFT_RESERVED = ["fields", "assignments", "warnings"] as const;

export const SHIFT_STATUSES = ["draft", "published", "canceled"] as const;

export const ASSIGNMENT_STATUSES = [
  "assigned",
  "requested",
  "released",
] as const;

export const SWAP_STATUSES = [
  "pending",
  "approved",
  "rejected",
  "canceled",
] as const;

export const AVAILABILITY_KINDS = [
  "available",
  "unavailable",
  "preferred",
] as const;

/** `('a', 'b')` for an `in` list. */
export const sqlList = (values: readonly string[]): string =>
  `(${values.map((value) => sqlString(value)).join(", ")})`;

/** `options.minRestHours`: the hours between two shifts of one person. */
export function minRestHours(ctx: BlockSqlContext): number {
  const hours = ctx.number("minRestHours", 11);

  if (!Number.isFinite(hours) || hours < 0 || hours > 48) {
    throw new TypeError(`${WHERE}.minRestHours takes 0 to 48 hours`);
  }

  return hours;
}

/** `options.qualificationCheck`: `block` refuses, `warn` assigns with a warning. */
export function qualificationCheck(ctx: BlockSqlContext): "block" | "warn" {
  const mode = ctx.text("qualificationCheck", "block");

  if (mode !== "block" && mode !== "warn") {
    throw new TypeError(`${WHERE}.qualificationCheck takes block or warn`);
  }

  return mode;
}

/** `options.timeZone`: the IANA zone shift templates and days are in. */
export function shiftTimeZone(ctx: BlockSqlContext): string {
  const zone = ctx.text("timeZone", "UTC");

  try {
    Intl.DateTimeFormat("en", { timeZone: zone });
  } catch {
    throw new TypeError(`${WHERE}.timeZone: "${zone}" is not a time zone`);
  }

  return zone;
}

/** `row.column`, or null when the app's table lacks the optional column. */
const optionalField = (
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
): string =>
  ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

/** The JSON of a shift template row. */
export function templateJson(ctx: BlockSqlContext, row: string): string {
  const t = (column: string): string =>
    `${row}.${ctx.col("templates", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "templates", row, column);

  return `jsonb_build_object('id', ${t("id")}, 'organizationId', ${t("tenant")}, 'name', ${t("name")}, 'teamId', ${t("team")}, 'locationId', ${field("location")}, 'startsTime', to_char(${t("startsTime")}, 'HH24:MI'), 'endsTime', to_char(${t("endsTime")}, 'HH24:MI'), 'breakMinutes', ${t("breakMinutes")}, 'headcount', ${t("headcount")}, 'requiredQualifications', to_jsonb(${t("requiredQualifications")}), 'weekdays', to_jsonb(${t("weekdays")}), 'archivedAt', ${t("archivedAt")}, 'createdAt', ${field("createdAt")}, 'updatedAt', ${field("updatedAt")})`;
}

/** The JSON of a shift row. */
export function shiftJson(ctx: BlockSqlContext, row: string): string {
  const s = (column: string): string => `${row}.${ctx.col("shifts", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "shifts", row, column);

  const extras = ctx.extraColumns("shifts", SHIFT_RESERVED);

  return `jsonb_build_object('id', ${s("id")}, 'organizationId', ${s("tenant")}, 'templateId', ${s("template")}, 'teamId', ${s("team")}, 'locationId', ${field("location")}, 'startsAt', ${s("startsAt")}, 'endsAt', ${s("endsAt")}, 'breakMinutes', ${s("breakMinutes")}, 'headcount', ${s("headcount")}, 'requiredQualifications', to_jsonb(${s("requiredQualifications")}), 'status', ${s("status")}, 'note', ${field("note")}, 'publishedAt', ${s("publishedAt")}, 'canceledAt', ${s("canceledAt")}, 'createdBy', ${field("createdBy")}, 'createdAt', ${field("createdAt")}, 'updatedAt', ${field("updatedAt")}${extraFieldsJson(row, extras)})`;
}

/** The JSON of a shift assignment row. */
export function assignmentJson(ctx: BlockSqlContext, row: string): string {
  const a = (column: string): string =>
    `${row}.${ctx.col("assignments", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "assignments", row, column);

  return `jsonb_build_object('id', ${a("id")}, 'organizationId', ${a("tenant")}, 'shiftId', ${a("shift")}, 'userId', ${a("user")}, 'status', ${a("status")}, 'startsAt', ${a("startsAt")}, 'endsAt', ${a("endsAt")}, 'assignedBy', ${field("assignedBy")}, 'createdAt', ${field("createdAt")}, 'updatedAt', ${field("updatedAt")})`;
}

/** The JSON of a shift swap row. */
export function swapJson(ctx: BlockSqlContext, row: string): string {
  const w = (column: string): string => `${row}.${ctx.col("swaps", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "swaps", row, column);

  return `jsonb_build_object('id', ${w("id")}, 'organizationId', ${w("tenant")}, 'assignmentId', ${w("assignment")}, 'fromUserId', ${w("fromUser")}, 'toUserId', ${w("toUser")}, 'status', ${w("status")}, 'approvalId', ${field("approval")}, 'note', ${field("note")}, 'decidedBy', ${field("decidedBy")}, 'decidedAt', ${w("decidedAt")}, 'createdAt', ${field("createdAt")})`;
}

/** The JSON of a shift availability row. */
export function availabilityJson(ctx: BlockSqlContext, row: string): string {
  const v = (column: string): string =>
    `${row}.${ctx.col("availability", column)}`;

  const field = (column: string): string =>
    optionalField(ctx, "availability", row, column);

  return `jsonb_build_object('id', ${v("id")}, 'organizationId', ${v("tenant")}, 'userId', ${v("user")}, 'onDate', ${v("onDate")}, 'fromTime', to_char(${v("fromTime")}, 'HH24:MI'), 'untilTime', to_char(${v("untilTime")}, 'HH24:MI'), 'kind', ${v("kind")}, 'note', ${field("note")}, 'createdAt', ${field("createdAt")})`;
}

/**
 * The record of shift `row` (a shifts row) for `event`, with `extra` (`, 'key',
 * value` pairs) after the shared keys.
 */
export function shiftRecord(
  ctx: BlockSqlContext,
  event: string,
  row: string,
  extra: string,
  summary: string,
): string {
  const s = (column: string): string => `${row}.${ctx.col("shifts", column)}`;

  return ctx.record({
    type: event,
    payload: `jsonb_build_object('organizationId', ${s("tenant")}, 'shiftId', ${s("id")}, 'teamId', ${s("team")}, 'startsAt', ${s("startsAt")}, 'endsAt', ${s("endsAt")}${extra})`,
    subject: `'shifts/' || ${s("id")}::text`,
    tenant: s("tenant"),
    audit: {
      category: "data",
      targetType: "shift",
      recordId: `${s("id")}::text`,
      summary: `'${summary}'`,
    },
  });
}

/** The record of assignment `row` for `event`, with `extra` pairs. */
export function assignmentRecord(
  ctx: BlockSqlContext,
  event: string,
  row: string,
  extra: string,
  summary: string,
): string {
  const a = (column: string): string =>
    `${row}.${ctx.col("assignments", column)}`;

  return ctx.record({
    type: event,
    payload: `jsonb_build_object('organizationId', ${a("tenant")}, 'shiftId', ${a("shift")}, 'assignmentId', ${a("id")}, 'userId', ${a("user")}, 'startsAt', ${a("startsAt")}, 'endsAt', ${a("endsAt")}${extra})`,
    subject: `'shifts/' || ${a("shift")}::text`,
    tenant: a("tenant"),
    audit: {
      category: "data",
      targetType: "shift_assignment",
      recordId: `${a("id")}::text`,
      summary: `'${summary}'`,
    },
  });
}

/**
 * PL/pgSQL that notifies `recipients` (a jsonb array of user ids) about shift
 * `shift` (a uuid expression), or nothing without the notifications module. The
 * function declares `v_claims text`.
 */
export function notifyShift(
  ctx: BlockSqlContext,
  options: {
    readonly type: string;
    readonly tenant: string;
    readonly shift: string;
    readonly recipients: string;
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
      'subject_type', 'shift',
      'subject_id', ${options.shift}::text,
      'summary', ${options.summary},
      'recipients', ${options.recipients},
      'key', ${options.key},
      'data', ${options.data}
    )`,
    { indent: "  " },
  );
}

/** The SQL type of a team id (`blocks.teams.options.teamIdType`). */
export const teamType = (ctx: BlockSqlContext): string =>
  teamIdType(ctx.of("teams"));
