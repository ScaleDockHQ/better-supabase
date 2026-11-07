import { beforeEach, describe, expect, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  order: [] as string[],
  navigation: vi.fn<() => Promise<void>>(),
  prefetch: vi.fn<() => Promise<void>>(),
  cacheLife: vi.fn<(profile: unknown) => void>(),
}));

vi.mock(import("next/headers.js"), () => ({
  // SAFETY: the code under test reads only getAll from the cookie jar.
  cookies: () => Promise.resolve({ getAll: () => [] } as never),
  headers: () => Promise.resolve(mocks.headers as never),
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: mocks.cacheLife,
  cacheTag: vi.fn(),
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  navigation: mocks.navigation,
  prefetch: mocks.prefetch,
  io: () => {
    mocks.order.push("first read");

    return Promise.resolve();
  },
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

const bsb = createNext(createSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  cacheTags: false,
  auth: { jwks: signer.jwks },
});

beforeEach(async () => {
  mocks.order.length = 0;
  mocks.cacheLife.mockReset();

  mocks.navigation.mockReset();
  mocks.navigation.mockImplementation(() => {
    mocks.order.push("navigation");

    return Promise.resolve();
  });

  mocks.prefetch.mockReset();
  mocks.prefetch.mockImplementation(() => {
    mocks.order.push("prefetch");

    return Promise.resolve();
  });

  mocks.headers = new Headers({
    authorization: `Bearer ${await signer.sign({ sub: USER })}`,
  });
});

describe("bsb.cached({ stage })", () => {
  it("awaits navigation() before the first read", async () => {
    await bsb.cached({ stage: "navigation" });

    expect(mocks.order[0]).toBe("navigation");
    expect(mocks.order).toContain("first read");
    expect(mocks.prefetch).not.toHaveBeenCalled();
  });

  it("awaits prefetch() before the first read", async () => {
    await bsb.cached({ stage: "prefetch" });

    expect(mocks.order[0]).toBe("prefetch");
    expect(mocks.order).toContain("first read");
    expect(mocks.navigation).not.toHaveBeenCalled();
  });

  it("calls neither gate without a stage", async () => {
    await bsb.cached();

    expect(mocks.navigation).not.toHaveBeenCalled();
    expect(mocks.prefetch).not.toHaveBeenCalled();
  });

  it("still reads when the gate throws", async () => {
    mocks.navigation.mockRejectedValueOnce(new Error("inside a cache scope"));

    const { session } = await bsb.cached({ stage: "navigation" });

    expect(session.kind).toBe("user");
  });
});

describe("bsb.cached({ life })", () => {
  it('maps "max" to the max profile', async () => {
    await bsb.cached({ life: "max" });

    expect(mocks.cacheLife).toHaveBeenLastCalledWith({
      stale: 300,
      revalidate: 2_592_000,
      expire: 31_536_000,
    });
  });

  it("keeps an object profile as it was", async () => {
    await bsb.cached({ life: { stale: 600 } });

    expect(mocks.cacheLife).toHaveBeenLastCalledWith({ stale: 600 });
  });
});

describe("awaitStage when a gate throws", () => {
  it("warns once and carries on", async () => {
    const { awaitStage } = await import("../../src/next/entry.ts");
    const warn = vi.fn<(message: string) => void>();
    mocks.navigation.mockRejectedValue(new Error("inside a cache scope"));

    await awaitStage("navigation", warn);
    await awaitStage("navigation", warn);

    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0]?.[0]).toContain("not allowed");
  });
});
