import type { Hono } from "hono";

import { withSupabase } from "@supabase/server/adapters/hono";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createHono } from "../../src/hono/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = "11111111-1111-4111-8111-111111111111";
const ADMIN = "22222222-2222-4222-8222-222222222222";
const signer = await createTestSigner();
const stranger = await createTestSigner();

const supabaseEnv = {
  url: PROJECT_URL,
  publishableKeys: { default: env.publishableKey },
  secretKeys: { default: "sb_secret_test" },
  jwks: signer.jwks as never,
};

describe("better-supabase/hono after @supabase/server's withSupabase", () => {
  const betterSupabase = defineSupabase(schema);
  /** Its own keys can't verify the token, so a 200 means it reused withSupabase's check. */
  const reusing = createHono(betterSupabase, {
    env,
    auth: { jwks: stranger.jwks as never },
  });
  const alone = createHono(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never },
  });

  const who = (bs: typeof alone) =>
    bs.handler((_c, ctx) => ({
      ok: true,
      data: {
        auth: ctx.auth.kind === "user" ? ctx.auth.claims : ctx.auth.kind,
        actor: ctx.db.$context.actor,
      },
      error: null,
    }));

  const combined = reusing
    .app()
    .use("*", withSupabase({ auth: "user", env: supabaseEnv }))
    .use("*", reusing.middleware())
    .get("/who", who(reusing));
  const own = alone.app().use("*", alone.middleware()).get("/who", who(alone));
  const skipped = reusing
    .app()
    .use("*", reusing.middleware())
    .get("/who", who(reusing));

  const call = (app: { request: Hono["request"] }, token: string) =>
    app.request("/who", { headers: { authorization: `Bearer ${token}` } });

  it("gives the same ctx.auth and actor as resolving the token itself", async () => {
    const token = await signer.sign({
      sub: USER,
      iss: `${PROJECT_URL}/auth/v1`,
      act: { sub: ADMIN },
    });
    const reused = await call(combined, token);
    expect(reused.status).toBe(200);
    const body = await reused.json();
    expect(body).toEqual(await (await call(own, token)).json());
    expect(body).toMatchObject({
      auth: { sub: USER },
      actor: { id: USER, kind: "user", impersonator: ADMIN },
    });
  });

  it("verifies the token itself when withSupabase didn't run, or the issuer differs", async () => {
    const token = await signer.sign({
      sub: USER,
      iss: `${PROJECT_URL}/auth/v1`,
    });
    expect((await call(skipped, token)).status).toBe(401);
    const foreign = await signer.sign({
      sub: USER,
      iss: "https://elsewhere.test/auth/v1",
    });
    expect((await call(combined, foreign)).status).toBe(401);
  });
});
