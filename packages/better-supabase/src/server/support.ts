import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AuthState } from "../auth/resolve.ts";
import type { SupportAuthorizeInput } from "../core/contracts/authorization-hooks.ts";
import type { EventHub } from "../core/events.ts";

import {
  clearSupportCookie,
  type SupportCookieOptions,
  supportCookie,
  supportCookieValue,
} from "../auth/support-cookie.ts";
import {
  supportClaims,
  type SupportListFilter,
  type SupportSession,
  type SupportSessionStore,
} from "../auth/support.ts";
import { emitBlockEvent, type SupportEventData } from "../core/block-events.ts";
import { cronRoute } from "../core/cron-route.ts";
import { type DbError, dbError, mapDbError } from "../core/errors.ts";
import { type ProblemFormat, problemResponse } from "../core/problem.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { boundedTtlCache } from "../core/ttl-cache.ts";
import { fromPgError } from "../postgres/executor.ts";

type UserAuth = Extract<AuthState, { kind: "user" }>;

export interface SupportPolicy {
  /** Seconds a session lasts. Defaults to 1800 (30 minutes). */
  readonly ttl?: number;
  /** The longest `ttl` a start may ask for. Defaults to 14400 (4 hours). */
  readonly maxTtl?: number;
  /** Defaults to true. */
  readonly requireReason?: boolean;
  /**
   * `always` (the default): every session is read-only. `default`: read-only
   * unless the start passes `readOnly: false`.
   */
  readonly readOnly?: "always" | "default";
}

export type { SupportAuthorizeInput };

export interface SupportOptions {
  readonly store: SupportSessionStore;
  /**
   * Whether `admin` may view the app as the target. A throw or rejection
   * counts as a deny. Defaults to allowing, so the store decides: the SQL
   * store checks `is_platform(modules.support-sessions.permissions.start)`.
   */
  readonly authorize?: (
    input: SupportAuthorizeInput,
  ) => boolean | Promise<boolean>;
  /**
   * The claims the target gets. Defaults to `store.claims` (the SQL store
   * runs your custom access token hook), then `{ role: 'authenticated' }`.
   */
  readonly claims?: (
    targetUserId: string,
  ) =>
    | Readonly<Record<string, unknown>>
    | Promise<Readonly<Record<string, unknown>>>;
  readonly policy?: SupportPolicy;
  readonly cookie?: SupportCookieOptions;
  /**
   * Where a request names its support session, for apps that keep it in a
   * header or their own request store instead of the `bs-support` cookie.
   * Defaults to reading the cookie.
   */
  readonly sessionId?: (request: Request) => string | undefined;
}

