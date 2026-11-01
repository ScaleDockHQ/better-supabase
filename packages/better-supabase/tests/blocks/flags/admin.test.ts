import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/flags/index.ts";

import { createFlags } from "../../../src/blocks/flags/index.ts";

const row = {
  key: "beta",
  type: "boolean",
  variants: { on: true, off: false },
  default_variant: "off",
  enabled: true,
  rules: [],
  rollout_percentage: "10",
  rollout_variants: [],
  overrides: [],
};

describe("createFlags", () => {
  it("calls the staff functions with database names", async () => {
    const calls: [string, string, Record<string, unknown>][] = [];

    const transport: BlockTransport = {
      call: (schema, fn, args) => {
        calls.push([schema, fn, { ...args }]);

        if (fn === "list_flags") {
          return Promise.resolve([row]);
        }

        if (fn === "save_flag") {
          return Promise.resolve(row);
        }

        return Promise.resolve(true);
      },
    };

    const admin = createFlags({ transport, schema: "app" });
    expect((await admin.list().orThrow())[0]).toMatchObject({
      key: "beta",
      rolloutPercentage: 10,
    });
    expect(
      await admin
        .upsert({
          key: "beta",
          input: {
            enabled: false,
            archived: true,
            description: null,
            rolloutPercentage: 10,
            defaultVariant: "off",
          },
        })
        .orThrow(),
    ).toMatchObject({ key: "beta" });
    expect(await admin.remove("beta").orThrow()).toBe(true);
    expect(
      await admin
        .override({ key: "beta", target: { userId: "u1" }, variant: null })
        .orThrow(),
    ).toBe(true);
    await admin
      .override({
        key: "beta",
        target: { context: "brand", contextKey: "acme" },
        variant: "on",
      })
      .orThrow();
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
            archived: true,
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
      [
        "app",
        "set_flag_override",
        {
          key: "beta",
          variant: "on",
          tenant: undefined,
          member: undefined,
          context: "brand",
          context_key: "acme",
        },
      ],
    ]);
  });

  it("saves with a message, reads revisions and manages segments", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const transport: BlockTransport = {
      call: (_schema, fn, args) => {
        calls.push([fn, { ...args }]);

        switch (fn) {
          case "flag_history": {
            return Promise.resolve([
              {
                revision: 2,
                definition: row,
                message: "Ship it",
                changed_by: "u1",
                changed_at: "2026-10-27T10:00:00Z",
              },
              { revision: 1, definition: null },
            ]);
          }

          case "list_flag_segments": {
            return Promise.resolve([
              {
                name: "beta-testers",
                description: null,
                rules: { users: ["u1"] },
              },
              { rules: {} },
            ]);
          }

          case "save_flag_segment": {
            return Promise.resolve({
              name: "staff",
              rules: { roles: ["owner"] },
            });
          }

          default: {
            return Promise.resolve(fn === "delete_flag_segment" ? true : row);
          }
        }
      },
    };

    const admin = createFlags({ transport });

    await admin
      .upsert({ key: "beta", input: { enabled: true }, message: "Ship it" })
      .orThrow();
    expect(calls[0]).toEqual([
      "save_flag",
      { key: "beta", definition: { enabled: true }, message: "Ship it" },
    ]);

    const history = await admin.history("beta").orThrow();
    expect(history).toHaveLength(1);
    expect(history[0]).toMatchObject({
      revision: 2,
      message: "Ship it",
      changedBy: "u1",
      definition: { key: "beta", rolloutVariants: [] },
    });

    expect(
      await admin.restore({ key: "beta", revision: 2 }).orThrow(),
    ).toMatchObject({ key: "beta" });
    expect(calls.at(-1)).toEqual([
      "restore_flag",
      { key: "beta", revision: 2 },
    ]);

    expect(await admin.segments().orThrow()).toEqual([
      { name: "beta-testers", users: ["u1"] },
    ]);
    expect(
      await admin.saveSegment({ name: "staff", roles: ["owner"] }).orThrow(),
    ).toMatchObject({ name: "staff", roles: ["owner"] });
    expect(calls.at(-1)).toEqual([
      "save_flag_segment",
      { name: "staff", description: null, rules: { roles: ["owner"] } },
    ]);
    expect(await admin.removeSegment("staff").orThrow()).toBe(true);
  });

  it("reads a missing flag after save as undefined", async () => {
    const admin = createFlags({
      transport: { call: () => Promise.resolve(null) },
    });

    expect(
      await admin.upsert({ key: "x", input: {} }).orThrow(),
    ).toBeUndefined();
    expect(await admin.remove("x").orThrow()).toBe(false);
  });
});
