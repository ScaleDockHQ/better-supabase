import { describe, expect, it, vi } from "vitest";

import {
  createFlagClient,
  createFlagsProvider,
  evaluateFlag,
  flagBucket,
  flagContext,
  type FlagDefinition,
  flagDefinitionsOf,
} from "../../../src/blocks/flags/index.ts";

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

/** The integration test checks the same vectors against flag_bucket() in SQL. */
const BUCKET_VECTORS: readonly (readonly [string, string, number])[] = [
  ["new_editor", USER, 1154],
  ["new_editor", "org-1", 697],
  ["checkout_v2", "user-42", 8741],
];

describe("flagBucket", () => {
  it.each(BUCKET_VECTORS)(
    "buckets %s for %s into %i",
    async (key, target, bucket) => {
      expect(await flagBucket(key, target)).toBe(bucket);
    },
  );
});

describe("evaluateFlag", () => {
  it("returns the default variant for a disabled flag", async () => {
    const result = await evaluateFlag(
      flag({
        enabled: false,
        overrides: [{ organizationId: undefined, userId: USER, variant: "on" }],
      }),
      { targetingKey: USER },
    );
    expect(result).toEqual({
      value: false,
      variant: "off",
      reason: "DISABLED",
    });
  });

  it("prefers a user override to a tenant override and to rules", async () => {
    const definition = flag({
      variants: { on: true, off: false, beta: true },
      overrides: [
        { organizationId: "org-1", userId: undefined, variant: "on" },
        { organizationId: undefined, userId: USER, variant: "beta" },
      ],
      rules: [{ variant: "off", tenants: ["org-1"] }],
    });
    expect(
      await evaluateFlag(definition, { targetingKey: USER, tenant: "org-1" }),
    ).toEqual({ value: true, variant: "beta", reason: "TARGETING_MATCH" });
    expect(
      await evaluateFlag(definition, {
        targetingKey: "other",
        tenant: "org-1",
      }),
    ).toMatchObject({ variant: "on", reason: "TARGETING_MATCH" });
  });

  it("matches the first rule whose lists all contain the caller", async () => {
    const definition = flag({
      rules: [
        { variant: "on", plans: ["pro", "enterprise"], roles: ["admin"] },
        { variant: "off", users: [USER] },
      ],
    });
    expect(
      await evaluateFlag(definition, {
        targetingKey: USER,
        tenant: "org-1",
        plans: ["pro"],
        role: "admin",
      }),
    ).toMatchObject({ variant: "on", reason: "TARGETING_MATCH" });
    expect(
      await evaluateFlag(definition, {
        targetingKey: USER,
        plans: ["pro"],
        role: "member",
      }),
    ).toMatchObject({ variant: "off", reason: "TARGETING_MATCH" });
    expect(
      await evaluateFlag(definition, {
        targetingKey: "x",
        plans: ["pro"],
        role: "member",
        roles: ["member", "admin"],
      }),
    ).toMatchObject({ variant: "on", reason: "TARGETING_MATCH" });
    expect(await evaluateFlag(definition, { targetingKey: "x" })).toMatchObject(
      {
        variant: "off",
        reason: "DEFAULT",
      },
    );
  });

  it("rolls out by bucket, by user first and then by tenant", async () => {
    // new_editor buckets USER at 1154 and org-1 at 697.
    const at = (rolloutPercentage: number) =>
      flag({ rolloutPercentage, rolloutVariant: "on" });
    expect(await evaluateFlag(at(11.55), { targetingKey: USER })).toMatchObject(
      {
        variant: "on",
        reason: "SPLIT",
      },
    );
    expect(await evaluateFlag(at(11.54), { targetingKey: USER })).toMatchObject(
      {
        variant: "off",
        reason: "DEFAULT",
      },
    );
    expect(await evaluateFlag(at(7), { tenant: "org-1" })).toMatchObject({
      reason: "SPLIT",
    });
    expect(await evaluateFlag(at(100))).toMatchObject({ reason: "DEFAULT" });
  });

  it("falls back to the default for a variant that does not exist", async () => {
    expect(await evaluateFlag(flag({ rules: [{ variant: "gone" }] }))).toEqual({
      value: false,
      variant: "off",
      reason: "DEFAULT",
    });
  });
});

