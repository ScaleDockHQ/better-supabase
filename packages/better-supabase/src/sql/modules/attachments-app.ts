import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";

/**
 * A row of `table` as JSON under the module's default column names, which the
 * TypeScript side reads, with `values` in place of some columns. On the app's
 * table `to_jsonb` would return the app's own names and its other columns, so
 * the object names each column the table has.
 */
export function namedRowJson(
  ctx: BlockSqlContext,
  table: string,
  row: string,
  values: Readonly<Record<string, string>>,
): string {
  const columns = ctx.names.tables[table]?.columns ?? {};

  return `jsonb_build_object(${Object.entries(columns)
    .filter(([logical]) => ctx.has(table, logical))
    .map(
      ([logical, name]) =>
        `${sqlString(name)}, ${values[logical] ?? `${row}.${ctx.col(table, logical)}`}`,
    )
    .join(", ")})`;
}

/** `row.column`, or null when the table lacks the optional column. */
export const columnOrNull = (
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
): string =>
  ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

/**
 * The status of a `from` row written to `to`, whose status may be the app's
 * type.
 */
export const statusFrom = (
  ctx: BlockSqlContext,
  to: string,
  from: string,
  value: string,
): string => ctx.cast(to, "status", ctx.owns(from) ? value : `${value}::text`);

/**
 * On the app's table the app's grants stay, so a client's insert can't be
 * trusted to leave the scan and upload columns at their defaults.
 */
export function attachmentInsertDefaults(ctx: BlockSqlContext): string {
  if (ctx.owns("attachments")) {
    return "";
  }

  const t = ctx.table("attachments");
  const c = (logical: string): string => ctx.col("attachments", logical);
  const fn = ctx.fn("attachment_insert_defaults");

  const cleared = ["detail", "scannedAt"]
    .filter((logical) => ctx.has("attachments", logical))
    .map((logical) => `\n    new.${c(logical)} := null;`)
    .join("");

  return `create or replace function ${fn}()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER}) then
    new.${c("status")} := 'pending';
    new.${c("uploadedBy")} := auth.uid();
    new.${c("uploadedAt")} := null;
    new.${c("version")} := 1;${cleared}
  end if;
  return new;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists bsb_attachments_insert_defaults on ${t};
create trigger bsb_attachments_insert_defaults
  before insert on ${t}
  for each row execute function ${fn}();
`;
}

/** The scans columns the table has, for its upserts and its JSON. */
export function scanColumns(ctx: BlockSqlContext): {
  readonly detail: boolean;
  readonly set: string;
  readonly pending: string;
  readonly json: (row: string) => string;
} {
  const sc = (logical: string): string => ctx.col("scans", logical);
  const detail = ctx.has("scans", "detail");

  const reset = (logical: string, value?: string): string[] =>
    ctx.has("scans", logical)
      ? [`${sc(logical)} = ${value ?? `excluded.${sc(logical)}`}`]
      : [];

  return {
    detail,
    set: [
      `${sc("status")} = excluded.${sc("status")}`,
      ...reset("detail"),
      `${sc("scannedAt")} = excluded.${sc("scannedAt")}`,
    ].join(", "),
    pending: [
      `${sc("status")} = 'pending'`,
      ...reset("detail", "null"),
      `${sc("scannedAt")} = null`,
      ...reset("createdAt", "now()"),
    ].join(", "),
    json: (row) =>
      ctx.owns("scans")
        ? `to_jsonb(${row})`
        : namedRowJson(ctx, "scans", row, {}),
  };
}
