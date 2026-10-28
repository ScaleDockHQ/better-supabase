import type {
  AuthModeWithKey,
  JWTClaims,
  SupabaseEnv,
  UserClaims,
} from "@supabase/server";

import { fromSupabaseUrl } from "@supabase/server";
import { extractCredentials, verifyCredentials } from "@supabase/server/core";

import type { DbError } from "../core/errors.ts";
import type { AuthOutageEvent, RefreshEvent } from "../core/events.ts";
import type { Logger } from "../core/logger.ts";
import type { StandardSchemaV1 } from "../core/standard.ts";
import type { BetterSupabaseEnv } from "../env/index.ts";
import type {
  CookieOptions,
  CookieRecord,
  CookieWrite,
  SessionEncoding,
  StoredSession,
} from "./session.ts";
import type { CookieRefresh } from "./ssr-client.ts";

import { decodeJwtHeader, decodeJwtPayload } from "../core/base64.ts";
import { dbError } from "../core/errors.ts";
import { clearJwksCache, sharedJwks } from "../core/jwks-cache.ts";
import { consoleLogger } from "../core/logger.ts";
import { actorOf, invalidActorError } from "./actor.ts";
import { sessionStatus } from "./ended.ts";
import { clearHs256Keys, isSharedSecretToken, verifyHs256 } from "./hs256.ts";
import {
  applyCookieWrites,
  parseCookies,
  readSession,
  serializeCookie,
  sessionCookieName,
} from "./session.ts";
import {
  clearCookieSession,
  NO_STORE,
  refreshCookieSession,
} from "./ssr-client.ts";

/**
 * Who is calling. `C` is the claims type from `betterSupabase.claims(schema)`;
 * the verified payload keeps every JWT claim and adds the schema's output. `P`
 * is the `user_metadata` type from `betterSupabase.userMetadata(schema)`.
 */
export type AuthState<C = unknown, P = unknown> =
  | {
      readonly kind: "user";
      readonly token: string;
      readonly claims: JWTClaims & C;
      readonly user: UserClaims;
      /**
       * Where the token came from: `oauth` for an RFC 9068 access token from
       * `accessTokenResolver`, which never has a cookie session.
       */
      readonly source: "bearer" | "cookie" | "oauth" | (string & {});
      /** Seconds since epoch, from the token's `exp`. */
      readonly expiresAt: number | null;
      /**
       * `user_metadata` parsed by `betterSupabase.userMetadata(schema)`;
       * `undefined` without a schema or when the metadata fails it. Users can
       * write this data themselves: use it for display, never for access.
       */
      readonly userMetadata?: P;
    }
  /** The secret key (or a legacy `service_role` key); `keyName` names it. */
  | { readonly kind: "secret"; readonly keyName: string }
  /**
   * An app API key (`better-supabase/blocks/api-keys`). `userId` is set for a
   * key that acts as its user, `organizationId` for one scoped to a tenant.
   * Queries run over direct Postgres with `claims`; there is no JWT for
   * PostgREST, so `ctx.supabase` is unavailable.
   */
  | {
      readonly kind: "apiKey";
      readonly keyId: string;
      readonly name: string;
      readonly organizationId?: string;
      readonly userId?: string;
      readonly scopes: readonly string[];
      /** When the key was created. */
      readonly createdAt?: Temporal.Instant;
      /** The user who created the key, when the row records one. */
      readonly createdBy?: string;
      /**
       * `sub` (the user, or the key for an organization key), `role:
       * authenticated` and `api_key`.
       */
      readonly claims: JWTClaims;
    }
  /** No session: no credentials, or a cookie session that did not hold. */
  | {
      readonly kind: "none";
      /**
       * `expired`: the cookie session needs a refresh that was not allowed here
       * (run the proxy).
       */
      readonly reason: "none" | "expired" | "signed_out" | "refresh_failed";
    }
  /**
   * Credentials were sent but did not verify (`token`), verified but failed the
   * claims schema (`claims`), or carry a malformed RFC 8693 `act` chain
   * (`actor`). Answer 401, never downgrade to anon.
   */
  | {
      readonly kind: "invalid";
      readonly reason: InvalidReason;
      readonly error: DbError;
    };

export type InvalidReason = "token" | "claims" | "actor";

/**
 * What an `AuthResolver` returns. `reason` may be left out of an `invalid`
 * state; it then counts as `token`.
 */
export type ResolvedState =
  | Exclude<AuthState, { kind: "invalid" }>
  | {
      readonly kind: "invalid";
      readonly reason?: InvalidReason;
      readonly error: DbError;
    };

