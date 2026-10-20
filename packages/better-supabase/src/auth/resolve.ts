import type {
  AuthModeWithKey,
  JWTClaims,
  SupabaseEnv,
  UserClaims,
} from "@supabase/server";

import { extractCredentials, verifyCredentials } from "@supabase/server/core";

import type { AuthOutageEvent, RefreshEvent } from "../core/events.ts";
import type { Logger } from "../core/logger.ts";
import type { StandardSchemaV1 } from "../core/standard.ts";
import type { BetterSupabaseEnv } from "../env/index.ts";

import { decodeJwtPayload } from "../core/base64.ts";
import { type DbError, dbError } from "../core/errors.ts";
import { consoleLogger } from "../core/logger.ts";
import { actorOf, invalidActorError } from "./actor.ts";
import { sessionStatus } from "./ended.ts";
import { clearHs256Keys, isSharedSecretToken, verifyHs256 } from "./hs256.ts";
import { refreshSession } from "./refresh.ts";
import {
  applyCookieWrites,
  AUTH_CACHE_HEADERS,
  type CookieOptions,
  type CookieRecord,
  type CookieWrite,
  parseCookies,
  pruneSessionChunks,
  readSession,
  serializeCookie,
  sessionCookieName,
  type SessionEncoding,
  type StoredSession,
  writeSession,
  type WriteSessionOptions,
} from "./session.ts";

/**
 * Who is calling. `C` is the claims type from `betterSupabase.claims(schema)`; the
 * verified payload keeps every JWT claim and adds the schema's output. `P`
 * is the `user_metadata` type from `betterSupabase.userMetadata(schema)`.
 */
export type AuthState<C = unknown, P = unknown> =
  | {
      readonly kind: "user";
      readonly token: string;
      readonly claims: JWTClaims & C;
      readonly user: UserClaims;
      /**
       * Where the token came from: `oauth` for an RFC 9068 access token
       * from `accessTokenResolver`, which never has a cookie session.
       */
      readonly source: "bearer" | "cookie" | "oauth" | (string & {});
      /** Seconds since epoch, from the token's `exp`. */
      readonly expiresAt: number | null;
      /**
       * `user_metadata` parsed by `betterSupabase.userMetadata(schema)`; `undefined`
       * without a schema or when the metadata fails it. Users can write this
       * data themselves: use it for display, never for access.
       */
      readonly profile?: P;
    }
  | { readonly kind: "service"; readonly keyName: string }
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
      /** `sub` (the user, or the key for an organization key), `role: authenticated` and `api_key`. */
      readonly claims: JWTClaims;
    }
  | {
      readonly kind: "anon";
      /** `expired`: the cookie session needs a refresh that was not allowed here (run the proxy). */
      readonly reason: "none" | "expired" | "signed_out" | "refresh_failed";
    }
  /**
   * Credentials were sent but did not verify (`token`), verified but failed
   * the claims schema (`claims`), or carry a malformed RFC 8693 `act` chain
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
  /** Allow refreshing an expiring cookie session. Only where cookies can be written (proxy). */
  readonly refresh?: boolean;
  /**
   * With `refresh`, refresh when the token expires within this many seconds.
   * Defaults to 60. Without `refresh` a token stays valid until its `exp`.
   */
  readonly leeway?: number;
  /** Milliseconds before a refresh counts as a network failure. Defaults to 5000. */
  readonly refreshTimeoutMs?: number;
  readonly checkSession?: boolean;
  /**
   * Accept `sb_secret_` keys (`apikey` header) as service callers: `true` for
   * any configured key, or the key names allowed (`['cron']`). Defaults to false.
   */
  readonly secret?: boolean | readonly string[];
  readonly audience?: string | string[];
  readonly issuer?: string | string[];
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
   * Inline JWKS instead of fetching `env.jwksUrl` (tests, air-gapped).
   * `false` or `null` verifies against no keys and never fetches, ignoring
   * `SUPABASE_JWKS` and `SUPABASE_JWKS_URL`.
   */
  readonly jwks?: SupabaseEnv["jwks"] | false;
  /**
   * Verify HS256 tokens without a `kid` locally with this shared secret, the
   * tokens Supabase Lite issues (`auth.jwt_secret`). Tokens with a `kid`
   * still verify against the JWKS. `createServer` sets it from
   * `SUPABASE_JWT_SECRET` with `backend: "lite"`.
   */
  readonly jwtSecret?: string;
  /**
   * Validates the verified claims (`betterSupabase.claims(schema)` sets it). A failure
   * resolves to `{ kind: 'invalid', reason: 'claims' }`.
   */
  readonly claims?: StandardSchemaV1;
  /**
   * Parses `user_metadata` into `profile` (`betterSupabase.userMetadata(schema)` sets
   * it). A failure leaves `profile` undefined and warns once; the session
   * stays valid.
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
   * With `refresh`, expire session chunks the readable session doesn't use
   * (a leftover `.2` after a shorter rewrite) on every request, not only
   * when the session is rewritten. Defaults to true.
   */
  readonly pruneChunks?: boolean;
  readonly fetch?: typeof fetch;
  /** Epoch milliseconds, the unit JWT `exp` and `iat` math needs. */
  readonly now?: () => number;
}

