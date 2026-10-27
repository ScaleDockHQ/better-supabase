import type {
  BlockSqlContext,
  BlockSqlTableSpec,
  ExtraColumn,
} from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";
import {
  addExtraColumns,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  lockTable,
  triggerGrant,
  writeExtraColumns,
} from "./shared.ts";

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

/** What a read gives for a line column the app's table lacks. */
const LINE_DEFAULTS: Readonly<Record<string, string>> = {
  productType: "null::text",
  productId: "null::text",
  discountBps: "0",
  taxRateBps: "0",
  taxCode: "null::text",
};

/** The line columns an app's line table may lack. */
const OPTIONAL_LINE_COLUMNS = [
  "productType",
  "productId",
  "discountBps",
  "taxRateBps",
  "taxCode",
  "createdAt",
] as const;

/**
 * A `NAMES.tables` entry for a line table called `name`. The app's own line
 * table can stand in; it may lack the product, discount, tax and creation
 * columns, and its product type may be an enum.
 */
export function lineTableSpec(name: string): BlockSqlTableSpec {
  return {
    name,
    app: {},
    lifecycle: { tenant: "tenant", export: true },
    columns: LINE_COLUMNS,
    optional: OPTIONAL_LINE_COLUMNS,
    typed: ["productType"],
  };
}

/**
 * Line column `column` of row `alias` in line table `lines`, or what a read
 * gives when the app's table lacks it.
 */
export function lineColumn(
  ctx: BlockSqlContext,
  lines: string,
  alias: string,
  column: string,
): string {
  return ctx.has(lines, column)
    ? `${alias}.${ctx.col(lines, column)}`
    : (LINE_DEFAULTS[column] ?? "null");
}

/** The columns a copy of lines writes, of the ones line table `lines` has. */
export function lineCopyColumns(
  ctx: BlockSqlContext,
  lines: string,
): readonly string[] {
  return [
    "tenant",
    "parent",
    "productType",
    "productId",
    "description",
    "quantity",
    "unitAmount",
    "discountBps",
    "taxRateBps",
    "taxCode",
    "position",
  ].filter((column) => ctx.has(lines, column));
}

const LINE_KEYS = ["unitAmount", "product", "fields"] as const;

export function lineExtraColumns(
  ctx: BlockSqlContext,
  lines = "lines",
): readonly ExtraColumn[] {
  return ctx.extraColumns(lines, LINE_KEYS, "lineExtraColumns");
}

export const lineFieldsJson = (
  alias: string,
  extras: readonly ExtraColumn[] = [],
): string => extraFieldsJson(alias, extras);

