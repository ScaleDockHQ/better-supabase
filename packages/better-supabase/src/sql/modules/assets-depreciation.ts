import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { booksAccounting } from "../accounting-sources-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The asset columns depreciation reads, by logical name. */
export const DEPRECIATION_COLUMNS = {
  acquisitionCost: "acquisition_cost",
  currency: "currency",
  acquiredOn: "acquired_on",
  usefulLifeMonths: "useful_life_months",
  residualValue: "residual_value",
  depreciationMethod: "depreciation_method",
  depreciationRateBps: "depreciation_rate_bps",
  disposedOn: "disposed_on",
  disposalAmount: "disposal_amount",
} as const;

type DepreciationColumn = keyof typeof DEPRECIATION_COLUMNS;

const COLUMNS: readonly string[] = Object.keys(DEPRECIATION_COLUMNS);

/** The patch keys `update_asset` takes for an asset's book value. */
const PATCH_KEYS = [
  "acquisitionCost",
  "currency",
  "acquiredOn",
  "usefulLifeMonths",
  "residualValue",
  "depreciationMethod",
  "depreciationRateBps",
] as const;

const METHODS = ["none", "straight_line", "declining_balance"] as const;

/**
 * Whether the module renders depreciation: in managed SQL, with every
 * depreciation column on the assets table (an app that maps one to `null` gets
 * none).
 */
export function depreciates(ctx: BlockSqlContext): boolean {
  return ctx.manages && COLUMNS.every((column) => ctx.has("assets", column));
}

/** The depreciation columns on the assets table and the depreciations table. */
export function depreciationTables(ctx: BlockSqlContext): string {
  if (!depreciates(ctx)) {
    return "";
  }

  const assets = ctx.table("assets");
  const depreciations = ctx.table("depreciations");
  const s = (column: string): string => ctx.col("assets", column);
  const d = (column: string): string => ctx.col("depreciations", column);
  const read = ctx.permission("read", moduleOperations("assets").read);
  const methods = METHODS.map((method) => `'${method}'`).join(", ");

  const add = (logical: DepreciationColumn, definition: string): string =>
    `alter table ${assets} add column if not exists ${s(logical)} ${definition};`;

  return `
-- What an asset cost and how it depreciates, in bigint minor units of currency.
${add("acquisitionCost", `bigint check (${s("acquisitionCost")} >= 0)`)}
${add("currency", `text check (${s("currency")} ~ '^[A-Z]{3}$')`)}
${add("acquiredOn", "date")}
${add("usefulLifeMonths", `integer check (${s("usefulLifeMonths")} between 1 and 1200)`)}
${add("residualValue", `bigint not null default 0 check (${s("residualValue")} >= 0)`)}
${add("depreciationMethod", `text not null default 'none' check (${s("depreciationMethod")} in (${methods}))`)}
-- Declining balance: the yearly rate in basis points of the book value.
${add("depreciationRateBps", `integer check (${s("depreciationRateBps")} between 1 and 100000)`)}
${add("disposedOn", "date")}
${add("disposalAmount", `bigint check (${s("disposalAmount")} >= 0)`)}

-- One month of an asset's depreciation; entry_id is its accounting entry.
create table if not exists ${depreciations} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("asset")} uuid not null references ${assets} (${s("id")}) on delete cascade,
  ${d("periodStart")} date not null check (extract(day from ${d("periodStart")}) = 1),
  ${d("amount")} bigint not null check (${d("amount")} > 0),
  ${d("entry")} uuid,
  ${d("createdAt")} timestamptz not null default now(),
  unique (${d("asset")}, ${d("periodStart")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("depreciations").name}_tenant_idx`)} on ${depreciations} (${d("tenant")}, ${d("periodStart")});
