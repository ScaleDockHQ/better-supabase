import { describe, expect, it } from "vitest";

import type { CloudEvent } from "../../../src/events/cloud-event.ts";

import { metricsSink } from "../../../src/blocks/metrics/index.ts";
import {
  TIME_TRACKING_METRIC_EVENTS,
  timeEntryMetricTime,
  timeTrackingMetrics,
} from "../../../src/blocks/time-tracking/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const event = (type: string, data?: unknown, time?: string): CloudEvent => ({
  specversion: "1.0",
  id: type,
  source: "test",
  type: `dev.better-supabase.${type}`,
  ...(time === undefined ? {} : { time }),
  ...(data === undefined ? {} : { data }),
});

describe("timeTrackingMetrics", () => {
  it("sums finished seconds per start day in the module's schema", () => {
    const [tracked] = timeTrackingMetrics();
    expect(tracked).toMatchObject({
      key: "time_tracked",
      table: "better_supabase.time_entries",
      tenant: "tenant_id",
      measure: { sum: "seconds" },
      timeColumn: "started_at",
      dimensions: ["billable", "user_id", "subject_type"],
      unit: "s",
    });
    expect(tracked).not.toHaveProperty("tz");
    expect(
      timeTrackingMetrics({ schema: "work", tz: "Europe/Amsterdam" })[0],
    ).toMatchObject({
      table: "work.time_entries",
      tz: "Europe/Amsterdam",
    });
  });

  it("buckets entry events by the time the entry started", async () => {
    expect(
      timeEntryMetricTime(
        event("time_entry.recorded", { startedAt: "2026-09-28T09:00:00Z" }),
      ),
    ).toBe("2026-09-28T09:00:00Z");
    expect(
      timeEntryMetricTime(
        event("time_entry.updated", {
          startedAt: "2026-09-28T09:00:00Z",
          previousStartedAt: "2026-09-20T09:00:00Z",
        }),
      ),
    ).toEqual(["2026-09-28T09:00:00Z", "2026-09-20T09:00:00Z"]);
    expect(
      timeEntryMetricTime(
        event("time_entry.updated", {
          startedAt: "2026-09-28T09:00:00Z",
          previousStartedAt: "2026-09-28T09:00:00Z",
        }),
      ),
    ).toBe("2026-09-28T09:00:00Z");
    expect(
      timeEntryMetricTime(event("time_entry.recorded", { startedAt: 3 })),
    ).toBeUndefined();
    expect(timeEntryMetricTime(event("time_entry.recorded"))).toBeUndefined();
    expect(
      timeEntryMetricTime(
        event("order.paid", { startedAt: "2026-09-28T09:00:00Z" }),
      ),
    ).toBeUndefined();

    const requests: unknown[] = [];

    const sink = metricsSink(
      {
        rollup: (request) => {
          requests.push({
            metric: request?.metric,
            since: request?.since?.toString(),
          });

          return AsyncResult.ok(1);
        },
      },
      {
        on: { ...TIME_TRACKING_METRIC_EVENTS, "order.paid": "revenue" },
        time: timeEntryMetricTime,
      },
    );

    await sink.send([
      event(
        "time_entry.updated",
        {
          startedAt: "2026-09-28T09:00:00Z",
          previousStartedAt: "2026-09-20T09:00:00Z",
        },
        "2026-10-02T10:00:00Z",
      ),
      event(
        "order.paid",
        { startedAt: "2026-09-01T00:00:00Z" },
        "2026-10-02T11:00:00Z",
      ),
    ]);
    expect(requests).toEqual([
      { metric: "time_tracked", since: "2026-09-28T09:00:00Z" },
      { metric: "time_tracked", since: "2026-09-20T09:00:00Z" },
      { metric: "revenue", since: "2026-10-02T11:00:00Z" },
    ]);
  });
});
