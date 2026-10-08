import type * as McpModule from "@ai-sdk/mcp";

import { jsonSchema, tool } from "ai";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type {
  Connectors,
  ConnectorServer,
  FingerprintStatus,
} from "../../../src/blocks/connectors/index.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../../src/credentials/provider.ts";
import type { VaultCredentials } from "../../../src/credentials/vault.ts";

import { AsyncResult } from "../../../src/core/result.ts";

const mcp = vi.hoisted(() => ({
  auth: vi.fn(),
  createMCPClient: vi.fn(),
}));

vi.mock("@ai-sdk/mcp", async (original) => ({
  ...(await original<typeof McpModule>()),
  auth: mcp.auth,
  createMCPClient: mcp.createMCPClient,
}));

const {
  authorizeConnector,
  completeConnector,
  connectAll,
  connectTools,
  mcpOAuthRef,
  vaultOAuthProvider,
} = await import("../../../src/ai-sdk/mcp/index.ts");

const AT = Temporal.Instant.from("2026-01-01T00:00:00Z");
const CAPABILITIES = {
  userSubjects: true,
  authorization: false,
  revoke: true,
  inbound: false,
};

const server = (over: Partial<ConnectorServer> = {}): ConnectorServer => ({
  id: "s1",
  organizationId: "o1",
  name: "Git Hub",
  url: "https://mcp.example.com/mcp",
  transport: "http",
  authType: "none",
  credentialRef: undefined,
  scopes: ["repo"],
  clientMetadata: {},
  enabled: true,
  grant: undefined,
  createdAt: AT,
  updatedAt: AT,
  ...over,
});

const grant = (credentialRef: CredentialRef) => ({
  id: "g1",
  userId: "u1",
  serverId: "s1",
  organizationId: "o1",
  credentialRef,
  scopes: ["repo"],
  expiresAt: undefined,
  grantedAt: AT,
  revokedAt: undefined,
});

function fakeVault() {
  const secrets = new Map<string, string>();
  const key = (ref: CredentialRef, subject?: { type: string; id?: string }) =>
    `${String(ref["secret"])}@${subject?.type === "user" ? subject.id : "app"}`;
  const vault = {
    apiVersion: 1,
    name: "vault",
    capabilities: () => CAPABILITIES,
    getToken: (ref, options) => {
      const value = secrets.get(key(ref, options.subject));
      return value === undefined
        ? AsyncResult.err({ kind: "not_found", message: "none", status: 404 })
        : AsyncResult.ok({ token: value, headers: {} });
    },
    set: (ref, value, options) => {
      secrets.set(key(ref, options?.subject), value);
      return AsyncResult.ok(undefined);
    },
    revoke: (ref, options) => {
      return AsyncResult.ok(secrets.delete(key(ref, options.subject)));
    },
    verifyInbound: () => AsyncResult.ok(false),
  } satisfies VaultCredentials;
  return { vault, secrets };
}

function fakeConnectors(status: FingerprintStatus = "approved") {
  const recorded: unknown[] = [];
  const saved: unknown[] = [];
  const forgotten: unknown[] = [];
  const checked: unknown[] = [];
  let session:
    | { sessionId: string; initializeResult: Record<string, unknown> }
    | undefined;
  const connectors = {
    grants: {
      record: (...args: unknown[]) => {
        recorded.push(args);
        return AsyncResult.ok(grant(mcpOAuthRef("s1")));
      },
    },
    sessions: {
      get: () =>
        AsyncResult.ok(
          session === undefined ? undefined : { ...session, expiresAt: AT },
        ),
      save: (...args: unknown[]) => {
        saved.push(args);
        return AsyncResult.ok(true);
      },
      forget: (...args: unknown[]) => {
        forgotten.push(args);
        return AsyncResult.ok(true);
      },
    },
    fingerprints: {
      check: (...args: unknown[]) => {
        checked.push(args);
        return AsyncResult.ok(status);
      },
    },
  } as unknown as Connectors;
  return {
    connectors,
    recorded,
    saved,
    forgotten,
    checked,
    resume: (value: typeof session) => {
      session = value;
    },
  };
}

