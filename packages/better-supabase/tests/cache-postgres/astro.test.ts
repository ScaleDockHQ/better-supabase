import { describe, expect, it, vi } from "vitest";

import astroPostgresCacheProvider, {
  astroPostgresCache,
} from "../../src/cache-postgres/astro/index.ts";
import { dbError } from "../../src/core/errors.ts";
import { err } from "../../src/core/result.ts";
import { memoryStore } from "./memory-store.ts";

const logger = { warn: vi.fn() };

function run(
  provider: ReturnType<typeof astroPostgresCache>,
  path: string,
  next: () => Promise<Response>,
) {
  const url = new URL(`https://example.com${path}`);

  return provider.onRequest({ request: new Request(url), url, logger }, next);
}

const cacheable =
  (body: string, extra: Record<string, string> = {}) =>
  () =>
    Promise.resolve(
      new Response(body, {
        headers: {
          "CDN-Cache-Control": "max-age=60",
          "Cache-Tag": "bsb:orders, bsb:orders:1",
          ...extra,
        },
      }),
    );

describe("astroPostgresCache", () => {
  it("stores a response and serves it from Postgres", async () => {
    const provider = astroPostgresCache({ client: memoryStore() });
    const next = vi.fn(cacheable("page"));

    const first = await run(provider, "/orders?b=2&a=1", next);
    const second = await run(provider, "/orders?a=1&b=2", next);

    expect(first.headers.get("X-Astro-Cache")).toBe("MISS");
    expect(second.headers.get("X-Astro-Cache")).toBe("HIT");
    expect(await second.text()).toBe("page");
    expect(next).toHaveBeenCalledOnce();
  });

  it("renders again after the tag is invalidated", async () => {
    const provider = astroPostgresCache({ client: memoryStore() });
    const next = vi.fn(cacheable("page"));

    await run(provider, "/orders", next);
    await new Promise<void>((resolve) => {
      setTimeout(resolve, 5);
    });
    await provider.invalidate({ tags: "bsb:orders:1" });
    const again = await run(provider, "/orders", next);

    expect(again.headers.get("X-Astro-Cache")).toBe("MISS");
    expect(next).toHaveBeenCalledTimes(2);
  });

  it("invalidates by path", async () => {
    const provider = astroPostgresCache({ client: memoryStore() });
    const next = vi.fn(cacheable("page"));

    await run(provider, "/orders", next);
    await provider.invalidate({ path: "/orders" });
    await run(provider, "/orders", next);

    expect(next).toHaveBeenCalledTimes(2);
  });

  it("never stores a response with a cookie or without max-age", async () => {
    const store = memoryStore();
    const provider = astroPostgresCache({ client: store });

    await run(provider, "/a", cacheable("x", { "Set-Cookie": "a=b" }));
    await run(provider, "/b", () => Promise.resolve(new Response("y")));
    await run(provider, "/c", cacheable("z", { Vary: "Cookie" }));

    expect(store.entries.size).toBe(0);
  });

  it("passes non-GET requests through", async () => {
    const provider = astroPostgresCache({ client: memoryStore() });
    const url = new URL("https://example.com/x");
    const next = vi.fn(cacheable("p"));

    await provider.onRequest(
      { request: new Request(url, { method: "POST" }), url, logger },
      next,
    );

    expect(next).toHaveBeenCalledOnce();
  });

  it("serves a stale entry and refreshes it in the background", async () => {
    const store = memoryStore();
    const provider = astroPostgresCache({ client: store });
    const waitUntil = vi.fn();
    const now = Date.now();

    store.entries.set("astro:https://example.com/s", {
      key: "astro:https://example.com/s",
      value: new TextEncoder().encode("old"),
      tags: [],
      storedAt: now - 120_000,
      expiresAt: now + 60_000,
      meta: {
        status: 200,
        headers: [["content-type", "text/plain"]],
        maxAge: 60,
      },
    });

    const url = new URL("https://example.com/s");

    const response = await provider.onRequest(
      { request: new Request(url), url, logger, waitUntil },
      cacheable("new"),
    );

    expect(response.headers.get("X-Astro-Cache")).toBe("STALE");
    expect(await response.text()).toBe("old");
    expect(waitUntil).toHaveBeenCalledOnce();

    await waitUntil.mock.calls[0]?.[0];

    expect(
      new TextDecoder().decode(
        store.entries.get("astro:https://example.com/s")?.value,
      ),
    ).toBe("new");
  });

  it("logs a refresh that fails instead of throwing", async () => {
    const store = memoryStore();
    const provider = astroPostgresCache({ client: store });
    const warn = vi.fn();
    const waitUntil = vi.fn();
    const now = Date.now();

    store.entries.set("astro:https://example.com/s", {
      key: "astro:https://example.com/s",
      value: new Uint8Array(),
      tags: [],
      storedAt: now - 120_000,
      expiresAt: now + 60_000,
      meta: { status: 200, headers: [], maxAge: 60 },
    });

    const url = new URL("https://example.com/s");

    await provider.onRequest(
      { request: new Request(url), url, logger: { warn }, waitUntil },
      () => Promise.reject(new Error("render failed")),
    );
    await waitUntil.mock.calls[0]?.[0];

    expect(warn).toHaveBeenCalledWith("Error: render failed");
  });

  it("treats a store read error as a miss and logs it", async () => {
    const store = memoryStore();
    const warn = vi.fn();

    const provider = astroPostgresCache({
      client: {
        ...store,
        lookup: () => Promise.resolve(err(dbError("unexpected", "read down"))),
      },
    });

    const url = new URL("https://example.com/x");

    const response = await provider.onRequest(
      { request: new Request(url), url, logger: { warn } },
      cacheable("fresh"),
    );

    expect(await response.text()).toBe("fresh");
    expect(response.headers.get("X-Astro-Cache")).toBeNull();
    expect(warn).toHaveBeenCalledWith("read down");
  });

  it("still answers when the write fails", async () => {
    const store = memoryStore();
    const warn = vi.fn();

    const provider = astroPostgresCache({
      client: {
        ...store,
        set: () => Promise.resolve(err(dbError("unexpected", "write down"))),
      },
    });

    const url = new URL("https://example.com/x");

    const response = await provider.onRequest(
      { request: new Request(url), url, logger: { warn } },
      cacheable("fresh"),
    );

    expect(response.headers.get("X-Astro-Cache")).toBe("MISS");
    expect(warn).toHaveBeenCalledWith("write down");
  });

  it("never stores a bodiless redirect or Vary: *", async () => {
    const store = memoryStore();
    const provider = astroPostgresCache({ client: store });

    await run(provider, "/r", () =>
      Promise.resolve(
        new Response(null, {
          status: 302,
          headers: { "CDN-Cache-Control": "max-age=60", Location: "/x" },
        }),
      ),
    );
    await run(provider, "/v", cacheable("v", { Vary: "*" }));

    expect(store.entries.size).toBe(0);
  });

  it("throws the store message when invalidation fails", async () => {
    const store = memoryStore();

    const provider = astroPostgresCache({
      client: {
        ...store,
        deletePath: () => Promise.resolve(err(dbError("unexpected", "del"))),
        markTags: () => Promise.resolve(err(dbError("unexpected", "mark"))),
      },
    });

    await expect(provider.invalidate({ path: "/x" })).rejects.toThrow("del");
    await expect(provider.invalidate({ tags: ["a"] })).rejects.toThrow("mark");
  });
});

