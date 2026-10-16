import { describe, expect, it } from "vitest";

import {
  isRateLimitPolicyName,
  periodSeconds,
  rateLimitHeader,
  rateLimitPolicyHeader,
} from "../../src/core/ratelimit-headers.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("RateLimit header fields (draft-ietf-httpapi-ratelimit-headers)", () => {
  it("pins the draft revision", () => {
    expect(SPEC_PINS.ratelimitHeaders).toBe("draft-11");
  });

  it("serializes RateLimit-Policy as a List of Strings with q, qu and w", () => {
    expect(
      rateLimitPolicyHeader([
        { name: "api", quota: 100, window: 60 },
        { name: "bytes", quota: 1000, unit: "content-bytes", window: 3600 },
        { name: "default", quota: 5, unit: "requests" },
      ]),
    ).toBe(
      '"api";q=100;w=60, "bytes";q=1000;qu="content-bytes";w=3600, "default";q=5',
    );
  });

  it("serializes RateLimit with r and an optional t", () => {
    expect(
      rateLimitHeader([
        { policy: "api", remaining: 42 },
        { policy: "burst", remaining: 0, reset: 1.2 },
      ]),
    ).toBe('"api";r=42, "burst";r=0;t=2');
  });

  it("escapes quotes and backslashes in policy names", () => {
    expect(rateLimitHeader([{ policy: 'a"b\\c', remaining: 1 }])).toBe(
      '"a\\"b\\\\c";r=1',
    );
  });

  it("rejects names and numbers a Structured Field can't carry", () => {
    expect(isRateLimitPolicyName("")).toBe(false);
    expect(isRateLimitPolicyName("naïve")).toBe(false);
    expect(isRateLimitPolicyName("per user")).toBe(true);
    expect(() => rateLimitHeader([{ policy: "é", remaining: 1 }])).toThrow(
      TypeError,
    );
    expect(() => rateLimitHeader([{ policy: "a", remaining: -1 }])).toThrow(
      TypeError,
    );
    expect(() => rateLimitPolicyHeader([])).toThrow(TypeError);
    expect(() =>
      rateLimitPolicyHeader([{ name: "a", quota: 1, window: 0 }]),
    ).toThrow(TypeError);
    expect(() => rateLimitPolicyHeader([{ name: "a", quota: 1e16 }])).toThrow(
      TypeError,
    );
  });

  it("reads windows from seconds and simple intervals", () => {
    expect(periodSeconds(60)).toBe(60);
    expect(periodSeconds("1 minute")).toBe(60);
    expect(periodSeconds("30 seconds")).toBe(30);
    expect(periodSeconds("2 hours")).toBe(7200);
    expect(periodSeconds("1 day")).toBe(86_400);
    expect(periodSeconds("1 month")).toBeUndefined();
    expect(periodSeconds("01:00:00")).toBeUndefined();
    expect(periodSeconds(0)).toBeUndefined();
  });
});
