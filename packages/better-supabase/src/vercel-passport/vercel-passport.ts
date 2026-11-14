import type { DbError } from "../core/errors.ts";
import type { JwksSource, JwksStore } from "../core/jwks-cache.ts";
import type { Jwks } from "../core/jws.ts";
import type { Result } from "../core/result.ts";

import { dbError } from "../core/errors.ts";
import { jwksSource } from "../core/jwks-cache.ts";
import { JwsError, verifyCompact } from "../core/jws.ts";
import { AsyncResult, err, ok } from "../core/result.ts";

/** The header Vercel sets with the Passport token of the signed-in caller. */
export const PASSPORT_HEADER = "x-vercel-oidc-passport-token";

/** Passport's issuer; a token's `iss` is it or it followed by `/<owner>`. */
export const PASSPORT_ISSUER = "https://passport.vercel.com";

/** Where Vercel publishes the keys Passport tokens are signed with. */
export const PASSPORT_JWKS_URL = "https://oidc.vercel.com/.well-known/jwks";

/**
 * The claims of a Passport token, mirroring `PassportIdentityPayload` from
 * `@vercel/passport` so either type is assignable to the other.
 */
export interface PassportClaims {
  readonly typ?: string;
  readonly owner?: string;
  readonly owner_id?: string;
  readonly project?: string;
  readonly project_id?: string;
  readonly environment?: string;
  readonly plan?: string;
  readonly aud?: string;
  readonly iss?: string;
  readonly sub: string;
  readonly scope?: string;
  readonly external_iss?: string;
  readonly external_sub?: string;
  readonly connector_id?: string;
  readonly sid?: string;
  readonly tenant_id?: string;
  readonly installation_id?: string;
  readonly email?: string;
  readonly name?: string;
  readonly [claim: string]: unknown;
}

/** Who `resolveUser` looks up: the verified issuer and subject, and all claims. */
export interface PassportPrincipal {
  readonly iss: string;
  readonly sub: string;
  readonly claims: PassportClaims;
}

/** Which headers `verifyPassport` reads the token from. */
export type PassportTokenSource = "passport" | "bearer" | "both";

export interface VerifyPassportOptions<U = never> {
  /**
   * The Vercel project ids (`project_id`) a token must be for, such as
   * `process.env.VERCEL_PROJECT_ID`. `"*"` accepts any project, and then needs
   * `ownerId` or `audience`.
   */
  readonly projectId: string | readonly string[];
  /**
   * The environments (`environment`) a token must be for, such as
   * `process.env.VERCEL_TARGET_ENV`. Default: `"*"`, any environment.
   */
  readonly environment?: string | readonly string[];
  /** The Vercel team or user id (`owner_id`) a token must carry. */
  readonly ownerId?: string;
  /** Audiences one of which the token's `aud` must hold. */
  readonly audience?: string | readonly string[];
  /** The key set: a JWKS URL or inline keys. Default: `PASSPORT_JWKS_URL`. */
  readonly jwks?: URL | Jwks;
  /**
   * Maps the verified caller to the app's own user, such as a profile row found
   * by `external_sub`. The library stores no mapping. A throw resolves to an
   * `unexpected` error.
   */
  readonly resolveUser?: (
    principal: PassportPrincipal,
  ) => U | undefined | Promise<U | undefined>;
  /** The `fetch` for the JWKS. */
  readonly fetch?: typeof fetch;
  /** Epoch milliseconds. */
  readonly now?: () => number;
  /** Seconds of clock skew allowed on `exp` and `nbf`. Default: 30. */
  readonly leeway?: number;
  /** Shares the fetched key set between instances (`vercelRuntimeCache`). */
  readonly store?: JwksStore;
  /**
   * Where the token is read: `passport` is the `x-vercel-oidc-passport-token`
   * header, `bearer` is `Authorization: Bearer` (a token forwarded to another
   * backend), and `both` (the default) tries the Passport header first.
   */
  readonly headers?: PassportTokenSource;
}

export interface PassportResult<U = never> {
  readonly claims: PassportClaims;
  /** What `resolveUser` returned; `undefined` without it. */
  readonly user: U | undefined;
}

const ANY = "*";
const DEFAULT_LEEWAY = 30;
const BEARER = /^Bearer\s+([\w.~+/-]+=*)\s*$/i;
const REQUIRED_CLAIMS = ["sub", "owner", "connector_id", "external_sub"];

const listOf = (value: string | readonly string[]): readonly string[] =>
  typeof value === "string" ? [value] : value;

const errorText = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

const nonEmpty = (value: unknown): value is string =>
  typeof value === "string" && value.length > 0;

function tokenOf(
  request: Request,
  source: PassportTokenSource,
): string | undefined {
  if (source !== "bearer") {
    const header = request.headers.get(PASSPORT_HEADER)?.trim();

    if (header) {
      return header;
    }
  }

  if (source === "passport") {
    return undefined;
  }

  return BEARER.exec(request.headers.get("authorization") ?? "")?.[1];
}

/** Whether `iss` is Passport's issuer, alone or scoped to an owner. */
function isPassportIssuer(iss: unknown): iss is string {
  return (
    iss === PASSPORT_ISSUER ||
    (typeof iss === "string" && iss.startsWith(`${PASSPORT_ISSUER}/`))
  );
}

const claimsError = (message: string): DbError =>
  dbError("unauthorized", message, { hint: "PASSPORT_CLAIMS" });

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

