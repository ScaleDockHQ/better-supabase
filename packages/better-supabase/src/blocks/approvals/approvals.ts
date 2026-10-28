import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  Approver,
  AuthorizationHooks,
} from "../../core/contracts/authorization-hooks.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { FilterQuery } from "../../list/filter-query.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import {
  allWithFields,
  blockFields,
  extraFieldsArg,
  withFields,
} from "../../core/block-fields.ts";
import { sha256Hex } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { subjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
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
>
  extends BlockTemporalOptions, BlockTenantOptions {
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

/**
 * `confirm`: the requester may approve their own request, as a second look.
 * `authorize`: someone else has to decide each step.
 */
export type ApprovalMode = "confirm" | "authorize";

/** Who may decide a step. Any match is enough. */
export interface ApprovalApprovers {
  readonly permission?: string;
  readonly role?: string;
  readonly team?: string;
  readonly users?: readonly string[];
  /** The requester's manager, through the employees block. */
  readonly manager?: boolean;
}

export interface ApprovalStep {
  readonly approvers: ApprovalApprovers;
  readonly required: number;
}

export interface ApprovalRequest {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: RecordRef;
  readonly action: string;
  readonly status: ApprovalStatus;
  readonly mode: ApprovalMode;
  /** The current step, from 0. */
  readonly step: number;
  /** The policy's steps when the request was made. */
  readonly steps: readonly ApprovalStep[];
  readonly requestedBy?: string;
  readonly reason?: string;
  readonly payload: Readonly<Record<string, unknown>>;
  /** The hex SHA-256 `consume` checks, from `approvalFingerprint`. */
  readonly fingerprint?: string;
  readonly expiresAt?: Temporal.Instant;
  readonly decidedAt?: Temporal.Instant;
  /** When `consume` used the approval. */
  readonly consumedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

/** What a request needs right now, from `requirement`. */
export interface ApprovalRequirement {
  readonly mode: ApprovalMode;
  readonly steps: readonly ApprovalStep[];
  readonly selfApproval: boolean;
  /** The request lifetime as a Postgres interval, when one applies. */
  readonly expiresIn?: string;
  /** The tenant policies that matched, in order. */
  readonly policies: readonly string[];
}

/**
 * A tenant's approval policy. It tightens the config policy for the same
 * subject type and action and can never loosen it.
 */
export interface ApprovalTenantPolicy {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly action: string;
  readonly name: string;
  /** Applies only to requests whose payload matches; none applies always. */
  readonly conditions?: FilterQuery;
  readonly mode: ApprovalMode;
  /** Added after the steps of the config policy and earlier tenant policies. */
  readonly steps: readonly ApprovalStep[];
  readonly selfApproval: boolean;
  readonly expiresIn?: string;
  readonly enabled: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
}

/** A new policy needs `subjectType`, `action` and `name`; `id` changes one. */
export interface ApprovalPolicyInput {
  readonly id?: string;
  readonly subjectType?: string;
  readonly action?: string;
  readonly name?: string;
  /** `null` removes the conditions. */
  readonly conditions?: FilterQuery | null;
  readonly mode?: ApprovalMode;
  readonly steps?: readonly ApprovalStep[];
  readonly selfApproval?: boolean;
  /** A Postgres interval such as `3 days`; `null` removes it. */
  readonly expiresIn?: string | null;
  readonly enabled?: boolean;
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
  /** An action `options.policies` names for the subject type. */
  readonly action: string;
  readonly reason?: string;
  /**
   * Passed to the job the final approval enqueues. Tenant policy conditions
   * match against it.
   */
  readonly payload?: Readonly<Record<string, unknown>>;
  /**
   * Binds the approval to one exact request: `consume` refuses a different
   * fingerprint. Build it with `approvalFingerprint`.
   */
  readonly fingerprint?: string;
}

export interface ApprovalListOptions {
  /** `null` lists every status. Default: `pending`. */
  readonly status?: ApprovalStatus | null;
  /** Only requests whose current step the caller can decide. */
  readonly assigned?: boolean;
  /** Only requests on this subject. */
  readonly subject?: RecordRef;
  readonly pageSize?: number;
  /** Requests made before this time, for the next page. */
  readonly before?: Temporal.Instant;
}

/**
 * `F` is the extra request fields `options.fields` describes. `request` and
 * `list` act in the block's `tenant`.
 */
export interface Approvals<F extends object = Record<never, never>> {
  /**
   * Files a request on `subject` under its type's policy for the action. Keys
   * besides the input's own are the request's extra columns.
   */
  request(
    subject: RecordRef,
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
    options?: ApprovalListOptions,
  ): AsyncResult<readonly (ApprovalRequest & F)[]>;
  /** Whether the subject's latest request for the action was approved. */
  isApproved(subject: RecordRef, action: string): AsyncResult<boolean>;
  /**
   * What a request would need for the subject type and action, with `payload`
   * as the request payload tenant conditions read; `null` when nothing is
   * required, so the action can run without a request.
   */
  requirement(
    subjectType: string,
    action: string,
    payload?: Readonly<Record<string, unknown>>,
  ): AsyncResult<ApprovalRequirement | null>;
  /**
   * Uses an approved request once, before its action runs. A second call fails
   * with `APPROVAL_CONSUMED`, and a fingerprint other than the request's with
   * `APPROVAL_FINGERPRINT_MISMATCH`.
   */
  consume(id: string, fingerprint?: string): AsyncResult<ApprovalRequest & F>;
  /** The tenant's policies (`options.tenantPolicies`). */
  listPolicies(options?: {
    readonly subjectType?: string;
    readonly pageSize?: number;
  }): AsyncResult<readonly ApprovalTenantPolicy[]>;
  /** Creates or changes a tenant policy. Needs `approvals.manage`. */
  savePolicy(input: ApprovalPolicyInput): AsyncResult<ApprovalTenantPolicy>;
  /** Deletes a tenant policy; `false` when it did not exist. */
  removePolicy(id: string): AsyncResult<boolean>;
}

/**
 * Serializes `value` with object keys sorted and no whitespace. It is stable
 * for JSON values; `undefined` members are dropped as `JSON.stringify` does.
 */
function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => (item === undefined ? "null" : canonicalJson(item))).join(",")}]`;
  }

  if (typeof value === "object" && value !== null) {
    const entries = Object.entries(value)
      .filter(([, item]) => item !== undefined)
      .toSorted(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([key, item]) => `${JSON.stringify(key)}:${canonicalJson(item)}`);

    return `{${entries.join(",")}}`;
  }

  return value === undefined ? "null" : JSON.stringify(value);
}

/**
 * The hex SHA-256 of `value` as sorted-key JSON, for `request` and `consume`.
 * Pass the exact operation the approval covers (for example the subject, the
 * action and its arguments) so an approval for one change can't run another.
 */
export function approvalFingerprint(value: unknown): Promise<string> {
  return sha256Hex(canonicalJson(value));
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
    ...(row["manager"] === true ? { manager: true } : {}),
  };
}

const stepsOf = (value: unknown, fn: string): readonly ApprovalStep[] =>
  recordsOf(value ?? [], fn).map((step) => ({
    approvers: approversOf(step["approvers"]),
    required: Number(step["required"] ?? 1),
  }));

const modeOf = (value: unknown): ApprovalMode =>
  value === "confirm" ? "confirm" : "authorize";

function requestOf(value: unknown, fn: string): ApprovalRequest {
  const row = recordOf(value, fn);
  const requestedBy = optionalText(row["requestedBy"]);
  const reason = optionalText(row["reason"]);
  const fingerprint = optionalText(row["fingerprint"]);
  const payload = row["payload"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subject: subjectRefOf(row["subjectType"], row["subjectId"]),
    action: textOf(row["action"]),
    status: statusOf(row["status"]),
    mode: modeOf(row["mode"]),
    step: Number(row["step"]),
    steps: stepsOf(row["steps"], fn),
    payload:
      typeof payload === "object" && payload !== null && !Array.isArray(payload)
        ? recordOf(payload, fn)
        : {},
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(requestedBy === undefined ? {} : { requestedBy }),
    ...(reason === undefined ? {} : { reason }),
    ...(fingerprint === undefined ? {} : { fingerprint }),
    ...instant(row["expiresAt"], "expiresAt"),
    ...instant(row["decidedAt"], "decidedAt"),
    ...instant(row["consumedAt"], "consumedAt"),
  };
}

function requirementOf(value: unknown): ApprovalRequirement | null {
  if (value === null || value === undefined) {
    return null;
  }

  const row = recordOf(value, "approval_requirement");
  const expiresIn = optionalText(row["expiresIn"]);

  return {
    mode: modeOf(row["mode"]),
    steps: stepsOf(row["steps"], "approval_requirement"),
    selfApproval: row["selfApproval"] === true,
    policies: Array.isArray(row["policies"])
      ? row["policies"].map((id) => textOf(id))
      : [],
    ...(expiresIn === undefined ? {} : { expiresIn }),
  };
}

/** Save_approval_policy stores only trees `rule_check` accepts. */
const isFilterGroup = (value: unknown): value is FilterQuery =>
  isRecord(value) && value["type"] === "group" && Array.isArray(value["rules"]);

function conditionsOf(value: unknown): FilterQuery {
  if (!isFilterGroup(value)) {
    throw new TypeError(`approval conditions are ${JSON.stringify(value)}`);
  }

  return value;
}

function tenantPolicyOf(value: unknown, fn: string): ApprovalTenantPolicy {
  const row = recordOf(value, fn);
  const expiresIn = optionalText(row["expiresIn"]);
  const conditions = row["conditions"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    action: textOf(row["action"]),
    name: textOf(row["name"]),
    mode: modeOf(row["mode"]),
    steps: stepsOf(row["steps"], fn),
    selfApproval: row["selfApproval"] === true,
    enabled: row["enabled"] !== false,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(conditions === null || conditions === undefined
      ? {}
      : { conditions: conditionsOf(conditions) }),
    ...(expiresIn === undefined ? {} : { expiresIn }),
    ...instant(row["updatedAt"], "updatedAt"),
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

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

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
          kind: `${request.subject.type}.${request.action}`,
          subject: request.subject.id,
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
    request: (subject, { action, reason, payload, fingerprint, ...extra }) =>
      tenant().andThen((organizationId) =>
        AsyncResult.from(() => extraFieldsArg(fields, extra)).andThen((more) =>
          one("request_approval", {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            action,
            reason: reason ?? null,
            payload: payload ?? {},
            ...more,
            ...(fingerprint === undefined ? {} : { fingerprint }),
          }),
        ),
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
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_approvals",
          {
            tenant: organizationId,
            status: list.status === undefined ? "pending" : list.status,
            assigned: list.assigned ?? false,
            subject_type: list.subject?.type ?? null,
            subject_id: list.subject?.id ?? null,
            page_size: list.pageSize ?? null,
            before: list.before?.toString() ?? null,
          },
          (value) =>
            recordsOf(value, "list_approvals").map(
              (row) => [row, requestOf(row, "list_approvals")] as const,
            ),
        ).andThen((rows) => allWithFields(fields, rows)),
      ),
    isApproved: (subject, action) =>
      call(
        "is_approved",
        { subject_type: subject.type, subject_id: subject.id, action },
        (value) => value === true,
      ),
    requirement: (subjectType, action, payload) =>
      tenant().andThen((organizationId) =>
        call(
          "approval_requirement",
          {
            tenant: organizationId,
            subject_type: subjectType,
            action,
            subject: payload ?? {},
          },
          requirementOf,
        ),
      ),
    consume: (id, fingerprint) =>
      one("consume_approval", {
        request_id: id,
        fingerprint: fingerprint ?? null,
      }),
    listPolicies: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_approval_policies",
          {
            tenant: organizationId,
            subject_type: list.subjectType ?? null,
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_approval_policies").map((row) =>
              tenantPolicyOf(row, "list_approval_policies"),
            ),
        ),
      ),
    savePolicy: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_approval_policy",
          { tenant: organizationId, policy: input },
          (value) => tenantPolicyOf(value, "save_approval_policy"),
        ),
      ),
    removePolicy: (id) =>
      call(
        "remove_approval_policy",
        { policy_id: id },
        (value) => value === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "approvals",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
