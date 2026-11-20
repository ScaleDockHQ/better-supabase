import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type {
  ApprovalContribution,
  ApprovalRequestSql,
  BlockContributes,
} from "../contributions.ts";
import type { ApprovalPolicy } from "./approvals-policies.ts";

import { extraFieldsArg } from "../shared.ts";
import {
  assertCountedApprovers,
  policyOf,
  policySnapshot,
} from "./approvals-policies.ts";
import { deciderCall } from "./direct-approver.ts";
import { leaveFeedSubject, leaveTeamFeedSubject } from "./leave-feed.ts";
import { leaveByEmployee, leavePartsMapped } from "./leave-owner.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** Leave requests this block files with approvals. */
const LEAVE_REQUEST_SUBJECT = "leave_request";

const WHERE = "blocks.leave.options";

const SUBJECT_TYPE = /^[a-z][a-z0-9_]{0,62}$/u;

/** `options.approvalSubject`: the subject type of the approval requests. */
export function leaveApprovalSubject(ctx: BlockSqlContext): string {
  const value = ctx.text("approvalSubject", LEAVE_REQUEST_SUBJECT);

  if (!SUBJECT_TYPE.test(value)) {
    throw new TypeError(
      `${WHERE}.approvalSubject must be a snake_case subject type, such as "time_off_request"`,
    );
  }

  return value;
}

/** The keys the request reads return next to the extra columns. */
export const RESERVED = ["fields"] as const;

const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

const ISO_WEEKDAY = new Map<string, number>(
  DAYS.map((day, index) => [day, index + 1]),
);

/** `options.workingDays` as ISO weekday numbers (Monday is 1). */
export function workingDaysOf(ctx: BlockSqlContext): readonly number[] {
  const days = ctx.list("workingDays", ["mon", "tue", "wed", "thu", "fri"]);

  if (days.length === 0) {
    throw new TypeError(`${WHERE}.workingDays must name at least one day`);
  }

  return [
    ...new Set(
      days.map((day) => {
        const weekday = ISO_WEEKDAY.get(day);

        if (weekday === undefined) {
          throw new TypeError(
            `${WHERE}.workingDays: "${day}" is not one of ${DAYS.join(", ")}`,
          );
        }

        return weekday;
      }),
    ),
  ].toSorted((a, b) => a - b);
}

/**
 * `options.policy` as an approvals policy; defaults to one approver step, which
 * `options.decider` joins in approvals mode.
 */
export function leavePolicyOf(ctx: BlockSqlContext): ApprovalPolicy {
  const decider = !leaveStatusMode(ctx) && ctx.text("decider", "") !== "";

  const raw = ctx.option("policy") ?? {
    steps: [
      {
        approvers: {
          permission: ctx.permissionKey("approve", OPERATIONS["leave.approve"]),
          ...(decider ? { decider: true } : {}),
        },
      },
    ],
  };

  const policy = policyOf(
    leaveApprovalSubject(ctx),
    "approve",
    raw,
    `${WHERE}.policy`,
  );

  if (policy.run !== undefined) {
    throw new TypeError(
      `${WHERE}.policy.run is not allowed; the final approval books the leave`,
    );
  }

  return policy;
}

/**
 * Throws when `selfDecideWhenTopOfChain` meets an approvals policy whose
 * approvers it can't count: it knows holders of the approve permission, the
 * manager and, with a decider, the managers up the chain, so a role, team, user
 * list or other permission could let the requester decide while someone else
 * could.
 */
export function leaveSelfDecideSteps(ctx: BlockSqlContext): void {
  if (leaveStatusMode(ctx) || !ctx.flag("selfDecideWhenTopOfChain", false)) {
    return;
  }

  assertCountedApprovers(
    leavePolicyOf(ctx),
    ctx.permissionKey("approve", OPERATIONS["leave.approve"]),
    `${WHERE}.selfDecideWhenTopOfChain`,
  );
}

/** `leavePolicyOf` as the snapshot `open_approval` takes. */
export function leavePolicy(ctx: BlockSqlContext): string {
  return policySnapshot(leavePolicyOf(ctx));
}

/**
 * `options.approvalOwner`: `"employee"` makes the request's employee the
 * approval's requester and points a manager step at their manager; the default
 * `"filer"` keeps the user who filed it. Needs `owner: "employee"`.
 */
