import type { JWTClaims, UserClaims } from "@supabase/server";

import type { DbError } from "../core/errors.ts";
import type { JwksInput, JwksSourceOptions } from "../core/jwks-cache.ts";
import type { JwsAlgorithm } from "../core/jws.ts";
import type { Result } from "../core/result.ts";
import type { AuthResolver, ResolvedState } from "./resolve.ts";

import { base64ToText } from "../core/base64.ts";
import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { jwksSource } from "../core/jwks-cache.ts";
import { JwsError, verifyCompact } from "../core/jws.ts";

/**
 * Checks whether an access token was revoked, by its `jti` or by the grant it
 * was issued under. `createOauthServer` from
 * `better-supabase/blocks/oauth-server` has this shape.
 */
export interface AccessTokenRevocation {
  isRevoked(
    jti: string,
    grantId: string | undefined,
  ): PromiseLike<Result<boolean>>;
}

/** The claims every RFC 9068 token carries, which `claims` cannot set. */
export type AccessTokenReservedClaim =
  | "iss"
  | "sub"
  | "aud"
  | "exp"
  | "iat"
  | "jti"
  | "client_id"
  | "scope"
  | "role";

const RESERVED: ReadonlySet<string> = new Set<AccessTokenReservedClaim>([
  "iss",
  "sub",
  "aud",
  "exp",
  "iat",
  "jti",
  "client_id",
  "scope",
  "role",
]);

export interface AccessTokenResolverOptions {
  /** The authorization server's keys: inline, a JWKS URL (cached), or a loader. */
  readonly jwks: JwksInput;
  /** The `iss` the tokens must carry, compared exactly. */
  readonly issuer: string | readonly string[];
  /** This resource server's identifier; the token's `aud` must contain it. */
  readonly audience: string | readonly string[];
  /** The `alg` values accepted. Default: `RS256`, `PS256`, `ES256` and `EdDSA`. */
  readonly algorithms?: readonly JwsAlgorithm[];
  /** Seconds of clock skew allowed on `exp`, `nbf` and `iat`. Default: 30. */
  readonly clockSkew?: number;
  /**
   * The Postgres role queries run as, which the token's `role` must match when
   * it has one. Default: `authenticated`.
   */
  readonly role?: string;
  /** Checked on every request after the signature; a failure answers 401. */
  readonly revocation?: AccessTokenRevocation;
  /** The claim with the grant id `revocation` receives. Default: `grant_id`. */
  readonly grantClaim?: string;
  /**
   * Extra claims for a verified token, such as a tenant read from a custom
   * claim. Claims the token carries keep their values.
   */
  readonly claims?: (
    payload: Readonly<Record<string, unknown>>,
  ) => Readonly<Record<string, unknown>>;
  /** How the JWKS is cached when `jwks` is a URL or a loader. */
  readonly cache?: Pick<JwksSourceOptions, "cacheSeconds" | "refetchSeconds">;
  readonly fetch?: typeof fetch;
  /** Epoch milliseconds. */
  readonly now?: () => number;
}

const TYPES = new Set(["at+jwt", "application/at+jwt"]);
const BEARER = /^Bearer\s+([\w.~+/-]+=*)\s*$/i;

function headerOf(token: string): Record<string, unknown> | undefined {
  const part = token.split(".", 1)[0];

  if (!part || token.split(".").length !== 3) {
    return undefined;
  }

  try {
    const value: unknown = JSON.parse(base64ToText(part));

    return isRecord(value) ? value : undefined;
  } catch {
    return undefined;
  }
}

/** Whether the token says it is an RFC 9068 access token (`typ: at+jwt`). */
export function isAccessTokenJwt(token: string): boolean {
  const typ = headerOf(token)?.["typ"];

  return typeof typ === "string" && TYPES.has(typ.toLowerCase());
}

function invalid(code: string, message: string): ResolvedState {
  return {
    kind: "invalid",
    reason: "token",
    error: dbError("unauthorized", message, { code }),
  };
}

