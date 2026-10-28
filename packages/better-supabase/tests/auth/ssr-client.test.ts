import { afterEach, describe, expect, it, vi } from "vitest";

import {
  clearCookieSession,
  clearRefreshes,
  NO_STORE,
  refreshCookieSession,
} from "../../src/auth/ssr-client.ts";

const base64url = (value: unknown) =>
  btoa(JSON.stringify(value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/, "");

const jwt = (sub: string) =>
  `${base64url({ alg: "HS256", typ: "JWT" })}.${base64url({
    sub,
    exp: Math.floor(Date.now() / 1000) + 3600,
  })}.sig`;

const answer = (token: string) =>
  Response.json({
    access_token: jwt(token),
    refresh_token: `r-${token}`,
    expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    token_type: "bearer",
    user: { id: token, aud: "authenticated" },
  });

const refresh = (
  refreshToken: string,
  fetch: typeof globalThis.fetch,
  extra: Partial<Parameters<typeof refreshCookieSession>[0]> = {},
) =>
  refreshCookieSession({
    url: "https://auth.test",
    publishableKey: "pk",
    cookieName: "sb-auth-auth-token",
    cookies: [],
    refreshToken,
    fetch,
    ...extra,
  });

const tokenCalls = (fetch: ReturnType<typeof vi.fn>) =>
  fetch.mock.calls.filter(([input]) =>
    String(input).includes("grant_type=refresh_token"),
  ).length;

afterEach(() => {
  clearRefreshes();
});

describe("refreshCookieSession", () => {
  it("sends one token request for ten parallel refreshes of one token", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () => {
      await new Promise((resolve) => {
        setTimeout(resolve, 10);
      });

      return answer("u1");
    });

    const results = await Promise.all(
      Array.from({ length: 10 }, () => refresh("same", fetch)),
    );

    expect(tokenCalls(fetch)).toBe(1);
    expect(results.every((result) => result.outcome.ok)).toBe(true);
    expect(
      results.filter((result) => result.outcome.ok && result.outcome.shared),
    ).toHaveLength(9);
    expect(results[0]!.writes.length).toBeGreaterThan(0);
    expect(results[0]!.headers["cache-control"]).toContain("no-store");
  });

  it("answers a repeat of the token from the shared response", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () => answer("u2"));

    await refresh("repeat", fetch);
    const again = await refresh("repeat", fetch);

    expect(again.outcome).toMatchObject({ ok: true, shared: true });
    expect(tokenCalls(fetch)).toBe(1);
  });

  it("reports a 5xx as an outage without retrying", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(
      async () => new Response("down", { status: 503 }),
    );

    const result = await refresh("down", fetch);

    expect(result.outcome).toEqual({
      ok: false,
      reason: "network",
      cause: "status",
      status: 503,
    });
    expect(tokenCalls(fetch)).toBe(1);
  });

  it("reports a thrown fetch as an outage and doesn't cache it", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () => {
      throw new TypeError("fetch failed");
    });

    expect((await refresh("offline", fetch)).outcome).toMatchObject({
      reason: "network",
      cause: "network",
    });
    await refresh("offline", fetch);
    expect(tokenCalls(fetch)).toBe(2);
  });

  it("reads a used refresh token as raced and a banned user as rejected", async () => {
    const used = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json(
        { code: 400, error_code: "refresh_token_already_used", msg: "used" },
        { status: 400 },
      ),
    );

    const banned = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json(
        { code: 403, error_code: "user_banned", msg: "banned" },
        { status: 403 },
      ),
    );

    expect((await refresh("used", used)).outcome).toMatchObject({
      ok: false,
      reason: "raced",
      code: "refresh_token_already_used",
    });
    expect((await refresh("banned", banned)).outcome).toMatchObject({
      ok: false,
      reason: "rejected",
      status: 403,
      code: "user_banned",
    });
  });

  it("sends the secret key and the client IP when forwarding", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () => answer("u3"));

    await refresh("forwarded", fetch, {
      forwardedFor: { ip: "203.0.113.7", secretKey: "sk" },
    });

    const [, init] = fetch.mock.calls.find(([input]) =>
      String(input).includes("grant_type=refresh_token"),
    )!;

    const headers = new Headers(init?.headers);

    expect(headers.get("apikey")).toBe("sk");
    expect(headers.get("sb-forwarded-for")).toBe("203.0.113.7");
    expect(headers.has("authorization")).toBe(false);
  });
});

describe("clearCookieSession", () => {
  it("clears the cookie and its chunks with no-store headers", async () => {
    const cleared = await clearCookieSession({
      cookieName: "sb-auth-auth-token",
      cookies: [
        { name: "sb-auth-auth-token.0", value: "a" },
        { name: "sb-auth-auth-token.1", value: "b" },
        { name: "other", value: "c" },
      ],
    });

    expect(cleared.writes.map((write) => write.name).toSorted()).toEqual([
      "sb-auth-auth-token.0",
      "sb-auth-auth-token.1",
    ]);
    expect(cleared.writes.every((write) => write.options.maxAge === 0)).toBe(
      true,
    );
    expect(cleared.headers).toEqual(NO_STORE);
  });

  it("writes nothing when there is no session cookie", async () => {
    expect(
      await clearCookieSession({
        cookieName: "sb-auth-auth-token",
        cookies: [{ name: "other", value: "c" }],
      }),
    ).toEqual({ writes: [], headers: {} });
  });
});
