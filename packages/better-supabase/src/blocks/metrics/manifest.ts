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
  recipes: ["metrics-dashboard"],
});
