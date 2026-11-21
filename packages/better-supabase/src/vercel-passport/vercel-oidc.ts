import type { AuthResolver, ResolvedState } from "../auth/resolve.ts";
import type { JwksStore } from "../core/jwks-cache.ts";
import type { Jwks } from "../core/jws.ts";

import { dbError } from "../core/errors.ts";
import { jwksSource } from "../core/jwks-cache.ts";
import { verifySignature } from "./vercel-passport.ts";

/** Vercel's OIDC issuer; a token's `iss` is it or it followed by `/<team>`. */
export const VERCEL_OIDC_ISSUER = "https://oidc.vercel.com";

/** Where Vercel publishes the keys deployment OIDC tokens are signed with. */
export const VERCEL_OIDC_JWKS_URL = "https://oidc.vercel.com/.well-known/jwks";

/** The claims `vercelOidcResolver` reads from a deployment's OIDC token. */
export interface VercelOidcClaims {
  readonly iss: string;
  readonly sub: string;
  readonly aud?: string | readonly string[];
  readonly owner?: string;
  readonly owner_id?: string;
  readonly project?: string;
  readonly project_id: string;
  readonly environment: string;
  readonly [claim: string]: unknown;
}

/** The service account a verified deployment acts as. */
export interface VercelServiceAccount {
  readonly name: string;
  /** The permission keys the deployment holds, as an API key's scopes. */
  readonly scopes: readonly string[];
  /** Scopes the deployment to one tenant. */
  readonly organizationId?: string;
  /** Acts as this user instead of as a service. */
  readonly userId?: string;
}

export interface VercelOidcResolverOptions {
  /**
   * The Vercel project ids (`project_id`) a token must be for, such as
   * `process.env.VERCEL_PROJECT_ID`. `"*"` accepts any project and then needs
   * `ownerId` or `audience`.
   */
  readonly projectId: string | readonly string[];
  /** The environments a token must be for. Default: `"*"`. */
  readonly environment?: string | readonly string[];
  /** The Vercel team or user id (`owner_id`) a token must carry. */
  readonly ownerId?: string;
  /** Audiences one of which the token's `aud` must hold. */
  readonly audience?: string | readonly string[];
  /**
   * Maps the verified deployment to a service account. Return `undefined` to
   * refuse it: the request then resolves to an `invalid` state. This is the
   * only place a deployment gets permissions.
   */
  readonly map: (
    claims: VercelOidcClaims,
  ) =>
    | VercelServiceAccount
    | undefined
    | Promise<VercelServiceAccount | undefined>;
  /**
   * The header the token is read from. Default: `Authorization: Bearer`. A
   * Bearer token whose issuer is not Vercel's falls through to the other
   * resolvers, so Supabase user tokens still verify.
   */
  readonly header?: string;
  /** The key set: a JWKS URL or inline keys. Default: `VERCEL_OIDC_JWKS_URL`. */
  readonly jwks?: URL | Jwks;
  readonly fetch?: typeof fetch;
  /** Epoch milliseconds. */
  readonly now?: () => number;
  /** Seconds of clock skew allowed on `exp` and `nbf`. Default: 30. */
  readonly leeway?: number;
  /** Shares the fetched key set between instances (`vercelRuntimeCache`). */
  readonly store?: JwksStore;
}

const ANY = "*";
const DEFAULT_LEEWAY = 30;
const BEARER = /^Bearer\s+([\w.~+/-]+=*)\s*$/i;

const listOf = (value: string | readonly string[]): readonly string[] =>
  typeof value === "string" ? [value] : value;

const isVercelIssuer = (iss: unknown): iss is string =>
  iss === VERCEL_OIDC_ISSUER ||
  (typeof iss === "string" && iss.startsWith(`${VERCEL_OIDC_ISSUER}/`));

/** The unverified `iss` of a compact JWT, used only to route the request. */
function unverifiedIssuer(token: string): string | undefined {
  const body = token.split(".")[1];

  if (body === undefined) {
    return undefined;
  }

  try {
    const bytes = Uint8Array.from(
      atob(body.replaceAll("-", "+").replaceAll("_", "/")),
      (char) => char.codePointAt(0) ?? 0,
    );

    const payload: unknown = JSON.parse(new TextDecoder().decode(bytes));

    // SAFETY: payload is a non-null object; iss is read, then checked by the caller.
    return typeof payload === "object" && payload !== null
      ? (payload as { iss?: string }).iss
      : undefined;
  } catch {
    return undefined;
  }
}

function matches(
  expected: string | readonly string[] | undefined,
  actual: unknown,
): boolean {
  return (
    expected === undefined ||
    expected === ANY ||
    (typeof actual === "string" && listOf(expected).includes(actual))
  );
}

