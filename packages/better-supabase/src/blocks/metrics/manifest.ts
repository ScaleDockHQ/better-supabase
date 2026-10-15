import type { BlockOf } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createMetrics } from "./metrics.ts";
import { metricsSink } from "./sink.ts";

/** The `metrics` block's manifest (ADR 0029). */
export const metricsBlock: BlockOf<"metrics", typeof createMetrics> =
  defineBlock({
    name: "metrics",
    sql: ["metrics"],
    options: {
      metrics: optionKeys(["metrics", "window"]),
    },
    provides: {
      sink: (client, options) =>
        options.sink === undefined
          ? undefined
          : metricsSink(client, options.sink),
    },
    create: createMetrics,
    category: "operations",
  });
