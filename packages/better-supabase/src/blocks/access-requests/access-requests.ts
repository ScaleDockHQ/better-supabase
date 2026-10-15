import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface AccessRequestsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `blocks.access-requests.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<AccessRequests>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * `pending`, `rejected`, `cancelled` and `expired` follow the approval
 * request; `granted` and `ended` follow the role itself.
 */
export type AccessRequestStatus =
  | "pending"
  | "granted"
  | "rejected"
  | "cancelled"
  | "expired"
  | "ended";

export interface AccessRequest {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly role: string;
  /** The role the member held before the grant; unset for a new member. */
  readonly previousRole?: string;
  readonly reason?: string;
  readonly duration?: Temporal.Duration;
  readonly status: AccessRequestStatus;
  /** The approvals request; approve, reject or cancel it there. */
  readonly approvalId?: string;
  readonly grantedAt?: Temporal.Instant;
  /** When the grant ends; unset for a grant without a duration. */
  readonly expiresAt?: Temporal.Instant;
  readonly endedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface AccessRequestInput {
  readonly organizationId: string;
  readonly role: string;
  readonly reason?: string;
  /** How long the role lasts. Default: `options.maxDuration`, else no end. */
  readonly duration?: Temporal.Duration;
}

export interface AccessRequestListOptions {
  /** Default: every status. */
  readonly status?: AccessRequestStatus;
  /** Only the caller's requests, even for readers of the organization. */
  readonly mine?: boolean;
  readonly pageSize?: number;
  /** Requests made before this time, for the next page. */
  readonly before?: Temporal.Instant;
}

export interface AccessRequests {
  /** Asks for a role; the approvals module routes it to the approvers. */
  request(input: AccessRequestInput): AsyncResult<AccessRequest>;
  /** Ends a granted role early: a manager, or the holder giving it up. */
  end(id: string): AsyncResult<AccessRequest>;
  get(id: string): AsyncResult<AccessRequest>;
  /** Newest first. */
  list(
    organizationId: string,
    options?: AccessRequestListOptions,
  ): AsyncResult<readonly AccessRequest[]>;
}

const STATUSES: readonly AccessRequestStatus[] = [
  "pending",
  "granted",
  "rejected",
  "cancelled",
  "expired",
  "ended",
];

function statusOf(value: unknown): AccessRequestStatus {
  const status = STATUSES.find((item) => item === value);
  if (status === undefined) {
    throw new TypeError(`unknown access request status ${String(value)}`);
  }
  return status;
}

const instant = (
  value: unknown,
  name: string,
): { readonly [key: string]: Temporal.Instant } =>
  value === null || value === undefined
    ? {}
    : { [name]: requiredInstant(value, name) };

function durationOf(value: unknown): { readonly duration?: Temporal.Duration } {
  const text = optionalText(value);
  return text === undefined ? {} : { duration: temporal().Duration.from(text) };
}

function requestOf(value: unknown, fn: string): AccessRequest {
  const row = recordOf(value, fn);
  const previousRole = optionalText(row["previousRole"]);
  const reason = optionalText(row["reason"]);
  const approvalId = optionalText(row["approvalId"]);
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    userId: textOf(row["userId"]),
    role: textOf(row["role"]),
    status: statusOf(row["status"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(previousRole === undefined ? {} : { previousRole }),
    ...(reason === undefined ? {} : { reason }),
    ...(approvalId === undefined ? {} : { approvalId }),
    ...durationOf(row["duration"]),
    ...instant(row["grantedAt"], "grantedAt"),
    ...instant(row["expiresAt"], "expiresAt"),
    ...instant(row["endedAt"], "endedAt"),
  };
}

/** The `access-requests` SQL module as typed calls. */
export function createAccessRequests(
  options: AccessRequestsOptions,
): AccessRequests {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: AccessRequests = {
    request: (input) =>
      call(
        "request_access",
        {
          tenant: input.organizationId,
          role: input.role,
          reason: input.reason ?? null,
          duration: input.duration?.toString() ?? null,
        },
        (value) => requestOf(value, "request_access"),
      ),
    end: (id) =>
      call("end_access", { request_id: id }, (value) =>
        requestOf(value, "end_access"),
      ),
    get: (id) =>
      call("get_access_request", { request_id: id }, (value) =>
        requestOf(value, "get_access_request"),
      ),
    list: (organizationId, list = {}) =>
      call(
        "list_access_requests",
        {
          tenant: organizationId,
          status: list.status ?? null,
          mine: list.mine ?? false,
          page_size: list.pageSize ?? null,
          before: list.before?.toString() ?? null,
        },
        (value) =>
          recordsOf(value, "list_access_requests").map((row) =>
            requestOf(row, "list_access_requests"),
          ),
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "access-requests",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
