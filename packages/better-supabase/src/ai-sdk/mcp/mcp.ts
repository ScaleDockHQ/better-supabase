import {
  auth,
  createMCPClient,
  type ElicitResult,
  ElicitationRequestSchema,
  type ElicitationRequest,
  type InitializeResult,
  type ListToolsResult,
  type MCPClient,
  mcpAppClientCapabilities,
  type OAuthClientInformation,
  type OAuthClientMetadata,
  type OAuthClientProvider,
  type OAuthTokens,
  splitMCPAppTools,
} from "@ai-sdk/mcp";
import { fingerprintTools, type ToolSet } from "ai";

import type {
  Connectors,
  ConnectorServer,
} from "../../blocks/connectors/connectors.ts";
import type { DbError } from "../../core/errors.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";
import type { VaultCredentials } from "../../credentials/vault.ts";

import { errorText, isRecord, sha256Hex } from "../../blocks/shared.ts";
import { DbException, dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
import { nowInstant } from "../../core/temporal.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
} from "../../credentials/provider.ts";

/** What the Vault keeps for one user's OAuth connection to one server. */
interface StoredConnection {
  tokens?: OAuthTokens | undefined;
  codeVerifier?: string | undefined;
  state?: string | undefined;
}

/** The Vault ref of a user's OAuth connection to a server. */
export function mcpOAuthRef(serverId: string): CredentialRef {
  return {
    provider: "vault",
    secret: `mcp:${serverId}`,
    scope: "user",
    oauth: "mcp",
  };
}

const clientRef = (serverId: string): CredentialRef => ({
  provider: "vault",
  secret: `mcp-client:${serverId}`,
});

const isOAuthRef = (ref: CredentialRef): boolean =>
  ref.provider === "vault" && ref["oauth"] === "mcp";

export interface VaultOAuthProviderOptions {
  readonly vault: VaultCredentials;
  readonly server: Pick<ConnectorServer, "id" | "clientMetadata" | "scopes">;
  readonly userId: string;
  /** The app's OAuth callback URL. */
  readonly redirectUrl: string;
  /** Overrides the server's `client_metadata`. */
  readonly clientMetadata?: OAuthClientMetadata;
}

export interface VaultOAuthProvider extends OAuthClientProvider {
  /** Where `auth` asked to send the user, once it did. */
  readonly authorizationUrl: URL | undefined;
}

/**
 * An `OAuthClientProvider` that keeps the user's tokens, PKCE verifier and
 * state in one per-user Vault secret, and the dynamically registered client
 * in one secret per server.
 */
export function vaultOAuthProvider(
  options: VaultOAuthProviderOptions,
): VaultOAuthProvider {
  const { vault, server, userId } = options;
  const ref = mcpOAuthRef(server.id);
  const subject = { type: "user" as const, id: userId };
  let cached: StoredConnection | undefined;
  let authorizationUrl: URL | undefined;

  const parse = (text: string): Record<string, unknown> | undefined => {
    try {
      const value: unknown = JSON.parse(text);
      return isRecord(value) ? value : undefined;
    } catch {
      return undefined;
    }
  };
  const load = async (): Promise<StoredConnection> => {
    if (cached !== undefined) return cached;
    const stored = await vault.getToken(ref, { subject });
    // SAFETY: only this provider writes the secret, as a StoredConnection.
    cached = (stored.ok ? parse(stored.data.token) : undefined) ?? {};
    return cached;
  };
  const store = async (patch: StoredConnection): Promise<void> => {
    const next = { ...(await load()), ...patch };
    cached = next;
    const saved = await vault.set(ref, JSON.stringify(next), {
      subject,
      description: `MCP connection to ${server.id}`,
    });
    if (!saved.ok) throw new DbException(saved.error);
  };
  const metadata: OAuthClientMetadata = options.clientMetadata ?? {
    client_name: "better-supabase",
    grant_types: ["authorization_code", "refresh_token"],
    response_types: ["code"],
    token_endpoint_auth_method: "none",
    ...server.clientMetadata,
    redirect_uris: [options.redirectUrl],
    ...(server.scopes.length === 0 ? {} : { scope: server.scopes.join(" ") }),
  };

  return {
    get authorizationUrl() {
      return authorizationUrl;
    },
    get redirectUrl() {
      return options.redirectUrl;
    },
    get clientMetadata() {
      return metadata;
    },
    tokens: async () => (await load()).tokens,
    saveTokens: (tokens) => store({ tokens }),
    redirectToAuthorization: (url) => {
      authorizationUrl = url;
    },
    saveCodeVerifier: (codeVerifier) => store({ codeVerifier }),
    codeVerifier: async () => {
      const verifier = (await load()).codeVerifier;
      if (verifier === undefined) throw new Error("No PKCE verifier is stored");
      return verifier;
    },
    state: () => crypto.randomUUID(),
    saveState: (state) => store({ state }),
    storedState: async () => (await load()).state,
    clientInformation: async () => {
      const stored = await vault.getToken(clientRef(server.id), {
        subject: { type: "app" },
      });
      // SAFETY: only saveClientInformation writes the secret.
      return stored.ok
        ? (parse(stored.data.token) as OAuthClientInformation | undefined)
        : undefined;
    },
    isClientInformationDynamicallyRegistered: () => true,
    saveClientInformation: async (information) => {
      const saved = await vault.set(
        clientRef(server.id),
        JSON.stringify(information),
        { description: `MCP client for ${server.id}` },
      );
      if (!saved.ok) throw new DbException(saved.error);
    },
    invalidateCredentials: async (scope) => {
      if (scope === "all" || scope === "client") {
        await vault.revoke(clientRef(server.id), { subject: { type: "app" } });
      }
      if (scope === "all") {
        cached = {};
        await vault.revoke(ref, { subject });
        return;
      }
      if (scope === "tokens") await store({ tokens: undefined });
      if (scope === "verifier") await store({ codeVerifier: undefined });
    },
  };
}

