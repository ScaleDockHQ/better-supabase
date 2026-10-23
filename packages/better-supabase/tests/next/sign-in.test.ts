import { beforeEach, describe, expect, it, vi } from "vitest";

import { readSession } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ jar: new Map<string, string>() }));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(new Headers()),
  cookies: () =>
    Promise.resolve({
      getAll: () => [...mocks.jar].map(([name, value]) => ({ name, value })),
      set: (name: string, value: string) => {
        mocks.jar.set(name, value);
      },
    }),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: () => undefined,
  revalidateTag: () => undefined,
  cacheTag: () => undefined,
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

describe("signIn", () => {
  beforeEach(() => {
    mocks.jar.clear();
  });

  it("writes the session, stores it for the render and checks next", async () => {
    const token = await signer.sign({ sub: USER });

    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json({
        access_token: token,
        refresh_token: "r1",
        expires_in: 3600,
        user: { id: USER, factors: [] },
      }),
    );

    const bsb = createNext(defineSupabase(schema), {
      env,
      auth: { jwks: signer.jwks, fetch },
    });

    const signed = await bsb.signIn(
      { email: "a@b.test", password: "pw", next: "//evil.test" },
      { fallback: "/en" },
    );

    expect(signed).toEqual({
      ok: true,
      data: { redirectTo: "/en", mfa: false },
      error: null,
    });
    expect(fetch).toHaveBeenCalledOnce();

    const cookies = [...mocks.jar].map(([name, value]) => ({ name, value }));
    expect(readSession(cookies, NAME)?.access_token).toBe(token);

    const before = bsb.sessions.stats();

    const snapshot = await bsb.snapshot(
      new Request("https://app.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );

    expect(snapshot?.userId).toBe(USER);
    expect(bsb.sessions.stats().misses).toBe(before.misses);
    expect(bsb.sessions.stats().hits).toBe(before.hits + 1);
  });

  it("returns the Auth error and writes nothing", async () => {
    const bsb = createNext(defineSupabase(schema), {
      env,
      auth: {
        jwks: signer.jwks,
        fetch: async () =>
          Response.json(
            { error_code: "invalid_credentials", msg: "Invalid" },
            { status: 400 },
          ),
      },
    });

    const signed = await bsb.signIn({ email: "a@b.test", password: "no" });

    expect(signed).toMatchObject({
      ok: false,
      error: { kind: "unauthorized", code: "invalid_credentials" },
    });
    expect(mocks.jar.size).toBe(0);
  });
});
