import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { columns } from "./inventory-stock.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The direction of trade an Intrastat line reports. */
const INTRASTAT_FLOWS = ["arrival", "dispatch"] as const;

/** The member states Intrastat covers, by ISO 3166 alpha-2 code. */
const INTRASTAT_COUNTRIES = [
  "AT",
  "BE",
  "BG",
  "HR",
  "CY",
  "CZ",
  "DK",
  "EE",
  "FI",
  "FR",
  "DE",
  "GR",
  "HU",
  "IE",
  "IT",
  "LV",
  "LT",
  "LU",
  "MT",
  "NL",
  "PL",
  "PT",
  "RO",
  "SK",
  "SI",
  "ES",
  "SE",
] as const;

/** The Intrastat lines table, for the module's names. */
export const INTRASTAT_TABLE = {
  name: "intrastat_lines",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    period: "period",
    flow: "flow",
    source: "source",
    shipmentLine: "shipment_line_id",
    variant: "variant_id",
    tradeCode: "trade_code",
    country: "country",
    netMass: "net_mass_kg",
    quantity: "quantity",
    value: "value",
    currency: "currency",
    createdAt: "created_at",
    updatedAt: "updated_at",
  },
  typed: ["flow", "source"],
} as const;

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

const COUNTRIES = `array[${list(INTRASTAT_COUNTRIES)}]`;

/** Whether the module has the Intrastat table and the shipment lines it reads. */
function intrastatOn(ctx: BlockSqlContext): boolean {
  return (
    ctx.hasTable("intrastatLines") &&
    ctx.hasTable("lines") &&
    ctx.installed("inventory")
  );
}

/** The `intrastat_lines` table (managed mode). */
export function intrastatTable(ctx: BlockSqlContext): string {
  if (!ctx.manages || !intrastatOn(ctx)) {
    return "";
  }

  const t = ctx.table("intrastatLines");
  const i = columns(ctx, "intrastatLines");
  const l = columns(ctx, "lines");
  const catalog = ctx.of("inventory").of("catalog");
  const name = ctx.tableName("intrastatLines").name;
  const read = ctx.permission("read", moduleOperations("shipments").read);
  const policyName = sqlIdent(`${name}_read`);

  return `
-- One line of the monthly Intrastat declaration. A shipment line that leaves for
-- or comes back from another member state is derived into a line by
-- prepare_intrastat; a line of another source (a purchase receipt) is saved by
-- hand and stays when the month is prepared again.
create table if not exists ${t} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("period")} date not null check (${i("period")} = date_trunc('month', ${i("period")})::date),
  ${i("flow")} text not null check (${i("flow")} in (${list(INTRASTAT_FLOWS)})),
  ${i("source")} text not null default 'shipment' check (${i("source")} in ('shipment', 'manual')),
  ${i("shipmentLine")} uuid unique references ${ctx.table("lines")} (${l("id")}) on delete cascade,
  ${i("variant")} uuid references ${catalog.table("variants")} (${catalog.col("variants", "id")}) on delete set null,
  ${i("tradeCode")} text check (${i("tradeCode")} is null or ${i("tradeCode")} ~ '^[0-9]{4,10}$'),
  ${i("country")} char(2) check (${i("country")} is null or ${i("country")} ~ '^[A-Z]{2}$'),
  ${i("netMass")} numeric(20, 3) check (${i("netMass")} is null or ${i("netMass")} >= 0),
  ${i("quantity")} numeric(20, 6) check (${i("quantity")} is null or ${i("quantity")} > 0),
  ${i("value")} bigint check (${i("value")} is null or ${i("value")} >= 0),
  ${i("currency")} char(3) check (${i("currency")} is null or ${i("currency")} ~ '^[A-Z]{3}$'),
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`${name}_period_idx`)} on ${t} (${i("tenant")}, ${i("period")});
${lockModuleTable(ctx, "intrastatLines", { read: true })}
drop policy if exists ${policyName} on ${t};
${renderPolicy(makePolicy({ table: t, name: policyName, command: "select", roles: ["authenticated"], using: ctx.scope.check(i("tenant"), read) }), { target: t })}
`;
}

