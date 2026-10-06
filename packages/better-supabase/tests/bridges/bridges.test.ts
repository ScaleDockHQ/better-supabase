import { os } from "@orpc/server";
import { RPCHandler } from "@orpc/server/fetch";
import { defineMiddleware, getEnv } from "@supabase/middleware";
import { Hono } from "hono";
import { describe, expect, it } from "vitest";

import type { ServerOptions } from "../../src/server/server.ts";
import type { AdapterRun } from "../../src/testing/adapter.ts";

import { bufferInPlace, toResponse } from "../../src/bridges/shared.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { toEdge } from "../../src/edge/index.ts";
import { toElysia } from "../../src/elysia/index.ts";
import { toExpo } from "../../src/expo/index.ts";
import { toH3 } from "../../src/h3/index.ts";
import { toHono } from "../../src/hono/index.ts";
import { createOrpc, toOrpc } from "../../src/orpc/index.ts";
import { toReactRouter } from "../../src/react-router/index.ts";
import { unexpectedResponse } from "../../src/server/adapter.ts";
import { withBetterSupabase } from "../../src/server/index.ts";
import { respond } from "../../src/server/respond.ts";
import { toSvelteKit } from "../../src/sveltekit/index.ts";
import { toTanStackStart } from "../../src/tanstack-start/index.ts";
import { testAdapter } from "../../src/testing/adapter.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

type Bs = Parameters<AdapterRun>[0];

/** What a route does with the module's `run`: a Result-aware response. */
async function answer(run: AdapterRun, bs: Bs, request: Request) {
  const instance = new URL(request.url).pathname;
  try {
    return await respond(() => run(bs), { instance, expose: false });
  } catch (cause) {
    return unexpectedResponse(cause, { instance, expose: false });
  }
}

const entriesFor = (
  server: ServerOptions,
  allow: NonNullable<Parameters<typeof withBetterSupabase>[1]>["allow"],
  waitUntil: (promise: Promise<unknown>) => void,
) =>
  [
    withBetterSupabase(betterSupabase, {
      ...server,
      ...(allow === undefined ? {} : { allow }),
      expose: false,
      waitUntil,
    }),
  ] as const;

describe("bridges pass testAdapter", () => {
  it("toHono", async () => {
    await testAdapter("toHono", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const app = new Hono()
          .use(toHono(entriesFor(server, allow, waitUntil)))
          .get("*", (c) => answer(run, c.var.bs, c.req.raw));
        return async (request) => app.fetch(request);
      },
    });
  });

  it("toEdge", async () => {
    await testAdapter("toEdge", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) =>
        toEdge(entriesFor(server, allow, waitUntil), (request, ctx) =>
          answer(run, ctx.bs, request),
        ),
    });
  });

  it("toExpo", async () => {
    await testAdapter("toExpo", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const handler = toExpo(
          entriesFor(server, allow, waitUntil),
          (request, ctx) => answer(run, ctx.bs, request),
        );
        return (request) => handler(request);
      },
    });
  });

  it("toOrpc", async () => {
    await testAdapter("toOrpc", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const orpc = createOrpc(betterSupabase, server);
        const procedure = os
          .$context<{ request: Request; bs: Bs }>()
          .handler(({ context }) =>
            orpc.unwrap((async () => run(context.bs))()),
          );
        const fetch = toOrpc(
          entriesFor(server, allow, waitUntil),
          new RPCHandler({ procedure }),
        );
        return (request) =>
          fetch(
            new Request(new URL("/procedure", request.url), {
              method: "POST",
              headers: {
                "content-type": "application/json",
                cookie: request.headers.get("cookie") ?? "",
              },
              body: JSON.stringify({ json: null }),
            }),
          );
      },
    });
  });

  it("toTanStackStart", async () => {
    await testAdapter("toTanStackStart", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const middleware = toTanStackStart(
          entriesFor(server, allow, waitUntil),
        );
        return async (request) => {
          try {
            const result = await middleware({
              request,
              next: async ({ context }) => ({
                response: await answer(run, context.bs, request),
              }),
            });
            return result.response;
          } catch (thrown) {
            if (thrown instanceof Response) return thrown;
            throw thrown;
          }
        };
      },
    });
  });

  it("toSvelteKit", async () => {
    await testAdapter("toSvelteKit", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const handle = toSvelteKit(entriesFor(server, allow, waitUntil));
        return (request) =>
          handle({
            event: { request, locals: {} },
            resolve: (event) => answer(run, event.locals.bs!, event.request),
          });
      },
    });
  });

  it("toReactRouter", async () => {
    await testAdapter("toReactRouter", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const key = Symbol("supabase");
        const middleware = toReactRouter(
          entriesFor(server, allow, waitUntil),
          key,
        );
        return (request) => {
          const store = new Map<symbol, { readonly bs: Bs }>();
          return middleware(
            { request, context: { set: (k, v) => store.set(k, v) } },
            () => answer(run, store.get(key)!.bs, request),
          );
        };
      },
    });
  });

  it("toH3", async () => {
    await testAdapter("toH3", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const middleware = toH3(entriesFor(server, allow, waitUntil));
        return (request) => {
          const event: Parameters<typeof middleware>[0] = {
            req: request,
            context: {},
          };
          return middleware(event, () =>
            answer(run, event.context.bs!, request),
          );
        };
      },
    });
  });

  it("toElysia", async () => {
    await testAdapter("toElysia", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const bridge = toElysia(entriesFor(server, allow, waitUntil));
        return bridge.wrap((request) =>
          answer(run, bridge.context(request).bs, request),
        );
      },
    });
  });
});

