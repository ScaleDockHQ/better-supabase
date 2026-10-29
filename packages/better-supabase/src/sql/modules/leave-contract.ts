import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockContributes } from "../contributions.ts";

import { extraFieldsArg } from "../shared.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { leaveFeedSubject, leaveTeamFeedSubject } from "./leave-feed.ts";
import { leaveByEmployee, leavePartsMapped } from "./leave-owner.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** Leave requests this block files with approvals. */
export const LEAVE_REQUEST_SUBJECT = "leave_request";

const WHERE = "blocks.leave.options";

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

/** `options.policy` as an approvals policy; defaults to one approver step. */
export function leavePolicy(ctx: BlockSqlContext): string {
  const raw = ctx.option("policy") ?? {
    steps: [
      {
        approvers: {
          permission: ctx.permissionKey("approve", OPERATIONS["leave.approve"]),
        },
      },
    ],
  };

  const policy = policyOf(
    LEAVE_REQUEST_SUBJECT,
    "approve",
    raw,
    `${WHERE}.policy`,
  );

  if (policy.run !== undefined) {
    throw new TypeError(
      `${WHERE}.policy.run is not allowed; the final approval books the leave`,
    );
  }

  return policySnapshot(policy);
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
    ...(leaveStatusMode(ctx)
      ? [
          {
            name: "decide_leave_request",
            args: ["uuid", "boolean", "text", "uuid"],
            returns: "jsonb",
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
  "share-links": (own) => [leaveFeedSubject(own), ...leaveTeamFeedSubject(own)],
  approvals: (own) =>
    leaveStatusMode(own)
      ? []
      : [
          {
            subject: LEAVE_REQUEST_SUBJECT,
            access: "declared",
            approve: ({ subjectId }) =>
              `perform ${own.fn("approve_leave_request")}(${subjectId}::uuid);`,
          },
        ],
};
