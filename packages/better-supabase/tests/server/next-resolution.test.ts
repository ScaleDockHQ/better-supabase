import { describe, expect, it, vi } from "vitest";

import type * as AuthResolve from "../../src/auth/resolve.ts";

import { createSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers(), resolutions: 0 }));

vi.mock(import("../../src/auth/resolve.ts"), async (original) => {
  const actual = await original<typeof AuthResolve>();

  return {
    ...actual,
    resolveAuth: (...args: Parameters<typeof actual.resolveAuth>) => {
      mocks.resolutions += 1;

      return actual.resolveAuth(...args);
    },
  };
});

vi.mock(import("next/headers.js"), () => ({
  // SAFETY: the resolver reads only getAll() from the cookie store.
  cookies: () => Promise.resolve({ getAll: () => [] } as never),
  headers: () => Promise.resolve(mocks.headers),
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: vi.fn(),
  cacheTag: vi.fn(),
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

describe("one resolution per request", () => {
  it("resolves once for each read of context and claims", async () => {
    const bsb = createNext(createSupabase(schema), {
      env: {
        url: PROJECT_URL,
        publishableKey: "sb_publishable_test",
        jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      },
      cacheTags: false,
      auth: { jwks: signer.jwks },
    });

    const token = await signer.sign({ sub: USER });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });

    const ctx = await bsb.context();

    expect(ctx.auth.kind).toBe("user");
    expect(mocks.resolutions).toBe(1);

    mocks.resolutions = 0;
    const session = await bsb.claims();

    expect(session.kind).toBe("user");
    expect(mocks.resolutions).toBe(1);
  });
});
