import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { describe, expect, it, vi } from "vitest";

import type { HonoEnv } from "../../src/hono/index.ts";
import type { Functions, Models } from "../fixtures/generated-camel.ts";

import { defineAuthorizer } from "../../src/core/authorizer.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { DbException, dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createHono, defineAction } from "../../src/hono/index.ts";
import { defineBucket } from "../../src/storage/index.ts";
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

describe("bsb.app()", () => {
  it("installs bsb.onError, and Env carries only a type", async () => {
    const bsb = createHono(defineSupabase(schema), { env });
    expect(bsb.Env).toBeUndefined();

    const app = bsb
      .app()
      .get("/thrown", () => {
        throw new DbException(dbError("not_found", "Gone"));
      })
      .get("/teapot", () => {
        throw new HTTPException(418, { message: "Short and stout" });
      });

    const thrown = await app.request("/thrown");
    expect(thrown.status).toBe(404);
    expect(thrown.headers.get("content-type")).toContain(
      "application/problem+json",
    );
    expect((await app.request("/teapot")).status).toBe(418);
  });
});

describe("createHono", () => {
  const betterSupabase = defineSupabase(schema);
  const refresh = vi.fn<typeof fetch>();

  const bsb = createHono(betterSupabase, {
    env,
    auth: { jwks: signer.jwks, fetch: refresh },
  });

  type Env = HonoEnv<Models, Functions, unknown>;

  const app = new Hono<Env>()
    .onError(bsb.onError)
    .use("/public/*", bsb.middleware({ allow: ["user", "anon"] }))
    .use("/api/*", bsb.middleware())
    .get("/public/who", (c) => c.json({ kind: c.var.auth.kind }))
    .get(
      "/api/me",
      bsb.handler((_c, ctx) =>
        ok({ id: ctx.auth.kind === "user" ? ctx.auth.user.id : null }),
      ),
    )
    .get(
      "/api/conflict",
      bsb.handler(() => err(dbError("conflict", "Taken"))),
    )
    .get(
      "/api/empty",
      bsb.handler(() => undefined),
    )
    .get("/api/thrown", () => {
      throw new DbException(dbError("not_found", "Gone"));
    })
    .get("/api/crash", () => {
      throw new Error("secret detail");
    })
    .get("/api/teapot", () => {
      throw new HTTPException(418, { message: "Short and stout" });
    });

  const call = async (path: string, token?: string) =>
    app.request(
      path,
      token ? { headers: { authorization: `Bearer ${token}` } } : {},
    );

  it("guards routes and exposes the caller on c.var", async () => {
    expect(await (await call("/public/who")).json()).toEqual({ kind: "anon" });
    const anonymous = await call("/api/me");
    expect(anonymous.status).toBe(401);
    expect(anonymous.headers.get("content-type")).toBe(
      "application/problem+json",
    );
    expect(await anonymous.json()).toMatchObject({
      kind: "unauthorized",
      instance: "/api/me",
    });

    const token = await signer.sign({ sub: USER });
    expect(await (await call("/api/me", token)).json()).toEqual({ id: USER });
    expect((await call("/api/me", "not-a-jwt")).status).toBe(401);
  });

  it("maps Results, undefined and thrown errors", async () => {
    const token = await signer.sign({ sub: USER });
    expect((await call("/api/conflict", token)).status).toBe(409);
    expect((await call("/api/empty", token)).status).toBe(204);
    const thrown = await call("/api/thrown", token);
    expect(thrown.status).toBe(404);
    expect(await thrown.json()).toMatchObject({ kind: "not_found" });
    const crash = await call("/api/crash", token);
    expect(crash.status).toBe(500);
    expect(JSON.stringify(await crash.json())).not.toContain("secret detail");
    const teapot = await call("/api/teapot", token);
    expect(teapot.status).toBe(418);
    expect(await teapot.text()).toBe("Short and stout");
  });

  it("explains a missing middleware", async () => {
    const bare = new Hono<Env>()
      .onError(bsb.onError)
      .route("/customers", bsb.resource("customers"));

    const response = await bare.request("/customers");
    expect(response.status).toBe(500);
  });

  it("only mounts item routes for single-column keys", () => {
    const routes = bsb.resource("customers").routes.map((route) => route.path);
    expect(routes).toEqual(["/", "/:id", "/*"]);
    expect(() => bsb.resource("nope" as never)).toThrow('Unknown table "nope"');
  });
});

describe("bsb.require()", () => {
  const bsb = createHono(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks },
  });

  const app = bsb
    .app()
    .use("*", bsb.middleware({ allow: ["user", "anon"] }))
    .get("/open", (c) => c.json(c.var.session.kind))
    .get(
      "/admin",
      bsb.require({
        authorize: (session) =>
          session.kind === "user" &&
          session.claims.app_metadata?.["role"] === "admin",
      }),
      (c) => c.json("ok"),
    )
    .get("/scoped", bsb.require({ requireOrganization: true }), (c) =>
      c.json(c.var.tenant),
    );

  const call = async (path: string, role?: string) =>
    app.request(
      path,
      role
        ? {
            headers: {
              authorization: `Bearer ${await signer.sign({ sub: USER, app_metadata: { role } })}`,
            },
          }
        : {},
    );

  it("guards a route after the middleware", async () => {
    expect(await (await call("/open")).json()).toBe("anon");
    expect((await call("/admin")).status).toBe(401);
    expect((await call("/admin", "member")).status).toBe(403);
    expect(await (await call("/admin", "admin")).json()).toBe("ok");
    const scoped = await call("/scoped", "admin");
    expect(scoped.status).toBe(403);
    expect(await scoped.json()).toMatchObject({ code: "NO_TENANT" });
  });
});

