import type { ModuleContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { columnRef } from "../shared.ts";

/** The log columns whose values `sql.modules.audit.options.values` maps. */
export type AuditValueColumn =
  | "scope"
  | "actorKind"
  | "outcome"
  | "source"
  | "category";

const COLUMNS: readonly AuditValueColumn[] = [
  "scope",
  "actorKind",
  "outcome",
  "source",
  "category",
];

export const isAuditValueColumn = (key: string): key is AuditValueColumn =>
  COLUMNS.some((column) => column === key);

/**
 * `sql.modules.audit.options.values`: the module's value to the adopted
 * log's, per column, such as `{ scope: { tenant: "organization" } }`.
 */
function valueMaps(
  ctx: ModuleContext,
): ReadonlyMap<AuditValueColumn, ReadonlyMap<string, string>> {
  const where = "sql.modules.audit.options.values";
  const configured = ctx.option("values");
  const maps = new Map<AuditValueColumn, Map<string, string>>();
  if (configured === undefined) return maps;
  if (typeof configured !== "object" || configured === null) {
    throw new TypeError(`${where} must be an object`);
  }
  for (const [column, value] of Object.entries(configured)) {
    const entries: unknown = value;
    if (!isAuditValueColumn(column)) {
      throw new TypeError(
        `${where}: unknown column "${column}". Columns: ${COLUMNS.join(", ")}`,
      );
    }
    if (typeof entries !== "object" || entries === null) {
      throw new TypeError(`${where}.${column} must map values to values`);
    }
    const map = new Map<string, string>();
    for (const [from, to] of Object.entries(entries)) {
      if (typeof to !== "string" || to === "") {
        throw new TypeError(`${where}.${column}.${from} must be a string`);
      }
      if ([...map.values()].includes(to)) {
        throw new TypeError(
          `${where}.${column}: two values map to "${to}", so reads can't tell them apart`,
        );
      }
      map.set(from, to);
    }
    maps.set(column, map);
  }
  return maps;
}

/** `expression` with the module's values replaced by the adopted log's. */
export function auditWrite(
  ctx: ModuleContext,
  column: AuditValueColumn,
  expression: string,
): string {
  const map = valueMaps(ctx).get(column);
  if (!map || map.size === 0) return expression;
  const cases = [...map]
    .map(([from, to]) => `when ${sqlString(from)} then ${sqlString(to)}`)
    .join(" ");
  return `case (${expression}) ${cases} else (${expression}) end`;
}

/** A stored value read back as the module's value. */
export function auditRead(
  ctx: ModuleContext,
  column: AuditValueColumn,
  expression: string,
): string {
  const map = valueMaps(ctx).get(column);
  if (!map || map.size === 0) return expression;
  const cases = [...map]
    .map(([from, to]) => `when ${sqlString(to)} then ${sqlString(from)}`)
    .join(" ");
  return `case ${expression} ${cases} else ${expression} end`;
}

/**
 * The tenant's name as it was: `sql.modules.audit.options.tenantLabel`
 * (`schema.table.column`, matched on `tenantLabelKey`, `id` by default),
 * else the organizations module's name column, else null.
 */
export function tenantLabel(ctx: ModuleContext, tenant: string): string {
  const configured = ctx.option("tenantLabel");
  if (configured !== undefined) {
    if (typeof configured !== "string") {
      throw new TypeError(
        "sql.modules.audit.options.tenantLabel must be a string",
      );
    }
    const ref = columnRef("sql.modules.audit.options.tenantLabel", configured);
    const key = sqlIdent(ctx.text("tenantLabelKey", "id"));
    return `(select o.${ref.column}::text from ${ref.table} o where o.${key} = ${tenant})`;
  }
  if (!ctx.installed("organizations")) return "null";
  const organizations = ctx.of("organizations");
  if (!organizations.has("organizations", "name")) return "null";
  return `(select o.${organizations.col("organizations", "name")}::text from ${organizations.table("organizations")} o where o.${organizations.col("organizations", "id")} = ${tenant})`;
}
