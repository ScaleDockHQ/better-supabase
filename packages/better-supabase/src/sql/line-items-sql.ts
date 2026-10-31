import type {
  BlockSqlContext,
  BlockSqlTableSpec,
  ExtraColumn,
} from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";
import { asColumnType } from "./column-type.ts";
import {
  addExtraColumns,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  lockTable,
  triggerGrant,
  updateExtraColumns,
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
  taxCodeId: "null::uuid",
  unitCost: "null::bigint",
  discountAmount: "0",
  costSource: "null::text",
  locationId: "null::uuid",
  binId: "null::uuid",
  billingParty: "'customer'::text",
  billingPartyId: "null::text",
  billingAccountId: "null::uuid",
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
 * The line columns of a document a customer answers: sections, options and the
 * number of periods a subscription line runs.
 */
const DOCUMENT_LINE_COLUMNS = {
  section: "section",
  optional: "optional",
  selected: "selected",
  periods: "periods",
} as const;

/**
 * The line columns of the tax block: a tax code by id, and what the goods cost
 * for a line with a margin-scheme code.
 */
const TAX_LINE_COLUMNS = {
  taxCodeId: "tax_code_id",
  unitCost: "unit_cost",
} as const;

/**
 * The line columns of sales documents (quotes, invoices): a fixed discount next
 * to the percentage, where the goods came from (location and bin), what they
 * cost and how that cost was found, and who pays the line.
 */
const SALES_LINE_COLUMNS = {
  discountAmount: "discount_amount",
  costSource: "cost_source",
  locationId: "location_id",
  binId: "bin_id",
  billingParty: "billing_party",
  billingPartyId: "billing_party_id",
  billingAccountId: "billing_account_id",
} as const;

/** Who can pay a line: `billing_party` on a line takes one of these. */
export const BILLING_PARTIES: readonly string[] = [
  "customer",
  "internal",
  "own_warranty",
  "supplier_warranty",
  "cost_account",
];

/** How a line's `unit_cost` was found. */
export const COST_SOURCES: readonly string[] = [
  "catalog",
  "average",
  "manual",
  "imported",
];

/**
 * A `NAMES.tables` entry for a line table called `name`. The app's own line
 * table can stand in; it may lack the product, discount, tax and creation
 * columns, and its product type may be an enum. `document` adds a section
 * heading and optional lines the customer can take or leave.
 */
export function lineTableSpec(
  name: string,
  options: {
    readonly document?: boolean;
    readonly tax?: boolean;
    readonly sales?: boolean;
  } = {},
): BlockSqlTableSpec {
  return {
    name,
    app: {},
    lifecycle: { tenant: "tenant", export: true },
    columns: {
      ...LINE_COLUMNS,
      ...(options.document === true ? DOCUMENT_LINE_COLUMNS : {}),
      ...(options.tax === true ? TAX_LINE_COLUMNS : {}),
      ...(options.sales === true ? SALES_LINE_COLUMNS : {}),
    },
    optional: [
      ...OPTIONAL_LINE_COLUMNS,
      ...(options.document === true ? Object.keys(DOCUMENT_LINE_COLUMNS) : []),
      ...(options.tax === true ? Object.keys(TAX_LINE_COLUMNS) : []),
      ...(options.sales === true ? Object.keys(SALES_LINE_COLUMNS) : []),
    ],
    typed: ["productType"],
  };
}

/**
 * Whether `table` declares logical `column` and has it. `ctx.has` throws for a
 * column the table doesn't declare, and shared SQL runs over tables that
 * declare different columns.
 */
export function declared(
  ctx: BlockSqlContext,
  table: string,
  column: string,
): boolean {
  return (
    Object.hasOwn(ctx.names.tables[table]?.columns ?? {}, column) &&
    ctx.has(table, column)
  );
}

/**
 * SQL over line alias `alias` that is true when the line counts toward the
 * totals: every line except an optional one the customer didn't take.
 */
export function countedLine(
  ctx: BlockSqlContext,
  lines: string,
  alias: string,
): string {
  if (!declared(ctx, lines, "optional")) {
    return "true";
  }

  const optional = `${alias}.${ctx.col(lines, "optional")}`;

  return declared(ctx, lines, "selected")
    ? `(not ${optional} or ${alias}.${ctx.col(lines, "selected")})`
    : `not ${optional}`;
}

/**
 * A line's amount before discounts: quantity times unit amount, times its
 * periods when the line table counts them, rounded once.
 */
export function lineAmount(
  ctx: BlockSqlContext,
  lines: string,
  alias: string,
): string {
  const periods = declared(ctx, lines, "periods")
    ? ` * coalesce(${alias}.${ctx.col(lines, "periods")}, 1)`
    : "";

  return `round(${alias}.${ctx.col(lines, "quantity")}${periods} * ${alias}.${ctx.col(lines, "unitAmount")})`;
}

/**
 * A line's discount: its percentage of `amount` plus its fixed amount, never
 * more than the amount. A credit line (a negative amount) takes no fixed
 * amount. `percent` is the SQL for the percentage column's value in basis
 * points, or `null` when the table has none.
 */
export function lineDiscount(
  ctx: BlockSqlContext,
  lines: string,
  alias: string,
  amount: string,
  percent: string | null,
): string {
  const share =
    percent === null ? "0" : `round(${amount} * ${percent} / 10000.0)`;

  return declared(ctx, lines, "discountAmount")
    ? `(${share} + least(coalesce(${alias}.${ctx.col(lines, "discountAmount")}, 0), greatest(${amount} - ${share}, 0)))`
    : share;
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
  if (!ctx.has(lines, column)) {
    return LINE_DEFAULTS[column] ?? "null";
  }

  return RATE_COLUMNS.has(column) && percentRates(ctx, lines)
    ? `round(${alias}.${ctx.col(lines, column)} * 100)::integer`
    : `${alias}.${ctx.col(lines, column)}`;
}

const RATE_COLUMNS: ReadonlySet<string> = new Set([
  "discountBps",
  "taxRateBps",
]);

/**
 * `options.lineRates: "percent"`: the app's line table keeps discount and tax
 * rates as percentages, such as `numeric(5, 2)`, which the block reads and
 * writes as basis points.
 */
function percentRates(ctx: BlockSqlContext, lines: string): boolean {
  const raw = ctx.option("lineRates") ?? "bps";

  if (raw !== "bps" && raw !== "percent") {
    throw new TypeError(
      `blocks.${ctx.module}.options.lineRates must be "bps" or "percent"`,
    );
  }

  if (raw === "percent" && ctx.owns(lines)) {
    throw new TypeError(
      `blocks.${ctx.module}.options.lineRates: "percent" needs your own line table, mapped in tables.${lines}`,
    );
  }

  return raw === "percent";
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
    "taxCodeId",
    "unitCost",
    ...Object.keys(SALES_LINE_COLUMNS),
    "position",
    ...Object.keys(DOCUMENT_LINE_COLUMNS),
  ].filter((column) => declared(ctx, lines, column));
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
  /**
   * Whether the record table has a logical column, for a module whose optional
   * columns are opt-in. Defaults to `declared`.
   */
  readonly parentHas?: (column: string) => boolean;
  /** The logical table the recount writes the record's tax per rate to. */
  readonly taxLines?: string;
  /**
   * `false` leaves out the unique `(parent, position)` index on the app's line
   * table, so the app can renumber lines in one update; the setter then updates
   * lines by position and inserts the rest. Default `true`.
   */
  readonly positionKey?: boolean;
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
    /**
     * Also renders `<this>(record, lines)`: the same write without the guard or
     * the frozen check, for the module's own functions only.
     */
    readonly restorer?: string;
    /**
     * Prices catalog variant lines through the discount matrix: a line without
     * `discountBps` takes the matching rule's, and one without `unitAmount` its
     * fixed price. `party` is SQL text for the customer's id and `on` SQL for
     * the pricing date, both over the record `v_parent` and the tenant
     * `v_tenant`. Needs the catalog with its discount tables.
     */
    readonly discountMatrix?: { readonly party: string; readonly on: string };
  },
): string {
  const t = ctx.table(items.lines);
  const p = ctx.table(items.parent);
  const c = (column: string): string => ctx.col(items.lines, column);
  const has = (column: string): boolean => declared(ctx, items.lines, column);

  const l = (column: string): string =>
    lineColumn(ctx, items.lines, "l", column);

  const pc = (column: string): string => ctx.col(items.parent, column);
  const fn = ctx.fn(options.setter);
  const recount = ctx.fn(`${options.setter}_recount`);
  const trigger = `bsb_${ctx.tableName(items.lines).name}_totals`;
  const list = lineAmount(ctx, items.lines, "l");

  const discount = lineDiscount(
    ctx,
    items.lines,
    "l",
    list,
    has("discountBps") ? l("discountBps") : null,
  );

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
  const positionKey = items.positionKey ?? true;

  const matrix = discountMatrixSql(ctx, options.discountMatrix);

  const unitFallback = [
    ...(matrix === undefined ? [] : [matrix.fixedPrice]),
    ...(options.fallback ? [options.fallback.unitAmount] : []),
  ];

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
        unitFallback.length > 0
          ? `coalesce((x.value ->> 'unitAmount')::bigint, ${unitFallback.join(", ")})`
          : "(x.value ->> 'unitAmount')::bigint",
      ],
      [
        "discountBps",
        `coalesce((x.value ->> 'discountBps')::integer, ${matrix === undefined ? "" : `${matrix.discountBps}, `}0)`,
      ],
      ["taxRateBps", "coalesce((x.value ->> 'taxRateBps')::integer, 0)"],
      ["taxCode", "x.value ->> 'taxCode'"],
      ["taxCodeId", "nullif(x.value ->> 'taxCodeId', '')::uuid"],
      ["unitCost", "(x.value ->> 'unitCost')::bigint"],
      ["discountAmount", "coalesce((x.value ->> 'discountAmount')::bigint, 0)"],
      ["costSource", "nullif(x.value ->> 'costSource', '')"],
      ["locationId", "nullif(x.value ->> 'locationId', '')::uuid"],
      ["binId", "nullif(x.value ->> 'binId', '')::uuid"],
      [
        "billingParty",
        "coalesce(nullif(x.value ->> 'billingParty', ''), 'customer')",
      ],
      ["billingPartyId", "nullif(x.value ->> 'billingPartyId', '')"],
      ["billingAccountId", "nullif(x.value ->> 'billingAccountId', '')::uuid"],
      ["section", "nullif(trim(x.value ->> 'section'), '')"],
      ["optional", "coalesce((x.value ->> 'optional')::boolean, false)"],
      [
        "selected",
        "coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false))",
      ],
      ["periods", "coalesce((x.value ->> 'periods')::integer, 1)"],
      ["position", "x.ordinality::integer"],
    ] as const
  )
    .filter(([column]) => has(column))
    .map(([column, value]): readonly [string, string] => [
      column,
      column === "productType"
        ? ctx.cast(items.lines, column, value)
        : column === "productId" && !replaces
          ? asColumnType(t, ctx.colName(items.lines, column), value)
          : RATE_COLUMNS.has(column) && percentRates(ctx, items.lines)
            ? `(${value} / 100.0)`
            : value,
    ]);

  const extras = items.extras ?? [];

  const fieldsOf = (line: string): string =>
    `(case when jsonb_typeof(${line} -> 'fields') = 'object' then ${line} -> 'fields' end)`;

  const extrasInsert = insertExtraColumns(t, extras, fieldsOf("x.value"));

  const manages = ctx.manages
    ? `create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("parent")} uuid not null references ${p} (${pc("id")}) on delete cascade,${optional("productType")}${optional("productId")}
  ${c("description")} text not null check (length(${c("description")}) between 1 and 2000),
  ${c("quantity")} numeric(18, 4) not null check (${c("quantity")} > 0),
  ${c("unitAmount")} bigint not null,${optional("discountBps", (bps) => `integer not null default 0 check (${bps} >= 0 and ${bps} <= 10000)`)}${optional("taxRateBps", (bps) => `integer not null default 0 check (${bps} >= 0 and ${bps} <= 100000)`)}${optional("taxCode")}${optional("taxCodeId", () => "uuid")}${optional("unitCost", () => "bigint")}${optional("discountAmount", (name) => `bigint not null default 0 check (${name} >= 0)`)}${optional("costSource", (name) => `text check (${name} in (${COST_SOURCES.map(sqlString).join(", ")}))`)}${optional("locationId", () => "uuid")}${optional("binId", () => "uuid")}${optional("billingParty", (name) => `text not null default 'customer' check (${name} in (${BILLING_PARTIES.map(sqlString).join(", ")}))`)}${optional("billingPartyId")}${optional("billingAccountId", () => "uuid")}${optional("section", (section) => `text check (length(${section}) between 1 and 300)`)}${optional("optional", () => "boolean not null default false")}${optional("selected", () => "boolean not null default true")}${optional("periods", (periods) => `integer not null default 1 check (${periods} > 0)`)}
  ${c("position")} integer not null${has("createdAt") ? `,\n  ${c("createdAt")} timestamptz not null default now()` : ""}${has("productType") && has("productId") ? `,\n  check ((${c("productType")} is null) = (${c("productId")} is null))` : ""}
);
${has("periods") ? `alter table ${t} add column if not exists ${c("periods")} integer not null default 1 check (${c("periods")} > 0);\n` : ""}create index if not exists ${sqlIdent(`${name}_parent_idx`)} on ${t} (${c("parent")}, ${c("position")});${
        ctx.owns(items.lines) || !positionKey
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

  const recountSql = documentTotals(ctx, items)
    ? documentRecountSql(ctx, items, { setter: options.setter, recount })
    : `
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
`;

  const triggers = recounted
    ? `${recountSql}
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

  const setterSql = (
    name: string,
    guard: string,
    frozen: string | undefined,
    grant: string,
  ): string => `create or replace function ${ctx.fn(name)}(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := ${name}.parent;
  v_tenant ${ctx.idType};
  v_currency text;
begin
  select x.${pc("tenant")}, x.${pc("currency")} into v_tenant, v_currency from ${p} x where x.${pc("id")} = v_parent${frozen === undefined ? "" : ` and not (${frozen.replaceAll("p.", "x.")})`};
  if v_tenant is null then
    ${fail("LINES_RECORD_INVALID", "no such record, or its lines are locked", "P0002")}
  end if;
  ${guard}
  if jsonb_typeof(coalesce(${name}.lines, '[]')) <> 'array' then
    ${fail("LINES_INVALID", "lines must be a list", "22023")}
  end if;
  if exists (select 1 from jsonb_array_elements(${name}.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    ${fail("LINES_CURRENCY", "every line must be in the record's currency", "22023")}
  end if;
  delete from ${t} l where l.${c("parent")} = v_parent${replaces ? "" : ` and l.${c("position")} > jsonb_array_length(coalesce(${name}.lines, '[]'))`};
  begin${
    replaces || positionKey
      ? ""
      : `
    update ${t} l set ${written
      .filter(([column]) => !["tenant", "parent", "position"].includes(column))
      .map(([column, value]) => `${c(column)} = ${value}`)
      .join(", ")}${updateExtraColumns(t, extras, fieldsOf("x.value"), "l")}
    from jsonb_array_elements(coalesce(${name}.lines, '[]')) with ordinality x
    where l.${c("parent")} = v_parent and l.${c("position")} = x.ordinality;`
  }
    insert into ${t}${replaces || !positionKey ? "" : " as l"} (${written.map(([column]) => c(column)).join(", ")}${extrasInsert.columns})
    select ${written.map(([, value]) => value).join(",\n      ")}${extrasInsert.values}
    from jsonb_array_elements(coalesce(${name}.lines, '[]')) with ordinality x${
      replaces
        ? ""
        : positionKey
          ? `\n    on conflict (${c("parent")}, ${c("position")}) do update set ${written
              .filter(
                ([column]) =>
                  !["tenant", "parent", "position"].includes(column),
              )
              .map(([column]) => `${c(column)} = excluded.${c(column)}`)
              .join(", ")}${extras
              .map(
                (extra) =>
                  `, ${extra.ident} = case when ${fieldsOf(`${name}.lines -> (excluded.${c("position")}::integer - 1)`)} ? ${sqlString(extra.name)} then excluded.${extra.ident} else l.${extra.ident} end`,
              )
              .join("")}`
          : `\n    where not exists (select 1 from ${t} l where l.${c("parent")} = v_parent and l.${c("position")} = x.ordinality)`
    };
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    ${fail("LINES_INVALID", "every line needs a description, a positive quantity and a unit amount", "22023")}
  end;
${recounted ? `  perform ${recount}(v_parent);\n` : ""}  return (select jsonb_build_object(
    ${totalsJson},
    'currency', x.${pc("currency")})
    from ${p} x where x.${pc("id")} = v_parent);
end;
$$;
${grant}
`;

  return `${manages}${triggers}
-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.${options.fallback ? "\n-- A line without unitAmount or description takes them from its product." : ""}
${setterSql(
  options.setter,
  options.guard,
  items.frozen,
  `revoke execute on function ${fn}(uuid, jsonb) from public, anon;