/**
 * Extension point for other credentials (API keys, third-party auth, custom
 * tokens). Return `undefined` when the request carries nothing this resolver
 * understands; the built-in Bearer and cookie resolution runs next.
 */
export interface AuthResolver {
  readonly name: string;
  resolve(
    request: Request,
  ): Promise<ResolvedState | undefined> | ResolvedState | undefined;
}

export interface ResolveAuthOptions {
  readonly env: BetterSupabaseEnv;
  /**
   * Allow refreshing an expiring cookie session. Only where cookies can be
   * written (proxy).
   */
  readonly refresh?: boolean;
  /**
   * With `refresh`, refresh when the token expires within this many seconds.
   * Defaults to 60. Without `refresh` a token stays valid until its `exp`.
   */
  readonly leeway?: number;
  /** Milliseconds before a refresh counts as a network failure. Defaults to 5000. */
  readonly refreshTimeoutMs?: number;
  readonly verifySession?: boolean;
  /**
   * Accept `sb_secret_` keys (`apikey` header) as service callers: `true` for
   * any configured key, or the key names allowed (`['cron']`). Defaults to
   * false.
   */
  readonly secret?: boolean | readonly string[];
  readonly audience?: string | string[];
  /**
   * The `iss` a token must carry. By default a token whose `iss` is not the
   * project's Auth URL (`<url>/auth/v1`) is rejected, so a token another
   * project signed with a shared key never verifies here; a token without `iss`
   * (only a holder of the keys can sign one) still does. Set it to require the
   * claim, or `false` to skip the check.
   */
  readonly issuer?: string | string[] | false;
  readonly cookie?: {
    readonly name?: string;
    readonly options?: CookieOptions;
    /**
     * The shape refreshed sessions are written in, `cookies.encode` in
     * `@supabase/ssr`. Use the browser client's value. Defaults to
     * `user-and-tokens`.
     */
    readonly encode?: SessionEncoding;
  };
  /**
   * Read the session cookie. Defaults to true. `false` suits endpoints only
   * bearer clients call (MCP): a browser's cookie then can't authorize a
   * request another site makes it send.
   */
  readonly cookies?: boolean;
  /**
   * Inline JWKS instead of fetching `env.jwksUrl` (tests, air-gapped). `false`
   * or `null` verifies against no keys and never fetches, ignoring
   * `SUPABASE_JWKS` and `SUPABASE_JWKS_URL`.
   */
  readonly jwks?: SupabaseEnv["jwks"] | false;
  /**
   * Verify HS256 tokens without a `kid` locally with this shared secret, the
   * tokens Supabase Lite issues (`auth.jwt_secret`). Tokens with a `kid` still
   * verify against the JWKS. `createServer` sets it from `SUPABASE_JWT_SECRET`
   * with `backend: "lite"`.
   */
  readonly jwtSecret?: string;
  /**
   * Validates the verified claims (`betterSupabase.claims(schema)` sets it). A
   * failure resolves to `{ kind: 'invalid', reason: 'claims' }`.
   */
  readonly claims?: StandardSchemaV1;
  /**
   * Parses `user_metadata` into `profile`
   * (`betterSupabase.userMetadata(schema)` sets it). A failure leaves `profile`
   * undefined and warns once; the session stays valid.
   */
  readonly userMetadata?: StandardSchemaV1;
  /** Receives the `userMetadata` warning. Defaults to `console`. */
  readonly logger?: Logger;
  readonly resolvers?: readonly AuthResolver[];
  /**
   * The caller's IP, sent to Auth as `Sb-Forwarded-For` on refreshes so its
   * per-IP rate limit counts users, not your server. Only with a secret key
   * (`env.secretKey`), which Auth requires for the header. Defaults to
   * `clientIp` (the last `x-forwarded-for` hop); `false` turns it off.
   */
  readonly clientIp?: ((request: Request) => string | undefined) | false;
  /** Called after every refresh attempt (metrics, logging). */
  readonly onRefresh?: (event: RefreshEvent) => void;
  /**
   * Called with the milliseconds each phase took: reading the session cookie
   * (`parse`), verifying a token (`verify`), refreshing (`refresh`) and asking
   * Auth whether the session ended (`ended`). For `Server-Timing`.
   */
  readonly onTiming?: (phase: ResolvePhase, ms: number) => void;
  /** The `fetch` for Auth calls and the JWKS. Defaults to the global one. */
  readonly fetch?: typeof fetch;
  /** Epoch milliseconds, the unit JWT `exp` and `iat` math needs. */
  readonly now?: () => number;
}