${lockModuleTable(ctx, "depreciations", { read: true })}
${renderPolicy(
  makePolicy({
    table: depreciations,
    name: sqlIdent(`${ctx.tableName("depreciations").name}_read`),
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(d("tenant"), read),
  }),
  { drop: true, target: depreciations },
)}
`;
}

/** `|| jsonb_build_object(...)` of an asset row's book value columns. */
export function depreciationJson(ctx: BlockSqlContext, row: string): string {
  if (!depreciates(ctx)) {
    return "";
  }

  const s = (column: string): string => `${row}.${ctx.col("assets", column)}`;

  return ` || jsonb_build_object('acquisitionCost', ${s("acquisitionCost")}::text, 'currency', ${s("currency")}, 'acquiredOn', ${s("acquiredOn")}, 'usefulLifeMonths', ${s("usefulLifeMonths")}, 'residualValue', ${s("residualValue")}::text, 'depreciationMethod', ${s("depreciationMethod")}, 'depreciationRateBps', ${s("depreciationRateBps")}, 'disposedOn', ${s("disposedOn")}, 'disposalAmount', ${s("disposalAmount")}::text)`;
}

/** `|| jsonb_build_object(...)` of what an asset has depreciated so far. */
export function bookValueJson(ctx: BlockSqlContext, row: string): string {
  if (!depreciates(ctx)) {
    return "";
  }

  const s = (column: string): string => `${row}.${ctx.col("assets", column)}`;
  const d = (column: string): string => ctx.col("depreciations", column);

  return ` || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when ${s("acquisitionCost")} is null then null else (${s("acquisitionCost")} - q.total)::text end) from (select coalesce(sum(y.${d("amount")}), 0) as total from ${ctx.table("depreciations")} y where y.${d("asset")} = ${s("id")}) q)`;
}

/**
 * The `update_asset` lines for the book value keys: their `set` clauses and the
 * checks that run on the updated row, `v_row`.
 */
export function depreciationPatch(
  ctx: BlockSqlContext,
  patch: string,
): { readonly before: string; readonly set: string; readonly after: string } {
  const keys = `array[${PATCH_KEYS.map((key) => `'${key}'`).join(", ")}]`;

  if (!depreciates(ctx)) {
    return {
      before: `
  if ${patch} ?| ${keys} then
    ${fail("ASSETS_DEPRECIATION_UNSUPPORTED", "this assets table has no depreciation columns", "22023")}
  end if;`,
      set: "",
      after: "",
    };
  }

  const s = (column: string): string => ctx.col("assets", column);
  const d = (column: string): string => ctx.col("depreciations", column);

  const invalid = (message: string): string =>
    fail("ASSETS_DEPRECIATION_INVALID", message, "22023");

  const set = (key: DepreciationColumn, value: string): string =>
    `\n    ${s(key)} = case when ${patch} ? '${key}' then ${value} else x.${s(key)} end,`;

  return {
    before: `
  if v_row.${s("disposedOn")} is not null and (
    ${patch} ?| ${keys} or coalesce(${patch} ->> 'status', 'retired') <> 'retired'
  ) then
    ${fail("ASSETS_DISPOSED", "a disposed asset stays retired and its book value can't change", "55000")}
  end if;
  if ${patch} ? 'currency' and not ${patch} ? 'acquisitionCost' and v_row.${s("acquisitionCost")} is not null
    and upper(${patch} ->> 'currency') is distinct from v_row.${s("currency")} then
    ${invalid("the amounts are in another currency than the asset's cost")}
  end if;
  if (
    (${patch} ? 'acquisitionCost' and (${patch} ->> 'acquisitionCost')::bigint is distinct from v_row.${s("acquisitionCost")})
    or (${patch} ? 'currency' and upper(${patch} ->> 'currency') is distinct from v_row.${s("currency")})
    or (${patch} ? 'acquiredOn' and (${patch} ->> 'acquiredOn')::date is distinct from v_row.${s("acquiredOn")})
  ) and exists (
    select 1 from ${ctx.table("depreciations")} y where y.${d("asset")} = v_row.${s("id")}
  ) then
    ${fail("ASSETS_DEPRECIATION_STARTED", "the cost, currency and acquisition date are fixed once the asset has depreciated", "55000")}
  end if;`,
    set: [
      set("acquisitionCost", `(${patch} ->> 'acquisitionCost')::bigint`),
      set("currency", `upper(${patch} ->> 'currency')`),
      set("acquiredOn", `(${patch} ->> 'acquiredOn')::date`),
      set("usefulLifeMonths", `(${patch} ->> 'usefulLifeMonths')::integer`),
      set(
        "residualValue",
        `coalesce((${patch} ->> 'residualValue')::bigint, 0)`,
      ),
      set(
        "depreciationMethod",
        `coalesce(${patch} ->> 'depreciationMethod', 'none')`,
      ),
      set(
        "depreciationRateBps",
        `(${patch} ->> 'depreciationRateBps')::integer`,
      ),
    ].join(""),
    after: `
  if v_row.${s("acquisitionCost")} is not null and v_row.${s("currency")} is null then
    ${invalid("an acquisition cost needs a currency")}
  end if;
  if v_row.${s("residualValue")} > coalesce(v_row.${s("acquisitionCost")}, 0) and v_row.${s("depreciationMethod")} <> 'none' then
    ${invalid("the residual value is more than the acquisition cost")}
  end if;
  if v_row.${s("depreciationMethod")} <> 'none' and (v_row.${s("acquisitionCost")} is null or v_row.${s("acquiredOn")} is null) then
    ${invalid("depreciation needs an acquisition cost and date")}
  end if;
  if v_row.${s("depreciationMethod")} = 'straight_line' and v_row.${s("usefulLifeMonths")} is null then
    ${invalid("straight-line depreciation needs a useful life")}
  end if;
  if v_row.${s("depreciationMethod")} = 'declining_balance' and v_row.${s("depreciationRateBps")} is null then
    ${invalid("declining-balance depreciation needs a rate")}
  end if;`,
  };
}

/**
 * `asset_depreciate` books an asset's months up to a date,
 * `run_asset_depreciation` runs it for every asset, `dispose_asset` takes an
 * asset off the books and `list_asset_depreciations` reads the months.
 */
export function depreciationFunctions(ctx: BlockSqlContext): string {
  if (!depreciates(ctx)) {
    return "";
  }

  const assets = ctx.table("assets");
  const depreciations = ctx.table("depreciations");
  const assignments = ctx.table("assignments");
  const s = (column: string): string => ctx.col("assets", column);
  const d = (column: string): string => ctx.col("depreciations", column);
  const g = (column: string): string => ctx.col("assignments", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("assets");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const books = booksAccounting(ctx);

  const post = (source: string, id: string): string =>
    `${ctx.of("accounting").fn("accounting_post_source")}('${source}', ${id}::text)`;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const readsAsset = (row: string): string =>
    `(${allowed(`${row}.${s("tenant")}`, read)} or (${row}.${s("assigneeType")} = 'member' and coalesce(${row}.${s("assigneeId")} = auth.uid()::text, false)))`;

  const assetMissing = fail("ASSETS_NOT_FOUND", "asset not found", "P0002");

  const depreciationJsonOf = (row: string, currency: string): string =>
    `jsonb_build_object('id', ${row}.${d("id")}, 'organizationId', ${row}.${d("tenant")}, 'assetId', ${row}.${d("asset")}, 'periodStart', ${row}.${d("periodStart")}, 'amount', ${row}.${d("amount")}::text, 'currency', ${currency}, 'entryId', ${row}.${d("entry")}, 'createdAt', ${row}.${d("createdAt")})`;

  const months = (from: string, to: string): string =>
    `((extract(year from ${to}) - extract(year from ${from})) * 12 + extract(month from ${to}) - extract(month from ${from}))::integer`;

  return `