grant execute on function ${fn}(uuid, jsonb) to authenticated, service_role;`,
)}${
    options.restorer === undefined
      ? ""
      : `
-- Writes a record's lines like ${options.setter}, without its checks, for the
-- module's own functions.
${setterSql(
  options.restorer,
  "",
  undefined,
  `revoke execute on function ${ctx.fn(options.restorer)}(uuid, jsonb) from public, anon, authenticated;`,
)}`
  }`;
}

/**
 * The SQL of the discount matrix for a line `x.value` that names a catalog
 * variant: its fixed price and its discount in basis points, null for other
 * lines and when no rule matches. Undefined when the catalog has no matrix.
 */
function discountMatrixSql(
  ctx: BlockSqlContext,
  matrix: { readonly party: string; readonly on: string } | undefined,
): { readonly fixedPrice: string; readonly discountBps: string } | undefined {
  if (
    matrix === undefined ||
    !ctx.installed("catalog") ||
    !ctx.of("catalog").hasTable("discountRules")
  ) {
    return undefined;
  }

  const catalog = ctx.of("catalog");
  const type = sqlString(catalog.naming.rename("product_variant"));

  const call = `${catalog.fn("resolve_line_discount")}(v_tenant, ${matrix.party}, (x.value -> 'product' ->> 'id')::uuid, coalesce((x.value ->> 'quantity')::numeric, 1), ${matrix.on}, v_currency)`;

  const rule = (key: string, cast: string): string =>
    `case when x.value -> 'product' ->> 'type' = ${type} then (${call} ->> '${key}')::${cast} end`;

  return {
    fixedPrice: rule("fixedPrice", "bigint"),
    discountBps: rule("discountBps", "integer"),
  };
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

/**
 * Whether a record's totals need the document recount: prices that include tax,
 * a discount on the whole record, optional lines or tax per rate. Without any
 * of them the plain line sums stay, so deals and invoices render as before.
 */
export function documentTotals(
  ctx: BlockSqlContext,
  items: LineItems,
): boolean {
  const parentHas =
    items.parentHas ??
    ((column: string): boolean => declared(ctx, items.parent, column));

  return (
    ["pricesIncludeTax", "discountBps", "discountAmount"].some(parentHas) ||
    declared(ctx, items.lines, "optional") ||
    (items.taxLines !== undefined && ctx.hasTable(items.taxLines))
  );
}

/**
 * The recount of a record whose totals follow its tax rates.
 *
 * Each counted line rounds once to its amount after the line discount. The
 * record discount (basis points of that sum plus a fixed amount, at most the
 * sum) is spread over the rate groups in proportion, the last group taking the
 * rounding, so the groups add up to it exactly. Each group's tax is its lines'
 * tax less the tax on its share of the discount. With prices that include tax,
 * an amount is gross and the tax is the part of it at `rate / (10000 + rate)`;
 * otherwise an amount is net and tax is added on top.
 */
function documentRecountSql(
  ctx: BlockSqlContext,
  items: LineItems,
  options: { readonly setter: string; readonly recount: string },
): string {
  const t = ctx.table(items.lines);
  const p = ctx.table(items.parent);
  const c = (column: string): string => ctx.col(items.lines, column);
  const pc = (column: string): string => ctx.col(items.parent, column);

  const l = (column: string): string =>
    lineColumn(ctx, items.lines, "l", column);

  const parentHas =
    items.parentHas ??
    ((column: string): boolean => declared(ctx, items.parent, column));

  const parent = `${options.setter}_recount.parent`;
  const amount = lineAmount(ctx, items.lines, "l");

  const discount = lineDiscount(
    ctx,
    items.lines,
    "l",
    amount,
    declared(ctx, items.lines, "discountBps") ? l("discountBps") : null,
  );

  const rate = declared(ctx, items.lines, "taxRateBps") ? l("taxRateBps") : "0";

  const code = declared(ctx, items.lines, "taxCode")
    ? `l.${c("taxCode")}`
    : "null::text";

  const counted = countedLine(ctx, items.lines, "l");

  const denominator = (bps: string): string =>
    `case when v_inclusive then 10000.0 + ${bps} else 10000.0 end`;

  const recordValue = (column: string, otherwise: string): string =>
    parentHas(column) ? `x.${pc(column)}` : otherwise;

  const totalsSet = (
    [
      ["listTotal", "v_list"],
      ["discountTotal", "v_discount"],
      ["subtotal", "v_subtotal"],
      ["taxTotal", "v_tax"],
      ["total", "v_total"],
    ] as const
  )
    .filter(([column]) => parentHas(column))
    .map(([column, value]) => `${pc(column)} = ${value}`)
    .join(",\n    ");

  const taxLines =
    items.taxLines !== undefined && ctx.hasTable(items.taxLines)
      ? items.taxLines
      : undefined;

  const tc = (column: string): string =>
    ctx.col(taxLines ?? items.parent, column);

  const taxColumn = (column: string): string =>
    taxLines !== undefined && declared(ctx, taxLines, column)
      ? `, ${tc(column)}`
      : "";

  const taxValue = (column: string, value: string): string =>
    taxLines !== undefined && declared(ctx, taxLines, column)
      ? `, ${value}`
      : "";

  const writeTaxLines =
    taxLines === undefined
      ? ""
      : `
  delete from ${ctx.table(taxLines)} x where x.${tc("parent")} = ${parent};
  insert into ${ctx.table(taxLines)} (${tc("tenant")}, ${tc("parent")}, ${tc("taxRateBps")}${taxColumn("taxCode")}, ${tc("net")}, ${tc("tax")}, ${tc("gross")}${taxColumn("discount")})
  select v_tenant, ${parent}, r.rate${taxValue("taxCode", "r.code")}, r.net, r.tax, r.gross${taxValue("discount", "r.discount")}
  from jsonb_to_recordset(v_groups) r(rate integer, code text, net bigint, tax bigint, gross bigint, discount bigint);`;

  return `
-- Writes a record's totals from its counted lines: an optional line counts
-- only when the customer took it. The record discount is spread over the tax
-- rates in proportion to their amounts, and tax is counted once per rate, so
-- the totals and the tax per rate always add up.
create or replace function ${options.recount}(parent uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_inclusive boolean;
  v_record_bps integer;
  v_record_amount bigint;
  v_list bigint;
  v_line_discount bigint;
  v_net bigint;
  v_record_discount bigint;
  v_groups jsonb;
  v_discount bigint;
  v_subtotal bigint;
  v_tax bigint;
  v_total bigint;
begin
  select x.${pc("tenant")}, ${recordValue("pricesIncludeTax", "false")}, ${recordValue("discountBps", "0")}, ${recordValue("discountAmount", "0")}
    into v_tenant, v_inclusive, v_record_bps, v_record_amount
  from ${p} x where x.${pc("id")} = ${parent};
  select coalesce(sum(${amount}), 0), coalesce(sum(${discount}), 0)
    into v_list, v_line_discount
  from ${t} l where l.${c("parent")} = ${parent} and ${counted};
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select ${rate} as rate, ${code} as code, sum(${amount} - ${discount}) as amount,
      sum(round((${amount} - ${discount}) * ${rate} / ${denominator(rate)})) as tax
    from ${t} l where l.${c("parent")} = ${parent} and ${counted}
    group by 1, 2
  ), shared as (
    select g.rate, g.code, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first rows between unbounded preceding and current row)
  ), taxed as (
    select s.rate, s.code, s.share, s.amount - s.share as amount,
      s.tax - round(s.share * s.rate / ${denominator("s.rate")}) as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rate', x.rate,
      'code', x.code,
      'net', case when v_inclusive then x.amount - x.tax else x.amount end,
      'tax', x.tax,
      'discount', x.share,
      'gross', case when v_inclusive then x.amount else x.amount + x.tax end
    ) order by x.rate, x.code nulls first), '[]'::jsonb)
    into v_groups
  from taxed x;
  select coalesce(sum(r.net), 0), coalesce(sum(r.tax), 0), coalesce(sum(r.gross), 0)
    into v_subtotal, v_tax, v_total
  from jsonb_to_recordset(v_groups) r(net bigint, tax bigint, gross bigint);
  v_discount := v_line_discount + v_record_discount;${writeTaxLines}
  update ${p} x set
    ${totalsSet}${items.afterTotals === undefined ? "" : `,\n    ${items.afterTotals}`}
  where x.${pc("id")} = ${parent};
end;
$$;
revoke execute on function ${options.recount}(uuid) from public, anon, authenticated;
`;
}
