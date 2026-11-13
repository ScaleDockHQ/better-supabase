import { afterEach, describe, expect, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { writeSession } from "../fixtures/session-cookies.ts";

const state = vi.hoisted(() => ({
  /** While true, `io()` stays pending like a prerender; `release` ends it. */
  block: false,
  release: undefined as (() => void) | undefined,
  calls: 0,
  headers: new Headers(),
}));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(state.headers),
  // SAFETY: the code under test only reads getAll() from the jar.
  cookies: () =>
    Promise.resolve({ getAll: () => [], set: () => undefined } as never),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: () => undefined,
  revalidateTag: () => undefined,
  cacheTag: () => undefined,
  cacheLife: () => undefined,
  io: () => {
    state.calls += 1;

    if (!state.block) {
      return Promise.resolve();
    }

    return new Promise<void>((resolve) => {
      state.release = resolve;
    });
  },
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

const bsb = createNext(createSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks, fetch: vi.fn<typeof fetch>() },
});

/** Microtasks only: a timer would read the clock itself. */
async function flush(): Promise<void> {
  for (let turn = 0; turn < 50; turn += 1) {
    await Promise.resolve();
  }
}

async function request(): Promise<Request> {
  const token = await signer.sign({ sub: USER });

  const cookie = writeSession([], NAME, {
    access_token: token,
    refresh_token: "r",
    expires_at: Math.floor(Date.now() / 1000) + 3600,
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");

  return new Request("https://app.test/", { headers: { cookie } });
}

describe("reading the clock during a prerender", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    state.block = false;
    state.release = undefined;
    state.calls = 0;
  });

  it("resolve waits for io() before it reads the clock", async () => {
    const incoming = await request();
    state.block = true;
    const now = vi.spyOn(Date, "now");
    const pending = bsb.resolve(incoming);

    await flush();
    expect(state.calls).toBe(1);
    expect(now).not.toHaveBeenCalled();

    state.release?.();
    const { auth } = await pending;

    expect(auth.kind).toBe("user");
    expect(now).toHaveBeenCalledWith();
  });

  it("contextFromSession waits for io() before it judges expiry", async () => {
    state.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });

    const snapshot = await bsb.getClaims();
    expect(snapshot?.userId).toBe(USER);

    state.block = true;
    state.calls = 0;
    const now = vi.spyOn(Date, "now");
    const pending = bsb.contextFromSession(snapshot);

    await flush();
    expect(state.calls).toBe(1);
    expect(now).not.toHaveBeenCalled();

    state.release?.();
    const ctx = await pending;

    expect(ctx.auth.kind).toBe("user");
    expect(now).toHaveBeenCalledWith();
  });

  it("an anonymous context needs no io()", async () => {
    state.block = true;
    const ctx = await bsb.contextFromSession(null);

    expect(ctx.auth.kind).toBe("none");
    expect(state.calls).toBe(0);
  });
});