function listOf(value: string | readonly string[]): readonly string[] {
  return typeof value === "string" ? [value] : value;
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value !== "" ? value : undefined;
}

type Checked =
  | { readonly ok: true; readonly payload: Readonly<Record<string, unknown>> }
  | { readonly ok: false; readonly state: ResolvedState };

/** RFC 9068 section 4: the claims a resource server checks. */
function checkClaims(
  payload: Readonly<Record<string, unknown>>,
  options: AccessTokenResolverOptions,
  now: number,
): Checked {
  const fail = (code: string, message: string): Checked => ({
    ok: false,
    state: invalid(code, message),
  });

  const skew = options.clockSkew ?? 30;
  const { exp, nbf, iat } = payload;

  if (!listOf(options.issuer).includes(String(payload["iss"]))) {
    return fail(
      "ACCESS_TOKEN_ISSUER",
      "The access token issuer is not trusted",
    );
  }

  const aud = payload["aud"];
  const audiences = Array.isArray(aud) ? aud : [aud];

  if (!listOf(options.audience).some((wanted) => audiences.includes(wanted))) {
    return fail(
      "ACCESS_TOKEN_AUDIENCE",
      "The access token is not for this resource server",
    );
  }

  if (typeof exp !== "number") {
    return fail("ACCESS_TOKEN_INVALID", "The access token has no exp claim");
  }

  if (exp + skew <= now) {
    return fail("ACCESS_TOKEN_EXPIRED", "The access token has expired");
  }

  if (typeof nbf === "number" && nbf - skew > now) {
    return fail("ACCESS_TOKEN_INVALID", "The access token is not valid yet");
  }

  if (typeof iat !== "number" || iat - skew > now) {
    return fail(
      "ACCESS_TOKEN_INVALID",
      "The access token has no iat claim, or one in the future",
    );
  }

  for (const claim of ["sub", "client_id", "jti"] as const) {
    if (text(payload[claim]) === undefined) {
      return fail(
        "ACCESS_TOKEN_INVALID",
        `The access token has no ${claim} claim`,
      );
    }
  }

  const scope = payload["scope"];

  if (scope !== undefined && typeof scope !== "string") {
    return fail(
      "ACCESS_TOKEN_INVALID",
      "The access token scope is not a string",
    );
  }

  const role = options.role ?? "authenticated";

  if (payload["role"] !== undefined && payload["role"] !== role) {
    return fail(
      "ACCESS_TOKEN_ROLE",
      `The access token role must be ${role} when it is set`,
    );
  }

  // RFC 9449 and RFC 8705: a sender-constrained token needs a proof this resolver can't check.
  if (payload["cnf"] !== undefined) {
    return fail(
      "ACCESS_TOKEN_BOUND",
      "Sender-constrained access tokens (cnf) are not accepted as bearer tokens",
    );
  }

  return { ok: true, payload };
}

interface Verified {
  readonly claims: JWTClaims;
  readonly user: UserClaims;
  readonly expiresAt: number;
  readonly jti: string;
  readonly grantId: string | undefined;
}

function verifiedOf(
  payload: Readonly<Record<string, unknown>>,
  options: AccessTokenResolverOptions,
): Verified {
  const extra = Object.entries(options.claims?.(payload) ?? {}).filter(
    ([name]) => !RESERVED.has(name),
  );

  const role = options.role ?? "authenticated";
  const sub = String(payload["sub"]);

  // SAFETY: checkClaims proved `sub` is a string; the rest are extra claims.
  const claims = {
    ...Object.fromEntries(extra),
    ...payload,
    role,
  } as JWTClaims;

  return {
    claims,
    user: {
      id: sub,
      role,
      ...(typeof claims.email === "string" ? { email: claims.email } : {}),
    },
    expiresAt: Number(payload["exp"]),
    jti: String(payload["jti"]),
    grantId: text(payload[options.grantClaim ?? "grant_id"]),
  };
}

function bearerOf(request: Request): string | undefined {
  return BEARER.exec(request.headers.get("authorization") ?? "")?.[1];
}

