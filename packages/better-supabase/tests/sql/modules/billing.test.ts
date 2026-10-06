import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/registry.ts";

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

  it("reads invoices, payment methods and the customer from the Sync Engine", () => {
    const sql = billing();
    expect(sql).toContain(
      "'invoices', 'payment_methods', 'subscriptions', 'customers'",
    );
    expect(sql).toContain(
      `"billing_stripe_rows"(billing_invoices.tenant, 'invoices'`,
    );
    expect(sql).toContain("BILLING_FORBIDDEN");
  });
});
