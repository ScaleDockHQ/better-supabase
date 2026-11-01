import type { BlockSqlContext } from "./context.ts";
import type { BlockSqlLayout } from "./module-types.ts";

import { sqlString } from "../core/template.ts";

/** `blocks.audit.options.blockTables`: which block tables get a row trigger. */
export type RowAuditScope = "all" | "entities" | "none";

/**
 * Modules whose tables are the audit trail itself or the plumbing under it: a
 * row trigger on them would audit the audit.
 */
const NOT_AUDITED = new Set(["audit", "audit-chain", "outbox"]);

function rowAuditScope(
  layout: BlockSqlLayout,
  installed: readonly string[],
): RowAuditScope {
  if (!installed.includes("audit")) {
    return "none";
  }

  const value = layout.modules?.["audit"]?.options?.["blockTables"];

  return value === "all" || value === "none" ? value : "entities";
}

/**
 * `better_supabase.audit(...)` for each table of `ctx`'s module that the audit
 * module's `blockTables` option covers, so a write through the Data API that no
 * block function recorded still leaves an entry (ADR 0177). A row a function
 * already recorded is skipped by the trigger through the `bsb.recorded` marker
 * that `audit_event` sets.
 */
export function rowAuditData(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
  installed: readonly string[],
  inSchema = false,
): string {
  const scope = rowAuditScope(layout, installed);

  if (!ctx.manages || NOT_AUDITED.has(ctx.module) || scope === "none") {
    return "";
  }

  const entities = Object.values(ctx.names.entities ?? {});
  const seen = new Set<string>();
  const lines: string[] = [];

  for (const entity of entities) {
    const logical = entity.table;

    if (
      logical === undefined ||
      seen.has(logical) ||
      !ctx.hasTable(logical) ||
      !ctx.owns(logical)
    ) {
      continue;
    }

    seen.add(logical);
    const { schema, name } = ctx.tableName(logical);

    lines.push(
      `select better_supabase.audit(${sqlString(`${schema}.${name}`)}, target_type => ${sqlString(ctx.naming.rename(entity.singular))}, event_prefix => ${sqlString(ctx.naming.rename(entity.singular))}, deferred => true);`,
    );
  }

  if (scope === "all") {
    for (const [logical] of Object.entries(ctx.names.tables)) {
      if (seen.has(logical) || !ctx.hasTable(logical) || !ctx.owns(logical)) {
        continue;
      }

      seen.add(logical);
      const { schema, name } = ctx.tableName(logical);
      lines.push(
        `select better_supabase.audit(${sqlString(`${schema}.${name}`)});`,
      );
    }
  }

  if (lines.length === 0) {
    return "";
  }

  const comment =
    "-- Row audit for the module's tables (blocks.audit.options.blockTables)";

  // A top-level `select` is a statement a schema diff skips; inside `do` it
  // runs when the schema is applied, so the triggers stay in the diff.
  return inSchema
    ? `${comment}\ndo $$\nbegin\n${lines.map((line) => `  perform ${line.slice("select ".length)}`).join("\n")}\nend;\n$$;`
    : `${comment}\n${lines.join("\n")}`;
}
