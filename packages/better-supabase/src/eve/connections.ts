import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
} from "../credentials/provider.ts";

import { type DbError, DbException } from "../core/errors.ts";

/** eve's `ConnectionAuthorizationRequiredError`, matched by name. */
export class ConnectionAuthorizationRequiredError extends Error {
  override readonly name = "ConnectionAuthorizationRequiredError";
  readonly connectionName: string;

  constructor(
    connectionName: string,
    options: { readonly message?: string } = {},
  ) {
    super(
      options.message ?? `Connection "${connectionName}" needs authorization`,
    );
    this.connectionName = connectionName;
  }
}

/** eve's `ConnectionAuthorizationFailedError`, matched by name. */
export class ConnectionAuthorizationFailedError extends Error {
  override readonly name = "ConnectionAuthorizationFailedError";
  readonly connectionName: string;
  readonly reason: string;
  readonly retryable: boolean;

  constructor(
    connectionName: string,
    options: {
      readonly message?: string;
      readonly reason: string;
      readonly retryable: boolean;
    },
  ) {
    super(
      options.message ??
        `Connection "${connectionName}" failed: ${options.reason}`,
    );
    this.connectionName = connectionName;
    this.reason = options.reason;
    this.retryable = options.retryable;
  }
}

/** The identity eve resolves for a connection callback. */
export type EveConnectionPrincipal =
  | { readonly type: "app" }
  | {
      readonly type: "user";
      readonly id: string;
      readonly issuer?: string;
      readonly attributes?: Readonly<
        Record<string, string | readonly string[]>
      >;
    };

export interface EveConnectionRequest {
  readonly principal: EveConnectionPrincipal;
  readonly connection: { readonly url: string };
}

export interface EveTokenResult {
  readonly token: string;
  /** Epoch milliseconds. */
  readonly expiresAt?: number;
  readonly providerSubject?: string;
}

export interface EveAuthorizationChallenge {
  readonly challenge: {
    readonly url?: string;
    readonly displayName?: string;
    readonly instructions?: string;
  };
}

/** A `getToken`-only connection `auth`: eve never runs a consent flow. */
export interface EveTokenAuthorization {
  readonly credentialOwner: "app" | "user";
  readonly displayName?: string;
  getToken(request: EveConnectionRequest): Promise<EveTokenResult>;
  readonly startAuthorization?: undefined;
  readonly completeAuthorization?: undefined;
}

/** An interactive connection `auth`, which eve allows only for users. */
export interface EveInteractiveAuthorization {
  readonly principalType: "user";
  readonly displayName?: string;
  getToken(request: EveConnectionRequest): Promise<EveTokenResult>;
  startAuthorization(
    request: EveConnectionRequest & { readonly callbackUrl: string },
  ): Promise<EveAuthorizationChallenge>;
  completeAuthorization(
    request: EveConnectionRequest & {
      readonly callbackUrl: string;
      readonly callback: {
        readonly params: Readonly<Record<string, string>>;
        readonly method: string;
      };
    },
  ): Promise<EveTokenResult>;
}

/** A connection `auth` value for eve's `defineMcpClientConnection`. */
export type EveConnectionAuthorization =
  | EveTokenAuthorization
  | EveInteractiveAuthorization;

export interface CredentialAuthOptions {
  readonly provider: CredentialProvider;
  readonly ref: CredentialRef;
  /** `app` uses the app's credential; `user` the principal's own. */
  readonly owner: "app" | "user";
  /** The connection's name in errors. Defaults to the ref's provider. */
  readonly connection?: string;
  readonly scopes?: readonly string[];
  /** For `user`: let eve send the user to connect the account when the provider can. Defaults to true. */
  readonly interactive?: boolean;
}

const AUTHORIZATION_HINTS = new Set([
  "CREDENTIAL_AUTHORIZATION_REQUIRED",
  "CREDENTIAL_NOT_FOUND",
  "CREDENTIAL_SUBJECT_REQUIRED",
]);

function connectionError(name: string, error: DbError): Error {
  const hint = "hint" in error ? error.hint : undefined;
  if (
    error.kind === "not_found" ||
    (typeof hint === "string" && AUTHORIZATION_HINTS.has(hint))
  )
    return new ConnectionAuthorizationRequiredError(name, {
      message: error.message,
    });
  if (error.kind === "forbidden" || error.kind === "invalid_input")
    return new ConnectionAuthorizationFailedError(name, {
      message: error.message,
      reason: typeof hint === "string" ? hint : error.kind,
      retryable: false,
    });
  return new DbException(error);
}

/**
 * An eve connection `authorization` over a better-supabase
 * `CredentialProvider` (Vault, Vercel Connect or your own): tokens come from
 * the provider for the app or for the session's user. A user without a stored
 * credential gets eve's authorization flow when the provider supports one.
 */
export function credentialAuth(
  options: CredentialAuthOptions,
): EveConnectionAuthorization {
  const name = options.connection ?? options.ref.provider;
  const subjectOf = (principal: EveConnectionPrincipal): CredentialSubject => {
    if (options.owner === "app") return { type: "app" };
    if (principal.type !== "user")
      throw new ConnectionAuthorizationRequiredError(name, {
        message: `Connection "${name}" needs a signed-in user`,
      });
    return principal.issuer === undefined
      ? { type: "user", id: principal.id }
      : { type: "user", id: principal.id, issuer: principal.issuer };
  };
  const displayName =
    options.connection === undefined ? {} : { displayName: options.connection };
  const getToken = async ({
    principal,
  }: EveConnectionRequest): Promise<EveTokenResult> => {
    const result = await options.provider.getToken(options.ref, {
      subject: subjectOf(principal),
      ...(options.scopes === undefined ? {} : { scopes: options.scopes }),
    });
    if (!result.ok) throw connectionError(name, result.error);
    const { token, expiresAt } = result.data;
    return expiresAt === undefined
      ? { token }
      : { token, expiresAt: expiresAt.epochMilliseconds };
  };

  const { provider, ref } = options;
  if (
    options.owner === "app" ||
    options.interactive === false ||
    !provider.capabilities(ref).authorization ||
    !provider.startAuthorization ||
    !provider.completeAuthorization
  )
    return { credentialOwner: options.owner, ...displayName, getToken };
  const start = provider.startAuthorization.bind(provider);
  const complete = provider.completeAuthorization.bind(provider);
  return {
    principalType: "user",
    ...displayName,
    getToken,
    startAuthorization: async ({ principal, callbackUrl }) => {
      const result = await start(ref, {
        subject: subjectOf(principal),
        redirectUri: callbackUrl,
        ...(options.scopes === undefined ? {} : { scopes: options.scopes }),
      });
      if (!result.ok) throw connectionError(name, result.error);
      return { challenge: { url: result.data.url } };
    },
    completeAuthorization: async (request) => {
      const callback = new URL(request.callbackUrl);
      for (const [key, value] of Object.entries(request.callback.params))
        callback.searchParams.set(key, value);
      const result = await complete(ref, {
        subject: subjectOf(request.principal),
        callback,
      });
      if (!result.ok) throw connectionError(name, result.error);
      return getToken(request);
    },
  };
}