export interface AuthorizeConnectorOptions {
  readonly connectors: Connectors;
  readonly vault: VaultCredentials;
  readonly server: ConnectorServer;
  readonly userId: string;
  readonly redirectUrl: string;
}

async function recordGrant(
  options: AuthorizeConnectorOptions,
  provider: OAuthClientProvider,
): Promise<Result<void>> {
  const expiresIn = (await provider.tokens())?.expires_in;
  const recorded = await options.connectors.grants.record(
    options.server.id,
    options.userId,
    mcpOAuthRef(options.server.id),
    {
      scopes: options.server.scopes,
      ...(expiresIn === undefined
        ? {}
        : {
            expiresAt: nowInstant().add({
              seconds: Math.floor(expiresIn),
            }),
          }),
    },
  );
  return recorded.ok ? ok(undefined) : recorded;
}

const authFailed = (cause: unknown): DbError =>
  dbError("forbidden", errorText(cause), {
    hint: "CONNECTOR_AUTHORIZATION_FAILED",
  });

/**
 * Starts the user's OAuth connection to a server: `{ url }` to send them
 * to, or `{ url: undefined }` when stored tokens still work and the grant
 * is recorded.
 */
export function authorizeConnector(
  options: AuthorizeConnectorOptions,
): AsyncResult<{ readonly url: string | undefined }> {
  return AsyncResult.from(async () => {
    const provider = vaultOAuthProvider(options);
    try {
      const result = await auth(provider, {
        serverUrl: options.server.url,
        ...(options.server.scopes.length === 0
          ? {}
          : { scope: options.server.scopes.join(" ") }),
      });
      if (result === "REDIRECT") {
        return ok({ url: provider.authorizationUrl?.toString() });
      }
    } catch (cause) {
      return err(authFailed(cause));
    }
    const recorded = await recordGrant(options, provider);
    return recorded.ok ? ok({ url: undefined }) : recorded;
  });
}

/**
 * Finishes the connection from the OAuth callback: checks the state,
 * exchanges the code, keeps the tokens in Vault and records the grant.
 */
export function completeConnector(
  options: AuthorizeConnectorOptions & { readonly callback: URL | string },
): AsyncResult<void> {
  return AsyncResult.from(async () => {
    const callback = new URL(options.callback);
    const code = callback.searchParams.get("code");
    const state = callback.searchParams.get("state") ?? undefined;
    if (code === null) {
      return err(
        authFailed(
          callback.searchParams.get("error") ?? "The callback has no code",
        ),
      );
    }
    const provider = vaultOAuthProvider(options);
    const stored = await provider.storedState?.();
    if (stored !== undefined && stored !== state) {
      return err(authFailed("The callback state does not match"));
    }
    try {
      await auth(provider, {
        serverUrl: options.server.url,
        authorizationCode: code,
        ...(state === undefined ? {} : { callbackState: state }),
        ...(callback.searchParams.has("iss")
          ? { callbackIssuer: callback.searchParams.get("iss") ?? "" }
          : {}),
      });
    } catch (cause) {
      return err(authFailed(cause));
    }
    return recordGrant(options, provider);
  });
}

