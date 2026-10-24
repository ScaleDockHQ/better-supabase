import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable } from "../shared.ts";

/** Postgres truncates longer identifiers, so two long index names could meet. */
const MAX_IDENTIFIER = 63;

/**
 * `lockTable` for a logical table. On a table the app has, the app's own grants
 * stay, so its code that writes the table keeps working: row level security
 * goes on and the module adds its read and service grants.
 */
export function lockModuleTable(
  ctx: BlockSqlContext,
  logical: string,
  options: { readonly read?: boolean } = {},
): string {
  const table = ctx.table(logical);

  if (!ctx.appOwned.includes(logical)) {
    return lockTable(table, options);
  }

  return `alter table ${table} enable row level security;
${options.read ? `grant select on ${table} to authenticated;\n` : ""}grant all on ${table} to service_role;`;
}

/**
 * `expr`, a read of a column on `logical`, as text. On a table the app has, the
 * column can be an enum or a domain, which a comparison with a text value
 * rejects; the module's own column is text already, so it stays as is.
 */
export function asText(
  ctx: BlockSqlContext,
  logical: string,
  expr: string,
): string {
  return ctx.appOwned.includes(logical) ? `${expr}::text` : expr;
}

/**
 * The unique index an `on conflict (columns)` target needs on a table the app
 * has, as logical columns. The module's own table declares the key inline, so
 * this is empty for it. `where` makes a partial index for a target with a
 * `where` clause.
 */
export function appUniqueIndex(
  ctx: BlockSqlContext,
  logical: string,
  columns: readonly string[],
  where?: string,
): string {
  if (!ctx.appOwned.includes(logical)) {
    return "";
  }

  const physical = columns.map((column) => ctx.colName(logical, column));
  const name = `${ctx.tableName(logical).name}_${physical.join("_")}_key`;

  return `\ncreate unique index if not exists ${sqlIdent(name.slice(0, MAX_IDENTIFIER))} on ${ctx.table(logical)} (${physical.map((column) => sqlIdent(column)).join(", ")})${where === undefined ? "" : ` where ${where}`};`;
}
