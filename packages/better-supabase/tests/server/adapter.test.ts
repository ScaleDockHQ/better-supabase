import { os } from "@orpc/server";
import { RPCHandler } from "@orpc/server/fetch";
import { describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException, dbError } from "../../src/core/errors.ts";
import { err } from "../../src/core/result.ts";
import { createEdge } from "../../src/edge/index.ts";
import { createExpo } from "../../src/expo/index.ts";
import { createHono } from "../../src/hono/index.ts";
import { createMcp } from "../../src/mcp/index.ts";
import { createOrpc, type OrpcRequestContext } from "../../src/orpc/index.ts";
import {
  createServer,
  flushEvents,
  handle,
  PRIMARY_COOKIE,
  resolveToken,
} from "../../src/server/index.ts";
import { testAdapter } from "../../src/testing/adapter.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

describe("handle", () => {
  const betterSupabase = defineSupabase(schema);
  const server = createServer(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never },
    readUrl: "https://replica.test",
  });
  const request = (token?: string) =>
    new Request("https://api.test/notes", {
      headers: token ? { authorization: `Bearer ${token}` } : {},
    });

  it("runs as the caller and answers data as JSON", async () => {
    const token = await signer.sign({ sub: USER });
    const response = await handle(server, request(token), (ctx) =>
      ctx.auth.kind === "user" ? { id: ctx.auth.user.id } : null,
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ id: USER });
  });

  it("refuses callers the guard rejects without running the handler", async () => {
    const run = vi.fn();
    const response = await handle(server, request(), run);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({
      instance: "/notes",
      code: "MISSING_CREDENTIALS",
    });
    expect(run).not.toHaveBeenCalled();
  });

  it("answers Results and thrown errors as Problem Details", async () => {
    const options = { allow: ["anon"] as const };
    const failed = await handle(
      server,
      request(),
      () => err(dbError("conflict", "Taken")),
      options,
    );
    expect(failed.status).toBe(409);
    const thrown = await handle(
      server,
      request(),
      () => {
        throw new Error("secret detail");
      },
      { ...options, instance: "/custom" },
    );
    expect(thrown.status).toBe(500);
    const body = await thrown.text();
    expect(body).not.toContain("secret detail");
    expect(body).toContain("/custom");
    const exposed = await handle(
      server,
      request(),
      () => {
        throw new Error("secret detail");
      },
      { ...options, expose: true },
    );
    expect(await exposed.text()).toContain("secret detail");
  });

  it("lets rethrow see thrown errors before they become a 500", async () => {
    const control = new Error("NEXT_REDIRECT");
    await expect(
      handle(
        server,
        request(),
        () => {
          throw control;
        },
        {
          allow: ["anon"],
          rethrow: (cause) => {
            if (cause === control) throw control;
          },
        },
      ),
    ).rejects.toBe(control);
  });

  it("flushes event sends before rethrowing control flow", async () => {
    const control = new Error("NEXT_REDIRECT");
    const waitUntil = vi.fn();
    let release = (): void => undefined;
    await expect(
      handle(
        server,
        request(),
        () => {
          betterSupabase.events.track(
            new Promise<void>((resolve) => {
              release = resolve;
            }),
          );
          throw control;
        },
        {
          allow: ["anon"],
          waitUntil,
          rethrow: (cause) => {
            if (cause === control) throw control;
          },
        },
      ),
    ).rejects.toBe(control);
    expect(waitUntil).toHaveBeenCalledOnce();
    release();
  });

  it("applies the primary pin and flushes event sends", async () => {
    const waitUntil = vi.fn();
    let release = (): void => undefined;
    const response = await handle(
      server,
      request(),
      (ctx) => {
        ctx.replica?.pin();
        betterSupabase.events.track(
          new Promise<void>((resolve) => {
            release = resolve;
          }),
        );
        return { ok: 1 };
      },
      { allow: ["anon"], waitUntil, status: 201 },
    );
    expect(response.status).toBe(201);
    expect(response.headers.get("set-cookie")).toContain(`${PRIMARY_COOKIE}=`);
    expect(waitUntil).toHaveBeenCalledOnce();
    release();
  });
});

describe("ctx.cookies", () => {
  it("lists the primary pin after a write, for cookie-jar frameworks", async () => {
    const server = createServer(defineSupabase(schema), {
      env,
      readUrl: "https://replica.test",
    });
    const ctx = await server.context(new Request("https://api.test/"));
    expect(ctx.cookies()).toEqual([]);
    ctx.replica?.pin();
    expect(ctx.cookies()).toEqual([
      expect.objectContaining({
        name: PRIMARY_COOKIE,
        options: expect.objectContaining({ httpOnly: true, path: "/" }),
      }),
    ]);
  });
});