const echo = tool({
  description: "echo",
  inputSchema: jsonSchema({ type: "object" }),
  execute: () => Promise.resolve("ok"),
});

function fakeClient(sessionId: string | null = "sess-1") {
  const close = vi.fn(() => Promise.resolve());
  const elicit: { handler?: (request: unknown) => unknown } = {};
  const client = {
    initializeResult: { protocolVersion: "2025-11-25" },
    onElicitationRequest: (
      _schema: unknown,
      handler: (r: unknown) => unknown,
    ) => {
      elicit.handler = handler;
    },
    listTools: vi.fn(() =>
      Promise.resolve({
        tools: [
          { name: "search", inputSchema: { type: "object" } },
          {
            name: "render",
            inputSchema: { type: "object" },
            _meta: { ui: { visibility: ["app"] } },
          },
        ],
      }),
    ),
    toolsFromDefinitions: (definitions: { tools: { name: string }[] }) =>
      Object.fromEntries(definitions.tools.map(({ name }) => [name, echo])),
    close,
  };
  mcp.createMCPClient.mockImplementation(
    (options: { transport: { onSessionIdChange?: (id?: string) => void } }) => {
      options.transport.onSessionIdChange?.(sessionId ?? undefined);
      return Promise.resolve(client);
    },
  );
  return { client, close, elicit };
}

beforeEach(() => {
  mcp.auth.mockReset();
  mcp.createMCPClient.mockReset();
});

describe("vaultOAuthProvider", () => {
  it("keeps tokens, verifier and state in one per-user secret", async () => {
    const { vault, secrets } = fakeVault();
    const provider = vaultOAuthProvider({
      vault,
      server: server({ clientMetadata: { logo_uri: "https://x/logo.png" } }),
      userId: "u1",
      redirectUrl: "https://app.test/callback",
    });
    expect(provider.redirectUrl).toBe("https://app.test/callback");
    expect(provider.clientMetadata).toMatchObject({
      redirect_uris: ["https://app.test/callback"],
      scope: "repo",
      logo_uri: "https://x/logo.png",
    });
    expect(await provider.tokens()).toBeUndefined();
    await provider.saveTokens({ access_token: "at", token_type: "Bearer" });
    await provider.saveCodeVerifier("v1");
    await provider.saveState?.("st");
    expect(await provider.codeVerifier()).toBe("v1");
    expect(await provider.storedState?.()).toBe("st");
    expect(typeof (await provider.state?.())).toBe("string");
    expect(JSON.parse(secrets.get("mcp:s1@u1") ?? "")).toEqual({
      tokens: { access_token: "at", token_type: "Bearer" },
      codeVerifier: "v1",
      state: "st",
    });

    const fresh = vaultOAuthProvider({
      vault,
      server: server(),
      userId: "u1",
      redirectUrl: "https://app.test/callback",
    });
    expect((await fresh.tokens())?.access_token).toBe("at");

    await provider.redirectToAuthorization(new URL("https://auth.test/x"));
    expect(provider.authorizationUrl?.toString()).toBe("https://auth.test/x");

    expect(await provider.clientInformation()).toBeUndefined();
    await provider.saveClientInformation?.({ client_id: "c1" });
    expect(await provider.clientInformation()).toEqual({ client_id: "c1" });
    expect(provider.isClientInformationDynamicallyRegistered?.()).toBe(true);

    await provider.invalidateCredentials?.("tokens");
    await provider.invalidateCredentials?.("verifier");
    await expect(provider.codeVerifier()).rejects.toThrow("No PKCE");
    expect(await provider.tokens()).toBeUndefined();
    await provider.invalidateCredentials?.("all");
    expect(secrets.size).toBe(0);
  });

  it("ignores a secret that isn't JSON and fails when Vault does", async () => {
    const { vault, secrets } = fakeVault();
    secrets.set("mcp:s1@u1", "not json");
    secrets.set("mcp-client:s1@app", "[]");
    const provider = vaultOAuthProvider({
      vault: {
        ...vault,
        set: () =>
          AsyncResult.err({
            kind: "network",
            message: "vault down",
            status: 503,
          }),
      },
      server: server({ scopes: [] }),
      userId: "u1",
      redirectUrl: "https://app.test/callback",
      clientMetadata: { redirect_uris: ["https://app.test/callback"] },
    });
    expect(provider.clientMetadata).toEqual({
      redirect_uris: ["https://app.test/callback"],
    });
    expect(await provider.tokens()).toBeUndefined();
    expect(await provider.clientInformation()).toBeUndefined();
    await expect(provider.saveCodeVerifier("v")).rejects.toThrow("vault down");
    await expect(
      provider.saveClientInformation?.({ client_id: "c" }),
    ).rejects.toThrow("vault down");
  });
});

