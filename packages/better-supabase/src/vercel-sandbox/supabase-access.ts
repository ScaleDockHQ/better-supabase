import type { AsyncResult, Result } from "../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
  CredentialToken,
} from "../credentials/provider.ts";
import type {
  VercelNetworkPolicy,
  VercelNetworkRule,
  VercelSandboxCreateOptions,
} from "./vercel-sandbox.ts";

import { isRecord } from "../core/block-helpers.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";

/** The Supabase APIs a sandbox can reach, by path prefix. */
export type SupabaseAccessService =
  | "auth"
  | "functions"
  | "graphql"
  | "realtime"
  | "rest"
  | "storage";

const SERVICE_PATHS: Readonly<Record<SupabaseAccessService, string>> = {
  auth: "/auth/v1",
  functions: "/functions/v1",
  graphql: "/graphql/v1",
  realtime: "/realtime/v1",
  rest: "/rest/v1",
  storage: "/storage/v1",
};

/** The services `supabaseAccess` allows when `services` is not set. */
export const DEFAULT_SUPABASE_ACCESS_SERVICES: readonly SupabaseAccessService[] =
  ["rest", "storage", "functions"];

/** A scoped token and, when known, when it stops working. */
export interface SupabaseAccessToken {
  readonly token: string;
  /** Defaults to the token's `exp` claim. */
  readonly expiresAt?: Temporal.Instant;
}

export interface SupabaseAccessOptions {
  /** The project's API URL, such as `https://<ref>.supabase.co`. */
  readonly url: string;
  /**
   * The publishable key, added as the `apikey` header. A secret key or a
   * `service_role` key is refused.
   */
  readonly apikey?: string;
  /** Services the sandbox may call. Defaults to rest, storage and functions. */
  readonly services?: readonly SupabaseAccessService[];
  /** Milliseconds kept free before the token expires. Default 60000. */
  readonly margin?: number;
  /** The clock in epoch milliseconds, for tests. */
  readonly now?: () => number;
  /**
   * Answer a path outside `services` with a 403 from the firewall. Default
   * true. Set false for a runtime whose policy type has no `response` rule,
   * such as eve's: other paths then pass without the token.
   */
  readonly denyOtherPaths?: boolean;
}

export interface SupabaseAccessFromOptions extends SupabaseAccessOptions {
  readonly subject: CredentialSubject;
  readonly scopes?: readonly string[];
}

const FORBIDDEN_STATUS = 403;

function claimsOf(
  token: string,
): Readonly<Record<string, unknown>> | undefined {
  const part = token.split(".")[1];

  if (part === undefined) {
    return undefined;
  }

  try {
    const base64 = part.replaceAll("-", "+").replaceAll("_", "/");
    const parsed: unknown = JSON.parse(atob(base64));

    return isRecord(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

function refuseServiceKey(name: string, key: string): void {
  if (
    key.startsWith("sb_secret_") ||
    claimsOf(key)?.["role"] === "service_role"
  ) {
    throw new TypeError(
      `supabaseAccess refuses a secret or service_role key as the ${name}: it would let sandbox code bypass row level security`,
    );
  }
}

function hostOf(url: string): string {
  let parsed: URL;

  try {
    parsed = new URL(url);
  } catch {
    throw new TypeError(`supabaseAccess needs the project URL, got "${url}"`);
  }

  if (parsed.protocol !== "https:") {
    throw new TypeError(
      "supabaseAccess needs an https project URL: a sandbox cannot reach a local stack",
    );
  }

  return parsed.hostname;
}

function expiryOf(token: SupabaseAccessToken): number | undefined {
  if (token.expiresAt !== undefined) {
    return token.expiresAt.epochMilliseconds;
  }

  const exp = claimsOf(token.token)?.["exp"];

  return typeof exp === "number" ? exp * 1000 : undefined;
}

/**
 * Create options for a sandbox that reaches only your Supabase project, as the
 * user the token belongs to. The firewall adds the `authorization` and `apikey`
 * headers and pins `host`, so code in the sandbox never holds the token. Only
 * the listed services answer: any other path on the project host gets a 403
 * from the firewall, and every other host is denied. The session timeout ends
 * before the token expires, and the Postgres port is not reachable.
 *
 * Pass a short-lived user access token, never a service role key.
 */
export function supabaseAccess(
  token: SupabaseAccessToken,
  options: SupabaseAccessOptions,
): VercelSandboxCreateOptions {
  const host = hostOf(options.url);
  refuseServiceKey("token", token.token);

  if (options.apikey !== undefined) {
    refuseServiceKey("apikey", options.apikey);
  }

  const headers: Record<string, string> = {
    authorization: `Bearer ${token.token}`,
    host,
    ...(options.apikey === undefined ? {} : { apikey: options.apikey }),
  };

  const services = options.services ?? DEFAULT_SUPABASE_ACCESS_SERVICES;

  const rules: VercelNetworkRule[] = [
    ...new Set(services.map((service) => SERVICE_PATHS[service])),
  ].map((path) => ({
    match: { path: { startsWith: path } },
    transform: [{ headers }],
  }));

  if (options.denyOtherPaths !== false) {
    rules.push({
      response: {
        statusCode: FORBIDDEN_STATUS,
        contentType: "application/json",
        body: JSON.stringify({
          message:
            "This path of the project is not available from the sandbox.",
        }),
      },
    });
  }

  const networkPolicy: VercelNetworkPolicy = { allow: { [host]: rules } };
  const expires = expiryOf(token);

  if (expires === undefined) {
    return { networkPolicy };
  }

  const now = (options.now ?? Date.now)();

  return {
    networkPolicy,
    timeout: Math.max(1000, expires - now - (options.margin ?? 60_000)),
  };
}

/**
 * `supabaseAccess` with the token from a credential provider, such as a
 * `jwt-bearer` subject that signs a short JWT for the user.
 */
export function supabaseAccessFrom(
  credentials: Pick<CredentialProvider, "getToken">,
  ref: CredentialRef,
  options: SupabaseAccessFromOptions,
): AsyncResult<VercelSandboxCreateOptions> {
  const build = (
    issued: CredentialToken,
  ): Result<VercelSandboxCreateOptions> => {
    try {
      return ok(
        supabaseAccess(
          {
            token: issued.token,
            ...(issued.expiresAt === undefined
              ? {}
              : { expiresAt: issued.expiresAt }),
          },
          options,
        ),
      );
    } catch (cause) {
      return err(
        dbError(
          "invalid_input",
          cause instanceof Error ? cause.message : "Invalid Supabase access",
          { hint: "SANDBOX_SUPABASE_ACCESS_INVALID" },
        ),
      );
    }
  };

  return credentials
    .getToken(ref, {
      subject: options.subject,
      ...(options.scopes === undefined ? {} : { scopes: options.scopes }),
    })
    .andThen((issued) => Promise.resolve(build(issued)));
}