export type ResolvePhase = "parse" | "verify" | "refresh" | "ended";

/** Why Auth rejected a session `verifySession` checked. */
export type SessionRejection = "session_not_found" | "user_banned";

export interface AuthResolution<C = unknown, P = unknown> {
  readonly auth: AuthState<C, P>;
  /**
   * Cookie writes for the response. Empty unless the session was refreshed or
   * cleared.
   */
  readonly cookies: readonly CookieWrite[];
  /** No-store headers, set whenever `cookies` is not empty. */
  readonly headers: Readonly<Record<string, string>>;
  /** Cookies the rest of this request should see, including a refreshed session. */
  readonly requestCookies: readonly CookieRecord[];
  /** Adds `cookies` and `headers` to a response. */
  apply(response: Response): Response;
  /**
   * `false` when `verifySession` asked Auth and the session no longer exists
   * (revoked, deleted or signed out elsewhere) or the user is banned; the
   * cookies are cleared. Absent when the session was not checked or is live.
   */
  readonly sessionVerified?: false;
  /** Why `sessionVerified` is `false`, as Auth's error code names it. */
  readonly reason?: SessionRejection;
  /** Set when a refresh failed because the Auth server was unreachable. */
  readonly outage?: AuthOutageEvent;
}

function expiryOf(session: StoredSession): number | undefined {
  if (typeof session.expires_at === "number") {
    return session.expires_at;
  }

  const exp = decodeJwtPayload(session.access_token)?.["exp"];

  return typeof exp === "number" ? exp : undefined;
}

type JwksSource = NonNullable<SupabaseEnv["jwks"]>;

type InlineJwks = Exclude<JwksSource, URL>;

/** An empty key set: `auth.jwks: false` verifies against it and fetches nothing. */
const NO_KEYS: InlineJwks = { keys: [] };

/** `auth.jwks`, then `env.jwks` (`SUPABASE_JWKS`), then `env.jwksUrl`. */
function jwksOf(options: ResolveAuthOptions): JwksSource {
  if (options.jwks === false || options.jwks === null) {
    return NO_KEYS;
  }

  return options.jwks ?? options.env.jwks ?? options.env.jwksUrl;
}

/** The `iss` the verifier requires: only one the app set. */
function issuerOf(options: ResolveAuthOptions): string | string[] | undefined {
  return options.issuer === false ? undefined : options.issuer;
}

/** A verified token whose `iss` names another issuer than the project's Auth. */
function foreignIssuer(
  options: ResolveAuthOptions,
  claims: { readonly iss?: unknown },
): AuthState | undefined {
  if (options.issuer !== undefined || typeof claims.iss !== "string") {
    return undefined;
  }

  return claims.iss === fromSupabaseUrl(options.env.url)
    ? undefined
    : {
        kind: "invalid",
        reason: "token",
        error: dbError(
          "unauthorized",
          "The token was issued by another project",
          { code: "INVALID_ISSUER" },
        ),
      };
}

/**
 * The keys to verify `token` with. A JWKS URL goes through the process-wide
 * cache (`sharedJwks`) and is passed inline, so `@supabase/server` never keeps
 * a resolver of its own; a `kid` the cached set lacks refetches it once per
 * cooldown, for key rotations.
 */
async function keysFor(
  options: ResolveAuthOptions,
  token: string | null,
): Promise<InlineJwks | DbError> {
  const source = jwksOf(options);

  if (!(source instanceof URL)) {
    return source;
  }

  if (!token) {
    return NO_KEYS;
  }

  const shared = {
    ...(options.fetch ? { fetch: options.fetch } : {}),
    ...(options.now ? { now: options.now } : {}),
  };

  let result = await sharedJwks(source, false, shared);
  const kid = decodeJwtHeader(token)?.["kid"];

  if (
    result.ok &&
    typeof kid === "string" &&
    !result.data.keys.some((key) => key["kid"] === kid)
  ) {
    result = await sharedJwks(source, true, shared);
  }

  // SAFETY: the issuer's JWK Set as served; jose validates each key it imports.
  return result.ok ? (result.data as InlineJwks) : result.error;
}

function serverEnv(options: ResolveAuthOptions, jwks: InlineJwks): SupabaseEnv {
  const { env } = options;

  return {
    url: env.url,
    publishableKeys: { default: env.publishableKey },
    secretKeys:
      env.secretKeys ?? (env.secretKey ? { default: env.secretKey } : {}),
    jwks,
  };
}

