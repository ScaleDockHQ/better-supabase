import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createMcp } from "../../src/mcp/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const signer = await createTestSigner();
const betterSupabase = defineSupabase(schema);
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const server = (scopes?: string[]) =>
  createMcp(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never },
    name: "crm",
    version: "1.0.0",
    ...(scopes ? { scopes, allow: ["service" as const] } : {}),
  });

const METADATA = "https://tools.test/.well-known/oauth-protected-resource/mcp";

describe("RFC 9728 OAuth 2.0 Protected Resource Metadata", () => {
  it("serves the metadata at the well-known path with the resource path appended (section 3.1)", async () => {
    const response = await server().fetch(new Request(METADATA));
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toMatch(/^application\/json/);
  });

  it("the resource member is the protected resource URL (section 3.3, it must match the request)", async () => {
    const metadata = (await (
      await server().fetch(new Request(METADATA))
    ).json()) as Record<string, unknown>;
    expect(metadata["resource"]).toBe("https://tools.test/mcp");
    expect(new URL(String(metadata["resource"])).hash).toBe("");
  });

  it("lists authorization_servers as issuer URLs and header-only bearer methods (section 2)", async () => {
    const metadata = (await (
      await server().fetch(new Request(METADATA))
    ).json()) as Record<string, string[]>;
    expect(metadata["authorization_servers"]).toEqual([
      `${PROJECT_URL}/auth/v1`,
    ]);
    for (const issuer of metadata["authorization_servers"]!)
      expect(new URL(issuer).protocol).toBe("https:");
    expect(metadata["bearer_methods_supported"]).toEqual(["header"]);
  });

  it("publishes scopes_supported without offline_access", async () => {
    const metadata = (await (
      await server(["openid", "crm.read", "offline_access"]).fetch(
        new Request(METADATA),
      )
    ).json()) as Record<string, unknown>;
    expect(metadata["scopes_supported"]).toEqual(["openid", "crm.read"]);
  });

  it("every 401 and 403 challenge carries resource_metadata (section 5.1)", async () => {
    const anonymous = await server().fetch(
      new Request("https://tools.test/mcp", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize" }),
      }),
    );
    expect(anonymous.status).toBe(401);
    expect(anonymous.headers.get("www-authenticate")).toContain(
      `resource_metadata="${METADATA}"`,
    );

    const forbidden = await server(["crm.read"]).fetch(
      new Request("https://tools.test/mcp", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${await signer.sign({ sub: "11111111-1111-4111-8111-111111111111" })}`,
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
      }),
    );
    expect(forbidden.status).toBe(403);
    expect(forbidden.headers.get("www-authenticate")).toContain(
      `resource_metadata="${METADATA}"`,
    );
  });
});
