import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import {
  allWithFields,
  blockFields,
  extraFieldsArg,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
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

interface AccessRequestBase {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string;
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

/** A request for a role in the organization. */
export interface RoleAccessRequest extends AccessRequestBase {
  readonly target: "role";
  readonly role: string;
  /** The role the member held before the grant; unset for a new member. */
  readonly previousRole?: string;
}

/** What a reviewer decided about an emergency access. */
export interface EmergencyReview {
  readonly verdict: "justified" | "unjustified";
  readonly note?: string;
  readonly reviewedBy: string;
  readonly reviewedAt: Temporal.Instant;
}

/** A request for access to one record, or an emergency access to it. */
export interface RecordAccessRequest extends AccessRequestBase {
  readonly target: "record";
  /** A `config.subjects` type with a record team, such as `client`. */
  readonly subjectType: string;
  readonly subjectId: string;
  /** The action asked for, such as `read`; emergency access is `read`. */
  readonly action: string;
  /** Opened with `openEmergency`, so granted at once and reviewed later. */
  readonly emergency: boolean;
  /** Set once a reviewer has looked at an emergency access. */
  readonly review?: EmergencyReview;
}

/** A role request or a record request; `target` tells them apart. */
export type AccessRequest = RoleAccessRequest | RecordAccessRequest;

export interface AccessRequestInput {
  readonly organizationId: string;
  readonly role: string;
  readonly reason?: string;
  /** How long the role lasts. Default: `options.maxDuration`, else no end. */
  readonly duration?: Temporal.Duration;
}

export interface RecordAccessInput {
  /** A `config.subjects` type with `team`, such as `client`. */
  readonly subjectType: string;
  readonly subjectId: string;
  /** One of the type's `team.actions`. Default: `read`. */
  readonly action?: string;
  readonly reason?: string;
  /**
   * How long the access lasts, at most `options.maxDuration`. Default: 7 days,
   * or `options.maxDuration` when that is shorter.
   */
  readonly duration?: Temporal.Duration;
}

export interface EmergencyAccessInput {
  readonly subjectType: string;
  readonly subjectId: string;
  /** Why the access can't wait for an approval; at least 10 characters. */
  readonly reason: string;
}

export interface EmergencyReviewInput {
  readonly verdict: "justified" | "unjustified";
  readonly note?: string;
}

export interface EmergencyListOptions {
  /** Only the accesses nobody reviewed yet. Default: `true`. */
  readonly unreviewed?: boolean;
  readonly pageSize?: number;
  /** Accesses opened before this time, for the next page. */
  readonly before?: Temporal.Instant;
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
  ): AsyncResult<RoleAccessRequest & F>;
  /**
   * Asks for access to one record. The record's team leads approve it, or the
   * holders of `subjects.manage` when it has no lead; the approval puts the
   * caller on the record's team until the duration ends.
   */
  requestRecord(input: RecordAccessInput): AsyncResult<RecordAccessRequest & F>;
  /**
   * Opens read access to one record at once, for `options.emergency.maxHours`.
   * Needs `access_requests.emergency`; team leads and reviewers are notified.
   */
  openEmergency(
    input: EmergencyAccessInput,
  ): AsyncResult<RecordAccessRequest & F>;
  /** Records a verdict on an emergency access. Needs `access_requests.review`. */
  reviewEmergency(
    id: string,
    input: EmergencyReviewInput,
  ): AsyncResult<RecordAccessRequest & F>;
  /** Emergency accesses in an organization, newest first. */
  emergencies(
    organizationId: string,
    options?: EmergencyListOptions,
  ): AsyncResult<readonly (RecordAccessRequest & F)[]>;
  /** Ends granted access early: a manager, or the holder giving it up. */
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

function reviewOf(value: unknown): { readonly review?: EmergencyReview } {
  if (value === null || value === undefined) {
    return {};
  }

  const row = recordOf(value, "review");
  const verdict = row["verdict"];
  const note = optionalText(row["note"]);

  if (verdict !== "justified" && verdict !== "unjustified") {
    throw new TypeError(`unknown emergency verdict ${String(verdict)}`);
  }

  return {
    review: {
      verdict,
      ...(note === undefined ? {} : { note }),
      reviewedBy: textOf(row["reviewedBy"]),
      reviewedAt: requiredInstant(row["reviewedAt"], "reviewedAt"),
    },
  };
}

function targetOf(
  row: Readonly<Record<string, unknown>>,
):
  | Pick<RoleAccessRequest, "target" | "role" | "previousRole">
  | Pick<
      RecordAccessRequest,
      "target" | "subjectType" | "subjectId" | "action" | "emergency" | "review"
    > {
  if (row["target"] === "record") {
    return {
      target: "record",
      subjectType: textOf(row["subjectType"]),
      subjectId: textOf(row["subjectId"]),
      action: textOf(row["action"]),
      emergency: row["emergency"] === true,
      ...reviewOf(row["review"]),
    };
  }

  const previousRole = optionalText(row["previousRole"]);

  return {
    target: "role",
    role: textOf(row["role"]),
    ...(previousRole === undefined ? {} : { previousRole }),
  };
}

function requestOf(value: unknown, fn: string): AccessRequest {
  const row = recordOf(value, fn);
  const reason = optionalText(row["reason"]);
  const approvalId = optionalText(row["approvalId"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    userId: textOf(row["userId"]),
    ...targetOf(row),
    status: statusOf(row["status"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(reason === undefined ? {} : { reason }),
    ...(approvalId === undefined ? {} : { approvalId }),
    ...durationOf(row["duration"]),
    ...instant(row["grantedAt"], "grantedAt"),
    ...instant(row["expiresAt"], "expiresAt"),
    ...instant(row["endedAt"], "endedAt"),
  };
}

function roleRequestOf(value: unknown, fn: string): RoleAccessRequest {
  const request = requestOf(value, fn);

  if (request.target !== "role") {
    throw new TypeError(`${fn} returned a record request`);
  }

  return request;
}

function recordRequestOf(value: unknown, fn: string): RecordAccessRequest {
  const request = requestOf(value, fn);

  if (request.target !== "record") {
    throw new TypeError(`${fn} returned a role request`);
  }

  return request;
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

  const oneRecord = (fn: string, args: Readonly<Record<string, unknown>>) =>
    call(
      fn,
      args,
      (value) => [value, recordRequestOf(value, fn)] as const,
    ).andThen(([raw, row]) => withFields(fields, raw, row));

  const client: AccessRequests<FieldsOf<S>> = {
    request: ({ organizationId, role, reason, duration, ...extra }) =>
      AsyncResult.from(() => extraFieldsArg(fields, extra)).andThen((more) =>
        call(
          "request_access",
          {
            tenant: organizationId,
            role,
            reason: reason ?? null,
            duration: duration?.toString() ?? null,
            ...more,
          },
          (value) => [value, roleRequestOf(value, "request_access")] as const,
        ).andThen(([raw, row]) => withFields(fields, raw, row)),
      ),
    requestRecord: ({ subjectType, subjectId, action, reason, duration }) =>
      oneRecord("request_record_access", {
        subject_type: subjectType,
        subject_id: subjectId,
        action: action ?? "read",
        reason: reason ?? null,
        duration: duration?.toString() ?? null,
      }),
    openEmergency: ({ subjectType, subjectId, reason }) =>
      oneRecord("open_emergency_access", {
        subject_type: subjectType,
        subject_id: subjectId,
        reason,
      }),
    reviewEmergency: (id, { verdict, note }) =>
      oneRecord("review_emergency_access", {
        request_id: id,
        verdict,
        note: note ?? null,
      }),
    emergencies: (organizationId, list = {}) =>
      call(
        "list_emergency_access",
        {
          tenant: organizationId,
          unreviewed: list.unreviewed ?? true,
          page_size: list.pageSize ?? null,
          before: list.before?.toString() ?? null,
        },
        (value) =>
          recordsOf(value, "list_emergency_access").map(
            (raw) =>
              [raw, recordRequestOf(raw, "list_emergency_access")] as const,
          ),
      ).andThen((rows) => allWithFields(fields, rows)),
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
