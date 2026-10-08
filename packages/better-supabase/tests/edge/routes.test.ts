import { describe, expect, it } from "vitest";

import { ok } from "../../src/core/result.ts";
import { createEdge } from "../../src/edge/index.ts";
import { compileRoutes, matchRoute } from "../../src/edge/routes.ts";
import {
  betterSupabase,
  env,
  requestAs,
  signer,
  USER,
} from "../fixtures/test-server.ts";

const bs = createEdge(betterSupabase, {
  env,
  auth: { jwks: signer.jwks as never },
  prefetchJwks: false,
});

const handler = bs.routes(
  {
    "GET /me": (_request, ctx) =>
      ok({ id: ctx.session.kind === "user" ? ctx.session.user.id : null }),
    "GET /notes/:id": (_request, ctx) => ok(ctx.params),
    "GET /notes/new": () => ok("static"),
    "/files/*": (_request, ctx) => ok(ctx.params["*"]),
    "POST /invites": { requireTenant: true, handler: () => ok("sent") },
    "GET /public": { allow: ["anon", "user"], handler: () => ok("hi") },
  },
  { basePath: "/api" },
);

const at = async (path: string, init: RequestInit = {}, signedIn = true) =>
  handler(
    await requestAs(signedIn ? { role: "member" } : undefined, {
      ...init,
      url: `https://fn.test${path}`,
    }),
  );

describe("bs.routes", () => {
  it("routes by method and path, with params and the session", async () => {
    expect(await (await at("/api/me")).json()).toEqual({ id: USER });
    expect(await (await at("/api/notes/a%20b")).json()).toEqual({ id: "a b" });
    expect(await (await at("/api/notes/new")).json()).toBe("static");
    expect(
      await (await at("/api/files/a/b.png", { method: "PUT" })).json(),
    ).toBe("a/b.png");
    expect((await at("/api/me", { method: "HEAD" })).status).toBe(200);
  });

  it("answers 404 and 405 before auth", async () => {
    expect((await at("/api/missing", {}, false)).status).toBe(404);
    expect((await at("/elsewhere", {}, false)).status).toBe(404);
    const wrongMethod = await at("/api/me", { method: "DELETE" }, false);
    expect(wrongMethod.status).toBe(405);
    expect(wrongMethod.headers.get("allow")).toBe("GET");
  });

  it("applies the shared guard and each route's own", async () => {
    expect((await at("/api/me", {}, false)).status).toBe(401);
    expect(await (await at("/api/public", {}, false)).json()).toBe("hi");
    const invite = await at("/api/invites", { method: "POST" });
    expect(invite.status).toBe(403);
  });
});

describe("compileRoutes", () => {
  it("rejects keys without a path", () => {
    expect(() => compileRoutes({ "GET me": () => 1 })).toThrow(/METHOD \/path/);
  });

  it("returns none for an unknown path and skips bad escapes", () => {
    const routes = compileRoutes({ "GET /a/:id": () => 1 });
    expect(matchRoute(routes, "GET", "/b")).toBe("none");
    expect(matchRoute(routes, "GET", "/a/%E0%A4%A")).toBe("none");
  });
});
