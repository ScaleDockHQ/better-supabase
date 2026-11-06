import type { BlockSqlContext } from "../context.ts";

import { booksAccounting } from "../accounting-sources-sql.ts";

/**
 * The data step that gives every existing project its value of accounting's
 * `project` dimension. `save_project` syncs a value on each save, so a project
 * written before accounting booked tasks had none until its next save. It
 * creates the dimension when it is missing and updates names, so running it
 * again changes nothing.
 */
export function backfillProjectDimensions(ctx: BlockSqlContext): string {
  if (
    ctx.mode === "custom" ||
    !booksAccounting(ctx) ||
    !ctx.hasTable("projects")
  ) {
    return "";
  }

  const projects = ctx.table("projects");
  const p = (column: string): string => ctx.col("projects", column);
  const sync = ctx.of("accounting").fn("accounting_sync_dimension_value");

  return `-- Gives each existing project its value of the accounting project dimension.
select ${sync}(x.${p("tenant")}, 'project', 'Project', x.${p("id")}::text, x.${p("key")} || ' ' || x.${p("name")}, x.${p("archivedAt")} is not null)
from ${projects} x
where exists (select 1 from ${ctx.of("accounting").table("settings")} s where s.${ctx.of("accounting").col("settings", "tenant")} = x.${p("tenant")});`;
}