describe("authorizeConnector and completeConnector", () => {
  const redirectUrl = "https://app.test/callback";

  it("returns the authorization URL, then records the grant on callback", async () => {
    const { vault } = fakeVault();
    const fake = fakeConnectors();
    mcp.auth.mockImplementationOnce(
      async (
        provider: Parameters<typeof vaultOAuthProvider>[0] & {
          redirectToAuthorization(url: URL): void;
          saveState(state: string): Promise<void>;
        },
      ) => {
        await provider.saveState("st");
        provider.redirectToAuthorization(
          new URL("https://auth.test/authorize"),
        );
        return "REDIRECT";
      },
    );
    const options = {
      connectors: fake.connectors,
      vault,
      server: server({ authType: "oauth" }),
      userId: "u1",
      redirectUrl,
    };
    expect(await authorizeConnector(options).orThrow()).toEqual({
      url: "https://auth.test/authorize",
    });
    expect(mcp.auth.mock.calls[0]?.[1]).toEqual({
      serverUrl: "https://mcp.example.com/mcp",
      scope: "repo",
    });

    const mismatch = await completeConnector({
      ...options,
      callback: `${redirectUrl}?code=c&state=other`,
    });
    expect(mismatch.ok ? undefined : mismatch.error.message).toContain("state");

    mcp.auth.mockImplementationOnce(
      async (provider: { saveTokens(tokens: unknown): Promise<void> }) => {
        await provider.saveTokens({
          access_token: "at",
          token_type: "Bearer",
          expires_in: 3600,
        });
        return "AUTHORIZED";
      },
    );
    await completeConnector({
      ...options,
      callback: `${redirectUrl}?code=c&state=st&iss=https://auth.test`,
    }).orThrow();
    expect(mcp.auth.mock.calls[1]?.[1]).toEqual({
      serverUrl: "https://mcp.example.com/mcp",
      authorizationCode: "c",
      callbackState: "st",
      callbackIssuer: "https://auth.test",
    });
    const [serverId, userId, ref, extra] = fake.recorded[0] as [
      string,
      string,
      CredentialRef,
      { expiresAt?: Temporal.Instant },
    ];
    expect([serverId, userId, ref]).toEqual(["s1", "u1", mcpOAuthRef("s1")]);
    expect(extra.expiresAt).toBeInstanceOf(Temporal.Instant);
  });

  it("records the grant when stored tokens still work", async () => {
    const { vault } = fakeVault();
    const fake = fakeConnectors();
    mcp.auth.mockResolvedValueOnce("AUTHORIZED");
    expect(
      await authorizeConnector({
        connectors: fake.connectors,
        vault,
        server: server({ authType: "oauth", scopes: [] }),
        userId: "u1",
        redirectUrl,
      }).orThrow(),
    ).toEqual({ url: undefined });
    expect(mcp.auth.mock.calls[0]?.[1]).toEqual({
      serverUrl: "https://mcp.example.com/mcp",
    });
    expect(fake.recorded[0]).toEqual([
      "s1",
      "u1",
      mcpOAuthRef("s1"),
      { scopes: [] },
    ]);
  });

  it("maps auth failures and callback errors", async () => {
    const { vault } = fakeVault();
    const options = {
      connectors: fakeConnectors().connectors,
      vault,
      server: server({ authType: "oauth" }),
      userId: "u1",
      redirectUrl,
    };
    mcp.auth.mockRejectedValue(new Error("discovery failed"));
    const started = await authorizeConnector(options);
    expect(started.ok ? undefined : started.error.hint).toBe(
      "CONNECTOR_AUTHORIZATION_FAILED",
    );
    const denied = await completeConnector({
      ...options,
      callback: `${redirectUrl}?error=access_denied`,
    });
    expect(denied.ok ? undefined : denied.error.message).toBe("access_denied");
    const noCode = await completeConnector({
      ...options,
      callback: redirectUrl,
    });
    expect(noCode.ok ? undefined : noCode.error.message).toContain("no code");
    const failed = await completeConnector({
      ...options,
      callback: `${redirectUrl}?code=c`,
    });
    expect(failed.ok ? undefined : failed.error.message).toBe(
      "discovery failed",
    );
  });
});

