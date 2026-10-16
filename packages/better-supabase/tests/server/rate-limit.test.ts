import { describe, expect, it, vi } from "vitest";

import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import {
  type RateLimiter,
  rateLimitGate,
} from "../../src/server/rate-limit.ts";

function limiter(remaining: number[]): RateLimiter {
  return {
    check: vi.fn(async () => {
      const left = remaining.shift() ?? -1;
      return ok(
        left >= 0
          ? { allowed: true, remaining: left, retryAfter: 0 }
          : { allowed: false, remaining: 0, retryAfter: 12.5 },
      );
    }),
  };
}

describe("rateLimitGate", () => {
  it("adds RateLimit, and RateLimit-Policy for a route rule", async () => {
    const gate = rateLimitGate<string>({
      limiter: limiter([4]),
      scope: "api",
      key: (key) => key,
      rule: { max: 5, period: "1 minute" },
    });
    const outcome = await gate("k");
    expect(outcome.kind).toBe("allow");
    if (outcome.kind !== "allow") return;
    expect(outcome.headers.get("ratelimit")).toBe('"api";r=4');
    expect(outcome.headers.get("ratelimit-policy")).toBe('"api";q=5;w=60');
  });

  it("refuses with rate_limited, Retry-After and t", async () => {
    const gate = rateLimitGate<string>({
      limiter: limiter([]),
      scope: "api",
      policy: "per-key",
      key: (key) => key,
    });
    const outcome = await gate("k");
    expect(outcome.kind).toBe("deny");
    if (outcome.kind !== "deny") return;
    expect(outcome.error).toMatchObject({
      kind: "rate_limited",
      retryAfter: 13,
    });
    expect(outcome.headers.get("retry-after")).toBe("13");
    expect(outcome.headers.get("ratelimit")).toBe('"per-key";r=0;t=13');
    expect(outcome.headers.has("ratelimit-policy")).toBe(false);
  });

  it("skips without a key, and on limiter errors when failing open", async () => {
    const failing: RateLimiter = {
      check: async () => err(dbError("network", "Down")),
    };
    const skip = rateLimitGate<string | undefined>({
      limiter: failing,
      scope: "api",
      key: (key) => key,
      failOpen: true,
    });
    expect((await skip(undefined)).kind).toBe("skip");
    expect((await skip("k")).kind).toBe("skip");
    const strict = rateLimitGate<string>({
      limiter: failing,
      scope: "api",
      key: (key) => key,
    });
    const outcome = await strict("k");
    expect(outcome.kind === "deny" && outcome.error.kind).toBe("network");
  });

  it("rejects a scope that can't name a policy", () => {
    expect(() =>
      rateLimitGate({ limiter: limiter([]), scope: "é", key: () => "k" }),
    ).toThrow(TypeError);
  });
});
