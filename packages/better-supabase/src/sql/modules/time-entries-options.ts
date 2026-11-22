import type { BlockSqlContext } from "../context.ts";
import type { ApprovalPolicy } from "./approvals-policies.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  assertCountedApprovers,
  policyOf,
  policySnapshot,
} from "./approvals-policies.ts";
import { otherDecider } from "./approvals-tenant.ts";
import { hasDecider } from "./direct-approver.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.time-entries.options";

/** Timesheets this block submits to approvals. */
export const TIMESHEET_SUBJECT = "timesheet";

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

/**
 * `options.policy` as an approvals policy; defaults to one approver step, which
 * `options.decider` joins.
 */
export function timesheetPolicy(ctx: BlockSqlContext): string {
  return policySnapshot(timesheetPolicyOf(ctx));
}

function timesheetPolicyOf(ctx: BlockSqlContext): ApprovalPolicy {
  const raw = ctx.option("policy") ?? {
    steps: [
      {
        approvers: {
          permission: ctx.permissionKey(
            "approve",
            OPERATIONS["time-entries.approve"],
          ),
          ...(hasDecider(ctx) ? { decider: true } : {}),
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

  return policy;
}

const FUNCTION = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/u;

/**
 * What `submit_timesheet` checks before it files a week with approvals:
 * `options.approvalRequired`, an app function `(tenant, timesheet_id uuid)
 * returns boolean` whose false approves the week at once, and
 * `options.selfApproveWhenTopOfChain`, which approves it at once when the
 * week's owner submits it, holds the approve permission and nobody else could
 * decide it. Both are `undefined` when the option is off.
 */
export function timesheetAtOnce(
  ctx: BlockSqlContext,
  args: {
    readonly tenant: string;
    readonly sheet: string;
    readonly requester: string;
    readonly employee?: string;
  },
): { readonly notRequired?: string; readonly self?: string } {
  const required = ctx.text("approvalRequired", "");
  const self = ctx.flag("selfApproveWhenTopOfChain", false);

  if ((required !== "" || self) && !ctx.flag("approvals", true)) {
    throw new TypeError(
      `${WHERE}.approvalRequired and selfApproveWhenTopOfChain decide whether a week goes to the approvals block, so they need approvals`,
    );
  }

  if (required !== "" && !FUNCTION.test(required)) {
    throw new TypeError(
      `${WHERE}.approvalRequired is "schema.function", a function (tenant, timesheet_id uuid) returns boolean`,
    );
  }

  const [schema = "", fn = ""] = required.split(".");

  const notRequired =
    required === ""
      ? undefined
      : `not coalesce(${sqlIdent(schema)}.${sqlIdent(fn)}(${args.tenant}, ${args.sheet}), true)`;

  if (!self) {
    return notRequired === undefined ? {} : { notRequired };
  }

  const policy = timesheetPolicyOf(ctx);

  const approve = ctx.permissionKey(
    "approve",
    OPERATIONS["time-entries.approve"],
  );

  assertCountedApprovers(policy, approve, `${WHERE}.selfApproveWhenTopOfChain`);

  if (!policy.steps.every((step) => step.approvers.permission === approve)) {
    throw new TypeError(
      `${WHERE}.selfApproveWhenTopOfChain approves for the owner only when every policy step names ${approve}, which the owner holds`,
    );
  }

  if (
    (ctx.modules.permissions?.model === "custom" &&
      ctx.modules.permissions.functions?.canUser === undefined) ||
    ctx.providerCallerOnly === true
  ) {
    throw new TypeError(
      `${WHERE}.selfApproveWhenTopOfChain needs an access model that answers for other users (blocks.permissions.functions.canUser, or the provider's idsWithFor and isPlatformFor) to find the other approvers`,
    );
  }

  const other = otherDecider(ctx, {
    requester: args.requester,
    tenant: args.tenant,
    permission: ctx.permission("approve", OPERATIONS["time-entries.approve"]),
    manager: policy.steps.some(
      (step) =>
        step.approvers.manager === true || step.escalateTo?.manager === true,
    ),
    chain: hasDecider(ctx),
    ...(args.employee === undefined ? {} : { employee: args.employee }),
  });

  if (other === undefined) {
    throw new TypeError(
      `${WHERE}.selfApproveWhenTopOfChain with a manager step or a decider needs the employees block's tables`,
    );
  }

  return {
    ...(notRequired === undefined ? {} : { notRequired }),
    self: `(auth.uid() is not null and coalesce(${args.requester} = auth.uid(), false) and coalesce(${ctx.can("tenant", args.tenant, ctx.permission("approve", OPERATIONS["time-entries.approve"]))}, false) and not ${other})`,
  };
}

/** The statements of `options.approvalRequired` and `selfApproveWhenTopOfChain`. */
export interface AtOnceSql {
  /** The declarations `decide` and `approve` use. */
  readonly declare: string;
  /** Sets `v_at_once` and `v_self`. */
  readonly decide: string;
  /** `statement` unless the week is approved at once. */
  readonly open: (statement: string) => string;
  /** `statements` when the week is approved at once. */
  readonly approve: (statements: string) => string;
}

/** `timesheetAtOnce` as statements of `submit_timesheet`. */
export function atOnceSql(
  checks: ReturnType<typeof timesheetAtOnce>,
): AtOnceSql {
  const { notRequired, self } = checks;

  if (notRequired === undefined && self === undefined) {
    return {
      declare: "",
      decide: "",
      open: (statement) => statement,
      approve: () => "",
    };
  }

  return {
    declare: "\n  v_self boolean := false;\n  v_at_once boolean;",
    decide: `${self === undefined ? "" : `\n  v_self := ${self};`}
  v_at_once := v_self${notRequired === undefined ? "" : ` or ${notRequired}`};`,
    open: (statement) =>
      `if not v_at_once then
    ${statement.replaceAll("\n", "\n  ")}
  end if;`,
    approve: (statements) => `
  if v_at_once then
    ${statements}
  end if;`,
  };
}
