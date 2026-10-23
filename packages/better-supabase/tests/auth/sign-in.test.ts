import { describe, expect, it, vi } from "vitest";

import {
  needsMfa,
  passwordGrant,
  safeRedirectPath,
} from "../../src/auth/sign-in.ts";

const options = { url: "https://a.test", publishableKey: "pk" };

describe("safeRedirectPath", () => {
  it.each([
    ["/dashboard?tab=1", "/dashboard?tab=1"],
    ["//evil.test", "/"],
    ["/\\evil.test", "/"],
    ["https://evil.test", "/"],
    ["/\tjavascript:alert(1)", "/"],
    ["", "/"],
    [null, "/"],
    [undefined, "/"],
  ])("maps %j to %j", (next, expected) => {
    expect(safeRedirectPath(next, "/")).toBe(expected);
  });
});

describe("passwordGrant", () => {
  it("returns the session with an expiry", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json({
        access_token: "a",
        refresh_token: "r",
        expires_in: 3600,
      }),
    );

    const granted = await passwordGrant(
      { email: "a@b.test", password: "pw" },
      { ...options, fetch, now: () => 1_000_000 },
    );

    expect(granted).toMatchObject({
      ok: true,
      data: { access_token: "a", refresh_token: "r", expires_at: 4600 },
    });
    expect(String(fetch.mock.calls[0]?.[0])).toBe(
      "https://a.test/auth/v1/token?grant_type=password",
    );
  });

  it("returns invalid credentials as unauthorized with the Auth code", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json(
        { error_code: "invalid_credentials", msg: "Invalid login credentials" },
        { status: 400 },
      ),
    );

    const granted = await passwordGrant(
      { email: "a@b.test", password: "wrong" },
      { ...options, fetch },
    );

    expect(granted).toMatchObject({
      ok: false,
      error: { kind: "unauthorized", code: "invalid_credentials" },
    });
  });

  it("maps 429 to rate_limited and a thrown fetch to network", async () => {
    const limited = await passwordGrant(
      { email: "a@b.test", password: "pw" },
      {
        ...options,
        fetch: async () => Response.json({ msg: "slow" }, { status: 429 }),
      },
    );

    expect(limited).toMatchObject({ error: { kind: "rate_limited" } });

    const down = await passwordGrant(
      { email: "a@b.test", password: "pw" },
      { ...options, fetch: () => Promise.reject(new Error("offline")) },
    );

    expect(down).toMatchObject({ error: { kind: "network" } });
  });

  it("forwards the client IP with the secret key", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json({ access_token: "a", refresh_token: "r" }),
    );

    await passwordGrant(
      { email: "a@b.test", password: "pw" },
      { ...options, fetch, forwardedFor: { ip: "1.2.3.4", secretKey: "sk" } },
    );

    expect(fetch.mock.calls[0]?.[1]?.headers).toMatchObject({
      apikey: "sk",
      "sb-forwarded-for": "1.2.3.4",
    });
  });
});

describe("needsMfa", () => {
  it("is true only with a verified factor", () => {
    const session = (factors: unknown) => ({
      access_token: "a",
      refresh_token: "r",
      user: { id: "u", factors },
    });

    expect(needsMfa(session([{ status: "verified" }]))).toBe(true);
    expect(needsMfa(session([{ status: "unverified" }]))).toBe(false);
    expect(needsMfa(session(undefined))).toBe(false);
    expect(needsMfa({ access_token: "a", refresh_token: "r" })).toBe(false);
  });
});