describe("flushEvents", () => {
  it("calls waitUntil only while sends are pending", async () => {
    const betterSupabase = defineSupabase(schema);
    const waitUntil = vi.fn();
    flushEvents(betterSupabase, waitUntil);
    expect(waitUntil).not.toHaveBeenCalled();
    betterSupabase.events.track(Promise.resolve());
    flushEvents(betterSupabase, waitUntil);
    flushEvents(betterSupabase, undefined);
    expect(waitUntil).toHaveBeenCalledOnce();
    await betterSupabase.events.settled();
  });
});

describe("resolveToken", () => {
  const server = createServer(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks as never },
  });

  it("verifies a bare token and treats a missing one as anon", async () => {
    const auth = await resolveToken(server, await signer.sign({ sub: USER }));
    expect(auth.kind === "user" && auth.user.id).toBe(USER);
    expect((await resolveToken(server, undefined)).kind).toBe("anon");
    expect((await resolveToken(server, "not-a-jwt")).kind).toBe("invalid");
  });
});

describe("testAdapter", () => {
  const betterSupabase = defineSupabase(schema);

  it("passes for createEdge", async () => {
    await testAdapter("edge", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) =>
        createEdge(betterSupabase, { ...server, waitUntil }).handler(
          (_request, ctx) => run(ctx),
          { allow },
        ),
    });
  });

  it("passes for createExpo", async () => {
    await testAdapter("expo", {
      betterSupabase,
      // Expo's server runs on Node, which has no waitUntil to call.
      serve: (server, run, { allow, waitUntil }) => {
        const handler = createExpo(betterSupabase, server).handler(
          (_request, ctx) => run(ctx),
          { allow },
        );
        return async (request) => {
          const response = await handler(request);
          flushEvents(betterSupabase, waitUntil);
          return response;
        };
      },
    });
  });

  it("passes for createHono", async () => {
    await testAdapter("hono", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const bs = createHono(betterSupabase, { ...server, waitUntil });
        const app = bs.app();
        app.use(bs.middleware({ allow }));
        app.get(
          "*",
          bs.handler((_c, ctx) => run(ctx)),
        );
        return async (request) => app.fetch(request);
      },
    });
  });

  it("passes for createOrpc", async () => {
    await testAdapter("orpc", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const bs = createOrpc(betterSupabase, { ...server, waitUntil });
        const procedure = os
          .$context<OrpcRequestContext>()
          .use(bs.middleware({ allow }))
          .handler(({ context }) => bs.unwrap(run(context.bs)));
        const fetch = bs.fetchHandler(new RPCHandler({ procedure }));
        return (request) =>
          fetch(
            new Request(new URL("/procedure", request.url), {
              method: "POST",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({ json: null }),
            }),
          );
      },
    });
  });

  it("passes for createMcp, with errors in tool results", async () => {
    await testAdapter("mcp", {
      betterSupabase,
      errorsInBody: true,
      cookies: false,
      serve: (server, run, { allow, waitUntil }) => {
        const mcp = createMcp(betterSupabase, {
          ...server,
          waitUntil,
          allow,
          name: "block",
          version: "1.0.0",
        }).tool({
          name: "run",
          description: "Runs the module.",
          run: (_a, ctx) => run(ctx),
        });
        return (request) =>
          mcp.fetch(
            new Request(request.url, {
              method: "POST",
              headers: {
                "content-type": "application/json",
                accept: "application/json, text/event-stream",
              },
              body: JSON.stringify({
                jsonrpc: "2.0",
                id: 1,
                method: "tools/call",
                params: { name: "run", arguments: {} },
              }),
            }),
          );
      },
    });
  });

  it("reports an adapter that leaks errors and skips the cookies", async () => {
    const failure = await testAdapter("leaky", {
      betterSupabase,
      serve: (server, run) => async (request) => {
        const ctx = await createServer(betterSupabase, server).context(request);
        try {
          return Response.json(await run(ctx));
        } catch (cause) {
          const status =
            cause instanceof DbException ? cause.error.status : 500;
          return new Response(String(cause), { status });
        }
      },
    }).catch((cause: unknown) => cause);
    expect(failure).toBeInstanceOf(ConformanceError);
    const failed = (failure as ConformanceError).report.checks
      .filter((check) => !check.ok)
      .map((check) => check.name);
    expect(failed).toEqual([
      "refuses a caller the guard rejects",
      "hides the message of an unexpected error",
      "applies the context's cookies",
      "hands pending event sends to waitUntil",
    ]);
  });
});
