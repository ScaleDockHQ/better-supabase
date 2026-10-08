import { describe, expect, it } from "vitest";

import { createMcp, MCP_PROTOCOL_VERSION } from "../../src/mcp/index.ts";
import { betterSupabase, env, signer, USER } from "../fixtures/test-server.ts";

const initialize = {
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: {
    protocolVersion: MCP_PROTOCOL_VERSION,
    capabilities: {},
    clientInfo: { name: "test", version: "1" },
  },
};

function serverWith(
  requiredRoles:
    | readonly string[]
    | { readonly roles: readonly string[]; readonly claim?: string },
) {
  return createMcp(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never },
    prefetchJwks: false,
    name: "crm",
    version: "1.0.0",
    requiredRoles,
  });
}

async function call(
  mcp: ReturnType<typeof serverWith>,
  appMetadata: Record<string, unknown>,
): Promise<Response> {
  const token = await signer.sign({ sub: USER, app_metadata: appMetadata });
  return mcp.fetch(
    new Request("https://tools.test/mcp", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json, text/event-stream",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(initialize),
    }),
  );
}

describe("createMcp requiredRoles", () => {
  it("admits callers holding a role at app_metadata.role", async () => {
    const mcp = serverWith(["admin"]);
    expect((await call(mcp, { role: "admin" })).status).toBe(200);
    const refused = await call(mcp, { role: "member" });
    expect(refused.status).toBe(403);
  });

  it("reads an array of roles at a custom claim", async () => {
    const mcp = serverWith({ roles: ["support"], claim: "app_metadata.roles" });
    expect((await call(mcp, { roles: ["billing", "support"] })).status).toBe(
      200,
    );
    expect((await call(mcp, { roles: ["billing"] })).status).toBe(403);
  });

  it("an empty list admits every signed-in caller", async () => {
    expect((await call(serverWith([]), {})).status).toBe(200);
  });
});