function revocationError(error: DbError): ResolvedState {
  return {
    kind: "invalid",
    reason: "token",
    error: dbError(
      error.kind === "network" ? "network" : "unexpected",
      `The revocation list could not be checked: ${error.message}`,
      { code: "ACCESS_TOKEN_REVOCATION_UNAVAILABLE" },
    ),
  };
}

/**
 * Resolves an OAuth 2.0 access token in the JWT format of RFC 9068, issued by
 * an authorization server the app trusts, to a `user` auth state with `source:
 * "oauth"`. Its claims keep `sub`, `client_id` and `scope`, so queries run as
 * the user under RLS and the access functions narrow the token to the
 * permissions its scopes map to.
 *
 * Only `Authorization: Bearer` tokens with the `typ` header `at+jwt` are
 * claimed; others fall through to the next resolver and the Supabase token
 * check. A claimed token that fails a check answers 401, never anon.
 *
 * `ctx.supabase` forwards the token to PostgREST, which accepts it only when
 * the issuer is registered as Supabase third-party auth.
 */
export function accessTokenResolver(
  options: AccessTokenResolverOptions,
): AuthResolver {
  if (listOf(options.issuer).length === 0) {
    throw new TypeError("accessTokenResolver: issuer is required");
  }

  if (listOf(options.audience).length === 0) {
    throw new TypeError("accessTokenResolver: audience is required");
  }

  const algorithms = options.algorithms ?? ["RS256", "PS256", "ES256", "EdDSA"];
  const rsa = algorithms.some((alg) => alg === "RS256" || alg === "PS256");

  const keys = jwksSource(options.jwks, {
    rsa,
    ...options.cache,
    ...(options.fetch ? { fetch: options.fetch } : {}),
    ...(options.now ? { now: options.now } : {}),
  });

  const seconds = (): number => Math.floor((options.now ?? Date.now)() / 1000);

  const verify = async (
    token: string,
  ): Promise<
    { ok: true; verified: Verified } | { ok: false; state: ResolvedState }
  > => {
    const now = seconds();
    let payload: Readonly<Record<string, unknown>> | undefined;

    for (const refresh of [false, true]) {
      const set = await keys(refresh);

      if (!set.ok) {
        return {
          ok: false,
          state: { kind: "invalid", reason: "token", error: set.error },
        };
      }

      try {
        ({ payload } = await verifyCompact(token, set.data, { algorithms }));
        break;
      } catch (cause) {
        if (!(cause instanceof JwsError)) {
          throw cause;
        }

        if (cause.code !== "JWS_KEY" || refresh) {
          return {
            ok: false,
            state: invalid("ACCESS_TOKEN_INVALID", cause.message),
          };
        }
      }
    }

    if (payload === undefined) {
      return {
        ok: false,
        state: invalid(
          "ACCESS_TOKEN_INVALID",
          "No key verifies the access token",
        ),
      };
    }

    const checked = checkClaims(payload, options, now);

    if (!checked.ok) {
      return checked;
    }

    return { ok: true, verified: verifiedOf(checked.payload, options) };
  };

  return {
    name: "oauth-access-token",
    async resolve(request): Promise<ResolvedState | undefined> {
      const token = bearerOf(request);

      if (token === undefined || !isAccessTokenJwt(token)) {
        return undefined;
      }

      const outcome = await verify(token);

      if (!outcome.ok) {
        return outcome.state;
      }

      const { verified } = outcome;

      if (options.revocation) {
        const revoked = await options.revocation.isRevoked(
          verified.jti,
          verified.grantId,
        );

        if (!revoked.ok) {
          return revocationError(revoked.error);
        }

        if (revoked.data) {
          return invalid(
            "ACCESS_TOKEN_REVOKED",
            "The access token was revoked",
          );
        }
      }

      return {
        kind: "user",
        token,
        claims: verified.claims,
        user: verified.user,
        source: "oauth",
        expiresAt: verified.expiresAt,
      };
    },
  };
}
