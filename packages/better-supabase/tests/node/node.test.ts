import type { AddressInfo } from "node:net";

import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { PassThrough } from "node:stream";
import { afterEach, describe, expect, it } from "vitest";

import { DbException, dbError } from "../../src/core/errors.ts";
import {
  type ExpressResponse,
  type FastifyReplyLike,
  type FastifyRequestLike,
  fastifyGuard,
  guard,
  type KoaContextLike,
  koaGuard,
  problemErrorHandler,
  toExpress,
  toFastify,
  toKoa,
  toNodeHandler,
  toWebHeaders,
} from "../../src/node/index.ts";
import { withBetterSupabase } from "../../src/server/composite.ts";
import { withServerTiming } from "../../src/server/entries/timing.ts";
import { server, signer, USER } from "../fixtures/test-server.ts";

const closers: (() => Promise<void>)[] = [];
afterEach(async () => {
  await Promise.all(closers.splice(0).map((close) => close()));
});

async function listen(
  listener: (req: IncomingMessage, res: ServerResponse) => void,
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
  const { port } = http.address() as AddressInfo;
  return `http://127.0.0.1:${port}`;
}

const bearer = async (role = "member") => ({
  authorization: `Bearer ${await signer.sign({ sub: USER, app_metadata: { role } })}`,
});

const entries = [
  withBetterSupabase(server, { allow: ["user", "anon"] }),
] as const;

describe("toWebHeaders", () => {
  it("drops pseudo-headers and keeps repeated values", () => {
    const headers = toWebHeaders({
      ":path": "/x",
      accept: "text/html",
      "x-many": ["a", "b"],
      skipped: undefined,
    });
    expect([...headers]).toEqual([
      ["accept", "text/html"],
      ["x-many", "a, b"],
    ]);
  });
});

describe("toNodeHandler", () => {
  it("runs the entries around the handler and streams the body", async () => {
    const url = await listen(
      toNodeHandler(
        [...entries, withServerTiming()],
        async (request, { bs }) => ({
          kind: bs.auth.kind,
          body: request.method === "POST" ? await request.text() : null,
        }),
      ),
    );
    const response = await fetch(`${url}/notes`, {
      method: "POST",
      headers: await bearer(),
      body: "hello",
    });
    expect(await response.json()).toEqual({ kind: "user", body: "hello" });
    expect(response.headers.get("server-timing")).toMatch(/dur=/);
  });

  it("answers a refused caller from the entries", async () => {
    const url = await listen(
      toNodeHandler(
        [withBetterSupabase(server, { allow: ["user"] })],
        () => "ok",
      ),
    );
    expect((await fetch(url)).status).toBe(401);
  });
});

describe("toExpress", () => {
  const app = (
    route: (
      req: IncomingMessage,
      res: ExpressResponse,
      next: (error?: unknown) => void,
    ) => void,
  ) =>
    listen((req, res) => {
      const response = Object.assign(res, { locals: {} });
      const fail = (error: unknown): void => {
        problemErrorHandler({ expose: true })(error, req, response, () => {
          res.statusCode = 500;
          res.end("unhandled");
        });
      };
      toExpress(entries)(req, response, (error) => {
        if (error) fail(error);
        else route(req, response, fail);
      });
    });

  it("puts the contributions on res.locals", async () => {
    const url = await app((_req, res) => {
      const bs = res.locals["bs"] as { auth: { kind: string } };
      res.end(bs.auth.kind);
    });
    expect(await (await fetch(url, { headers: await bearer() })).text()).toBe(
      "user",
    );
  });

  it("guards a route and maps thrown DbExceptions", async () => {
    const admins = guard({ roles: ["admin"] });
    const url = await app((req, res, next) => {
      admins(req, res, () => {
        if (req.url === "/throw")
          next(new DbException(dbError("conflict", "Taken")));
        else if (req.url === "/boom") next(new Error("boom"));
        else res.end("admin");
      });
    });
    expect((await fetch(url, { headers: await bearer("member") })).status).toBe(
      403,
    );
    expect(
      await (await fetch(url, { headers: await bearer("admin") })).text(),
    ).toBe("admin");
    const conflict = await fetch(`${url}/throw`, {
      headers: await bearer("admin"),
    });
    expect(conflict.status).toBe(409);
    expect(conflict.headers.get("content-type")).toBe(
      "application/problem+json",
    );
    const boom = await fetch(`${url}/boom`, { headers: await bearer("admin") });
    expect(await boom.text()).toBe("unhandled");
  });

  it("answers the entries' refusal before the route", async () => {
    const url = await listen((req, res) => {
      toExpress([withBetterSupabase(server, { allow: ["user"] })])(
        req,
        Object.assign(res, { locals: {} }),
        () => res.end("route"),
      );
    });
    expect((await fetch(url)).status).toBe(401);
  });
});