describe("astroPostgresCacheProvider", () => {
  it("needs the URL and key in the env", () => {
    vi.stubEnv("BSB_TEST_URL", "");

    const provider = astroPostgresCacheProvider({
      urlEnv: "BSB_TEST_URL",
      keyEnv: "BSB_TEST_KEY",
    });

    expect(() => provider.invalidate({ path: "/" })).toThrow(
      "The Postgres Astro cache needs the project URL and the service role key in the env",
    );
    vi.unstubAllEnvs();
  });

  it("builds the provider once from the env", async () => {
    vi.stubEnv("BSB_TEST_URL", "http://127.0.0.1:1");
    vi.stubEnv("BSB_TEST_KEY", "key");

    const provider = astroPostgresCacheProvider({
      urlEnv: "BSB_TEST_URL",
      keyEnv: "BSB_TEST_KEY",
    });

    const url = new URL("https://example.com/x");
    const next = vi.fn(() => Promise.resolve(new Response("posted")));
    const request = () => new Request(url, { method: "POST" });

    const first = await provider.onRequest(
      { request: request(), url, logger },
      next,
    );

    await provider.onRequest({ request: request(), url, logger }, next);

    expect(provider.name).toBe("better-supabase-postgres");
    expect(await first.text()).toBe("posted");
    expect(next).toHaveBeenCalledTimes(2);
    vi.unstubAllEnvs();
  });
});
