import {
  Client,
  StreamableHTTPClientTransport,
} from "@modelcontextprotocol/client";
import { describe, expect, it, vi } from "vitest";

import type { SupabaseMcpModule } from "../../src/core/supabase-mcp.ts";
import type { CredentialProvider } from "../../src/credentials/provider.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import {
  loadSupabaseMcp,
  loadSupabaseMcpPlatform,
} from "../../src/core/supabase-mcp.ts";
import { createMcpAuth, supabaseMcpHandler } from "../../src/mcp/sdk/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const ADMIN = "11111111-1111-4111-8111-111111111111";
const MEMBER = "22222222-2222-4222-8222-222222222222";
const ENDPOINT = "https://ops.test/mcp";
const signer = await createTestSigner();

const auth = createMcpAuth(defineSupabase(schema), {
  env,
  auth: { jwks: signer.jwks },
  resource: ENDPOINT,
});

const REF = { provider: "test", key: "supabase-management" };

function credentials(token: string | null) {
  const getToken = vi.fn(() =>
    AsyncResult.from(() =>
      Promise.resolve(
        token === null
          ? err(dbError("forbidden", "No Management API token"))
          : ok({ token, headers: { authorization: `Bearer ${token}` } }),
      ),
    ),
  );

  const provider: CredentialProvider = {
    apiVersion: 1,
    name: "test",
    getToken,
    capabilities: () => ({
      userSubjects: false,
      authorization: false,
      revoke: false,
      inbound: false,
    }),
    revoke: () => AsyncResult.from(() => Promise.resolve(ok(false))),
  };

  return { provider, getToken };
}

function setup(token: string | null = "sbp_test") {
  const tokens: string[] = [];
  const closed = vi.fn();
  const { provider, getToken } = credentials(token);

  const app = supabaseMcpHandler(
    auth,
    {
      credentials: provider,
      credentialRef: REF,
      projectRef: "abcdefghijklmnopqrst",
      features: ["database", "docs"],
      authorize: (user) => user.user.id === ADMIN,
    },
    {
      server: async (): Promise<SupabaseMcpModule> => {
        const real = await loadSupabaseMcp();

        return {
          ...real,
          createSupabaseMcpHandler: (options) => {
            const handler = real.createSupabaseMcpHandler(options);

            return {
              fetch: (request, init) => handler.fetch(request, init),
              close: async () => {
                closed();
                await handler.close();
              },
            };
          },
        };
      },
      platform: async () => {
        const real = await loadSupabaseMcpPlatform();

        return {
          createSupabaseApiPlatform: (options) => {
            tokens.push(options.accessToken);

            return real.createSupabaseApiPlatform(options);
          },
        };
      },
    },
  );

  return { app, tokens, closed, getToken };
}

const connect = async (
  app: (request: Request) => Promise<Response>,
  token: string,
) => {
  const client = new Client(
    { name: "test", version: "1.0.0" },
    { versionNegotiation: { mode: "auto" } },
  );

  await client.connect(
    new StreamableHTTPClientTransport(new URL(ENDPOINT), {
      requestInit: { headers: { authorization: `Bearer ${token}` } },
      fetch: (url, init) => app(new Request(url, init)),
    }),
  );

  return client;
};

describe("supabaseMcpHandler", () => {
  it("serves the project's read-only tools to an authorized caller", async () => {
    const { app, tokens, closed, getToken } = setup();

    const client = await connect(
      app,
      await signer.sign({ sub: ADMIN, role: "authenticated" }),
    );

    const { tools } = await client.listTools();
    expect(tools.map((tool) => tool.name).toSorted()).toEqual([
      "execute_sql",
      "list_extensions",
      "list_migrations",
      "list_tables",
      "search_docs",
    ]);
    await client.close();
    expect(tokens.every((token) => token === "sbp_test")).toBe(true);
    expect(getToken).toHaveBeenCalledWith(REF, { subject: { type: "app" } });
    await vi.waitFor(() => {
      expect(closed).toHaveBeenCalledWith();
    });
  });

  it("refuses a caller authorize turns down, before reading the token", async () => {
    const { app, getToken } = setup();

    const response = await app(
      new Request(ENDPOINT, {
        method: "POST",
        headers: {
          authorization: `Bearer ${await signer.sign({ sub: MEMBER, role: "authenticated" })}`,
          "content-type": "application/json",
          accept: "application/json, text/event-stream",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "ping" }),
      }),
    );

    expect(response.status).toBe(403);
    expect(getToken).not.toHaveBeenCalled();
  });

  it("challenges a request without a bearer token", async () => {
    const { app } = setup();
    const response = await app(new Request(ENDPOINT, { method: "POST" }));
    expect(response.status).toBe(401);
    expect(response.headers.get("www-authenticate")).toContain(
      "resource_metadata=",
    );
  });

  it("answers the credential provider's error", async () => {
    const { app } = setup(null);

    const response = await app(
      new Request(ENDPOINT, {
        method: "POST",
        headers: {
          authorization: `Bearer ${await signer.sign({ sub: ADMIN, role: "authenticated" })}`,
        },
      }),
    );

    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({
      detail: "No Management API token",
    });
  });
});
