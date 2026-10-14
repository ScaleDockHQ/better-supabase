import { describe, expect, it } from "vitest";

import {
  ORDER_METRIC_EVENTS,
  orderMetrics,
} from "../../../src/blocks/orders/index.ts";

describe("orderMetrics", () => {
  it("counts placed orders and measures paid ones in one currency", () => {
    const [orders, revenue, average] = orderMetrics({ currency: "EUR" });
    expect(orders).toMatchObject({
      key: "orders",
      table: "better_supabase.orders",
      tenant: "tenant_id",
      measure: "count",
      timeColumn: "placed_at",
    });
    expect(orders).not.toHaveProperty("where");
    expect(revenue).toMatchObject({
      measure: { sum: "total" },
      timeColumn: "paid_at",
      where: { currency: "EUR" },
      unit: "EUR",
    });
    expect(average).toMatchObject({
      key: "average_order_value",
      measure: { avg: "total" },
    });
    expect(
      orderMetrics({
        currency: "USD",
        schema: "store",
        tz: "America/New_York",
      })[1],
    ).toMatchObject({
      table: "store.orders",
      tz: "America/New_York",
      where: { currency: "USD" },
    });
  });

  it("names the events that add rows to each metric", () => {
    const keys = new Set<string>(
      orderMetrics({ currency: "EUR" }).map((metric) => metric.key),
    );
    for (const metrics of Object.values(ORDER_METRIC_EVENTS)) {
      for (const metric of metrics) expect(keys.has(metric)).toBe(true);
    }
  });
});
