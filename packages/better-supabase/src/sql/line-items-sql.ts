import type { BlockSqlContext, BlockSqlTableSpec } from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";
import { fail, lockTable, triggerGrant } from "./shared.ts";

/**
 * The logical columns of a line table (`<record>_lines`). Every block with line
 * items (deals, quotes, invoices) declares one with these names, so every line
 * table has the same shape.
 */
const LINE_COLUMNS = {
  id: "id",
  tenant: "tenant_id",
  parent: "parent_id",
  productType: "product_type",
  productId: "product_id",
  description: "description",
  quantity: "quantity",
  unitAmount: "unit_amount",
  discountBps: "discount_bps",
  taxRateBps: "tax_rate_bps",
  taxCode: "tax_code",
  position: "position",
  createdAt: "created_at",
} as const;

/** The totals columns a record with lines carries, written by the trigger. */
export const TOTAL_COLUMNS = {
  listTotal: "list_total",
  discountTotal: "discount_total",
  subtotal: "subtotal",
  taxTotal: "tax_total",
  total: "total",
} as const;

/** A `NAMES.tables` entry for a line table called `name`. */
export function lineTableSpec(name: string): BlockSqlTableSpec {
  return {
    name,
    lifecycle: { tenant: "tenant", export: true },
    columns: LINE_COLUMNS,
  };
}

export interface LineItems {
  /** The logical name of the line table. */
  readonly lines: string;
  /** The logical name of the record table that owns the lines. */
  readonly parent: string;
  /** SQL over row alias `p` that is true when the record's lines can't change. */
  readonly frozen?: string;
  /** Extra `set` assignments on the record after a recount, over `v_*` totals. */
  readonly afterTotals?: string;
}

/**
 * The line table, its totals trigger and `set_<name>(record, lines)`.
 *
 * Every line rounds once: its list amount is quantity times unit amount, the
 * discount is a share of that in basis points, and tax applies to what is left.
 * The record's totals are the sums, so they always add up.
 */
