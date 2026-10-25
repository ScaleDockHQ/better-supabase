import type { DoctorContext, FindingInput } from "./rules.ts";

import { catalogOf } from "./shared.ts";

/**
 * The table each block's `options.partitioned` partitions, and the option it
 * also needs.
 */
const PARTITIONED_TABLES: readonly {
  readonly block: string;
  readonly table: string;
  readonly requires?: string;
}[] = [
  { block: "audit", table: "audit_events" },
  { block: "outbox", table: "outbox_events" },
  { block: "usage", table: "usage_history", requires: "history" },
  { block: "webhooks", table: "webhook_deliveries" },
  { block: "notifications", table: "notification_delivery_events" },
];

export function unpartitionedTables(context: DoctorContext): FindingInput[] {
  const { tables } = catalogOf(context);

  return PARTITIONED_TABLES.flatMap(({ block, table, requires }) => {
    const options = context.config.blocks[block]?.options ?? {};

    if (
      !context.config.blockNames.includes(block) ||
      options["partitioned"] !== true ||
      (requires !== undefined && options[requires] !== true)
    ) {
      return [];
    }

    const found = tables.find(
      (candidate) =>
        candidate.schema === "better_supabase" && candidate.name === table,
    );

    if (found?.primaryKey.length !== 1) {
      return [];
    }

    return [
      {
        message: `better_supabase.${table} isn't partitioned, so blocks.${block}.options.partitioned has no effect on it. Postgres can't convert it in place: copy the rows into a partitioned table in a maintenance window, or turn the option off.`,
        target: `better_supabase.${table}`,
      },
    ];
  });
}
