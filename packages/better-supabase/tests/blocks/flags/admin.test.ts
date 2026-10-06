import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/flags/index.ts";

import { createFlagAdmin } from "../../../src/blocks/flags/index.ts";

const row = {
  key: "beta",
  type: "boolean",
  variants: { on: true, off: false },
  default_variant: "off",
  enabled: true,
  rules: [],
  rollout_percentage: "10",
  rollout_variant: null,
  overrides: [],
};

describe("createFlagAdmin", () => {
  it("calls the staff functions with database names", async () => {
    const calls: [string, string, Record<string, unknown>][] = [];
    const transport: BlockTransport = {
      call: (schema, fn, args) => {
        calls.push([schema, fn, { ...args }]);
        if (fn === "list_flags") return Promise.resolve([row]);
        if (fn === "save_flag") return Promise.resolve(row);
        return Promise.resolve(true);
      },
    };
    const admin = createFlagAdmin({ transport, schema: "app" });
    expect((await admin.list().orThrow())[0]).toMatchObject({
      key: "beta",
      rolloutPercentage: 10,
    });
    expect(
      await admin
        .save("beta", {
          enabled: false,
          description: null,
          rolloutPercentage: 10,
          defaultVariant: "off",
        })
        .orThrow(),
    ).toMatchObject({ key: "beta" });
    expect(await admin.remove("beta").orThrow()).toBe(true);
    expect(await admin.override("beta", { userId: "u1" }, null).orThrow()).toBe(
      true,
    );
    expect(calls.slice(1)).toEqual([
      [
        "app",
        "save_flag",
        {
          key: "beta",
          definition: {
            description: null,
            default_variant: "off",
            enabled: false,
            rollout_percentage: 10,
          },
        },
      ],
      ["app", "delete_flag", { key: "beta" }],
      [
        "app",
        "set_flag_override",
        { key: "beta", variant: null, tenant: undefined, member: "u1" },
      ],
    ]);
  });

  it("reads a missing flag after save as undefined", async () => {
    const admin = createFlagAdmin({
      transport: { call: () => Promise.resolve(null) },
    });
    expect(await admin.save("x", {}).orThrow()).toBeUndefined();
    expect(await admin.remove("x").orThrow()).toBe(false);
  });
});