type VerifiedUser = Omit<
  Extract<AuthState, { kind: "user" }>,
  "source" | "profile"
>;

const MEMO_SIZE = 256;
const memoByUrl = new Map<string, Map<string, VerifiedUser>>();
let memoByJwks = new WeakMap<object, Map<string, Map<string, VerifiedUser>>>();

/** The most JWT secrets remembered at once; the oldest goes first. */
const SECRET_IDS_SIZE = 64;

/**
 * A number per JWT secret, so memo keys tell secrets apart. Bounded, and never
 * reuses a number.
 */
const secretIds = new Map<string, number>();
let nextSecretId = 1;

function secretId(secret: string | undefined): number | null {
  if (secret === undefined) {
    return null;
  }

  let id = secretIds.get(secret);

  if (id === undefined) {
    id = nextSecretId;
    nextSecretId += 1;
    secretIds.set(secret, id);

    if (secretIds.size > SECRET_IDS_SIZE) {
      const oldest = secretIds.keys().next();

      if (!oldest.done) {
        secretIds.delete(oldest.value);
      }
    }
  }

  return id;
}

/**
 * Tokens that already verified, until they expire. Every private-cache scope
 * and island resolves the same token again; this skips the signature check. A
 * hit skips the audience and issuer checks too, so both are part of the key.
 */
function memoFor(options: ResolveAuthOptions): Map<string, VerifiedUser> {
  const jwks = jwksOf(options);
  const inline = !(jwks instanceof URL);

  const key = JSON.stringify([
    inline ? null : String(jwks),
    options.env.url,
    options.audience ?? null,
    options.issuer ?? null,
    secretId(options.jwtSecret),
  ]);

  if (inline) {
    let byKey = memoByJwks.get(jwks);

    if (!byKey) {
      memoByJwks.set(
        jwks,
        (byKey = new Map<string, Map<string, VerifiedUser>>()),
      );
    }

    let memo = byKey.get(key);

    if (!memo) {
      byKey.set(key, (memo = new Map<string, VerifiedUser>()));
    }

    return memo;
  }

  let memo = memoByUrl.get(key);

  if (!memo) {
    memoByUrl.set(key, (memo = new Map<string, VerifiedUser>()));
  }

  return memo;
}

/**
 * Forgets every verified token and every cached key set. For benchmarks and
 * tests.
 */
export function clearVerifiedTokens(): void {
  memoByUrl.clear();
  memoByJwks = new WeakMap();
  secretIds.clear();
  clearHs256Keys();
  clearJwksCache();
}

function remembered(
  memo: Map<string, VerifiedUser>,
  token: string,
  now: number,
): VerifiedUser | undefined {
  const hit = memo.get(token);

  if (!hit) {
    return undefined;
  }

  memo.delete(token);

  if (hit.expiresAt === null || hit.expiresAt <= now) {
    return undefined;
  }

  memo.set(token, hit);

  return hit;
}

type CheckedState = DistributiveOmit<AuthState, "source">;

type DistributiveOmit<T, K extends PropertyKey> = T extends unknown
  ? Omit<T, K>
  : never;

const NO_SCHEMA = {};

const checkedByMemo = new WeakMap<
  object,
  WeakMap<object, WeakMap<object, Map<string, CheckedState>>>
>();

/**
 * Tokens that already passed (or failed) the claims and `userMetadata` schemas,
 * per verification memo and schema pair, so a memo hit skips validation too.
 */
function checkedFor(
  memo: object,
  options: ResolveAuthOptions,
): Map<string, CheckedState> {
  const claims = options.claims ?? NO_SCHEMA;
  const metadata = options.userMetadata ?? NO_SCHEMA;
  let byClaims = checkedByMemo.get(memo);

  if (!byClaims) {
    checkedByMemo.set(memo, (byClaims = new WeakMap()));
  }

  let byMetadata = byClaims.get(claims);

  if (!byMetadata) {
    byClaims.set(claims, (byMetadata = new WeakMap()));
  }

  let checked = byMetadata.get(metadata);

  if (!checked) {
    byMetadata.set(metadata, (checked = new Map<string, CheckedState>()));
  }

  return checked;
}

function withoutSource(state: AuthState): CheckedState {
  if (state.kind !== "user") {
    return state;
  }

  const { source: _source, ...rest } = state;

  return rest;
}

