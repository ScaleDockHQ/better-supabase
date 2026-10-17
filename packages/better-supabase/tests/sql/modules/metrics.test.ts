import { describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../../src/sql/module-types.ts";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (
  options: Record<string, unknown> = {},
  extra: ModuleLayout = {},
): string =>
  renderModules(["metrics"], {
    ...extra,
    modules: {
      ...extra.modules,
      metrics: { ...extra.modules?.["metrics"], options },
    },
  })
    .filter((file) => file.module === "metrics")
    .map((file) => file.contents)
    .join("\n");

const orders = {
  key: "orders",
  table: "shop.orders",
  measure: "count",
  timeColumn: "placed_at",
  dimensions: ["channel"],
  tz: "Europe/Amsterdam",
  rollup: ["hour", "day"],
};

describe("metrics module", () => {
  it("rolls each stored grain up in the metric's time zone", () => {
    const sql = sqlOf({ metrics: [orders] });
    expect(sql).toContain(
      `create table if not exists "better_supabase"."metric_points"`,
    );
    expect(sql).toContain(
      `v_from := date_trunc('hour', v_since, 'Europe/Amsterdam');`,
    );
    expect(sql).toContain(
      `v_to := ((date_trunc('day', v_until - interval '1 microsecond', 'Europe/Amsterdam')) at time zone 'Europe/Amsterdam' + interval '1 day') at time zone 'Europe/Amsterdam';`,
    );
    expect(sql).toContain(
      `jsonb_build_object('channel', t."channel") as dims, 1::numeric as value, 1::bigint as count\n        from "shop"."orders" t`,
    );
    expect(sql).toContain("when 'day' then 'day'");
    expect(sql).toContain("when 'week' then 'day'");
    expect(sql).toContain("when 'hour' then 'hour'");
    expect(sql).toContain("v_source := 'hour';");
    expect(sql).toContain("perform pg_advisory_xact_lock");
    expect(sql).toContain("now() - interval '3 days'");
  });

  it("reads small tables directly and filters rows with where", () => {
    const sql = sqlOf({
      metrics: {
        api_calls: {
          table: "better_supabase.usage_events",
          measure: { sum: "quantity" },
          timeColumn: "recorded_at",
          where: { meter: "api_calls", voided: false, deleted_at: null, n: 1 },
          rollup: false,
          permission: "metrics.manage",
        },
      },
      window: "12 hours",
    });

    expect(sql).toContain(
      `coalesce(t."quantity", 0)::numeric as value, 1::bigint as count`,
    );
    expect(sql).toContain(
      `where t."meter" = 'api_calls'\n          and t."voided" = false\n          and t."deleted_at" is null\n          and t."n" = 1`,
    );
    expect(sql).toContain("v_source := null;");
    expect(sql).not.toContain('from "better_supabase"."metric_points" p');
    expect(sql).toContain(`'metrics.manage'`);
    expect(sql).toContain("now() - interval '12 hours'");
  });

  it("averages over the rows with a value", () => {
    const sql = sqlOf({
      metrics: [
        {
          key: "basket",
          table: "orders",
          measure: { avg: "total" },
          timeColumn: "placed_at",
        },
      ],
    });

    expect(sql).toContain(
      `t."total"::numeric as value, (t."total" is not null)::int::bigint as count`,
    );
    expect(sql).toContain("round(p.value / nullif(p.count, 0), 6)");
    expect(sql).toContain(`from "public"."orders" t`);
  });

  it("renders the functions without metrics", () => {
    const sql = sqlOf();
    expect(sql).toContain("p_metric <> all (array[]::text[])");
    expect(sql).toContain("METRIC_UNKNOWN");
    expect(sql).toContain(`select '[]'::jsonb`);
  });

  it("rejects a bad window and bad definitions", () => {
    expect(() => sqlOf({ window: "forever" })).toThrow(
      "options.window must be an interval",
    );
    expect(() =>
      sqlOf({ metrics: [{ ...orders, tz: "Nowhere/Here" }] }),
    ).toThrow("is not an IANA time zone");
  });

  it("renders nothing in custom mode, and adopts an existing points table", () => {
    expect(
      sqlOf({}, { modules: { metrics: { mode: "custom" } } }),
    ).not.toContain("metric_series");

    const adopted = sqlOf(
      { metrics: [orders] },
      {
        modules: {
          metrics: { mode: "adopt", tables: { points: "analytics.points" } },
        },
      },
    );

    expect(adopted).not.toContain('"better_supabase"."metric_points"');
    expect(adopted).toContain(`delete from "analytics"."points"`);
  });
});
