import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException, dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { type HonoEnv, createHono } from "../../src/hono/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import {
  type Functions,
  type Models,
  schema,
} from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

describe("createHono", () => {
  const betterSupabase = defineSupabase(schema);
  const refresh = vi.fn<typeof fetch>();
  const bs = createHono(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never, fetch: refresh },
  });
  type Env = HonoEnv<Models, Functions, unknown>;

  const app = new Hono<Env>()
    .onError(bs.onError)
    .use("/public/*", bs.middleware({ allow: ["user", "anon"] }))
    .use("/api/*", bs.middleware())
    .get("/public/who", (c) => c.json({ kind: c.var.auth.kind }))
    .get(
      "/api/me",
      bs.handler((_c, ctx) =>
        ok({ id: ctx.auth.kind === "user" ? ctx.auth.user.id : null }),
      ),
    )
    .get(
      "/api/conflict",
      bs.handler(() => err(dbError("conflict", "Taken"))),
    )
    .get(
      "/api/empty",
      bs.handler(() => undefined),
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
      .onError(bs.onError)
      .route("/customers", bs.resource("customers"));
    const response = await bare.request("/customers");
    expect(response.status).toBe(500);
  });

  it("only mounts item routes for single-column keys", () => {
    const routes = bs.resource("customers").routes.map((route) => route.path);
    expect(routes).toEqual(["/", "/:id"]);
    expect(() => bs.resource("nope" as never)).toThrow('Unknown table "nope"');
  });
});