function fakeReply(raw: ServerResponse): FastifyReplyLike & {
  readonly state: { status: number; payload: unknown; sent: boolean };
} {
  const state = { status: 200, payload: undefined as unknown, sent: false };
  const reply = {
    raw,
    state,
    get sent() {
      return state.sent;
    },
    code(status: number) {
      state.status = status;
      return reply;
    },
    header(name: string, value: string | readonly string[]) {
      raw.setHeader(name, value);
      return reply;
    },
    getHeader: (name: string) => raw.getHeader(name),
    send(payload?: unknown) {
      state.payload = payload;
      state.sent = true;
      return reply;
    },
  };
  return reply;
}

describe("toFastify", () => {
  it("puts the contributions on request.locals and guards routes", async () => {
    const hook = toFastify(entries);
    const admins = fastifyGuard({ roles: ["admin"] });
    const seen: { kind?: string; status?: number } = {};
    const url = await listen((req, res) => {
      const request: FastifyRequestLike = { raw: req };
      const reply = fakeReply(res);
      void (async () => {
        await hook(request, reply);
        await admins(request, reply);
        const bs = request.locals?.["bs"] as { auth: { kind: string } };
        seen.kind = bs.auth.kind;
        seen.status = reply.state.status;
        res.statusCode = reply.state.status;
        res.end(reply.state.sent ? "refused" : "admin");
      })();
    });
    expect(
      await (await fetch(url, { headers: await bearer("admin") })).text(),
    ).toBe("admin");
    expect(seen.kind).toBe("user");
    const refused = await fetch(url, { headers: await bearer("member") });
    expect(refused.status).toBe(403);
  });

  it("sends the entries' short circuit as the reply", async () => {
    const hook = toFastify([withBetterSupabase(server, { allow: ["user"] })]);
    const url = await listen((req, res) => {
      const reply = fakeReply(res);
      void hook({ raw: req }, reply).then(() => {
        res.statusCode = reply.state.status;
        res.end();
      });
    });
    expect((await fetch(url)).status).toBe(401);
  });
});

function fakeKoa(req: IncomingMessage, res: ServerResponse): KoaContextLike {
  return {
    req,
    res,
    state: {},
    status: 404,
    body: undefined,
    set: (name, value) => {
      res.setHeader(name, value);
    },
    get response() {
      return {
        get: (name: string) => {
          const value = res.getHeader(name);
          return value === undefined
            ? ""
            : typeof value === "number"
              ? String(value)
              : value;
        },
      };
    },
  };
}

describe("toKoa", () => {
  it("puts the contributions on ctx.state, guards and maps DbExceptions", async () => {
    const middleware = toKoa(entries, { expose: true });
    const admins = koaGuard({ roles: ["admin"] });
    const url = await listen((req, res) => {
      const ctx = fakeKoa(req, res);
      void middleware(ctx, () =>
        admins(ctx, () => {
          if (req.url === "/throw")
            throw new DbException(dbError("conflict", "Taken"));
          const bs = ctx.state["bs"] as { auth: { kind: string } };
          ctx.status = 200;
          ctx.body = bs.auth.kind;
          return Promise.resolve();
        }),
      ).then(() => {
        res.statusCode = ctx.status;
        res.end(
          typeof ctx.body === "string" || ctx.body instanceof Buffer
            ? ctx.body
            : "",
        );
      });
    });
    expect(
      await (await fetch(url, { headers: await bearer("admin") })).text(),
    ).toBe("user");
    expect((await fetch(url, { headers: await bearer("member") })).status).toBe(
      403,
    );
    expect(
      (await fetch(`${url}/throw`, { headers: await bearer("admin") })).status,
    ).toBe(409);
  });

  it("rethrows errors that are not DbExceptions and answers short circuits", async () => {
    const ctx = fakeKoa(
      Object.assign(new PassThrough(), {
        headers: {},
        method: "GET",
        url: "/",
        complete: true,
      }) as unknown as IncomingMessage,
      {
        setHeader: () => undefined,
        getHeader: () => undefined,
      } as unknown as ServerResponse,
    );
    await expect(
      toKoa(entries)(ctx, () => Promise.reject(new Error("boom"))),
    ).rejects.toThrow("boom");
    const refusing = fakeKoa(ctx.req, ctx.res);
    await toKoa([withBetterSupabase(server, { allow: ["user"] })])(
      refusing,
      () => Promise.resolve(),
    );
    expect(refusing.status).toBe(401);
  });
});
