import type { MetricSeries } from "./metrics.ts";

/** One row of chart data: the bucket, its value and one key per group. */
export type MetricChartRow = Readonly<
  Record<string, string | number | null>
> & { readonly date: string; readonly value: number | null };

export interface MetricChartOptions {
  /** The label of each bucket. Default: its ISO 8601 instant. */
  readonly format?: (bucket: Temporal.Instant) => string;
}

/**
 * Rows in the shape Recharts (and chart components built on it) read: `{ date,
 * value, previous?, ...groups }`, one per bucket. `previous` is the bucket at
 * the same position of the compared range.
 */
export function toChartData(
  series: MetricSeries,
  options: MetricChartOptions = {},
): readonly MetricChartRow[] {
  const format = options.format ?? ((bucket) => bucket.toString());

  return series.points.map((point, index) => {
    const previous = series.previous?.[index];

    return {
      ...point.groups,
      date: format(point.bucket),
      value: point.value,
      ...(series.previous === undefined
        ? {}
        : { previous: previous?.value ?? null }),
    };
  });
}