describe("flagDefinitionsOf", () => {
  it("parses flag_definitions() rows", () => {
    expect(
      flagDefinitionsOf([
        {
          key: "plan_banner",
          type: "string",
          variants: { a: "blue", b: "green" },
          default_variant: "a",
          enabled: true,
          rules: [
            { variant: "b", plans: ["pro"], tenants: "bad" },
            { nope: 1 },
          ],
          rollout_percentage: "12.50",
          rollout_variant: null,
          overrides: [
            { organization_id: "org-1", user_id: null, variant: "b" },
          ],
        },
        { key: "odd", type: "weird", variants: null, enabled: false },
      ]),
    ).toEqual([
      {
        key: "plan_banner",
        type: "string",
        variants: { a: "blue", b: "green" },
        defaultVariant: "a",
        enabled: true,
        rules: [{ variant: "b", plans: ["pro"] }],
        rolloutPercentage: 12.5,
        rolloutVariant: undefined,
        overrides: [
          { organizationId: "org-1", userId: undefined, variant: "b" },
        ],
      },
      {
        key: "odd",
        type: "boolean",
        variants: {},
        defaultVariant: "",
        enabled: false,
        rules: [],
        rolloutPercentage: 0,
        rolloutVariant: undefined,
        overrides: [],
      },
    ]);
  });
});

describe("createFlagsProvider", () => {
  it("needs a transport or definitions", () => {
    expect(() => createFlagsProvider({})).toThrow(TypeError);
  });

  it("resolves each type and reports missing flags and type mismatches", async () => {
    const provider = createFlagsProvider({
      definitions: [
        flag(),
        flag({
          key: "banner",
          type: "string",
          variants: { a: "blue" },
          defaultVariant: "a",
        }),
        flag({
          key: "limit",
          type: "number",
          variants: { a: 5 },
          defaultVariant: "a",
        }),
        flag({
          key: "layout",
          type: "object",
          variants: { a: { cols: 2 } },
          defaultVariant: "a",
        }),
      ],
    });
    await provider.initialize();
    expect(provider.metadata.name).toBe("better-supabase");
    expect(
      await provider.resolveBooleanEvaluation("new_editor", true, {}),
    ).toEqual({
      value: false,
      variant: "off",
      reason: "DEFAULT",
    });
    expect(
      await provider.resolveStringEvaluation("banner", "x", {}),
    ).toMatchObject({ value: "blue" });
    expect(
      await provider.resolveNumberEvaluation("limit", 0, {}),
    ).toMatchObject({ value: 5 });
    expect(
      await provider.resolveObjectEvaluation("layout", {}, {}),
    ).toMatchObject({
      value: { cols: 2 },
    });
    expect(
      await provider.resolveBooleanEvaluation("missing", true, {}),
    ).toMatchObject({
      value: true,
      reason: "ERROR",
      errorCode: "FLAG_NOT_FOUND",
    });
    expect(
      await provider.resolveNumberEvaluation("banner", 1, {}),
    ).toMatchObject({
      value: 1,
      reason: "ERROR",
      errorCode: "TYPE_MISMATCH",
    });
    expect(
      await provider.resolveObjectEvaluation("limit", {}, {}),
    ).toMatchObject({
      errorCode: "TYPE_MISMATCH",
    });
  });

  it("caches definitions for ttl, reloads after refresh() and after a failure", async () => {
    let clock = 0;
    const call = vi
      .fn()
      .mockResolvedValueOnce([
        {
          key: "new_editor",
          variants: { on: true, off: false },
          default_variant: "on",
        },
      ])
      .mockRejectedValueOnce(new Error("connection reset"))
      .mockResolvedValue([]);
    const provider = createFlagsProvider({
      transport: { call },
      schema: "flags",
      ttl: 1000,
      now: () => clock,
    });
    expect(
      await provider.resolveBooleanEvaluation("new_editor", false, {}),
    ).toMatchObject({ value: true });
    clock = 999;
    await provider.resolveBooleanEvaluation("new_editor", false, {});
    expect(call).toHaveBeenCalledTimes(1);
    expect(call).toHaveBeenCalledWith("flags", "flag_definitions", {});
    provider.refresh();
    expect(
      await provider.resolveBooleanEvaluation("new_editor", false, {}),
    ).toEqual({
      value: false,
      reason: "ERROR",
      errorCode: "GENERAL",
      errorMessage: "connection reset",
    });
    expect(
      await provider.resolveBooleanEvaluation("new_editor", false, {}),
    ).toMatchObject({
      errorCode: "FLAG_NOT_FOUND",
    });
    expect(call).toHaveBeenCalledTimes(3);
  });

  it("uses the error codes it is given", async () => {
    const provider = createFlagsProvider({
      definitions: [],
      errorCodes: {
        FLAG_NOT_FOUND: "not-found",
        TYPE_MISMATCH: "type",
        PROVIDER_NOT_READY: "not-ready",
        GENERAL: "general",
      },
    });
    expect(await provider.resolveStringEvaluation("x", "", {})).toMatchObject({
      errorCode: "not-found",
    });
  });
});

