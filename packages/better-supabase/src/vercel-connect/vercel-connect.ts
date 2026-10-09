import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
  CredentialToken,
} from "../credentials/provider.ts";

import { isRecord } from "../core/block-helpers.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../core/result.ts";
import { optionalTemporal } from "../core/temporal.ts";

interface ConnectTokenParams {
  subject: CredentialSubject;
  installationId?: string;
  scopes?: string[];
}

interface ConnectOptions {
  vercelToken?: string;
}

/** The part of `@vercel/connect` this provider calls, typed structurally. */
export interface VercelConnectModule {
  getTokenResponse(
    connector: string,
    params: ConnectTokenParams,
    options?: ConnectOptions,
  ): Promise<{ token: string; expiresAt: number }>;
  revokeToken(
    connector: string,
    params: { subject: CredentialSubject; installationId?: string },
    options?: ConnectOptions,
  ): Promise<void>;
  startAuthorization(
    connector: string,
    params: ConnectTokenParams,
    options?: { vercelToken?: string; callbackUrl?: string },
  ): Promise<{ url: string }>;
}

/** A Vercel Connect connector; `connector` is its UID. */
export interface VercelConnectRef {
  readonly provider: "vercel-connect";
  readonly connector: string;
  readonly installationId?: string;
  readonly scopes?: readonly string[];
}

export interface VercelConnectCredentialsOptions {
  /** Defaults to the OIDC token `@vercel/connect` reads on Vercel. */
  readonly vercelToken?: string;
  /** Returns `@vercel/connect`; defaults to importing it on first use. */
  readonly load?: () => Promise<unknown>;
}

const isModule = (value: unknown): value is VercelConnectModule =>
  isRecord(value) &&
  typeof value["getTokenResponse"] === "function" &&
  typeof value["revokeToken"] === "function" &&
  typeof value["startAuthorization"] === "function";

/**
 * Loads `@vercel/connect` on first use. The specifier is a variable so
 * bundlers leave the optional peer out of apps that don't use it.
 */
async function loadConnect(): Promise<unknown> {
  const specifier = "@vercel/connect";
  try {
    return await import(specifier);
  } catch {
    return undefined;
  }
}

function connectRef(ref: CredentialRef): Result<VercelConnectRef> {
  const { connector, installationId, scopes } = ref;
  if (ref.provider !== "vercel-connect" || typeof connector !== "string")
    return err(
      dbError(
        "invalid_input",
        `vercel-connect resolves refs with a connector, not "${ref.provider}"`,
        { hint: "CREDENTIAL_REF_INVALID" },
      ),
    );
  return ok({
    provider: "vercel-connect",
    connector,
    ...(typeof installationId === "string" ? { installationId } : {}),
    ...(Array.isArray(scopes)
      ? {
          scopes: scopes.filter(
            (scope): scope is string => typeof scope === "string",
          ),
        }
      : {}),
  });
}

/** Maps the `@vercel/connect` error classes by name, without importing them. */
function connectError(cause: unknown): Result<never> {
  const name = cause instanceof Error ? cause.name : "";
  const message = cause instanceof Error ? cause.message : String(cause);
  switch (name) {
    case "UserAuthorizationRequiredError": {
      return err(
        dbError("forbidden", message, {
          hint: "CREDENTIAL_AUTHORIZATION_REQUIRED",
        }),
      );
    }
    case "ConnectorInstallationRequiredError": {
      return err(
        dbError("forbidden", message, {
          hint: "CREDENTIAL_INSTALLATION_REQUIRED",
        }),
      );
    }
    case "NoValidTokenError": {
      return err(
        dbError("not_found", message, { hint: "CREDENTIAL_NOT_FOUND" }),
      );
    }
    default: {
      return err(dbError("network", message));
    }
  }
}

/**
 * A `CredentialProvider` over Vercel Connect: OAuth tokens for a connector,
 * for the app or a user, refreshed by Vercel. Needs `@vercel/connect`.
 */
export function vercelConnectCredentials(
  options: VercelConnectCredentialsOptions = {},
): CredentialProvider {
  let loaded: Promise<VercelConnectModule> | undefined;
  const connect = (): Promise<VercelConnectModule> =>
    (loaded ??= (options.load ?? loadConnect)().then((value) => {
      if (!isModule(value)) {
        loaded = undefined;
        throw new TypeError(
          "vercelConnectCredentials needs the @vercel/connect package: pnpm add @vercel/connect",
        );
      }
      return value;
    }));
  const connectOptions: ConnectOptions =
    options.vercelToken === undefined
      ? {}
      : { vercelToken: options.vercelToken };

  const run = <T>(
    ref: CredentialRef,
    subject: CredentialSubject,
    fn: (module: VercelConnectModule, parsed: VercelConnectRef) => Promise<T>,
  ): AsyncResult<T> => {
    // Connect has no tenant namespace: the app subject would resolve the
    // app's own installation for every tenant.
    if (ref.tenant !== undefined && subject.type === "app")
      return AsyncResult.err(
        dbError(
          "forbidden",
          "vercel-connect has no per-tenant credentials; use a user subject or a provider with tenant namespaces",
          { hint: "CREDENTIAL_REF_FOREIGN" },
        ),
      );
    const parsed = connectRef(ref);
    if (!parsed.ok) return AsyncResult.err(parsed.error);
    return AsyncResult.from(async () => {
      const module = await connect();
      try {
        return ok(await fn(module, parsed.data));
      } catch (cause) {
        return connectError(cause);
      }
    });
  };

  const params = (
    parsed: VercelConnectRef,
    subject: CredentialSubject,
    scopes: readonly string[] | undefined,
    installationId: string | undefined,
  ): ConnectTokenParams => {
    const chosen = scopes ?? parsed.scopes;
    const installation = installationId ?? parsed.installationId;
    return {
      subject,
      ...(installation === undefined ? {} : { installationId: installation }),
      ...(chosen === undefined ? {} : { scopes: [...chosen] }),
    };
  };

  return {
    apiVersion: 1,
    name: "vercel-connect",
    getToken(ref, getOptions) {
      return run(
        ref,
        getOptions.subject,
        async (module, parsed): Promise<CredentialToken> => {
          const response = await module.getTokenResponse(
            parsed.connector,
            params(
              parsed,
              getOptions.subject,
              getOptions.scopes,
              getOptions.installationId,
            ),
            connectOptions,
          );
          const temporal = optionalTemporal();
          return {
            token: response.token,
            ...(temporal === undefined
              ? {}
              : {
                  expiresAt: temporal.Instant.fromEpochMilliseconds(
                    response.expiresAt,
                  ),
                }),
            headers: { authorization: `Bearer ${response.token}` },
          };
        },
      );
    },
    capabilities() {
      return {
        userSubjects: true,
        authorization: true,
        revoke: true,
        inbound: false,
      };
    },
    startAuthorization(ref, startOptions) {
      return run(ref, startOptions.subject, async (module, parsed) => {
        const { url } = await module.startAuthorization(
          parsed.connector,
          params(parsed, startOptions.subject, startOptions.scopes, undefined),
          { ...connectOptions, callbackUrl: startOptions.redirectUri },
        );
        return { url };
      });
    },
    revoke(ref, revokeOptions) {
      return run(ref, revokeOptions.subject, async (module, parsed) => {
        await module.revokeToken(
          parsed.connector,
          {
            subject: revokeOptions.subject,
            ...(parsed.installationId === undefined
              ? {}
              : { installationId: parsed.installationId }),
          },
          connectOptions,
        );
        return true;
      });
    },
  };
}
