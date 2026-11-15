import type { BlockSqlContext } from "../context.ts";

import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { TIMESHEET_SUBJECT } from "./time-entries-approvals.ts";

const WHERE = "blocks.time-entries.options";

/** `options.timeZone`: the IANA zone weeks start in. Default `UTC`. */
export function weekTimeZone(ctx: BlockSqlContext): string {
  const raw = ctx.option("timeZone") ?? "UTC";

  if (typeof raw !== "string" || raw.length === 0) {
    throw new TypeError(`${WHERE}.timeZone must be an IANA time zone`);
  }

  try {
    Intl.DateTimeFormat("en", { timeZone: raw });
  } catch {
    throw new TypeError(`${WHERE}.timeZone: "${raw}" is not a time zone`);
  }

  return raw;
}

/** `options.policy` as an approvals policy; defaults to one approver step. */
export function timesheetPolicy(ctx: BlockSqlContext): string {
  const raw = ctx.option("policy") ?? {
    steps: [
      {
        approvers: {
          permission: ctx.permissionKey(
            "approve",
            OPERATIONS["time-entries.approve"],
          ),
        },
      },
    ],
  };

  const policy = policyOf(TIMESHEET_SUBJECT, "approve", raw, `${WHERE}.policy`);

  if (policy.run !== undefined) {
    throw new TypeError(
      `${WHERE}.policy.run is not allowed; the final approval locks the week`,
    );
  }

  return policySnapshot(policy);
}
