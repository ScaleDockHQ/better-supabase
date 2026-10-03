import type {
  AuthModeWithKey,
  JWTClaims,
  SupabaseEnv,
  UserClaims,
} from "@supabase/server";

import { extractCredentials, verifyCredentials } from "@supabase/server/core";

import type { RefreshEvent } from "../core/events.ts";
import type { Logger } from "../core/logger.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { StandardSchemaV1 } from "../core/standard.ts";
import type { BetterSupabaseEnv } from "../env/index.ts";

import { decodeJwtPayload } from "../core/base64.ts";
import { type DbError, dbError } from "../core/errors.ts";
import { consoleLogger } from "../core/logger.ts";
import { actorOf } from "./actor.ts";
import { userContext } from "./impersonation.ts";
import { refreshSession } from "./refresh.ts";
import {
  applyCookieWrites,
  AUTH_CACHE_HEADERS,
  type CookieOptions,
  type CookieRecord,
  type CookieWrite,
  parseCookies,
  readSession,
  serializeCookie,
  sessionCookieName,
  type StoredSession,
  writeSession,
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
      readonly source: "bearer" | "cookie" | (string & {});
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
  };
  /**
   * Read the session cookie. Defaults to true. `false` suits endpoints only
   * bearer clients call (MCP): a browser's cookie then can't authorize a
   * request another site makes it send.
   */
  readonly cookies?: boolean;
  /** Inline JWKS instead of fetching `env.jwksUrl` (tests, air-gapped). */
  readonly jwks?: SupabaseEnv["jwks"];
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
   * `clientIp` (the first `x-forwarded-for` hop); `false` turns it off.
   */
  readonly clientIp?: ((request: Request) => string | undefined) | false;
  /** Called after every refresh attempt (metrics, logging). */
  readonly onRefresh?: (event: RefreshEvent) => void;
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
}

function expiryOf(session: StoredSession): number | undefined {
  if (typeof session.expires_at === "number") return session.expires_at;
  const exp = decodeJwtPayload(session.access_token)?.["exp"];
  return typeof exp === "number" ? exp : undefined;
}

function serverEnv(options: ResolveAuthOptions): SupabaseEnv {
  const { env } = options;
  return {
    url: env.url,
    publishableKeys: { default: env.publishableKey },
    secretKeys:
      env.secretKeys ?? (env.secretKey ? { default: env.secretKey } : {}),
    jwks: options.jwks ?? env.jwks ?? env.jwksUrl,
  };
}

type VerifiedUser = Omit<
  Extract<AuthState, { kind: "user" }>,
  "source" | "profile"
>;

const MEMO_SIZE = 256;
const memoByUrl = new Map<string, Map<string, VerifiedUser>>();
let memoByJwks = new WeakMap<object, Map<string, VerifiedUser>>();

/**
 * Tokens that already verified, until they expire. Every private-cache scope
 * and island resolves the same token again; this skips the signature check.
 */
function memoFor(options: ResolveAuthOptions): Map<string, VerifiedUser> {
  const jwks = options.jwks ?? options.env.jwks;
  if (jwks && typeof jwks === "object" && !(jwks instanceof URL)) {
    let memo = memoByJwks.get(jwks);
    if (!memo) memoByJwks.set(jwks, (memo = new Map<string, VerifiedUser>()));
    return memo;
  }
  const key = JSON.stringify([
    String(jwks ?? options.env.jwksUrl),
    options.env.url,
    options.audience ?? null,
    options.issuer ?? null,
  ]);
  let memo = memoByUrl.get(key);
  if (!memo) memoByUrl.set(key, (memo = new Map<string, VerifiedUser>()));
  return memo;
}

/** Forgets every verified token. For benchmarks and tests. */
export function clearVerifiedTokens(): void {
  memoByUrl.clear();
  memoByJwks = new WeakMap();
}

function remembered(
  memo: Map<string, VerifiedUser>,
  token: string,
  now: number,
): VerifiedUser | undefined {
  const hit = memo.get(token);
  if (!hit) return undefined;
  memo.delete(token);
  if (hit.expiresAt === null || hit.expiresAt <= now) return undefined;
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
  if (!byClaims) checkedByMemo.set(memo, (byClaims = new WeakMap()));
  let byMetadata = byClaims.get(claims);
  if (!byMetadata) byClaims.set(claims, (byMetadata = new WeakMap()));
  let checked = byMetadata.get(metadata);
  if (!checked)
    byMetadata.set(metadata, (checked = new Map<string, CheckedState>()));
  return checked;
}

function withoutSource(state: AuthState): CheckedState {
  if (state.kind !== "user") return state;
  const { source: _source, ...rest } = state;
  return rest;
}

