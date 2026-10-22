import type { BlockSqlUpgrade } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { renameSql } from "../shared.ts";

/** The audit module's `upgrade` steps, from each installed version. */
export const AUDIT_UPGRADES: readonly BlockSqlUpgrade[] = [
  {
    from: 1,
    description:
      "Renames audit_log to audit_events (with a read-only audit_log view, dropped in 0.6), at to occurred_at, org_id to organization_id and audit_trigger() to audit_row_change(); audit() takes redact, category, event_prefix, target_type and tenant_column; audit_event() records semantic events; purge_audit_log() takes a tenant.",
    sql: (ctx) =>
      [
        ctx.manages
          ? renameSql({
              schema: ctx.tableName("log").schema,
              table: "audit_log",
              tables: [["audit_log", ctx.tableName("log").name]],
              columns: [
                ["at", "occurred_at"],
                ["org_id", "organization_id"],
              ],
              indexes: [
                ["audit_log_record_idx", "audit_events_record_idx"],
                ["audit_log_org_idx", "audit_events_organization_idx"],
              ],
            })
          : "",
        renameSql({
          schema: "better_supabase",
          table: "audited_tables",
          functions: [["audit_trigger", "audit_row_change", ""]],
        }),
        "drop function if exists better_supabase.audit(regclass, text[], boolean);",
        "drop function if exists better_supabase.purge_audit_log(interval, integer);",
      ]
        .filter(Boolean)
        .join("\n"),
  },
  {
    from: 2,
    description:
      "Entries record the actor kind and label, the tenant and target labels, a summary, the request and correlation ids and the scope (managed tables; adopted ones map the columns they have); the restricted table keeps the session id and per-column changes; audit() takes label_column and audit_event() takes summary, target_label and correlation_id; audit_schema_calls() and audit_schema() register a schema's tenant tables.",
    sql: (ctx) =>
      [
        "drop function if exists better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text);",
        `drop function if exists better_supabase.audit_event(text, text, text, text, text, text, ${ctx.idType}, jsonb, text, jsonb, uuid);`,
      ].join("\n"),
  },
  {
    from: 3,
    description:
      "The row trigger reads the JWT and the request headers once per row; list_audit_events and count_audit_events filter only on the arguments you pass; per-tenant retention deletes tenant by tenant through the index.",
    sql: () => "",
  },
  {
    from: 4,
    description:
      "Drops the read-only audit_log view that 0.5 kept for the 0.4 names; read better_supabase.audit_events.",
    sql: (ctx) =>
      `drop view if exists ${sqlIdent(ctx.tableName("log").schema)}.audit_log;`,
  },
  {
    from: 5,
    description:
      "Row changes and audit_event read the request and correlation ids from the better_supabase.request_id and better_supabase.correlation_id settings, then from the requestIdHeader and correlationIdHeader headers, and keep only ids of up to 128 safe characters; managed logs index correlation_id.",
    sql: () => "",
  },
  {
    from: 6,
    description:
      "revert_audit_entries(entries) writes the old values of row changes back as the caller and returns the entries it wrote, for an undo token; members need audit.revert.",
    sql: () => "",
  },
  {
    from: 7,
    description:
      "purge_audit_log keeps entries for the data-lifecycle retention policies and skips entries under a legal hold; with options.chain the log gains chain_seq, prev_hash and row_hash (new entries only), verify_audit_chain and audit_checkpoints. options.partitioned applies to new logs only.",
    sql: () => "",
  },
  {
    from: 8,
    description:
      "audit_event_many(events) records a batch of semantic events in one call, with audit_event's checks per event and an {id} or {error} result each; audit_row_change() is no longer executable by API roles.",
    sql: () => "",
  },
];
