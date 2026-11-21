import type { BlockSqlContext } from "../context.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { managerMatch } from "./approvals-tenant.ts";

/**
 * `options.approver`: `"manager"` lets the requester's manager (the employees
 * block) decide in the direct decide functions too, next to holders of the
 * approve permission. Default `"permission"`.
 */
function directApprover(
  ctx: BlockSqlContext,
  where: string,
): "permission" | "manager" {
  const value = ctx.text("approver", "permission");

  if (value !== "permission" && value !== "manager") {
    throw new TypeError(`${where}.approver must be "permission" or "manager"`);
  }

  if (
    value === "manager" &&
    (!ctx.installed("employees") || ctx.of("employees").mode === "custom")
  ) {
    throw new TypeError(
      `${where}.approver "manager" needs the employees block's tables`,
    );
  }

  return value;
}

/**
 * ` or <the caller is the requester's manager>` under `approver: "manager"`,
 * else `""`. `employee`, a text SQL expression, names the employee whose
 * manager decides when it is not null.
 */
export function managerDecides(
  ctx: BlockSqlContext,
  where: string,
  args: {
    readonly requester: string;
    readonly tenant: string;
    readonly employee?: string;
  },
): string {
  return directApprover(ctx, where) === "manager"
    ? ` or ${managerMatch(ctx, { ...args, user: "auth.uid()" })}`
    : "";
}

const FUNCTION = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;

/** The request kind the provider's `approverFor` template receives. */
const DECIDER_KINDS: Readonly<Record<string, string>> = {
  expenses: "expense",
  leave: "leave",
  "time-entries": "time-entry",
};

/**
 * Whether a caller beyond the permission holders can decide: the app's
 * `options.decider`, or the provider's `approverFor` under the provider model.
 */
export function hasDecider(ctx: BlockSqlContext): boolean {
  return (
    ctx.text("decider", "") !== "" ||
    (ctx.providerApproverFor !== undefined &&
      DECIDER_KINDS[ctx.module] !== undefined)
  );
}

/**
 * ` or <the caller may decide request id>` for `options.decider`, an app
 * function `(id uuid) returns boolean` that lets more callers decide, such as
 * the managers up the requester's reporting chain; else, when the provider's
 * `approverFor` names the request with `{id}`, a caller in its set; else `""`.
 * The explicit option wins. A null answer denies.
 */
export function deciderCall(
  ctx: BlockSqlContext,
  where: string,
  id: string,
): string {
  const name = ctx.text("decider", "");

  const kind = DECIDER_KINDS[ctx.module];

  if (name === "" && ctx.providerApproverFor !== undefined && kind) {
    const approvers = fillTemplate(
      "authorization.functions.approverFor",
      ctx.providerApproverFor,
      { kind: sqlString(kind), id },
    );

    return ` or coalesce(auth.uid() in (select t.u from ${approvers} as t(u)), false)`;
  }

  if (name === "") {
    return "";
  }

  if (!FUNCTION.test(name)) {
    throw new TypeError(
      `${where}.decider is "schema.function", a function (id uuid) returns boolean`,
    );
  }

  const [schema = "", fn = ""] = name.split(".");

  return ` or coalesce(${sqlIdent(schema)}.${sqlIdent(fn)}(${id}), false)`;
}

/**
 * The quoted `"schema"."function"` an option such as `approvalRequired` names,
 * or undefined when it is unset.
 */
export function appFunction(
  ctx: BlockSqlContext,
  where: string,
  option: string,
): string | undefined {
  const name = ctx.text(option, "");

  if (name === "") {
    return undefined;
  }

  if (!FUNCTION.test(name)) {
    throw new TypeError(`${where}.${option} is "schema.function"`);
  }

  const [schema = "", fn = ""] = name.split(".");

  return `${sqlIdent(schema)}.${sqlIdent(fn)}`;
}
