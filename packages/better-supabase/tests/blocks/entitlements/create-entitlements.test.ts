import { describe, expect, it } from "vitest";

import { dbError } from "../../../src/core/errors.ts";
import { createEntitlements } from "../../../src/blocks/entitlements/index.ts";

describe("createEntitlements", () => {
  it("calls has_entitlement and entitlement_value as the member", async () => {
    const calls: [string, string, Record<string, unknown>][] = [];
    const entitlements = createEntitlements({
      schema: "api",
      transport: {
        call: (schema, fn, args) => {
          calls.push([schema, fn, { ...args }]);
          if (fn === "has_entitlement") return Promise.resolve(true);
          return Promise.resolve(args["key"] === "seats" ? 10 : null);
        },
      },
    });
    expect(await entitlements.has("org-1", "exports").orThrow()).toBe(true);
    expect(await entitlements.value("org-1", "seats").orThrow()).toBe(10);
    expect(
      await entitlements.value("org-1", "sso").orThrow(),
    ).toBeUndefined();
    expect(calls).toEqual([
      ["api", "has_entitlement", { tenant: "org-1", key: "exports" }],
      ["api", "entitlement_value", { tenant: "org-1", key: "seats" }],
      ["api", "entitlement_value", { tenant: "org-1", key: "sso" }],
    ]);
  });

  it("runs hooks around its methods", async () => {
    const entitlements = createEntitlements({
      transport: { call: () => Promise.resolve(true) },
      hooks: {
        has: {
          before: ([, key]) =>
            key === "beta" ? dbError("forbidden", "Not yet") : undefined,
        },
      },
    });
    const refused = await entitlements.has("org-1", "beta");
    expect(refused.ok).toBe(false);
    expect(await entitlements.has("org-1", "exports").orThrow()).toBe(true);
  });
});
