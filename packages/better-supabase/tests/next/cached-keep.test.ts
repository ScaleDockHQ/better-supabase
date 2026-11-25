import type { MockInstance } from "vitest";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { memoryKeptStore } from "../../src/core/kept-cache.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(mocks.headers),
  // SAFETY: the code under test reads only getAll() and set() from the jar.
  cookies: () =>
    Promise.resolve({ getAll: () => [], set: () => undefined } as never),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag() {},
  revalidateTag() {},
  cacheTag() {},
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";

const signer = await createTestSigner();

async function signIn(userId: string): Promise<void> {
  mocks.headers = new Headers({
    authorization: `Bearer ${await signer.sign({ sub: userId })}`,
  });
}

const tick = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 2);
  });

describe("bsb.cached({ keep })", () => {
  let rest: MockInstance<typeof fetch>;

  beforeEach(() => {
    rest = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation(async () => Response.json([]));
  });

  afterEach(() => {
    rest.mockRestore();
  });

  const make = (store = memoryKeptStore()) =>
    createNext(createSupabase(schema), {
      env: {
        url: PROJECT_URL,
        publishableKey: "sb_publishable_test",
        jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      },
      cacheTags: false,
      auth: { jwks: signer.jwks },
      kept: { store },
    });

  const dataCalls = () =>
    rest.mock.calls.filter(([input]) => String(input).includes("/rest/v1/"))
      .length;

  const page = async (bsb: ReturnType<typeof make>) => {
    const ctx = await bsb.cached({ keep: { name: "page" } });

    return ctx.db.customers.list();
  };

  it("fills 29 parallel renders with one database call", async () => {
    const bsb = make();
    await signIn(ALICE);

    await Promise.all(Array.from({ length: 29 }, () => page(bsb)));

    expect(dataCalls()).toBe(1);
  });

  it("serves a restarted instance from the shared store", async () => {
    const store = memoryKeptStore();
    await signIn(ALICE);
    await page(make(store));
    rest.mockClear();

    await page(make(store));

    expect(dataCalls()).toBe(0);
  });

  it("keeps one entry per user", async () => {
    const bsb = make();
    await signIn(ALICE);
    await page(bsb);
    await signIn(BOB);
    await page(bsb);

    expect(dataCalls()).toBe(2);
  });

  it("reads again after a write expires the table's tag", async () => {
    const bsb = make();
    await signIn(ALICE);
    await page(bsb);
    await tick();
    await bsb.expireTags(["bsb:customers"]);
    await tick();
    await page(bsb);

    expect(dataCalls()).toBe(2);
  });

  it("reads through without the option", async () => {
    const bsb = make();
    await signIn(ALICE);

    for (let i = 0; i < 2; i += 1) {
      const ctx = await bsb.cached();
      await ctx.db.customers.list();
    }

    expect(dataCalls()).toBe(2);
  });

  it("keeps a bootstrap answer across instances", async () => {
    const store = memoryKeptStore();
    await signIn(ALICE);

    rest.mockImplementation(async () =>
      Response.json({
        session_active: true,
        authz_version: 1,
        tenant: null,
        data: { name: "Alice" },
      }),
    );

    const boot = async (bsb: ReturnType<typeof make>) =>
      bsb.bootstrap({ rpc: "app", kept: true });

    const first = await boot(make(store));
    const second = await boot(make(store));

    expect(second.data).toEqual(first.data);
    expect(dataCalls()).toBe(1);
  });
});
