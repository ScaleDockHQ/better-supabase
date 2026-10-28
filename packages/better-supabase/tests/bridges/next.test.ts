import type { Entry } from "@supabase/middleware";

import { defineMiddleware } from "@supabase/middleware";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { NextCookieWrite } from "../../src/bridges/next.ts";
import type { ServerOptions } from "../../src/server/server-types.ts";
import type { AdapterRun } from "../../src/testing/adapter.ts";

import {
  actionRequest,
  NextActionRejected,
  nextAction,
  parseSetCookie,
  toNextRoute,
} from "../../src/bridges/next.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { unexpectedResponse } from "../../src/server/adapter.ts";
import { withBetterSupabase } from "../../src/server/index.ts";
import { respond } from "../../src/server/respond.ts";
import { testAdapter } from "../../src/testing/adapter.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

type Bs = Parameters<AdapterRun>[0];

async function answer(run: AdapterRun, bsb: Bs, request: Request) {
  const instance = new URL(request.url).pathname;

  try {
    return await respond(() => run(bsb), { instance, expose: false });
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

const routeContext = { params: Promise.resolve({}) };

const setsCookie: Entry<Record<never, never>> =
  (next) => async (request, ctx) => {
    const response = await next(request, ctx);
    const headers = new Headers(response.headers);
    headers.append(
      "set-cookie",
      "sb-test-auth-token=base64-abc; Path=/; Max-Age=60; HttpOnly; SameSite=Lax",
    );

    return new Response(response.body, { status: response.status, headers });
  };

const rejects: Entry<Record<never, never>> = () => async () =>
  new Response(null, { status: 401 });

const tenant = defineMiddleware({
  key: "tenant",
  run: () => async (request) => ({
    tenant: request.headers.get("x-tenant") ?? "none",
  }),
});

function fakeIO(incoming: HeadersInit) {
  const written: NextCookieWrite[] = [];

  return {
    written,
    io: {
      headers: async () => new Headers(incoming),
      setCookie: async (write: NextCookieWrite) => {
        written.push(write);
      },
    },
  };
}

describe("toNextRoute", () => {
  it("passes testAdapter", async () => {
    await testAdapter("toNextRoute", {
      betterSupabase,
      serve: (server, run, { allow, waitUntil }) => {
        const handler = toNextRoute(
          entriesFor(server, allow, waitUntil),
          (request, ctx) => answer(run, ctx.bsb, request),
        );

        return (request) => handler(request, routeContext);
      },
    });
  });

  it("sends a returned value as JSON and undefined as 204", async () => {
    const json = toNextRoute([tenant()], (_request, ctx) => ({
      tenant: ctx.tenant,
    }));

    const empty = toNextRoute([tenant()], () => undefined);

    const request = new Request("https://app.test/api", {
      headers: { "x-tenant": "acme" },
    });

    expect(await (await json(request, routeContext)).json()).toEqual({
      tenant: "acme",
    });
    expect((await empty(request, routeContext)).status).toBe(204);
  });

  it("hands the route params through and lets entries see the response", async () => {
    const handler = toNextRoute(
      [setsCookie],
      async (_request, _ctx, { params }) => Response.json(await params),
    );

    const response = await handler(new Request("https://app.test/api/7"), {
      params: Promise.resolve({ id: "7" }),
    });

    expect(await response.json()).toEqual({ id: "7" });
    expect(response.headers.getSetCookie()).toHaveLength(1);
  });
});

describe("toNextAction", () => {
  it("runs the action with the contributions and writes the entries' cookies", async () => {
    const { io, written } = fakeIO({ host: "app.test", "x-tenant": "acme" });

    const action = nextAction(
      [setsCookie, tenant()],
      async (ctx, suffix: string) => `${ctx.tenant}-${suffix}`,
      io,
    );

    expect(await action("1")).toBe("acme-1");
    expect(written).toEqual([
      {
        name: "sb-test-auth-token",
        value: "base64-abc",
        path: "/",
        maxAge: 60,
        httpOnly: true,
        sameSite: "lax",
      },
    ]);
  });

  it("throws NextActionRejected when an entry answers first", async () => {
    const { io } = fakeIO({ host: "app.test" });
    let ran = false;

    const action = nextAction(
      [rejects],
      async () => {
        ran = true;
      },
      io,
    );

    const error = await action().catch((cause: unknown) => cause);

    expect(error).toBeInstanceOf(NextActionRejected);
    expect((error as NextActionRejected).status).toBe(401);
    expect(ran).toBe(false);
  });

  it("builds a POST to the calling page from the incoming headers", () => {
    const request = actionRequest(
      new Headers({
        host: "app.test",
        "x-forwarded-proto": "http",
        "next-url": "/notes",
        cookie: "a=1",
      }),
    );

    expect(request.method).toBe("POST");
    expect(request.url).toBe("http://app.test/notes");
    expect(request.headers.get("cookie")).toBe("a=1");
  });
});

describe("parseSetCookie", () => {
  it("reads every attribute Next.js cookies().set takes", () => {
    expect(
      parseSetCookie(
        "a=b%20c; Domain=.app.test; Path=/x; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Secure; SameSite=None; Partitioned",
      ),
    ).toEqual({
      name: "a",
      value: "b c",
      domain: ".app.test",
      path: "/x",
      expires: new Date("Wed, 21 Oct 2026 07:28:00 GMT"),
      secure: true,
      sameSite: "none",
      partitioned: true,
    });
  });

  it("skips a header without a name", () => {
    expect(parseSetCookie("=value")).toBeUndefined();
  });
});

describe("bridges", () => {
  it("never import the deprecated @supabase/server adapters", async () => {
    const directory = join(import.meta.dirname, "../../src/bridges");
    const files = await readdir(directory);

    const offenders = await Promise.all(
      files.map(async (file) =>
        /@supabase\/server\/adapters/u.test(
          await readFile(join(directory, file), "utf-8"),
        )
          ? file
          : undefined,
      ),
    );

    expect(offenders.filter(Boolean)).toEqual([]);
  });
});
