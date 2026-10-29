import type { LeaveEvents } from "../../blocks/leave/events.ts";
import type { BlockSqlEvents, BlockSqlNames } from "../context.ts";

import {
  leaveAutoApproveMapped,
  leaveByEmployee,
  leavePartsMapped,
} from "./leave-owner.ts";

const REQUEST_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "typeId",
  "startsOn",
  "endsOn",
  "amount",
  "approvalId",
] as const;

const ADJUSTED_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "typeId",
  "kind",
  "amount",
  "period",
] as const;

const EVENTS: BlockSqlEvents<LeaveEvents> = {
  "leave.requested": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.approved": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.cancelled": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.rejected": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.updated": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.split": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.adjusted": {
    subject: "leave-ledger-entries",
    payload: ADJUSTED_PAYLOAD,
  },
};

export const LEAVE_NAMES: BlockSqlNames = {
  entities: {
    request: { table: "requests", singular: "leave_request", primary: true },
    type: { table: "types", singular: "leave_type" },
  },
  events: EVENTS,
  hooks: ["before_leave_request", "after_leave_request"],
  options: [
    "policy",
    "workingDays",
    "allowNegative",
    "extraColumns",
    "feed",
    "approvals",
    "owner",
    "reapprove",
    "approvalOwner",
  ],
  tables: {
    types: {
      name: "leave_types",
      app: {
        unused: (ctx) => [
          ...(leaveAutoApproveMapped(ctx) ? [] : ["autoApprove"]),
          ...(typeof ctx.config.columns["types"]?.["confidential"] === "string"
            ? []
            : ["confidential"]),
        ],
      },
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        unit: "unit",
        paid: "paid",
        tracked: "tracked",
        allowance: "allowance",
        carryoverMax: "carryover_max",
        color: "color",
        autoApprove: "auto_approve",
        confidential: "confidential",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "key",
        "allowance",
        "carryoverMax",
        "color",
        "autoApprove",
        "confidential",
      ],
      typed: ["unit"],
    },
    requests: {
      name: "leave_requests",
      app: {
        unused: (ctx) => [
          ...(leaveByEmployee(ctx) ? [] : ["employee"]),
          ...(leavePartsMapped(ctx) ? [] : ["startPart", "endPart"]),
        ],
      },
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        employee: "employee_id",
        type: "type_id",
        startsOn: "starts_on",
        endsOn: "ends_on",
        partial: "partial",
        startPart: "start_part",
        endPart: "end_part",
        amount: "amount",
        note: "note",
        approval: "approval_id",
        approvedAt: "approved_at",
        cancelledAt: "cancelled_at",
        cancelledBy: "cancelled_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        rejectedAt: "rejected_at",
        decidedBy: "decided_by",
        decisionNote: "decision_note",
      },
      optional: [
        "user",
        "employee",
        "partial",
        "startPart",
        "endPart",
        "note",
        "cancelledBy",
        "approval",
        "rejectedAt",
        "decidedBy",
        "decisionNote",
      ],
      typed: ["partial", "startPart", "endPart"],
    },
    balances: {
      name: "leave_balance_entries",
      app: {
        onlyWhenMapped: true,
        unused: (ctx) => (leaveByEmployee(ctx) ? [] : ["employee"]),
      },
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        employee: "employee_id",
        type: "type_id",
        kind: "kind",
        amount: "amount",
        effectiveOn: "effective_on",
        expiresOn: "expires_on",
        request: "request_id",
        note: "note",
        key: "key",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: [
        "user",
        "employee",
        "effectiveOn",
        "expiresOn",
        "note",
        "key",
        "createdBy",
      ],
      typed: ["kind"],
    },
  },
};
