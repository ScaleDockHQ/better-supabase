import { describe, expect, it, vi } from "vitest";

import { astroPostgresCache } from "../../src/cache-postgres/astro/index.ts";
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
});
