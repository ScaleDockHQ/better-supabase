import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";
const ACME = "00000000-0000-4000-8000-000000000001";
const signer = await createTestSigner();

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

async function request(): Promise<Request> {
  const token = await signer.sign({ sub: USER });

  return new Request("https://app.test/", {
    headers: { authorization: `Bearer ${token}` },
  });
}

describe("server.context", () => {
  it("builds the context directly when no tenant or support is configured", async () => {
    const server = createServer(createSupabase(schema), {
      env,
      auth: { jwks: signer.jwks },
    });

    const ctx = await server.context(await request());

    expect(ctx.auth.kind).toBe("user");
    expect(ctx.db.$context.tenant).toBeUndefined();
  });

  it("keeps the composed path, with the tenant, when a tenant is configured", async () => {
    const server = createServer(createSupabase(schema), {
      env,
      auth: { jwks: signer.jwks },
      tenant: () => ACME,
    });

    const ctx = await server.context(await request());

    expect(ctx.db.$context.tenant).toBe(ACME);
  });

  it("takes a tenant from the call options on the direct path", async () => {
    const server = createServer(createSupabase(schema), {
      env,
      auth: { jwks: signer.jwks },
    });

    const ctx = await server.context(await request(), { tenant: ACME });

    expect(ctx.db.$context.tenant).toBe(ACME);
  });
});
