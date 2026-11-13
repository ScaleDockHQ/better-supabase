import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  instantOf,
  nullableInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  isRecord,
} from "../shared.ts";

/** Why a support session ended. */
export type SupportSessionEndedBy = "admin" | "expired" | "revoked";

/** A support session as the `impersonation` functions return it. */
export interface ImpersonationSession {
  readonly id: string;
  readonly adminId: string;
  readonly targetUserId: string;
  readonly reason: string;
  readonly readOnly: boolean;
  /** The tenant the session was opened for, when it named one. */
  readonly tenant: string | undefined;
  readonly startedAt: Temporal.Instant;
  readonly expiresAt: Temporal.Instant;
  readonly endedAt: Temporal.Instant | undefined;
  readonly endedBy: SupportSessionEndedBy | undefined;
  readonly metadata: Readonly<Record<string, unknown>>;
}

/** A request for a session that waits for a second admin. */
export interface ImpersonationRequest {
  readonly id: string;
  readonly adminId: string;
  readonly targetUserId: string;
  readonly reason: string;
  readonly readOnly: boolean;
  readonly tenant: string | undefined;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly requestedAt: Temporal.Instant;
  readonly expiresAt: Temporal.Instant;
  readonly approvedBy: string | undefined;
  readonly approvedAt: Temporal.Instant | undefined;
  readonly sessionId: string | undefined;
}

export interface ImpersonationTarget {
  /** The user to view the app as. */
  readonly target: string;
  readonly reason?: string;
  /** Default true; writes need `blocks.impersonation.options.allowWrites`. */
  readonly readOnly?: boolean;
  readonly metadata?: Readonly<Record<string, unknown>>;
  readonly tenant?: string;
}

export interface Impersonation {
  /** Asks for a session that a second admin approves before it can start. */
  request(input: ImpersonationTarget): AsyncResult<ImpersonationRequest>;
  /** Approves a request as a second admin; the requester cannot. */
  approve(requestId: string): AsyncResult<ImpersonationRequest>;
  /** Starts a session, as the admin who is calling. */
  start(
    input: ImpersonationTarget & {
      /** How long the session lasts, in seconds. Default 30 minutes. */
      readonly ttlSeconds?: number;
    },
  ): AsyncResult<ImpersonationSession>;
  /**
   * Ends a session. Its admin ends their own; staff with the revoke permission
   * end anyone's.
   */
  end(sessionId: string): AsyncResult<boolean>;
  /** Sessions, newest first, for staff with the read permission. */
  list(filter?: {
    readonly adminId?: string;
    readonly targetUserId?: string;
    /** `true` for sessions still running, `false` for the ended ones. */
    readonly active?: boolean;
    readonly limit?: number;
  }): AsyncResult<readonly ImpersonationSession[]>;
}

export interface ImpersonationOptions extends Pick<
  BlockOptions,
  "transport" | "schema" | "mappers" | "temporal"
> {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Impersonation>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const DEFAULT_TTL_SECONDS = 30 * 60;

function endedByOf(value: unknown): SupportSessionEndedBy | undefined {
  return value === "admin" || value === "expired" || value === "revoked"
    ? value
    : undefined;
}

function metadataOf(value: unknown): Readonly<Record<string, unknown>> {
  return isRecord(value) ? value : {};
}

function sessionOf(value: unknown, fn: string): ImpersonationSession {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    adminId: textOf(row["admin_id"]),
    targetUserId: textOf(row["target_user_id"]),
    reason: textOf(row["reason"] ?? ""),
    readOnly: row["read_only"] !== false,
    tenant: optionalText(row["tenant"]),
    startedAt: instantOf(row["started_at"]),
    expiresAt: instantOf(row["expires_at"]),
    endedAt: nullableInstant(row["ended_at"]) ?? undefined,
    endedBy: endedByOf(row["ended_by"]),
    metadata: metadataOf(row["metadata"]),
  };
}

function requestOf(value: unknown, fn: string): ImpersonationRequest {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    adminId: textOf(row["admin_id"]),
    targetUserId: textOf(row["target_user_id"]),
    reason: textOf(row["reason"] ?? ""),
    readOnly: row["read_only"] !== false,
    tenant: optionalText(row["tenant"]),
    metadata: metadataOf(row["metadata"]),
    requestedAt: instantOf(row["requested_at"]),
    expiresAt: instantOf(row["expires_at"]),
    approvedBy: optionalText(row["approved_by"]),
    approvedAt: nullableInstant(row["approved_at"]) ?? undefined,
    sessionId: optionalText(row["session_id"]),
  };
}

/**
 * The `impersonation` block's client over `request_support_session`,
 * `approve_support_request`, `start_support_session`, `end_support_session` and
 * `list_support_sessions`. Call it as the signed-in admin (`rpcTransport` over
 * the `api` schema, or `sqlTransport` as the user): the functions check
 * `is_platform()` themselves.
 */
export function createImpersonation(
  options: ImpersonationOptions,
): Impersonation {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: Impersonation = {
    request: (input) =>
      call(
        "request_support_session",
        {
          target: input.target,
          reason: input.reason ?? null,
          read_only: input.readOnly ?? true,
          metadata: input.metadata ?? {},
          tenant: input.tenant ?? null,
        },
        (value) => requestOf(value, "request_support_session"),
      ),

    approve: (requestId) =>
      call("approve_support_request", { request_id: requestId }, (value) =>
        requestOf(value, "approve_support_request"),
      ),

    start: (input) =>
      call(
        "start_support_session",
        {
          target: input.target,
          reason: input.reason ?? null,
          ttl: `${String(input.ttlSeconds ?? DEFAULT_TTL_SECONDS)} seconds`,
          read_only: input.readOnly ?? true,
          metadata: input.metadata ?? {},
          tenant: input.tenant ?? null,
        },
        (value) => sessionOf(value, "start_support_session"),
      ),

    end: (sessionId) =>
      call(
        "end_support_session",
        { session_id: sessionId },
        (value) => value === true,
      ),

    list: (filter = {}) =>
      call(
        "list_support_sessions",
        {
          admin_id: filter.adminId ?? null,
          target: filter.targetUserId ?? null,
          active: filter.active ?? null,
          max_rows: filter.limit ?? 50,
        },
        (value) =>
          recordsOf(value, "list_support_sessions").map((row) =>
            sessionOf(row, "list_support_sessions"),
          ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "impersonation",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
