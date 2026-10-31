import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { TILL_MOVEMENT_INFLOWS } from "./tills-values.ts";

/** A block context of another module, when it is installed and not custom. */
function linked(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

/** The SQL pieces the tills files share. */
export interface TillsSql {
  readonly fn: (name: string) => string;
  /** A column of the tills table. */
  readonly t: (column: string) => string;
  /** A column of the sessions table. */
  readonly s: (column: string) => string;
  /** A column of the movements table. */
  readonly m: (column: string) => string;
  /** A column of the counts table. */
  readonly c: (column: string) => string;
  /** A column of the deposits table. */
  readonly d: (column: string) => string;
  readonly tills: string;
  readonly sessions: string;
  readonly movements: string;
  readonly counts: string;
  readonly deposits: string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly status: (message: string) => string;
  readonly tillMissing: string;
  readonly sessionMissing: string;
  readonly depositMissing: string;
  /** The accounting block's context, when it is installed and not custom. */
  readonly accounting: BlockSqlContext | undefined;
  /** The banking block's context, when it is installed and not custom. */
  readonly banking: BlockSqlContext | undefined;
  /** The cash the drawer should hold for session row `row`, in minor units. */
  readonly expected: (row: string) => string;
  readonly tillJson: (row: string) => string;
  readonly sessionJson: (row: string) => string;
  readonly movementJson: (row: string) => string;
  readonly countJson: (row: string) => string;
  /** A session with its movements, count and deposits. */
  readonly sessionDetail: (row: string) => string;
  readonly depositJson: (row: string) => string;
  /** Records a `till.*` event of a tills row. */
  readonly recordTill: (type: string, row: string, summary: string) => string;
  /** Records a `till_session.*` event of a sessions row of till `till`. */
  readonly recordSession: (
    type: string,
    row: string,
    till: string,
    summary: string,
  ) => string;
  /** Records a `till_movement.recorded` event. */
  readonly recordMovement: (row: string, till: string) => string;
  /** Records a `till_deposit.*` event of a deposits row of till `till`. */
  readonly recordDeposit: (
    type: string,
    row: string,
    till: string,
    summary: string,
  ) => string;
}

export function tillsSql(ctx: BlockSqlContext): TillsSql {
  const t = (column: string): string => ctx.col("tills", column);
  const s = (column: string): string => ctx.col("sessions", column);
  const m = (column: string): string => ctx.col("movements", column);
  const c = (column: string): string => ctx.col("counts", column);
  const d = (column: string): string => ctx.col("deposits", column);

  const inflows = TILL_MOVEMENT_INFLOWS.map((kind) => sqlString(kind)).join(
    ", ",
  );

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const self: TillsSql = {
    fn: (name) => ctx.fn(name),
    t,
    s,
    m,
    c,
    d,
    tills: ctx.table("tills"),
    sessions: ctx.table("sessions"),
    movements: ctx.table("movements"),
    counts: ctx.table("counts"),
    deposits: ctx.table("deposits"),
    read: ctx.permission("read", OPERATIONS["tills.read"]),
    write: ctx.permission("write", OPERATIONS["tills.write"]),
    manage: ctx.permission("manage", OPERATIONS["tills.manage"]),
    allowed,
    invalid: (message) => fail("TILL_INVALID", message, "22023"),
    forbidden: (message) => fail("TILL_FORBIDDEN", message),
    status: (message) => fail("TILL_STATUS", message, "55000"),
    tillMissing: fail("TILL_NOT_FOUND", "no such till", "P0002"),
    sessionMissing: fail(
      "TILL_SESSION_NOT_FOUND",
      "no such till session",
      "P0002",
    ),
    depositMissing: fail(
      "TILL_DEPOSIT_NOT_FOUND",
      "no such cash deposit",
      "P0002",
    ),
    accounting: linked(ctx, "accounting"),
    banking: linked(ctx, "banking"),
    expected: (row) =>
      `(${row}.${s("openingFloat")} + coalesce((select sum(case when bm.${m("kind")} in (${inflows}) then bm.${m("amount")} else -bm.${m("amount")} end) from ${ctx.table("movements")} bm where bm.${m("session")} = ${row}.${s("id")}), 0))`,
    tillJson: (row) =>
      `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, 'name', ${row}.${t("name")}, 'currency', ${row}.${t("currency")}, 'accountId', ${row}.${t("account")}, 'location', ${row}.${t("location")}, 'archivedAt', ${row}.${t("archivedAt")}, 'createdAt', ${row}.${t("createdAt")}, 'updatedAt', ${row}.${t("updatedAt")})`,
    sessionJson: (row) =>
      `jsonb_build_object('id', ${row}.${s("id")}, 'tillId', ${row}.${s("till")}, 'organizationId', ${row}.${s("tenant")}, 'status', ${row}.${s("status")}, 'openingFloat', ${row}.${s("openingFloat")}::text, 'expected', (select (${row}.${s("openingFloat")} + coalesce(sum(case when bm.${m("kind")} in (${inflows}) then bm.${m("amount")} else -bm.${m("amount")} end), 0))::text from ${ctx.table("movements")} bm where bm.${m("session")} = ${row}.${s("id")}), 'currency', (select bt.${t("currency")} from ${ctx.table("tills")} bt where bt.${t("id")} = ${row}.${s("till")}), 'openedBy', ${row}.${s("openedBy")}, 'openedAt', ${row}.${s("openedAt")}, 'closedBy', ${row}.${s("closedBy")}, 'closedAt', ${row}.${s("closedAt")}, 'notes', ${row}.${s("notes")})`,
    movementJson: (row) =>
      `jsonb_build_object('id', ${row}.${m("id")}, 'currency', (select bt.${t("currency")} from ${ctx.table("tills")} bt join ${ctx.table("sessions")} bs on bs.${s("till")} = bt.${t("id")} where bs.${s("id")} = ${row}.${m("session")}), 'sessionId', ${row}.${m("session")}, 'kind', ${row}.${m("kind")}, 'amount', ${row}.${m("amount")}::text, 'reason', ${row}.${m("reason")}, 'reference', ${row}.${m("reference")}, 'createdBy', ${row}.${m("createdBy")}, 'createdAt', ${row}.${m("createdAt")})`,
    countJson: (row) =>
      `jsonb_build_object('id', ${row}.${c("id")}, 'currency', (select bt.${t("currency")} from ${ctx.table("tills")} bt join ${ctx.table("sessions")} bs on bs.${s("till")} = bt.${t("id")} where bs.${s("id")} = ${row}.${c("session")}), 'sessionId', ${row}.${c("session")}, 'denominations', ${row}.${c("denominations")}, 'expected', ${row}.${c("expected")}::text, 'counted', ${row}.${c("counted")}::text, 'variance', ${row}.${c("variance")}::text, 'countedBy', ${row}.${c("countedBy")}, 'countedAt', ${row}.${c("countedAt")}, 'entryId', ${row}.${c("entry")}, 'notes', ${row}.${c("notes")})`,
    depositJson: (row) =>
      `jsonb_build_object('id', ${row}.${d("id")}, 'currency', (select bt.${t("currency")} from ${ctx.table("tills")} bt join ${ctx.table("sessions")} bs on bs.${s("till")} = bt.${t("id")} where bs.${s("id")} = ${row}.${d("session")}), 'sessionId', ${row}.${d("session")}, 'amount', ${row}.${d("amount")}::text, 'depositedOn', ${row}.${d("depositedOn")}, 'reference', ${row}.${d("reference")}, 'status', ${row}.${d("status")}, 'entryId', ${row}.${d("entry")}, 'bankTransactionId', ${row}.${d("bankTransaction")}, 'reconciledAt', ${row}.${d("reconciledAt")}, 'createdBy', ${row}.${d("createdBy")}, 'createdAt', ${row}.${d("createdAt")})`,
    sessionDetail: (row) =>
      `${self.sessionJson(row)} || jsonb_build_object(
    'movements', coalesce((select jsonb_agg(${self.movementJson("y")} order by y.${m("createdAt")}, y.${m("id")}) from ${ctx.table("movements")} y where y.${m("session")} = ${row}.${s("id")}), '[]'::jsonb),
    'count', (select ${self.countJson("y")} from ${ctx.table("counts")} y where y.${c("session")} = ${row}.${s("id")}),
    'deposits', coalesce((select jsonb_agg(${self.depositJson("y")} order by y.${d("createdAt")}, y.${d("id")}) from ${ctx.table("deposits")} y where y.${d("session")} = ${row}.${s("id")}), '[]'::jsonb))`,
    recordTill: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${t("tenant")}, 'id', ${row}.${t("id")}, 'name', ${row}.${t("name")}, 'currency', ${row}.${t("currency")})`,
        subject: `'tills/' || ${row}.${t("id")}::text`,
        tenant: `${row}.${t("tenant")}`,
        audit: {
          category: "data",
          targetType: "till",
          recordId: `${row}.${t("id")}::text`,
          targetLabel: `${row}.${t("name")}`,
          summary: sqlString(summary),
        },
      }),
    recordSession: (type, row, till, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${s("tenant")}, 'id', ${row}.${s("id")}, 'tillId', ${row}.${s("till")}, 'status', ${row}.${s("status")})`,
        subject: `'tills/' || ${row}.${s("till")}::text`,
        tenant: `${row}.${s("tenant")}`,
        audit: {
          category: "data",
          targetType: "till",
          recordId: `${row}.${s("till")}::text`,
          targetLabel: `${till}.${t("name")}`,
          summary: sqlString(summary),
        },
      }),
    recordMovement: (row, till) =>
      ctx.record({
        type: "till_movement.recorded",
        payload: `jsonb_build_object('organizationId', ${row}.${m("tenant")}, 'id', ${row}.${m("id")}, 'sessionId', ${row}.${m("session")}, 'kind', ${row}.${m("kind")}, 'amount', ${row}.${m("amount")}::text)`,
        subject: `'tills/' || ${till}.${t("id")}::text`,
        tenant: `${row}.${m("tenant")}`,
        audit: {
          category: "data",
          targetType: "till",
          recordId: `${till}.${t("id")}::text`,
          targetLabel: `${till}.${t("name")}`,
          summary: sqlString("cash movement recorded"),
        },
      }),
    recordDeposit: (type, row, till, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${d("tenant")}, 'id', ${row}.${d("id")}, 'sessionId', ${row}.${d("session")}, 'amount', ${row}.${d("amount")}::text, 'status', ${row}.${d("status")}, 'bankTransactionId', ${row}.${d("bankTransaction")})`,
        subject: `'tills/' || ${till}.${t("id")}::text`,
        tenant: `${row}.${d("tenant")}`,
        audit: {
          category: "data",
          targetType: "till",
          recordId: `${till}.${t("id")}::text`,
          targetLabel: `${till}.${t("name")}`,
          summary: sqlString(summary),
        },
      }),
  };

  return self;
}