describe("authorizer", () => {
  const authorizer = defineAuthorizer<"invite" | "export">({
    name: "test",
    key: (ref) => ref,
    evaluate: (request) =>
      request.subject.properties?.["role"] === "authenticated" &&
      request.action === "export"
        ? { outcome: "granted" }
        : request.action === "invite"
          ? { outcome: "approval-required", approval: { id: "apr_9" } }
          : { outcome: "denied" },
  });

  const bsb = createHono(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks },
    authorizer,
  });

  const app = bsb
    .app()
    .use("*", bsb.middleware())
    .post("/invites", bsb.require({ permission: "invite" }), (c) =>
      c.json("ok"),
    )
    .route(
      "/customers",
      bsb.resource("customers", {
        actions: {
          export: defineAction({
            method: "GET",
            path: "/export",
            permission: "export",
            handler: (ctx) => ({ table: ctx.table }),
          }),
          send: {
            method: "POST",
            path: "/{id}/send",
            handler: (ctx, { id }) => ({ id, user: ctx.context.actor?.id }),
          },
        },
      }),
    );

  const call = async (path: string, method = "GET") =>
    app.request(path, {
      method,
      headers: { authorization: `Bearer ${await signer.sign({ sub: USER })}` },
    });

  it("routes resource actions before item paths", async () => {
    const exported = await call("/customers/export");
    expect(exported.status).toBe(200);
    expect(await exported.json()).toEqual({ table: "customers" });
    const sent = await call("/customers/c1/send", "POST");
    expect(await sent.json()).toEqual({ id: "c1", user: USER });
    expect((await call("/customers/c1/send")).status).toBe(405);
    expect(
      bsb
        .resource("customers", {
          actions: {
            ping: { method: "POST", path: "/ping", handler: () => undefined },
          },
        })
        .routes.map((route) => route.path),
    ).toEqual(["/", "/ping", "/:id", "/*"]);
  });

  it("matches through the shared resource router", async () => {
    const malformed = await call("/customers/%E0%A4%A");
    expect(malformed.status).toBe(400);
    expect(await malformed.json()).toMatchObject({ kind: "invalid_input" });

    const unknown = await call("/customers/c1/unknown");
    expect(unknown.status).toBe(404);
    expect(unknown.headers.get("content-type")).toContain(
      "application/problem+json",
    );

    expect((await call("/customers/export", "PATCH")).status).toBe(405);
  });

  it("refuses a route whose permission needs an approval", async () => {
    const response = await call("/invites", "POST");
    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({
      code: "APPROVAL_REQUIRED",
      permission: "invite",
      approval: { id: "apr_9" },
    });
  });

  it("types permissions from the authorizer", () => {
    // @ts-expect-error "delete" is not a permission of this authorizer
    bsb.require({ permission: "delete" });
    // @ts-expect-error "delete" is not a permission of this authorizer
    bsb.resource("customers", { permissions: { list: "delete" } });
  });
});

describe("createHono buckets", () => {
  it("reads db.$buckets in a handler", async () => {
    const logos = defineBucket({ id: "logos", path: "{userId}/logo.webp" });

    const bsb = createHono(defineSupabase(schema).buckets({ logos }), {
      env,
      auth: { jwks: signer.jwks },
    });

    const app = new Hono<typeof bsb.Env>()
      .use(bsb.middleware({ allow: ["anon"] }))
      .get(
        "/",
        bsb.handler((_c, ctx) => ok({ id: ctx.db.$buckets.logos.bucket.id })),
      );

    const response = await app.request("/");
    expect(await response.json()).toEqual({ id: "logos" });
  });
});

describe("createHono options", () => {
  it("answers a preflight and adds CORS headers with cors", async () => {
    const bsb = createHono(defineSupabase(schema), {
      env,
      cors: { origin: "https://app.example.com" },
    });

    const app = bsb.app().get("/ping", (c) => c.text("pong"));

    const preflight = await app.request("/ping", {
      method: "OPTIONS",
      headers: {
        origin: "https://app.example.com",
        "access-control-request-method": "GET",
      },
    });

    expect(preflight.status).toBeLessThan(300);
    expect(preflight.headers.get("access-control-allow-origin")).toBe(
      "https://app.example.com",
    );

    const reply = await app.request("/ping", {
      headers: { origin: "https://app.example.com" },
    });

    expect(await reply.text()).toBe("pong");
    expect(reply.headers.get("access-control-allow-origin")).toBe(
      "https://app.example.com",
    );
  });

  it("takes an existing server instead of building one", () => {
    const definition = defineSupabase(schema);
    const first = createHono(definition, { env });
    const second = createHono(definition, { server: first });
    // oxlint-disable-next-line typescript/unbound-method -- compares the shared function, never calls it.
    expect(second.contextFor).toBe(first.contextFor);
  });
});
