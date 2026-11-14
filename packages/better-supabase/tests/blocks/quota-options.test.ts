import { describe, expect, it } from "vitest";

import { BLOCK_OPTION_SCHEMAS } from "../../src/blocks/options-registry.ts";

/**
 * A block option that limits use is named `quota` (ADR 0909) and takes a
 * `BlockQuota`. A per-row `rateLimit` column (api-keys, webhooks) is data, not
 * a block option, so it isn't listed here.
 */
const LIMIT_WORDS = /quota|rate.?limit|throttle|plan.?limit/i;

describe("quota option names", () => {
  it("names every limiting block option `quota`", () => {
    const found = Object.entries(BLOCK_OPTION_SCHEMAS).flatMap(
      ([module, schema]) =>
        Object.keys(schema.specs)
          .filter((key) => LIMIT_WORDS.test(key))
          .map((key) => `${module}.${key}`),
    );

    expect(found).toEqual(["drive.quota"]);
  });
});
