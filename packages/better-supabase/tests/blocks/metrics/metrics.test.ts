import { describe, expect, expectTypeOf, it } from "vitest";

import type { CloudEvent } from "../../../src/events/cloud-event.ts";

import {
  compareValues,
  createMetrics,
  defineMetric,
  metricsSink,
  previousRange,
  toChartData,
} from "../../../src/blocks/metrics/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

function recorder(
  results: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: unknown) {
        // SAFETY: the client passes named arguments as an object.
        const named = args as Record<string, unknown>;
        calls.push({ fn, args: named });
        return Promise.resolve(results(fn, named));
      },
    },
  };
}

const at = (iso: string) => Temporal.Instant.from(iso);
const range = {
  from: at("2026-10-02T00:00:00Z"),
  until: at("2026-10-04T00:00:00Z"),
};

const orders = defineMetric({
  key: "orders",
  table: "orders",
  measure: "count",
  timeColumn: "placed_at",
  dimensions: ["channel"],
});

describe("metrics block", () => {
  it("reads a series, with the previous range and typed dimensions", async () => {
    const { calls, transport } = recorder((_fn, args) =>
      args["p_from"] === range.from.toString()
        ? [
            {
              bucket: "2026-10-02T00:00:00Z",
              value: "3",
              count: 3,
              groups: { web: 2, "": null },
            },
            { bucket: "2026-10-03T00:00:00Z", value: null, count: 0 },
          ]
        : [{ bucket: "2026-09-30T00:00:00Z", value: 1, count: 1 }],
    );
    const metrics = createMetrics({ transport, metrics: [orders] });
    expectTypeOf<
      Parameters<typeof metrics.series>[0]
    >().toEqualTypeOf<"orders">();
    const series = await metrics
      .series("orders", range, {
        organizationId: "org",
        grain: "day",
        groupBy: "channel",
        filter: { channel: "web" },
        compare: "previous",
      })
      .orThrow();
    expect(series.points).toEqual([
      {
        bucket: at("2026-10-02T00:00:00Z"),
        value: 3,
        count: 3,
        groups: { web: 2, "": null },
      },
      { bucket: at("2026-10-03T00:00:00Z"), value: null, count: 0 },
    ]);
    expect(series.previous).toHaveLength(1);
    expect(calls[1]?.args).toEqual({
      p_metric: "orders",
      p_tenant: "org",
      p_from: "2026-09-30T00:00:00Z",
      p_until: "2026-10-02T00:00:00Z",
      p_grain: "day",
      p_dims: { channel: "web" },
      p_group_by: "channel",
    });

    const plain = await metrics
      .series("orders", range, { organizationId: "org" })
      .orThrow();
    expect(plain.previous).toBeUndefined();
    expect(calls[2]?.args).toMatchObject({
      p_grain: "day",
      p_dims: {},
      p_group_by: null,
    });

    expect(
      toChartData(series, {
        format: (bucket) => bucket.toString().slice(0, 10),
      }),
    ).toEqual([
      { web: 2, "": null, date: "2026-10-02", value: 3, previous: 1 },
      { date: "2026-10-03", value: null, previous: null },
    ]);
    expect(toChartData(plain)[0]).toEqual({
      web: 2,
      "": null,
      date: "2026-10-02T00:00:00Z",
      value: 3,
    });
  });

  it("reads a kpi and compares it with the previous range", async () => {
    const { transport } = recorder((_fn, args) =>
      args["p_from"] === range.from.toString()
        ? { value: "60", count: 4 }
        : { value: 40, count: 2 },
    );
    const metrics = createMetrics({ transport });
    expect(
      await metrics
        .kpi("orders", range, { organizationId: "org", compare: "previous" })
        .orThrow(),
    ).toEqual({
      metric: "orders",
      value: 60,
      count: 4,
      previous: 40,
      change: 0.5,
      trend: "up",
    });
    expect(
      await metrics.kpi("orders", range, { organizationId: "org" }).orThrow(),
    ).toEqual({ metric: "orders", value: 60, count: 4 });
  });

  it("compares values", () => {
    expect(compareValues(1, 2)).toEqual({ change: -0.5, trend: "down" });
    expect(compareValues(2, 2)).toEqual({ change: 0, trend: "flat" });
    expect(compareValues(2, 0)).toEqual({ change: null, trend: "up" });
    expect(compareValues(null, 2)).toEqual({ change: null });
    expect(previousRange(range)).toEqual({
      from: at("2026-09-30T00:00:00Z"),
      until: range.from,
    });
  });

  it("lists definitions", async () => {
    const { transport } = recorder(() => [
      {
        key: "orders",
        label: null,
        unit: "EUR",
        measure: "sum",
        dimensions: ["channel"],
        grains: ["day"],
        tz: "UTC",
      },
      {
        key: "visits",
        measure: "count",
        dimensions: [],
        grains: [],
        tz: "UTC",
      },
    ]);
    const metrics = createMetrics({ transport });
    expect(await metrics.definitions().orThrow()).toEqual([
      {
        key: "orders",
        label: null,
        unit: "EUR",
        measure: "sum",
        dimensions: ["channel"],
        grains: ["day"],
        tz: "UTC",
      },
      {
        key: "visits",
        label: null,
        unit: null,
        measure: "count",
        dimensions: [],
        grains: [],
        tz: "UTC",
      },
    ]);
  });

  it("rolls up through the service transport, also from the job", async () => {
    const member = recorder(() => 0);
    const service = recorder(() => 7);
    const metrics = createMetrics({
      transport: member.transport,
      service: service.transport,
    });
    expect(await metrics.rollup().orThrow()).toBe(7);
    await metrics.job(
      {
        metric: "orders",
        since: "2026-10-01T00:00:00Z",
        until: "2026-10-02T00:00:00Z",
      },
      undefined as never,
      new AbortController().signal,
    );
    await metrics.job(null, undefined as never, new AbortController().signal);
    expect(member.calls).toEqual([]);
    expect(service.calls.map((call) => call.args)).toEqual([
      { p_metric: null, p_since: null, p_until: null },
      {
        p_metric: "orders",
        p_since: "2026-10-01T00:00:00Z",
        p_until: "2026-10-02T00:00:00Z",
      },
      { p_metric: null, p_since: null, p_until: null },
    ]);
    await expect(
      Promise.resolve(
        metrics.job("orders", undefined as never, new AbortController().signal),
      ),
    ).rejects.toThrow("metrics.rollup needs an object payload");
  });
});

