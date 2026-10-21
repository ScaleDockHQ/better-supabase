import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import {
  createMetrics,
  defineMetric,
  metricsSink,
  sqlTransport,
  toChartData,
} from "../../src/blocks/metrics/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const orders = defineMetric({
  key: "orders",
  table: "metrics_it.orders",
  measure: "count",
  timeColumn: "placed_at",
  dimensions: ["channel"],
  tz: "Europe/Amsterdam",
  rollup: ["hour", "day"],
});

const revenue = defineMetric({
  key: "revenue",
  table: "metrics_it.orders",
  measure: { sum: "total" },
  timeColumn: "placed_at",
  dimensions: ["channel"],
  rollup: false,
});

const basket = defineMetric({
  key: "basket",
  table: "metrics_it.orders",
  measure: { avg: "total" },
  timeColumn: "placed_at",
  where: { channel: "web" },
});

const apiCalls = defineMetric({
  key: "api_calls",
  table: "better_supabase.usage_events",
  measure: { sum: "quantity" },
  timeColumn: "recorded_at",
  where: { meter: "api_calls" },
  permission: "metrics.manage",
});

const layout: ModuleLayout = {
  modules: {
    metrics: { options: { metrics: [orders, revenue, basket, apiCalls] } },
  },
};

const TABLES = `create schema metrics_it;
create table metrics_it.orders (
  id serial primary key,
  organization_id uuid not null,
  channel text not null,
  total numeric not null,
  placed_at timestamptz not null
);`;

interface Bucket {
  readonly bucket: string;
  readonly value: number | null;
  readonly count: number;
  readonly groups?: Record<string, number | null>;
}