export interface ConnectToolsOptions {
  /** The connectors block as the user. */
  readonly connectors: Connectors;
  readonly server: ConnectorServer;
  readonly userId: string;
  /** For `oauth` servers whose grant lives in Vault. */
  readonly vault?: VaultCredentials;
  /** Resolves `header` refs and grants from other providers (Vercel Connect). */
  readonly credentials?: CredentialProvider;
  /** The OAuth callback URL, for refreshing tokens. */
  readonly redirectUrl?: string;
  /** Reuses the MCP session per chat. */
  readonly chatKey?: string;
  /** Asks for MCP Apps and returns their app-only tools apart. */
  readonly apps?: boolean;
  /** Answers the server's elicitation requests; declined without one. */
  readonly elicit?: (request: ElicitationRequest) => Promise<ElicitResult>;
  /** Prefixes tool names, such as `github_`, so servers don't collide. */
  readonly prefix?: string;
}

export interface ConnectedTools {
  readonly tools: ToolSet;
  /** Tools only an MCP App may call; empty unless `apps`. */
  readonly appTools: ToolSet;
  readonly client: MCPClient;
  readonly fingerprint: string;
  close(): Promise<void>;
}

const forbidden = (message: string, hint: string): DbError =>
  dbError("forbidden", message, { hint });

async function authOf(options: ConnectToolsOptions): Promise<
  | {
      ok: true;
      headers: Record<string, string>;
      provider?: OAuthClientProvider;
    }
  | { ok: false; error: DbError }
> {
  const { server } = options;
  switch (server.authType) {
    case "none": {
      return { ok: true, headers: {} };
    }
    case "header": {
      if (
        server.credentialRef === undefined ||
        options.credentials === undefined
      ) {
        return {
          ok: false,
          error: forbidden(
            `${server.name} needs credentials`,
            "CONNECTOR_NOT_AUTHORIZED",
          ),
        };
      }
      if (!credentialRefInTenant(server.credentialRef, server.organizationId)) {
        return {
          ok: false,
          error: foreignCredentialRef(server.organizationId),
        };
      }
      const token = await options.credentials.getToken(server.credentialRef, {
        subject: { type: "app" },
      });
      return token.ok
        ? { ok: true, headers: { ...token.data.headers } }
        : { ok: false, error: token.error };
    }
    case "oauth": {
      const grant = server.grant;
      if (grant === undefined) {
        return {
          ok: false,
          error: forbidden(
            `Connect ${server.name} first`,
            "CONNECTOR_NOT_AUTHORIZED",
          ),
        };
      }
      if (isOAuthRef(grant.credentialRef)) {
        if (options.vault === undefined) {
          return {
            ok: false,
            error: forbidden(
              "connectTools needs vault for OAuth grants",
              "CONNECTOR_NOT_AUTHORIZED",
            ),
          };
        }
        return {
          ok: true,
          headers: {},
          provider: vaultOAuthProvider({
            vault: options.vault,
            server,
            userId: options.userId,
            redirectUrl: options.redirectUrl ?? "http://localhost/",
          }),
        };
      }
      if (options.credentials === undefined) {
        return {
          ok: false,
          error: forbidden(
            `connectTools needs credentials for ${grant.credentialRef.provider}`,
            "CONNECTOR_NOT_AUTHORIZED",
          ),
        };
      }
      const token = await options.credentials.getToken(grant.credentialRef, {
        subject: { type: "user", id: options.userId },
        scopes: grant.scopes,
      });
      return token.ok
        ? { ok: true, headers: { ...token.data.headers } }
        : { ok: false, error: token.error };
    }
    default: {
      const unreachable: never = server.authType;
      return unreachable;
    }
  }
}

/** One digest over the per-tool fingerprints, in name order. */
async function digestOf(fingerprints: Record<string, string>): Promise<string> {
  const entries = Object.entries(fingerprints).toSorted(([a], [b]) =>
    a < b ? -1 : a > b ? 1 : 0,
  );
  return `sha256:${await sha256Hex(JSON.stringify(entries))}`;
}

function prefixed(tools: ToolSet, prefix: string | undefined): ToolSet {
  if (prefix === undefined || prefix === "") return tools;
  return Object.fromEntries(
    Object.entries(tools).map(([name, tool]) => [`${prefix}${name}`, tool]),
  );
}

/**
 * Connects to a server as the user and returns its tools, once the
 * fingerprint of their definitions is approved. A changed tool list waits
 * for an admin (`CONNECTOR_TOOLS_CHANGED`) and the client is closed. Close
 * the client when the run ends.
 */
