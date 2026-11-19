import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AuthState } from "../auth/resolve.ts";
import type { SupportCookieOptions } from "../auth/support-cookie.ts";
import type {
  SupportListFilter,
  SupportRequest,
  SupportSession,
  SupportSessionStore,
} from "../auth/support.ts";
import type { ImpersonationEvents } from "../blocks/impersonation/events.ts";
import type { SupportEventData } from "../core/block-events.ts";
import type {
  AuthorizationHooks,
  SupportAuthorize,
  SupportAuthorizeInput,
  SupportDecision,
} from "../core/contracts/authorization-hooks.ts";
import type { DbError } from "../core/errors.ts";
import type { EventHub } from "../core/events.ts";
import type { ProblemFormat } from "../core/problem.ts";
import type { StatsRecorder } from "../core/stats.ts";

import {
  clearSupportCookie,
  supportCookie,
  supportCookieValue,
} from "../auth/support-cookie.ts";
import {
  SUPPORT_SESSION_ID,
  SUPPORT_UNAVAILABLE_DIGEST,
} from "../auth/support-view.ts";
import { supportClaims } from "../auth/support.ts";
import { emitBlockEvent } from "../core/block-events.ts";
import { cronRoute } from "../core/cron-route.ts";
import { dbError, mapDbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { boundedTtlCache } from "../core/ttl-cache.ts";
import { fromPgError } from "../postgres/pg-error.ts";

type UserAuth = Extract<AuthState, { kind: "user" }>;

/**
 * Who calls a support method: the `AuthState` of the request, or the verified
 * `token` and `claims` an app already holds. The library builds the `AuthState`
 * from the second form.
 */
export type SupportCaller =
  | AuthState
  | {
      readonly token: string;
      readonly claims: Readonly<Record<string, unknown>>;
    };

function toAuthState(caller: SupportCaller): AuthState {
  if ("kind" in caller) {
    return caller;
  }

  const { claims } = caller;

  const text = (key: string): string | undefined =>
    typeof claims[key] === "string" ? claims[key] : undefined;

  const email = text("email");
  const exp = claims["exp"];

  return {
    kind: "user",
    token: caller.token,
    // SAFETY: the caller passes claims it verified; they are a JWT payload.
    claims: claims as UserAuth["claims"],
    user: {
      id: text("sub") ?? "",
      role: text("role") ?? "authenticated",
      ...(email === undefined ? {} : { email }),
    },
    source: "bearer",
    expiresAt: typeof exp === "number" ? exp : null,
  };
}

/**
 * The `kind` an `approverOf` hook sees for a support request; the SQL
 * `isApprover` sees the same.
 */
const SUPPORT_SESSION_APPROVAL = "support-session";

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
  /**
   * `distinct` (the default): a start needs a request that another admin
   * approved (`support.request`, then `support.approve`), or an `authorize`
   * decision of `{ approvedBy }` naming someone else. `none`: no second admin.
   * Set `blocks.impersonation.options.approval` to the same value, because the
   * SQL store checks it again.
   */
  readonly approval?: "distinct" | "none";
}

export type { SupportAuthorizeInput };

export interface SupportOptions {
  readonly store: SupportSessionStore;
  /**
   * Whether `admin` may view the app as the target. Without it, the
   * authorization hooks' `support.authorize` decides, and without those every
   * start is refused (`IMPERSONATION_FORBIDDEN`). A throw or rejection counts
   * as a deny. `true` still needs a second admin under `policy.approval:
   * 'distinct'`; `{ approvedBy }` names that admin.
   *
   * `'store'` hands the decision to the store alone: the SQL store checks
   * `is_platform(blocks['impersonation'].permissions.start)` and nothing else,
   * so use it only when that permission is the whole rule.
   */
  readonly authorize?: SupportAuthorize | "store";
  /**
   * The claims the target gets. Defaults to `store.claims` (the SQL store runs
   * your custom access token hook), then `{ role: 'authenticated' }`.
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
   * header or their own request store instead of the `bsb-support` cookie.
   * Defaults to reading the cookie.
   */
  readonly sessionId?: (request: Request) => string | undefined;
  /**
   * What `resolve` and `current` do when the session or the target's claims
   * can't be loaded (a store outage). `'admin'`, the default, answers
   * `undefined`, so the request runs as the admin. `'throw'` throws
   * `SupportUnavailableError`, so an app can fail closed instead of showing the
   * admin's own view while the cookie still names a session.
   */
  readonly unavailable?: "admin" | "throw";
}

