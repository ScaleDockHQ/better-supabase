import type { BlockSqlContext } from "../context.ts";

import { auditWrite } from "./audit-values.ts";

/**
 * The log columns a change fills, as logical name and SQL value. `expr` is the
 * operation as lower case text and the event kind: the row trigger reads
 * `tg_op`, the statement trigger the `op` of each paired row.
 */
export function rowPairs(
  ctx: BlockSqlContext,
  snapshots: boolean,
  expr: { op: string; kind: string },
  context: readonly (readonly [string, string])[],
): (readonly [string, string])[] {
  return [
    ["table", "tg_table_schema || '.' || tg_table_name"],
    [
      "record",
      "(select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord))",
    ],
    ["op", expr.op],
    ...(snapshots
      ? ([
          ["old", "old_row"],
          ["new", "new_row"],
        ] as const)
      : []),
    ["changed", "changed_columns"],
    ["actor", "coalesce(auth.uid(), better_supabase.acting_member())"],
    ["actorRole", "coalesce(auth.jwt() ->> 'role', current_user)"],
    ["tenant", "row_tenant"],
    [
      "impersonatedBy",
      "case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end",
    ],
    ["impersonationReason", "auth.jwt() -> 'act' ->> 'reason'"],
    [
      "supportSession",
      "case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end",
    ],
    [
      "eventType",
      `coalesce(entry.event_prefix, tg_table_name) || '.' || ${expr.kind}`,
    ],
    [
      "category",
      auditWrite(ctx, "category", "coalesce(entry.category, 'data')"),
    ],
    ["outcome", auditWrite(ctx, "outcome", "'success'")],
    ["source", auditWrite(ctx, "source", "'database'")],
    ["targetType", "coalesce(entry.target_type, tg_table_name)"],
    ...context,
  ];
}
