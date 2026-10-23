import { describe, expect, it, vi } from "vitest";

import type {
  FlagDefinition,
  FlagsProvider,
} from "../../src/blocks/flags/index.ts";

import {
  betterSupabaseAdapter,
  createIdentify,
  flagContextOf,
  flagOptions,
  getProviderData,
} from "../../src/flags-sdk/index.ts";

const USER = "8c5a3d3e-0000-4000-8000-000000000001";

const flag = (patch: Partial<FlagDefinition> = {}): FlagDefinition => ({
  key: "new_editor",
  type: "boolean",
  variants: { on: true, off: false },
  defaultVariant: "off",
  enabled: true,
  rules: [],
  rolloutPercentage: 0,
  rolloutVariant: undefined,
  overrides: [],
  ...patch,
});

const DEFINITIONS: readonly FlagDefinition[] = [
  flag({
    description: "The new editor",
    rules: [{ variant: "on", contexts: { brand: ["acme"] } }],
    updatedAt: "2026-10-17T10:00:00Z",
  }),
  flag({
    key: "theme",
    type: "string",
    variants: { light: "light", dark: "dark" },
    defaultVariant: "light",
    overrides: [
      { organizationId: "org-1", userId: undefined, variant: "dark" },
    ],
  }),
  flag({ key: "old_banner", archived: true }),
];

const request = {
  headers: new Headers({ host: "acme.example.com" }),
  cookies: { get: () => undefined },
};

describe("flagContextOf", () => {
  it("maps the user, the organization and custom contexts", () => {
    expect(
      flagContextOf({
        user: { id: USER },
        organization: {
          id: "org-1",
          plans: ["pro"],
          roles: ["admin", "owner"],
        },
        brand: { id: "acme" },
        region: undefined,
      }),
    ).toEqual({
      targetingKey: USER,
      tenant: "org-1",
      plans: ["pro"],
      role: "admin",
      roles: ["admin", "owner"],
      contexts: { brand: "acme" },
    });
    expect(flagContextOf()).toEqual({});
  });
});

describe("betterSupabaseAdapter", () => {
  it("decides from cached definitions, called or by reference", async () => {
    const bsb = betterSupabaseAdapter({
      definitions: DEFINITIONS,
      origin: "https://admin.example.com/flags/{key}",
    });

    const adapter = bsb<boolean>();

    expect(adapter.adapterId).toBe(bsb<string>().adapterId);
    expect(adapter.origin?.("new editor")).toBe(
      "https://admin.example.com/flags/new%20editor",
    );
    expect(
      await adapter.decide({
        key: "new_editor",
        entities: { brand: { id: "acme" } },
      }),
    ).toBe(true);
    expect(
      await adapter.decide({ key: "new_editor", defaultValue: true }),
    ).toBe(false);
    expect(
      await bsb<string>().decide({
        key: "theme",
        entities: { organization: { id: "org-1" } },
        defaultValue: "light",
      }),
    ).toBe("dark");
    expect(bsb.origin).toBe("https://admin.example.com/flags/{key}");
  });

  it("falls back to defaultValue, and throws without one", async () => {
    const adapter = betterSupabaseAdapter({ definitions: DEFINITIONS })();

    expect(await adapter.decide({ key: "missing", defaultValue: 7 })).toBe(7);
    expect(
      await betterSupabaseAdapter({
        definitions: [flag({ defaultVariant: "gone" })],
      })().decide({ key: "new_editor", defaultValue: true }),
    ).toBe(true);
    expect(await adapter.decide({ key: "theme", defaultValue: false })).toBe(
      false,
    );
    expect(adapter.origin).toBeUndefined();
    await expect(adapter.decide({ key: "missing" })).rejects.toThrow(
      'Flag "missing": it is missing, and it has no defaultValue',
    );

    const failing = betterSupabaseAdapter({
      transport: { call: () => Promise.reject(new Error("offline")) },
    })();

    expect(
      await failing.decide({ key: "new_editor", defaultValue: true }),
    ).toBe(true);
    await expect(failing.decide({ key: "new_editor" })).rejects.toThrow(
      "offline",
    );
    expect(
      await failing.bulkDecide({
        flags: [{ key: "new_editor", defaultValue: true }],
      }),
    ).toEqual({});
  });

  describe("null values", () => {
    const json = flag({
      key: "layout",
      type: "object",
      variants: { none: null, grid: { columns: 3 }, label: "grid" },
      defaultVariant: "none",
    });

    const served = (variant: string) => ({
      definitions: [{ ...json, defaultVariant: variant }],
    });

    // [variant, declared defaultValue, served value]
    const cases: [string, unknown, unknown][] = [
      ["missing", null, null],
      ["missing", { columns: 1 }, { columns: 1 }],
      ["none", undefined, null],
      ["none", null, null],
      ["none", { columns: 1 }, { columns: 1 }],
      ["grid", undefined, { columns: 3 }],
      ["grid", null, { columns: 3 }],
      ["grid", { columns: 1 }, { columns: 3 }],
      ["label", null, null],
      ["label", { columns: 1 }, { columns: 1 }],
      ["label", "list", "grid"],
    ];

    it.each(cases)(
      "variant %s with defaultValue %j serves %j",
      async (variant, defaultValue, expected) => {
        const adapter = betterSupabaseAdapter(served(variant))();

        const params = {
          key: "layout",
          ...(defaultValue === undefined ? {} : { defaultValue }),
        };

        expect(await adapter.decide(params)).toEqual(expected);
        expect(await adapter.bulkDecide({ flags: [params] })).toEqual({
          layout: expected,
        });
      },
    );

    it("throws for a missing variant without a defaultValue", async () => {
      const adapter = betterSupabaseAdapter(served("missing"))();

      await expect(adapter.decide({ key: "layout" })).rejects.toThrow(
        "it has no such variant or has another type",
      );
      expect(await adapter.bulkDecide({ flags: [{ key: "layout" }] })).toEqual(
        {},
      );
    });
  });

  it("never serves a flag of an unknown type", async () => {
    const adapter = betterSupabaseAdapter({
      definitions: [flag({ invalidType: "json" })],
    })();

    expect(
      await adapter.decide({ key: "new_editor", defaultValue: false }),
    ).toBe(false);
    await expect(adapter.decide({ key: "new_editor" })).rejects.toThrow(
      'it has the unknown type "json"',
    );
    expect(
      await adapter.bulkDecide({
        flags: [{ key: "new_editor" }, { key: "x", defaultValue: 1 }],
      }),
    ).toEqual({ x: 1 });
  });

  it("decides a batch from one load", async () => {
    const definitions = vi.fn(() => Promise.resolve(DEFINITIONS));

    const provider: FlagsProvider<string> = {
      ...betterSupabaseAdapter({ definitions: DEFINITIONS }).provider,
      definitions,
    };

    const adapter = betterSupabaseAdapter({ provider })();

    expect(
      await adapter.bulkDecide({
        flags: [
          { key: "new_editor" },
          { key: "theme", defaultValue: "light" },
          { key: "missing", defaultValue: false },
          { key: "gone" },
        ],
        entities: { organization: { id: "org-1" }, brand: { id: "acme" } },
      }),
    ).toEqual({ new_editor: true, theme: "dark", missing: false });
    expect(definitions).toHaveBeenCalledOnce();
  });
});

