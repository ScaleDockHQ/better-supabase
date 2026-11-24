import { beforeEach, describe, expect, it, vi } from "vitest";

import type { KeptSkip } from "../../src/core/kept-cache.ts";

import { createSupabase } from "../../src/core/define.ts";
import { memoryKeptStore } from "../../src/core/kept-cache.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock(import("next/headers.js"), () => ({
  // SAFETY: the code under test reads only getAll from the cookie jar.
  cookies: () => Promise.resolve({ getAll: () => [] } as never),
  headers: () => Promise.resolve(mocks.headers as never),
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: vi.fn(),
  cacheTag: vi.fn(),
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";
const signer = await createTestSigner();

async function signIn(userId: string): Promise<void> {
  const token = await signer.sign({ sub: userId });
  mocks.headers = new Headers({ authorization: `Bearer ${token}` });
}

describe('bsb.kept({ share: "public" })', () => {
  const store = memoryKeptStore();
  const set = vi.spyOn(store, "set");
  const skips: KeptSkip[] = [];
  const requests: { path: string; key: string | null }[] = [];

  const bsb = createNext(createSupabase(schema), {
    env: {
      url: PROJECT_URL,
      publishableKey: "sb_publishable_test",
      jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
    },
    cacheTags: false,
    auth: { jwks: signer.jwks },
    kept: { store, onSkip: (skip) => skips.push(skip) },
  });

  const tags = bsb.kept(
    async (ctx) => ({
      kind: ctx.auth.kind,
      rows: await ctx.db.tags.list({ select: ["id"] }),
    }),
    { name: "public-tags", tables: ["tags"], share: "public" },
  );

  beforeEach(() => {
    set.mockClear();
    skips.length = 0;
    requests.length = 0;

    vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const headers = new Headers(init?.headers);

      requests.push({ path: url.pathname, key: headers.get("authorization") });

      return Promise.resolve(Response.json([{ id: "t1" }]));
    });
  });

  it("fills once as anon and serves every visitor the same entry", async () => {
    await signIn(ALICE);
    const first = await tags();

    await signIn(BOB);
    const second = await tags();

    mocks.headers = new Headers();
    const third = await tags();

    expect(first).toEqual(second);
    expect(third).toEqual(first);
    expect(first.kind).toBe("none");
    expect(requests).toHaveLength(1);
    expect(requests[0]?.key).not.toContain(".");
    expect(set).toHaveBeenCalledOnce();
  });

  it("refuses a read outside the declared tables and stores nothing", async () => {
    const outside = bsb.kept(
      async (ctx) => {
        const read = await ctx.db.contacts.list({ select: ["id"] });

        return read.ok ? "read" : read.error.table;
      },
      { name: "public-outside", tables: ["tags"], share: "public" },
    );

    await signIn(ALICE);

    expect(await outside()).toBe("contacts");
    expect(requests).toHaveLength(0);
    expect(set).not.toHaveBeenCalled();
    expect(skips[0]).toMatchObject({ name: "public-outside" });
  });
});
