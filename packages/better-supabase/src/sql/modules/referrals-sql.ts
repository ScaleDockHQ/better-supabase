import type { BlockSqlContext } from "../context.ts";

import { SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The names and checks the referrals functions share. */
export interface ReferralSql {
  readonly ctx: BlockSqlContext;
  readonly idType: string;
  readonly fn: (name: string) => string;
  readonly codes: string;
  readonly referrals: string;
  /** A column of `referral_codes` or `referrals`. */
  readonly k: (column: string) => string;
  readonly r: (column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  /** A boolean SQL expression: service caller, or a member holding `permission`. */
  readonly allowed: (tenant: string, permission: string) => string;
  readonly ledger: BlockSqlContext;
}

/** The referrals block's table, column and permission names. */
export function referralSql(ctx: BlockSqlContext): ReferralSql {
  return {
    ctx,
    idType: ctx.idType,
    fn: (name) => ctx.fn(name),
    codes: ctx.table("codes"),
    referrals: ctx.table("referrals"),
    k: (column) => ctx.col("codes", column),
    r: (column) => ctx.col("referrals", column),
    read: ctx.permission("read", OPERATIONS["referrals.read"]),
    write: ctx.permission("write", OPERATIONS["referrals.write"]),
    manage: ctx.permission("manage", OPERATIONS["referrals.manage"]),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    ledger: ctx.of("ledger"),
  };
}
