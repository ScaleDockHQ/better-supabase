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
 * block function recorded still leaves an entry (ADR 0196). A row a function
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
  const triggers: string[] = [];

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

    const label = ctx.naming.rename(entity.singular);

    lines.push(
      `select better_supabase.audit(${sqlString(`${schema}.${name}`)}, target_type => ${sqlString(label)}, event_prefix => ${sqlString(label)}, deferred => true);`,
    );
    triggers.push(
      auditTrigger(`${schema}.${name}`, {
        target_type: label,
        event_prefix: label,
      }),
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
      triggers.push(auditTrigger(`${schema}.${name}`, {}, false));
    }
  }

  if (lines.length === 0) {
    return "";
  }

  const comment =
    "-- Row audit for the module's tables (blocks.audit.options.blockTables)";

  // A top-level `select` is a statement a schema diff skips, so the schema
  // file declares the trigger itself, with the settings `audit()` would store
  // in its arguments.
  return inSchema
    ? `${comment}\n${triggers.join("\n")}`
    : `${comment}\n${lines.join("\n")}`;
}

/**
 * The trigger `better_supabase.audit(target, ...)` creates, as one static
 * statement. The settings are the trigger's argument, so the row's key columns
 * fall back to its primary key when the trigger runs.
 */
export function auditTrigger(
  target: string,
  names: Readonly<Record<string, string>>,
  deferred = true,
): string {
  const settings = JSON.stringify({ ignore: [], redact: [], ...names });

  return `create ${deferred ? "constraint " : ""}trigger bsb_audit after insert or update or delete on ${target} ${deferred ? "deferrable initially deferred " : ""}for each row execute function better_supabase.audit_row_change(${sqlString(settings)});`;
}
