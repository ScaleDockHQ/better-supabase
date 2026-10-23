import type { IncomingMessage, ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";

import { createServer } from "node:http";
import { afterEach, describe, expect, it } from "vitest";

import type { NuxtLike } from "../../src/nuxt/index.ts";
import type { SolidFetchEvent } from "../../src/solid-start/index.ts";
import type { CommunityAdapter } from "./tiers.ts";

import { createAstro } from "../../src/astro/index.ts";
import { ok } from "../../src/core/result.ts";
import { createEdge } from "../../src/edge/index.ts";
import { toElysia } from "../../src/elysia/index.ts";
import { toH3 } from "../../src/h3/index.ts";
import { toH3V1 } from "../../src/h3/v1/index.ts";
import { contextOf, toNestMiddleware } from "../../src/nestjs/index.ts";
import { toNodeHandler } from "../../src/node/index.ts";
import betterSupabaseNuxt from "../../src/nuxt/index.ts";
import { withBetterSupabase } from "../../src/server/composite.ts";
import { createSolidStart } from "../../src/solid-start/index.ts";
import {
  betterSupabase,
  env,
  requestAs,
  server,
  signer,
  USER,
} from "../fixtures/test-server.ts";
import { COMMUNITY_ADAPTERS } from "./tiers.ts";

const options = { env, auth: { jwks: signer.jwks }, prefetchJwks: false };

const entries = [
  withBetterSupabase(server, { allow: ["user", "anon"] }),
] as const;

const member = (): Promise<Request> => requestAs({ role: "member" });

const closers: (() => Promise<void>)[] = [];

afterEach(async () => {
  await Promise.all(closers.splice(0).map((close) => close()));
});

async function listen(
  listener: (req: IncomingMessage, res: ServerResponse) => unknown,
): Promise<string> {
  const http = createServer(listener);
  await new Promise<void>((resolve) => {
    http.listen(0, resolve);
  });
  closers.push(
    () =>
      new Promise<void>((resolve) => {
        http.close(() => {
          resolve();
        });
      }),
  );
  // SAFETY: a server listening on a port has an AddressInfo address.
  const { port } = http.address() as AddressInfo;

  return `http://127.0.0.1:${port}`;
}

async function bearer(): Promise<Record<string, string>> {
  return {
    authorization: `Bearer ${await signer.sign({ sub: USER, app_metadata: { role: "member" } })}`,
  };
}

function authKind(
  context: Readonly<Record<string, unknown>> | undefined,
): unknown {
  const bsb = context?.["bsb"];

  return typeof bsb === "object" &&
    bsb !== null &&
    "auth" in bsb &&
    typeof bsb.auth === "object" &&
    bsb.auth !== null &&
    "kind" in bsb.auth
    ? bsb.auth.kind
    : undefined;
}

/**
 * One signed-in request through each community adapter. Each smoke returns the
 * caller's auth kind as the route saw it. Nuxt needs the Nitro runtime to
 * serve, so its smoke installs the module and returns the handler it added.
 */
const smokes: Record<CommunityAdapter, () => Promise<unknown>> = {
  astro: async () => {
    const bsb = createAstro(betterSupabase, options);
    const context = { request: await member(), locals: {} };

    const response = await bsb.onRequest(context, async () =>
      Response.json(bsb.locals(context).bsb.auth.kind),
    );

    return response.json();
  },
  edge: async () => {
    const bsb = createEdge(betterSupabase, options);

    const response = await bsb.handler((_request, ctx) => ok(ctx.auth.kind))(
      await member(),
    );

    return response.json();
  },
  elysia: async () => {
    const bridge = toElysia(entries);

    const fetch = bridge.wrap(async (request) =>
      Response.json(bridge.context(request).bsb.auth.kind),
    );

    return (await fetch(await member())).json();
  },
  h3: async () => {
    const middleware = toH3(entries);

    const event: Parameters<typeof middleware>[0] = {
      req: await member(),
      context: {},
    };

    const response = await middleware(event, () => ({
      kind: event.context.bsb?.auth.kind,
    }));

    return (await response.json()).kind;
  },
  "h3/v1": async () => {
    const middleware = toH3V1(entries);

    const event: Parameters<typeof middleware>[0] = {
      node: {
        req: {
          method: "GET",
          url: "/",
          headers: { host: "app.test", ...(await bearer()) },
        },
        res: { getHeader: () => undefined, setHeader: () => undefined },
      },
      context: {},
    };

    expect(await middleware(event)).toBeUndefined();

    return event.context.bsb?.auth.kind;
  },
  nestjs: async () => {
    const middleware = toNestMiddleware(entries);

    const url = await listen((req, res) => {
      middleware(req, res, () => {
        res.end(JSON.stringify(authKind(contextOf(req)) ?? null));
      });
    });

    return (await fetch(url, { headers: await bearer() })).json();
  },
  node: async () => {
    const url = await listen(
      toNodeHandler(entries, (_request, { bsb }) => bsb.auth.kind),
    );

    return (await fetch(url, { headers: await bearer() })).text();
  },
  nuxt: async () => {
    const nuxt: NuxtLike = {
      options: { betterSupabase: { server: "~~/server/bsb" }, nitro: {} },
      hook: () => undefined,
    };

    betterSupabaseNuxt(undefined, nuxt);

    return nuxt.options.nitro.handlers;
  },
  "solid-start": async () => {
    let current: SolidFetchEvent | undefined;

    const bsb = createSolidStart(betterSupabase, {
      ...options,
      getRequestEvent: () => current,
    });

    const event: SolidFetchEvent = {
      request: await member(),
      response: { headers: new Headers() },
      locals: {},
    };

    expect(await bsb.middleware.onRequest(event)).toBeUndefined();
    current = event;

    try {
      return (await bsb.require()).bsb.auth.kind;
    } finally {
      current = undefined;
      bsb.middleware.onBeforeResponse(event);
    }
  },
};

const expected: Record<CommunityAdapter, unknown> = {
  astro: "user",
  edge: "user",
  elysia: "user",
  h3: "user",
  "h3/v1": "user",
  nestjs: "user",
  node: "user",
  nuxt: [{ handler: "#better-supabase/middleware", middleware: true }],
  "solid-start": "user",
};

describe("community adapters", () => {
  // SAFETY: Object.keys of a const object returns exactly its keys.
  it.each(Object.keys(COMMUNITY_ADAPTERS) as CommunityAdapter[])(
    "%s serves a signed-in request",
    async (adapter) => {
      expect(await smokes[adapter]()).toEqual(expected[adapter]);
    },
  );
});
