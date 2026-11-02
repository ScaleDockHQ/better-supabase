import type { BlockSqlContext } from "./context.ts";

import { sqlString } from "../core/template.ts";

/**
 * `better_supabase.track_realtime(...)` for each entity of `ctx`'s module whose
 * subject sets `realtime`, when the `realtime-tables` module is installed (ADR
 * 0196). The statement keys the topic by the table's tenant column.
 */
export function rowRealtimeData(
  ctx: BlockSqlContext,
  installed: readonly string[],
): string {
  if (!ctx.manages || !installed.includes("realtime-tables")) {
    return "";
  }

  const seen = new Set<string>();
  const lines: string[] = [];

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

    lines.push(
      `select better_supabase.track_realtime(${sqlString(`${schema}.${name}`)}, tenant_column => ${tenant === undefined ? "null" : sqlString(ctx.col(logical, "tenant").replaceAll('"', ""))});`,
    );
  }

  return lines.length === 0
    ? ""
    : `-- Realtime for the module's entities (subject.realtime)\n${lines.join("\n")}`;
}