function claimsProblem(
  claims: Readonly<Record<string, unknown>>,
  options: VercelOidcResolverOptions,
  now: number,
): string | undefined {
  const leeway = options.leeway ?? DEFAULT_LEEWAY;
  const { exp, nbf } = claims;

  if (!isVercelIssuer(claims["iss"])) {
    return "The token was not issued by Vercel";
  }

  if (typeof claims["sub"] !== "string" || claims["sub"].length === 0) {
    return "The token has no sub claim";
  }

  if (typeof exp !== "number" || exp + leeway <= now) {
    return "The token has expired";
  }

  if (nbf !== undefined && (typeof nbf !== "number" || nbf - leeway > now)) {
    return "The token is not valid yet";
  }

  if (!matches(options.projectId, claims["project_id"])) {
    return "The token is for another Vercel project";
  }

  if (!matches(options.environment, claims["environment"])) {
    return "The token is for another environment";
  }

  if (options.ownerId !== undefined && claims["owner_id"] !== options.ownerId) {
    return "The token is for another Vercel team";
  }

  if (options.audience !== undefined) {
    const aud = claims["aud"];
    const held = Array.isArray(aud) ? aud : [aud];

    if (!listOf(options.audience).some((value) => held.includes(value))) {
      return "The token is for another audience";
    }
  }

  return undefined;
}

const invalid = (message: string, hint: string): ResolvedState => ({
  kind: "invalid",
  reason: "token",
  error: dbError("unauthorized", message, { hint }),
});

function optionsProblem(
  options: VercelOidcResolverOptions,
): string | undefined {
  const projects = listOf(options.projectId);

  if (projects.length === 0 || projects.some((id) => id.length === 0)) {
    return 'vercelOidcResolver needs a projectId, such as process.env.VERCEL_PROJECT_ID, or "*"';
  }

  if (
    options.projectId === ANY &&
    options.ownerId === undefined &&
    (options.audience === undefined || listOf(options.audience).length === 0)
  ) {
    return 'vercelOidcResolver with projectId "*" needs an ownerId or an audience';
  }

  return undefined;
}

/**
 * An `AuthResolver` for server-to-server calls from a Vercel deployment. It
 * verifies the deployment's OIDC token (`VERCEL_OIDC_TOKEN`, sent as a Bearer
 * token) against Vercel's keys with the library's own JWS code, checks the
 * project, environment, team and audience you pass, and resolves to an `apiKey`
 * state for the service account `map` returns. The deployment needs no stored
 * key for your API.
 *
 * It does not give the deployment a Supabase role: Vercel's token has no `role`
 * claim, so PostgREST would see `anon`. Queries run through better-supabase
 * with the mapped account's claims, as an API key's do. Pass it to
 * `createServer({ auth: { resolvers: [...] } })`.
 */
export function vercelOidcResolver(
  options: VercelOidcResolverOptions,
): AuthResolver {
  const header = (options.header ?? "authorization").toLowerCase();
  const misconfigured = optionsProblem(options);

  const keys = jwksSource(options.jwks ?? new URL(VERCEL_OIDC_JWKS_URL), {
    rsa: true,
    ...(options.fetch ? { fetch: options.fetch } : {}),
    ...(options.now ? { now: options.now } : {}),
    ...(options.store ? { store: options.store } : {}),
  });

  return {
    name: "vercel-oidc",
    async resolve(request): Promise<ResolvedState | undefined> {
      const raw = request.headers.get(header)?.trim();

      const token =
        header === "authorization" ? BEARER.exec(raw ?? "")?.[1] : raw;

      if (token === undefined || token === "") {
        return undefined;
      }

      if (!isVercelIssuer(unverifiedIssuer(token))) {
        return undefined;
      }

      if (misconfigured) {
        return {
          kind: "invalid",
          reason: "token",
          error: dbError("unexpected", misconfigured, {
            hint: "VERCEL_OIDC_OPTIONS",
          }),
        };
      }

      const verified = await verifySignature(token, keys);

      if (!verified.ok) {
        return { kind: "invalid", reason: "token", error: verified.error };
      }

      const now = Math.floor((options.now ?? Date.now)() / 1000);
      const problem = claimsProblem(verified.data, options, now);

      if (problem !== undefined) {
        return invalid(problem, "VERCEL_OIDC_CLAIMS");
      }

      // SAFETY: claimsProblem checked iss and sub; project_id and environment
      // are strings on every Vercel OIDC token and are matched against options.
      const claims = verified.data as VercelOidcClaims;
      let account: VercelServiceAccount | undefined;

      try {
        account = await options.map(claims);
      } catch (cause) {
        return {
          kind: "invalid",
          reason: "token",
          error: dbError(
            "unexpected",
            `map failed: ${cause instanceof Error ? cause.message : String(cause)}`,
            { hint: "VERCEL_OIDC_MAP" },
          ),
        };
      }

      if (account === undefined) {
        return invalid(
          "This deployment has no service account",
          "VERCEL_OIDC_UNMAPPED",
        );
      }

      return {
        kind: "apiKey",
        keyId: claims.sub,
        name: account.name,
        ...(account.organizationId
          ? { organizationId: account.organizationId }
          : {}),
        ...(account.userId ? { userId: account.userId } : {}),
        scopes: account.scopes,
        claims: {
          sub: account.userId ?? "",
          role: "authenticated",
          aud: "authenticated",
          api_key: {
            id: claims.sub,
            name: account.name,
            scopes: account.scopes,
            ...(account.organizationId
              ? { organization_id: account.organizationId }
              : {}),
          },
          vercel_oidc: {
            project_id: claims.project_id,
            environment: claims.environment,
            ...(claims.owner_id ? { owner_id: claims.owner_id } : {}),
          },
        },
      };
    },
  };
}
