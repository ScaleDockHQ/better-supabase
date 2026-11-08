import type { BlockSqlContext } from "./context.ts";

import { sqlString } from "../core/template.ts";

/**
 * The triggers `better_supabase.track_realtime(target, ...)` creates, as static
 * statements a schema diff can see. Without a scope column the table broadcasts
 * one statement trigger on the shared topic; with one, a trigger per event
 * carries the transition tables and the column that names the topic.
 */
export function realtimeTriggers(
  target: string,
  scope?: { readonly column: string; readonly kind: "tenant" | "user" },
): string {
  if (scope === undefined) {
    return `create trigger bsb_realtime after insert or update or delete on ${target} for each statement execute function better_supabase.broadcast_changes();`;
  }

  const args = `(${sqlString(scope.column)}, ${sqlString(scope.kind)})`;

  const trigger = (event: string, referencing: string): string =>
    `create trigger bsb_realtime_${event} after ${event} on ${target} referencing ${referencing} for each statement execute function better_supabase.broadcast_changes${args};`;

  return [
    trigger("insert", "new table as new_rows"),
    trigger("update", "old table as old_rows new table as new_rows"),
    trigger("delete", "old table as old_rows"),
  ].join("\n");
}

/**
 * `better_supabase.track_realtime(...)` for each entity of `ctx`'s module whose
 * subject sets `realtime`, when the `realtime-tables` module is installed (ADR
 * 0196). The statement keys the topic by the table's tenant column.
 */
export function rowRealtimeData(
  ctx: BlockSqlContext,
  installed: readonly string[],
  inSchema = false,
): string {
  if (!ctx.manages || !installed.includes("realtime-tables")) {
    return "";
  }

  const seen = new Set<string>();
  const lines: string[] = [];
  const triggers: string[] = [];

  for (const entity of Object.values(ctx.names.entities ?? {})) {
    const logical = entity.table;

    if (
      entity.subject?.realtime !== true ||
      logical === undefined ||
      seen.has(logical) ||
      !ctx.hasTable(logical) ||
      !ctx.owns(logical)
    ) {
      continue;
    }

    seen.add(logical);
    const { schema, name } = ctx.tableName(logical);
    const tenant = ctx.names.tables[logical]?.columns["tenant"];

    const column =
      tenant === undefined
        ? undefined
        : ctx.col(logical, "tenant").replaceAll('"', "");

    lines.push(
      `select better_supabase.track_realtime(${sqlString(`${schema}.${name}`)}, tenant_column => ${column === undefined ? "null" : sqlString(column)});`,
    );
    triggers.push(
      realtimeTriggers(
        `"${schema}"."${name}"`,
        column === undefined ? undefined : { column, kind: "tenant" },
      ),
    );
  }

  const comment = "-- Realtime for the module's entities (subject.realtime)";

  if (lines.length === 0) {
    return "";
  }

  // A top-level `select` is a statement a schema diff skips, so the schema
  // file declares the triggers themselves.
  return `${comment}\n${(inSchema ? triggers : lines).join("\n")}`;
}
