import type { CloudEvent } from "../../events/cloud-event.ts";

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
      table: `${options.schema ?? "better_supabase"}.time_entries`,
      tenant: "tenant_id",
      measure: { sum: "seconds" },
      timeColumn: "started_at",
      dimensions: ["billable", "user_id", "subject_type"],
      unit: "s",
      ...(options.tz === undefined ? {} : { tz: options.tz }),
    }),
  ];
}

/** The events that change `timeTrackingMetrics`, for `metricsSink` or `createBlocks({ metricEvents })`. */
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
 * `metricsSink({ time })` or `createBlocks({ metricTime })`. Undefined for
 * other events, so they keep their own time.
 */
export function timeEntryMetricTime(event: CloudEvent): string | undefined {
  if (!event.type.includes("time_entry.") || !isRecord(event.data))
    return undefined;
  const startedAt = event.data["startedAt"];
  return typeof startedAt === "string" ? startedAt : undefined;
}
