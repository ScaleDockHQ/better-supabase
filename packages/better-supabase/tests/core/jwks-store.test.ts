import { describe, expect, it, vi } from "vitest";

import { clearJwksCache, sharedJwks } from "../../src/core/jwks-cache.ts";
import { vercelRuntimeCache } from "../../src/core/jwks-store.ts";

function runtimeCache() {
  const values = new Map<string, unknown>();

  return {
    values,
    get: vi.fn(async (key: string) => values.get(key) ?? null),
    set: vi.fn(
      async (key: string, value: unknown, _options?: { ttl?: number }) => {
        values.set(key, value);
      },
    ),
  };
}

describe("vercelRuntimeCache", () => {
  it("opens the cache on first use, once, in the default namespace", async () => {
    const cache = runtimeCache();
    const getCache = vi.fn(() => cache);
    const store = vercelRuntimeCache(getCache);

    expect(getCache).not.toHaveBeenCalled();

    await store.set("k", { a: 1 }, { ttl: 60 });
    expect(await store.get("k")).toEqual({ a: 1 });
    expect(getCache).toHaveBeenCalledExactlyOnceWith({
      namespace: "better-supabase-jwks",
    });
    expect(cache.set).toHaveBeenCalledWith("k", { a: 1 }, { ttl: 60 });
  });

  it("uses the namespace it is given", async () => {
    const getCache = vi.fn(() => runtimeCache());
    await vercelRuntimeCache(getCache, { namespace: "auth" }).get("k");

    expect(getCache).toHaveBeenCalledWith({ namespace: "auth" });
  });

  it("turns a getCache that throws into a rejection", async () => {
    const store = vercelRuntimeCache(() => {
      throw new Error("no request context");
    });

    await expect(store.get("k")).rejects.toThrow("no request context");
  });

  it("serves sharedJwks across instances", async () => {
    clearJwksCache();

    const cache = runtimeCache();
    const store = vercelRuntimeCache(() => cache);
    const url = new URL("https://issuer.example.com/jwks.json");
    const keys = { keys: [{ kty: "OKP", crv: "Ed25519", x: "x", kid: "k1" }] };

    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json(keys),
    );

    await sharedJwks(url, false, { fetch, now: () => 0, store });
    clearJwksCache();
    await sharedJwks(url, false, { fetch, now: () => 1000, store });

    expect(fetch).toHaveBeenCalledOnce();
  });
});
