import { describe, expect, it } from "vitest";

import {
  entitlementMembers,
  ENTITLEMENTS_UPDATED,
} from "../../../src/blocks/entitlements/index.ts";
import { fakeSql, pgError } from "../../fixtures/fake-sql.ts";

describe("entitlementMembers", () => {
  const event = (customer: unknown) => ({
    type: ENTITLEMENTS_UPDATED,
    data: { object: { customer } },
  });

  it("names the Stripe event", () => {
    expect(ENTITLEMENTS_UPDATED).toBe(
      "entitlements.active_entitlement_summary.updated",
    );
  });

  it("looks up members of a customer id or customer object", async () => {
    const fake = fakeSql([
      ["entitlement_members", [{ user_id: "u1" }, { user_id: "u2" }]],
    ]);
    expect(
      await entitlementMembers(fake.sql, event("cus_1")).orThrow(),
    ).toEqual(["u1", "u2"]);
    expect(
      await entitlementMembers(fake.sql, event({ id: "cus_2" })).orThrow(),
    ).toEqual(["u1", "u2"]);
    expect(fake.calls).toEqual([
      {
        text: "select user_id from better_supabase.entitlement_members($1) as user_id",
        values: ["cus_1"],
      },
      {
        text: "select user_id from better_supabase.entitlement_members($1) as user_id",
        values: ["cus_2"],
      },
    ]);
  });

  it("returns no members without a query for payloads without a customer", async () => {
    const fake = fakeSql();
    for (const payload of [
      null,
      "evt",
      {},
      { data: {} },
      event(undefined),
      event({ id: 3 }),
    ]) {
      expect(await entitlementMembers(fake.sql, payload).orThrow()).toEqual([]);
    }
    expect(fake.calls).toHaveLength(0);
  });

  it("returns a database error as a result", async () => {
    const fake = fakeSql([
      [
        "entitlement_members",
        { throws: pgError("42883", "function does not exist") },
      ],
    ]);
    const result = await entitlementMembers(fake.sql, event("cus_1"));
    expect(result.ok).toBe(false);
    expect(result.error?.message).toBe("function does not exist");
  });
});
