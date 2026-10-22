import { describe, expect, it } from "vitest";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

const usage = (options?: Record<string, unknown>) =>
  moduleBody("usage", { modules: options ? { usage: { options } } : {} })!;

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
      renderBlocks(["entitlements", "usage"], {
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
      renderBlocks(["entitlements"], {
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
      /use unit, category, label, kind, period and query/,
    );
  });

  it("counts distinct subjects and refreshes computed meters", () => {
    const sql = usage({
      meters: {
        mau: { kind: "distinct", period: "month" },
        storage: {
          kind: "computed",
          period: "month",
          query: "select organization_id, sum(bytes) from app.files group by 1",
        },
      },
    });

    expect(sql).toContain(
      'create table if not exists "better_supabase"."usage_distinct"',
    );
    expect(sql).toContain("track_usage");
    expect(sql).toContain("if track_usage.meter <> all (array['mau'])");
    expect(sql).toContain("usage_refresh");
    expect(sql).toContain("from app.files group by 1");
    // The query is not exposed in the catalog usage_meters() returns.
    expect(sql).toContain(
      `'{"mau":{"kind":"distinct","period":"month"},"storage":{"kind":"computed","period":"month"}}'::jsonb`,
    );
    expect(usage()).not.toContain("track_usage");
    expect(() => usage({ meters: { m: { kind: "computed" } } })).toThrow(
      /needs a query/,
    );
    expect(() => usage({ meters: { m: { query: "select 1" } } })).toThrow(
      /needs kind "computed"/,
    );
    expect(() =>
      usage({ meters: { m: { kind: "computed", query: "select 1; drop" } } }),
    ).toThrow(/one select/);
  });
});

describe("usage module under the provider access model", () => {
  it("checks membership through the provider's memberIds", () => {
    const sql = moduleBody("usage", {
      modules: { access: { model: "provider" } },
      accessProvider: {
        name: "stub",
        scope: "organization",
        idType: "uuid",
        functions: {
          idsWith: "authz.ids_with({permission}, {scope})",
          isPlatform: "authz.is_platform({permission})",
          memberIds: "authz.member_ids({scope})",
        },
      },
    })!;

    expect(sql).toContain(
      "tenant::text in (select t.id::text from authz.member_ids(organization) as t(id))",
    );
    expect(sql).not.toContain("has_organization_role(tenant)");
  });
});

describe("usage partitioned history", () => {
  it("partitions usage_history by month and drops expired months", () => {
    const sql = usage({ history: true, partitioned: true });
    expect(sql).toContain('primary key ("id", "recorded_at")');
    expect(sql).toContain(') partition by range ("recorded_at");');
    expect(sql).toContain(
      `"id" bigint not null default nextval('"better_supabase".usage_history_id_seq')`,
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."usage_history_default" partition of "better_supabase"."usage_history" default;',
    );
    expect(sql).toContain(
      `better_supabase.expired_partitions('"better_supabase"."usage_history"'::regclass, now() - older_than)`,
    );
    expect(sql).toContain("return purged + v_dropped;");
  });

  it("needs options.history and stays unpartitioned by default", () => {
    expect(usage({ partitioned: true })).not.toContain("partition by range");
    expect(usage({ history: true })).not.toContain("partition by range");
    expect(usage({ history: true })).toContain(
      '"id" bigint generated always as identity primary key',
    );
  });
});