export function leaveApprovalOwner(
  ctx: BlockSqlContext,
  employee: boolean,
): "filer" | "employee" {
  const value = ctx.text("approvalOwner", "filer");

  if (value !== "filer" && value !== "employee") {
    throw new TypeError(`${WHERE}.approvalOwner must be "filer" or "employee"`);
  }

  if (value === "employee" && !employee) {
    throw new TypeError(
      `${WHERE}.approvalOwner "employee" needs ${WHERE}.owner "employee"`,
    );
  }

  return value;
}

/**
 * Whether requests keep their decision themselves instead of in the approvals
 * block: `options.approvals: false`, or no approval column.
 */
export function leaveStatusMode(ctx: BlockSqlContext): boolean {
  return !ctx.flag("approvals", true) || !ctx.has("requests", "approval");
}

export function leaveContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("requests", RESERVED)).contract;
  const employee = leaveByEmployee(ctx) ? ["uuid"] : [];

  return [
    {
      name: "request_leave",
      args: [
        "{id}",
        "uuid",
        "date",
        "date",
        "text",
        "numeric",
        "text",
        ...(leavePartsMapped(ctx) ? ["text", "text"] : []),
        ...employee,
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "leave_working_days", args: ["date", "date"], returns: "integer" },
    { name: "cancel_leave_request", args: ["uuid"], returns: "jsonb" },
    {
      name: "update_leave_request",
      args: [
        "uuid",
        "date",
        "date",
        "text",
        "numeric",
        "text",
        ...(leavePartsMapped(ctx) ? ["text", "text"] : []),
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "split_leave_request",
      args: ["uuid", "date", "date"],
      returns: "jsonb",
    },
    {
      name: "leave_balances",
      args: ["{id}", "uuid", "integer", ...employee],
      returns: "jsonb",
    },
    {
      name: "list_leave_requests",
      args: [
        "{id}",
        "uuid",
        "text",
        "date",
        "date",
        "boolean",
        "integer",
        ...employee,
      ],
      returns: "jsonb",
    },
    { name: "page_leave_requests", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "get_leave_request", args: ["uuid"], returns: "jsonb" },
    ...(leaveStatusMode(ctx)
      ? [
          {
            name: "decide_leave_request",
            args: ["uuid", "boolean", "text", "uuid"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(ctx.flag("selfDecideWhenTopOfChain", false)
      ? [
          { name: "leave_self_decides", args: ["{id}"], returns: "boolean" },
          {
            name: "leave_request_self_decides",
            args: ["uuid"],
            returns: "boolean",
          },
        ]
      : []),
    ...(ctx.installed("share-links")
      ? [{ name: "leave_feed", args: ["text"], returns: "jsonb" }]
      : []),
  ];
}

/** The final approval of a leave request books it. */
export const LEAVE_CONTRIBUTES: BlockContributes = {
  periods: (own) => [
    {
      kind: "leave_year",
      cadence: "year",
      blockers: own.fn("leave_range_close_blockers"),
      onClose: own.fn("leave_close_range"),
    },
  ],
  "share-links": (own) => [leaveFeedSubject(own), ...leaveTeamFeedSubject(own)],
  approvals: (own) =>
    leaveStatusMode(own)
      ? []
      : [
          {
            subject: leaveApprovalSubject(own),
            access: "declared",
            approve: ({ subjectId, comment, approver }) =>
              `perform ${own.fn("leave_approval_decided")}(${subjectId}::uuid, 'approved', ${comment}, ${approver});`,
            reject: ({ subjectId, comment, approver }) =>
              `perform ${own.fn("leave_approval_decided")}(${subjectId}::uuid, 'rejected', ${comment}, ${approver});`,
            cancel: ({ subjectId, approver }) =>
              `perform ${own.fn("leave_approval_decided")}(${subjectId}::uuid, 'cancelled', null, ${approver});`,
            ...leaveDeciders(own),
          },
        ],
};

/**
 * `options.decider` and `options.selfDecideWhenTopOfChain` in approvals mode:
 * the app function decides steps with `decider: true`, and a requester nobody
 * else can decide for approves their own request.
 */
function leaveDeciders(
  own: BlockSqlContext,
): Pick<ApprovalContribution, "decides" | "selfDecides"> {
  const decider = deciderCall(own, WHERE, "null");

  return {
    ...(decider === ""
      ? {}
      : {
          decides: ({ subjectId }: ApprovalRequestSql) =>
            deciderCall(own, WHERE, `${subjectId}::uuid`).replace(/^ or /u, ""),
        }),
    ...(own.flag("selfDecideWhenTopOfChain", false)
      ? {
          selfDecides: ({ subjectId }: ApprovalRequestSql) =>
            `${own.fn("leave_request_self_decides")}(${subjectId}::uuid)`,
        }
      : {}),
  };
}