export interface LineItems {
  /** The logical name of the line table. */
  readonly lines: string;
  /** The logical name of the record table that owns the lines. */
  readonly parent: string;
  /** SQL over row alias `p` that is true when the record's lines can't change. */
  readonly frozen?: string;
  /** Extra `set` assignments on the record after a recount, over `v_*` totals. */
  readonly afterTotals?: string;
  /**
   * `false` when the app keeps the record's totals itself: no recount and no
   * totals trigger, and the setter returns the totals the record holds.
   */
  readonly totals?: boolean;
  readonly extras?: readonly ExtraColumn[];
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
    /**
     * A line without `unitAmount` or `description` takes them from here: bigint
     * and text SQL over the line `x.value`, the record's tenant `v_tenant` and
     * currency `v_currency`.
     */
    readonly fallback?: {
      readonly unitAmount: string;
      readonly description: string;
    };
  },
): string {
  const t = ctx.table(items.lines);
  const p = ctx.table(items.parent);
  const c = (column: string): string => ctx.col(items.lines, column);
  const has = (column: string): boolean => ctx.has(items.lines, column);

  const l = (column: string): string =>
    lineColumn(ctx, items.lines, "l", column);

  const pc = (column: string): string => ctx.col(items.parent, column);
  const fn = ctx.fn(options.setter);
  const recount = ctx.fn(`${options.setter}_recount`);
  const trigger = `bsb_${ctx.tableName(items.lines).name}_totals`;
  const list = `round(l.${c("quantity")} * l.${c("unitAmount")})`;

  const discount = has("discountBps")
    ? `round(${list} * ${l("discountBps")} / 10000.0)`
    : "0";

  const tax = has("taxRateBps")
    ? `round((${list} - ${discount}) * ${l("taxRateBps")} / 10000.0)`
    : "0";

  const optional = (
    column: string,
    definition: (name: string) => string = () => "text",
  ): string =>
    has(column) ? `\n  ${c(column)} ${definition(c(column))},` : "";

  const name = ctx.tableName(items.lines).name;
  // The app's line table keeps its line ids: a line moves in place by position,
  // so foreign keys to it survive. The block's own table is replaced outright.
  const replaces = ctx.owns(items.lines);

  const written = (
    [
      ["tenant", "v_tenant"],
      ["parent", "v_parent"],
      ["productType", "x.value -> 'product' ->> 'type'"],
      ["productId", "x.value -> 'product' ->> 'id'"],
      [
        "description",
        options.fallback
          ? `coalesce(x.value ->> 'description', ${options.fallback.description})`
          : "x.value ->> 'description'",
      ],
      ["quantity", "coalesce((x.value ->> 'quantity')::numeric, 1)"],
      [
        "unitAmount",
        options.fallback
          ? `coalesce((x.value ->> 'unitAmount')::bigint, ${options.fallback.unitAmount})`
          : "(x.value ->> 'unitAmount')::bigint",
      ],
      ["discountBps", "coalesce((x.value ->> 'discountBps')::integer, 0)"],
      ["taxRateBps", "coalesce((x.value ->> 'taxRateBps')::integer, 0)"],
      ["taxCode", "x.value ->> 'taxCode'"],
      ["position", "x.ordinality::integer"],
    ] as const
  )
    .filter(([column]) => has(column))
    .map(([column, value]): readonly [string, string] => [
      column,
      column === "productType" ? ctx.cast(items.lines, column, value) : value,
    ]);

  const extras = items.extras ?? [];

  const extrasInsert = insertExtraColumns(
    t,
    extras,
    "(case when jsonb_typeof(x.value -> 'fields') = 'object' then x.value -> 'fields' end)",
  );

  const manages = ctx.manages
    ? `create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("parent")} uuid not null references ${p} (${pc("id")}) on delete cascade,${optional("productType")}${optional("productId")}
  ${c("description")} text not null check (length(${c("description")}) between 1 and 2000),
  ${c("quantity")} numeric(18, 4) not null check (${c("quantity")} > 0),
  ${c("unitAmount")} bigint not null,${optional("discountBps", (bps) => `integer not null default 0 check (${bps} >= 0 and ${bps} <= 10000)`)}${optional("taxRateBps", (bps) => `integer not null default 0 check (${bps} >= 0 and ${bps} <= 100000)`)}${optional("taxCode")}
  ${c("position")} integer not null${has("createdAt") ? `,\n  ${c("createdAt")} timestamptz not null default now()` : ""}${has("productType") && has("productId") ? `,\n  check ((${c("productType")} is null) = (${c("productId")} is null))` : ""}
);
create index if not exists ${sqlIdent(`${name}_parent_idx`)} on ${t} (${c("parent")}, ${c("position")});${
        ctx.owns(items.lines)
          ? ""
          : `\ncreate unique index if not exists ${sqlIdent(`bsb_${name}_position_key`)} on ${t} (${c("parent")}, ${c("position")});`
      }${addExtraColumns(t, extras)}
${lockTable(t, { read: true })}
drop policy if exists ${sqlIdent(`${name}_read`)} on ${t};
create policy ${sqlIdent(`${name}_read`)} on ${t} for select to authenticated
using (exists (select 1 from ${p} x where x.${pc("id")} = ${c("parent")}));
`
    : "";

  const parentHas = (column: string): boolean => ctx.has(items.parent, column);

  const totalsSet = (
    [
      ["listTotal", "v_list"],
      ["discountTotal", "v_discount"],
      ["subtotal", "v_list - v_discount"],
      ["taxTotal", "v_tax"],
      ["total", "v_list - v_discount + v_tax"],
    ] as const
  )
    .filter(([column]) => parentHas(column))
    .map(([column, value]) => `${pc(column)} = ${value}`)
    .join(",\n    ");

  const totalJson = (column: string): string =>
    parentHas(column)
      ? `${sqlString(column)}, x.${pc(column)}::text`
      : column === "listTotal"
        ? `'listTotal', x.${pc("subtotal")}::text`
        : `'discountTotal', '0'`;

  const totalsJson = [
    ["listTotal", "discountTotal"],
    ["subtotal", "taxTotal", "total"],
  ]
    .map((group) => group.map(totalJson).join(", "))
    .join(",\n    ");

  const recounted = items.totals !== false;

  const triggers = recounted
    ? `
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
    ${totalsSet}${items.afterTotals === undefined ? "" : `,\n    ${items.afterTotals}`}
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
`
    : `
-- The app keeps the record's totals, so the block doesn't recount them.
drop trigger if exists ${trigger} on ${t};
drop trigger if exists ${trigger}_insert on ${t};
drop trigger if exists ${trigger}_update on ${t};
drop trigger if exists ${trigger}_delete on ${t};
drop function if exists better_supabase.${trigger}();
drop function if exists ${recount}(uuid);
`;

  return `${manages}${triggers}
-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.${options.fallback ? "\n-- A line without unitAmount or description takes them from its product." : ""}
create or replace function ${fn}(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := ${options.setter}.parent;
  v_tenant ${ctx.idType};
  v_currency text;${extras.length === 0 ? "" : "\n  v_line record;"}
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
  delete from ${t} l where l.${c("parent")} = v_parent${replaces ? "" : ` and l.${c("position")} > jsonb_array_length(coalesce(${options.setter}.lines, '[]'))`};
  begin
    insert into ${t} (${written.map(([column]) => c(column)).join(", ")}${extrasInsert.columns})
    select ${written.map(([, value]) => value).join(",\n      ")}${extrasInsert.values}
    from jsonb_array_elements(coalesce(${options.setter}.lines, '[]')) with ordinality x${
      replaces
        ? ""
        : `\n    on conflict (${c("parent")}, ${c("position")}) do update set ${written
            .filter(
              ([column]) => !["tenant", "parent", "position"].includes(column),
            )
            .map(([column]) => `${c(column)} = excluded.${c(column)}`)
            .join(", ")}`
    };
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    ${fail("LINES_INVALID", "every line needs a description, a positive quantity and a unit amount", "22023")}
  end;${
    extras.length === 0
      ? ""
      : `
  for v_line in select x.value -> 'fields' as fields, x.ordinality::integer as position from jsonb_array_elements(coalesce(${options.setter}.lines, '[]')) with ordinality x where jsonb_typeof(x.value -> 'fields') = 'object' loop${writeExtraColumns(t, extras, "v_line.fields", `x.${c("parent")} = v_parent and x.${c("position")} = v_line.position`).replaceAll("\n", "\n  ")}
  end loop;`
  }
${recounted ? `  perform ${recount}(v_parent);\n` : ""}  return (select jsonb_build_object(
    ${totalsJson},
    'currency', x.${pc("currency")})
    from ${p} x where x.${pc("id")} = v_parent);
end;
$$;
revoke execute on function ${fn}(uuid, jsonb) from public, anon;
grant execute on function ${fn}(uuid, jsonb) to authenticated, service_role;
`;
}

