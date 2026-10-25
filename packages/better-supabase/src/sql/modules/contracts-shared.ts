import type { BlockSqlContext } from "../context.ts";

/** The keys the contract reads return next to the extra columns. */
export const CONTRACT_RESERVED = ["fields"] as const;

export const CONTRACT_STATUSES = [
  "draft",
  "in_review",
  "out_for_signature",
  "active",
  "expired",
  "terminated",
] as const;

const PAIRS: Readonly<Record<string, readonly [string, string]>> = {
  value: ["value", "currency"],
  currency: ["value", "currency"],
  counterpartyType: ["counterpartyType", "counterpartyId"],
  counterpartyId: ["counterpartyType", "counterpartyId"],
};

/**
 * Whether the contracts table keeps column. The value and currency, and the
 * counterparty type and id, are kept together or not at all.
 */
export function keepsContract(ctx: BlockSqlContext, column: string): boolean {
  const pair = PAIRS[column];

  return pair === undefined
    ? ctx.has("contracts", column)
    : ctx.has("contracts", pair[0]) && ctx.has("contracts", pair[1]);
}
