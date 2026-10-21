import { os } from "@orpc/server";
import { RPCHandler } from "@orpc/server/fetch";
import { describe, expect, it } from "vitest";

import type { OrpcRequestContext, RateLimiter } from "../../src/orpc/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { createOrpc } from "../../src/orpc/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

describe("createOrpc().rateLimit", () => {
  const counts = new Map<string, number>();

  const limiter: RateLimiter = {
    check: async (_scope, key, rule) => {
      const used = (counts.get(key) ?? 0) + 1;
      counts.set(key, used);
      const max = rule?.max ?? 1;

      return ok(
        used <= max
          ? { allowed: true, remaining: max - used, retryAfter: 0 }
          : { allowed: false, remaining: 0, retryAfter: 30 },
      );
    },
  };

  const bs = createOrpc(defineSupabase(schema), { env });

  const base = os
    .$context<OrpcRequestContext>()
    .use(
      bs.rateLimit({
        limiter,
        scope: "rpc",
        rule: { max: 2, period: "1 minute" },
        key: ({ context, path }) =>
          context.request.headers.get("x-client") === null
            ? undefined
            : `${context.request.headers.get("x-client")}:${path.join(".")}`,
      }),
    );

  const fetch = bs.fetchHandler(
    new RPCHandler({ ping: base.handler(() => ({ pong: true })) }),
    { prefix: "/rpc" },
  );

  const post = (client?: string) =>
    fetch(
      new Request("https://api.test/rpc/ping", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(client ? { "x-client": client } : {}),
        },
        body: JSON.stringify({}),
      }),
    );

  it("adds the RateLimit fields, then refuses with 429 and Retry-After", async () => {
    const first = await post("a");
    expect(first.status).toBe(200);
    expect(first.headers.get("ratelimit")).toBe('"rpc";r=1');
    expect(first.headers.get("ratelimit-policy")).toBe('"rpc";q=2;w=60');
    expect((await post("a")).headers.get("ratelimit")).toBe('"rpc";r=0');
    const refused = await post("a");
    expect(refused.status).toBe(429);
    expect(refused.headers.get("retry-after")).toBe("30");
    expect(refused.headers.get("ratelimit")).toBe('"rpc";r=0;t=30');
  });

  it("leaves calls without a key alone", async () => {
    const response = await post();
    expect(response.status).toBe(200);
    expect(response.headers.has("ratelimit")).toBe(false);
  });
});
