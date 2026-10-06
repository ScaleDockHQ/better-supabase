import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException, dbError } from "../../src/core/errors.ts";
import { ok } from "../../src/core/result.ts";
import { createEdge } from "../../src/edge/index.ts";
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

describe("createEdge", () => {
  const betterSupabase = defineSupabase(schema);
  const bs = createEdge(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never },
    cors: { origin: ["https://app.test"] },
  });

  const request = async (
    path: string,
    init: { method?: string; token?: string; origin?: string } = {},
  ) =>
    new Request(`https://project.functions.test${path}`, {
      method: init.method ?? "GET",
      headers: {
        ...(init.token ? { authorization: `Bearer ${init.token}` } : {}),
        ...(init.origin ? { origin: init.origin } : {}),
        ...(init.method === "OPTIONS"
          ? { "access-control-request-method": "POST" }
          : {}),
      },
    });

  it("wraps a handler with auth, Results and CORS", async () => {
    const serve = bs.handler((_request, ctx) =>
      ok({ id: ctx.auth.kind === "user" ? ctx.auth.user.id : null }),
    );
    const token = await signer.sign({ sub: USER });
    const response = await serve(
      await request("/hello", { token, origin: "https://app.test" }),
    );
    expect(await response.json()).toEqual({ id: USER });
    expect(response.headers.get("access-control-allow-origin")).toBe(
      "https://app.test",
    );
    expect(response.headers.get("vary")).toBe("Origin");

    const anonymous = await serve(
      await request("/hello", { origin: "https://evil.test" }),
    );
    expect(anonymous.status).toBe(401);
    expect(anonymous.headers.get("access-control-allow-origin")).toBeNull();

    const preflight = await serve(
      await request("/hello", {
        method: "OPTIONS",
        origin: "https://app.test",
      }),
    );
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("access-control-allow-headers")).toContain(
      "apikey",
    );
  });

  it("hands sends a handler started to waitUntil", async () => {
    const token = await signer.sign({ sub: USER });
    const kept: Promise<unknown>[] = [];
    let release: () => void = () => undefined;
    const serve = bs.handler(() => {
      betterSupabase.events.track(
        new Promise<void>((resolve) => {
          release = resolve;
        }),
      );
    });
    const response = await serve(await request("/x", { token }), undefined, {
      waitUntil: (promise) => void kept.push(promise),
    });
    expect(response.status).toBe(204);
    expect(kept).toHaveLength(1);
    let done = false;
    void kept[0]!.then(() => {
      done = true;
    });
    await Promise.resolve();
    expect(done).toBe(false);
    release();
    await kept[0];
    expect(done).toBe(true);

    const quiet = bs.handler(() => undefined);
    await quiet(await request("/x", { token }), undefined, {
      waitUntil: (promise) => void kept.push(promise),
    });
    expect(kept).toHaveLength(1);

    const global: Promise<unknown>[] = [];
    const deno = createEdge(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
      waitUntil: (promise) => void global.push(promise),
    }).handler(() => {
      betterSupabase.events.track(
        new Promise((resolve) => {
          setTimeout(resolve, 5);
        }),
      );
    });
    await deno(await request("/x", { token }));
    expect(global).toHaveLength(1);
    await global[0];
  });

  it("maps thrown errors without leaking details", async () => {
    const token = await signer.sign({ sub: USER });
    const missing = bs.handler(() => {
      throw new DbException(dbError("not_found", "Gone"));
    });
    expect((await missing(await request("/x", { token }))).status).toBe(404);
    const crash = bs.handler(() => {
      throw new Error("secret detail");
    });
    const response = await crash(await request("/x", { token }));
    expect(response.status).toBe(500);
    expect(await response.text()).not.toContain("secret detail");
  });

  it("routes resources under a base path", async () => {
    const serve = bs.resources({ customers: true }, { basePath: "/api" });
    const token = await signer.sign({ sub: USER });
    expect((await serve(await request("/api/nope", { token }))).status).toBe(
      404,
    );
    expect(
      (await serve(await request("/api/customers/a/b", { token }))).status,
    ).toBe(404);
    expect(
      (await serve(await request("/other/customers", { token }))).status,
    ).toBe(404);
    expect(
      (
        await serve(
          await request("/api/customers/c1", { method: "PUT", token }),
        )
      ).status,
    ).toBe(405);
    expect((await serve(await request("/api/customers"))).status).toBe(401);
    // Unknown routes answer before auth: no token still gets a 404.
    expect((await serve(await request("/api/nope"))).status).toBe(404);
    expect(
      (await serve(await request("/api/customers/%E0%A4%A", { token }))).status,
    ).toBe(400);
  });

  it("allows any origin with cors: true", async () => {
    const open = createEdge(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
      cors: true,
    });
    const response = await open.handler(() => undefined)(
      await request("/x", { origin: "https://elsewhere.test" }),
    );
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
    expect(response.headers.get("vary")).toBeNull();
  });
});