describe("createFlagClient", () => {
  it("returns evaluation details from a provider or from options", async () => {
    const definitions = [flag({ rules: [{ variant: "on", users: [USER] }] })];
    for (const client of [
      createFlagClient({ definitions }),
      createFlagClient(createFlagsProvider({ definitions })),
    ]) {
      expect(
        await client.getBooleanDetails("new_editor", false, {
          targetingKey: USER,
        }),
      ).toEqual({
        flagKey: "new_editor",
        flagMetadata: {},
        value: true,
        variant: "on",
        reason: "TARGETING_MATCH",
      });
      expect(await client.getBooleanDetails("new_editor", true)).toMatchObject({
        value: false,
      });
      expect(await client.getStringDetails("new_editor", "x")).toMatchObject({
        errorCode: "TYPE_MISMATCH",
      });
      expect(await client.getNumberDetails("new_editor", 1)).toMatchObject({
        value: 1,
      });
      expect(
        await client.getObjectDetails("new_editor", { a: 1 }),
      ).toMatchObject({ value: { a: 1 } });
    }
  });
});

describe("flagContext", () => {
  it("reads the user, tenant, plan features and role from the claims", () => {
    expect(
      flagContext({
        jwtClaims: {
          sub: USER,
          tenant_id: "org-1",
          features: { "org-1": ["pro"], "org-2": ["free"] },
          memberships: { "org-1": "admin" },
        },
      }),
    ).toEqual({
      targetingKey: USER,
      tenant: "org-1",
      plans: ["pro"],
      role: "admin",
    });
  });

  it("takes the tenant from app_metadata or the source, and custom claim names", () => {
    expect(
      flagContext(
        {
          jwtClaims: {
            sub: USER,
            app_metadata: { org: "org-2" },
            plan: { "org-2": ["free"] },
            roles: { "org-2": "member" },
          },
        },
        {
          tenantClaim: "org",
          featuresClaim: "plan",
          membershipsClaim: "roles",
        },
      ),
    ).toEqual({
      targetingKey: USER,
      tenant: "org-2",
      plans: ["free"],
      role: "member",
    });
    expect(flagContext({ jwtClaims: null, tenant: "org-3" })).toEqual({
      tenant: "org-3",
    });
    expect(flagContext({})).toEqual({});
  });

  it("reads roles from PermDock's memberships entries", () => {
    const jwtClaims = {
      sub: USER,
      tenant_id: "org-1",
      memberships: [
        {
          scope: "team",
          id: "org-1",
          within: { org: "org-9" },
          roles: ["lead"],
        },
        { scope: "org", id: "org-1", roles: ["admin", "billing"] },
      ],
    };
    expect(flagContext({ jwtClaims })).toEqual({
      targetingKey: USER,
      tenant: "org-1",
      role: "admin",
      roles: ["admin", "billing"],
    });
    expect(flagContext({ jwtClaims }, { membershipScope: "team" })).toEqual({
      targetingKey: USER,
      tenant: "org-1",
      role: "lead",
    });
    expect(
      flagContext(
        { jwtClaims },
        {
          roles: (claims, tenant) => (claims["sub"] ? `${tenant}:viewer` : []),
        },
      ),
    ).toMatchObject({ role: "org-1:viewer" });
    expect(
      flagContext({
        jwtClaims: { tenant_id: "org-2", memberships: jwtClaims.memberships },
      }),
    ).toEqual({ tenant: "org-2" });
  });
});
