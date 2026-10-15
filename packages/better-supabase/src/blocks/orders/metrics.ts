import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import {
  defineMetric,
  type MetricDefinition,
} from "../../core/metric-definition.ts";

export interface OrderMetricsOptions {
  /** The orders module's schema. Default `better_supabase`. */
  readonly schema?: string;
  /** The currency revenue and order value add up in; other orders are left out. */
  readonly currency: string;
  /** The IANA time zone buckets start in. Default `UTC`. */
  readonly tz?: string;
}

export type OrderMetrics = readonly [
  MetricDefinition<"orders">,
  MetricDefinition<"revenue">,
  MetricDefinition<"average_order_value">,
];

/**
 * Metric definitions over the orders table: orders placed, and revenue and
 * average order value from paid orders, in minor units of `currency`. Pass
 * them to `blocks.metrics.options.metrics` and `createMetrics`.
 */
export function orderMetrics(options: OrderMetricsOptions): OrderMetrics {
  const shared = {
    table: `${options.schema ?? DEFAULT_BLOCK_SCHEMA}.orders`,
    tenant: "tenant_id",
    ...(options.tz === undefined ? {} : { tz: options.tz }),
  };
  const paid = {
    ...shared,
    timeColumn: "paid_at",
    where: { currency: options.currency },
    unit: options.currency,
  };
  return [
    defineMetric({
      key: "orders",
      label: "Orders",
      measure: "count",
      timeColumn: "placed_at",
      ...shared,
    }),
    defineMetric({
      key: "revenue",
      label: "Revenue",
      measure: { sum: "total" },
      ...paid,
    }),
    defineMetric({
      key: "average_order_value",
      label: "Average order value",
      measure: { avg: "total" },
      ...paid,
    }),
  ];
}

/** The events that add rows to `orderMetrics`, for `metricsSink` or `createBlocks({ metricEvents })`. */
export const ORDER_METRIC_EVENTS: {
  readonly "order.placed": readonly ["orders"];
  readonly "order.paid": readonly ["revenue", "average_order_value"];
} = {
  "order.placed": ["orders"],
  "order.paid": ["revenue", "average_order_value"],
};