-- Books an asset's depreciation for every month that ended on or before
-- until, from the month it was acquired in and stopping at the month it was
-- disposed of in. Straight line spreads the cost less the residual value over
-- the useful life; declining balance takes the yearly rate of the book value,
-- and writes the rest down at the end of the useful life when there is one.
-- A month books what the method has reached less what is booked, so a changed
-- life or residual value catches up in the next month. Returns the months
-- booked.
create or replace function ${fn("asset_depreciate")}(asset_id uuid, until date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_asset ${assets}%rowtype;
  v_row ${depreciations}%rowtype;
  v_start date;
  v_month date;
  v_last date;
  v_booked bigint;
  v_base bigint;
  v_age integer;
  v_amount bigint;${books ? "\n  v_entry uuid;" : ""}
  v_count integer := 0;
begin
  select * into v_asset from ${assets} x where x.${s("id")} = asset_depreciate.asset_id for update;
  if not found or v_asset.${s("depreciationMethod")} = 'none'
    or v_asset.${s("acquisitionCost")} is null or v_asset.${s("acquiredOn")} is null then
    return 0;
  end if;
  select max(y.${d("periodStart")}), coalesce(sum(y.${d("amount")}), 0) into v_last, v_booked
  from ${depreciations} y where y.${d("asset")} = v_asset.${s("id")};
  v_start := date_trunc('month', v_asset.${s("acquiredOn")})::date;
  v_month := coalesce((v_last + interval '1 month')::date, v_start);
  v_base := v_asset.${s("acquisitionCost")} - v_asset.${s("residualValue")};
  while (v_month + interval '1 month' - interval '1 day')::date <= asset_depreciate.until
    and (v_asset.${s("disposedOn")} is null or v_month < date_trunc('month', v_asset.${s("disposedOn")})::date)
    and v_booked < v_base loop
    v_age := ${months("v_start", "v_month")} + 1;
    if v_asset.${s("depreciationMethod")} = 'straight_line' then
      v_amount := least(v_base, round(v_base::numeric * v_age / v_asset.${s("usefulLifeMonths")})::bigint) - v_booked;
    elsif v_asset.${s("usefulLifeMonths")} is not null and v_age >= v_asset.${s("usefulLifeMonths")} then
      v_amount := v_base - v_booked;
    else
      v_amount := least(v_base - v_booked, round((v_asset.${s("acquisitionCost")} - v_booked)::numeric * v_asset.${s("depreciationRateBps")} / 120000)::bigint);
    end if;
    if v_amount > 0 then
      insert into ${depreciations} (${d("tenant")}, ${d("asset")}, ${d("periodStart")}, ${d("amount")})
      values (v_asset.${s("tenant")}, v_asset.${s("id")}, v_month, v_amount)
      returning * into v_row;${
        books
          ? `
      v_entry := ${post("asset_depreciation", `v_row.${d("id")}`)};
      if v_entry is not null then
        update ${depreciations} y set ${d("entry")} = v_entry where y.${d("id")} = v_row.${d("id")}
        returning * into v_row;
      end if;`
          : ""
      }
      ${ctx.record({
        type: "asset.depreciated",
        payload: `jsonb_build_object('organizationId', v_row.${d("tenant")}, 'id', v_row.${d("id")}, 'assetId', v_row.${d("asset")}, 'periodStart', v_row.${d("periodStart")}, 'amount', v_row.${d("amount")}::text, 'currency', v_asset.${s("currency")}, 'entryId', v_row.${d("entry")})`,
        subject: `'assets/' || v_asset.${s("id")}::text`,
        tenant: `v_asset.${s("tenant")}`,
        audit: false,
      })}
      v_booked := v_booked + v_amount;
      v_count := v_count + 1;
    end if;
    v_month := (v_month + interval '1 month')::date;
  end loop;
  return v_count;
end;
$$;
revoke execute on function ${fn("asset_depreciate")}(uuid, date) from public, anon, authenticated;

-- Books depreciation up to until (default today) for every asset in service
-- of an organization, or of every organization with tenant null. Run it
-- monthly from a scheduled job; it books each month once.
create or replace function ${fn("run_asset_depreciation")}(tenant ${idType} default null, until date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_until date := coalesce(run_asset_depreciation.until, current_date);
  v_id uuid;
  v_months integer;
  v_assets integer := 0;
  v_total integer := 0;
begin
  if not ${SERVICE_CALLER} then
    ${fail("ASSETS_FORBIDDEN", "only the service role runs depreciation")}
  end if;
  for v_id in
    select x.${s("id")} from ${assets} x
    where (run_asset_depreciation.tenant is null or x.${s("tenant")} = run_asset_depreciation.tenant)
      and x.${s("depreciationMethod")} <> 'none' and x.${s("disposedOn")} is null
    order by x.${s("tenant")}, x.${s("id")}
  loop
    v_months := ${fn("asset_depreciate")}(v_id, v_until);
    if v_months > 0 then
      v_assets := v_assets + 1;
      v_total := v_total + v_months;
    end if;
  end loop;
  return jsonb_build_object('until', v_until, 'assets', v_assets, 'months', v_total);
end;
$$;
${serviceGrant(`${fn("run_asset_depreciation")}(${idType}, date)`)}

-- Takes an asset off the books on disposed_on for amount, the proceeds in
-- currency (the asset's): books depreciation through the month before, then
-- retires and releases the asset and books the disposal, the proceeds less
-- the book value being a gain or a loss.
create or replace function ${fn("dispose_asset")}(asset_id uuid, disposed_on date, amount bigint default 0, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assets}%rowtype;${books ? "\n  v_entry uuid;" : ""}
begin
  select * into v_row from ${assets} x where x.${s("id")} = dispose_asset.asset_id for update;
  if not found or not ${readsAsset("v_row")} then
    ${assetMissing}
  end if;
  if not ${allowed(`v_row.${s("tenant")}`, manage)} then
    ${fail("ASSETS_FORBIDDEN", "not allowed to manage assets")}
  end if;
  if v_row.${s("disposedOn")} is not null then
    ${fail("ASSETS_DISPOSED", "the asset is already disposed of", "55000")}
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row.${s("acquiredOn")}, dispose_asset.disposed_on) then
    ${fail("ASSETS_DISPOSAL_INVALID", "a disposal needs a date on or after the acquisition and proceeds of 0 or more", "22023")}
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row.${s("currency")} is null or upper(coalesce(dispose_asset.currency, v_row.${s("currency")})) <> v_row.${s("currency")}
  ) then
    ${fail("ASSETS_DISPOSAL_INVALID", "the proceeds need to be in the asset's currency", "22023")}
  end if;
  perform ${fn("asset_depreciate")}(v_row.${s("id")}, (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update ${assignments} y set ${g("releasedAt")} = now()
  where y.${g("asset")} = v_row.${s("id")} and y.${g("releasedAt")} is null;
  update ${assets} x set
    ${s("disposedOn")} = dispose_asset.disposed_on,
    ${s("disposalAmount")} = coalesce(dispose_asset.amount, 0),
    ${s("status")} = ${ctx.cast("assets", "status", "'retired'")},
    ${s("assigneeType")} = null,
    ${s("assigneeId")} = null,${ctx.has("assets", "retiredAt") ? `\n    ${s("retiredAt")} = coalesce(x.${s("retiredAt")}, now()),` : ""}
    ${s("updatedAt")} = now()
  where x.${s("id")} = v_row.${s("id")}
  returning * into v_row;${books ? `\n  v_entry := ${post("asset_disposal", `v_row.${s("id")}`)};` : ""}
  ${ctx.record({
    type: "asset.disposed",
    payload: `jsonb_build_object('organizationId', v_row.${s("tenant")}, 'id', v_row.${s("id")}, 'disposedOn', v_row.${s("disposedOn")}, 'amount', v_row.${s("disposalAmount")}::text, 'currency', v_row.${s("currency")}, 'entryId', ${books ? "v_entry" : "null::uuid"})`,
    subject: `'assets/' || v_row.${s("id")}::text`,
    tenant: `v_row.${s("tenant")}`,
    audit: {
      category: "data",
      targetType: "asset",
      recordId: `v_row.${s("id")}::text`,
      targetLabel: `v_row.${s("name")}`,
      summary: "'disposed of asset'",
    },
  })}
  return ${fn("get_asset")}(v_row.${s("id")});
end;
$$;
${userGrant(`${fn("dispose_asset")}(uuid, date, bigint, text)`)}

-- An asset's depreciation, oldest month first.
create or replace function ${fn("list_asset_depreciations")}(asset_id uuid, page_size integer default 600)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assets}%rowtype;
begin
  select * into v_row from ${assets} x where x.${s("id")} = list_asset_depreciations.asset_id;
  if not found or not ${readsAsset("v_row")} then
    ${assetMissing}
  end if;
  return (
    select coalesce(jsonb_agg(${depreciationJsonOf("q", `v_row.${s("currency")}`)} order by q.${d("periodStart")}), '[]'::jsonb)
    from (
      select * from ${depreciations} y where y.${d("asset")} = v_row.${s("id")}
      order by y.${d("periodStart")}
      limit greatest(1, least(coalesce(list_asset_depreciations.page_size, 600), 1200))
    ) q
  );
end;
$$;
${userGrant(`${fn("list_asset_depreciations")}(uuid, integer)`)}
`;
}

/**
 * What assets books in accounting: each month of depreciation, and each
 * disposal with its gain or loss.
 */
export function assetAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  if (!depreciates(ctx)) {
    return [];
  }

  const assets = ctx.table("assets");
  const depreciations = ctx.table("depreciations");
  const s = (column: string): string => ctx.col("assets", column);
  const d = (column: string): string => ctx.col("depreciations", column);
  const label = `coalesce(${ctx.has("assets", "tag") ? `a.${s("tag")} || ' ' || ` : ""}a.${s("name")}, a.${s("name")})`;

  return [
    {
      source: "asset_depreciation",
      journal: "general",
      fn: "accounting_asset_depreciation_lines",
      comment:
        "The entry of a month of an asset's depreciation for accounting:\ndepreciation expense against accumulated depreciation.",
      body: `  select jsonb_build_object(
    'organizationId', y.${d("tenant")},
    'entryDate', (y.${d("periodStart")} + interval '1 month' - interval '1 day')::date,
    'currency', a.${s("currency")},
    'reference', left(${label}, 200),
    'memo', left('Depreciation of ' || a.${s("name")} || ' for ' || to_char(y.${d("periodStart")}, 'YYYY-MM'), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'depreciation_expense', 'debit', y.${d("amount")}::text),
      jsonb_build_object('role', 'accumulated_depreciation', 'credit', y.${d("amount")}::text))
  )
  from ${depreciations} y join ${assets} a on a.${s("id")} = y.${d("asset")}
  where y.${d("id")}::text = source_id`,
    },
    {
      source: "asset_disposal",
      journal: "general",
      fn: "accounting_asset_disposal_lines",
      comment:
        "The entry of an asset's disposal for accounting: the proceeds to bank and\nthe accumulated depreciation against the cost, the difference a gain or a loss.",
      body: `  select jsonb_build_object(
    'organizationId', a.${s("tenant")},
    'entryDate', a.${s("disposedOn")},
    'currency', a.${s("currency")},
    'reference', left(${label}, 200),
    'memo', left('Disposal of ' || a.${s("name")}, 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', a.${s("disposalAmount")}::text),
      jsonb_build_object('role', 'accumulated_depreciation', 'debit', q.total::text),
      jsonb_build_object('role', 'fixed_asset', 'credit', a.${s("acquisitionCost")}::text),
      jsonb_build_object('role', 'disposal_gain', 'credit', greatest(q.result, 0)::text),
      jsonb_build_object('role', 'disposal_loss', 'debit', greatest(-q.result, 0)::text))
  )
  from ${assets} a
  cross join lateral (
    select coalesce(sum(y.${d("amount")}), 0) as total,
      a.${s("disposalAmount")} + coalesce(sum(y.${d("amount")}), 0) - a.${s("acquisitionCost")} as result
    from ${depreciations} y where y.${d("asset")} = a.${s("id")}
  ) q
  where a.${s("id")}::text = source_id and a.${s("disposedOn")} is not null and a.${s("acquisitionCost")} is not null`,
    },
  ];
}
