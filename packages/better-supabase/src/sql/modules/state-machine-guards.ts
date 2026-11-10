import type { BlockSqlContext } from "../context.ts";
import type { Guard, Machine } from "./state-machine-options.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, quotedTable, SERVICE_CALLER } from "../shared.ts";

/** The permission part of a guard, on the row `row` names. */
export function guardPermission(
  ctx: BlockSqlContext,
  item: Machine,
  guard: Guard,
  row: string,
): string | undefined {
  return guard.permission === undefined
    ? undefined
    : `(${SERVICE_CALLER} or ${ctx.can("tenant", `${row}.${sqlIdent(item.tenantColumn)}`, sqlString(guard.permission))})`;
}

/** The function part of a guard, on the row `row` names. */
export function guardCheck(guard: Guard, row: string): string | undefined {
  return guard.check === undefined
    ? undefined
    : `coalesce(${quotedTable(guard.check)}(${row}), false)`;
}

export function guardGate(ctx: BlockSqlContext, item: Machine): string {
  return item.guards
    .map((guard) => {
      const permission = guardPermission(ctx, item, guard, "new");
      const check = guardCheck(guard, "new");

      return `
  if old.${sqlIdent(item.column)}::text = ${sqlString(guard.from)} and new.${sqlIdent(item.column)}::text = ${sqlString(guard.to)} then${
    permission === undefined
      ? ""
      : `
    if not ${permission} then
      ${fail("STATE_TRANSITION_FORBIDDEN", "the caller may not make that status change", "42501")}
    end if;`
  }${
    check === undefined
      ? ""
      : `
    if not ${check} then
      ${fail("STATE_GUARD_FAILED", "the record does not meet the condition for that status change", "23514")}
    end if;`
  }
  end if;`;
    })
    .join("");
}

/**
 * Sets each `stamps` column when the record enters its status; on insert only
 * when the column is empty and no import runs.
 */
export function stampWrite(
  ctx: BlockSqlContext,
  item: Machine,
  inserting: boolean,
): string {
  return Object.entries(item.stamps)
    .map(
      ([status, column]) => `
    if new.${sqlIdent(item.column)}::text = ${sqlString(status)}${inserting ? ` and new.${sqlIdent(column)} is null and not ${ctx.importing()}` : ""} then
      new.${sqlIdent(column)} := now();
    end if;`,
    )
    .join("");
}
