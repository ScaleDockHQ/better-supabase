import { describe, expect, it } from "vitest";

import {
  checkMetric,
  defineMetric,
  grainDivides,
  METRIC_GRAINS,
  metricsOf,
} from "../../src/core/metric-definition.ts";

const base = {
  key: "orders",
  table: "public.orders",
  measure: "count",
  timeColumn: "placed_at",
} as const;

describe("defineMetric", () => {
  it("returns the definition and keeps its literal types", () => {
    const metric = defineMetric({
      ...base,
      measure: { sum: "total" },
      dimensions: ["channel"],
      tz: "Europe/Amsterdam",
      where: { status: "paid", test: false, voided_at: null, version: 2 },
      rollup: ["hour", "day"],
      permission: "metrics.read",
      label: "Orders",
      unit: "EUR",
    });

    expect(metric.key).toBe("orders");
    expect(metric.dimensions).toEqual(["channel"]);
  });

  it.each([
    [{ ...base, key: "Orders" }, "key must be lowercase"],
    [{ ...base, table: "a.b.c" }, "table must be"],
    [{ ...base, measure: "max" }, 'measure must be "count"'],
    [{ ...base, measure: { sum: "Total" } }, "measure.sum must be a column"],
    [{ ...base, measure: { sum: "a", avg: "b" } }, "measure must be"],
    [{ ...base, timeColumn: 3 }, "timeColumn must be a column"],
    [{ ...base, dimensions: "channel" }, "dimensions must be a list"],
    [{ ...base, dimensions: ["a", "a"] }, "lists a column twice"],
    [{ ...base, rollup: ["year"] }, "rollup must be false"],
    [{ ...base, rollup: [] }, "rollup must be false"],
    [{ ...base, permission: "Bad Key" }, "permission must be"],
    [{ ...base, where: [] }, "where must be an object"],
    [{ ...base, where: { a: {} } }, "where.a must be"],
    [{ ...base, where: { a: Number.NaN } }, "where.a must be"],
    [{ ...base, label: 1 }, "label must be a string"],
    [{ ...base, tenant: "Org" }, "tenant must be a column"],
    [{ ...base, tz: "" }, "tz must be an IANA time zone"],
    [{ ...base, tz: "Mars/Olympus" }, "is not an IANA time zone"],
    ["orders", "metric must be an object"],
  ])("rejects %j", (value, message) => {
    expect(() => checkMetric(value)).toThrow(message);
  });

  it("rejects a bad definition at the call site", () => {
    expect(() =>
      // @ts-expect-error measure is not a known measure
      defineMetric({ ...base, measure: "max" }),
    ).toThrow("defineMetric orders.measure");
  });
});

describe("metricsOf", () => {
  it("reads a list, an object keyed by metric, or nothing", () => {
    expect(metricsOf(undefined)).toEqual([]);
    expect(metricsOf([base]).map((metric) => metric.key)).toEqual(["orders"]);
    const { key: _, ...rest } = base;
    expect(metricsOf({ signups: rest }).map((metric) => metric.key)).toEqual([
      "signups",
    ]);
  });

  it("rejects other shapes and duplicate keys", () => {
    expect(() => metricsOf("orders")).toThrow("must be a list");
    expect(() => metricsOf({ a: 1 })).toThrow("must be an object");
    expect(() => metricsOf([base, base])).toThrow('"orders" is defined twice');
  });
});

describe("grainDivides", () => {
  it("sums finer stored grains into coarser ones", () => {
    const table = METRIC_GRAINS.map((stored) =>
      METRIC_GRAINS.filter((grain) => grainDivides(stored, grain)),
    );

    expect(table).toEqual([
      ["hour", "day", "week", "month"],
      ["day", "week", "month"],
      ["week"],
      ["month"],
    ]);
  });
});