function remember<T>(
  memo: Map<string, T>,
  token: string,
  user: T,
  expiresAt: number | null,
): void {
  if (expiresAt === null) {
    return;
  }

  memo.set(token, user);

  if (memo.size > MEMO_SIZE) {
    memo.delete(memo.keys().next().value!);
  }
}

async function verify(
  credentials: { token: string | null; apikey: string | null },
  modes: AuthModeWithKey[],
  options: ResolveAuthOptions,
  source: "bearer" | "cookie",
): Promise<AuthState> {
  const token = modes.length === 1 && modes[0] === "user" && credentials.token;
  const memo = token ? memoFor(options) : undefined;

  if (token && memo) {
    const now = Math.floor((options.now ?? Date.now)() / 1000);
    const hit = remembered(memo, token, now);

    if (hit) {
      const checked = checkedFor(memo, options);
      const known = checked.get(token);

      if (known) {
        return known.kind === "user" ? { ...known, source } : known;
      }

      const state = await checkUser({ ...hit, source }, options);
      remember(checked, token, withoutSource(state), hit.expiresAt);

      return state;
    }
  }

  const state = await verifyOnce(credentials, modes, options, source);

  if (token && memo && state.kind === "user") {
    remember(
      memo,
      token,
      {
        kind: "user",
        token: state.token,
        claims: state.claims,
        user: state.user,
        expiresAt: state.expiresAt,
      },
      state.expiresAt,
    );
  }

  const checked = await checkUser(state, options);

  if (token && memo && state.kind === "user") {
    remember(
      checkedFor(memo, options),
      token,
      withoutSource(checked),
      state.expiresAt,
    );
  }

  return checked;
}

/** Validates a user's claims against `options.claims`, keeping every JWT claim. */
async function checkClaims(
  state: AuthState,
  options: ResolveAuthOptions,
): Promise<AuthState> {
  if (state.kind !== "user") {
    return state;
  }

  if (!actorOf(state.claims).ok) {
    return { kind: "invalid", reason: "actor", error: invalidActorError() };
  }

  if (!options.claims) {
    return state;
  }

  let outcome = options.claims["~standard"].validate(state.claims);

  if (outcome instanceof Promise) {
    outcome = await outcome;
  }

  if (outcome.issues) {
    const issues = outcome.issues
      .map((issue) => {
        const path = issue.path
          ?.map((segment) =>
            typeof segment === "object" ? String(segment.key) : String(segment),
          )
          .join(".");

        return path ? `${path}: ${issue.message}` : issue.message;
      })
      .join("; ");

    return {
      kind: "invalid",
      reason: "claims",
      error: dbError(
        "unauthorized",
        `The token claims are invalid (${issues})`,
        { code: "CLAIMS_INVALID" },
      ),
    };
  }

  const extra = outcome.value;

  return typeof extra === "object" && extra !== null
    ? { ...state, claims: { ...state.claims, ...extra } }
    : state;
}

const warnedMetadata = new WeakSet<StandardSchemaV1>();

/**
 * Claims first, then `user_metadata`, whose failure never invalidates the
 * session.
 */
async function checkUser(
  state: AuthState,
  options: ResolveAuthOptions,
): Promise<AuthState> {
  const checked = await checkClaims(state, options);
  const schema = options.userMetadata;

  if (checked.kind !== "user" || !schema) {
    return checked;
  }

  const { userMetadata: _untrusted, ...user } = checked;

  let outcome = schema["~standard"].validate(
    checked.user.userMetadata ?? checked.claims.user_metadata ?? {},
  );

  if (outcome instanceof Promise) {
    outcome = await outcome;
  }

  if (!outcome.issues) {
    return { ...user, userMetadata: outcome.value };
  }

  if (!warnedMetadata.has(schema)) {
    warnedMetadata.add(schema);
    (options.logger ?? consoleLogger).warn(
      "user_metadata does not match betterSupabase.userMetadata(schema); session.userMetadata is undefined",
      {
        paths: outcome.issues.map(
          (issue) =>
            issue.path
              ?.map((segment) =>
                typeof segment === "object"
                  ? String(segment.key)
                  : String(segment),
              )
              .join(".") ?? "",
        ),
      },
    );
  }

  return user;
}

/**
 * Loads the remote JWKS into the process-wide cache so the first request
 * doesn't wait for it. Never throws; a failure leaves the first request to
 * fetch it.
 */
