import type { BlockSqlContext } from "../context.ts";

/** The keys the control reads return next to the extra columns. */
export const CONTROL_RESERVED = ["fields", "status"] as const;

/** The attachments module, when its table is there to reference. */
export function evidenceAttachments(
  ctx: BlockSqlContext,
): BlockSqlContext | undefined {
  return ctx.installed("attachments") && ctx.of("attachments").manages
    ? ctx.of("attachments")
    : undefined;
}

/** `row.column`, or null when the app's table lacks the optional column. */
export const optionalField = (
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
): string =>
  ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";