describe("connectTools", () => {
  it("connects, splits app tools, saves the session and closes", async () => {
    const { close, elicit } = fakeClient();
    const fake = fakeConnectors();
    const elicitAnswer = vi.fn(() =>
      Promise.resolve({ action: "accept" as const, content: {} }),
    );
    const connected = await connectTools({
      connectors: fake.connectors,
      server: server(),
      userId: "u1",
      chatKey: "c1",
      apps: true,
      prefix: "gh_",
      elicit: elicitAnswer,
    }).orThrow();
    expect(Object.keys(connected.tools)).toEqual(["gh_search"]);
    expect(Object.keys(connected.appTools)).toEqual(["gh_render"]);
    expect(connected.fingerprint).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(fake.saved).toEqual([
      [
        "s1",
        {
          chatKey: "c1",
          sessionId: "sess-1",
          initializeResult: { protocolVersion: "2025-11-25" },
        },
      ],
    ]);
    await elicit.handler?.({ params: {} });
    expect(elicitAnswer).toHaveBeenCalled();
    await connected.close();
    expect(close).toHaveBeenCalled();
    const options = mcp.createMCPClient.mock.calls[0]?.[0];
    expect(options.capabilities.elicitation).toEqual({});
    expect(options.transport.headers).toEqual({});
  });

  it("resumes a stored session and declines elicitation by default", async () => {
    const { elicit } = fakeClient(null);
    const fake = fakeConnectors();
    fake.resume({
      sessionId: "old",
      initializeResult: { protocolVersion: "2025-06-18" },
    });
    await connectTools({
      connectors: fake.connectors,
      server: server(),
      userId: "u1",
    }).orThrow();
    const options = mcp.createMCPClient.mock.calls[0]?.[0];
    expect(options.transport.initialSessionId).toBe("old");
    expect(options.initialInitializeResult).toEqual({
      protocolVersion: "2025-06-18",
    });
    expect(fake.forgotten).toEqual([["s1", ""]]);
    expect(fake.saved).toEqual([]);
    expect(await elicit.handler?.({})).toEqual({ action: "decline" });
  });

  it("blocks a changed tool list until an admin approves it", async () => {
    const { close } = fakeClient();
    const result = await connectTools({
      connectors: fakeConnectors("pending").connectors,
      server: server(),
      userId: "u1",
    });
    expect(result.ok ? undefined : result.error.hint).toBe(
      "CONNECTOR_TOOLS_CHANGED",
    );
    expect(close).toHaveBeenCalled();
  });

  it("sends header credentials and other providers' grants", async () => {
    fakeClient();
    const tokens: unknown[] = [];
    const credentials: CredentialProvider = {
      apiVersion: 1,
      name: "fake",
      capabilities: () => CAPABILITIES,
      getToken: (ref, options) => {
        tokens.push([ref, options]);
        return AsyncResult.ok({
          token: "t",
          headers: { authorization: `Bearer ${ref.provider}` },
        });
      },
      revoke: () => AsyncResult.ok(true),
    };
    const fake = fakeConnectors();
    await connectTools({
      connectors: fake.connectors,
      server: server({
        authType: "header",
        credentialRef: { provider: "vault", secret: "k" },
      }),
      userId: "u1",
      credentials,
    }).orThrow();
    const connectRef = { provider: "vercel-connect", connector: "gh" };
    await connectTools({
      connectors: fake.connectors,
      server: server({ authType: "oauth", grant: grant(connectRef) }),
      userId: "u1",
      credentials,
    }).orThrow();
    expect(
      mcp.createMCPClient.mock.calls.map(
        ([options]) => options.transport.headers,
      ),
    ).toEqual([
      { authorization: "Bearer vault" },
      { authorization: "Bearer vercel-connect" },
    ]);
    expect(tokens[1]).toEqual([
      connectRef,
      { subject: { type: "user", id: "u1" }, scopes: ["repo"] },
    ]);
  });

  it("uses the Vault OAuth provider for MCP grants", async () => {
    fakeClient();
    const { vault } = fakeVault();
    await connectTools({
      connectors: fakeConnectors().connectors,
      server: server({ authType: "oauth", grant: grant(mcpOAuthRef("s1")) }),
      userId: "u1",
      vault,
    }).orThrow();
    const options = mcp.createMCPClient.mock.calls[0]?.[0];
    expect(options.transport.authProvider.redirectUrl).toBe(
      "http://localhost/",
    );
  });

  it("explains what is missing before connecting", async () => {
    const { connectors } = fakeConnectors();
    const hints = await Promise.all(
      [
        { server: server({ enabled: false }) },
        { server: server({ authType: "header" }) },
        { server: server({ authType: "oauth" }) },
        {
          server: server({
            authType: "oauth",
            grant: grant(mcpOAuthRef("s1")),
          }),
        },
        {
          server: server({
            authType: "oauth",
            grant: grant({ provider: "vercel-connect", connector: "gh" }),
          }),
        },
      ].map(async ({ server: target }) => {
        const result = await connectTools({
          connectors,
          server: target,
          userId: "u1",
        });
        return result.ok ? undefined : result.error.hint;
      }),
    );
    expect(hints).toEqual([
      "CONNECTOR_DISABLED",
      "CONNECTOR_NOT_AUTHORIZED",
      "CONNECTOR_NOT_AUTHORIZED",
      "CONNECTOR_NOT_AUTHORIZED",
      "CONNECTOR_NOT_AUTHORIZED",
    ]);
    expect(mcp.createMCPClient).not.toHaveBeenCalled();
  });

  it("maps connection and listing failures", async () => {
    const { connectors } = fakeConnectors();
    mcp.createMCPClient.mockRejectedValueOnce(new Error("refused"));
    const refused = await connectTools({
      connectors,
      server: server(),
      userId: "u1",
    });
    expect(refused.ok ? undefined : refused.error.hint).toBe(
      "CONNECTOR_UNREACHABLE",
    );
    const { client, close } = fakeClient();
    client.listTools.mockRejectedValueOnce(new Error("boom"));
    const listed = await connectTools({
      connectors,
      server: server(),
      userId: "u1",
    });
    expect(listed.ok ? undefined : listed.error.message).toBe("boom");
    expect(close).toHaveBeenCalled();
  });

  it("closes the client when the fingerprint check fails", async () => {
    const { close } = fakeClient();
    const fake = fakeConnectors();
    const connectors = {
      ...fake.connectors,
      fingerprints: {
        check: () =>
          AsyncResult.err({ kind: "forbidden", message: "no", status: 403 }),
      },
    } as unknown as Connectors;
    const result = await connectTools({
      connectors,
      server: server(),
      userId: "u1",
    });
    expect(result.ok).toBe(false);
    expect(close).toHaveBeenCalled();
  });
});

describe("connectAll", () => {
  it("merges prefixed tools and reports the servers it skipped", async () => {
    const { close } = fakeClient();
    const { connectors } = fakeConnectors();
    const all = await connectAll(
      [server(), server({ id: "s2", name: "Off", enabled: false })],
      { connectors, userId: "u1" },
    );
    expect(Object.keys(all.tools)).toEqual([
      "git_hub_search",
      "git_hub_render",
    ]);
    expect(
      all.skipped.map(({ server: skipped, error }) => [skipped.id, error.hint]),
    ).toEqual([["s2", "CONNECTOR_DISABLED"]]);
    await all.close();
    expect(close).toHaveBeenCalledTimes(1);
  });
});