/** `prepare_intrastat` and the functions that save and delete manual lines. */
export function intrastatFunctions(ctx: BlockSqlContext): string {
  if (!intrastatOn(ctx)) {
    return "";
  }

  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("intrastatLines");
  const i = columns(ctx, "intrastatLines");
  const l = columns(ctx, "lines");
  const h = columns(ctx, "shipments");
  const shipments = ctx.table("shipments");
  const lines = ctx.table("lines");
  const catalog = ctx.of("inventory").of("catalog");
  const v = columns(catalog, "variants");
  const manage = ctx.permission("manage", moduleOperations("shipments").manage);

  const allowed = (tenant: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, manage)})`;

  const tradeCode = catalog.has("variants", "tradeCode")
    ? `cv.${v("tradeCode")}`
    : "null::text";

  const weight = catalog.has("variants", "weight")
    ? `cv.${v("weight")}`
    : "null::integer";

  const lineJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${i("id")}, 'period', ${row}.${i("period")}, 'flow', ${row}.${i("flow")}, 'source', ${row}.${i("source")},
      'shipmentLineId', ${row}.${i("shipmentLine")}, 'variantId', ${row}.${i("variant")}, 'tradeCode', ${row}.${i("tradeCode")}, 'country', ${row}.${i("country")},
      'netMassKg', ${row}.${i("netMass")}::text, 'quantity', ${row}.${i("quantity")}::text, 'value', ${row}.${i("value")}::text, 'currency', ${row}.${i("currency")})`;

  return `
-- Derives the Intrastat lines of a month (period is any date in it) from the
-- shipment lines moved in it, and lists them with their exceptions. An outbound
-- line to another member state is a dispatch and a return line from one an
-- arrival; the partner country is the shipment's destination, and the shipment's
-- own country (its from address) is left out. Trade code and net mass come from
-- the variant (mass is its weight times the quantity), value from the line's
-- detail or, in a known currency, the variant's price; a line's detail can
-- carry netMassKg, value and currency instead. A line that lacks a trade code,
-- a country, a net mass or a value is an exception. Preparing again replaces the
-- derived lines of the month and keeps the manual ones. Returns { period,
-- lines, exceptions }.
create or replace function ${fn("prepare_intrastat")}(tenant ${ctx.idType}, period date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start date := date_trunc('month', prepare_intrastat.period)::date;
begin
  if not ${allowed("prepare_intrastat.tenant")} then
    ${fail("SHIPMENT_FORBIDDEN", "not allowed to manage shipments")}
  end if;
  if prepare_intrastat.period is null then
    ${fail("SHIPMENT_INTRASTAT_INVALID", "name the month to prepare", "22023")}
  end if;
  delete from ${t} x where x.${i("tenant")} = prepare_intrastat.tenant and x.${i("period")} = v_start and x.${i("source")} = 'shipment';
  insert into ${t} (${i("tenant")}, ${i("period")}, ${i("flow")}, ${i("source")}, ${i("shipmentLine")}, ${i("variant")}, ${i("tradeCode")}, ${i("country")}, ${i("netMass")}, ${i("quantity")}, ${i("value")}, ${i("currency")})
  select s.tenant, v_start, s.flow, 'shipment', s.line, s.variant, s.trade_code, s.partner, s.net_mass, s.quantity, s.value, s.currency
  from (
    select sl.${l("tenant")} as tenant, sl.${l("id")} as line, sl.${l("variant")} as variant, sl.${l("quantity")} as quantity,
      case when sl.${l("direction")} = 'return' then 'arrival' else 'dispatch' end as flow,
      upper(sh.${h("toAddress")} ->> 'country') as partner,
      upper(sh.${h("fromAddress")} ->> 'country') as own,
      ${tradeCode} as trade_code,
      coalesce(nullif(sl.${l("detail")} ->> 'netMassKg', '')::numeric, case when ${weight} is not null then round(${weight}::numeric * sl.${l("quantity")} / 1000, 3) end) as net_mass,
      coalesce(nullif(sl.${l("detail")} ->> 'currency', ''), sh.${h("currency")}) as currency,
      coalesce(nullif(sl.${l("detail")} ->> 'value', '')::bigint, (select round((${catalog.fn("variant_price")}(sl.${l("variant")}, coalesce(nullif(sl.${l("detail")} ->> 'currency', ''), sh.${h("currency")}), null, null) ->> 'amount')::numeric * sl.${l("quantity")})::bigint
        where coalesce(nullif(sl.${l("detail")} ->> 'currency', ''), sh.${h("currency")}) is not null)) as value
    from ${lines} sl
    join ${shipments} sh on sh.${h("id")} = sl.${l("shipment")}
    left join ${catalog.table("variants")} cv on cv.${v("id")} = sl.${l("variant")}
    where sl.${l("tenant")} = prepare_intrastat.tenant and sl.${l("movedAt")} is not null and sh.${h("cancelledAt")} is null
      and sl.${l("movedAt")} >= v_start::timestamptz and sl.${l("movedAt")} < (v_start + interval '1 month')::timestamptz
  ) s
  where s.partner = any (${COUNTRIES}) and s.partner is distinct from s.own;
  return jsonb_build_object(
    'period', v_start,
    'lines', (select coalesce(jsonb_agg(${lineJson("x")} order by x.${i("flow")}, x.${i("tradeCode")} nulls first, x.${i("createdAt")}, x.${i("id")}), '[]'::jsonb) from ${t} x
      where x.${i("tenant")} = prepare_intrastat.tenant and x.${i("period")} = v_start),
    'exceptions', (select coalesce(jsonb_agg(jsonb_build_object('lineId', e.id, 'shipmentLineId', e.shipment_line, 'variantId', e.variant, 'code', e.code) order by e.code, e.id), '[]'::jsonb)
      from (
        select x.${i("id")} as id, x.${i("shipmentLine")} as shipment_line, x.${i("variant")} as variant, c.code
        from ${t} x
        cross join lateral (values
          ('INTRASTAT_TRADE_CODE_MISSING', x.${i("tradeCode")} is null),
          ('INTRASTAT_COUNTRY_MISSING', x.${i("country")} is null),
          ('INTRASTAT_NET_MASS_MISSING', x.${i("netMass")} is null or x.${i("netMass")} = 0),
          ('INTRASTAT_VALUE_MISSING', x.${i("value")} is null)
        ) c (code, failed)
        where x.${i("tenant")} = prepare_intrastat.tenant and x.${i("period")} = v_start and c.failed
      ) e)
  );
end;
$$;
${userGrant(`${fn("prepare_intrastat")}(${ctx.idType}, date)`)}

-- Saves a line the shipments don't derive, such as a purchase receipt (line
-- null creates one). attrs: { period, flow, country, tradeCode?, netMassKg?,
-- quantity?, value? (minor units as text), currency?, variantId? }. Returns the
-- line's id and whether it was created.
create or replace function ${fn("save_intrastat_line")}(tenant ${ctx.idType}, line uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_attrs jsonb := coalesce(save_intrastat_line.attrs, '{}'::jsonb);
  v_period date;
  v_id uuid;
begin
  if not ${allowed("save_intrastat_line.tenant")} then
    ${fail("SHIPMENT_FORBIDDEN", "not allowed to manage shipments")}
  end if;
  begin
    v_period := date_trunc('month', (v_attrs ->> 'period')::date)::date;
    perform (v_attrs ->> 'netMassKg')::numeric, (v_attrs ->> 'quantity')::numeric, (v_attrs ->> 'value')::bigint, (v_attrs ->> 'variantId')::uuid;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    ${fail("SHIPMENT_INTRASTAT_INVALID", "period is a date and the amounts and variantId are numbers and a uuid", "22023")}
  end;
  if v_period is null or v_attrs ->> 'flow' is null or v_attrs ->> 'flow' not in (${list(INTRASTAT_FLOWS)})
    or coalesce(v_attrs ->> 'country', '') !~ '^[A-Z]{2}$' or not (v_attrs ->> 'country') = any (${COUNTRIES}) then
    ${fail("SHIPMENT_INTRASTAT_INVALID", "a line needs a period, a flow (arrival or dispatch) and the country of a member state", "22023")}
  end if;
  if (v_attrs ->> 'variantId') is not null and not exists (select 1 from ${catalog.table("variants")} cv where cv.${v("id")} = (v_attrs ->> 'variantId')::uuid and cv.${v("tenant")} = save_intrastat_line.tenant) then
    ${fail("SHIPMENT_INTRASTAT_INVALID", "the variant isn't in this organization", "P0002")}
  end if;
  if save_intrastat_line.line is null then
    insert into ${t} as x (${i("tenant")}, ${i("period")}, ${i("flow")}, ${i("source")}, ${i("variant")}, ${i("tradeCode")}, ${i("country")}, ${i("netMass")}, ${i("quantity")}, ${i("value")}, ${i("currency")})
    values (save_intrastat_line.tenant, v_period, v_attrs ->> 'flow', 'manual', nullif(v_attrs ->> 'variantId', '')::uuid, nullif(v_attrs ->> 'tradeCode', ''), v_attrs ->> 'country',
      (v_attrs ->> 'netMassKg')::numeric, (v_attrs ->> 'quantity')::numeric, (v_attrs ->> 'value')::bigint, nullif(v_attrs ->> 'currency', ''))
    returning x.${i("id")} into v_id;
    return jsonb_build_object('id', v_id, 'created', true);
  end if;
  update ${t} x set ${i("period")} = v_period, ${i("flow")} = v_attrs ->> 'flow', ${i("variant")} = nullif(v_attrs ->> 'variantId', '')::uuid, ${i("tradeCode")} = nullif(v_attrs ->> 'tradeCode', ''),
    ${i("country")} = v_attrs ->> 'country', ${i("netMass")} = (v_attrs ->> 'netMassKg')::numeric, ${i("quantity")} = (v_attrs ->> 'quantity')::numeric,
    ${i("value")} = (v_attrs ->> 'value')::bigint, ${i("currency")} = nullif(v_attrs ->> 'currency', ''), ${i("updatedAt")} = now()
  where x.${i("id")} = save_intrastat_line.line and x.${i("tenant")} = save_intrastat_line.tenant and x.${i("source")} = 'manual'
  returning x.${i("id")} into v_id;
  if v_id is null then
    ${fail("SHIPMENT_INTRASTAT_NOT_FOUND", "a manual Intrastat line of this organization wasn't found", "P0002")}
  end if;
  return jsonb_build_object('id', v_id, 'created', false);
end;
$$;
${userGrant(`${fn("save_intrastat_line")}(${ctx.idType}, uuid, jsonb)`)}

-- Deletes a manual line; derived lines come from the shipments.
create or replace function ${fn("delete_intrastat_line")}(line uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${i("tenant")} into v_tenant from ${t} x where x.${i("id")} = delete_intrastat_line.line and x.${i("source")} = 'manual';
  if v_tenant is null then
    return false;
  end if;
  if not ${allowed("v_tenant")} then
    ${fail("SHIPMENT_FORBIDDEN", "not allowed to manage shipments")}
  end if;
  delete from ${t} x where x.${i("id")} = delete_intrastat_line.line;
  return true;
end;
$$;
${userGrant(`${fn("delete_intrastat_line")}(uuid)`)}
`;
}

export function intrastatContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!intrastatOn(ctx)) {
    return [];
  }

  return [
    { name: "prepare_intrastat", args: ["{id}", "date"], returns: "jsonb" },
    {
      name: "save_intrastat_line",
      args: ["{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_intrastat_line", args: ["uuid"], returns: "boolean" },
  ];
}
