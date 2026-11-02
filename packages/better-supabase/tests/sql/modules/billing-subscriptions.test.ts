import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const render = (blocks: readonly string[]): string =>
  renderBlocks(blocks, { modules: {} })
    .filter((file) => file.module === "billing")
    .map((file) => file.contents)
    .join("\n");

describe("native subscriptions", () => {
  it("creates a Stripe-free table and service-only functions", () => {
    const sql = render(["billing"]);

    expect(sql).toContain("billing_native_subscriptions");
    expect(sql).toContain('"create_native_subscription"');
    expect(sql).toMatch(
      /revoke execute on function "better_supabase"\."?prorate_change"?\([^)]*\) from public, anon, authenticated;\s+grant execute on function "better_supabase"\."?prorate_change"?\([^)]*\) to service_role;/,
    );
    expect(sql).not.toContain("stripe_subscription");
  });

  it("computes credit, charge and net over the unused part of the period", () => {
    const sql = render(["billing"]);

    expect(sql).toContain("v_net := v_charge - v_credit;");
    expect(sql).toContain("greatest(0, least(1,");
  });

  it("posts the net to the ledger only when the ledger block is installed", () => {
    expect(render(["billing"])).not.toContain("ledger_post");

    const sql = render(["billing", "ledger"]);

    expect(sql).toContain("ledger_post");
    expect(sql).toContain("'billing.proration'");
    expect(sql).toContain("'billing:proration:'");
  });
});