export interface SupportStartRequest {
  readonly targetUserId: string;
  readonly reason?: string;
  /** Seconds; defaults to `policy.ttl`. */
  readonly ttl?: number;
  /** Honoured only with `policy.readOnly: 'default'`. */
  readonly readOnly?: boolean;
  readonly tenant?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** Options for `support.expireRoute`. */
export interface SupportExpireRouteOptions {
  /** The bearer token the cron caller sends, such as `process.env.CRON_SECRET`. */
  readonly secret: string | undefined;
  /** Rewrites the Problem Details bodies of the route's errors. */
  readonly problem?: ProblemFormat;
}

/** A running support session, as the request that carries its cookie sees it. */
export interface ActiveSupport {
  readonly session: SupportSession;
  /** The admin behind the session, from their own verified token. */
  readonly admin: { readonly id: string; readonly email?: string };
  /** The target's claims plus `act`, which repositories run with. */
  readonly claims: Readonly<Record<string, unknown>>;
}

/** `bs.support`: start, stop and inspect support sessions. */
export interface SupportApi {
  /**
   * Starts a session for a signed-in admin and returns it with the
   * `Set-Cookie` value that switches the admin's next requests to the target.
   */
  start(
    admin: AuthState,
    request: SupportStartRequest,
  ): AsyncResult<{ readonly session: SupportSession; readonly cookie: string }>;
  /** Ends the admin's own session and returns the `Set-Cookie` that clears the cookie. */
  stop(
    admin: AuthState,
    sessionId: string,
  ): AsyncResult<{ readonly ended: boolean; readonly cookie: string }>;
  /**
   * Ends a session as `caller`: the SQL store allows the session's admin and
   * staff with the revoke permission.
   */
  revoke(caller: AuthState, sessionId: string): AsyncResult<boolean>;
  /** The running session the request names (`sessionIdOf`) for `auth`, if any. */
  current(
    request: Request,
    auth: AuthState,
  ): Promise<ActiveSupport | undefined>;
  /**
   * The running session `sessionId` for the admin in `auth`, if any. Use it
   * when the app keeps the session id in its own request context; pass the
   * result to `contextFor(auth, { support })` or `dbFor(auth, context, { support })`.
   */
  resolve(
    sessionId: string,
    auth: AuthState,
  ): Promise<ActiveSupport | undefined>;
  /** The sessions `caller` may view (the SQL store checks the view permission). */
  list(
    caller: AuthState,
    filter?: SupportListFilter,
  ): AsyncResult<readonly SupportSession[]>;
  /**
   * Ends every session past its expiry through the store and emits
   * `support.ended` with `endedBy: "expired"` for each; the SQL store runs
   * over `postgres.admin`. Returns the sessions it ended.
   */
  expire(): AsyncResult<readonly SupportSession[]>;
  /**
   * A `GET` or `POST` handler for a cron caller that runs `expire()` and
   * answers `{ expired }`, the number of sessions it ended.
   */
  expireRoute(
    options: SupportExpireRouteOptions,
  ): (request: Request) => Promise<Response>;
  /** The support session id a request names: `options.sessionId`, or the cookie. */
  sessionIdOf(request: Request): string | undefined;
  /** `Set-Cookie` that clears the support cookie. */
  clearCookie(): string;
}

/** How long a support target's claims are reused; a role change applies within it. */
const CLAIMS_TTL_MS = 60_000;
const CLAIMS_CACHE_SIZE = 1000;

const denied = (message: string, code: string): DbError =>
  dbError("forbidden", message, { code });

const invalid = (message: string, code: string): DbError =>
  dbError("invalid_request", message, { code });

function storeError(cause: unknown): DbError {
  const raw = fromPgError(cause);
  return raw ? mapDbError(raw) : toDbError(cause);
}

/** `ServerOptions.support`, from `supportSessions(options)`. */
export interface SupportSessions {
  readonly options: SupportOptions;
  /**
   * Builds `bs.support`; `createServer` calls it once, with the definition's
   * `temporal`, which goes on to the store's `withTemporal`.
   */
  readonly create: (
    events: EventHub,
    claimsSchema: StandardSchemaV1 | undefined,
    temporal?: typeof Temporal,
  ) => SupportApi;
}

/**
 * Support sessions for `createServer(betterSupabase, { support })`. Apps that
 * never import it don't bundle the support code.
 */
export function supportSessions(options: SupportOptions): SupportSessions {
  return {
    options,
    create: (events, claimsSchema, temporal) =>
      createSupport(options, events, claimsSchema, temporal),
  };
}

function createSupport(
  options: SupportOptions,
  events: EventHub,
  claimsSchema: StandardSchemaV1 | undefined,
  temporal: typeof Temporal | undefined,
): SupportApi {
  const store =
    temporal !== undefined && options.store.withTemporal
      ? options.store.withTemporal(temporal)
      : options.store;
  const policy = options.policy ?? {};
  const ttl = policy.ttl ?? 1800;
  const maxTtl = policy.maxTtl ?? 14_400;
  const cookieName = options.cookie?.name;

  const emit = (
    type: "support.started" | "support.ended" | "support.denied",
    data: SupportEventData,
  ): void => {
    emitBlockEvent(events, type, data, {
      actorId: data.adminId,
      ...(data.sessionId
        ? { subject: `support_sessions/${data.sessionId}` }
        : {}),
    });
  };

  const targetClaims = async (
    store: SupportSessionStore,
    targetUserId: string,
  ): Promise<Readonly<Record<string, unknown>>> => {
    if (options.claims) return options.claims(targetUserId);
    if (store.claims) return store.claims(targetUserId);
    return { role: "authenticated" };
  };

  /** Target claims per support session; the session itself is loaded every time, so revoking stays immediate. */
  const claimsCache = boundedTtlCache<
    string,
    Readonly<Record<string, unknown>>
  >({ max: CLAIMS_CACHE_SIZE });
  const cachedTargetClaims = async (
    session: SupportSession,
  ): Promise<Readonly<Record<string, unknown>>> => {
    const cached = claimsCache.get(session.id);
    if (cached) return cached;
    const claims = await targetClaims(store, session.targetUserId);
    claimsCache.set(
      session.id,
      claims,
      Math.min(session.expiresAt.epochMilliseconds, Date.now() + CLAIMS_TTL_MS),
    );
    return claims;
  };

  const checkPolicy = (
    admin: UserAuth,
    request: SupportStartRequest,
    reason: string,
    seconds: number,
  ): DbError | undefined => {
    if (admin.claims["act"] !== undefined)
      return denied(
        "An impersonated session cannot start a support session",
        "SUPPORT_NESTED",
      );
    if (request.targetUserId === admin.user.id)
      return invalid(
        "An admin cannot start a support session as themselves",
        "SUPPORT_SELF",
      );
    if ((policy.requireReason ?? true) && reason === "")
      return invalid("A reason is required", "SUPPORT_REASON_REQUIRED");
    if (!Number.isFinite(seconds) || seconds <= 0 || seconds > maxTtl)
      return invalid(
        `ttl must be between 1 and ${String(maxTtl)} seconds`,
        "SUPPORT_TTL",
      );
    return;
  };

  const authorized = async (input: SupportAuthorizeInput): Promise<boolean> => {
    if (!options.authorize) return true;
    try {
      return await options.authorize(input);
    } catch {
      return false;
    }
  };

  const expire = (): AsyncResult<readonly SupportSession[]> =>
    AsyncResult.from(async () => {
      if (!store.expire) {
        return err(
          dbError(
            "unsupported",
            `The "${store.name}" support session store has no expire()`,
            { code: "SUPPORT_EXPIRE_UNSUPPORTED" },
          ),
        );
      }
      let expired: readonly SupportSession[];
      try {
        expired = await store.expire();
      } catch (cause) {
        return err(storeError(cause));
      }
      for (const session of expired) {
        emit("support.ended", {
          sessionId: session.id,
          adminId: session.adminId,
          targetUserId: session.targetUserId,
          reason: session.reason,
          endedBy: "expired",
          ...(session.tenant === undefined
            ? {}
            : { organizationId: session.tenant }),
        });
      }
      return ok(expired);
    });

  const sessionIdOf = (request: Request): string | undefined => {
    if (options.sessionId) {
      try {
        const id = options.sessionId(request);
        return id === "" ? undefined : id;
      } catch (cause) {
        events.logger.warn("support.sessionId threw", { cause });
        return;
      }
    }
    return supportCookieValue(request.headers.get("cookie"), cookieName);
  };

  const resolve = async (
    id: string,
    auth: AuthState,
  ): Promise<ActiveSupport | undefined> => {
    if (auth.kind !== "user") return;
    // A support session's own token never nests another one.
    if (auth.claims["act"] !== undefined) return;
    if (!id) return;
    let session: SupportSession | undefined;
    let claims: Readonly<Record<string, unknown>>;
    try {
      session = await store.get(id, auth.user.id, auth.claims);
      if (!session || session.expiresAt.epochMilliseconds <= Date.now()) {
        return;
      }
      if (policy.readOnly !== "default" && !session.readOnly) {
        session = { ...session, readOnly: true };
      }
      claims = supportClaims(session, await cachedTargetClaims(session));
    } catch (cause) {
      // The admin keeps their own view; a store outage never widens access.
      events.logger.warn("Could not load the support session", { cause });
      return;
    }
    if (claimsSchema) {
      const checked = await validate(claimsSchema, claims, "claims");
      if (!checked.ok) {
        events.logger.warn(
          "The support target's claims fail the claims schema",
          { sessionId: session.id },
        );
        return;
      }
      if (typeof checked.data === "object" && checked.data !== null) {
        claims = { ...claims, ...checked.data };
      }
    }
    return {
      session,
      admin: {
        id: auth.user.id,
        ...(auth.user.email ? { email: auth.user.email } : {}),
      },
      claims,
    };
  };

  return {
    expire,
    expireRoute: (routeOptions) =>
      cronRoute(
        {
          name: "expire",
          secret: routeOptions.secret,
          problem: routeOptions.problem,
        },
        async (_request, instance) => {
          const result = await expire();
          return result.ok
            ? Response.json({ expired: result.data.length })
            : problemResponse(result.error, {
                instance,
                format: routeOptions.problem,
              });
        },
      ),
    start(admin, request) {
      return AsyncResult.from(async () => {
        if (admin.kind !== "user")
          return err(
            dbError("unauthorized", "Sign in to start a support session"),
          );
        const reason = request.reason?.trim() ?? "";
        const seconds = request.ttl ?? ttl;
        const readOnly =
          policy.readOnly === "default" ? (request.readOnly ?? true) : true;
        const deny = (
          error: DbError,
          denial: NonNullable<SupportEventData["denial"]>,
        ) => {
          emit("support.denied", {
            adminId: admin.user.id,
            targetUserId: request.targetUserId,
            ...(reason ? { reason } : {}),
            denial,
          });
          return err(error);
        };
        const violation = checkPolicy(admin, request, reason, seconds);
        if (violation) return deny(violation, "policy");
        const input: SupportAuthorizeInput = {
          admin,
          targetUserId: request.targetUserId,
          reason,
          readOnly,
          ...(request.tenant === undefined ? {} : { tenant: request.tenant }),
          metadata: request.metadata ?? {},
        };
        if (!(await authorized(input))) {
          return deny(
            denied(
              "Not allowed to start a support session",
              "SUPPORT_FORBIDDEN",
            ),
            "authorize",
          );
        }
        let session: SupportSession;
        try {
          session = await store.start({
            adminId: admin.user.id,
            adminClaims: admin.claims,
            targetUserId: request.targetUserId,
            reason,
            ttlSeconds: seconds,
            readOnly,
            ...(request.tenant === undefined ? {} : { tenant: request.tenant }),
            metadata: request.metadata ?? {},
          });
        } catch (cause) {
          const error = storeError(cause);
          return deny(error, error.code === "42501" ? "permission" : "store");
        }
        emit("support.started", {
          sessionId: session.id,
          adminId: session.adminId,
          targetUserId: session.targetUserId,
          reason: session.reason,
          readOnly: session.readOnly,
          expiresAt: session.expiresAt,
        });
        return ok({ session, cookie: supportCookie(session, options.cookie) });
      });
    },

    stop(admin, sessionId) {
      return AsyncResult.from(async () => {
        const cookie = clearSupportCookie(options.cookie);
        if (admin.kind !== "user")
          return err(
            dbError("unauthorized", "Sign in to stop a support session"),
          );
        try {
          const session = await store.get(
            sessionId,
            admin.user.id,
            admin.claims,
          );
          if (!session) return ok({ ended: false, cookie });
          const ended = await store.end(sessionId, "admin", admin.claims);
          if (ended) {
            emit("support.ended", {
              sessionId,
              adminId: session.adminId,
              targetUserId: session.targetUserId,
              endedBy: "admin",
            });
          }
          return ok({ ended, cookie });
        } catch (cause) {
          return err(storeError(cause));
        }
      });
    },

    revoke(caller, sessionId) {
      return AsyncResult.from(async () => {
        if (caller.kind !== "user")
          return err(
            dbError("unauthorized", "Sign in to revoke a support session"),
          );
        try {
          return ok(await store.end(sessionId, "revoked", caller.claims));
        } catch (cause) {
          return err(storeError(cause));
        }
      });
    },

    async current(request, auth) {
      const id = sessionIdOf(request);
      return id ? resolve(id, auth) : undefined;
    },

    resolve,

    list(caller, filter) {
      return AsyncResult.from(async () => {
        if (caller.kind !== "user")
          return err(
            dbError("unauthorized", "Sign in to list support sessions"),
          );
        try {
          return ok(await store.list(filter, caller.claims));
        } catch (cause) {
          return err(storeError(cause));
        }
      });
    },

    sessionIdOf,
    clearCookie: () => clearSupportCookie(options.cookie),
  };
}
