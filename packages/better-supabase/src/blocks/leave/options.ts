import type { ShareLinkFeedOptions } from "../feed-options.ts";
import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.leave.options.feed`. */
export type LeaveFeedOptions = ShareLinkFeedOptions & {
  /** Each entry carries the employee's name. Needs the employees block. */
  readonly names?: boolean;
  /** Type keys whose name the feed leaves out, such as sick leave. */
  readonly hideTypes?: readonly string[];
  /**
   * A `leave_team_feed` share link (subject id: a team's id) shares the leave
   * of that team's members. Needs the teams block.
   */
  readonly teams?: boolean;
  /** Each entry carries the request's extra columns. */
  readonly fields?: boolean;
  /**
   * A column of the employees table that names an employee's team, such as
   * `department_team_id`. A team feed then shares the leave of the employees
   * whose column holds the team's id, instead of the team's members. Needs
   * `teams` and the employees block.
   */
  readonly teamColumn?: string;
  /** A team feed carries the team's name. Needs `teams`. */
  readonly teamName?: boolean;
  /**
   * `"schema.table.column"` of the organization's name, matched on the table's
   * `id`; the feed carries it as `organizationName`.
   */
  readonly organizationName?: string;
  /**
   * `"busy"` lists the confidential leave the link's creator can't see under
   * `busy`, with who and when but without the type, amount or fields. Default
   * `"hide"` leaves it out. Needs `columns.types.confidential`.
   */
  readonly confidential?: "hide" | "busy";
};

/** `blocks.leave.options`. */
export type LeaveSqlOptions = {
  readonly policy?: unknown;
  readonly workingDays?: readonly string[];
  readonly allowNegative?: boolean;
  readonly feed?: LeaveFeedOptions;
  /**
   * `false` runs leave without the approvals block: a request stays pending
   * until `decide_leave_request` approves or rejects it.
   */
  readonly approvals?: boolean;
  readonly owner?: "user" | "employee";
  readonly reapprove?: boolean;
  /**
   * `"employee"` makes the request's employee the approval's requester, so they
   * can't approve their own leave, and points a manager step at their manager
   * instead of the filer's. Needs `owner: "employee"`. Default `"filer"`.
   */
  readonly approvalOwner?: "filer" | "employee";
  /**
   * With `approvals: false`, `"manager"` lets the requester's manager (the
   * employees block) decide through `decide_leave_request` too, next to holders
   * of the approve permission. Default `"permission"`.
   */
  readonly approver?: "permission" | "manager";
  /**
   * With `approvals: false`, `"schema.function"` of an app function
   * `(request_id uuid) returns boolean` that lets more callers decide through
   * `decide_leave_request`, such as the managers up the requester's reporting
   * chain. It runs as the function's owner with the caller's `auth.uid()`; the
   * requester still never decides their own request.
   */
  readonly decider?: string;
  /**
   * With `approvals: false`, a requester who holds the approve permission
   * decides their own request through `decide_leave_request` when nobody else
   * can: no other active member holds the permission, and no active manager
   * with a login can decide it (`approver: "manager"`, or anyone up the chain
   * with a `decider`). Needs the employees block. Default `false`.
   */
  readonly selfDecideWhenTopOfChain?: boolean;
  /**
   * In approvals mode, the subject type the requests' approvals are filed
   * under, such as `"time_off_request"`; approval policies match it. Default
   * `"leave_request"`.
   */
  readonly approvalSubject?: string;
  /**
   * An app function `"schema.function"`, `(tenant, request_id uuid) returns
   * boolean`. When it answers false, the request is approved at once and no
   * approval request is filed, so its type never reaches an approval payload;
   * true or null files one as usual.
   */
  readonly approvalRequired?: string;
};

export const leaveSqlOptions: BlockOptionsSchema<LeaveSqlOptions> =
  blockOptions<LeaveSqlOptions>({
    policy: option.unknown(),
    workingDays: option.strings({
      default: ["mon", "tue", "wed", "thu", "fri"],
    }),
    allowNegative: option.boolean({ default: false }),
    feed: option.unknown<LeaveFeedOptions>(),
    approvals: option.boolean({ default: true }),
    owner: option.string<"user" | "employee">({ default: "user" }),
    reapprove: option.boolean({ default: false }),
    approvalOwner: option.string<"filer" | "employee">({ default: "filer" }),
    approver: option.string<"permission" | "manager">({
      default: "permission",
    }),
    decider: option.string(),
    selfDecideWhenTopOfChain: option.boolean({ default: false }),
    approvalSubject: option.string({ default: "leave_request" }),
    approvalRequired: option.string(),
  });