function remember<T>(
  memo: Map<string, T>,
  token: string,
  user: T,
  expiresAt: number | null,
): void {
  if (expiresAt === null) return;
  memo.set(token, user);
  if (memo.size > MEMO_SIZE) memo.delete(memo.keys().next().value!);
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
  if (state.kind !== "user") return state;
  if (!actorOf(state.claims).ok) {
    return {
      kind: "invalid",
      reason: "actor",
      error: dbError(
        "unauthorized",
        "The token's act claim is not a chain of actors with a sub",
        { code: "ACTOR_INVALID" },
      ),
    };
  }
  if (!options.claims) return state;
  let outcome = options.claims["~standard"].validate(state.claims);
  if (outcome instanceof Promise) outcome = await outcome;
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
  if (checked.kind !== "user" || !schema) return checked;
  const { profile: _untrusted, ...user } = checked;
  let outcome = schema["~standard"].validate(
    checked.user.userMetadata ?? checked.claims.user_metadata ?? {},
  );
  if (outcome instanceof Promise) outcome = await outcome;
  if (!outcome.issues) return { ...user, profile: outcome.value };
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
  if (options.jwks !== undefined || options.env.jwks !== undefined)
    return Promise.resolve();
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
  if (data.authMode === "secret")
    return { kind: "service", keyName: data.keyName ?? "default" };
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
): AuthResolution {
  const headers = writes.length > 0 ? AUTH_CACHE_HEADERS : {};
  let requestCookies: readonly CookieRecord[] | undefined;
  return {
    auth,
    cookies: writes,
    headers,
    /** Parsed on first read: bearer requests rarely need their cookies. */
    get requestCookies() {
      requestCookies ??=
        writes.length > 0 ? applyCookieWrites(cookies(), writes) : cookies();
      return requestCookies;
    },
    apply(response) {
      if (writes.length === 0) return response;
      let target = response;
      try {
        for (const write of writes)
          target.headers.append("set-cookie", serializeCookie(write));
      } catch {
        target = new Response(response.body, response);
        for (const write of writes)
          target.headers.append("set-cookie", serializeCookie(write));
      }
      for (const [name, value] of Object.entries(headers))
        target.headers.set(name, value);
      return target;
    },
  };
}

const IP = /^[0-9a-f:.]+$/i;

/** The first `x-forwarded-for` hop, the client as your edge saw it. */
export function clientIp(request: Request): string | undefined {
  const first = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return first && IP.test(first) ? first : undefined;
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
    if (!state) continue;
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
  const session = readSession(cookies(), name);
  if (!session) {
    const stale = cookies().some(
      (cookie) => cookie.name === name || cookie.name.startsWith(`${name}.`),
    );
    const writes =
      stale && options.refresh
        ? writeSession(cookies(), name, null, options.cookie?.options)
        : [];
    return resolution(
      { kind: "anon", reason: stale ? "signed_out" : "none" },
      cookies,
      writes,
    );
  }

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
    // A refresh can't fix claims the schema or the act check rejects, nor an unreachable JWKS.
    if (
      state.kind !== "invalid" ||
      state.reason !== "token" ||
      state.error.kind === "network"
    )
      return resolution(state, cookies);
    if (!options.refresh)
      return resolution({ kind: "anon", reason: "signed_out" }, cookies);
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
  options.onRefresh?.({
    ok: outcome.ok,
    shared: outcome.ok && outcome.shared === true,
    durationMs: performance.now() - started,
  });
  if (!outcome.ok) {
    if (outcome.reason === "network")
      return resolution({ kind: "anon", reason: "refresh_failed" }, cookies);
    return resolution(
      { kind: "anon", reason: "signed_out" },
      cookies,
      writeSession(cookies(), name, null, options.cookie?.options),
    );
  }
  const writes = writeSession(
    cookies(),
    name,
    outcome.session,
    options.cookie?.options,
  );
  const state = await verify(
    { token: outcome.session.access_token, apikey: null },
    ["user"],
    options,
    "cookie",
  );
  return resolution(state, cookies, writes);
}

/** The repository context (`actor`, `claims`) for an auth state. */
export function authContext(auth: AuthState): RequestContext {
  switch (auth.kind) {
    case "user":
      return userContext(auth.user, auth.claims);
    case "service":
      return {
        actor: {
          id: `service:${auth.keyName}`,
          kind: "service",
          role: "service_role",
        },
        claims: { role: "service_role" },
      };
    case "anon":
    case "invalid":
      return {
        actor: { id: "anon", kind: "anon", role: "anon" },
        claims: { role: "anon" },
      };
    default: {
      const exhaustive: never = auth;
      return exhaustive;
    }
  }
}