describe.skipIf(!live)("metrics", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("rolls up, reads series and totals, and checks the permission", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      await s.install(["organizations", "usage", "metrics"], layout);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      const other = await s.organization(await s.user("other"));
      await s.service();
      await s.client.query(
        `insert into metrics_it.orders (organization_id, channel, total, placed_at) values
          ($1, 'web', 10, '2026-03-01 23:30+00'),
          ($1, 'web', 30, '2026-03-02 08:00+00'),
          ($1, 'shop', 5, '2026-03-02 09:00+00'),
          ($1, 'web', 20, '2026-03-04 12:00+00'),
          ($2, 'web', 99, '2026-03-02 10:00+00')`,
        [tenant, other],
      );
      await s.client.query(
        `insert into better_supabase.usage_events (organization_id, meter, idempotency_key, quantity, recorded_at) values
          ($1, 'api_calls', 'k1', 3, '2026-03-02 10:00+00'),
          ($1, 'seats', 'k2', 7, '2026-03-02 10:00+00')`,
        [tenant],
      );

      const rolled = await s.value<number>(
        "better_supabase.metrics_rollup(null, '2026-03-01', '2026-03-05')",
      );

      expect(rolled).toBeGreaterThan(0);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.metric_points where metric = 'orders' and grain = 'day')",
        ),
      ).toBe(4);

      const series = (
        metric: string,
        grain = "day",
        dims: object = {},
        groupBy: string | null = null,
      ): Promise<Bucket[]> =>
        s.value<Bucket[]>(
          "better_supabase.metric_series($1, $2, '2026-03-01T23:00:00Z', '2026-03-05T23:00:00Z', $3, $4, $5)",
          [metric, tenant, grain, dims, groupBy],
        );

      await s.as(member);
      const daily = await series("orders");
      expect(daily.map((b) => b.value)).toEqual([3, 0, 1, 0]);
      expect(daily.map((b) => b.count)).toEqual([3, 0, 1, 0]);
      expect(Temporal.Instant.from(daily[0]!.bucket).toString()).toBe(
        "2026-03-01T23:00:00Z",
      );
      expect(
        (await series("orders", "day", { channel: "web" })).map((b) => b.value),
      ).toEqual([2, 0, 1, 0]);
      const grouped = await series("orders", "day", {}, "channel");
      expect(grouped[0]?.groups).toEqual({ web: 2, shop: 1 });
      expect(grouped[1]?.groups).toEqual({});
      expect(await series("orders", "hour")).toHaveLength(96);
      expect((await series("orders", "week")).map((b) => b.value)).toEqual([4]);

      expect((await series("revenue")).map((b) => b.value)).toEqual([
        10, 35, 0, 20, 0,
      ]);
      expect((await series("basket")).map((b) => b.value)).toEqual([
        10,
        30,
        null,
        20,
        null,
      ]);

      expect(
        await s.value(
          "better_supabase.metric_value('orders', $1, '2026-03-01T23:00:00Z', '2026-03-05T23:00:00Z')",
          [tenant],
        ),
      ).toEqual({ value: 4, count: 4 });
      expect(
        await s.value(
          "better_supabase.metric_value('revenue', $1, '2026-03-02T00:00:00Z', '2026-03-03T00:00:00Z', '{\"channel\":\"web\"}')",
          [tenant],
        ),
      ).toEqual({ value: 30, count: 1 });

      expect(
        await s.hint(
          "better_supabase.metric_value('api_calls', $1, '2026-03-01', '2026-03-05')",
          [tenant],
        ),
      ).toBe("METRIC_FORBIDDEN");
      expect(
        await s.hint(
          "better_supabase.metric_value('orders', $1, '2026-03-01', '2026-03-05')",
          [other],
        ),
      ).toBe("METRIC_FORBIDDEN");
      expect(
        await s.hint(
          "better_supabase.metric_series('orders', $1, '2026-03-01', '2026-03-05', 'day', '{\"total\":1}')",
          [tenant],
        ),
      ).toBe("METRIC_DIMENSION_UNKNOWN");
      expect(
        await s.hint(
          "better_supabase.metric_series('orders', $1, '2026-03-01', '2026-03-05', 'year')",
          [tenant],
        ),
      ).toBe("METRIC_GRAIN_INVALID");
      expect(
        await s.hint(
          "better_supabase.metric_series('orders', $1, '2020-01-01', '2026-03-05', 'hour')",
          [tenant],
        ),
      ).toBe("METRIC_RANGE_TOO_LARGE");
      expect(
        await s.hint(
          "better_supabase.metric_series('nope', $1, '2026-03-01', '2026-03-05')",
          [tenant],
        ),
      ).toBe("METRIC_UNKNOWN");

      await s.as(owner);
      expect(
        await s.value(
          "better_supabase.metric_value('api_calls', $1, '2026-03-01', '2026-03-05')",
          [tenant],
        ),
      ).toEqual({ value: 3, count: 1 });

      await s.service();
      await s.client.query(
        `insert into metrics_it.orders (organization_id, channel, total, placed_at)
         values ($1, 'shop', 1, '2026-03-02 09:30+00')`,
        [tenant],
      );
      await s.value(
        "better_supabase.metrics_rollup('orders', '2026-03-02 09:00+00', '2026-03-02 09:31+00')",
      );
      await s.as(member);
      expect((await series("orders")).map((b) => b.value)).toEqual([
        4, 0, 1, 0,
      ]);
      expect(
        (
          await s.value<{ key: string; grains: string[] }[]>(
            "better_supabase.metric_definitions()",
          )
        ).map((metric) => [metric.key, metric.grains]),
      ).toEqual([
        ["orders", ["hour", "day"]],
        ["revenue", []],
        ["basket", ["day"]],
        ["api_calls", ["day"]],
      ]);

      const metrics = createMetrics({
        transport: sqlTransport(s.sql),
        metrics: [orders, revenue, basket, apiCalls],
      });

      const range = {
        from: Temporal.Instant.from("2026-03-03T23:00:00Z"),
        until: Temporal.Instant.from("2026-03-05T23:00:00Z"),
      };

      const compared = await metrics
        .series("orders", range, {
          organizationId: tenant,
          compare: "previous",
          filter: { channel: "web" },
        })
        .orThrow();

      expect(compared.points.map((p) => p.value)).toEqual([1, 0]);
      expect(compared.previous?.map((p) => p.value)).toEqual([2, 0]);
      expect(toChartData(compared)).toEqual([
        { date: "2026-03-03T23:00:00Z", value: 1, previous: 2 },
        { date: "2026-03-04T23:00:00Z", value: 0, previous: 0 },
      ]);
      expect(
        await metrics
          .kpi("revenue", range, {
            organizationId: tenant,
            compare: "previous",
          })
          .orThrow(),
      ).toEqual({
        metric: "revenue",
        value: 20,
        count: 1,
        previous: 46,
        change: (20 - 46) / 46,
        trend: "down",
      });
      expect(
        await metrics
          .kpi("api_calls", range, { organizationId: tenant })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("METRIC_FORBIDDEN");

      await s.service();
      await s.client.query(
        `insert into metrics_it.orders (organization_id, channel, total, placed_at)
         values ($1, 'web', 2, '2026-03-05 10:00+00')`,
        [tenant],
      );
      await metricsSink(metrics, { on: { "order.placed": ["orders"] } }).send([
        {
          specversion: "1.0",
          id: "e1",
          source: "/test",
          type: "dev.better-supabase.order.placed",
          time: "2026-03-05T10:00:00Z",
        },
      ]);
      await s.as(member);
      expect(
        (
          await metrics
            .series("orders", range, { organizationId: tenant })
            .orThrow()
        ).points.map((p) => p.value),
      ).toEqual([1, 1]);
    } finally {
      await s.close();
    }
  });
});