/**
 * The `fallback` of a line that names a catalog variant (`product: { type:
 * "product_variant", id }`, with the catalog's entity renames): the variant's
 * price in the record's currency and its title, or its product's. A variant of
 * another tenant gives neither. The caller lists `catalog` in `integrates`.
 */
export function catalogLineFallback(ctx: BlockSqlContext): {
  readonly unitAmount: string;
  readonly description: string;
} {
  const catalog = ctx.of("catalog");
  const v = (column: string): string => catalog.col("variants", column);
  const pr = (column: string): string => catalog.col("products", column);
  const type = sqlString(catalog.naming.rename("product_variant"));

  const variant = (select: string): string =>
    `(select ${select} from ${catalog.table("variants")} v where x.value -> 'product' ->> 'type' = ${type} and v.${v("id")} = (x.value -> 'product' ->> 'id')::uuid and v.${v("tenant")} = v_tenant)`;

  const title = catalog.has("variants", "title")
    ? `coalesce(v.${v("title")}, (select p.${pr("title")} from ${catalog.table("products")} p where p.${pr("id")} = v.${v("product")}))`
    : `(select p.${pr("title")} from ${catalog.table("products")} p where p.${pr("id")} = v.${v("product")})`;

  return {
    unitAmount: variant(
      `(${catalog.fn("variant_price")}(v.${v("id")}, v_currency) ->> 'amount')::bigint`,
    ),
    description: variant(title),
  };
}

/** The totals columns of a record table, as `create table` lines. */
export function totalColumnsSql(ctx: BlockSqlContext, table: string): string {
  return Object.keys(TOTAL_COLUMNS)
    .filter((column) => ctx.has(table, column))
    .map((column) => `${ctx.col(table, column)} bigint not null default 0`)
    .join(",\n  ");
}
