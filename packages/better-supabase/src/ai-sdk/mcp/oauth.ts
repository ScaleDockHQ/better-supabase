import {
  auth,
  type OAuthClientInformation,
  type OAuthClientMetadata,
  type OAuthClientProvider,
  type OAuthTokens,
} from "@ai-sdk/mcp";

import type {
  ConnectorServer,
  Connectors,
} from "../../blocks/connectors/connectors.ts";
import type { CredentialRef } from "../../credentials/provider.ts";
import type { VaultCredentials } from "../../credentials/vault.ts";

import { errorText, isRecord } from "../../core/block-helpers.ts";
import { DbException, dbError, type DbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
import { nowInstant } from "../../core/temporal.ts";

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

export const isOAuthRef = (ref: CredentialRef): boolean =>
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
    if (cached !== undefined) {
      return cached;
    }

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

    if (!saved.ok) {
      throw new DbException(saved.error);
    }
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

      if (verifier === undefined) {
        throw new Error("No PKCE verifier is stored");
      }

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

      if (!saved.ok) {
        throw new DbException(saved.error);
      }
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

      if (scope === "tokens") {
        await store({ tokens: undefined });
      }

      if (scope === "verifier") {
        await store({ codeVerifier: undefined });
      }
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
