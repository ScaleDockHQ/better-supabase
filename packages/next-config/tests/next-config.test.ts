import { describe, expect, it } from "vitest";

import { createNextConfig } from "../src/next-config.ts";

describe("createNextConfig headers", () => {
  it("lets /sw.js control the whole origin and never caches it", async () => {
    const rules = (await createNextConfig().headers?.()) ?? [];
    const worker = rules.find((rule) => rule.source === "/sw.js");

    expect(worker?.headers).toStrictEqual([
      { key: "Service-Worker-Allowed", value: "/" },
      { key: "Content-Type", value: "application/javascript; charset=utf-8" },
      { key: "Cache-Control", value: "no-cache, no-store, must-revalidate" },
    ]);
  });

  it("keeps an app's own rules after the shared ones", async () => {
    const own = { source: "/x", headers: [{ key: "X-Own", value: "1" }] };
    const config = createNextConfig({ headers: async () => [own] });

    const rules = (await config.headers?.()) ?? [];

    expect(rules.at(-1)).toStrictEqual(own);
  });
});

describe("createNextConfig remoteCacheHandler", () => {
  it("sets cacheHandlers.remote next to the app's other handlers", () => {
    expect(createNextConfig().cacheHandlers).toBeUndefined();
    expect(
      createNextConfig({
        remoteCacheHandler: "./cache/remote.mjs",
        cacheHandlers: { default: "./cache/default.mjs" },
      }).cacheHandlers,
    ).toStrictEqual({
      default: "./cache/default.mjs",
      remote: "./cache/remote.mjs",
    });
    expect(
      createNextConfig({ remoteCacheHandler: "./r.mjs" }),
    ).not.toHaveProperty("remoteCacheHandler");
  });
});
