import { createTestSigner } from "better-supabase/testing";
import { afterEach, describe, expect, it, vi } from "vitest";

import { shippingAddresses } from "./commerce/shipping.ts";
import { createRuntime, sessionOf } from "./runtime/index.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const signer = await createTestSigner();
const runtime = createRuntime({
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks as never },
});
const sub = "6f1c2c1e-5d0a-4d9e-9a51-6b1f0e7c2a10";
const client = "5f0e4d3c-2b1a-4098-8776-655443322110";

const addresses = runtime.handler(
  async (_request, ctx) => {
    const session = sessionOf(ctx);
    const rows = await shippingAddresses(ctx.db, "c1");
    if (!rows.ok) return rows;
    return {
      actor: session.kind === "user" ? session.actor : undefined,
      delegation: session.kind === "user" ? session.delegation : undefined,
      rows: rows.data,
    };
  },
  { scopes: ["addresses:read"] },
);

function call(token: string): Promise<Response> {
  return addresses(
    new Request("https://app.test/api/addresses", {
      headers: { authorization: `Bearer ${token}` },
    }),
  );
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("bearer callers through the runtime", () => {
  it("hands the domain code the acting client and its scopes", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(Response.json([])),
    );
    const token = await signer.sign({
      sub,
      client_id: client,
      scope: "openid addresses:read",
    });
    const response = await call(token);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      actor: { id: client, kind: "oauth-client" },
      delegation: { scopes: ["openid", "addresses:read"] },
      rows: [],
    });
  });

  it("passes the act chain along with the current actor", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(Response.json([])),
    );
    const act = { sub: "agent-runner", act: { sub: "mcp-client-42" } };
    const response = await call(
      await signer.sign({ sub, act, scope: "addresses:read" }),
    );
    expect(await response.json()).toMatchObject({
      actor: { id: "agent-runner", kind: "oauth-client", chain: act },
      delegation: { scopes: ["addresses:read"], chain: act },
    });
  });

  it("refuses a missing scope and a malformed chain before any query", async () => {
    const fetch = vi.spyOn(globalThis, "fetch");
    const narrow = await call(
      await signer.sign({ sub, client_id: client, scope: "openid" }),
    );
    expect(narrow.status).toBe(403);
    expect(narrow.headers.get("www-authenticate")).toContain(
      'error="insufficient_scope", scope="addresses:read"',
    );
    const broken = await call(await signer.sign({ sub, act: [] }));
    expect(broken.status).toBe(401);
    expect(fetch).not.toHaveBeenCalled();
  });
});
