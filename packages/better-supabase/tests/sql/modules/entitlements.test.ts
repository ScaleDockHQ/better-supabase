import { describe, expect, it } from "vitest";

import type { EntitlementPlansSource } from "../../../src/config/index.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const entitlements = (
  source: "stripe-sync" | "custom" | EntitlementPlansSource,
) =>
  renderBlocks(["entitlements"], { entitlements: { key: "id", source } }).find(
    (file) => file.module === "entitlements" && file.kind === "schema",
  )!.contents;

const PLANS: EntitlementPlansSource = {
  plans: {
    subscriptions: {
      table: "public.subscriptions",
      tenant: "team_id",
      plan: "plan_key",
      status: "status",
    },
    features: {
      table: "public.plan_features",
      plan: "plan_key",
      feature: "feature_key",
      included: "included",
    },
  },
};

describe("entitlements sources", () => {
  it("reads a plan catalog without a Stripe customer", () => {
    const sql = entitlements(PLANS);
    expect(sql).toContain('from "public"."subscriptions" s');
    expect(sql).toContain(
      `join "public"."plan_features" f on f."plan_key"::text = s."plan_key"::text`,
    );
    expect(sql).toContain(
      `and s."status"::text = any (array['active', 'trialing']::text[])`,
    );
    expect(sql).toContain('and f."included"');
    expect(sql).not.toContain("stripe.active_entitlements");
    expect(sql).not.toContain("tenant_stripe_customer");
    expect(sql).toContain("better_supabase.has_entitlement");
  });

  it("leaves tenant_entitlements to the app in custom mode", () => {
    const sql = entitlements("custom");
    expect(sql).not.toContain(
      "create or replace function better_supabase.tenant_entitlements",
    );
    expect(sql).toContain("set check_function_bodies = off;");
    expect(sql).toContain("better_supabase.feature_claims(user_id uuid)");
  });

  it("keeps the Stripe customer lookup by default", () => {
    const sql = renderBlocks(["entitlements"], {
      entitlements: { table: "public.teams", column: "stripe_id", key: "id" },
    }).find(
      (file) => file.module === "entitlements" && file.kind === "schema",
    )!.contents;

    expect(sql).toContain("stripe.active_entitlements");
    expect(sql).toContain("better_supabase.tenant_stripe_customer");
  });

  it("reads the customer from renamed billing columns", () => {
    const sql = renderBlocks(["billing", "entitlements"], {
      modules: {
        billing: {
          schema: "app",
          tables: { customers: "team_billing" },
          columns: { customers: { tenant: "team_id", customer: "cus_id" } },
        },
      },
    }).find(
      (file) => file.module === "entitlements" && file.kind === "schema",
    )!.contents;

    expect(sql).toContain("-- config.entitlements: app.team_billing.cus_id");
    expect(sql).toContain(
      'select t."cus_id" from "app"."team_billing" t where t."team_id" = tenant',
    );
    expect(sql).not.toContain("stripe_customer_id");
  });

  it("reads the customer from a renamed organizations table", () => {
    const sql = renderBlocks(["organizations", "entitlements"], {
      modules: {
        organizations: {
          schema: "app",
          tables: { organizations: "teams" },
          columns: { organizations: { id: "team_id" } },
        },
      },
    }).find(
      (file) => file.module === "entitlements" && file.kind === "schema",
    )!.contents;

    expect(sql).toContain(
      'select t."stripe_customer_id" from "app"."teams" t where t."team_id" = tenant',
    );
    expect(sql).not.toContain("better_supabase.organizations");
  });

  it("adds the organizations customer column only when entitlements read it", () => {
    const organizations = (layout: Parameters<typeof renderBlocks>[1]) =>
      renderBlocks(["entitlements", "organizations"], layout).find(
        (file) => file.module === "organizations" && file.kind === "schema",
      )!.contents;

    const column = "add column if not exists stripe_customer_id text unique;";

    expect(organizations({})).toContain(column);
    expect(
      organizations({ entitlements: { key: "id", source: PLANS } }),
    ).not.toContain(column);
    expect(
      organizations({ entitlements: { key: "id", source: "custom" } }),
    ).not.toContain(column);
    expect(
      organizations({
        entitlements: {
          table: "public.billing_customers",
          column: "customer",
          key: "organization_id",
        },
      }),
    ).not.toContain(column);
  });

  it("renders a plan catalog without status or included columns", () => {
    const sql = entitlements({
      plans: {
        subscriptions: {
          table: "subscriptions",
          tenant: "team_id",
          plan: "plan",
        },
        features: { table: "plan_features", plan: "plan", feature: "key" },
      },
    });

    expect(sql).not.toContain("any (array['active'");
    expect(sql).not.toContain('and f."included"');
  });

  it("returns feature values from the plan catalog's value column", () => {
    const sql = entitlements({
      plans: {
        ...PLANS.plans,
        features: { ...PLANS.plans.features, value: "limit_value" },
      },
    });

    expect(sql).toContain(
      "create or replace function better_supabase.tenant_entitlement_value(tenant uuid, key text)",
    );
    expect(sql).toContain(
      `select coalesce(to_jsonb(f."limit_value"), 'true'::jsonb)`,
    );
    expect(sql).toContain(
      `order by case when jsonb_typeof(to_jsonb(f."limit_value")) = 'number' then (to_jsonb(f."limit_value") #>> '{}')::numeric end desc nulls last`,
    );
    expect(sql).toContain(
      "select case when better_supabase.has_organization_role(tenant) then better_supabase.tenant_entitlement_value(tenant, key) end",
    );
    expect(sql).toContain(
      "grant execute on function better_supabase.entitlement_value(uuid, text) to authenticated, service_role;",
    );

    for (const source of [PLANS, "stripe-sync"] as const) {
      const plain =
        source === "stripe-sync"
          ? renderBlocks(["entitlements"], {
              entitlements: {
                table: "public.teams",
                column: "stripe_id",
                key: "id",
              },
            }).find(
              (file) =>
                file.module === "entitlements" && file.kind === "schema",
            )!.contents
          : entitlements(source);

      expect(plain).toContain(
        "select case when key = any (better_supabase.tenant_entitlements(tenant)) then 'true'::jsonb end",
      );
    }

    const custom = entitlements("custom");
    expect(custom).not.toContain(
      "create or replace function better_supabase.tenant_entitlement_value",
    );
    expect(custom).toContain(
      "better_supabase.entitlement_value(tenant uuid, key text)",
    );
  });
});
