import { describe, expect, it } from "vitest";

import { moduleBody, renderModules } from "../../../src/sql/registry.ts";

const billing = (options?: Record<string, unknown>) =>
  moduleBody("billing", {
    modules: options ? { billing: { options } } : {},
  })!;

describe("billing module", () => {
  it("resolves plan keys through the app's catalog", () => {
    expect(billing()).toContain("select null::text");
    const sql = billing({
      plans: {
        table: "app.plans",
        key: "slug",
        price: "price",
        interval: "every",
        active: "on_sale",
      },
    });
    expect(sql).toContain(`from "app"."plans" p`);
    expect(sql).toContain(`p."slug"::text = billing_plan_price.plan`);
    expect(sql).toContain(
      `p."every"::text = billing_plan_price.billing_interval`,
    );
    expect(sql).toContain(`and p."on_sale"`);
    expect(sql).toContain(
      'drop function if exists "better_supabase"."billing_plan_price"(text, text);',
    );
    const variants = billing({
      plans: { table: "plans", interval: "every", variant: "pack" },
    });
    expect(variants).toContain(
      `and (billing_plan_price.variant is null or p."pack"::text = billing_plan_price.variant)`,
    );
    expect(variants).toContain(
      `order by (p."pack" is null) desc, (p."every"::text = 'month') desc, 1`,
    );
    expect(billing({ plans: { table: "plans" } })).toContain(
      `select p."stripe_price_id"::text from "public"."plans" p`,
    );
    expect(() => billing({ plans: [] })).toThrow(/must be \{ table/);
    expect(() => billing({ plans: { table: "a.b.c" } })).toThrow(
      /"table" or "schema.table"/,
    );
    expect(() =>
      billing({ plans: { table: "plans", key: "Bad Key" } }),
    ).toThrow(/lowercase identifier/);
  });

  it("references the tenant table through the mapping", () => {
    expect(billing()).not.toContain("billing_customers_tenant_fkey");
    expect(billing({ tenantKey: "app.accounts.account_id" })).toContain(
      `foreign key ("organization_id") references "app"."accounts" ("account_id") on delete cascade`,
    );
    const withOrganizations = renderModules(["organizations", "billing"]).find(
      (file) => file.module === "billing" && file.kind === "schema",
    )!.contents;
    expect(withOrganizations).toContain(
      'constraint "billing_customers_tenant_fkey"\n      foreign key ("organization_id") references "better_supabase"."organizations" ("id") on delete cascade',
    );
    const off = renderModules(["organizations", "billing"], {
      modules: { billing: { options: { tenantKey: false } } },
    }).find((file) => file.module === "billing" && file.kind === "schema")!;
    expect(off.contents).not.toContain("billing_customers_tenant_fkey");
    expect(() => billing({ tenantKey: "accounts" })).toThrow(
      /schema.table.column/,
    );
    expect(() => billing({ tenantKey: 1 })).toThrow(/or false/);
  });

  it("reads invoices, payment methods and the customer from the Sync Engine", () => {
    const sql = billing();
    expect(sql).toContain(
      "'invoices', 'payment_methods', 'subscriptions', 'customers', 'tax_ids'",
    );
    expect(sql).toContain(
      `"billing_stripe_rows"(billing_tax_ids.tenant, 'tax_ids', 100)`,
    );
    expect(sql).toContain(
      "'created', coalesce(t -> 'created', t -> '_raw_data' -> 'created')",
    );
    expect(sql).toContain(
      `grant execute on function "better_supabase"."billing_tax_ids"(uuid) to authenticated, service_role;`,
    );
    expect(sql).toContain(
      `"billing_stripe_rows"(billing_invoices.tenant, 'invoices'`,
    );
    expect(sql).toContain("BILLING_FORBIDDEN");
  });

  it("reads a tenant's subscription unchecked for the owner's functions only", () => {
    const sql = billing();
    expect(sql).toContain(
      'create or replace function "better_supabase"."billing_tenant_subscription"(tenant uuid)',
    );
    expect(sql).toContain(
      'revoke execute on function "better_supabase"."billing_tenant_subscription"(uuid) from public, anon, authenticated, service_role;',
    );
    expect(sql).not.toMatch(
      /grant execute on function "better_supabase"\."billing_tenant_subscription"/,
    );
    expect(sql).toContain(
      'return "better_supabase"."billing_tenant_subscription"(billing_subscription.tenant);',
    );
  });

  it("lists every linked customer for platform staff", () => {
    const sql = billing();
    expect(sql).toContain(
      'create or replace function "better_supabase"."billing_platform_customers"()',
    );
    expect(sql).toContain("Not allowed to read every tenant''s billing");
    expect(sql).toContain(
      'from "better_supabase"."billing_platform_customers"() c',
    );
    expect(sql).toContain(
      'grant execute on function "better_supabase"."billing_all_customers"() to authenticated, service_role;',
    );
  });
});
