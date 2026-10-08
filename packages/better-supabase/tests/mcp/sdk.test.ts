import type { CallToolResult } from "@modelcontextprotocol/server";

import {
  Client,
  StreamableHTTPClientTransport,
} from "@modelcontextprotocol/client";
import { createMcpHandler, McpServer } from "@modelcontextprotocol/server";
import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { afterEach, describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import {
  createMcpAuth,
  withBetterSupabaseMcp,
} from "../../src/mcp/sdk/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = "11111111-1111-4111-8111-111111111111";
const ENDPOINT = "https://tools.test/mcp";
const signer = await createTestSigner();
const betterSupabase = defineSupabase(schema);

type ToolHandler = (...params: never[]) => unknown;

/**
 * A structural stand-in for an authorization library's `protectServer`: it takes a
 * `permission` key in the tool config, checks it against the caller's
 * `authInfo`, and registers the remaining config on the wrapped server.
 */
function protectServer<
  S extends {
    registerTool(name: string, config: never, cb: ToolHandler): unknown;
  },
>(
  server: S,
  can: (permission: string, scopes: readonly string[]) => boolean,
): S {
  const register = server.registerTool.bind(server) as unknown as (
    name: string,
    config: object,
    cb: (...params: unknown[]) => unknown,
  ) => unknown;
  const registerTool = (
    name: string,
    { permission, ...config }: { permission: string },
    cb: (...params: unknown[]) => unknown,
  ) =>
    register(name, config, (...params: unknown[]) => {
      const ctx = params.at(-1) as {
        http?: { authInfo?: { scopes: string[] } };
      };
      if (!can(permission, ctx.http?.authInfo?.scopes ?? [])) {
        return {
          isError: true,
          content: [{ type: "text", text: `Missing permission ${permission}` }],
        };
      }
      return cb(...params);
    });
  return Object.assign(server, { registerTool });
}

const auth = createMcpAuth(betterSupabase, {
  env,
  auth: { jwks: signer.jwks as never },
  resource: ENDPOINT,
  advertisedScopes: ["crm:read", "offline_access"],
});

const build = (guarded: boolean) => {
  const handler = createMcpHandler(() => {
    const base = new McpServer({ name: "crm", version: "1.0.0" });
    const inner = guarded
      ? protectServer(base, (permission, scopes) => scopes.includes(permission))
      : base;
    const server = withBetterSupabaseMcp(inner, auth);
    server.registerTool(
      "whoami",
      { description: "The signed-in user.", permission: "crm:read" },
      (ctx) => ({
        content: [
          {
            type: "text",
            text: JSON.stringify({
              id: ctx.auth.kind === "user" ? ctx.auth.user.id : null,
              hasDb: typeof ctx.db.customers.findMany === "function",
              same: ctx.bs.db === ctx.db,
            }),
          },
        ],
      }),
    );
    server.registerTool(
      "echo",
      {
        description: "Echoes a message.",
        inputSchema: toStandardJsonSchema(v.object({ message: v.string() })),
        permission: "crm:read",
      },
      (args, ctx) => ({
        content: [
          {
            type: "text",
            text: `${args.message} from ${ctx.auth.kind}`,
          },
        ],
      }),
    );
    return base;
  });
  return auth.serve(handler);
};

const connect = async (
  app: (request: Request) => Promise<Response>,
  token: string,
) => {
  const client = new Client({ name: "test", version: "1.0.0" });
  await client.connect(
    new StreamableHTTPClientTransport(new URL(ENDPOINT), {
      requestInit: { headers: { authorization: `Bearer ${token}` } },
      fetch: (url, init) => app(new Request(url, init)),
    }),
  );
  return client;
};

const text = (result: unknown): string =>
  ((result as CallToolResult).content[0] as { text: string }).text;

describe("createMcpAuth", () => {
  const app = build(false);

  it("serves the RFC 9728 metadata", async () => {
    const response = await app(
      new Request(
        "https://tools.test/.well-known/oauth-protected-resource/mcp",
      ),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      resource: ENDPOINT,
      authorization_servers: [`${PROJECT_URL}/auth/v1`],
      bearer_methods_supported: ["header"],
      scopes_supported: ["crm:read"],
    });
    expect(auth.metadataUrl(new Request(ENDPOINT))).toBe(
      "https://tools.test/.well-known/oauth-protected-resource/mcp",
    );
  });

  it("answers CORS preflight for the metadata", async () => {
    const response = await app(
      new Request("https://tools.test/.well-known/oauth-protected-resource", {
        method: "OPTIONS",
      }),
    );
    expect(response.status).toBe(204);
  });

  it("refuses a missing or invalid token with a challenge", async () => {
    for (const authorization of [undefined, "Bearer not-a-jwt"]) {
      const response = await app(
        new Request(ENDPOINT, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            ...(authorization ? { authorization } : {}),
          },
          body: "{}",
        }),
      );
      expect(response.status).toBe(401);
      expect(response.headers.get("www-authenticate")).toContain(
        'resource_metadata="https://tools.test/.well-known/oauth-protected-resource/mcp"',
      );
    }
  });

  it("verifies tokens into AuthInfo", async () => {
    const token = await signer.sign({ sub: USER, client_id: "claude" });
    const info = await auth.verifier.verifyAccessToken(token);
    expect(info).toMatchObject({ token, clientId: "claude", scopes: [] });
    expect(info.expiresAt).toBeTypeOf("number");
    await expect(auth.verifier.verifyAccessToken("nope")).rejects.toThrow(
      "not valid",
    );
  });

  it("puts db and auth for the verified caller on the tool context", async () => {
    const client = await connect(app, await signer.sign({ sub: USER }));
    expect(JSON.parse(text(await client.callTool({ name: "whoami" })))).toEqual(
      { id: USER, hasDb: true, same: true },
    );
    expect(
      text(
        await client.callTool({ name: "echo", arguments: { message: "hi" } }),
      ),
    ).toBe("hi from user");
    await client.close();
  });

  it("falls back to an anon context without verified auth", async () => {
    const ctx = await auth.contextOf({} as never);
    expect(ctx.auth.kind).toBe("anon");
    const token = await signer.sign({ sub: USER });
    const fromToken = await auth.contextOf({
      http: { authInfo: { token, clientId: "", scopes: [] } },
    } as never);
    expect(fromToken.auth.kind).toBe("user");
    const forged = await auth.contextOf({
      http: {
        authInfo: {
          token: "",
          clientId: "",
          scopes: [],
          extra: { betterSupabase: { kind: "user" } },
        },
      },
    } as never);
    expect(forged.auth.kind).toBe("anon");
  });
});