export interface AuthResolution<C = unknown, P = unknown> {
  readonly auth: AuthState<C, P>;
  /** Cookie writes for the response. Empty unless the session was refreshed or cleared. */
  readonly cookies: readonly CookieWrite[];
  /** No-store headers, set whenever `cookies` is not empty. */
  readonly headers: Readonly<Record<string, string>>;
  /** Cookies the rest of this request should see, including a refreshed session. */
  readonly requestCookies: readonly CookieRecord[];
  /** Adds `cookies` and `headers` to a response. */
  apply(response: Response): Response;
  /** The session was ended server-side (revoked, deleted or banned); the cookies are cleared. */
  readonly sessionEnded?: boolean;
  /** Why `sessionEnded` is set: `banned` when Auth rejected the user as banned. */
  readonly sessionEndedReason?: "ended" | "banned";
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

/** An empty key set: `auth.jwks: false` verifies against it and fetches nothing. */
const NO_KEYS: JwksSource = { keys: [] };

/** `auth.jwks`, then `env.jwks` (`SUPABASE_JWKS`), then `env.jwksUrl`. */
function jwksOf(options: ResolveAuthOptions): JwksSource {
  if (options.jwks === false || options.jwks === null) {
    return NO_KEYS;
  }

  return options.jwks ?? options.env.jwks ?? options.env.jwksUrl;
}

function serverEnv(options: ResolveAuthOptions): SupabaseEnv {
  const { env } = options;

  return {
    url: env.url,
    publishableKeys: { default: env.publishableKey },
    secretKeys:
      env.secretKeys ?? (env.secretKey ? { default: env.secretKey } : {}),
    jwks: jwksOf(options),
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

/** A number per JWT secret, so memo keys tell secrets apart. Bounded, and never reuses a number. */
const secretIds = new Map<string, number>();
let nextSecretId = 1;

function secretId(secret: string | undefined): number | null {
  if (secret === undefined) {
    return null;
  }

  let id = secretIds.get(secret);

  if (id === undefined) {
    id = nextSecretId++;
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
 * and island resolves the same token again; this skips the signature check.
 * A hit skips the audience and issuer checks too, so both are part of the key.
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

/** Forgets every verified token. For benchmarks and tests. */
export function clearVerifiedTokens(): void {
  memoByUrl.clear();
  memoByJwks = new WeakMap();
  secretIds.clear();
  clearHs256Keys();
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
 * Tokens that already passed (or failed) the claims and `userMetadata`
 * schemas, per verification memo and schema pair, so a memo hit skips
 * validation too.
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
        {
          code: "CLAIMS_INVALID",
        },
      ),
    };
  }

  const extra = outcome.value;

  return typeof extra === "object" && extra !== null
    ? { ...state, claims: { ...state.claims, ...extra } }
    : state;
}

const warnedMetadata = new WeakSet<StandardSchemaV1>();

/** Claims first, then `user_metadata`, whose failure never invalidates the session. */
async function checkUser(
  state: AuthState,
  options: ResolveAuthOptions,
): Promise<AuthState> {
  const checked = await checkClaims(state, options);
  const schema = options.userMetadata;

  if (checked.kind !== "user" || !schema) {
    return checked;
  }

  const { profile: _untrusted, ...user } = checked;

  let outcome = schema["~standard"].validate(
    checked.user.userMetadata ?? checked.claims.user_metadata ?? {},
  );

  if (outcome instanceof Promise) {
    outcome = await outcome;
  }

  if (!outcome.issues) {
    return { ...user, profile: outcome.value };
  }

  if (!warnedMetadata.has(schema)) {
    warnedMetadata.add(schema);
    (options.logger ?? consoleLogger).warn(
      "user_metadata does not match betterSupabase.userMetadata(schema); session.profile is undefined",
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

/** A token whose `kid` matches no key: verifying it loads the JWKS and fails. */
const PREFETCH_TOKEN = `${base64url(
  JSON.stringify({ alg: "ES256", kid: "better-supabase-prefetch", typ: "JWT" }),
)}.e30.AA`;

function base64url(text: string): string {
  return btoa(text)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

/**
 * Loads the remote JWKS into the verifier's cache so the first request
 * doesn't wait for it. Never throws; a failure leaves the first request to
 * fetch it as before.
 */
export function prefetchJwks(options: ResolveAuthOptions): Promise<void> {
  if (!(jwksOf(options) instanceof URL)) {
    return Promise.resolve();
  }

  return verifyCredentials(
    { token: PREFETCH_TOKEN, apikey: null },
    { auth: ["user"], env: serverEnv(options) },
  ).then(
    () => {},
    () => {},
  );
}

async function verifyOnce(
  credentials: { token: string | null; apikey: string | null },
  modes: AuthModeWithKey[],
  options: ResolveAuthOptions,
  source: "bearer" | "cookie",
): Promise<AuthState> {
  const token = credentials.token;

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
      ...(options.issuer === undefined ? {} : { issuer: options.issuer }),
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

    return {
      kind: "user",
      token,
      claims: verified.claims,
      user: verified.user,
      source,
      expiresAt:
        typeof verified.claims.exp === "number" ? verified.claims.exp : null,
    };
  }

  const { data, error } = await verifyCredentials(credentials, {
    auth: modes,
    env: serverEnv(options),
    ...(options.audience === undefined ? {} : { audience: options.audience }),
    ...(options.issuer === undefined ? {} : { issuer: options.issuer }),
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
    return { kind: "service", keyName: data.keyName ?? "default" };
  }

  if (
    data.authMode === "user" &&
    data.token &&
    data.jwtClaims &&
    data.userClaims
  ) {
    return {
      kind: "user",
      token: data.token,
      claims: data.jwtClaims,
      user: data.userClaims,
      source,
      expiresAt:
        typeof data.jwtClaims.exp === "number" ? data.jwtClaims.exp : null,
    };
  }

  return { kind: "anon", reason: "none" };
}

function resolution(
  auth: AuthState,
  cookies: () => readonly CookieRecord[],
  writes: readonly CookieWrite[] = [],
  ended?: "ended" | "banned",
  outage?: AuthOutageEvent,
): AuthResolution {
  const headers = writes.length > 0 ? AUTH_CACHE_HEADERS : {};
  let requestCookies: readonly CookieRecord[] | undefined;

  return {
    auth,
    ...(ended ? { sessionEnded: true, sessionEndedReason: ended } : {}),
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
 * left come from the client and can be forged. Behind more than one proxy,
 * pass your own reader to `clientIp`.
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
export async function resolveAuth(
  request: Request,
  options: ResolveAuthOptions,
): Promise<AuthResolution> {
  let parsed: readonly CookieRecord[] | undefined;

  const cookies = (): readonly CookieRecord[] =>
    (parsed ??= parseCookies(request.headers.get("cookie")));

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
      await verify(
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
      await verify(
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
    return resolution({ kind: "anon", reason: "none" }, cookies);
  }

  const name = options.cookie?.name ?? sessionCookieName(options.env.url);

  const encoding: WriteSessionOptions =
    options.cookie?.encode === undefined
      ? {}
      : { encode: options.cookie.encode };

  const session = readSession(cookies(), name);

  if (!session) {
    const stale = cookies().some(
      (cookie) => cookie.name === name || cookie.name.startsWith(`${name}.`),
    );

    const writes =
      stale && options.refresh
        ? writeSession(cookies(), name, null, options.cookie?.options, encoding)
        : [];

    return resolution(
      { kind: "anon", reason: stale ? "signed_out" : "none" },
      cookies,
      writes,
    );
  }

  // Leftover chunks are expired wherever cookies can be written, so they
  // don't wait for the next refresh.
  const pruned =
    options.refresh && options.pruneChunks !== false
      ? pruneSessionChunks(cookies(), name, options.cookie?.options)
      : [];

  const now = Math.floor((options.now ?? Date.now)() / 1000);
  const expiry = expiryOf(session);
  // The leeway only decides when to refresh: where refreshing isn't allowed,
  // a token in its last minute is still valid.
  const leeway = options.refresh ? (options.leeway ?? 60) : 0;
  const fresh = expiry !== undefined && expiry - leeway > now;

  if (fresh) {
    const state = await verify(
      { token: session.access_token, apikey: null },
      ["user"],
      options,
      "cookie",
    );

    const status =
      state.kind === "user" && options.checkSession
        ? await sessionStatus(state.token, {
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
        { kind: "anon", reason: "signed_out" },
        cookies,
        options.refresh
          ? writeSession(
              cookies(),
              name,
              null,
              options.cookie?.options,
              encoding,
            )
          : [],
        status,
      );
    }

    // A refresh can't fix claims the schema or the act check rejects, nor an unreachable JWKS.
    if (
      state.kind !== "invalid" ||
      state.reason !== "token" ||
      state.error.kind === "network"
    ) {
      return resolution(state, cookies, pruned);
    }

    if (!options.refresh) {
      return resolution({ kind: "anon", reason: "signed_out" }, cookies);
    }
  } else if (!options.refresh) {
    return resolution({ kind: "anon", reason: "expired" }, cookies);
  }

  const secretKey = options.env.secretKey;

  const ip =
    secretKey && options.clientIp !== false
      ? (options.clientIp ?? clientIp)(request)
      : undefined;

  const started = performance.now();

  const outcome = await refreshSession(session.refresh_token, {
    url: options.env.url,
    publishableKey: options.env.publishableKey,
    ...(secretKey && ip ? { forwardedFor: { ip, secretKey } } : {}),
    ...(options.fetch ? { fetch: options.fetch } : {}),
    ...(options.now ? { now: options.now } : {}),
    ...(options.refreshTimeoutMs === undefined
      ? {}
      : { timeoutMs: options.refreshTimeoutMs }),
  });

  const durationMs = performance.now() - started;
  options.onRefresh?.({
    ok: outcome.ok,
    shared: outcome.ok && outcome.shared === true,
    durationMs,
    ...(outcome.ok
      ? {}
      : {
          reason: outcome.reason,
          ...(outcome.status === undefined ? {} : { status: outcome.status }),
          ...(outcome.code === undefined ? {} : { code: outcome.code }),
        }),
  });

  if (!outcome.ok) {
    if (outcome.reason === "network") {
      const outage = (kept: boolean): AuthOutageEvent => ({
        cause:
          outcome.cause === "timeout"
            ? "timeout"
            : outcome.cause === "status"
              ? "status"
              : "network",
        ...(outcome.status === undefined ? {} : { status: outcome.status }),
        kept,
        durationMs,
      });

      // A token refreshed early, in its leeway, is still good until it expires.
      if (!fresh && expiry !== undefined && expiry > now) {
        const state = await verify(
          { token: session.access_token, apikey: null },
          ["user"],
          options,
          "cookie",
        );

        if (state.kind !== "invalid") {
          return resolution(state, cookies, pruned, undefined, outage(true));
        }
      }

      return resolution(
        { kind: "anon", reason: "refresh_failed" },
        cookies,
        pruned,
        undefined,
        outage(false),
      );
    }

    return resolution(
      { kind: "anon", reason: "signed_out" },
      cookies,
      writeSession(cookies(), name, null, options.cookie?.options, encoding),
      outcome.code === "user_banned" ? "banned" : undefined,
    );
  }

  const writes = writeSession(
    cookies(),
    name,
    outcome.session,
    options.cookie?.options,
    encoding,
  );

  const state = await verify(
    { token: outcome.session.access_token, apikey: null },
    ["user"],
    options,
    "cookie",
  );

  return resolution(state, cookies, writes);
}
