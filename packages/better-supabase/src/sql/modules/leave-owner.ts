import type { BlockSqlContext } from "../context.ts";
import type { RecordOwner } from "./record-owner.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import { ownerIsEmployee, recordOwner } from "./record-owner.ts";

const WHERE = "blocks.leave.options";

export function leaveByEmployee(ctx: BlockSqlContext): boolean {
  return ownerIsEmployee(ctx, WHERE);
}

/**
 * Whether the app's own table has the column, which turns the feature that
 * needs it on. The block's own tables never carry these columns.
 */
const declared = (ctx: BlockSqlContext, table: string, column: string) =>
  ctx.declares(table, column);

export function leaveParts(ctx: BlockSqlContext): boolean {
  const start = declared(ctx, "requests", "startPart");

  if (start !== declared(ctx, "requests", "endPart")) {
    throw new TypeError(
      "Your requests table declares only one of the columns startPart and endPart; declare both or neither",
    );
  }

  return start;
}

/**
 * Whether leave types say which requests need no approval: the block's own
 * types table, or an app table that declares the column.
 */
export function leaveAutoApprove(ctx: BlockSqlContext): boolean {
  return ctx.owns("types")
    ? ctx.has("types", "autoApprove")
    : declared(ctx, "types", "autoApprove");
}

export function leaveConfidential(ctx: BlockSqlContext): boolean {
  return declared(ctx, "types", "confidential");
}

export const leaveConfidentialKey = (ctx: BlockSqlContext): string =>
  sqlString(
    ctx.config.permissions["readConfidential"] ??
      ctx.permissionKey("manage", moduleOperations("leave").manage),
  );

export const leaveConfidentialReader = (
  ctx: BlockSqlContext,
  tenant: string,
): string =>
  `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, leaveConfidentialKey(ctx))})`;

export const leaveConfidentialFilter = (
  ctx: BlockSqlContext,
  type: string,
  sees: string,
): string =>
  leaveConfidential(ctx)
    ? ` and (${sees} or not exists (select 1 from ${ctx.table("types")} lc where lc.${ctx.col("types", "id")}::text = (${type})::text and lc.${ctx.col("types", "confidential")}))`
    : "";

export function leaveBalancesTable(ctx: BlockSqlContext): boolean {
  if (typeof ctx.config.tables["balances"] !== "string") {
    return false;
  }

  if (!ctx.appOwned.includes("balances")) {
    throw new TypeError(
      "blocks.leave.tables.balances names a table the schema doesn't declare; the block reads and adds rows to your table and never creates it",
    );
  }

  return true;
}

export type LeaveOwner = RecordOwner;

export function leaveOwner(ctx: BlockSqlContext): LeaveOwner {
  return recordOwner(ctx, {
    block: "leave",
    table: "requests",
    noun: "request",
    helper: "leave_is_mine",
  });
}

export function halfDays(
  startsOn: string,
  endsOn: string,
  startPart: string,
  endPart: string,
): { readonly first: string; readonly last: string } {
  return {
    first: `((${startsOn} - date '2000-01-01') * 2 + case when ${startPart} = 'afternoon' then 1 else 0 end)`,
    last: `((${endsOn} - date '2000-01-01') * 2 + case when ${endPart} = 'morning' then 0 else 1 end)`,
  };
}

export function dropSignatures(name: string, types: string): string {
  return `drop function if exists ${name}(${types});
drop function if exists ${name}(${types}, jsonb);`;
}
