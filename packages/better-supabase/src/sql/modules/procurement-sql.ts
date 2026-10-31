import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail } from "../shared.ts";
import { linked } from "./manufacturing-sql.ts";

const PARTY_TABLES = ["companies", "people"] as const;

/**
 * A query over the contacts party `id` (text) names in `tenant`: one row per
 * company or person that matches, with the `columns` asked for (null where the
 * table lacks one). Undefined without the contacts block.
 */
export function partyRows(
  ctx: BlockSqlContext,
  id: string,
  tenant: string,
  columns: readonly string[],
): string | undefined {
  const contacts = linked(ctx, "contacts");

  if (
    contacts === undefined ||
    !PARTY_TABLES.some((table) =>
      columns.some((column) => contacts.has(table, column)),
    )
  ) {
    return undefined;
  }

  return PARTY_TABLES.map((table) => {
    const c = (column: string): string => contacts.col(table, column);

    const picked = columns
      .map((column) =>
        contacts.has(table, column) ? `p.${c(column)}` : "null",
      )
      .join(", ");

    return `select ${picked} from ${contacts.table(table)} p where p.${c("id")}::text = ${id} and p.${c("tenant")} = ${tenant} and p.${c("mergedInto")} is null`;
  }).join(" union all ");
}

/**
 * PL/pgSQL that refuses a supplier contacts marks blocked
 * (`PURCHASE_ORDER_SUPPLIER_BLOCKED`); empty without contacts or its supplier
 * status column.
 */
export function supplierBlockedSql(
  ctx: BlockSqlContext,
  id: string,
  tenant: string,
): string {
  const rows = partyRows(ctx, id, tenant, ["supplierStatus"]);

  return rows === undefined
    ? ""
    : `
  if ${id} is not null and exists (select 1 from (${rows}) s(status) where s.status = 'blocked') then
    ${fail("PURCHASE_ORDER_SUPPLIER_BLOCKED", "the supplier is blocked and can't get a purchase order", "55000")}
  end if;`;
}

/**
 * PL/pgSQL that refuses a sale which takes the party over its contacts credit
 * limit: `open` is what the party owes now in `currency`, `amount` what the
 * sale adds, and `override` holds the SQL of the caller's override. The limit
 * applies only in its own currency. Empty without contacts or its credit
 * columns. Declares nothing; it runs in its own block.
 */
export function creditLimitSql(
  ctx: BlockSqlContext,
  check: {
    readonly party: string;
    readonly tenant: string;
    readonly currency: string;
    readonly amount: string;
    readonly open: string;
    readonly override: string;
    readonly hint: string;
    readonly what: string;
    /**
     * A jsonb variable the caller declares; a soft block appends its warning to
     * it.
     */
    readonly warnings: string;
  },
): string {
  const rows = partyRows(ctx, check.party, check.tenant, [
    "creditLimit",
    "creditCurrency",
    "creditBlock",
  ]);

  if (rows === undefined) {
    return "";
  }

  return `
  declare
    v_limit bigint;
    v_block text;
  begin
    select s.credit_limit, s.credit_block into v_limit, v_block from (${rows}) s(credit_limit, credit_currency, credit_block)
    where s.credit_limit is not null and coalesce(s.credit_currency, ${check.currency}) = ${check.currency}
    order by s.credit_limit limit 1;
    if v_limit is not null and v_block is distinct from 'none' and (${check.open}) + ${check.amount} > v_limit and not (${check.override}) then
      if v_block = 'soft' then
        ${check.warnings} := coalesce(${check.warnings}, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
          'code', ${sqlString(check.hint)}, 'message', ${sqlString(`${check.what} takes the customer over their credit limit`)}, 'limit', v_limit::text));
      else
        ${fail(check.hint, `${check.what} takes the customer over their credit limit`, "55000")}
      end if;
    end if;
  end;`;
}

/**
 * The contacts person (id as text) whose `user` is `user` in `tenant`, the
 * oldest one when several are; undefined without contacts' people user column.
 */
export function userPartySql(
  ctx: BlockSqlContext,
  user: string,
  tenant: string,
): string | undefined {
  const contacts = linked(ctx, "contacts");

  if (contacts === undefined || !contacts.has("people", "user")) {
    return undefined;
  }

  const c = (column: string): string => contacts.col("people", column);

  return `(select p.${c("id")}::text from ${contacts.table("people")} p where p.${c("user")} = ${user} and p.${c("tenant")} = ${tenant} and p.${c("mergedInto")} is null order by p.${c("createdAt")} limit 1)`;
}