/** A support session could not be loaded; see `SupportOptions.unavailable`. */
export class SupportUnavailableError extends Error {
  override readonly name = "SupportUnavailableError";
  readonly digest: typeof SUPPORT_UNAVAILABLE_DIGEST =
    SUPPORT_UNAVAILABLE_DIGEST;
  readonly sessionId: string;

  constructor(sessionId: string, options?: { readonly cause?: unknown }) {
    super("The support session could not be loaded", options);
    this.sessionId = sessionId;
  }
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

/** `bsb.support`: start, stop and inspect support sessions. */
export interface SupportApi {
  /**
   * Starts a session for a signed-in admin and returns it with the `Set-Cookie`
   * value that switches the admin's next requests to the target.
   */
  start(
    admin: SupportCaller,
    request: SupportStartRequest,
  ): AsyncResult<{ readonly session: SupportSession; readonly cookie: string }>;
  /**
   * Asks for a session that a second admin approves with `approve`; the policy
   * checks of `start` apply. `ttl` is not stored: `start` passes it.
   */
  request(
    admin: SupportCaller,
    request: SupportStartRequest,
  ): AsyncResult<SupportRequest>;
  /**
   * Approves a request as `approver`, who is never the admin who asked. With
   * the hooks' `approverOf`, it decides who may approve; otherwise the store
   * does (the SQL store: the provider's `isApprover`, else the start
   * permission).
   */
  approve(
    approver: SupportCaller,
    requestId: string,
  ): AsyncResult<SupportRequest>;
  /**
   * Ends the admin's own session and returns the `Set-Cookie` that clears the
   * cookie.
   */
  stop(
    admin: SupportCaller,
    sessionId: string,
  ): AsyncResult<{ readonly ended: boolean; readonly cookie: string }>;
  /**
   * Ends a session as `caller`: the SQL store allows the session's admin and
   * staff with the revoke permission.
   */
  revoke(caller: SupportCaller, sessionId: string): AsyncResult<boolean>;
  /** The running session the request names (`sessionIdOf`) for `auth`, if any. */
  current(
    request: Request,
    auth: SupportCaller,
    stats?: StatsRecorder,
  ): Promise<ActiveSupport | undefined>;
  /**
   * The running session `sessionId` for the admin in `auth`, if any. Use it
   * when the app keeps the session id in its own request context; pass the
   * result to `contextFor(auth, { support })` or `dbFor(auth, context, {
   * support })`.
   */
  resolve(
    sessionId: string,
    auth: SupportCaller,
    stats?: StatsRecorder,
  ): Promise<ActiveSupport | undefined>;
  /** The sessions `caller` may view (the SQL store checks the view permission). */
  list(
    caller: SupportCaller,
    filter?: SupportListFilter,
  ): AsyncResult<readonly SupportSession[]>;
  /**
   * Ends every session past its expiry through the store and emits
   * `support_session.ended` with `endedBy: "expired"` for each; the SQL store
   * runs over `postgres.admin`. Returns the sessions it ended.
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

/**
 * How long a support target's claims are reused; a role change applies within
 * it.
 */
const CLAIMS_TTL_MS = 60_000;

/**
 * How long one session lookup serves the lookups that follow it: a render that
 * builds many contexts loads the session once, and a revoke on another instance
 * applies within it.
 */
const SESSION_REUSE_MS = 1000;

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
   * Builds `bsb.support`; `createServer` calls it once, with the definition's
   * `temporal`, which goes on to the store's `withTemporal`, and the server's
   * authorization hooks.
   */
  readonly create: (
    events: EventHub,
    claimsSchema: StandardSchemaV1 | undefined,
    temporal?: typeof Temporal,
    authorization?: AuthorizationHooks,
  ) => SupportApi;
}

/**
 * Support sessions for `createServer(betterSupabase, { support })`. Apps that
 * never import it don't bundle the support code.
 */
export function supportSessions(options: SupportOptions): SupportSessions {
  return {
    options,
    create: (events, claimsSchema, temporal, authorization) =>
      createSupport(options, events, claimsSchema, temporal, authorization),
  };
}

const forbidden = (): DbError =>
  denied("Not allowed to start a support session", "IMPERSONATION_FORBIDDEN");

const selfApproval = (): DbError =>
  denied(
    "An admin cannot approve their own support session",
    "IMPERSONATION_SELF_APPROVAL",
  );

function createSupport(
  options: SupportOptions,
  events: EventHub,
  claimsSchema: StandardSchemaV1 | undefined,
  temporal: typeof Temporal | undefined,
  authorization: AuthorizationHooks | undefined,
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
    type:
      | "support_session.started"
      | "support_session.ended"
      | "support_session.denied",
    data: SupportEventData,
  ): void => {
    emitBlockEvent<ImpersonationEvents>(events, type, data, {
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
    if (options.claims) {
      return options.claims(targetUserId);
    }

    if (store.claims) {
      return store.claims(targetUserId);
    }

    return { role: "authenticated" };
  };

  /**
   * Target claims per support session. The session itself is reused for at most
   * `SESSION_REUSE_MS`, and a stop or revoke on this instance drops it at
   * once.
   */
  const claimsCache = boundedTtlCache<
    string,
    Promise<Readonly<Record<string, unknown>>>
  >({ max: CLAIMS_CACHE_SIZE });

  const cachedTargetClaims = async (
    session: SupportSession,
  ): Promise<Readonly<Record<string, unknown>>> => {
    const cached = claimsCache.get(session.id);

    if (cached) {
      return cached;
    }

    const claims = targetClaims(store, session.targetUserId);
    claimsCache.set(
      session.id,
      claims,
      Math.min(session.expiresAt.epochMilliseconds, Date.now() + CLAIMS_TTL_MS),
    );
    claims.catch(() => {
      if (claimsCache.get(session.id) === claims) {
        claimsCache.delete(session.id);
      }
    });

    return claims;
  };

  const sessionLookups = boundedTtlCache<
    string,
    {
      readonly adminId: string;
      readonly token: string;
      readonly session: Promise<SupportSession | undefined>;
    }
  >({ max: CLAIMS_CACHE_SIZE });

  const loadSession = (
    id: string,
    auth: UserAuth,
    stats?: StatsRecorder,
  ): Promise<SupportSession | undefined> => {
    const reused = sessionLookups.get(id);

    if (reused?.adminId === auth.user.id && reused.token === auth.token) {
      return reused.session;
    }

    const end = stats?.begin("support_sessions");

    const session = (async () => {
      try {
        return await store.get(id, auth.user.id, auth.claims);
      } finally {
        end?.();
      }
    })();

    const entry = { adminId: auth.user.id, token: auth.token, session };

    sessionLookups.set(id, entry, Date.now() + SESSION_REUSE_MS);
    session.catch(() => {
      if (sessionLookups.get(id) === entry) {
        sessionLookups.delete(id);
      }
    });

    return session;
  };

  const checkPolicy = (
    admin: UserAuth,
    request: SupportStartRequest,
    reason: string,
    seconds: number,
  ): DbError | undefined => {
    if (admin.claims["act"] !== undefined) {
      return denied(
        "An impersonated session cannot start a support session",
        "SUPPORT_NESTED",
      );
    }

    if (request.targetUserId === admin.user.id) {
      return invalid(
        "An admin cannot start a support session as themselves",
        "IMPERSONATION_SELF",
      );
    }

    if ((policy.requireReason ?? true) && reason === "") {
      return invalid("A reason is required", "IMPERSONATION_REASON_REQUIRED");
    }

    if (!Number.isFinite(seconds) || seconds <= 0 || seconds > maxTtl) {
      return invalid(
        `ttl must be between 1 and ${String(maxTtl)} seconds`,
        "IMPERSONATION_TTL",
      );
    }

    return;
  };

  const approval = policy.approval ?? "distinct";
  const authorize = options.authorize ?? authorization?.support?.authorize;

  /** The decision for a start; a missing hook and a throw refuse it. */
  const decide = async (
    input: SupportAuthorizeInput,
  ): Promise<SupportDecision> => {
    if (authorize === undefined) {
      return false;
    }

    if (authorize === "store") {
      return true;
    }

    try {
      return await authorize(input);
    } catch {
      return false;
    }
  };

  const mayApprove = async (
    approver: UserAuth,
    request: SupportRequest,
  ): Promise<boolean> => {
    const approverOf = authorization?.approverOf;

    if (approverOf === undefined) {
      return true;
    }

    try {
      return await approverOf(
        { userId: approver.user.id, claims: approver.claims },
        {
          kind: SUPPORT_SESSION_APPROVAL,
          subject: request.id,
          requester: request.adminId,
          ...(request.tenant === undefined ? {} : { tenant: request.tenant }),
        },
      );
    } catch {
      return false;
    }
  };

  /**
   * The approved request a start uses: recorded now for an `{ approvedBy }`
   * decision, else looked up.
   */
  const approvedRequest = async (
    admin: UserAuth,
    request: SupportStartRequest,
    reason: string,
    readOnly: boolean,
    approvedBy: string | undefined,
  ): Promise<SupportRequest | undefined> => {
    const tenant =
      request.tenant === undefined ? {} : { tenant: request.tenant };

    if (approvedBy !== undefined) {
      return store.request?.({
        adminId: admin.user.id,
        adminClaims: admin.claims,
        targetUserId: request.targetUserId,
        reason,
        readOnly,
        ...tenant,
        metadata: request.metadata ?? {},
        approvedBy,
      });
    }

    return store.approvedRequest?.({
      adminId: admin.user.id,
      targetUserId: request.targetUserId,
      readOnly,
      ...tenant,
    });
  };

  const noApprovals = (): DbError =>
    dbError(
      "unsupported",
      `The "${store.name}" support session store does not record approvals; set policy.approval to "none" or use a store that does`,
      { code: "SUPPORT_APPROVAL_UNSUPPORTED" },
    );

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
        emit("support_session.ended", {
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
    raw: string,
    auth: AuthState,
    stats?: StatsRecorder,
  ): Promise<ActiveSupport | undefined> => {
    if (auth.kind !== "user") {
      return;
    }

    // A support session's own token never nests another one.
    if (auth.claims["act"] !== undefined) {
      return;
    }

    // A malformed id (a junk cookie) names no session, so no store outage either.
    if (!SUPPORT_SESSION_ID.test(raw)) {
      return;
    }

    const id = raw.toLowerCase();

    let session: SupportSession | undefined;
    let claims: Readonly<Record<string, unknown>>;

    try {
      session = await loadSession(id, auth, stats);

      if (!session || session.expiresAt.epochMilliseconds <= Date.now()) {
        return;
      }

      if (policy.readOnly !== "default" && !session.readOnly) {
        session = { ...session, readOnly: true };
      }

      claims = supportClaims(session, await cachedTargetClaims(session));
    } catch (cause) {
      events.logger.warn("Could not load the support session", { cause });

      if (options.unavailable === "throw") {
        throw new SupportUnavailableError(id, { cause });
      }

      // The admin keeps their own view; a store outage never widens access.
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
    start(adminCaller, request) {
      return AsyncResult.from(async () => {
        const admin = toAuthState(adminCaller);

        if (admin.kind !== "user") {
          return err(
            dbError("unauthorized", "Sign in to start a support session"),
          );
        }

        const reason = request.reason?.trim() ?? "";
        const seconds = request.ttl ?? ttl;

        const readOnly =
          policy.readOnly === "default" ? (request.readOnly ?? true) : true;

        const deny = (
          error: DbError,
          denial: NonNullable<SupportEventData["denial"]>,
        ) => {
          emit("support_session.denied", {
            adminId: admin.user.id,
            targetUserId: request.targetUserId,
            ...(reason ? { reason } : {}),
            denial,
          });

          return err(error);
        };

        const violation = checkPolicy(admin, request, reason, seconds);

        if (violation) {
          return deny(violation, "policy");
        }

        const tenant =
          request.tenant === undefined ? {} : { tenant: request.tenant };

        const input: SupportAuthorizeInput = {
          admin,
          targetUserId: request.targetUserId,
          reason,
          readOnly,
          ...tenant,
          metadata: request.metadata ?? {},
        };

        const decision = await decide(input);

        if (decision === false) {
          return deny(forbidden(), "authorize");
        }

        const approvedBy =
          typeof decision === "object" ? decision.approvedBy : undefined;

        if (approvedBy === admin.user.id) {
          return deny(selfApproval(), "authorize");
        }

        let requestId: string | undefined;

        if (approval === "distinct") {
          let approved: SupportRequest | undefined;

          try {
            approved = await approvedRequest(
              admin,
              request,
              reason,
              readOnly,
              approvedBy,
            );
          } catch (cause) {
            const error = storeError(cause);

            return deny(error, error.code === "42501" ? "permission" : "store");
          }

          if (approved === undefined || approved.approvedBy === admin.user.id) {
            return deny(
              denied(
                "A second admin must approve this support session",
                "IMPERSONATION_APPROVAL_REQUIRED",
              ),
              "policy",
            );
          }

          requestId = approved.id;
        }

        let session: SupportSession;

        try {
          sessionLookups.clear();
          session = await store.start({
            adminId: admin.user.id,
            adminClaims: admin.claims,
            targetUserId: request.targetUserId,
            reason,
            ttlSeconds: seconds,
            readOnly,
            ...tenant,
            metadata: request.metadata ?? {},
            ...(requestId === undefined ? {} : { requestId }),
          });
        } catch (cause) {
          const error = storeError(cause);

          return deny(error, error.code === "42501" ? "permission" : "store");
        }

        // The cookie and every lookup take a UUID; another id would never resolve.
        if (!SUPPORT_SESSION_ID.test(session.id)) {
          return deny(
            dbError(
              "unexpected",
              `The support store "${store.name}" returned a session id that is not a UUID`,
              { code: "SUPPORT_SESSION_ID" },
            ),
            "store",
          );
        }

        emit("support_session.started", {
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

    request(adminCaller, request) {
      return AsyncResult.from(async () => {
        const admin = toAuthState(adminCaller);

        if (admin.kind !== "user") {
          return err(
            dbError("unauthorized", "Sign in to ask for a support session"),
          );
        }

        const reason = request.reason?.trim() ?? "";

        const violation = checkPolicy(
          admin,
          request,
          reason,
          request.ttl ?? ttl,
        );

        if (violation) {
          return err(violation);
        }

        if (!store.request) {
          return err(noApprovals());
        }

        try {
          return ok(
            await store.request({
              adminId: admin.user.id,
              adminClaims: admin.claims,
              targetUserId: request.targetUserId,
              reason,
              readOnly:
                policy.readOnly === "default"
                  ? (request.readOnly ?? true)
                  : true,
              ...(request.tenant === undefined
                ? {}
                : { tenant: request.tenant }),
              metadata: request.metadata ?? {},
            }),
          );
        } catch (cause) {
          return err(storeError(cause));
        }
      });
    },

    approve(approverCaller, requestId) {
      return AsyncResult.from(async () => {
        const approver = toAuthState(approverCaller);

        if (approver.kind !== "user") {
          return err(
            dbError("unauthorized", "Sign in to approve a support session"),
          );
        }

        if (approver.claims["act"] !== undefined) {
          return err(
            denied(
              "An impersonated session cannot approve a support session",
              "SUPPORT_NESTED",
            ),
          );
        }

        if (!store.approve || !store.getRequest) {
          return err(noApprovals());
        }

        try {
          const found = await store.getRequest(requestId);

          if (!found) {
            return err(
              dbError("not_found", "No such support request", {
                code: "IMPERSONATION_REQUEST_MISSING",
              }),
            );
          }

          if (found.adminId === approver.user.id) {
            return err(selfApproval());
          }

          if (authorization?.approverOf === undefined) {
            return ok(
              await store.approve(requestId, {
                id: approver.user.id,
                claims: approver.claims,
              }),
            );
          }

          if (!(await mayApprove(approver, found))) {
            return err(
              denied(
                "Not allowed to approve this support session",
                "IMPERSONATION_FORBIDDEN",
              ),
            );
          }

          return ok(await store.approve(requestId, { id: approver.user.id }));
        } catch (cause) {
          return err(storeError(cause));
        }
      });
    },

    stop(adminCaller, sessionId) {
      return AsyncResult.from(async () => {
        const admin = toAuthState(adminCaller);
        const cookie = clearSupportCookie(options.cookie);

        if (admin.kind !== "user") {
          return err(
            dbError("unauthorized", "Sign in to stop a support session"),
          );
        }

        if (!SUPPORT_SESSION_ID.test(sessionId)) {
          return ok({ ended: false, cookie });
        }

        const id = sessionId.toLowerCase();

        try {
          const session = await store.get(id, admin.user.id, admin.claims);

          if (!session) {
            return ok({ ended: false, cookie });
          }

          sessionLookups.delete(id);

          const ended = await store
            .end(id, "admin", admin.claims)
            .finally(() => {
              sessionLookups.delete(id);
            });

          if (ended) {
            emit("support_session.ended", {
              sessionId: id,
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

    revoke(callerCaller, sessionId) {
      return AsyncResult.from(async () => {
        const caller = toAuthState(callerCaller);

        if (caller.kind !== "user") {
          return err(
            dbError("unauthorized", "Sign in to revoke a support session"),
          );
        }

        if (!SUPPORT_SESSION_ID.test(sessionId)) {
          return ok(false);
        }

        const id = sessionId.toLowerCase();

        try {
          sessionLookups.delete(id);

          return ok(
            await store.end(id, "revoked", caller.claims).finally(() => {
              sessionLookups.delete(id);
            }),
          );
        } catch (cause) {
          return err(storeError(cause));
        }
      });
    },

    async current(request, auth, stats) {
      const id = sessionIdOf(request);

      return id ? resolve(id, toAuthState(auth), stats) : undefined;
    },

    resolve: (id, auth, stats) => resolve(id, toAuthState(auth), stats),

    list(callerCaller, filter) {
      return AsyncResult.from(async () => {
        const caller = toAuthState(callerCaller);

        if (caller.kind !== "user") {
          return err(
            dbError("unauthorized", "Sign in to list support sessions"),
          );
        }

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