describe("bridge behavior", () => {
  const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
  const env = {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  };

  it("lets an entry and the route both read the body", async () => {
    const reads: string[] = [];
    const peek = defineMiddleware({
      key: "peeked",
      run: () => async (request) => {
        reads.push(await request.text());
        return { peeked: true };
      },
    });
    const app = new Hono()
      .use(toHono([peek()]))
      .post("/", async (c) => c.text(await c.req.text()));
    const response = await app.fetch(
      new Request("https://api.test/", { method: "POST", body: "hello" }),
    );
    expect(await response.text()).toBe("hello");
    expect(reads).toEqual(["hello"]);
  });

  it("bufferInPlace keeps the request and caches its body", async () => {
    const request = new Request("https://api.test/", {
      method: "POST",
      body: JSON.stringify({ a: 1 }),
    });
    bufferInPlace(request);
    expect(await request.text()).toBe('{"a":1}');
    expect(await request.json()).toEqual({ a: 1 });
    expect(request.clone()).toBe(request);
  });

  it("toResponse maps handler values", async () => {
    expect(toResponse(undefined).status).toBe(204);
    expect(await toResponse("hi").text()).toBe("hi");
    expect(await toResponse({ a: 1 }).json()).toEqual({ a: 1 });
    const response = new Response("x");
    expect(toResponse(response)).toBe(response);
  });

  it("toH3 answers a plain handler value as JSON", async () => {
    const signer = await createTestSigner();
    const middleware = toH3([
      withBetterSupabase(betterSupabase, {
        env,
        auth: { jwks: signer.jwks as never },
        allow: ["anon"],
      }),
    ]);
    const event = { req: new Request("https://api.test/"), context: {} };
    const response = await middleware(event, () => ({ ok: true }));
    expect(await response.json()).toEqual({ ok: true });
    expect(Object.keys(event.context)).toContain("db");
  });

  it("toSvelteKit seeds getEnv from event.platform.env", async () => {
    const seen: (string | undefined)[] = [];
    const probe = defineMiddleware({
      key: "probe",
      run: () => async () => {
        seen.push(getEnv("BRIDGE_PROBE"));
        return { probe: true };
      },
    });
    const handle = toSvelteKit([probe()]);
    const locals: { probe?: boolean } = {};
    await handle({
      event: {
        request: new Request("https://app.test/"),
        locals,
        platform: { env: { BRIDGE_PROBE: "bound" } },
      },
      resolve: () => new Response("ok"),
    });
    expect(seen).toEqual(["bound"]);
    expect(locals.probe).toBe(true);
  });

  it("toTanStackStart throws a short circuit as a Response", async () => {
    const signer = await createTestSigner();
    const middleware = toTanStackStart([
      withBetterSupabase(betterSupabase, {
        env,
        auth: { jwks: signer.jwks as never },
      }),
    ]);
    let ran = false;
    const thrown = await middleware({
      request: new Request("https://app.test/"),
      next: async () => {
        ran = true;
        return {};
      },
    }).catch((error: unknown) => error);
    expect(thrown).toBeInstanceOf(Response);
    expect((thrown as Response).status).toBe(401);
    expect(ran).toBe(false);
  });

  it("toTanStackStart returns a server function result without a response", async () => {
    const middleware = toTanStackStart([]);
    const result = await middleware({
      request: new Request("https://app.test/"),
      next: async () => ({ result: 1 }),
    });
    expect(result).toEqual({ result: 1 });
  });

  it("toElysia fails closed for a request it did not serve", () => {
    const bridge = toElysia([]);
    expect(() => bridge.context(new Request("https://app.test/"))).toThrow(
      /toElysia\(\)\.wrap/,
    );
  });
});
