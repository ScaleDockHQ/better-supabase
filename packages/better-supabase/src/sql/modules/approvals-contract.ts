import type { ApprovalsEvents } from "../../blocks/approvals/events.ts";
import type {
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";

const PAYLOAD = [
  "organizationId",
  "subjectType",
  "subjectId",
  "id",
  "action",
  "status",
  "step",
] as const;

const EVENTS: BlockSqlEvents<ApprovalsEvents> = {
  "approval.requested": { subject: "approval-requests", payload: PAYLOAD },
  "approval.approved": { subject: "approval-requests", payload: PAYLOAD },
  "approval.rejected": { subject: "approval-requests", payload: PAYLOAD },
  "approval.cancelled": { subject: "approval-requests", payload: PAYLOAD },
  "approval.expired": { subject: "approval-requests", payload: PAYLOAD },
  "approval.delegated": { subject: "approval-requests", payload: PAYLOAD },
};

/** The keys the request reads return next to the extra columns. */
export const REQUEST_KEYS: readonly string[] = [
  "id",
  "action",
  "status",
  "step",
  "steps",
  "reason",
  "payload",
  "decisions",
  "fields",
];

/** The approvals tables, events, hooks and options. */
export const APPROVALS_NAMES: BlockSqlNames = {
  entities: {
    approval: { table: "requests", singular: "approval", primary: true },
  },
  events: EVENTS,
  hooks: [
    "before_approval_request",
    "after_approval_request",
    "before_approval_decide",
    "after_approval_decide",
  ],
  options: ["policies", "extraColumns"],
  tables: {
    requests: {
      name: "approval_requests",
      app: {},
      lifecycle: { tenant: "tenant", user: "requestedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        action: "action",
        policy: "policy",
        step: "step",
        status: "status",
        requestedBy: "requested_by",
        reason: "reason",
        payload: "payload",
        expiresAt: "expires_at",
        remindedAt: "reminded_at",
        decidedAt: "decided_at",
        createdAt: "created_at",
      },
      optional: [
        "policy",
        "step",
        "reason",
        "payload",
        "expiresAt",
        "remindedAt",
        "decidedAt",
      ],
      typed: ["status"],
    },
    decisions: {
      name: "approval_decisions",
      app: {},
      lifecycle: { tenant: "tenant", user: "approver", export: true },
      columns: {
        id: "id",
        request: "request_id",
        tenant: "tenant_id",
        step: "step",
        approver: "approver",
        decision: "decision",
        delegateTo: "delegate_to",
        comment: "comment",
        createdAt: "created_at",
      },
      optional: ["delegateTo", "comment"],
      typed: ["decision"],
    },
  },
};

/**
 * The approvals functions the module exposes; extra is the contract of
 * request_approval's `fields` argument.
 */
export function approvalsContract(
  extra: readonly string[],
): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "request_approval",
      args: ["{id}", "text", "text", "text", "text", "jsonb", ...extra],
      returns: "jsonb",
    },
    {
      name: "decide_approval",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "delegate_approval",
      args: ["uuid", "uuid", "text"],
      returns: "jsonb",
    },
    { name: "cancel_approval", args: ["uuid"], returns: "jsonb" },
    { name: "is_approved", args: ["text", "text", "text"], returns: "boolean" },
  ];
}
