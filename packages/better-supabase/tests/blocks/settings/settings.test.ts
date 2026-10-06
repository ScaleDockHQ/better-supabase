import * as v from "valibot";
import { describe, expect, expectTypeOf, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { defineSettings } from "../../../src/blocks/settings/index.ts";

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
    const client = settings.connect({ transport });
    expect(await client.user.get().orThrow()).toEqual({
      theme: "dark",
      digest: undefined,
    });
    expect(await client.user.get("theme").orThrow()).toBe("dark");
    expect(calls[0]).toEqual(["better_supabase", "get_user_settings", {}]);
  });

  it("reads a stored value that fails its schema as the default", async () => {
    const { transport } = fakeTransport(() => ({ seats: -1 }));
    const client = settings.connect({ transport, schema: "app" });
    expect(await client.organization.get("org-1", "seats").orThrow()).toBe(5);
    expect(await client.organization.get("org-1").orThrow()).toEqual({
      seats: 5,
    });
  });

  it("validates before writing", async () => {
    const { transport, calls } = fakeTransport(() => null);
    const client = settings.connect({ transport });
    // @ts-expect-error not one of the enum values
    const bad = await client.user.set("theme", "neon");
    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(calls).toHaveLength(0);

    expect(await client.user.set("theme", "light").orThrow()).toBe("light");
    expect(await client.organization.set("org-1", "seats", 9).orThrow()).toBe(
      9,
    );
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
    const client = settings.connect({ transport });
    // @ts-expect-error not a declared key
    const read = await client.user.get("color");
    // @ts-expect-error not a declared key
    const write = await client.user.set("color", "red");
    // @ts-expect-error not a declared key
    const reset = await client.organization.reset("org-1", "color");
    for (const result of [read, write, reset]) {
      expect(result).toMatchObject({
        ok: false,
        error: { kind: "invalid_input" },
      });
    }
    expect(calls).toHaveLength(0);
    expect(await client.user.reset("theme").orThrow()).toBe(true);
    expect(await client.organization.reset("org-1", "seats").orThrow()).toBe(
      true,
    );
  });

  it("types values per key", () => {
    const client = settings.connect({
      transport: fakeTransport(() => 0).transport,
    });
    expectTypeOf(client.user.get("theme").orThrow()).resolves.toEqualTypeOf<
      "light" | "dark" | "system"
    >();
    expectTypeOf(client.user.get("digest").orThrow()).resolves.toEqualTypeOf<
      { weekly: boolean } | undefined
    >();
    expectTypeOf(
      client.organization.get("org-1", "seats").orThrow(),
    ).resolves.toEqualTypeOf<number>();
  });

  it("works with an empty spec", async () => {
    const empty = defineSettings({});
    expect(empty.schemas).toEqual({ user: {}, organization: {} });
    const client = empty.connect({
      transport: fakeTransport(() => null).transport,
    });
    expect(await client.user.get().orThrow()).toEqual({});
  });
});
