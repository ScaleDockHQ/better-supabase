import { defineMetric } from "better-supabase/blocks/metrics";

/**
 * The dashboard's metrics, shared by the config (the SQL module) and the
 * client. `rollup: false` reads `customers` on every request, so a status
 * change shows at once without a rollup job. Archived customers drop out
 * because the `customer` subject's `deletedAt` is `archived_at`.
 */
export const metrics = [
  defineMetric({
    key: "customers",
    label: "Customers",
    table: "public.customers",
    measure: "count",
    timeColumn: "created_at",
    dimensions: ["status"],
    rollup: false,
  }),
] as const;
