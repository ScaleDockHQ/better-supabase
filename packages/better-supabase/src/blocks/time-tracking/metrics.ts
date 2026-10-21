import type { CloudEvent } from "../../events/cloud-event.ts";

import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import { isRecord } from "../../core/guards.ts";
import {
  defineMetric,
  type MetricDefinition,
} from "../../core/metric-definition.ts";

export interface TimeTrackingMetricsOptions {
  /** The time-tracking module's schema. Default `better_supabase`. */
  readonly schema?: string;
  /** The IANA time zone buckets start in. Default `UTC`. */
  readonly tz?: string;
}

export type TimeTrackingMetrics = readonly [
  MetricDefinition<"time_tracked", "billable" | "user_id" | "subject_type">,
];

/**
 * A metric over finished time entries: the seconds tracked per day the entry
 * started, which a series can filter or group by `billable`, `user_id` and
 * `subject_type`. Running timers count once they stop.
 */
export function timeTrackingMetrics(
  options: TimeTrackingMetricsOptions = {},
): TimeTrackingMetrics {
  return [
    defineMetric({
      key: "time_tracked",
      label: "Time tracked",
      table: `${options.schema ?? DEFAULT_BLOCK_SCHEMA}.time_entries`,
      tenant: "tenant_id",
      measure: { sum: "seconds" },
      timeColumn: "started_at",
      dimensions: ["billable", "user_id", "subject_type"],
      unit: "s",
      ...(options.tz === undefined ? {} : { tz: options.tz }),
    }),
  ];
}

/**
 * The events that change `timeTrackingMetrics`, for `metricsSink` or
 * `createBlocks({ metricEvents })`.
 */
export const TIME_TRACKING_METRIC_EVENTS: {
  readonly "time_entry.recorded": readonly ["time_tracked"];
  readonly "time_entry.updated": readonly ["time_tracked"];
  readonly "time_entry.deleted": readonly ["time_tracked"];
} = {
  "time_entry.recorded": ["time_tracked"],
  "time_entry.updated": ["time_tracked"],
  "time_entry.deleted": ["time_tracked"],
};

/**
 * The entry's `startedAt`, the time its seconds are bucketed by, for
 * `metricsSink({ time })` or `createBlocks({ metricTime })`. An update that
 * moves the entry to another day also returns its `previousStartedAt`, so the
 * old day's total drops. Undefined for other events, so they keep their own
 * time.
 */
export function timeEntryMetricTime(
  event: CloudEvent,
): string | readonly string[] | undefined {
  if (!event.type.includes("time_entry.") || !isRecord(event.data)) {
    return undefined;
  }

  const startedAt = event.data["startedAt"];

  if (typeof startedAt !== "string") {
    return undefined;
  }

  const previous = event.data["previousStartedAt"];

  return typeof previous === "string" && previous !== startedAt
    ? [startedAt, previous]
    : startedAt;
}
