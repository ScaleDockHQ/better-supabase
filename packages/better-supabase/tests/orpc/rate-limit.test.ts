import { os } from "@orpc/server";
import { RPCHandler } from "@orpc/server/fetch";
import { ResponseHeadersPlugin } from "@orpc/server/plugins";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type {
  MultiRateLimiter,
  OrpcRequestContext,
  RateLimiter,
  RouteRateLimitHit,
} from "../../src/orpc/index.ts";

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

  const bsb = createOrpc(defineSupabase(schema), { env });

  const base = os
    .$context<OrpcRequestContext>()
    .use(
      bsb.rateLimit({
        limiter,
        scope: "rpc",
        rule: { max: 2, period: "1 minute" },
        key: ({ request, path }) =>
          request.headers.get("x-client") === null
            ? undefined
            : `${request.headers.get("x-client")}:${path.join(".")}`,
      }),
    );

  const fetch = bsb.fetchHandler(
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

describe("createOrpc().rateLimit with hits", () => {
  const counts = new Map<string, number>();

  const limiter: MultiRateLimiter = {
    checkAll: async (hits: readonly RouteRateLimitHit[]) => {
      const results = hits.map((hit) => {
        const used = (counts.get(`${hit.scope}:${hit.key}`) ?? 0) + 1;
        const max = hit.rule?.max ?? 1;

        return used <= max
          ? { allowed: true, remaining: max - used, retryAfter: 0 }
          : { allowed: false, remaining: 0, retryAfter: 20 };
      });

      const allowed = results.every((result) => result.allowed);

      if (allowed) {
        for (const hit of hits) {
          const id = `${hit.scope}:${hit.key}`;
          counts.set(id, (counts.get(id) ?? 0) + 1);
        }
      }

      return ok({
        allowed,
        remaining: Math.min(...results.map((result) => result.remaining)),
        retryAfter: Math.max(...results.map((result) => result.retryAfter)),
        results,
      });
    },
  };

  const bsb = createOrpc(defineSupabase(schema), { env });

  const limited = os
    .$context<OrpcRequestContext & { resHeaders?: Headers }>()
    .use(
      bsb.rateLimit({
        limiter,
        hits: ({ request }) => {
          const user = request.headers.get("x-user");

          return user === null
            ? []
            : [
                { scope: "user", key: user, rule: { max: 2, period: 60 } },
                { scope: "org", key: "acme", rule: { max: 3, period: 60 } },
              ];
        },
      }),
    );

  const fetch = bsb.fetchHandler(
    new RPCHandler(
      {
        ping: limited.handler(() => ({ pong: true })),
        typed: limited
          .errors({
            TOO_MANY_REQUESTS: { data: v.object({ retryAfter: v.number() }) },
          })
          .handler(() => ({ pong: true })),
      },
      { plugins: [new ResponseHeadersPlugin()] },
    ),
    { prefix: "/rpc" },
  );

  const post = (procedure: string, user?: string) =>
    fetch(
      new Request(`https://api.test/rpc/${procedure}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(user ? { "x-user": user } : {}),
        },
        body: JSON.stringify({}),
      }),
    );

  it("counts every limit and writes them through resHeaders", async () => {
    const first = await post("ping", "u1");
    expect(first.status).toBe(200);
    expect(first.headers.get("ratelimit")).toBe('"user";r=1, "org";r=2');
    expect(first.headers.get("ratelimit-policy")).toBe(
      '"user";q=2;w=60, "org";q=3;w=60',
    );
    await post("ping", "u2");
    await post("ping", "u2");
    const refused = await post("ping", "u1");
    expect(refused.status).toBe(429);
    expect(refused.headers.get("retry-after")).toBe("20");
    expect(refused.headers.get("ratelimit")).toBe('"user";r=0, "org";r=0;t=20');
  });

  it("throws the procedure's declared error once a limit refuses", async () => {
    const refused = await post("typed", "u3");

    const body = (await refused.json()) as {
      json: { defined: boolean; code: string };
    };

    expect(refused.status).toBe(429);
    expect(body.json).toMatchObject({
      defined: true,
      code: "TOO_MANY_REQUESTS",
    });
  });

  it("skips an empty list of hits", async () => {
    const response = await post("ping");
    expect(response.status).toBe(200);
    expect(response.headers.has("ratelimit")).toBe(false);
  });
});
