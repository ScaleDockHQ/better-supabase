import { describe, expect, it } from "vitest";

import { createFlags } from "../../../src/blocks/flags/index.ts";

const flag = {
  key: "beta",
  type: "boolean",
  variants: { on: true, off: false },
  default_variant: "off",
  enabled: true,
  rules: [],
  rollout_percentage: "0",
  rollout_variants: [],
  overrides: [
    { organization_id: "o1", variant: "on" },
    { organization_id: "o2", variant: "off" },
    { organization_id: "o3", variant: "on" },
  ],
};

const admin = createFlags({
  transport: { call: () => Promise.resolve([flag]) },
});

describe("flags helpers", () => {
  it("tenantsWith lists the tenants whose override turns the flag on", async () => {
    expect(await admin.tenantsWith({ key: "beta" }).orThrow()).toEqual([
      "o1",
      "o3",
    ]);
    expect(await admin.tenantsWith({ key: "none" }).orThrow()).toEqual([]);
  });

  it("isEnabled evaluates the flag and treats an unknown flag as off", async () => {
    expect(await admin.isEnabled({ key: "beta" }).orThrow()).toBe(false);
    expect(await admin.isEnabled({ key: "none" }).orThrow()).toBe(false);
  });
});
