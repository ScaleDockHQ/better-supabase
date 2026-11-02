import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const BASE = ["memberships", "permissions", "agent-checkout"];

const sqlOf = (modules: readonly string[] = BASE): string =>
  renderBlocks(modules, {})
    .filter((file) => file.module === "agent-checkout")
    .map((file) => file.contents)
    .join("\n");

describe("agent-checkout module", () => {
  it("renders both tables with their checks", () => {
    const sql = sqlOf();

    expect(sql).toContain("checkout_sessions");
    expect(sql).toContain("agent_mandates");
    expect(sql).toContain("'acp', 'ucp'");
    expect(sql).toContain("'open', 'ready', 'completed', 'canceled'");
    expect(sql).toContain("'mandate.checkout.open.1', 'mandate.checkout.1'");
    expect(sql).toContain("'active', 'consumed', 'revoked'");
  });

  it("keeps one session per tenant and idempotency key", () => {
    expect(sqlOf()).toMatch(/idempotency_key/);
  });

  it("renders every function", () => {
    const sql = sqlOf();

    for (const fn of [
      "create_checkout_session",
      "update_checkout_session",
      "complete_checkout_session",
      "store_agent_mandate",
      "consume_agent_mandate",
      "revoke_agent_mandate",
    ]) {
      expect(sql).toContain(fn);
    }
  });

  it("works without orders, outbox and audit", () => {
    expect(() => sqlOf(BASE)).not.toThrow();
    expect(sqlOf([...BASE, "orders"])).toContain("checkout_sessions");
  });
});
