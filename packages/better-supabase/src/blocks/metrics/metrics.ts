import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type {
  MetricDefinition,
  MetricGrain,
  MetricWhereValue,
} from "../../core/metric-definition.ts";
import type { JobHandler } from "../jobs/types.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

/** The queue `metrics.job` handles: re-aggregates a window of rollups. */
export const METRICS_ROLLUP_QUEUE = "metrics.rollup";

/** The key of one of `M`'s metrics, any string without definitions. */
export type MetricKey<M extends readonly MetricDefinition[]> = M[number]["key"];

/** The dimensions of metric `K` in `M`. */
export type MetricDimension<
  M extends readonly MetricDefinition[],
  K extends string,
> =
  Extract<M[number], { readonly key: K }> extends MetricDefinition<
    string,
    infer D
  >
    ? D
    : never;

export interface MetricsOptions<
  M extends readonly MetricDefinition[],
> extends Pick<BlockOptions, "transport" | "service" | "schema" | "mappers"> {
  /**
   * The same `defineMetric` definitions as `blocks.metrics.options.metrics`,
   * so `series` and `kpi` type the keys and dimensions.
   */
  readonly metrics?: M;
  /** `withBlockHooks` hooks around the methods. */
  readonly hooks?: BlockHooks<Metrics<M>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** `[from, until)`. */
export interface MetricRange {
  readonly from: Temporal.Instant;
  readonly until: Temporal.Instant;
}

export interface MetricReadOptions<D extends string = string> {
  readonly organizationId: string;
  /** Rows whose dimensions equal these values. */
  readonly filter?: Readonly<Partial<Record<D, MetricWhereValue>>>;
  /** Also reads the range of the same length just before. */
  readonly compare?: "previous";
}

export interface MetricSeriesOptions<
  D extends string = string,
> extends MetricReadOptions<D> {
  /** Default `day`. */
  readonly grain?: MetricGrain;
  /** Splits each bucket by one dimension into `groups`. */
  readonly groupBy?: D;
}

export interface MetricPoint {
  /** The bucket's start, in the metric's time zone. */
  readonly bucket: Temporal.Instant;
  /** `null` for an average over no rows. */
  readonly value: number | null;
  /** The rows counted. */
  readonly count: number;
  /** The value per dimension value with `groupBy`; `""` collects nulls. */
  readonly groups?: Readonly<Record<string, number | null>>;
}

export interface MetricSeries {
  readonly metric: string;
  readonly grain: MetricGrain;
  readonly range: MetricRange;
  readonly points: readonly MetricPoint[];
  /** With `compare: "previous"`: the range before, bucket for bucket. */
  readonly previous?: readonly MetricPoint[];
}

export interface Kpi {
  readonly metric: string;
  readonly value: number | null;
  readonly count: number;
  /** With `compare: "previous"`: the value over the range before. */
  readonly previous?: number | null;
  /** `(value - previous) / |previous|`, `null` when there is nothing to compare. */
  readonly change?: number | null;
  readonly trend?: "up" | "down" | "flat";
}

/** A declared metric, as `metric_definitions()` returns it. */
export interface MetricInfo {
  readonly key: string;
  readonly label: string | null;
  readonly unit: string | null;
  readonly measure: "count" | "sum" | "avg";
  readonly dimensions: readonly string[];
  readonly grains: readonly MetricGrain[];
  readonly tz: string;
}

export interface MetricsRollupRequest {
  /** One metric. Default: all of them. */
  readonly metric?: string;
  /** Default: `blocks.metrics.options.window` ago. */
  readonly since?: Temporal.Instant;
  /** Default: now. */
  readonly until?: Temporal.Instant;
}

export interface Metrics<
  M extends readonly MetricDefinition[] = readonly MetricDefinition[],
> {
  /** One point per bucket of `range`, gaps filled. Checked against the metric's permission. */
  series<K extends MetricKey<M>>(
    metric: K,
    range: MetricRange,
    options: MetricSeriesOptions<MetricDimension<M, K>>,
  ): AsyncResult<MetricSeries>;
  /** The total over `range`, for a stat card. */
  kpi<K extends MetricKey<M>>(
    metric: K,
    range: MetricRange,
    options: MetricReadOptions<MetricDimension<M, K>>,
  ): AsyncResult<Kpi>;
  definitions(): AsyncResult<readonly MetricInfo[]>;
  /**
   * Re-aggregates the rollups of a window, so late or changed rows land.
   * Service only. Resolves to the number of points written.
   */
  rollup(request?: MetricsRollupRequest): AsyncResult<number>;
  /** The handler for `metrics.rollup` jobs, whose payload is a `MetricsRollupRequest` as JSON. */
  readonly job: JobHandler<unknown>;
}

const numberOrNull = (value: unknown): number | null =>
  value === null || value === undefined ? null : Number(value);

function pointOf(row: Record<string, unknown>): MetricPoint {
  const groups = row["groups"];
  return {
    bucket: requiredInstant(row["bucket"], "bucket"),
    value: numberOrNull(row["value"]),
    count: Number(row["count"] ?? 0),
    ...(isRecord(groups)
      ? {
          groups: Object.fromEntries(
            Object.entries(groups).map(([key, value]) => [
              key,
              numberOrNull(value),
            ]),
          ),
        }
      : {}),
  };
}

function infoOf(row: Record<string, unknown>): MetricInfo {
  const measure = textOf(row["measure"]);
  return {
    key: textOf(row["key"]),
    label: optionalText(row["label"]) ?? null,
    unit: optionalText(row["unit"]) ?? null,
    measure: measure === "sum" || measure === "avg" ? measure : "count",
    dimensions: stringsOf(row["dimensions"]),
    // SAFETY: metric_definitions() lists the grains defineMetric checked.
    grains: stringsOf(row["grains"]) as readonly MetricGrain[],
    tz: textOf(row["tz"]),
  };
}

/** The range of the same length that ends where `range` starts. */
export function previousRange(range: MetricRange): MetricRange {
  return {
    from: range.from.subtract(range.until.since(range.from)),
    until: range.from,
  };
}

/** How `value` moved from `previous`. */
export function compareValues(
  value: number | null,
  previous: number | null,
): Pick<Kpi, "change" | "trend"> {
  if (value === null || previous === null) return { change: null };
  const trend = value > previous ? "up" : value < previous ? "down" : "flat";
  return {
    change: previous === 0 ? null : (value - previous) / Math.abs(previous),
    trend,
  };
}

function requestOf(value: unknown): MetricsRollupRequest {
  if (value !== undefined && value !== null && !isRecord(value)) {
    throw new TypeError(`${METRICS_ROLLUP_QUEUE} needs an object payload`);
  }
  const payload = value ?? {};
  const metric = optionalText(payload["metric"]);
  const since = optionalText(payload["since"]);
  const until = optionalText(payload["until"]);
  return {
    ...(metric === undefined ? {} : { metric }),
    ...(since === undefined ? {} : { since: temporal().Instant.from(since) }),
    ...(until === undefined ? {} : { until: temporal().Instant.from(until) }),
  };
}

/**
 * The `metrics` SQL module as typed calls: `series` and `kpi` for charts
 * and stat cards as the caller, and `rollup` with a service transport.
 */
export function createMetrics<
  const M extends readonly MetricDefinition[] = readonly MetricDefinition[],
>(options: MetricsOptions<M>): Metrics<M> {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const readSeries = (
    metric: string,
    range: MetricRange,
    read: MetricSeriesOptions,
    grain: MetricGrain,
  ) =>
    call(
      "metric_series",
      {
        p_metric: metric,
        p_tenant: read.organizationId,
        p_from: range.from.toString(),
        p_until: range.until.toString(),
        p_grain: grain,
        p_dims: read.filter ?? {},
        p_group_by: read.groupBy ?? null,
      },
      (value) => recordsOf(value, "metric_series").map(pointOf),
    );
  const readValue = (
    metric: string,
    range: MetricRange,
    read: MetricReadOptions,
  ) =>
    call(
      "metric_value",
      {
        p_metric: metric,
        p_tenant: read.organizationId,
        p_from: range.from.toString(),
        p_until: range.until.toString(),
        p_dims: read.filter ?? {},
      },
      (value) => {
        const row = recordOf(value, "metric_value");
        return {
          value: numberOrNull(row["value"]),
          count: Number(row["count"] ?? 0),
        };
      },
    );
  const rollup: Metrics<M>["rollup"] = (request = {}) =>
    service(
      "metrics_rollup",
      {
        p_metric: request.metric ?? null,
        p_since: request.since?.toString() ?? null,
        p_until: request.until?.toString() ?? null,
      },
      Number,
    );
  const client: Metrics<M> = {
    series(metric, range, read) {
      const grain = read.grain ?? "day";
      return readSeries(metric, range, read, grain).andThen((points) =>
        read.compare === "previous"
          ? readSeries(metric, previousRange(range), read, grain).map(
              (previous) => ({ metric, grain, range, points, previous }),
            )
          : AsyncResult.ok({ metric, grain, range, points }),
      );
    },
    kpi(metric, range, read) {
      return readValue(metric, range, read).andThen((current) =>
        read.compare === "previous"
          ? readValue(metric, previousRange(range), read).map((before) => ({
              metric,
              ...current,
              previous: before.value,
              ...compareValues(current.value, before.value),
            }))
          : AsyncResult.ok({ metric, ...current }),
      );
    },
    definitions: () =>
      call("metric_definitions", {}, (value) =>
        recordsOf(value, "metric_definitions").map(infoOf),
      ),
    rollup,
    job: async (payload) => {
      await rollup(requestOf(payload)).orThrow();
    },
  };
  return withBlockHooks(client, options.hooks, {
    block: "metrics",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
