import * as v from "valibot";
import { describe, expect, expectTypeOf, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createSettings,
  defineSettings,
} from "../../../src/blocks/settings/index.ts";

function fakeTransport(
  answer: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const calls: [string, string, Record<string, unknown>][] = [];

  const transport: BlockTransport = {
    async call(schemaName, fn, args) {
      calls.push([schemaName, fn, { ...args }]);

      return answer(fn, { ...args });
    },
  };

  return { transport, calls };
}

const settings = defineSettings({
  user: {
    theme: {
      schema: v.picklist(["light", "dark", "system"]),
      default: "system",
    },
    digest: { schema: v.object({ weekly: v.boolean() }) },
  },
  organization: {
    seats: {
      schema: v.pipe(v.number(), v.integer(), v.minValue(1)),
      default: 5,
    },
  },
});

describe("defineSettings", () => {
  it("merges stored values over the defaults and drops unknown keys", async () => {
    const { transport, calls } = fakeTransport(() => ({
      theme: "dark",
      stale: true,
    }));

    const client = createSettings({ settings, transport });
    expect(await client.getUser().orThrow()).toEqual({
      theme: "dark",
      digest: undefined,
    });
    expect(await client.getUser("theme").orThrow()).toBe("dark");
    expect(calls[0]).toEqual(["better_supabase", "get_user_settings", {}]);
  });

  it("reads a stored value that fails its schema as the default", async () => {
    const { transport } = fakeTransport(() => ({ seats: -1 }));
    const client = createSettings({ settings, transport, schema: "app" });
    expect(
      await client
        .getOrganization({ organizationId: "org-1", key: "seats" })
        .orThrow(),
    ).toBe(5);
    expect(
      await client.getOrganization({ organizationId: "org-1" }).orThrow(),
    ).toEqual({ seats: 5 });
  });

  it("validates before writing", async () => {
    const { transport, calls } = fakeTransport(() => null);
    const client = createSettings({ settings, transport });
    // @ts-expect-error not one of the enum values
    const bad = await client.setUser({ key: "theme", value: "neon" });
    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(calls).toHaveLength(0);

    expect(
      await client.setUser({ key: "theme", value: "light" }).orThrow(),
    ).toBe("light");
    expect(
      await client
        .setOrganization({ organizationId: "org-1", key: "seats", value: 9 })
        .orThrow(),
    ).toBe(9);
    expect(calls).toEqual([
      [
        "better_supabase",
        "set_user_setting",
        { key: "theme", value: { value: "light" } },
      ],
      [
        "better_supabase",
        "set_organization_setting",
        { tenant: "org-1", key: "seats", value: { value: 9 } },
      ],
    ]);
  });

  it("refuses keys it does not declare", async () => {
    const { transport, calls } = fakeTransport(() => true);
    const client = createSettings({ settings, transport });
    // @ts-expect-error not a declared key
    const read = await client.getUser("color");
    // @ts-expect-error not a declared key
    const write = await client.setUser({ key: "color", value: "red" });

    const reset = await client.resetOrganization({
      organizationId: "org-1",
      // @ts-expect-error not a declared key
      key: "color",
    });

    for (const result of [read, write, reset]) {
      expect(result).toMatchObject({
        ok: false,
        error: { kind: "invalid_input" },
      });
    }

    expect(calls).toHaveLength(0);
    expect(await client.resetUser("theme").orThrow()).toBe(true);
    expect(
      await client
        .resetOrganization({ organizationId: "org-1", key: "seats" })
        .orThrow(),
    ).toBe(true);
  });

  it("types values per key", () => {
    const client = createSettings({
      settings,
      transport: fakeTransport(() => 0).transport,
    });

    expectTypeOf(client.getUser("theme").orThrow()).resolves.toEqualTypeOf<
      "light" | "dark" | "system"
    >();
    expectTypeOf(client.getUser("digest").orThrow()).resolves.toEqualTypeOf<
      { weekly: boolean } | undefined
    >();
    expectTypeOf(
      client
        .getOrganization({ organizationId: "org-1", key: "seats" })
        .orThrow(),
    ).resolves.toEqualTypeOf<number>();
  });

  it("works with an empty spec", async () => {
    const empty = defineSettings({});
    expect(empty.schemas).toEqual({ user: {}, organization: {}, platform: {} });

    const client = createSettings({
      settings: empty,
      transport: fakeTransport(() => null).transport,
    });

    expect(await client.getUser().orThrow()).toEqual({});
  });

  it("reads and writes platform settings through their functions", async () => {
    const platform = defineSettings({
      platform: {
        fee: {
          schema: v.number(),
          default: 1,
          permission: "billing.platform",
          read: "public",
        },
      },
    });

    expect(platform.schemas.platform.fee.permission).toBe("billing.platform");

    const { transport, calls } = fakeTransport((fn) =>
      fn === "get_platform_settings"
        ? { fee: 2 }
        : fn === "reset_platform_setting",
    );

    const client = createSettings({ settings: platform, transport });
    expect(await client.getPlatform("fee").orThrow()).toBe(2);
    expect(await client.setPlatform({ key: "fee", value: 3 }).orThrow()).toBe(
      3,
    );
    expect(await client.resetPlatform("fee").orThrow()).toBe(true);
    expect(calls.map(([, fn, args]) => [fn, args])).toEqual([
      ["get_platform_settings", {}],
      ["set_platform_setting", { key: "fee", value: { value: 3 } }],
      ["reset_platform_setting", { key: "fee" }],
    ]);
    expectTypeOf<
      Parameters<typeof client.setPlatform<"fee">>[0]["value"]
    >().toEqualTypeOf<number>();
  });
});

describe("resolve", () => {
  it("applies the legal entity's value, then the organization's, then the default", async () => {
    const sources = [
      { value: 8, source: "legal_entity", legalEntityId: "le1" },
      { value: 3, source: "organization", legalEntityId: "le1" },
      { value: null, source: "default", legalEntityId: null },
    ];

    const queue = [...sources];
    const { transport, calls } = fakeTransport(() => queue.shift());
    const client = createSettings({ settings, transport });

    expect(
      await client
        .resolve({
          organizationId: "org-1",
          key: "seats",
          legalEntityId: "le1",
        })
        .orThrow(),
    ).toBe(8);
    expect(
      await client.resolve({ organizationId: "org-1", key: "seats" }).orThrow(),
    ).toBe(3);
    expect(
      await client.resolve({ organizationId: "org-1", key: "seats" }).orThrow(),
    ).toBe(5);
    expect(calls[0]).toEqual([
      "better_supabase",
      "resolve_setting",
      { tenant: "org-1", key: "seats", legal_entity: "le1" },
    ]);
    expect(calls[1]?.[2]["legal_entity"]).toBeNull();
  });
});
