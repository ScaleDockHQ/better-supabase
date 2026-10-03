import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AuthState } from "../auth/resolve.ts";
import type { EventHub } from "../core/events.ts";

import {
  clearSupportCookie,
  type SupportCookieOptions,
  supportClaims,
  supportCookie,
  supportCookieValue,
  type SupportListFilter,
  type SupportSession,
  type SupportSessionStore,
} from "../auth/support.ts";
import { type DbError, dbError, mapDbError } from "../core/errors.ts";
import { emitKitEvent, type SupportEventData } from "../core/kit-events.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { validate } from "../core/standard.ts";
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

export interface SupportAuthorizeInput {
  readonly admin: UserAuth;
  readonly targetUserId: string;
  readonly reason: string;
  readonly readOnly: boolean;
  readonly tenant?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
}

export interface SupportOptions {
  readonly store: SupportSessionStore;
  /**
   * Whether `admin` may view the app as the target. A throw or rejection
   * counts as a deny. Defaults to allowing, so the store decides: the SQL
   * store checks `is_platform(kits.support-sessions.permissions.start)`.
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
  /** Ends anyone's session. Check the caller's permission first. */
  revoke(sessionId: string): AsyncResult<boolean>;
  /** The running session the request's cookie names for `auth`, if any. */
  current(
    request: Request,
    auth: AuthState,
  ): Promise<ActiveSupport | undefined>;
  list(filter?: SupportListFilter): AsyncResult<readonly SupportSession[]>;
  /** The support session id in a request's cookie. */
  sessionIdOf(request: Request): string | undefined;
  /** `Set-Cookie` that clears the support cookie. */
  clearCookie(): string;
}

const denied = (message: string, code: string): DbError =>
  dbError("forbidden", message, { code });

const invalid = (message: string, code: string): DbError =>
  dbError("invalid_request", message, { code });

function storeError(cause: unknown): DbError {
  const raw = fromPgError(cause);
  return raw ? mapDbError(raw) : toDbError(cause);
}

const NOT_CONFIGURED =
  "Support sessions need createServer(betterSupabase, { support: { store } })";

/** The support API over `options`; every method fails when support is not configured. */
export function createSupport(
  options: SupportOptions | undefined,
  events: EventHub,
  claimsSchema: StandardSchemaV1 | undefined,
): SupportApi {
  const policy = options?.policy ?? {};
  const ttl = policy.ttl ?? 1800;
  const maxTtl = policy.maxTtl ?? 14_400;
  const cookieName = options?.cookie?.name;

  const emit = (
    type: "support.started" | "support.ended" | "support.denied",
    data: SupportEventData,
  ): void => {
    emitKitEvent(events, type, data, {
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
    if (options?.claims) return options.claims(targetUserId);
    if (store.claims) return store.claims(targetUserId);
    return { role: "authenticated" };
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
    if (!options?.authorize) return true;
    try {
      return await options.authorize(input);
    } catch {
      return false;
    }
  };

  return {
    start(admin, request) {
      return AsyncResult.from(async () => {
        if (!options) return err(dbError("unexpected", NOT_CONFIGURED));
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
          session = await options.store.start({
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
        if (!options) return err(dbError("unexpected", NOT_CONFIGURED));
        const cookie = clearSupportCookie(options.cookie);
        if (admin.kind !== "user")
          return err(
            dbError("unauthorized", "Sign in to stop a support session"),
          );
        try {
          const session = await options.store.get(sessionId, admin.user.id);
          if (!session) return ok({ ended: false, cookie });
          const ended = await options.store.end(sessionId, "admin");
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

    revoke(sessionId) {
      return AsyncResult.from(async () => {
        if (!options) return err(dbError("unexpected", NOT_CONFIGURED));
        try {
          return ok(await options.store.end(sessionId, "revoked"));
        } catch (cause) {
          return err(storeError(cause));
        }
      });
    },

    async current(request, auth) {
      if (!options || auth.kind !== "user") return;
      // A support session's own token never nests another one.
      if (auth.claims["act"] !== undefined) return;
      const id = supportCookieValue(request.headers.get("cookie"), cookieName);
      if (!id) return;
      let session: SupportSession | undefined;
      let claims: Readonly<Record<string, unknown>>;
      try {
        session = await options.store.get(id, auth.user.id);
        if (!session || session.expiresAt.epochMilliseconds <= Date.now()) {
          return;
        }
        claims = supportClaims(
          session,
          await targetClaims(options.store, session.targetUserId),
        );
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
    },

    list(filter) {
      return AsyncResult.from(async () => {
        if (!options) return err(dbError("unexpected", NOT_CONFIGURED));
        try {
          return ok(await options.store.list(filter));
        } catch (cause) {
          return err(storeError(cause));
        }
      });
    },

    sessionIdOf: (request) =>
      supportCookieValue(request.headers.get("cookie"), cookieName),
    clearCookie: () => clearSupportCookie(options?.cookie),
  };
}
