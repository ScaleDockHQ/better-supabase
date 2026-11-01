import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/resolve.ts";

const seedOf = (seed?: Parameters<typeof resolveConfig>[0]["seed"]) =>
  resolveConfig(seed === undefined ? {} : { seed }, "/app").seed;

describe("seed.defaults and seed.sample", () => {
  it("seeds new organizations in English and samples at size m by default", () => {
    const seed = seedOf();

    expect(seed.defaults).toEqual({
      enabled: true,
      onCreate: true,
      locale: "en",
      variants: {},
    });

    expect(seed.sample).toMatchObject({ size: "m", seed: 1, locale: "en" });
  });

  it("turns defaults off with false", () => {
    expect(seedOf({ defaults: false }).defaults.enabled).toBe(false);
  });

  it("takes the defaults' locale as the sample locale", () => {
    const seed = seedOf({
      defaults: { locale: "nl", variants: { pipelines: "b2b-sales" } },
      sample: { size: "l", seed: 42 },
    });

    expect(seed.defaults.variants).toEqual({ pipelines: "b2b-sales" });
    expect(seed.sample).toMatchObject({ size: "l", seed: 42, locale: "nl" });
  });
});
