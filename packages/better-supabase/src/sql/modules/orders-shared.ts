import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { BlockSqlScope } from "../scope.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { fail } from "../shared.ts";
import { amountOf as bareAmountOf } from "./catalog-functions.ts";

export interface OrdersNames {
  /** The block's scope checks. */
  readonly scope: BlockSqlScope;
  readonly fn: (name: string) => string;
  readonly manage: string;
  readonly read: string;
  /** Moves lines through the kitchen (`options.kitchen`). */
  readonly prepare: string;
  /** `options.extraColumns` of the orders table. */
  readonly extras: readonly ExtraColumn[];
}

/**
 * A text amount as bigint, or null, in parentheses: a bare `case` in a PL/pgSQL
 * `if` condition ends at its first `then`.
 */
export const amountOf = (value: string): string => `(${bareAmountOf(value)})`;

/** Column accessors for one logical table. */
export const columns =
  (ctx: BlockSqlContext, table: string) =>
  (column: string): string =>
    ctx.col(table, column);

/** Order status edges; a state machine on the status column replaces them. */
const ORDER_STATUS_EDGES: Readonly<Record<string, readonly string[]>> = {
  pending_payment: ["paid", "cancelled"],
  confirmed: ["paid", "fulfilled", "cancelled"],
  paid: ["fulfilled", "refunded"],
  fulfilled: ["paid", "completed", "refunded"],
  completed: ["refunded"],
  cancelled: [],
  refunded: [],
};

/** Minutes a placed order holds its stock for payment. Default 30. */
export function paymentWindow(ctx: BlockSqlContext): number {
  const minutes = ctx.number("paymentWindowMinutes", 30);

  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 10_080) {
    throw new TypeError(
      "blocks.orders.options.paymentWindowMinutes must be a whole number of minutes from 1 to 10080",
    );
  }

  return minutes;
}

export function guard(
  scope: BlockSqlScope,
  permission: string,
  tenant: string,
): string {
  return `if not (auth.role() = 'service_role' or ${scope.can(tenant, permission)}) then
    ${fail("ORDERS_FORBIDDEN", "not allowed to manage these orders")}
  end if;`;
}

export function serviceOnlyGuard(): string {
  return `if auth.role() is distinct from 'service_role' then
    ${fail("ORDERS_FORBIDDEN", "only the service role can do this")}
  end if;`;
}

/**
 * Runs `statements` with service-role claims, then restores the caller's. The
 * function declares `v_claims text`.
 */
export function asService(statements: string): string {
  return `v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  ${statements}
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);`;
}

/** Whether a `state-machine` machine governs the orders status column. */
function machineGoverns(ctx: BlockSqlContext): boolean {
  if (!ctx.installed("state-machine")) {
    return false;
  }

  const raw = ctx.of("state-machine").option("machines");

  if (!isRecord(raw)) {
    return false;
  }

  const { schema, name } = ctx.tableName("orders");
  const column = ctx.col("orders", "status").replaceAll('"', "");

  return Object.values(raw).some((entry: unknown) => {
    if (!isRecord(entry)) {
      return false;
    }

    const table = entry["table"];

    return (
      (table === `${schema}.${name}` ||
        (schema === "public" && table === name)) &&
      entry["column"] === column
    );
  });
}

/**
 * The `numbering` format for `entity` in `tenant` as SQL, when the app
 * configured one.
 */
function sequenceFormat(
  ctx: BlockSqlContext,
  entity: "order" | "invoice",
  tenant: string,
): string | undefined {
  if (!ctx.installed("numbering")) {
    return undefined;
  }

  const entities = ctx.of("numbering").option("entities");

  if (!isRecord(entities)) {
    return undefined;
  }

  const entry = entities[entity];

  if (!isRecord(entry) || typeof entry["format"] !== "string") {
    return undefined;
  }

  return isRecord(entry["formatFrom"])
    ? `${ctx.of("numbering").fn("number_format")}(${tenant}, ${sqlString(entity)})`
    : sqlString(entry["format"]);
}

/**
 * PL/pgSQL that assigns the next gapless number of `entity` in `tenant` to
 * `seq` and `number`: from `numbering` when it configures the entity, otherwise
 * one more than the tenant's highest under a transaction lock, as plain
 * digits.
 */
