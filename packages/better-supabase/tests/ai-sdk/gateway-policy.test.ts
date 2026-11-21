import { describe, expect, it } from "vitest";

import {
  applyGatewayPolicy,
  gatewayPolicyReader,
  gatewayPolicySchema,
  governedGatewayOptions,
  mergeGatewayPolicies,
  parseGatewayPolicy,
} from "../../src/ai-sdk/index.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";

describe("parseGatewayPolicy", () => {
  it("reads nothing as the empty policy", () => {
    expect(parseGatewayPolicy(undefined)).toEqual(ok({}));
    expect(parseGatewayPolicy(null)).toEqual(ok({}));
  });

  it("accepts a full policy and upper-cases country codes", () => {
    const parsed = parseGatewayPolicy({
      zeroDataRetention: true,
      allowedProviders: ["anthropic", "bedrock"],
      region: "eu",
      promptCaching: true,
      headquarters: ["us", "de"],
    });

    expect(parsed.ok && parsed.data.headquarters).toEqual(["US", "DE"]);
  });

  it.each([
    { unknown: true },
    { zeroDataRetention: "yes" },
    { allowedProviders: [] },
    { allowedProviders: ["Not A Slug"] },
    { region: "mars" },
    { headquarters: ["US", "!DE"] },
  ])("rejects %j", (value) => {
    expect(parseGatewayPolicy(value).ok).toBe(false);
  });

  it("is a Standard Schema", () => {
    const result = gatewayPolicySchema["~standard"].validate({ region: "us" });

    expect(result).toEqual({ value: { region: "us" } });
  });
});

describe("applyGatewayPolicy", () => {
  it("forces the flags and region onto the options", () => {
    const applied = applyGatewayPolicy(
      {
        zeroDataRetention: true,
        disallowPromptTraining: true,
        promptCaching: true,
        region: "eu",
      },
      { tags: ["org:a"] },
    );

    expect(applied).toEqual(
      ok({
        tags: ["org:a"],
        zeroDataRetention: true,
        disallowPromptTraining: true,
        caching: "auto",
        inferenceRegion: { scope: "zone", geoRegion: "eu" },
      }),
    );
  });

  it("intersects the providers a call asked for", () => {
    const applied = applyGatewayPolicy(
      { allowedProviders: ["anthropic", "openai"] },
      { only: ["openai", "google"], order: ["google", "openai"] },
    );

    expect(applied).toEqual(ok({ only: ["openai"], order: ["openai"] }));
  });

  it("fails when no allowed provider is left", () => {
    const applied = applyGatewayPolicy(
      { allowedProviders: ["anthropic"] },
      { only: ["google"] },
    );

    expect(applied.ok).toBe(false);
  });

  it("never lets a call switch zero data retention off", () => {
    const applied = applyGatewayPolicy(
      { zeroDataRetention: true },
      { zeroDataRetention: false },
    );

    expect(applied.ok && applied.data.zeroDataRetention).toBe(true);
  });
});

describe("mergeGatewayPolicies", () => {
  it("is never looser than either side", () => {
    const merged = mergeGatewayPolicies(
      { zeroDataRetention: true, allowedProviders: ["anthropic", "openai"] },
      { allowedProviders: ["openai", "google"], promptCaching: true },
    );

    expect(merged).toEqual(
      ok({
        zeroDataRetention: true,
        allowedProviders: ["openai"],
        promptCaching: true,
      }),
    );
  });

  it("fails on an empty provider intersection", () => {
    expect(
      mergeGatewayPolicies(
        { allowedProviders: ["a"] },
        { allowedProviders: ["b"] },
      ).ok,
    ).toBe(false);
  });
});

describe("gatewayPolicyReader", () => {
  it("parses what the settings read returns", async () => {
    const read = gatewayPolicyReader(
      () => new AsyncResult(Promise.resolve(ok({ region: "jp" }))),
    );

    expect(await read("org")).toEqual(ok({ region: "jp" }));
  });

  it("fails on a stored value that is invalid", async () => {
    const read = gatewayPolicyReader(
      () => new AsyncResult(Promise.resolve(ok({ region: "mars" }))),
    );

    expect((await read("org")).ok).toBe(false);
  });
});

describe("governedGatewayOptions", () => {
  it("keeps the tenant tags and applies the policy", () => {
    const options = governedGatewayOptions(
      { userId: "u1", organizationId: "o1" },
      { zeroDataRetention: true },
    );

    expect(options.ok && options.data.gateway).toMatchObject({
      user: "u1",
      tags: expect.arrayContaining(["org:o1"]),
      zeroDataRetention: true,
    });
  });
});
