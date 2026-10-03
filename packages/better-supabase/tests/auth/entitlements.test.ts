import { describe, expect, expectTypeOf, it } from "vitest";

import type { AuthSession } from "../../src/auth/view.ts";

import {
  type EntitlementKey,
  hasEntitlement,
} from "../../src/auth/entitlements.ts";

const ACME = "00000000-0000-4000-8000-000000000001";
const GLOBEX = "00000000-0000-4000-8000-000000000002";

interface Claims {
  memberships?: { scope: string; id: string; roles: string[] }[];
  features?: Record<string, ("exports" | "sso")[]>;
}

const session = <C extends object>(claims: C): AuthSession<C> => ({
  kind: "user",
  user: { id: "u1" },
  claims: { sub: "u1", ...claims },
  expiresAt: null,
  aal: "aal1",
  anonymous: false,
  amr: [],
});

describe("hasEntitlement", () => {
  const user = session<Claims>({
    memberships: [
      { scope: "tenant", id: ACME, roles: ["admin"] },
      { scope: "tenant", id: GLOBEX, roles: ["member"] },
    ],
    features: { [ACME]: ["exports"], [GLOBEX]: [] },
  });

  it("checks the entitlement within one tenant", () => {
    expect(hasEntitlement(user, ACME, "exports")).toBe(true);
    expect(hasEntitlement(user, ACME, "sso")).toBe(false);
    expect(hasEntitlement(user, GLOBEX, "exports")).toBe(false);
    expect(hasEntitlement(user, "other", "exports")).toBe(false);
  });

  it("is false without a user or a features claim", () => {
    expect(
      hasEntitlement({ kind: "anon", reason: "none" }, ACME, "exports"),
    ).toBe(false);
    expect(hasEntitlement(session<Claims>({}), ACME, "exports")).toBe(false);
  });

  it("never reads plan features from memberships entitlements (seats)", () => {
    const seats = session({
      memberships: [
        { scope: "tenant", id: ACME, roles: [], entitlements: ["exports"] },
      ],
    });
    expect(hasEntitlement(seats, ACME, "exports")).toBe(false);
  });

  it("ignores inherited keys", () => {
    const tricky = session({ features: {} });
    expect(hasEntitlement(tricky, "constructor", "exports")).toBe(false);
  });

  it("reads a configured claim name", () => {
    const plans = session({ plans: { [ACME]: ["sso"] } });
    expect(hasEntitlement(plans, ACME, "sso", "plans")).toBe(true);
    expect(hasEntitlement(plans, ACME, "sso")).toBe(false);
  });

  it("types keys from the claims schema", () => {
    expectTypeOf<EntitlementKey<Claims>>().toEqualTypeOf<"exports" | "sso">();
    expectTypeOf<EntitlementKey<unknown>>().toEqualTypeOf<string>();
    // @ts-expect-error: not an entitlement of the claims schema
    hasEntitlement(user, ACME, "billing");
  });
});
