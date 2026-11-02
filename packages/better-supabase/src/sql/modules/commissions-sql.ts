import type { BlockSqlContext } from "../context.ts";

import { SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The names and checks the commissions functions share. */
export interface CommissionSql {
  readonly ctx: BlockSqlContext;
  readonly idType: string;
  readonly fn: (name: string) => string;
  readonly plans: string;
  readonly assignments: string;
  readonly entries: string;
  readonly statements: string;
  /**
   * A column of `commission_plans`, `commission_assignments`, `commissions` or
   * `commission_statements`.
   */
  readonly p: (column: string) => string;
  readonly a: (column: string) => string;
  readonly c: (column: string) => string;
  readonly s: (column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  /** A boolean SQL expression: service caller, or a member holding `permission`. */
  readonly allowed: (tenant: string, permission: string) => string;
  readonly ledger: BlockSqlContext;
}

/** The commissions block's table, column and permission names. */
export function commissionSql(ctx: BlockSqlContext): CommissionSql {
  return {
    ctx,
    idType: ctx.idType,
    fn: (name) => ctx.fn(name),
    plans: ctx.table("plans"),
    assignments: ctx.table("assignments"),
    entries: ctx.table("entries"),
    statements: ctx.table("statements"),
    p: (column) => ctx.col("plans", column),
    a: (column) => ctx.col("assignments", column),
    c: (column) => ctx.col("entries", column),
    s: (column) => ctx.col("statements", column),
    read: ctx.permission("read", OPERATIONS["commissions.read"]),
    write: ctx.permission("write", OPERATIONS["commissions.write"]),
    manage: ctx.permission("manage", OPERATIONS["commissions.manage"]),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    ledger: ctx.of("ledger"),
  };
}