describe("metricsSink", () => {
  const event = (type: string, time?: string): CloudEvent => ({
    specversion: "1.0",
    id: `${type}-${time ?? "now"}`,
    source: "test",
    type,
    ...(time === undefined ? {} : { time }),
  });

  it("rolls up each metric over the window of its events", async () => {
    const requests: unknown[] = [];
    const sink = metricsSink(
      {
        rollup: (request) => {
          requests.push({
            metric: request?.metric,
            since: request?.since?.toString(),
            until: request?.until?.toString(),
          });
          return AsyncResult.ok(1);
        },
      },
      {
        on: {
          "order.placed": ["orders", "revenue"],
          "visit.started": "visits",
        },
      },
    );
    await sink.send([
      event("dev.better-supabase.order.placed", "2026-10-02T10:00:00Z"),
      event("dev.better-supabase.order.placed", "2026-10-01T09:00:00Z"),
      event("dev.better-supabase.order.placed", "2026-10-03T08:00:00Z"),
      event("dev.better-supabase.unrelated", "2026-10-03T08:00:00Z"),
    ]);
    expect(requests).toEqual([
      {
        metric: "orders",
        since: "2026-10-01T09:00:00Z",
        until: "2026-10-03T08:00:00.001Z",
      },
      {
        metric: "revenue",
        since: "2026-10-01T09:00:00Z",
        until: "2026-10-03T08:00:00.001Z",
      },
    ]);

    requests.length = 0;
    await sink.send([event("dev.better-supabase.visit.started")]);
    expect(requests).toHaveLength(1);
  });
});
