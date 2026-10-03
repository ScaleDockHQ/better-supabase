import { NextRequest } from "next/server.js";
import { afterEach, describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

vi.mock("next/headers.js", () => ({
  headers: () => Promise.resolve(new Headers()),
  cookies: () => Promise.resolve({ set: vi.fn() }),
}));
vi.mock("next/cache.js", () => ({
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  cacheTag: vi.fn(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();
const sub = "6f1c2c1e-5d0a-4d9e-9a51-6b1f0e7c2a10";
const client = "5f0e4d3c-2b1a-4098-8776-655443322110";
const bs = createNext(defineSupabase(schema), {
  env,
  auth: { jwks: signer.jwks as never },
  cacheTags: false,
});
const segment = { params: Promise.resolve({ id: "c1" }) };

function call(
  handler: ReturnType<typeof bs.route<{ id: string }>>,
  token?: string,
): Promise<Response> {
  return handler(
    new NextRequest("https://app.test/api/customers/c1", {
      headers: token ? { authorization: `Bearer ${token}` } : {},
    }),
    segment,
  );
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("next.route for bearer callers", () => {
  const read = bs.route<{ id: string }>(
    (_request, { db, params }) =>
      db.customers.findById(params.id, { select: ["id"] }),
    { scopes: ["customers:read"] },
  );

  it("answers 401 with a Bearer challenge without a valid token", async () => {
    const missing = await call(read);
    expect(missing.status).toBe(401);
    expect(missing.headers.get("www-authenticate")).toBe(
      'Bearer realm="supabase"',
    );
    expect(missing.headers.get("content-type")).toBe(
      "application/problem+json",
    );

    const broken = await call(read, "not-a-jwt");
    expect(broken.status).toBe(401);
    expect(broken.headers.get("www-authenticate")).toBe(
      'Bearer realm="supabase", error="invalid_token"',
    );
  });

  it("answers 401 for a malformed act chain", async () => {
    const token = await signer.sign({ sub, act: { act: { sub: "x" } } });
    const response = await call(read, token);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({
      kind: "unauthorized",
      code: "ACTOR_INVALID",
    });
  });

  it("answers 403 insufficient_scope when the client lacks a scope", async () => {
    const token = await signer.sign({
      sub,
      client_id: client,
      scope: "openid email",
    });
    const response = await call(read, token);
    expect(response.status).toBe(403);
    expect(response.headers.get("www-authenticate")).toBe(
      'Bearer realm="supabase", error="insufficient_scope", scope="customers:read"',
    );
    expect(await response.json()).toMatchObject({
      kind: "forbidden",
      code: "INSUFFICIENT_SCOPE",
      scopes: ["customers:read"],
    });
  });

  it("answers 404 for a row RLS hides, and lets the user's own token through", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(Response.json([])),
    );
    const delegated = await signer.sign({
      sub,
      client_id: client,
      scope: "openid customers:read",
    });
    const hidden = await call(read, delegated);
    expect(hidden.status).toBe(404);
    expect(await hidden.json()).toMatchObject({ kind: "not_found" });

    const own = await signer.sign({ sub });
    expect((await call(read, own)).status).toBe(404);
  });
});
