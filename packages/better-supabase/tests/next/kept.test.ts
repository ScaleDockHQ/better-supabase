import { beforeEach, describe, expect, it, vi } from "vitest";

import type { KeptSkip } from "../../src/core/kept-cache.ts";

import { createSupabase } from "../../src/core/define.ts";
import { memoryKeptStore } from "../../src/core/kept-cache.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  cacheLife: vi.fn<(profile: unknown) => void>(),
  cacheTag: vi.fn<(...tags: string[]) => void>(),
}));

vi.mock("next/headers.js", () => ({
  cookies: () => Promise.resolve({ getAll: () => [] }),
  headers: () => Promise.resolve(mocks.headers),
}));

vi.mock("next/cache.js", () => ({
  cacheLife: mocks.cacheLife,
  cacheTag: mocks.cacheTag,
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";
const signer = await createTestSigner();

async function signIn(userId: string): Promise<void> {
  const token = await signer.sign({ sub: userId });
  mocks.headers = new Headers({ authorization: `Bearer ${token}` });
}

describe("bsb.kept()", () => {
  const store = memoryKeptStore();
  const set = vi.spyOn(store, "set");
  const skips: KeptSkip[] = [];

  const bsb = createNext(createSupabase(schema), {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks },
    kept: { store, onSkip: (skip) => skips.push(skip) },
  });

  const fill = vi.fn((userId: string | null, id: string) =>
    Promise.resolve({ userId, id }),
  );

  const read = bsb.kept(
    (ctx, id: string) =>
      fill(ctx.auth.kind === "user" ? ctx.auth.user.id : null, id),
    { name: "customer", tables: ["customers"] },
  );

  beforeEach(() => {
    mocks.headers = new Headers();
    mocks.cacheLife.mockReset();
    mocks.cacheTag.mockReset();
    fill.mockClear();
    set.mockClear();
    skips.length = 0;
  });

  it("runs as the caller once and serves the entry after", async () => {
    await signIn(ALICE);

    expect(await read("c1")).toEqual({ userId: ALICE, id: "c1" });
    expect(await read("c1")).toEqual({ userId: ALICE, id: "c1" });
    expect(fill).toHaveBeenCalledOnce();
    expect(set.mock.calls[0]?.[2].tags).toEqual(
      expect.arrayContaining(["bsb:customers"]),
    );
  });

  it("keeps one entry per user and per argument", async () => {
    await signIn(ALICE);
    await read("c2");
    await read("c3");
    await signIn(BOB);

    expect(await read("c2")).toEqual({ userId: BOB, id: "c2" });
    expect(fill).toHaveBeenCalledTimes(3);
  });

  it("fills again once a table tag expires", async () => {
    await signIn(ALICE);
    await read("c4");
    await new Promise((resolve) => {
      setTimeout(resolve, 2);
    });
    await store.expireTags(["bsb:customers"]);
    await new Promise((resolve) => {
      setTimeout(resolve, 2);
    });
    await read("c4");

    expect(fill).toHaveBeenCalledTimes(2);
  });

  it("applies its tags and life to an enclosing cache entry", async () => {
    await signIn(ALICE);
    await read("c5");

    expect(mocks.cacheLife).toHaveBeenLastCalledWith({
      stale: 300,
      revalidate: 300,
      expire: 86_400,
    });
    expect(mocks.cacheTag.mock.lastCall).toEqual(
      expect.arrayContaining(["bsb:customers"]),
    );
  });

  it("reads through for a token that fails to verify", async () => {
    mocks.headers = new Headers({ authorization: "Bearer not-a-token" });

    await read("c6");
    await read("c6");

    expect(fill).toHaveBeenCalledTimes(2);
    expect(set).not.toHaveBeenCalled();
  });

  it("starts new entries when the version changes", async () => {
    await signIn(ALICE);

    const v2 = bsb.kept(
      (ctx, id: string) =>
        fill(ctx.auth.kind === "user" ? ctx.auth.user.id : null, id),
      { name: "customer", tables: ["customers"], version: "2" },
    );

    await read("c7");
    await v2("c7");

    expect(fill).toHaveBeenCalledTimes(2);
  });

  it("reports an entry it could not store", async () => {
    await signIn(ALICE);

    const big = bsb.kept(() => Promise.resolve("x".repeat(3 * 1024 * 1024)), {
      name: "big",
    });

    await big();

    expect(skips).toEqual([
      expect.objectContaining({ name: "big", reason: "size" }),
    ]);
  });
});
