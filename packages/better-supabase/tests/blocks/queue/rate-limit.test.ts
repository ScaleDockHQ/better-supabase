import { describe, expect, it } from "vitest";

import { createRateLimit, rateLimited } from "../../../src/rate-limit/index.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";

describe("createRateLimit", () => {
  it("counts a hit against the scope's rule or a given limit", async () => {
    const fake = fakeSql([
      ["hit_rate_limit", [{ allowed: false, remaining: 0, retry_after: 42 }]],
    ]);

    const limit = createRateLimit({ sql: fake.sql });
    expect(
      await limit.check({ scope: "preview", key: "token-1" }).orThrow(),
    ).toEqual({ allowed: false, remaining: 0, retryAfter: 42 });
    await limit
      .check({ scope: "chat", key: "thread-1", rule: { max: 20, period: 60 } })
      .orThrow();
    await limit
      .check({
        scope: "chat",
        key: "thread-1",
        rule: { max: 5, period: "1 hour" },
      })
      .orThrow();
    expect(fake.calls.map((call) => call.values)).toEqual([
      ["preview", "token-1", null, null],
      ["chat", "thread-1", 20, "60 seconds"],
      ["chat", "thread-1", 5, "1 hour"],
    ]);
  });

  it("refuses a bad limit and reads a missing row as refused", async () => {
    const fake = fakeSql([]);
    const limit = createRateLimit({ sql: fake.sql });
    expect(
      await limit.check({ scope: "x", key: "k", rule: { max: 0, period: 1 } }),
    ).toMatchObject({ ok: false, error: { kind: "invalid_input" } });
    expect(fake.calls).toEqual([]);
    expect(await limit.check({ scope: "x", key: "k" }).orThrow()).toEqual({
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
      transport: {
        async call(schema, fn, args) {
          calls.push([schema, fn, { ...args }]);

          return { allowed: false, remaining: 0, retry_after: 7 };
        },
      },
    });

    expect(
      await limit.check({ scope: "preview", key: "token-1" }).orThrow(),
    ).toEqual({ allowed: false, remaining: 0, retryAfter: 7 });
    await limit
      .check({ scope: "chat", key: "t", rule: { max: 3, period: 60 } })
      .orThrow();
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
      transport: {
        call: () =>
          Promise.reject(
            Object.assign(new Error("No rate limit"), {
              code: "22023",
              hint: "RATE_LIMIT_UNKNOWN",
            }),
          ),
      },
    });

    expect(await failing.check({ scope: "x", key: "k" })).toMatchObject({
      ok: false,
      error: { hint: "RATE_LIMIT_UNKNOWN" },
    });
  });

  it("calls the functions in the schema it is given", async () => {
    const schemas: string[] = [];

    const limit = createRateLimit({
      transport: {
        async call(schema) {
          schemas.push(schema);

          return { allowed: true, remaining: 1, retry_after: 0 };
        },
      },
      schema: "api",
    });

    await limit.check({ scope: "preview", key: "token-1" }).orThrow();
    await limit.purge().orThrow();
    expect(schemas).toEqual(["api", "api"]);
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

describe("createRateLimit checkAll", () => {
  it("sends every limit in one call and reports the one that blocked", async () => {
    const fake = fakeSql([
      [
        "check_rate_limits",
        [
          {
            result: {
              allowed: false,
              blocked: 1,
              retry_after: 30,
              results: [
                { allowed: true, remaining: 4, retry_after: 0 },
                { allowed: false, remaining: 0, retry_after: 30 },
              ],
            },
          },
        ],
      ],
    ]);

    const limit = createRateLimit({ sql: fake.sql });

    expect(
      await limit
        .checkAll([
          { scope: "login:user", key: "user-1" },
          { scope: "login:ip", key: "1.2.3.4", rule: { max: 3, period: 60 } },
        ])
        .orThrow(),
    ).toEqual({
      allowed: false,
      remaining: 0,
      retryAfter: 30,
      blocked: { index: 1, scope: "login:ip", key: "1.2.3.4" },
      results: [
        { allowed: true, remaining: 4, retryAfter: 0 },
        { allowed: false, remaining: 0, retryAfter: 30 },
      ],
    });
    expect(fake.calls).toHaveLength(1);
    expect(JSON.parse(String(fake.calls[0]!.values[0]))).toEqual([
      { scope: "login:user", key: "user-1" },
      {
        scope: "login:ip",
        key: "1.2.3.4",
        max_requests: 3,
        period: "60 seconds",
      },
    ]);
  });

  it("answers allowed with the lowest remaining", async () => {
    const calls: [string, unknown][] = [];

    const limit = createRateLimit({
      transport: {
        async call(_schema, fn, args) {
          calls.push([fn, args["hits"]]);

          return {
            allowed: true,
            blocked: null,
            retry_after: 0,
            results: [
              { allowed: true, remaining: 9, retry_after: 0 },
              { allowed: true, remaining: 2, retry_after: 0 },
            ],
          };
        },
      },
    });

    expect(
      await limit
        .checkAll([
          { scope: "a", key: "k" },
          { scope: "b", key: "k" },
        ])
        .orThrow(),
    ).toMatchObject({ allowed: true, remaining: 2, retryAfter: 0 });
    expect(calls).toEqual([
      [
        "check_rate_limits",
        [
          { scope: "a", key: "k" },
          { scope: "b", key: "k" },
        ],
      ],
    ]);
  });

  it("refuses an empty list and a bad rule without a call", async () => {
    const fake = fakeSql([]);
    const limit = createRateLimit({ sql: fake.sql });

    expect(await limit.checkAll([])).toMatchObject({
      ok: false,
      error: { kind: "invalid_input" },
    });
    expect(
      await limit.checkAll([
        { scope: "a", key: "k", rule: { max: 0, period: 1 } },
      ]),
    ).toMatchObject({ ok: false, error: { kind: "invalid_input" } });
    expect(fake.calls).toEqual([]);
  });
});

describe("createRateLimit decoding", () => {
  const over = (answer: unknown) =>
    createRateLimit({
      transport: { call: async () => answer },
      logger: { error: () => undefined, warn: () => undefined } as never,
    });

  const two = [
    { scope: "a", key: "k1" },
    { scope: "b", key: "k2" },
  ];

  it("reads a missing answer as refused by the first limit", async () => {
    expect(await over(null).checkAll(two).orThrow()).toEqual({
      allowed: false,
      remaining: 0,
      retryAfter: 0,
      blocked: { index: 0, scope: "a", key: "k1" },
      results: [],
    });
  });

  it("refuses an allowed answer that lacks a result per limit", async () => {
    expect(
      await over({
        allowed: true,
        retry_after: "soon",
        results: [{ allowed: true, remaining: "x", retry_after: null }],
      })
        .checkAll(two)
        .orThrow(),
    ).toEqual({
      allowed: false,
      remaining: 0,
      retryAfter: 0,
      blocked: { index: 0, scope: "a", key: "k1" },
      results: [{ allowed: true, remaining: 0, retryAfter: 0 }],
    });
  });

  it("drops a blocked index outside the hits and reads bad rows as refusals", async () => {
    expect(
      await over({
        allowed: false,
        blocked: 7,
        retry_after: 12,
        results: ["bad", { allowed: false, remaining: 0, retry_after: 12 }],
      })
        .checkAll(two)
        .orThrow(),
    ).toEqual({
      allowed: false,
      remaining: 0,
      retryAfter: 12,
      results: [
        { allowed: false, remaining: 0, retryAfter: 0 },
        { allowed: false, remaining: 0, retryAfter: 12 },
      ],
    });
  });

  it("reads a missing single-check row over a transport as refused", async () => {
    expect(
      await over(undefined).check({ scope: "a", key: "k" }).orThrow(),
    ).toEqual({ allowed: false, remaining: 0, retryAfter: 0 });
    expect(
      await over({ allowed: true, remaining: null })
        .check({ scope: "a", key: "k" })
        .orThrow(),
    ).toEqual({ allowed: true, remaining: 0, retryAfter: 0 });
  });

  it("purges with the default batch and reads a missing count as zero", async () => {
    const seen: unknown[] = [];

    const limit = createRateLimit({
      transport: {
        async call(_schema, fn, args) {
          seen.push([fn, args["batch"]]);

          return null;
        },
      },
    });

    expect(await limit.purge().orThrow()).toBe(0);
    expect(seen).toEqual([["purge_rate_limits", undefined]]);
  });

  it("reads a missing SQL row as refused for checkAll", async () => {
    const limit = createRateLimit({ sql: fakeSql([]).sql });

    expect(
      await limit.checkAll([{ scope: "a", key: "k" }]).orThrow(),
    ).toMatchObject({ allowed: false, blocked: { index: 0 } });
  });
});
