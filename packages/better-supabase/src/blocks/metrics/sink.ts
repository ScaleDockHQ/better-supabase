import type { EventSink } from "../../events/cloud-event.ts";
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
}

/**
 * An outbox sink that re-aggregates the buckets an event's rows fall in,
 * so charts catch up without waiting for the periodic rollup:
 * `outbox.relay('metrics', metricsSink(metrics, { on }))`. It reads the
 * event's `time` (now when it has none) and runs one rollup per metric over
 * the batch's window. Build `metrics` with a service transport.
 */
export function metricsSink(
  metrics: Pick<Metrics, "rollup">,
  options: MetricsSinkOptions,
): EventSink {
  return {
    async send(events) {
      const windows = new Map<
        string,
        { since: Temporal.Instant; until: Temporal.Instant }
      >();
      for (const event of events) {
        const entry =
          options.on[stripTypePrefix(event.type, options.typePrefix)];
        if (entry === undefined) continue;
        const at =
          event.time === undefined
            ? nowInstant()
            : temporal().Instant.from(event.time);
        for (const metric of typeof entry === "string" ? [entry] : entry) {
          const window = windows.get(metric);
          windows.set(metric, {
            since:
              window && temporal().Instant.compare(window.since, at) < 0
                ? window.since
                : at,
            until:
              window && temporal().Instant.compare(window.until, at) > 0
                ? window.until
                : at,
          });
        }
      }
      for (const [metric, window] of windows) {
        await metrics
          .rollup({
            metric,
            since: window.since,
            until: window.until.add({ milliseconds: 1 }),
          })
          .orThrow();
      }
    },
  };
}