export function lineItemsSql(
  ctx: BlockSqlContext,
  items: LineItems,
  options: {
    /** `set_<this>` replaces a record's lines. */
    readonly setter: string;
    /** SQL that refuses the call unless the caller may edit record `v_parent`. */
    readonly guard: string;
  },
): string {
  const t = ctx.table(items.lines);
  const p = ctx.table(items.parent);
  const c = (column: string): string => ctx.col(items.lines, column);
  const pc = (column: string): string => ctx.col(items.parent, column);
  const fn = ctx.fn(options.setter);
  const recount = ctx.fn(`${options.setter}_recount`);
  const trigger = `bsb_${ctx.tableName(items.lines).name}_totals`;
  const list = `round(l.${c("quantity")} * l.${c("unitAmount")})`;
  const discount = `round(${list} * l.${c("discountBps")} / 10000.0)`;
  const tax = `round((${list} - ${discount}) * l.${c("taxRateBps")} / 10000.0)`;

  const manages = ctx.manages
    ? `create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("parent")} uuid not null references ${p} (${pc("id")}) on delete cascade,
  ${c("productType")} text,
  ${c("productId")} text,
  ${c("description")} text not null check (length(${c("description")}) between 1 and 2000),
  ${c("quantity")} numeric(18, 4) not null check (${c("quantity")} > 0),
  ${c("unitAmount")} bigint not null,
  ${c("discountBps")} integer not null default 0 check (${c("discountBps")} >= 0 and ${c("discountBps")} <= 10000),
  ${c("taxRateBps")} integer not null default 0 check (${c("taxRateBps")} >= 0 and ${c("taxRateBps")} <= 100000),
  ${c("taxCode")} text,
  ${c("position")} integer not null,
  ${c("createdAt")} timestamptz not null default now(),
  check ((${c("productType")} is null) = (${c("productId")} is null))
);
create index if not exists ${sqlIdent(`${ctx.tableName(items.lines).name}_parent_idx`)} on ${t} (${c("parent")}, ${c("position")});
${lockTable(t, { read: true })}
drop policy if exists ${sqlIdent(`${ctx.tableName(items.lines).name}_read`)} on ${t};
create policy ${sqlIdent(`${ctx.tableName(items.lines).name}_read`)} on ${t} for select to authenticated
using (exists (select 1 from ${p} x where x.${pc("id")} = ${c("parent")}));
`
    : "";

  return `${manages}
-- Writes a record's totals from its lines. A record without lines keeps
-- zero totals.
create or replace function ${recount}(parent uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list bigint;
  v_discount bigint;
  v_tax bigint;
begin
  select coalesce(sum(${list}), 0), coalesce(sum(${discount}), 0), coalesce(sum(${tax}), 0)
    into v_list, v_discount, v_tax
  from ${t} l where l.${c("parent")} = ${options.setter}_recount.parent;
  update ${p} x set
    ${pc("listTotal")} = v_list,
    ${pc("discountTotal")} = v_discount,
    ${pc("subtotal")} = v_list - v_discount,
    ${pc("taxTotal")} = v_tax,
    ${pc("total")} = v_list - v_discount + v_tax${items.afterTotals === undefined ? "" : `,\n    ${items.afterTotals}`}
  where x.${pc("id")} = ${options.setter}_recount.parent;
end;
$$;
revoke execute on function ${recount}(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.${trigger}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then ${sqlString(`select distinct n.${c("parent")} from new_rows n order by 1`)}
    when 'DELETE' then ${sqlString(`select distinct o.${c("parent")} from old_rows o order by 1`)}
    else ${sqlString(`select n.${c("parent")} from new_rows n union select o.${c("parent")} from old_rows o order by 1`)}
  end loop
    perform ${recount}(v_parent);
  end loop;
  return null;
end;
$$;
${triggerGrant(`better_supabase.${trigger}()`)}
drop trigger if exists ${trigger} on ${t};
drop trigger if exists ${trigger}_insert on ${t};
drop trigger if exists ${trigger}_update on ${t};
drop trigger if exists ${trigger}_delete on ${t};
create trigger ${trigger}_insert after insert on ${t}
referencing new table as new_rows
for each statement execute function better_supabase.${trigger}();
create trigger ${trigger}_update after update on ${t}
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.${trigger}();
create trigger ${trigger}_delete after delete on ${t}
referencing old table as old_rows
for each statement execute function better_supabase.${trigger}();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function ${fn}(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := ${options.setter}.parent;
  v_tenant ${ctx.idType};
  v_currency text;
begin
  select x.${pc("tenant")}, x.${pc("currency")} into v_tenant, v_currency from ${p} x where x.${pc("id")} = v_parent${items.frozen === undefined ? "" : ` and not (${items.frozen.replaceAll("p.", "x.")})`};
  if v_tenant is null then
    ${fail("LINES_RECORD_INVALID", "no such record, or its lines are locked", "P0002")}
  end if;
  ${options.guard}
  if jsonb_typeof(coalesce(${options.setter}.lines, '[]')) <> 'array' then
    ${fail("LINES_INVALID", "lines must be a list", "22023")}
  end if;
  if exists (select 1 from jsonb_array_elements(${options.setter}.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    ${fail("LINES_CURRENCY", "every line must be in the record's currency", "22023")}
  end if;
  delete from ${t} l where l.${c("parent")} = v_parent;
  begin
    insert into ${t} (${c("tenant")}, ${c("parent")}, ${c("productType")}, ${c("productId")}, ${c("description")}, ${c("quantity")}, ${c("unitAmount")}, ${c("discountBps")}, ${c("taxRateBps")}, ${c("taxCode")}, ${c("position")})
    select v_tenant, v_parent, x.value -> 'product' ->> 'type', x.value -> 'product' ->> 'id', x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1), (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0), coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode', x.ordinality::integer
    from jsonb_array_elements(coalesce(${options.setter}.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    ${fail("LINES_INVALID", "every line needs a description, a positive quantity and a unit amount", "22023")}
  end;
  perform ${recount}(v_parent);
  return (select jsonb_build_object(
    'listTotal', x.${pc("listTotal")}::text, 'discountTotal', x.${pc("discountTotal")}::text,
    'subtotal', x.${pc("subtotal")}::text, 'taxTotal', x.${pc("taxTotal")}::text, 'total', x.${pc("total")}::text,
    'currency', x.${pc("currency")})
    from ${p} x where x.${pc("id")} = v_parent);
end;
$$;
revoke execute on function ${fn}(uuid, jsonb) from public, anon;
grant execute on function ${fn}(uuid, jsonb) to authenticated, service_role;
`;
}

/** The totals columns of a record table, as `create table` lines. */
export function totalColumnsSql(ctx: BlockSqlContext, table: string): string {
  const c = (column: string): string => ctx.col(table, column);

  return [
    `${c("listTotal")} bigint not null default 0`,
    `${c("discountTotal")} bigint not null default 0`,
    `${c("subtotal")} bigint not null default 0`,
    `${c("taxTotal")} bigint not null default 0`,
    `${c("total")} bigint not null default 0`,
  ].join(",\n  ");
}