export async function prefetchJwks(options: ResolveAuthOptions): Promise<void> {
  const source = jwksOf(options);

  if (!(source instanceof URL)) {
    return;
  }

  await sharedJwks(source, false, {
    ...(options.fetch ? { fetch: options.fetch } : {}),
    ...(options.now ? { now: options.now } : {}),
  }).catch(() => undefined);
}

async function verifyOnce(
  credentials: { token: string | null; apikey: string | null },
  modes: AuthModeWithKey[],
  options: ResolveAuthOptions,
  source: "bearer" | "cookie",
): Promise<AuthState> {
  const token = credentials.token;
  const issuer = issuerOf(options);

  if (
    options.jwtSecret !== undefined &&
    token &&
    modes.length === 1 &&
    modes[0] === "user" &&
    isSharedSecretToken(token)
  ) {
    const verified = await verifyHs256(token, options.jwtSecret, {
      now: Math.floor((options.now ?? Date.now)() / 1000),
      ...(options.audience === undefined ? {} : { audience: options.audience }),
      ...(issuer === undefined ? {} : { issuer }),
    });

    if (!verified.ok) {
      return {
        kind: "invalid",
        reason: "token",
        error: dbError("unauthorized", verified.message, {
          code: verified.code,
        }),
      };
    }

    return (
      foreignIssuer(options, verified.claims) ?? {
        kind: "user",
        token,
        claims: verified.claims,
        user: verified.user,
        source,
        expiresAt:
          typeof verified.claims.exp === "number" ? verified.claims.exp : null,
      }
    );
  }

  const keys = await keysFor(options, token);

  if (!("keys" in keys)) {
    return { kind: "invalid", reason: "token", error: keys };
  }

  const { data, error } = await verifyCredentials(credentials, {
    auth: modes,
    env: serverEnv(options, keys),
    ...(options.audience === undefined ? {} : { audience: options.audience }),
    ...(issuer === undefined ? {} : { issuer }),
  });

  if (error) {
    const kind =
      error.code === "JWKS_FETCH_FAILED"
        ? "network"
        : error.status >= 500
          ? "unexpected"
          : "unauthorized";

    return {
      kind: "invalid",
      reason: "token",
      error: dbError(kind, error.message, { code: error.code }),
    };
  }

  if (data.authMode === "secret") {
    return { kind: "secret", keyName: data.keyName ?? "default" };
  }

  if (
    data.authMode === "user" &&
    data.token &&
    data.jwtClaims &&
    data.userClaims
  ) {
    return (
      foreignIssuer(options, data.jwtClaims) ?? {
        kind: "user",
        token: data.token,
        claims: data.jwtClaims,
        user: data.userClaims,
        source,
        expiresAt:
          typeof data.jwtClaims.exp === "number" ? data.jwtClaims.exp : null,
      }
    );
  }

  return { kind: "none", reason: "none" };
}

interface CookieChange {
  readonly writes: readonly CookieWrite[];
  readonly headers: Readonly<Record<string, string>>;
}

const NO_CHANGE: CookieChange = { writes: [], headers: {} };

function resolution(
  auth: AuthState,
  cookies: () => readonly CookieRecord[],
  change: CookieChange = NO_CHANGE,
  rejected?: SessionRejection,
  outage?: AuthOutageEvent,
): AuthResolution {
  const { writes } = change;

  const headers =
    writes.length === 0
      ? {}
      : Object.keys(change.headers).length > 0
        ? change.headers
        : NO_STORE;

  let requestCookies: readonly CookieRecord[] | undefined;

  return {
    auth,
    ...(rejected ? { sessionVerified: false, reason: rejected } : {}),
    ...(outage ? { outage } : {}),
    cookies: writes,
    headers,
    /** Parsed on first read: bearer requests rarely need their cookies. */
    get requestCookies() {
      requestCookies ??=
        writes.length > 0 ? applyCookieWrites(cookies(), writes) : cookies();

      return requestCookies;
    },
    apply(response) {
      if (writes.length === 0) {
        return response;
      }

      let target = response;

      try {
        for (const write of writes) {
          target.headers.append("set-cookie", serializeCookie(write));
        }
      } catch {
        target = new Response(response.body, response);

        for (const write of writes) {
          target.headers.append("set-cookie", serializeCookie(write));
        }
      }

      for (const [name, value] of Object.entries(headers)) {
        target.headers.set(name, value);
      }

      return target;
    },
  };
}

const IP = /^[0-9a-f:.]+$/i;

/**
 * The last `x-forwarded-for` hop, the one your own edge appended. Hops to its
 * left come from the client and can be forged. Behind more than one proxy, pass
 * your own reader to `clientIp`.
 */
