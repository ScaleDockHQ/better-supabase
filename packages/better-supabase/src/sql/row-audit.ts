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

  if (
    !ctx.manages ||
    !ctx.config.audit ||
    NOT_AUDITED.has(ctx.module) ||
    scope === "none"
  ) {
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

    const archive =
      "archivedAt" in (ctx.names.tables[logical]?.columns ?? {}) &&
      ctx.has(logical, "archivedAt")
        ? ctx.colName(logical, "archivedAt")
        : undefined;

    lines.push(
      `select better_supabase.audit(${sqlString(`${schema}.${name}`)}, target_type => ${sqlString(label)}, event_prefix => ${sqlString(label)}, deferred => true${archive === undefined ? "" : `, archive_column => ${sqlString(archive)}`});`,
    );
    triggers.push(
      auditTrigger(`${schema}.${name}`, {
        target_type: label,
        event_prefix: label,
        ...(archive === undefined ? {} : { archive_column: archive }),
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
 * The `when` condition of a row audit trigger: false while an import run with
 * `imports.audit: summary` writes, so the function never starts for a row the
 * run audits per entity at its end (ADR 0141). The import check keeps a user
 * session from setting the flag.
 */
export const AUDIT_NOT_IMPORT_SUMMARY =
  "better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary'";

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

  return `create ${deferred ? "constraint " : ""}trigger bsb_audit after insert or update or delete on ${target} ${deferred ? "deferrable initially deferred " : ""}for each row when (${AUDIT_NOT_IMPORT_SUMMARY}) execute function better_supabase.audit_row_change(${sqlString(settings)});`;
}

/**
 * The three statement triggers `audit(statement => true)` creates, in order.
 * `referencing` names the transition tables the function reads.
 */
export const AUDIT_STATEMENT_TRIGGERS = [
  ["bsb_audit_stmt_insert", "insert", "referencing new table as new_rows"],
  [
    "bsb_audit_stmt_update",
    "update",
    "referencing old table as old_rows new table as new_rows",
  ],
  ["bsb_audit_stmt_delete", "delete", "referencing old table as old_rows"],
] as const;

/** One statement trigger. `settings` is the SQL literal of its argument. */
export function auditStatementTrigger(
  name: string,
  event: string,
  referencing: string,
  target: string,
  when: string,
  settings: string,
): string {
  return `create trigger ${name} after ${event} on ${target} ${referencing} for each statement when (${when}) execute function better_supabase.audit_statement_change(${settings})`;
}

/**
 * The three static statement triggers for `target`, with the same settings
 * shape a row trigger stores. A schema diff keeps a `create trigger`, which it
 * skips for a top-level `select better_supabase.audit(...)`.
 */
export function auditStatementTriggers(
  target: string,
  names: Readonly<Record<string, unknown>>,
): string {
  const settings = JSON.stringify({ ignore: [], redact: [], ...names });

  return AUDIT_STATEMENT_TRIGGERS.map(([name, event, referencing]) =>
    auditStatementTrigger(
      name,
      event,
      referencing,
      target,
      AUDIT_NOT_IMPORT_SUMMARY,
      sqlString(settings),
    ),
  )
    .map((statement) => `${statement};`)
    .join("\n");
}

/**
 * The `execute format(...)` lines `audit()` runs for statement mode. The format
 * string is the static trigger with `%s` for the table and `%L` for the
 * settings, so the two forms stay the same statement.
 */
export function auditStatementExecute(): string {
  return AUDIT_STATEMENT_TRIGGERS.map(([name, event, referencing]) => {
    const body = auditStatementTrigger(
      name,
      event,
      referencing,
      "%s",
      AUDIT_NOT_IMPORT_SUMMARY,
      "%L",
    ).replaceAll("'", "''");

    return `    execute format(\n      '${body}',\n      target, base_settings::text\n    );`;
  }).join("\n");
}
