import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  allWithFields,
  type BlockFields,
  blockFields,
  extraFieldsArg,
  type FieldsOf,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
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

export interface AccessRequestsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the request columns the app adds
   * (`blocks.access-requests.options.extraColumns`), keyed by column name. It
   * types and parses them on every read, and validates them on `request`, which
   * returns a `validation` error for a bad value.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<AccessRequests<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * `pending`, `rejected`, `cancelled` and `expired` follow the approval request;
 * `granted` and `ended` follow the role itself.
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

/** `F` is the extra fields `options.fields` describes. */
export interface AccessRequests<F extends object = Record<never, never>> {
  /**
   * Asks for a role; the approvals module routes it to the approvers. Keys
   * besides the input's own are the request's extra columns.
   */
  request(
    input: AccessRequestInput & Partial<F>,
  ): AsyncResult<AccessRequest & F>;
  /** Ends a granted role early: a manager, or the holder giving it up. */
  end(id: string): AsyncResult<AccessRequest & F>;
  get(id: string): AsyncResult<AccessRequest & F>;
  /** Newest first. */
  list(
    organizationId: string,
    options?: AccessRequestListOptions,
  ): AsyncResult<readonly (AccessRequest & F)[]>;
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
export function createAccessRequests<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AccessRequestsOptions<S>): AccessRequests<FieldsOf<S>> {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<FieldsOf<S>> = blockFields(
    options.fields,
    "access request fields",
  );

  const one = (fn: string, args: Readonly<Record<string, unknown>>) =>
    call(fn, args, (value) => [value, requestOf(value, fn)] as const).andThen(
      ([raw, row]) => withFields(fields, raw, row),
    );

  const client: AccessRequests<FieldsOf<S>> = {
    request: ({ organizationId, role, reason, duration, ...extra }) =>
      AsyncResult.from(() => extraFieldsArg(fields, extra)).andThen((more) =>
        one("request_access", {
          tenant: organizationId,
          role,
          reason: reason ?? null,
          duration: duration?.toString() ?? null,
          ...more,
        }),
      ),
    end: (id) => one("end_access", { request_id: id }),
    get: (id) => one("get_access_request", { request_id: id }),
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
          recordsOf(value, "list_access_requests").map(
            (raw) => [raw, requestOf(raw, "list_access_requests")] as const,
          ),
      ).andThen((rows) => allWithFields(fields, rows)),
  };

  return withBlockHooks(client, options.hooks, {
    block: "access-requests",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