export function clientIp(request: Request): string | undefined {
  const last = request.headers
    .get("x-forwarded-for")
    ?.split(",")
    .at(-1)
    ?.trim();

  return last && IP.test(last) ? last : undefined;
}

/**
 * Resolves who is calling: custom resolvers, then `Authorization: Bearer`
 * (APIs, MCP, mobile), then the `@supabase/ssr` session cookie (browsers).
 *
 * A valid token costs no network call: it is verified locally against the
 * cached JWKS. An expiring cookie session is refreshed only when `refresh` is
 * set, through a single-flight request, and only then are cookies written.
 */
/**
 * The access token `resolveAuth` would verify for `request`, without verifying
 * it: the bearer token, else the session cookie's. `null` when there is none.
 */
export function requestToken(
  request: Request,
  cookieName: string,
  cookies = true,
): string | null {
  const credentials = extractCredentials(request);

  if (credentials.token) {
    return credentials.token;
  }

  if (!cookies) {
    return null;
  }

  const session = readSession(
    parseCookies(request.headers.get("cookie")),
    cookieName,
  );

  return session?.access_token ?? null;
}

async function timed<T>(
  options: ResolveAuthOptions,
  phase: ResolvePhase,
  work: () => Promise<T>,
): Promise<T> {
  if (!options.onTiming) {
    return work();
  }

  const started = performance.now();

  try {
    return await work();
  } finally {
    options.onTiming(phase, performance.now() - started);
  }
}