export function connectTools(
  options: ConnectToolsOptions,
): AsyncResult<ConnectedTools> {
  const { connectors, server } = options;
  return AsyncResult.from(async () => {
    if (!server.enabled) {
      return err(
        forbidden(`${server.name} is turned off`, "CONNECTOR_DISABLED"),
      );
    }
    const authorization = await authOf(options);
    if (!authorization.ok) return err(authorization.error);
    const session = await connectors.sessions.get(server.id, options.chatKey);
    const previous = session.ok ? session.data : undefined;
    const chatKey = options.chatKey ?? "";
    let sessionId = previous?.sessionId;
    let client: MCPClient;
    try {
      client = await createMCPClient({
        transport: {
          type: server.transport,
          url: server.url,
          headers: authorization.headers,
          ...(authorization.provider === undefined
            ? {}
            : { authProvider: authorization.provider }),
          ...(previous?.sessionId === undefined
            ? {}
            : { initialSessionId: previous.sessionId }),
          onSessionIdChange: (next) => {
            sessionId = next;
            if (next === undefined) {
              void connectors.sessions.forget(server.id, chatKey);
            }
          },
        },
        ...(previous?.initializeResult === undefined ||
        previous.sessionId === undefined
          ? {}
          : {
              // SAFETY: the stored value is the server's initialize result.
              initialInitializeResult:
                previous.initializeResult as InitializeResult,
            }),
        capabilities: {
          ...(options.apps === true ? mcpAppClientCapabilities : {}),
          elicitation: {},
        },
      });
    } catch (cause) {
      return err(
        dbError("network", errorText(cause), { hint: "CONNECTOR_UNREACHABLE" }),
      );
    }
    const close = (): Promise<void> => client.close().catch(() => {});
    try {
      client.onElicitationRequest(ElicitationRequestSchema, (request) =>
        options.elicit === undefined
          ? { action: "decline" }
          : options.elicit(request),
      );
      if (sessionId !== undefined) {
        void connectors.sessions.save(server.id, {
          chatKey,
          sessionId,
          initializeResult: { ...client.initializeResult },
        });
      }
      const definitions: ListToolsResult = await client.listTools();
      const split =
        options.apps === true
          ? splitMCPAppTools(definitions)
          : { modelVisible: definitions, appVisible: { tools: [] } };
      const tools = client.toolsFromDefinitions(split.modelVisible);
      const fingerprints = await fingerprintTools(tools);
      const fingerprint = await digestOf(fingerprints);
      const status = await connectors.fingerprints.check(
        server.id,
        fingerprint,
        fingerprints,
      );
      if (!status.ok) {
        await close();
        return status;
      }
      if (status.data !== "approved") {
        await close();
        return err(
          forbidden(
            `The tools of ${server.name} changed and wait for an admin's approval`,
            "CONNECTOR_TOOLS_CHANGED",
          ),
        );
      }
      return ok({
        tools: prefixed(tools, options.prefix),
        appTools: prefixed(
          client.toolsFromDefinitions(split.appVisible),
          options.prefix,
        ),
        client,
        fingerprint,
        close,
      });
    } catch (cause) {
      await close();
      return err(
        dbError("network", errorText(cause), { hint: "CONNECTOR_UNREACHABLE" }),
      );
    }
  });
}

export interface ConnectAllResult {
  readonly tools: ToolSet;
  /** The servers left out, with why. */
  readonly skipped: readonly {
    readonly server: ConnectorServer;
    readonly error: DbError;
  }[];
  close(): Promise<void>;
}

/**
 * Connects to several servers (an agent's `connectorIds`) and merges their
 * tools, each prefixed with its server's name. A server that fails is
 * skipped and reported, not fatal.
 */
export async function connectAll(
  servers: readonly ConnectorServer[],
  options: Omit<ConnectToolsOptions, "server" | "prefix">,
): Promise<ConnectAllResult> {
  const results = await Promise.all(
    servers.map(async (server) => ({
      server,
      result: await connectTools({
        ...options,
        server,
        prefix: `${server.name.toLowerCase().replaceAll(/[^a-z0-9]+/g, "_")}_`,
      }),
    })),
  );
  const tools: ToolSet = {};
  const skipped: { server: ConnectorServer; error: DbError }[] = [];
  const open: ConnectedTools[] = [];
  for (const { server, result } of results) {
    if (result.ok) {
      Object.assign(tools, result.data.tools);
      open.push(result.data);
    } else {
      skipped.push({ server, error: result.error });
    }
  }
  return {
    tools,
    skipped,
    close: async () => {
      await Promise.all(open.map((connected) => connected.close()));
    },
  };
}