describe("withBetterSupabaseMcp after a protectServer wrapper", () => {
  const app = build(true);

  it("runs the tool when the permission check passes", async () => {
    const client = await connect(
      app,
      await signer.sign({ sub: USER, scope: "crm:read" }),
    );
    expect(JSON.parse(text(await client.callTool({ name: "whoami" })))).toEqual(
      { id: USER, hasDb: true, same: true },
    );
    await client.close();
  });

  it("refuses the tool before the context is built", async () => {
    const client = await connect(app, await signer.sign({ sub: USER }));
    const result = await client.callTool({
      name: "echo",
      arguments: { message: "hi" },
    });
    expect(result.isError).toBe(true);
    expect(text(result)).toBe("Missing permission crm:read");
    await client.close();
  });
});

describe("createMcpAuth guard options", () => {
  it("lets anon callers through when allowed", async () => {
    const open = createMcpAuth(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
      allow: ["user", "anon"],
    });
    let seen: unknown = "unset";
    const response = await open.serve({
      fetch: async (_request, options) => {
        seen = options?.authInfo;
        return new Response("ok");
      },
    })(new Request(ENDPOINT, { method: "POST" }));
    expect(await response.text()).toBe("ok");
    expect(seen).toBeUndefined();
  });

  it("hands event sends a tool started to waitUntil", async () => {
    const waited: Promise<unknown>[] = [];
    const open = createMcpAuth(betterSupabase, {
      env,
      allow: ["anon"],
      waitUntil: (promise) => waited.push(promise),
    });
    const { promise: send, resolve } = Promise.withResolvers<void>();
    await open.serve({
      fetch: async () => {
        betterSupabase.events.track(send);
        return new Response("ok");
      },
    })(new Request(ENDPOINT, { method: "POST" }));
    expect(waited).toHaveLength(1);
    resolve();
    await Promise.all(waited);
  });

  it("doesn't trust auth that another instance verified", async () => {
    const scoped = createMcpAuth(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
      requiredScopes: ["crm:write"],
    });
    const token = await signer.sign({
      sub: USER,
      scope: "crm:read",
      client_id: "claude",
      act: { sub: "claude", client_id: "claude" },
    });
    const info = await auth.verifier.verifyAccessToken(token);
    const ctx = await scoped.contextOf({ http: { authInfo: info } } as never);
    expect(ctx.auth.kind).toBe("anon");
    const own = await auth.contextOf({ http: { authInfo: info } } as never);
    expect(own.auth.kind).toBe("user");
  });

  it("answers 403 insufficient_scope for a delegated token without the scope", async () => {
    const scoped = createMcpAuth(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
      requiredScopes: ["crm:write"],
    });
    const token = await signer.sign({
      sub: USER,
      scope: "crm:read",
      client_id: "claude",
      act: { sub: "claude", client_id: "claude" },
    });
    const response = await scoped.serve({
      fetch: () => Promise.resolve(new Response("ok")),
    })(
      new Request(ENDPOINT, {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    expect(response.status).toBe(403);
    expect(response.headers.get("www-authenticate")).toContain(
      "insufficient_scope",
    );
  });

  it("answers CORS preflight for the endpoint and adds CORS headers", async () => {
    const open = createMcpAuth(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const serve = open.serve({
      fetch: () => Promise.resolve(new Response("ok")),
    });
    const preflight = await serve(
      new Request(ENDPOINT, {
        method: "OPTIONS",
        headers: { origin: "https://app.test" },
      }),
    );
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("access-control-allow-headers")).toContain(
      "Authorization",
    );
    const challenge = await serve(new Request(ENDPOINT, { method: "POST" }));
    expect(challenge.status).toBe(401);
    expect(challenge.headers.get("access-control-allow-origin")).toBe("*");
    expect(challenge.headers.get("access-control-expose-headers")).toBe(
      "WWW-Authenticate",
    );

    const closed = createMcpAuth(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
      cors: false,
    }).serve({ fetch: () => Promise.resolve(new Response("ok")) });
    const refused = await closed(new Request(ENDPOINT, { method: "OPTIONS" }));
    expect(refused.status).toBe(401);
    expect(refused.headers.get("access-control-allow-origin")).toBeNull();
  });
});