describe("createIdentify", () => {
  it("reads entities from claims, the tenant and custom contexts", async () => {
    const identify = createIdentify({
      claims: () => ({
        sub: USER,
        tenant_id: "org-1",
        features: { "org-1": ["pro"] },
        memberships: { "org-1": "admin" },
        region_id: "eu",
      }),
      contextClaims: { region: "region_id" },
      contexts: (req) => ({
        brand: req.headers.get("host")?.split(".")[0],
        user: "ignored",
      }),
    });

    expect(await identify(request)).toEqual({
      user: { id: USER },
      organization: { id: "org-1", plans: ["pro"], roles: ["admin"] },
      region: { id: "eu" },
      brand: { id: "acme" },
    });
  });

  it("returns no entities for an anonymous request", async () => {
    const identify = createIdentify({
      claims: () => null,
      tenant: () => Promise.resolve("org-2"),
    });

    expect(await identify(request)).toEqual({ organization: { id: "org-2" } });
    expect(await createIdentify({ claims: () => undefined })(request)).toEqual(
      {},
    );
  });
});

describe("flagOptions and getProviderData", () => {
  it("lists variants as options", () => {
    expect(flagOptions({ variants: { on: true, off: false } })).toEqual([
      { value: true, label: "on" },
      { value: false, label: "off" },
    ]);
  });

  it("describes every flag that is not archived", async () => {
    const bsb = betterSupabaseAdapter({
      definitions: DEFINITIONS,
      origin: (key) => (key === "theme" ? undefined : `/admin/${key}`),
    });

    expect(await getProviderData(bsb)).toEqual({
      definitions: {
        new_editor: {
          options: [
            { value: true, label: "on" },
            { value: false, label: "off" },
          ],
          description: "The new editor",
          origin: "/admin/new_editor",
          updatedAt: Date.parse("2026-10-17T10:00:00Z"),
        },
        theme: {
          options: [
            { value: "light", label: "light" },
            { value: "dark", label: "dark" },
          ],
        },
      },
      hints: [],
    });
  });

  it("hints at a flag of an unknown type", async () => {
    const data = await getProviderData({
      provider: betterSupabaseAdapter({
        definitions: [flag({ invalidType: "json" })],
      }).provider,
    });

    expect(data.hints).toEqual([
      {
        key: "better-supabase/invalid-type",
        text: 'Flag "new_editor" has the unknown type "json", so it always serves its fallback',
      },
    ]);
  });

  it("turns a failed load into a hint", async () => {
    const bsb = betterSupabaseAdapter({
      transport: { call: () => Promise.reject(new Error("offline")) },
    });

    expect(await getProviderData(bsb)).toEqual({
      definitions: {},
      hints: [
        {
          key: "better-supabase/load-failed",
          text: "Could not load the flag definitions: offline",
        },
      ],
    });
  });
});
