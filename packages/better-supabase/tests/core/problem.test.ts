import { describe, expect, it } from "vitest";

import { dbError, mapDbError, withMaxAffected } from "../../src/core/errors.ts";
import {
  fromProblem,
  problemResponse,
  toProblem,
} from "../../src/core/problem.ts";

describe("rate_limited", () => {
  const error = mapDbError({
    code: "BS429",
    message: "Rate limit for * exceeded: 5 writes per 00:01:00",
    details: "Retry after 12 seconds.",
  });

  it("maps BS429 and PT429 with the seconds to wait", () => {
    expect(error).toMatchObject({
      kind: "rate_limited",
      status: 429,
      retryAfter: 12,
    });
    expect(mapDbError({ code: "PT429", message: "slow down" })).toEqual({
      kind: "rate_limited",
      status: 429,
      code: "PT429",
      message: "slow down",
    });
  });

  it("sends Retry-After and round-trips through Problem Details", async () => {
    const response = problemResponse(error);
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("12");
    const problem = toProblem(error);
    expect(problem).toMatchObject({
      type: "https://bettersupabase.com/problems/rate-limited",
      title: "Too many requests",
      retryAfter: 12,
    });
    expect(fromProblem(await response.json())).toMatchObject({
      kind: "rate_limited",
      retryAfter: 12,
    });
  });
});

describe("quota_exceeded", () => {
  const error = mapDbError({
    code: "BSQ29",
    message: "Quota for api_calls exceeded",
    details: '{"meter":"api_calls","limit":1000,"retry_after":3600}',
    hint: "QUOTA_EXCEEDED",
  });

  it("maps BSQ29 with the meter, limit and seconds to wait", () => {
    expect(error).toMatchObject({
      kind: "quota_exceeded",
      status: 429,
      meter: "api_calls",
      limit: 1000,
      retryAfter: 3600,
    });
    expect(mapDbError({ code: "BSQ29", message: "over" })).toEqual({
      kind: "quota_exceeded",
      status: 429,
      code: "BSQ29",
      message: "over",
    });
    for (const details of ["not json", "null", '{"limit":"x"}']) {
      expect(mapDbError({ code: "BSQ29", message: "over", details })).toEqual({
        kind: "quota_exceeded",
        status: 429,
        code: "BSQ29",
        message: "over",
        details,
      });
    }
  });

  it("sends Retry-After and round-trips through Problem Details", async () => {
    const response = problemResponse(error);
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("3600");
    expect(toProblem(error)).toMatchObject({
      type: "https://bettersupabase.com/problems/quota-exceeded",
      title: "Quota exceeded",
      meter: "api_calls",
      limit: 1000,
    });
    expect(fromProblem(await response.json())).toMatchObject({
      kind: "quota_exceeded",
      meter: "api_calls",
      limit: 1000,
      retryAfter: 3600,
    });
  });
});

describe("max_affected", () => {
  const error = dbError("max_affected", "too many rows", { maxAffected: 5 });

  it("answers 400 and round-trips the limit through Problem Details", async () => {
    const response = problemResponse(error);
    expect(response.status).toBe(400);
    expect(toProblem(error)).toMatchObject({
      type: "https://bettersupabase.com/problems/max-affected",
      title: "Too many rows affected",
      kind: "max_affected",
      maxAffected: 5,
    });
    expect(fromProblem(await response.json())).toEqual(error);
  });

  it("adds the operation's limit only when the error lacks one", () => {
    const bare = dbError("max_affected", "too many rows");
    expect(withMaxAffected(bare, 3)).toEqual({ ...bare, maxAffected: 3 });
    expect(withMaxAffected(error, 3)).toBe(error);
    expect(withMaxAffected(bare, undefined)).toBe(bare);
    const other = dbError("timeout", "slow");
    expect(withMaxAffected(other, 3)).toBe(other);
  });
});

describe("problemResponse format", () => {
  it("rewrites the body and keeps the status and headers", async () => {
    const response = problemResponse(
      dbError("rate_limited", "Slow down", { retryAfter: 3 }),
      {
        instance: "/api/x",
        format: (problem) => ({ error: problem.kind, at: problem.instance }),
      },
    );
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("3");
    expect(await response.json()).toEqual({
      error: "rate_limited",
      at: "/api/x",
    });
  });
});