/** The first claim check that fails, as a `PASSPORT_CLAIMS` error. */
function claimsProblem<U>(
  claims: Readonly<Record<string, unknown>>,
  options: VerifyPassportOptions<U>,
  now: number,
): DbError | undefined {
  const leeway = options.leeway ?? DEFAULT_LEEWAY;

  if (!isPassportIssuer(claims["iss"])) {
    return claimsError("The token was not issued by Vercel Passport");
  }

  if (claims["typ"] !== "passport") {
    return claimsError('The token is not a Passport token (typ "passport")');
  }

  const missing = REQUIRED_CLAIMS.find((name) => !nonEmpty(claims[name]));

  if (missing !== undefined) {
    return claimsError(`The token has no ${missing} claim`);
  }

  const exp = claims["exp"];
  const nbf = claims["nbf"];

  if (typeof exp !== "number" || exp + leeway <= now) {
    return claimsError("The token has expired");
  }

  if (nbf !== undefined && (typeof nbf !== "number" || nbf - leeway > now)) {
    return claimsError("The token is not valid yet");
  }

  if (!matches(options.projectId, claims["project_id"])) {
    return claimsError("The token is for another Vercel project");
  }

  if (!matches(options.environment, claims["environment"])) {
    return claimsError("The token is for another environment");
  }

  if (options.ownerId !== undefined && claims["owner_id"] !== options.ownerId) {
    return claimsError("The token is for another Vercel team");
  }

  if (options.audience !== undefined) {
    const aud = claims["aud"];
    const held = Array.isArray(aud) ? aud : [aud];

    if (!listOf(options.audience).some((value) => held.includes(value))) {
      return claimsError("The token is for another audience");
    }
  }

  return undefined;
}

function optionsProblem<U>(
  options: VerifyPassportOptions<U>,
): DbError | undefined {
  const projects = listOf(options.projectId);

  if (projects.length === 0 || projects.some((id) => id.length === 0)) {
    return dbError(
      "unexpected",
      'verifyPassport needs a projectId, such as process.env.VERCEL_PROJECT_ID, or "*"',
      { hint: "PASSPORT_OPTIONS" },
    );
  }

  const audiences =
    options.audience === undefined ? [] : listOf(options.audience);

  if (
    options.projectId === ANY &&
    options.ownerId === undefined &&
    audiences.length === 0
  ) {
    return dbError(
      "unexpected",
      'verifyPassport with projectId "*" needs an ownerId or an audience',
      { hint: "PASSPORT_OPTIONS" },
    );
  }

  return undefined;
}

async function verifySignature(
  token: string,
  keys: JwksSource,
): Promise<Result<Readonly<Record<string, unknown>>>> {
  const signatureError = (cause: unknown): Result<never> =>
    err(
      dbError(
        "unauthorized",
        `The Passport token does not verify: ${errorText(cause)}`,
        { hint: "PASSPORT_TOKEN" },
      ),
    );

  let jwks = await keys(false);

  if (!jwks.ok) {
    return jwks;
  }

  try {
    return ok(
      (await verifyCompact(token, jwks.data, { algorithms: ["RS256"] }))
        .payload,
    );
  } catch (cause) {
    if (!(cause instanceof JwsError) || cause.code !== "JWS_KEY") {
      return signatureError(cause);
    }
  }

  jwks = await keys(true);

  if (!jwks.ok) {
    return jwks;
  }

  try {
    return ok(
      (await verifyCompact(token, jwks.data, { algorithms: ["RS256"] }))
        .payload,
    );
  } catch (cause) {
    return signatureError(cause);
  }
}

/**
 * Verifies the Vercel Passport token of a request with the library's own JWS
 * code: the RS256 signature against Vercel's keys, the issuer, `typ`, the
 * required claims, expiry, and the project, environment, owner and audience you
 * pass. Errors are `unauthorized` (`MISSING_CREDENTIALS`, `PASSPORT_TOKEN`,
 * `PASSPORT_CLAIMS`), `network` (`JWKS_FETCH_FAILED`) or `unexpected`
 * (`PASSPORT_OPTIONS`, a throwing `resolveUser`).
 */
export function verifyPassport<U = never>(
  request: Request,
  options: VerifyPassportOptions<U>,
): AsyncResult<PassportResult<U>> {
  return AsyncResult.from(async () => {
    const misconfigured = optionsProblem(options);

    if (misconfigured) {
      return err(misconfigured);
    }

    const token = tokenOf(request, options.headers ?? "both");

    if (token === undefined) {
      return err(
        dbError("unauthorized", "The request has no Passport token", {
          code: "MISSING_CREDENTIALS",
        }),
      );
    }

    const keys = jwksSource(options.jwks ?? new URL(PASSPORT_JWKS_URL), {
      rsa: true,
      ...(options.fetch ? { fetch: options.fetch } : {}),
      ...(options.now ? { now: options.now } : {}),
      ...(options.store ? { store: options.store } : {}),
    });

    const verified = await verifySignature(token, keys);

    if (!verified.ok) {
      return verified;
    }

    const now = Math.floor((options.now ?? Date.now)() / 1000);
    const problem = claimsProblem(verified.data, options, now);

    if (problem) {
      return err(problem);
    }

    // SAFETY: claimsProblem checked iss, sub and the other required claims.
    const claims = verified.data as PassportClaims;

    if (!options.resolveUser) {
      return ok({ claims, user: undefined });
    }

    try {
      const user = await options.resolveUser({
        // SAFETY: claimsProblem checked that iss is Passport's issuer.
        iss: claims.iss!,
        sub: claims.sub,
        claims,
      });

      return ok({ claims, user });
    } catch (cause) {
      return err(
        dbError("unexpected", `resolveUser failed: ${errorText(cause)}`, {
          hint: "PASSPORT_RESOLVE_USER",
        }),
      );
    }
  });
}
