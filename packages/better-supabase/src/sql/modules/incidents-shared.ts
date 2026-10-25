import type { BlockSqlContext } from "../context.ts";

/** `row.column`, or null when the app's table lacks the optional column. */
export const optionalField = (
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
): string =>
  ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

/** A column of the app's table as text, since it may be an enum there. */
export const asText = (
  ctx: BlockSqlContext,
  table: string,
  value: string,
): string => (ctx.owns(table) ? value : `${value}::text`);

/** The order of a component list: position when the table has it, then name. */
export const componentOrder = (ctx: BlockSqlContext, row: string): string =>
  ctx.has("components", "position")
    ? `${row}.${ctx.col("components", "position")}, ${row}.${ctx.col("components", "name")}`
    : `${row}.${ctx.col("components", "name")}`;

/** The keys the incident reads return next to the extra columns. */
export const INCIDENT_RESERVED = [
  "fields",
  "updates",
  "impacts",
  "postmortem",
] as const;

export const INCIDENT_SEVERITIES = ["sev1", "sev2", "sev3", "sev4"] as const;

export const INCIDENT_STATUSES = [
  "investigating",
  "identified",
  "monitoring",
  "resolved",
] as const;

/** Component statuses, least to most severe. */
export const COMPONENT_STATUSES = [
  "operational",
  "maintenance",
  "degraded",
  "partial_outage",
  "major_outage",
] as const;
