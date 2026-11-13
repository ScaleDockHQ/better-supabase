import { createBrowserClient, createServerClient } from "@supabase/ssr";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ssrSession } from "../../src/auth/session.ts";
import { createSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ jar: new Map<string, string>() }));

vi.mock(import("react"), async (original) => ({
  ...(await original()),
  // SAFETY: the flows only call cache as a pass-through wrapper.
  cache: (<T>(fn: T) => fn) as never,
}));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(new Headers()),
  cookies: () =>
    Promise.resolve(
      // SAFETY: the auth flows read only getAll and set from the cookie jar.
      {
        getAll: () => [...mocks.jar].map(([name, value]) => ({ name, value })),
        set: (name: string, value: string, options: { maxAge?: number }) => {
          if (options.maxAge === 0) {
            mocks.jar.delete(name);
          } else {
            mocks.jar.set(name, value);
          }
        },
      } as never,
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
const PUBLISHABLE_KEY = "sb_publishable_test";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

function jarCookies(): { name: string; value: string }[] {
  return [...mocks.jar].map(([name, value]) => ({ name, value }));
}

const readOnly = { getAll: jarCookies, setAll: () => undefined };

async function signIn(metadata: Record<string, unknown>): Promise<string> {
  const token = await signer.sign({ sub: USER });

  const fetch = vi.fn<typeof globalThis.fetch>(async () =>
    Response.json({
      access_token: token,
      refresh_token: "r1",
      expires_in: 3600,
      user: { id: USER, factors: [], user_metadata: metadata },
    }),
  );

  const betterSupabase = createSupabase(schema);

  const env = {
    url: PROJECT_URL,
    publishableKey: PUBLISHABLE_KEY,
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  };

  const options = { env, auth: { jwks: signer.jwks, fetch } };

  const bsb = createNext(betterSupabase, {
    ...options,
    server: createServer(betterSupabase, options),
    tenant: () => "org-1",
  });

  const signed = await bsb.signInWithPassword({
    email: "a@b.test",
    password: "pw",
  });

  expect(signed.ok).toBe(true);

  return token;
}

describe("session cookies written by the sign-in flows", () => {
  beforeEach(() => {
    mocks.jar.clear();
  });

  it.each([
    ["one cookie", {}, [NAME]],
    [
      "chunked cookies",
      { bio: "x".repeat(8000) },
      [0, 1, 2, 3].map((i) => `${NAME}.${i}`),
    ],
  ])(
    "read back through @supabase/ssr as %s",
    async (_label, metadata, names) => {
      const token = await signIn(metadata);

      expect([...mocks.jar.keys()]).toEqual(names);

      const server = createServerClient(PROJECT_URL, PUBLISHABLE_KEY, {
        cookies: readOnly,
      });

      const browser = createBrowserClient(PROJECT_URL, PUBLISHABLE_KEY, {
        cookies: readOnly,
        isSingleton: false,
      });

      const fromServer = await server.auth.getSession();
      const fromBrowser = await browser.auth.getSession();

      expect(fromServer.data.session?.access_token).toBe(token);
      expect(fromBrowser.data.session?.access_token).toBe(token);
      expect(fromBrowser.data.session?.user.user_metadata).toEqual(metadata);
      expect((await ssrSession(jarCookies(), NAME))?.access_token).toBe(token);
    },
  );
});
