import type { FlagClient as MiddlewareFlagClient } from "@supabase-labs/middleware-openfeature";

import { ErrorCode, OpenFeature, type Provider } from "@openfeature/server-sdk";
import { afterAll, describe, expect, expectTypeOf, it } from "vitest";

import {
  createFlagClient,
  createFlagsProvider,
  type FlagDefinition,
  flagContext,
} from "../../src/blocks/flags/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const USER = "8c5a3d3e-0000-4000-8000-000000000001";
const DOMAIN = "better-supabase-conformance";

const definitions: readonly FlagDefinition[] = [
  {
    key: "new_editor",
    type: "boolean",
    variants: { on: true, off: false },
    defaultVariant: "off",
    enabled: true,
    rules: [{ variant: "on", plans: ["pro"] }],
    rolloutPercentage: 0,
    rolloutVariant: undefined,
    overrides: [],
  },
  {
    key: "theme",
    type: "string",
    variants: { light: "light", dark: "dark" },
    defaultVariant: "light",
    enabled: true,
    rules: [],
    rolloutPercentage: 100,
    rolloutVariant: "dark",
    overrides: [],
  },
];

const provider = createFlagsProvider({ definitions, errorCodes: ErrorCode });
await OpenFeature.setProviderAndWait(DOMAIN, provider);
const client = OpenFeature.getClient(DOMAIN);

afterAll(async () => {
  await OpenFeature.clearProviders();
});

describe("OpenFeature", () => {
  it("pins the specification version", () => {
    expect(SPEC_PINS.openfeature).toBe("0.9.0");
  });

  it("is a server Provider and a middleware FlagClient without adapters", () => {
    expectTypeOf(provider).toExtend<Provider>();
    expectTypeOf(createFlagClient(provider)).toExtend<MiddlewareFlagClient>();
    expectTypeOf(client).toExtend<MiddlewareFlagClient>();
    expectTypeOf(flagContext({ jwtClaims: { sub: USER } })).toExtend<
      Parameters<typeof client.getBooleanDetails>[2]
    >();
  });

  it("resolves through the SDK with the provider's variant and reason (1.4, 2.2)", async () => {
    const context = flagContext({
      jwtClaims: {
        sub: USER,
        tenant_id: "org-1",
        features: { "org-1": ["pro"] },
      },
    });
    expect(
      await client.getBooleanDetails("new_editor", false, context),
    ).toEqual({
      flagKey: "new_editor",
      flagMetadata: {},
      value: true,
      variant: "on",
      reason: "TARGETING_MATCH",
    });
    expect(
      await client.getStringDetails("theme", "light", context),
    ).toMatchObject({
      value: "dark",
      variant: "dark",
      reason: "SPLIT",
    });
    expect(
      await client.getBooleanValue("new_editor", true, { targetingKey: USER }),
    ).toBe(false);
  });

  it("returns the default with the error code for a missing flag and a type mismatch (1.4.7, 2.2.7)", async () => {
    expect(await client.getBooleanDetails("missing", true)).toMatchObject({
      value: true,
      reason: "ERROR",
      errorCode: ErrorCode.FLAG_NOT_FOUND,
    });
    expect(await client.getNumberDetails("theme", 3)).toMatchObject({
      value: 3,
      reason: "ERROR",
      errorCode: ErrorCode.TYPE_MISMATCH,
    });
  });

  it("names itself in the provider metadata (2.1.1)", () => {
    expect(OpenFeature.getProviderMetadata(DOMAIN).name).toBe(
      "better-supabase",
    );
  });
});
