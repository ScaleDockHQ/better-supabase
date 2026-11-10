import type { Rule } from "./rules.ts";

import { errorText } from "../core/errors.ts";

/** Row estimate from which the audit log is worth converting to partitions. */
export const PARTITION_HINT_ROWS = 1_000_000;

export const PARTITION_HINT_RULES: readonly Rule[] = [
  {
    code: "BS399",
    severity: "info",
    title: "Large audit log is not partitioned",
    description: `\`better_supabase.audit_events\` is a plain table with an estimated ${PARTITION_HINT_ROWS.toLocaleString("en-US")} rows or more, so its retention purge deletes row by row and a date-range read scans one large heap. Set \`blocks.audit.options.partitioned\` and call \`better_supabase.convert_audit_log_to_partitioned()\` to move it to monthly partitions without blocking writes for the copy (ADR 0601). The estimate is \`pg_class.reltuples\`, so a table that was never analyzed reports nothing. Needs a database; saved snapshots skip it.`,
    async check(context) {
      const db = context.database;

      if (
        !db ||
        "skipped" in db ||
        !context.config.blockNames.includes("audit")
      ) {
        return [];
      }

      try {
        const rows = await db.query<{ rows: number | string }>(
          `select c.reltuples::int8 as rows from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'better_supabase' and c.relname = 'audit_events' and c.relkind = 'r'`,
        );

        const estimate = Number(rows[0]?.rows ?? 0);

        return estimate >= PARTITION_HINT_ROWS
          ? [
              {
                message: `better_supabase.audit_events holds about ${estimate.toLocaleString("en-US")} rows and is not partitioned. Turn on blocks.audit.options.partitioned and call better_supabase.convert_audit_log_to_partitioned() in a quiet period.`,
                target: "better_supabase.audit_events",
              },
            ]
          : [];
      } catch (cause) {
        return [
          {
            message: `Could not read the audit log size (${db.describe}): ${errorText(cause)}`,
          },
        ];
      }
    },
  },
];
