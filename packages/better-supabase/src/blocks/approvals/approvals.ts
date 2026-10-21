import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  Approver,
  AuthorizationHooks,
} from "../../core/contracts/authorization-hooks.ts";
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
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface ApprovalsOptions<
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
   * (`blocks.approvals.options.extraColumns`), keyed by column name. It types
   * and parses them on every read, and validates them on `request`, which
   * returns a `validation` error for a bad value.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Approvals<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * The authorization hooks. `approverOf` sees every approve, reject and
   * delegate with kind `<subject type>.<action>` and the subject id, after the
   * SQL eligibility check, and can only refuse. Needs `approver`.
   */
  readonly authorization?: Pick<AuthorizationHooks, "approverOf">;
  /** The signed-in user the transport runs as, for `approverOf`. */
  readonly approver?: Approver;
}

export type ApprovalStatus =
  | "pending"
  | "approved"
  | "rejected"
  | "cancelled"
  | "expired";

/** Who may decide a step. Any match is enough. */
export interface ApprovalApprovers {
  readonly permission?: string;
  readonly role?: string;
  readonly team?: string;
  readonly users?: readonly string[];
}

export interface ApprovalStep {
  readonly approvers: ApprovalApprovers;
  readonly required: number;
}

export interface ApprovalRequest {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly action: string;
  readonly status: ApprovalStatus;
  /** The current step, from 0. */
  readonly step: number;
  /** The policy's steps when the request was made. */
  readonly steps: readonly ApprovalStep[];
  readonly requestedBy?: string;
  readonly reason?: string;
  readonly payload: Readonly<Record<string, unknown>>;
  readonly expiresAt?: Temporal.Instant;
  readonly decidedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface ApprovalDecision {
  readonly id: string;
  readonly step: number;
  readonly approver?: string;
  readonly decision: "approved" | "rejected" | "delegated";
  readonly delegateTo?: string;
  readonly comment?: string;
  readonly createdAt: Temporal.Instant;
}

/** A request with its decisions, from `get`. */
export interface ApprovalRequestDetail extends ApprovalRequest {
  /** Whether the caller can decide the current step. */
  readonly canDecide: boolean;
  readonly decisions: readonly ApprovalDecision[];
}

export interface ApprovalRequestInput {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** An action `options.policies` names for the subject type. */
  readonly action: string;
  readonly reason?: string;
  /** Passed to the job the final approval enqueues. */
  readonly payload?: Readonly<Record<string, unknown>>;
}

export interface ApprovalListOptions {
  /** `null` lists every status. Default: `pending`. */
  readonly status?: ApprovalStatus | null;
  /** Only requests whose current step the caller can decide. */
  readonly assigned?: boolean;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly pageSize?: number;
  /** Requests made before this time, for the next page. */
  readonly before?: Temporal.Instant;
}

/** `F` is the extra request fields `options.fields` describes. */
export interface Approvals<F extends object = Record<never, never>> {
  /** Files a request under the subject type's policy for the action. */
  /** Keys besides the input's own are the request's extra columns. */
  request(
    input: ApprovalRequestInput & Partial<F>,
  ): AsyncResult<ApprovalRequest & F>;
  /** Approves the current step; the last step runs the policy's action. */
  approve(id: string, comment?: string): AsyncResult<ApprovalRequest & F>;
  /** Rejects the request. */
  reject(id: string, comment?: string): AsyncResult<ApprovalRequest & F>;
  /** Hands the caller's place on the current step to another member. */
  delegate(
    id: string,
    userId: string,
    comment?: string,
  ): AsyncResult<ApprovalRequest & F>;
  /** The requester or a manager closes a pending request. */
  cancel(id: string): AsyncResult<ApprovalRequest & F>;
  get(id: string): AsyncResult<ApprovalRequestDetail & F>;
  /** Newest first. */
  list(
    organizationId: string,
    options?: ApprovalListOptions,
  ): AsyncResult<readonly (ApprovalRequest & F)[]>;
  /** Whether the subject's latest request for the action was approved. */
  isApproved(
    subjectType: string,
    subjectId: string,
    action: string,
  ): AsyncResult<boolean>;
}

const STATUSES: readonly ApprovalStatus[] = [
  "pending",
  "approved",
  "rejected",
  "cancelled",
  "expired",
];

const DECISIONS: readonly ApprovalDecision["decision"][] = [
  "approved",
  "rejected",
  "delegated",
];

function statusOf(value: unknown): ApprovalStatus {
  const status = STATUSES.find((item) => item === value);

  if (status === undefined) {
    throw new TypeError(`unknown approval status ${String(value)}`);
  }

  return status;
}

function decisionKind(value: unknown): ApprovalDecision["decision"] {
  const decision = DECISIONS.find((item) => item === value);

  if (decision === undefined) {
    throw new TypeError(`unknown approval decision ${String(value)}`);
  }

  return decision;
}

const instant = (
  value: unknown,
  name: string,
): { readonly [key: string]: Temporal.Instant } =>
  value === null || value === undefined
    ? {}
    : { [name]: requiredInstant(value, name) };

function approversOf(value: unknown): ApprovalApprovers {
  const row = recordOf(value, "approvers");
  const permission = optionalText(row["permission"]);
  const role = optionalText(row["role"]);
  const team = optionalText(row["team"]);

  return {
    ...(permission === undefined ? {} : { permission }),
    ...(role === undefined ? {} : { role }),
    ...(team === undefined ? {} : { team }),
    ...(Array.isArray(row["users"])
      ? { users: row["users"].map((user) => textOf(user)) }
      : {}),
  };
}

function requestOf(value: unknown, fn: string): ApprovalRequest {
  const row = recordOf(value, fn);
  const requestedBy = optionalText(row["requestedBy"]);
  const reason = optionalText(row["reason"]);
  const payload = row["payload"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    action: textOf(row["action"]),
    status: statusOf(row["status"]),
    step: Number(row["step"]),
    steps: recordsOf(row["steps"] ?? [], fn).map((step) => ({
      approvers: approversOf(step["approvers"]),
      required: Number(step["required"]),
    })),
    payload:
      typeof payload === "object" && payload !== null && !Array.isArray(payload)
        ? recordOf(payload, fn)
        : {},
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(requestedBy === undefined ? {} : { requestedBy }),
    ...(reason === undefined ? {} : { reason }),
    ...instant(row["expiresAt"], "expiresAt"),
    ...instant(row["decidedAt"], "decidedAt"),
  };
}

function decisionOf(
  value: Readonly<Record<string, unknown>>,
): ApprovalDecision {
  const approver = optionalText(value["approver"]);
  const delegateTo = optionalText(value["delegateTo"]);
  const comment = optionalText(value["comment"]);

  return {
    id: textOf(value["id"]),
    step: Number(value["step"]),
    decision: decisionKind(value["decision"]),
    createdAt: requiredInstant(value["createdAt"], "createdAt"),
    ...(approver === undefined ? {} : { approver }),
    ...(delegateTo === undefined ? {} : { delegateTo }),
    ...(comment === undefined ? {} : { comment }),
  };
}

/** The `approvals` SQL module as typed calls. */
export function createApprovals<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ApprovalsOptions<S>): Approvals<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "approval request fields",
  );

  const one = (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): AsyncResult<ApprovalRequest & F> =>
    call(fn, args, (value) => value).andThen((value) =>
      withFields(fields, value, requestOf(value, fn)),
    );

  const approverOf = options.authorization?.approverOf;

  if (approverOf !== undefined && options.approver === undefined) {
    throw new TypeError(
      "createApprovals: authorization.approverOf needs the approver the transport runs as",
    );
  }

  const refused = dbError("forbidden", "not an approver for this step", {
    hint: "APPROVAL_FORBIDDEN",
  });

  /**
   * Runs `then` once `approverOf` allows the caller on request `id`; the SQL
   * check runs as well.
   */
  const asApprover = <T>(
    id: string,
    then: () => AsyncResult<T>,
  ): AsyncResult<T> => {
    const approver = options.approver;

    if (approverOf === undefined || approver === undefined) {
      return then();
    }

    return getRequest(id).andThen(async (request) => {
      if (!request.canDecide) {
        return err(refused);
      }

      let allowed = false;

      try {
        allowed = await approverOf(approver, {
          kind: `${request.subjectType}.${request.action}`,
          subject: request.subjectId,
          tenant: request.organizationId,
          ...(request.requestedBy === undefined
            ? {}
            : { requester: request.requestedBy }),
        });
      } catch {
        allowed = false;
      }

      return allowed ? then() : err(refused);
    });
  };

  const getRequest = (id: string): AsyncResult<ApprovalRequestDetail & F> =>
    call("get_approval", { request_id: id }, (value) => value).andThen(
      (value) => {
        const row = recordOf(value, "get_approval");

        return withFields(fields, row, {
          ...requestOf(row, "get_approval"),
          canDecide: row["canDecide"] === true,
          decisions: recordsOf(row["decisions"] ?? [], "get_approval").map(
            decisionOf,
          ),
        });
      },
    );

  const decide = (id: string, decision: string, comment?: string) =>
    asApprover(id, () =>
      one("decide_approval", {
        request_id: id,
        decision,
        comment: comment ?? null,
      }),
    );

  const client: Approvals<F> = {
    request: ({
      organizationId,
      subjectType,
      subjectId,
      action,
      reason,
      payload,
      ...extra
    }) =>
      AsyncResult.from(() => extraFieldsArg(fields, extra)).andThen((more) =>
        one("request_approval", {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          action,
          reason: reason ?? null,
          payload: payload ?? {},
          ...more,
        }),
      ),
    approve: (id, comment) => decide(id, "approved", comment),
    reject: (id, comment) => decide(id, "rejected", comment),
    delegate: (id, userId, comment) =>
      asApprover(id, () =>
        one("delegate_approval", {
          request_id: id,
          to_user: userId,
          comment: comment ?? null,
        }),
      ),
    cancel: (id) => one("cancel_approval", { request_id: id }),
    get: getRequest,
    list: (organizationId, list = {}) =>
      call(
        "list_approvals",
        {
          tenant: organizationId,
          status: list.status === undefined ? "pending" : list.status,
          assigned: list.assigned ?? false,
          subject_type: list.subjectType ?? null,
          subject_id: list.subjectId ?? null,
          page_size: list.pageSize ?? null,
          before: list.before?.toString() ?? null,
        },
        (value) =>
          recordsOf(value, "list_approvals").map(
            (row) => [row, requestOf(row, "list_approvals")] as const,
          ),
      ).andThen((rows) => allWithFields(fields, rows)),
    isApproved: (subjectType, subjectId, action) =>
      call(
        "is_approved",
        { subject_type: subjectType, subject_id: subjectId, action },
        (value) => value === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "approvals",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