export function assignNumber(
  ctx: BlockSqlContext,
  entity: "order" | "invoice",
  tenant: string,
  target: { readonly seq: string; readonly number: string },
): string {
  const format = sequenceFormat(ctx, entity, tenant);

  if (format !== undefined) {
    const next = ctx.of("numbering").fn("next_number");

    return `${target.seq} := ${next}(${tenant}, ${sqlString(entity)}, now());
  ${target.number} := better_supabase.format_assigned_number(${format}, ${target.seq}, now());`;
  }

  const o = columns(ctx, "orders");
  const column = entity === "order" ? o("sequence") : o("invoiceSequence");

  return `perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(${tenant}::text || ':commerce:${entity}', 0));
  select coalesce(max(x.${column}), 0) + 1 into ${target.seq} from ${ctx.table("orders")} x where x.${o("tenant")} = ${tenant};
  ${target.number} := ${target.seq}::text;`;
}

/**
 * `${fn("order_transition")}(order, to)`: moves an order's status along the
 * built-in edges (or leaves the check to the state machine), stamps the
 * matching timestamp and returns the previous status. Internal.
 */
export function transitionFunction(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  const o = columns(ctx, "orders");
  const governed = machineGoverns(ctx);

  const edges = Object.entries(ORDER_STATUS_EDGES)
    .map(
      ([from, to]) =>
        `    when ${sqlString(from)} then p_to = any (${sqlString(`{${to.join(",")}}`)}::text[])`,
    )
    .join("\n");

  const fn = names.fn("order_transition");

  return `
-- Moves an order to p_to and stamps when it happened. Internal: the order
-- functions call it after their own checks.
create or replace function ${fn}(p_order uuid, p_to text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from text;
begin
  select ${ctx.label("orders", "status", `x.${o("status")}`)} into v_from from ${ctx.table("orders")} x where x.${o("id")} = p_order for update;
  if v_from = p_to then
    return v_from;
  end if;${
    governed
      ? ""
      : `
  if not (case v_from
${edges}
    else false end) then
    ${fail("ORDERS_TRANSITION_INVALID", "the order can't move to this status", "55000")}
  end if;`
  }
  update ${ctx.table("orders")} x set ${o("status")} = ${ctx.cast("orders", "status", "p_to")}, ${o("updatedAt")} = now(),
    ${o("paidAt")} = case when p_to = 'paid' then coalesce(x.${o("paidAt")}, now()) else x.${o("paidAt")} end,
    ${o("fulfilledAt")} = case when p_to = 'fulfilled' then now() when p_to = 'paid' then null else x.${o("fulfilledAt")} end,
    ${o("completedAt")} = case when p_to = 'completed' then now() else x.${o("completedAt")} end,
    ${o("cancelledAt")} = case when p_to = 'cancelled' then now() else x.${o("cancelledAt")} end
  where x.${o("id")} = p_order;
  return v_from;
end;
$$;
revoke execute on function ${fn}(uuid, text) from public, anon, authenticated;
`;
}

/**
 * The `jsonb_build_object` of an order event; `o` is a record with the order's
 * columns.
 */
export function orderPayload(
  row: string,
  extra: readonly (readonly [string, string])[] = [],
): string {
  const parts = [
    `'organizationId', ${row}.tenant`,
    `'subjectType', 'order'`,
    `'subjectId', ${row}.id::text`,
    `'id', ${row}.id`,
    ...extra.map(([key, value]) => `'${key}', ${value}`),
  ];

  return `jsonb_build_object(${parts.join(", ")})`;
}

/** SQL `select` list that loads an order into a record with stable field names. */
export function orderFields(ctx: BlockSqlContext, alias: string): string {
  const o = columns(ctx, "orders");

  return [
    ["id", "id"],
    ["tenant", "tenant"],
    ["number", "number"],
    ["customer", "customer"],
    ["status", "status"],
    ["currency", "currency"],
    ["total", "total"],
    ["paid_total", "paidTotal"],
    ["refunded_total", "refundedTotal"],
    ["tax_total", "taxTotal"],
    ["tax_inclusive", "taxInclusive"],
    ["invoice_number", "invoiceNumber"],
    ["placed_at", "placedAt"],
  ]
    .map(([as, column]) =>
      column === "status"
        ? `${ctx.label("orders", "status", `${alias}.${o(column)}`)} as ${as}`
        : `${alias}.${o(column ?? "")} as ${as}`,
    )
    .join(", ");
}
