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

const mapped = (ctx: BlockSqlContext, table: string, column: string): boolean =>
  typeof ctx.config.columns[table]?.[column] === "string";

export function leaveParts(ctx: BlockSqlContext): boolean {
  const start = mapped(ctx, "requests", "startPart");

  if (start !== mapped(ctx, "requests", "endPart")) {
    throw new TypeError(
      "blocks.leave.columns.requests.startPart and endPart are mapped together",
    );
  }

  if (start && ctx.owns("requests")) {
    throw new TypeError(
      "blocks.leave.columns.requests.startPart and endPart name columns of your own requests table; map tables.requests to it",
    );
  }

  return start;
}

export function leavePartsMapped(ctx: BlockSqlContext): boolean {
  return mapped(ctx, "requests", "startPart");
}

export function leaveAutoApproveMapped(ctx: BlockSqlContext): boolean {
  return mapped(ctx, "types", "autoApprove");
}

/**
 * Whether leave types say which requests need no approval: the block's own
 * types table, or a mapped `columns.types.autoApprove`.
 */
export function leaveAutoApprove(ctx: BlockSqlContext): boolean {
  return (
    ctx.has("types", "autoApprove") &&
    (leaveAutoApproveMapped(ctx) || ctx.owns("types"))
  );
}

export function leaveConfidential(ctx: BlockSqlContext): boolean {
  if (!mapped(ctx, "types", "confidential")) {
    return false;
  }

  if (ctx.owns("types")) {
    throw new TypeError(
      "blocks.leave.columns.types.confidential names a column of your own types table; map tables.types to it",
    );
  }

  return true;
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
