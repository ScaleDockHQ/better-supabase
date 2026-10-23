import { NextRequest } from "next/server.js";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { writeSession } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(mocks.headers),
  cookies: () =>
    Promise.resolve(
      // SAFETY: the proxy and getRequestSession only await the cookie jar.
      { set: () => undefined, getAll: () => [] } as never,
    ),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: () => undefined,
  revalidateTag: () => undefined,
  cacheTag: () => undefined,
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const signer = await createTestSigner();
const auth = vi.fn<typeof fetch>();

const bsb = createNext(defineSupabase(schema), {
  env,
  auth: { jwks: signer.jwks, fetch: auth },
  prefetchJwks: false,
});

/** A session cookie whose token expires in `seconds`. */
async function expiring(seconds: number, refresh = "r-1"): Promise<string> {
  const token = await signer.sign({ sub: USER, expiresIn: seconds });

  return writeSession([], NAME, {
    access_token: token,
    refresh_token: refresh,
    expires_at: Math.floor(Date.now() / 1000) + seconds,
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");
}

function page(cookie: string, headers: Record<string, string> = {}) {
  return new NextRequest("https://app.test/dashboard", {
    headers: { "sec-fetch-dest": "document", cookie, ...headers },
  });
}

const renewed = async () =>
  Response.json({
    access_token: await signer.sign({ sub: USER }),
    refresh_token: "r-next",
    expires_in: 3600,
  });

/** Runs the proxy and returns the response with the auth it resolved. */
async function run(
  request: NextRequest,
  options: Parameters<typeof bsb.proxy>[1] = {},
) {
  let seen: AuthState | undefined;

  const response = await bsb.proxy(request, {
    ...options,
    after: (_response, state) => {
      seen = state;
    },
  });

  return { response, auth: seen };
}

beforeEach(() => {
  auth.mockReset();
  auth.mockImplementation(renewed);
});

describe("proxy fast path", () => {
  it.each([
    { "next-router-prefetch": "1" },
    { "next-router-segment-prefetch": "/_tree" },
    { "x-middleware-prefetch": "1" },
    { purpose: "prefetch" },
    { "sec-purpose": "prefetch;prerender" },
  ])("never calls Auth for a prefetch with %o", async (headers) => {
    await run(page(await expiring(20), headers));
    expect(auth).not.toHaveBeenCalled();
  });

  it("refreshes the same expiring cookie on a page load", async () => {
    const { response } = await run(page(await expiring(20, "r-page")));

    expect(auth).toHaveBeenCalledOnce();
    expect(response.headers.getSetCookie().join("\n")).toContain(NAME);
  });

  it("verifies locally outside the refresh skew and refreshes inside it", async () => {
    const cookie = await expiring(30, "r-skew");
    const outside = await run(page(cookie), { refreshSkewSeconds: 10 });

    expect(auth).not.toHaveBeenCalled();
    expect(outside.auth).toMatchObject({ kind: "user" });

    await run(page(cookie), { refreshSkewSeconds: 60 });
    expect(auth).toHaveBeenCalledOnce();
  });

  it("keeps the session when another request already rotated the token", async () => {
    auth.mockImplementation(async () =>
      Response.json(
        { code: 400, error_code: "refresh_token_already_used" },
        { status: 400 },
      ),
    );

    const { response, auth: state } = await run(
      page(await expiring(20, "r-raced")),
    );

    expect(auth).toHaveBeenCalledOnce();
    expect(state).toMatchObject({ kind: "user", user: { id: USER } });
    expect(
      response.headers
        .getSetCookie()
        .some((value) => value.includes("Max-Age=0")),
    ).toBe(false);
  });

  it("checks for an ended session on document loads only", async () => {
    auth.mockImplementation(async () => Response.json({ id: USER }));
    const cookie = await expiring(3600);

    await run(page(cookie, { "sec-fetch-dest": "empty", rsc: "1" }), {
      endedSession: true,
    });
    await run(page(cookie, { "next-router-prefetch": "1" }), {
      endedSession: true,
    });
    expect(auth).not.toHaveBeenCalled();

    await run(page(cookie), { endedSession: true });
    expect(auth).toHaveBeenCalledOnce();
  });

  it("reports each phase that ran in Server-Timing", async () => {
    const { response } = await run(page(await expiring(20, "r-timing")), {
      serverTiming: true,
    });

    const names = (response.headers.get("server-timing") ?? "")
      .split(", ")
      .map((entry) => entry.split(";")[0]);

    expect(names).toEqual(
      expect.arrayContaining([
        "bsb-proxy",
        "bsb-auth",
        "bsb-parse",
        "bsb-refresh",
        "bsb-verify",
      ]),
    );
    expect(names).not.toContain("bsb-ended");
  });
});

describe("session memo", () => {
  it("seeds the memo with a refreshed token, so the render never verifies it", async () => {
    let issued = "";
    auth.mockImplementation(async () => {
      issued = await signer.sign({ sub: USER });

      return Response.json({
        access_token: issued,
        refresh_token: "r-next",
        expires_in: 3600,
      });
    });

    await run(page(await expiring(20, "r-seed")));

    const { hits, misses } = bsb.sessions.stats();

    const snapshot = await bsb.snapshot(
      new Request("https://app.test/", {
        headers: { authorization: `Bearer ${issued}` },
      }),
    );

    expect(snapshot).toMatchObject({ userId: USER });
    expect(bsb.sessions.stats()).toMatchObject({ hits: hits + 1, misses });
  });

  it("evicts a user's sessions on invalidateSession", async () => {
    const token = await signer.sign({ sub: USER });

    const request = new Request("https://app.test/", {
      headers: { authorization: `Bearer ${token}` },
    });

    await bsb.snapshot(request);
    bsb.invalidateSession(USER);
    await vi.waitFor(() => {
      expect(bsb.sessions.stats().size).toBe(0);
    });

    const { misses } = bsb.sessions.stats();
    await bsb.snapshot(request);
    expect(bsb.sessions.stats().misses).toBe(misses + 1);
  });

  it("getRequestSession verifies a request's token once across scopes", async () => {
    const token = await signer.sign({ sub: USER });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });
    const { misses } = bsb.sessions.stats();

    const [first, second] = await Promise.all([
      bsb.getRequestSession(),
      bsb.getRequestSession(),
    ]);

    expect(first).toMatchObject({ userId: USER });
    expect(second).toMatchObject({ userId: USER });
    expect(bsb.sessions.stats().misses).toBe(misses + 1);
    mocks.headers = new Headers();
  });
});
