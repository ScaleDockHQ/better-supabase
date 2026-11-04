import { describe, expect, it } from "vitest";

import { authResult } from "../../src/blocks/auth-reply.ts";

describe("authResult", () => {
  it("returns the data of a reply without an error", async () => {
    const result = await authResult(() =>
      Promise.resolve({ data: 7, error: null }),
    );

    expect(result.ok && result.data).toBe(7);
  });

  it("keeps the code and message of an Auth error", async () => {
    const result = await authResult(() =>
      Promise.resolve({
        data: null,
        error: { code: "user_banned", message: "Banned", status: 403 },
      }),
    );

    expect(!result.ok && result.error).toMatchObject({
      code: "user_banned",
      message: "Banned",
    });
  });

  it("maps an unreachable Auth server to a network error", async () => {
    const result = await authResult(() =>
      Promise.resolve({
        data: null,
        error: { name: "AuthRetryableFetchError", message: "down", status: 0 },
      }),
    );

    expect(!result.ok && result.error.kind).toBe("network");
  });

  it("maps a rate limit and an error without a message", async () => {
    const limited = await authResult(() =>
      Promise.resolve({ data: null, error: { status: 429, message: "slow" } }),
    );

    const bare = await authResult(() =>
      Promise.resolve({ data: null, error: {} }),
    );

    expect(!limited.ok && limited.error.kind).toBe("rate_limited");
    expect(!bare.ok && bare.error.message).toBe("Auth request failed");
  });

  it("turns a throw into a DbError", async () => {
    const result = await authResult(() => Promise.reject(new Error("boom")));

    expect(result.ok).toBe(false);
  });
});
