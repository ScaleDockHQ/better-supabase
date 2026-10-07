import { describe, expect, it } from "vitest";

import {
  createRateLimit,
  rateLimited,
} from "../../../src/blocks/jobs/index.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";

describe("createRateLimit", () => {
  it("counts a hit against the scope's rule or a given limit", async () => {
    const fake = fakeSql([
      ["hit_rate_limit", [{ allowed: false, remaining: 0, retry_after: 42 }]],
    ]);
    const limit = createRateLimit(fake.sql);
    expect(await limit.check("preview", "token-1").orThrow()).toEqual({
      allowed: false,
      remaining: 0,
      retryAfter: 42,
    });
    await limit.check("chat", "thread-1", { max: 20, period: 60 }).orThrow();
    await limit
      .check("chat", "thread-1", { max: 5, period: "1 hour" })
      .orThrow();
    expect(fake.calls.map((call) => call.values)).toEqual([
      ["preview", "token-1", null, null],
      ["chat", "thread-1", 20, "60 seconds"],
      ["chat", "thread-1", 5, "1 hour"],
    ]);
  });

  it("refuses a bad limit and reads a missing row as refused", async () => {
    const fake = fakeSql([]);
    const limit = createRateLimit(fake.sql);
    expect(await limit.check("x", "k", { max: 0, period: 1 })).toMatchObject({
      ok: false,
      error: { kind: "invalid_input" },
    });
    expect(fake.calls).toEqual([]);
    expect(await limit.check("x", "k").orThrow()).toEqual({
      allowed: false,
      remaining: 0,
      retryAfter: 0,
    });
  });
});

describe("createRateLimit over a BlockTransport", () => {
  it("calls check_rate_limit and maps its row", async () => {
    const calls: [string, string, Record<string, unknown>][] = [];
    const limit = createRateLimit({
      async call(schema, fn, args) {
        calls.push([schema, fn, { ...args }]);
        return { allowed: false, remaining: 0, retry_after: 7 };
      },
    });
    expect(await limit.check("preview", "token-1").orThrow()).toEqual({
      allowed: false,
      remaining: 0,
      retryAfter: 7,
    });
    await limit.check("chat", "t", { max: 3, period: 60 }).orThrow();
    expect(calls).toEqual([
      [
        "better_supabase",
        "check_rate_limit",
        {
          scope: "preview",
          key: "token-1",
          max_requests: undefined,
          period: undefined,
        },
      ],
      [
        "better_supabase",
        "check_rate_limit",
        { scope: "chat", key: "t", max_requests: 3, period: "60 seconds" },
      ],
    ]);
    const failing = createRateLimit({
      call: () =>
        Promise.reject(
          Object.assign(new Error("No rate limit"), {
            code: "22023",
            hint: "RATE_LIMIT_UNKNOWN",
          }),
        ),
    });
    expect(await failing.check("x", "k")).toMatchObject({
      ok: false,
      error: { hint: "RATE_LIMIT_UNKNOWN" },
    });
  });
});

describe("rateLimited", () => {
  it("answers 429 problem+json with Retry-After", async () => {
    const response = rateLimited({ retryAfter: 2.2 }, { instance: "/api/x" });
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("3");
    expect(response.headers.get("content-type")).toBe(
      "application/problem+json",
    );
    expect(await response.json()).toMatchObject({
      status: 429,
      instance: "/api/x",
      detail: "Too many requests. Retry after 3 seconds.",
    });
    expect(
      (await rateLimited({ retryAfter: 0 }, { detail: "Slow down" }).json())
        .detail,
    ).toBe("Slow down");
    expect(
      await rateLimited(
        { retryAfter: 1 },
        {
          problem: (problem) => ({
            code: "RATE_LIMITED",
            status: problem.status,
          }),
        },
      ).json(),
    ).toEqual({ code: "RATE_LIMITED", status: 429 });
  });
});
