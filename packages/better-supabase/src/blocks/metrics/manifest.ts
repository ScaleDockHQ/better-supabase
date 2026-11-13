import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createMetrics } from "./metrics.ts";
import { metricsSqlOptions } from "./options.ts";
import { metricsSink } from "./sink.ts";

/** The `metrics` block's manifest (ADR 0029). */
export const metricsBlock: BlockOf<
  "metrics",
  typeof createMetrics,
  Record<never, never>,
  Record<never, never>,
  "sink"
> = defineBlock({
  name: "metrics",
  sql: ["metrics"],
  options: { metrics: metricsSqlOptions },
  provides: {
    sink: (client, options) =>
      options.sink === undefined
        ? undefined
        : metricsSink(client, options.sink),
  },
  create: createMetrics,
  category: "admin",
  entities: { metric: { mutability: "read-only" } },
  description:
    "Metrics declared with defineMetric over a table (count, sum or avg per time bucket and dimension), rolled up into metric_points or read from the table, with metric_series and metric_value checked against a permission in the tenant.",
  recipes: ["metrics-dashboard"],
});
