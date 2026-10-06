import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/registry.ts";

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
