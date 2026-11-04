import { describe, expect, it } from "vitest";

import { fillTopic } from "../../src/blocks/block-config.ts";

describe("fillTopic", () => {
  it("fills every placeholder", () => {
    expect(fillTopic("user:{userId}:{kind}", { userId: "u1", kind: "k" })).toBe(
      "user:u1:k",
    );
  });

  it("names the missing value", () => {
    expect(() => fillTopic("user:{userId}", {})).toThrow(
      'fillTopic: no value for {userId} in "user:{userId}"',
    );
  });
});
