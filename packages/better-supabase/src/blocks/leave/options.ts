import type { ShareLinkFeedOptions } from "../feed-options.ts";
import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

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
  readonly extraColumns?: ExtraColumns;
  readonly feed?: LeaveFeedOptions;
  /**
   * `false` runs leave without the approvals block: a request stays pending
   * until `decide_leave_request` approves or rejects it.
   */
  readonly approvals?: boolean;
  readonly owner?: "user" | "employee";
  readonly reapprove?: boolean;
};

export const leaveSqlOptions: BlockOptionsSchema<LeaveSqlOptions> =
  blockOptions<LeaveSqlOptions>({
    policy: option.unknown(),
    workingDays: option.strings({
      default: ["mon", "tue", "wed", "thu", "fri"],
    }),
    allowNegative: option.boolean({ default: false }),
    extraColumns: option.extraColumns(),
    feed: option.unknown<LeaveFeedOptions>(),
    approvals: option.boolean({ default: true }),
    owner: option.string<"user" | "employee">({ default: "user" }),
    reapprove: option.boolean({ default: false }),
  });
