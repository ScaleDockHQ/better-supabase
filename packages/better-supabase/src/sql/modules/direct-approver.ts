import type { BlockSqlContext } from "../context.ts";

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