export async function resolveAuth(
  request: Request,
  options: ResolveAuthOptions,
): Promise<AuthResolution> {
  let parsed: readonly CookieRecord[] | undefined;

  const cookies = (): readonly CookieRecord[] =>
    (parsed ??= parseCookies(request.headers.get("cookie")));

  const verifyTimed = (
    ...args: Parameters<typeof verify>
  ): ReturnType<typeof verify> =>
    timed(options, "verify", () => verify(...args));

  const statusTimed = (
    ...args: Parameters<typeof sessionStatus>
  ): ReturnType<typeof sessionStatus> =>
    timed(options, "ended", () => sessionStatus(...args));

  for (const resolver of options.resolvers ?? []) {
    const state = await resolver.resolve(request);

    if (!state) {
      continue;
    }

    return resolution(
      state.kind === "invalid"
        ? {
            kind: "invalid",
            reason: state.reason ?? "token",
            error: state.error,
          }
        : await checkUser(state, options),
      cookies,
    );
  }

  const credentials = extractCredentials(request);

  if (credentials.token) {
    return resolution(
      await verifyTimed(
        { token: credentials.token, apikey: null },
        ["user"],
        options,
        "bearer",
      ),
      cookies,
    );
  }

  if (options.secret && credentials.apikey?.startsWith("sb_secret_")) {
    return resolution(
      await verifyTimed(
        { token: null, apikey: credentials.apikey },
        options.secret === true
          ? ["secret"]
          : options.secret.map((name): AuthModeWithKey => `secret:${name}`),
        options,
        "bearer",
      ),
      cookies,
    );
  }

  if (options.cookies === false) {
    return resolution({ kind: "none", reason: "none" }, cookies);
  }

  const name = options.cookie?.name ?? sessionCookieName(options.env.url);

  const parseStarted = options.onTiming ? performance.now() : 0;
  const session = readSession(cookies(), name);
  options.onTiming?.("parse", performance.now() - parseStarted);

  const cleared = (): Promise<CookieChange> =>
    clearCookieSession({
      cookieName: name,
      cookies: cookies(),
      ...(options.cookie?.options
        ? { cookieOptions: options.cookie.options }
        : {}),
    });

  if (!session) {
    const stale = cookies().some(
      (cookie) => cookie.name === name || cookie.name.startsWith(`${name}.`),
    );

    return resolution(
      { kind: "none", reason: stale ? "signed_out" : "none" },
      cookies,
      stale && options.refresh ? await cleared() : NO_CHANGE,
    );
  }

  const now = Math.floor((options.now ?? Date.now)() / 1000);
  const expiry = expiryOf(session);
  // The leeway only decides when to refresh: where refreshing isn't allowed,
  // a token in its last minute is still valid.
  const leeway = options.refresh ? (options.leeway ?? 60) : 0;
  const fresh = expiry !== undefined && expiry - leeway > now;

  if (fresh) {
    const state = await verifyTimed(
      { token: session.access_token, apikey: null },
      ["user"],
      options,
      "cookie",
    );

    const status =
      state.kind === "user" && options.verifySession
        ? await statusTimed(state.token, {
            url: options.env.url,
            publishableKey: options.env.publishableKey,
            ...(options.fetch ? { fetch: options.fetch } : {}),
            ...(options.refreshTimeoutMs === undefined
              ? {}
              : { timeoutMs: options.refreshTimeoutMs }),
            ...(options.now ? { now: options.now } : {}),
          })
        : undefined;

    if (status === "ended" || status === "banned") {
      return resolution(
        { kind: "none", reason: "signed_out" },
        cookies,
        options.refresh ? await cleared() : NO_CHANGE,
        status === "banned" ? "user_banned" : "session_not_found",
      );
    }

    // A refresh can't fix claims the schema or the act check rejects, nor an unreachable JWKS.
    if (
      state.kind !== "invalid" ||
      state.reason !== "token" ||
      state.error.kind === "network"
    ) {
      return resolution(state, cookies);
    }

    if (!options.refresh) {
      return resolution({ kind: "none", reason: "signed_out" }, cookies);
    }
  } else if (!options.refresh) {
    return resolution({ kind: "none", reason: "expired" }, cookies);
  }

  const secretKey = options.env.secretKey;

  const ip =
    secretKey && options.clientIp !== false
      ? (options.clientIp ?? clientIp)(request)
      : undefined;

  const started = performance.now();

  const refreshed: CookieRefresh = await timed(options, "refresh", () =>
    refreshCookieSession({
      url: options.env.url,
      publishableKey: options.env.publishableKey,
      cookieName: name,
      cookies: cookies(),
      refreshToken: session.refresh_token,
      ...(options.cookie?.options
        ? { cookieOptions: options.cookie.options }
        : {}),
      ...(options.cookie?.encode === undefined
        ? {}
        : { encode: options.cookie.encode }),
      ...(secretKey && ip ? { forwardedFor: { ip, secretKey } } : {}),
      ...(options.fetch ? { fetch: options.fetch } : {}),
      ...(options.now ? { now: options.now } : {}),
      ...(options.refreshTimeoutMs === undefined
        ? {}
        : { timeoutMs: options.refreshTimeoutMs }),
    }),
  );

  const { outcome } = refreshed;
  const durationMs = performance.now() - started;

  options.onRefresh?.({
    ok: outcome.ok,
    shared: outcome.ok && outcome.shared,
    durationMs,
    ...(outcome.ok
      ? {}
      : {
          reason: outcome.reason,
          ...(outcome.status === undefined ? {} : { status: outcome.status }),
          ...("code" in outcome ? { code: outcome.code } : {}),
        }),
  });

  if (!outcome.ok) {
    // An early refresh, in the leeway, leaves a token that is good until it expires.
    const stillValid = async (): Promise<AuthState | undefined> => {
      if (fresh || expiry === undefined || expiry <= now) {
        return undefined;
      }

      const state = await verifyTimed(
        { token: session.access_token, apikey: null },
        ["user"],
        options,
        "cookie",
      );

      return state.kind === "invalid" ? undefined : state;
    };

    switch (outcome.reason) {
      case "network": {
        const kept = await stillValid();

        const outage: AuthOutageEvent = {
          cause: outcome.cause,
          ...(outcome.status === undefined ? {} : { status: outcome.status }),
          kept: kept !== undefined,
          durationMs,
        };

        // auth-js clears the session when the token request fails; an
        // unreachable Auth server must not sign anyone out.
        return resolution(
          kept ?? { kind: "none", reason: "refresh_failed" },
          cookies,
          NO_CHANGE,
          undefined,
          outage,
        );
      }

      case "raced": {
        // The request that won the rotation sets the new cookies; clearing
        // them here would sign the user out.
        return resolution(
          (await stillValid()) ?? { kind: "none", reason: "expired" },
          cookies,
        );
      }

      case "rejected": {
        return resolution(
          { kind: "none", reason: "signed_out" },
          cookies,
          refreshed.writes.length > 0 ? refreshed : await cleared(),
          outcome.code === "user_banned" ? "user_banned" : undefined,
        );
      }

      default: {
        const unhandled: never = outcome;

        return unhandled;
      }
    }
  }

  const state = await verifyTimed(
    { token: outcome.session.access_token, apikey: null },
    ["user"],
    options,
    "cookie",
  );

  return resolution(state, cookies, refreshed);
}