describe("createMcpAuth on Supabase Edge Functions", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("advertises the public function URL and serves the suffix route", async () => {
    vi.stubEnv("SUPABASE_FUNCTION_SLUG", "mcp");
    const edge = createMcpAuth(betterSupabase, {
      env: { ...env, url: "http://kong:8000" },
      auth: { jwks: signer.jwks as never },
    });
    const serve = edge.serve({
      fetch: () => Promise.resolve(new Response("ok")),
    });
    const headers = {
      "x-forwarded-host": "abcdefghijklmnopqrst.supabase.co",
      "x-forwarded-proto": "https",
      "x-forwarded-port": "443",
    };
    const PUBLIC = `${PROJECT_URL}/functions/v1/mcp`;
    const challenge = await serve(
      new Request("http://localhost:8081/mcp", { method: "POST", headers }),
    );
    expect(challenge.headers.get("www-authenticate")).toContain(
      `resource_metadata="${PUBLIC}/oauth-protected-resource"`,
    );
    const metadata = await serve(
      new Request("http://localhost:8081/mcp/oauth-protected-resource", {
        headers,
      }),
    );
    expect(await metadata.json()).toEqual({
      resource: PUBLIC,
      authorization_servers: [`${PROJECT_URL}/auth/v1`],
      bearer_methods_supported: ["header"],
    });
  });
});
