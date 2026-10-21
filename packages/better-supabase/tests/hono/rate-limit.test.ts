import { describe, expect, it } from "vitest";

import type { RateLimiter } from "../../src/hono/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { createHono } from "../../src/hono/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

describe("createHono().rateLimit", () => {
  const counts = new Map<string, number>();

  const limiter: RateLimiter = {
    check: async (_scope, key) => {
      const used = (counts.get(key) ?? 0) + 1;
      counts.set(key, used);

      return ok(
        used <= 1
          ? { allowed: true, remaining: 0, retryAfter: 0 }
          : { allowed: false, remaining: 0, retryAfter: 7 },
      );
    },
  };

  const bs = createHono(defineSupabase(schema), { env });

  const app = bs
    .app()
    .use(
      "/api/*",
      bs.rateLimit({
        limiter,
        scope: "api",
        key: (c) => c.req.header("x-api-key"),
      }),
    )
    .get("/api/ping", (c) => c.json({ pong: true }))
    .get("/api/raw", () => new Response("raw"));

  it("adds RateLimit, then answers 429 Problem Details with Retry-After", async () => {
    const first = await app.request("/api/ping", {
      headers: { "x-api-key": "k1" },
    });

    expect(first.status).toBe(200);
    expect(first.headers.get("ratelimit")).toBe('"api";r=0');
    expect(first.headers.has("ratelimit-policy")).toBe(false);

    const refused = await app.request("/api/ping", {
      headers: { "x-api-key": "k1" },
    });

    expect(refused.status).toBe(429);
    expect(refused.headers.get("content-type")).toContain(
      "application/problem+json",
    );
    expect(refused.headers.get("retry-after")).toBe("7");
    expect(refused.headers.get("ratelimit")).toBe('"api";r=0;t=7');
  });

  it("adds the fields to a raw Response and skips requests without a key", async () => {
    const raw = await app.request("/api/raw", {
      headers: { "x-api-key": "k2" },
    });

    expect(raw.headers.get("ratelimit")).toBe('"api";r=0');
    const anonymous = await app.request("/api/ping");
    expect(anonymous.status).toBe(200);
    expect(anonymous.headers.has("ratelimit")).toBe(false);
  });
});
