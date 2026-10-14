import type { CloudEvent, EventSink } from "../../events/cloud-event.ts";
import type { Metrics } from "./metrics.ts";

import { temporal } from "../../core/temporal-required.ts";
import { nowInstant } from "../../core/temporal.ts";
import { stripTypePrefix } from "../../events/cloud-event.ts";

export interface MetricsSinkOptions {
  /**
   * Event type (without `typePrefix`) to the metrics whose rows the event
   * adds, such as `{ "order.placed": ["orders", "revenue"] }`.
   */
  readonly on: Readonly<Record<string, string | readonly string[] | undefined>>;
  /** Stripped from each event type. Defaults to `dev.better-supabase`. */
  readonly typePrefix?: string;
  /**
   * When the event's rows sit in time, for events about rows bucketed by
   * another time than when the event happened, such as time logged for a
   * past day (`timeEntryMetricTime`). Several times re-aggregate each of
   * their buckets, for an event that moves a row from one day to another.
   * Default: the event's `time`.
   */
  readonly time?: (event: CloudEvent) => string | readonly string[] | undefined;
}

type Window = { since: Temporal.Instant; until: Temporal.Instant };

function widen(window: Window | undefined, at: Temporal.Instant): Window {
  if (window === undefined) return { since: at, until: at };
  return {
    since: temporal().Instant.compare(window.since, at) < 0 ? window.since : at,
    until: temporal().Instant.compare(window.until, at) > 0 ? window.until : at,
  };
}

function timesOf(
  event: CloudEvent,
  options: MetricsSinkOptions,
): readonly Temporal.Instant[] {
  const time = options.time?.(event) ?? event.time;
  const times =
    time === undefined ? [] : typeof time === "string" ? [time] : time;
  return times.length === 0
    ? [nowInstant()]
    : times.map((value) => temporal().Instant.from(value));
}

/**
 * An outbox sink that re-aggregates the buckets an event's rows fall in,
 * so charts catch up without waiting for the periodic rollup:
 * `outbox.relay('metrics', metricsSink(metrics, { on }))`. It reads the
 * event's `time` (or `options.time`, now when neither has one) and runs one
 * rollup per metric for each UTC day the batch's times fall on, so a row
 * moved to another day fixes both days without re-aggregating the days
 * between. Build `metrics` with a service transport.
 */
export function metricsSink(
  metrics: Pick<Metrics, "rollup">,
  options: MetricsSinkOptions,
): EventSink {
  return {
    async send(events) {
      const windows = new Map<string, Map<string, Window>>();
      for (const event of events) {
        const entry =
          options.on[stripTypePrefix(event.type, options.typePrefix)];
        if (entry === undefined) continue;
        const times = timesOf(event, options);
        for (const metric of typeof entry === "string" ? [entry] : entry) {
          const days = windows.get(metric) ?? new Map<string, Window>();
          windows.set(metric, days);
          for (const at of times) {
            const day = at.toString().slice(0, 10);
            days.set(day, widen(days.get(day), at));
          }
        }
      }
      for (const [metric, days] of windows) {
        for (const window of days.values()) {
          await metrics
            .rollup({
              metric,
              since: window.since,
              until: window.until.add({ milliseconds: 1 }),
            })
            .orThrow();
        }
      }
    },
  };
}
