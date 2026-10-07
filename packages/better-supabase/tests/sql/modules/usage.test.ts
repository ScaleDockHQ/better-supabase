import { describe, expect, it } from "vitest";

import { moduleBody, renderModules } from "../../../src/sql/registry.ts";

const usage = (options?: Record<string, unknown>) =>
  moduleBody("usage", {
    modules: options ? { usage: { options } } : {},
  })!;

describe("usage module", () => {
  it("allows billing periods through the app's hook", () => {
    const sql = usage();
    expect(sql).toContain("'day', 'week', 'month', 'year', 'billing'");
    expect(sql).toContain(
      `to_regprocedure('"public"."usage_billing_period"(uuid)')`,
    );
    expect(sql).toContain(
      'drop constraint if exists "usage_quotas_period_check"',
    );
    expect(sql).not.toContain("USAGE_METER_UNKNOWN");
  });

  it("matches plan quotas by plan key with a plan catalog", () => {
    const render = (source: unknown) =>
      renderModules(["entitlements", "usage"], {
        entitlements: { key: "id", source },
      } as never).find(
        (file) => file.module === "usage" && file.kind === "schema",
      )!.contents;
    const plans = {
      plans: {
        subscriptions: { table: "subs", tenant: "org_id", plan: "plan" },
        features: { table: "features", plan: "plan", feature: "key" },
      },
    };
    expect(render(plans)).toContain(
      "= any (better_supabase.tenant_plans(tenant))",
    );
    expect(render("custom")).not.toContain("tenant_plans");
    expect(
      renderModules(["entitlements"], {
        entitlements: { key: "id", source: plans },
      }).find((file) => file.module === "entitlements")!.contents,
    ).toContain("create or replace function better_supabase.tenant_plans");
  });

  it("reads the meter catalog from a table", () => {
    const sql = usage({
      meters: {
        table: "app.meters",
        key: "slug",
        label: "title",
        active: "on",
      },
    });
    expect(sql).toContain(
      `jsonb_object_agg(m."slug"::text, jsonb_strip_nulls(jsonb_build_object('label', m."title"::text)))`,
    );
    expect(sql).toContain(`from "app"."meters" m where m."on"`);
    expect(sql).toContain("stable\nsecurity definer");
    expect(sql).toContain(
      `if not ("better_supabase"."usage_meters"() ? meter)`,
    );
    expect(() => usage({ meters: { table: "a.b.c" } })).toThrow(
      /"table" or "schema.table"/,
    );
    expect(() => usage({ meters: { table: "m", color: "c" } })).toThrow(
      /not color/,
    );
    expect(() => usage({ meters: { table: "m", key: "Bad" } })).toThrow(
      /lowercase identifier/,
    );
  });

  it("refuses meters outside options.meters and returns the catalog", () => {
    const sql = usage({ meters: { "api.requests": { unit: "requests" } } });
    expect(sql).toContain(`'{"api.requests":{"unit":"requests"}}'::jsonb`);
    expect(sql).toContain("USAGE_METER_UNKNOWN");
    expect(() => usage({ meters: [] })).toThrow(/must be an object of meter/);
    expect(() => usage({ meters: { "Bad Meter": {} } })).toThrow(
      /is not a meter name/,
    );
    expect(() => usage({ meters: { m: "x" } })).toThrow(/m must be an object/);
    expect(() => usage({ meters: { m: { color: "red" } } })).toThrow(
      /use unit, category and label/,
    );
  });
});
