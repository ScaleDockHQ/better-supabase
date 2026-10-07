import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/profiles/index.ts";

import { createProfiles } from "../../../src/blocks/profiles/index.ts";

function fake(results: Record<string, unknown>): BlockTransport {
  return {
    call(_schema, fn) {
      const value = results[fn];
      return value instanceof Error
        ? Promise.reject(value)
        : Promise.resolve(value ?? null);
    },
  };
}

describe("createProfiles", () => {
  it("reads and updates the caller's profile", async () => {
    const profiles = createProfiles({
      transport: fake({
        my_profile: { full_name: "Ada", email: "ada@example.com" },
        update_my_profile: true,
      }),
    });
    expect(await profiles.mine().orThrow()).toEqual({
      full_name: "Ada",
      email: "ada@example.com",
    });
    expect(
      await profiles.updateMine({ full_name: "Ada Lovelace" }).orThrow(),
    ).toBe(true);
  });
});
