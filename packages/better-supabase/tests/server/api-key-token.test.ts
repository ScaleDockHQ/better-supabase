import { Hono } from "hono";
import { describe, expect, it } from "vitest";

import type { HonoEnv } from "../../src/hono/index.ts";
import type { Functions, Models } from "../fixtures/generated-camel.ts";

import {
  apiKeyResolver,
  createApiKeys,
} from "../../src/blocks/api-keys/index.ts";
import { createSupabase } from "../../src/core/define.ts";
import {
  generateSigningKey,
  publicJwk,
  verifyCompact,
} from "../../src/core/jws.ts";
import { ok } from "../../src/core/result.ts";
import { createHono } from "../../src/hono/index.ts";
import { apiKeyTokenSigner } from "../../src/server/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const PROJECT_URL = "https://project.supabase.test";
const KEY = `bs_0123456789abcdef_${"d".repeat(43)}`;

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const keys = createApiKeys({
  transport: {
    call: () =>
      Promise.resolve({
        status: "ok",
        key: {
          id: "33333333-3333-4333-8333-333333333333",
          organization_id: ORG,
          user_id: null,
          name: "CI",
          prefix: "bs",
          public_id: "0123456789abcdef",
          scopes: ["deals:read"],
          rate_limit: 60,
          expires_at: null,
          last_used_at: null,
          revoked_at: null,
          rotated_from: null,
          created_by: null,
          created_at: "2026-10-06T09:00:00Z",
        },
      }),
  },
});

type Env = HonoEnv<Models, Functions, unknown>;

describe("apiKeyTokenSigner", () => {
  it("signs the key's claims as a short-lived ES256 JWT", async () => {
    const { kid, privateKey } = await generateSigningKey("ES256");

    const sign = apiKeyTokenSigner({
      key: { ...privateKey, kid },
      ttlSeconds: 30,
    });

    const token = await sign({
      kind: "apiKey",
      keyId: "k",
      name: "CI",
      scopes: ["deals:read"],
      claims: {
        sub: "",
        role: "authenticated",
        aud: "authenticated",
        api_key: { id: "k" },
      },
    } as never);

    const { header, payload } = await verifyCompact(token, {
      keys: [{ ...publicJwk(privateKey), kid }],
    });

    expect(header).toMatchObject({ alg: "ES256", typ: "JWT", kid });
    expect(payload).toMatchObject({
      role: "authenticated",
      api_key: { id: "k" },
    });
    expect(Number(payload["exp"]) - Number(payload["iat"])).toBe(30);
  });

  it("refuses a key that is not a private P-256 JWK", async () => {
    const { privateKey } = await generateSigningKey("Ed25519");

    expect(() => apiKeyTokenSigner({ key: privateKey })).toThrow(TypeError);
    expect(() => apiKeyTokenSigner({ key: publicJwk(privateKey) })).toThrow(
      TypeError,
    );
  });
});

describe("an API key without direct Postgres", () => {
  it("runs ctx.db over PostgREST with a minted token and the key's tenant", async () => {
    const { kid, privateKey } = await generateSigningKey("ES256");
    const sent: Request[] = [];

    const bsb = createHono(createSupabase(schema), {
      env,
      fetch: (input, init) => {
        sent.push(new Request(input, init));

        return Promise.resolve(Response.json([]));
      },
      apiKeyToken: apiKeyTokenSigner({ key: { ...privateKey, kid } }),
      auth: { resolvers: [apiKeyResolver({ keys })] },
    });

    const app = new Hono<Env>()
      .onError(bsb.onError)
      .use("/keys/*", bsb.middleware({ allow: ["apiKey"] }))
      .get(
        "/keys/customers",
        bsb.handler(async (_c, ctx) => {
          const rows = await ctx.db.customers.list({ limit: 1 });

          if (!rows.ok) {
            return ok({ error: rows.error });
          }

          return ok({
            rows: rows.data.length,
            supabase: typeof ctx.supabase.from,
          });
        }),
      );

    const answer = await app.request("/keys/customers", {
      headers: { "x-api-key": KEY },
    });

    expect(await answer.json()).toEqual({ rows: 0, supabase: "function" });

    const request = sent[0]!;
    const bearer = request.headers.get("authorization")?.replace("Bearer ", "");

    expect(request.url).toContain(`${PROJECT_URL}/rest/v1/customers`);
    expect(request.headers.get("apikey")).toBe(env.publishableKey);
    expect(request.headers.get("x-bsb-tenant")).toBe(ORG);

    const { payload } = await verifyCompact(bearer!, {
      keys: [{ ...publicJwk(privateKey), kid }],
    });

    expect(payload).toMatchObject({
      sub: "",
      role: "authenticated",
      api_key: { organization_id: ORG, scopes: ["deals:read"] },
    });
  });

  it("names apiKeyToken when neither it nor postgres is set", async () => {
    const bsb = createHono(createSupabase(schema), {
      env,
      auth: { resolvers: [apiKeyResolver({ keys })] },
    });

    const ctx = await bsb.context(
      new Request(`${PROJECT_URL}/keys`, { headers: { "x-api-key": KEY } }),
    );

    expect(ctx.auth.kind).toBe("apiKey");
    expect(ctx.sql).toBeUndefined();
    expect(() => ctx.db).toThrow(/ServerOptions\.apiKeyToken/);
    expect(() => ctx.supabase).toThrow(/ServerOptions\.apiKeyToken/);
  });
});
