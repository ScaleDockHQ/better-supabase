import { describe, expect, it } from "vitest";

import { mapDbError } from "../../src/core/errors.ts";
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
