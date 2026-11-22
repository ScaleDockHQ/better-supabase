import type { MockInstance } from "vitest";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({
  reads: 0,
  cacheLife: vi.fn<(profile: unknown) => void>(),
  cacheTag: vi.fn<(...tags: string[]) => void>(),
}));

// "use cache" forbids cookies() and headers(): reading either throws there.
vi.mock(import("next/headers.js"), () => ({
  cookies: () => {
    mocks.reads += 1;

    return Promise.reject(new Error("cookies() in a use cache scope"));
  },
  headers: () => {
    mocks.reads += 1;

    return Promise.reject(new Error("headers() in a use cache scope"));
  },
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: mocks.cacheLife,
  cacheTag: mocks.cacheTag,
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => {
    mocks.reads += 1;

    return Promise.reject(new Error("io() in a use cache scope"));
  },
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const PUBLISHABLE = "sb_publishable_test";
const signer = await createTestSigner();

describe("bsb.public()", () => {
  let rest: MockInstance<typeof fetch>;

  const bsb = createNext(createSupabase(schema), {
    env: {
      url: PROJECT_URL,
      publishableKey: PUBLISHABLE,
      jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
    },
    cacheTags: false,
    auth: { jwks: signer.jwks },
  });

  beforeEach(() => {
    mocks.reads = 0;
    mocks.cacheLife.mockReset();
    mocks.cacheTag.mockReset();

    rest = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation(async () => Response.json([]));
  });

  afterEach(() => {
    rest.mockRestore();
  });

  it("never reads the request, so it runs where use cache forbids it", async () => {
    const ctx = await bsb.public({ tables: ["plans"] });

    expect(mocks.reads).toBe(0);
    expect(ctx.auth).toMatchObject({ kind: "none" });
    expect(ctx.session).toMatchObject({ kind: "none" });
  });

  it("reads as the anon role with the publishable key, never a token or the service role", async () => {
    const ctx = await bsb.public();
    await ctx.db.plans.list();

    const [, init] = rest.mock.calls[0] ?? [];
    const sent = new Headers(init?.headers);

    expect(sent.get("apikey")).toBe(PUBLISHABLE);
    expect(sent.get("authorization") ?? `Bearer ${PUBLISHABLE}`).toBe(
      `Bearer ${PUBLISHABLE}`,
    );

    expect(ctx.auth.kind).not.toBe("secret");
  });

  it("gives a signed-in request the same anonymous context", async () => {
    const first = await bsb.public();
    const second = await bsb.public();

    expect(first.auth).toEqual(second.auth);
    expect(first.auth.kind).toBe("none");
  });

  it("sets the shared cacheLife and the table, tenant and row tags", async () => {
    await bsb.public({ tables: ["plans"], id: "pro", tenant: "org-1" });

    expect(mocks.cacheLife).toHaveBeenCalledWith({
      stale: 300,
      revalidate: 300,
      expire: 3600,
    });

    expect(mocks.cacheTag).toHaveBeenCalledWith(
      "bsb:plans@org-1",
      "bsb:plans@*",
      "bsb:plans:pro",
    );
  });

  it("takes the life option and adds no session tag", async () => {
    await bsb.public({ life: { stale: 600, revalidate: 60, expire: 120 } });

    expect(mocks.cacheLife).toHaveBeenCalledWith({
      stale: 600,
      revalidate: 60,
      expire: 120,
    });

    expect(mocks.cacheTag).not.toHaveBeenCalled();
  });
});
