// oxlint-disable-next-line import/no-unassigned-import -- installs Reflect.getMetadata, which Nest decorators write to.
import "reflect-metadata";
import type { AddressInfo } from "node:net";

import { HttpException } from "@nestjs/common";
import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { afterEach, describe, expect, it } from "vitest";

import { DbException, dbError } from "../../src/core/errors.ts";
import {
  contextOf,
  Ctx,
  type ExecutionContextLike,
  guard,
  problemFilter,
  toNestMiddleware,
} from "../../src/nestjs/index.ts";
import { withBetterSupabase } from "../../src/server/composite.ts";
import { server, signer, USER } from "../fixtures/test-server.ts";

const closers: (() => Promise<void>)[] = [];
afterEach(async () => {
  await Promise.all(closers.splice(0).map((close) => close()));
});

async function listen(
  route: (req: IncomingMessage, res: ServerResponse) => Promise<void>,
): Promise<string> {
  const middleware = toNestMiddleware([
    withBetterSupabase(server, { allow: ["user", "anon"] }),
  ]);
  const http = createServer((req, res) => {
    middleware(req, res, (error) => {
      if (error) {
        res.statusCode = 500;
        res.end();
        return;
      }
      void route(req, res);
    });
  });
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
  return `http://127.0.0.1:${(http.address() as AddressInfo).port}`;
}

const hostOf = (req: object, res: object): ExecutionContextLike => ({
  switchToHttp: () => ({ getRequest: () => req, getResponse: () => res }),
});

const bearer = async (role: string) => ({
  authorization: `Bearer ${await signer.sign({ sub: USER, app_metadata: { role } })}`,
});

describe("better-supabase/nestjs", () => {
  it("stores the contributions for @Ctx() and the guard", async () => {
    class Notes {
      list(): void {}
    }
    Ctx("bs")(Notes.prototype, "list", 0);
    const args = Reflect.getMetadata(
      "__routeArguments__",
      Notes,
      "list",
    ) as Record<
      string,
      {
        factory: (data: unknown, ctx: ExecutionContextLike) => unknown;
        data: unknown;
      }
    >;
    const [param] = Object.values(args);

    const admins = guard({ roles: ["admin"] });
    const url = await listen(async (req, res) => {
      const fastifyRequest = { raw: req };
      const host = hostOf(fastifyRequest, { raw: res });
      const bs = param?.factory(param.data, host) as { auth: { kind: string } };
      try {
        await admins.canActivate(host);
        res.end(`${bs.auth.kind}:${contextOf(fastifyRequest) ? "ctx" : ""}`);
      } catch (error) {
        const status = error instanceof HttpException ? error.getStatus() : 500;
        res.statusCode = status;
        res.end(
          JSON.stringify(
            error instanceof HttpException ? error.getResponse() : {},
          ),
        );
      }
    });

    expect(
      await (await fetch(url, { headers: await bearer("admin") })).text(),
    ).toBe("user:ctx");
    const refused = await fetch(url, { headers: await bearer("member") });
    expect(refused.status).toBe(403);
    expect(await refused.json()).toMatchObject({ code: "MISSING_ROLE" });
  });

  it("redirects refused callers to signIn through HttpException", async () => {
    const signedIn = guard({ signIn: "/sign-in" });
    const url = await listen(async (req, res) => {
      try {
        await signedIn.canActivate(hostOf(req, res));
        res.end("ok");
      } catch (error) {
        res.statusCode =
          error instanceof HttpException ? error.getStatus() : 500;
        res.end();
      }
    });
    const response = await fetch(`${url}/notes`, { redirect: "manual" });
    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toMatch(
      /\/sign-in\?next=%2Fnotes$/,
    );
  });

  it("answers DbExceptions with Problem Details and other errors like Nest", async () => {
    const filter = problemFilter({ expose: true });
    const answer = filter.catch.bind(filter);
    const url = await listen((req, res) => {
      const thrown =
        req.url === "/conflict"
          ? new DbException(dbError("conflict", "Taken"))
          : req.url === "/http"
            ? new HttpException("Nope", 418)
            : new Error("boom");
      answer(thrown, hostOf(req, res));
      return Promise.resolve();
    });
    const conflict = await fetch(`${url}/conflict`);
    expect(conflict.status).toBe(409);
    expect(conflict.headers.get("content-type")).toBe(
      "application/problem+json",
    );
    const teapot = await fetch(`${url}/http`);
    expect(teapot.status).toBe(418);
    expect(await teapot.json()).toEqual({ statusCode: 418, message: "Nope" });
    expect((await fetch(url)).status).toBe(500);
  });

  it("throws a setup error when the middleware did not run", async () => {
    await expect(guard().canActivate(hostOf({}, {}))).rejects.toThrow(
      /toNestMiddleware/,
    );
  });
});
