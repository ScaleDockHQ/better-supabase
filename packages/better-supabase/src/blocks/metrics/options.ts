import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.metrics.options`. */
export type MetricsSqlOptions = {
  readonly metrics?: unknown;
  readonly window?: string;
};

export const metricsSqlOptions: BlockOptionsSchema<MetricsSqlOptions> =
  blockOptions<MetricsSqlOptions>({
    metrics: option.unknown(),
    window: option.string({ default: "3 days" }),
  });
