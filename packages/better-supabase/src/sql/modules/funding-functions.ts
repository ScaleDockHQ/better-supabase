import type { BlockSqlContext } from "../context.ts";

import {
  fail,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import {
  AWARD_RESERVED,
  awardJson,
  awardRecord,
  DELIVERY_SOURCES,
  deliveryJson,
  fundingKeys,
  notifyFunding,
  PERIODS,
  periodEnd,
  periodStart,
  productJson,
  sqlList,
  UNITS,
} from "./funding-shared.ts";

/**
 * A condition that holds when `funder` (a uuid expression) is a company or
 * person of `tenant` in contacts that isn't merged away and, when the table
 * keeps roles, holds the `funder` role.
 */
export function funderCheck(
  ctx: BlockSqlContext,
  funder: string,
  tenant: string,
): string {
  const contacts = ctx.of("contacts");

  const party = (table: "companies" | "people"): string => {
    const col = (column: string): string => contacts.col(table, column);

    const merged = contacts.has(table, "mergedInto")
      ? ` and x.${col("mergedInto")} is null`
      : "";

    const role = contacts.has(table, "roles")
      ? ` and 'funder' = any (x.${col("roles")})`
      : "";

    return `exists (select 1 from ${contacts.table(table)} x where x.${col("id")} = ${funder} and x.${col("tenant")} = ${tenant}${merged}${role})`;
  };

  return `(${party("companies")} or ${party("people")})`;
}

/** The product, award and delivery functions. */
export function fundingFunctions(ctx: BlockSqlContext): string {
  const products = ctx.table("products");
  const awards = ctx.table("awards");
  const deliveries = ctx.table("deliveries");
  const p = (column: string): string => ctx.col("products", column);
  const w = (column: string): string => ctx.col("awards", column);
  const d = (column: string): string => ctx.col("deliveries", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const { write, register, approve, manage } = fundingKeys(ctx);
  const notifies = ctx.installed("notifications");

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const insertCol = (table: string, column: string): string =>
    has(table, column) ? `, ${ctx.col(table, column)}` : "";

  const insertVal = (table: string, column: string, value: string): string =>
    has(table, column) ? `, ${value}` : "";

  const touch = (table: string): string =>
    has(table, "updatedAt") ? `, ${ctx.col(table, "updatedAt")} = now()` : "";

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("FUNDING_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("FUNDING_INVALID", message, "22023");

  const productNotFound = fail(
    "FUNDING_PRODUCT_NOT_FOUND",
    "funding product not found",
    "P0002",
  );

  const awardNotFound = fail(
    "FUNDING_AWARD_NOT_FOUND",
    "funding award not found",
    "P0002",
  );

  const deliveryNotFound = fail(
    "FUNDING_DELIVERY_NOT_FOUND",
    "funding delivery not found",
    "P0002",
  );

  const funderInvalid = fail(
    "FUNDING_FUNDER_INVALID",
    "the funder is a company or person in this organization's contacts with the funder role",
    "22023",
  );

  const extras = ctx.extraColumns("awards", AWARD_RESERVED);

  const fieldsCheck = (attrs: string): string =>
    extras.length === 0
      ? ""
      : `if ${attrs} ? 'fields' and jsonb_typeof(${attrs} -> 'fields') <> 'object' then
    ${invalid("fields is an object")}
  end if;`;

  const writeFields = (attrs: string): string =>
    writeExtraColumns(
      awards,
      extras,
      `coalesce(${attrs} -> 'fields', '{}'::jsonb)`,
      `x.${w("id")} = v_row.${w("id")}`,
      "v_row",
    );

  const value = (attrs: string, key: string): string =>
    `nullif(trim(${attrs} ->> '${key}'), '')`;

  // A key attrs leaves out keeps `fallback`.
  const pick = (
    attrs: string,
    key: string,
    read: string,
    fallback: string,
  ): string =>
    `case when ${attrs} ? '${key}' then ${read} else ${fallback} end`;

  const awardFields = (attrs: string, row: string | undefined): string => {
    const keep = (column: string): string =>
      row === undefined ? "null" : `${row}.${w(column)}`;

    return `v_funder := ${pick(attrs, "funderId", `${value(attrs, "funderId")}::uuid`, keep("funder"))};
  v_product := ${pick(attrs, "productId", `${value(attrs, "productId")}::uuid`, keep("product"))};
  v_units := ${pick(attrs, "units", `${value(attrs, "units")}::numeric`, keep("units"))};
  v_period := ${pick(attrs, "period", value(attrs, "period"), keep("period"))};
  v_starts := ${pick(attrs, "startsOn", `${value(attrs, "startsOn")}::date`, keep("startsOn"))};
  v_ends := ${pick(attrs, "endsOn", `${value(attrs, "endsOn")}::date`, keep("endsOn"))};
  v_reference := ${pick(attrs, "reference", value(attrs, "reference"), keep("reference"))};
  v_status := ${pick(attrs, "status", value(attrs, "status"), row === undefined ? "'active'" : keep("status"))};`;
  };

  const awardChecks = (
    tenant: string,
  ): string => `if v_funder is null or not ${funderCheck(ctx, "v_funder", tenant)} then
    ${funderInvalid}
  end if;
  if v_product is null or not exists (select 1 from ${products} x where x.${p("id")} = v_product and x.${p("tenant")} = ${tenant}) then
    ${productNotFound}
  end if;
  if v_units is null or v_units <= 0 then
    ${invalid("an award needs units above zero")}
  end if;
  if v_period is null or v_period not in ${sqlList(PERIODS)} then
    ${invalid("period is week, month or total")}
  end if;
  if v_starts is null then
    ${invalid("an award needs a start date")}
  end if;
  if v_ends is not null and v_ends < v_starts then
    ${invalid("an award ends on or after its start date")}
  end if;
  if v_reference is not null and length(v_reference) > 200 then
    ${invalid("reference is at most 200 characters")}
  end if;
  if v_status is null or v_status not in ('requested', 'active') then
    ${invalid("a saved award is requested or active; end_funding_award ends it")}
  end if;`;

  const awardSets = [
    `${w("funder")} = v_funder`,
    `${w("product")} = v_product`,
    `${w("units")} = v_units`,
    `${w("period")} = v_period`,
    `${w("startsOn")} = v_starts`,
    `${w("endsOn")} = v_ends`,
    `${w("reference")} = v_reference`,
    `${w("status")} = v_status`,
  ].join(",\n    ");

  const productChecks = `if v_code is null or length(v_code) > 50 then
    ${invalid("a product needs a code of at most 50 characters")}
  end if;
  if v_title is null or length(v_title) > 300 then
    ${invalid("a product needs a title of at most 300 characters")}
  end if;
  if v_unit is null or v_unit not in ${sqlList(UNITS)} then
    ${invalid("unit is minute, hour, day_part, day, visit or piece")}
  end if;
  if save_funding_product.rate is null or save_funding_product.rate < 0 then
    ${invalid("a rate is zero or more minor units")}
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    ${invalid("currency is a three-letter ISO 4217 code")}
  end if;
  if save_funding_product.valid_until < save_funding_product.valid_from then
    ${invalid("a product is valid until on or after it is valid from")}
  end if;`;

  const sourceCheck = (): string => {
    const check = (
      module: "time-tracking" | "bookings",
      logical: string,
      source: string,
    ): string => {
      if (!ctx.installed(module) || ctx.of(module).mode === "custom") {
        return "";
      }

      const other = ctx.of(module);

      return `
  if v_source = '${source}' and not exists (
    select 1 from ${other.table(logical)} x
    where x.${other.col(logical, "id")}::text = v_source_id and x.${other.col(logical, "tenant")} = v_award.${w("tenant")}
  ) then
    ${invalid(`the ${source.replace("_", " ")} isn't in this organization`)}
  end if;`;
    };

    return `${check("time-tracking", "entries", "time_entry")}${check("bookings", "bookings", "booking")}`;
  };

  const exceeded = `v_start := ${periodStart(ctx, "v_award", `v_row.${d("deliveredOn")}`)};
  select coalesce(sum(x.${d("units")}), 0) into v_used from ${deliveries} x
  where x.${d("tenant")} = v_award.${w("tenant")} and x.${d("award")} = v_award.${w("id")} and x.${d("status")} <> 'rejected'
    and x.${d("deliveredOn")} >= v_start and x.${d("deliveredOn")} < ${periodEnd(ctx, "v_award", "v_start")};
  if v_used > v_award.${w("units")} and v_used - v_row.${d("units")} <= v_award.${w("units")} then
    ${awardRecord(ctx, "funding_award.exceeded", "v_award", `, 'periodStart', v_start, 'awarded', v_award.${w("units")}, 'used', v_used`, "Funding award exceeded")}${
      notifies
        ? `
    ${notifyFunding(ctx, {
      type: "funding_award.exceeded",
      tenant: `v_award.${w("tenant")}`,
      subjectType: `v_award.${w("subjectType")}`,
      subjectId: `v_award.${w("subjectId")}`,
      permission: manage,
      summary: "'A funding award went over its units'",
      key: `'funding-exceeded:' || v_award.${w("id")}::text || ':' || v_start::text`,
      data: `jsonb_build_object('awardId', v_award.${w("id")}, 'periodStart', v_start, 'awarded', v_award.${w("units")}, 'used', v_used)`,
    })}`
        : ""
    }
  end if;`;

  return `
-- Adds a product a funder pays for, or changes one (product_id): its code,
-- unit and rate in minor units. The code is unique in the organization.
create or replace function ${fn("save_funding_product")}(tenant ${idType}, code text, title text, unit text, rate bigint, currency text, valid_from date default null, valid_until date default null, product_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${products}%rowtype;
  v_code text := nullif(trim(save_funding_product.code), '');
  v_title text := nullif(trim(save_funding_product.title), '');
  v_unit text := nullif(trim(save_funding_product.unit), '');
  v_currency text := upper(nullif(trim(save_funding_product.currency), ''));
begin
  if not ${allowed("save_funding_product.tenant", manage)} then
    ${forbidden("not allowed to manage funding products")}
  end if;
  ${productChecks}
  if exists (
    select 1 from ${products} x
    where x.${p("tenant")} = save_funding_product.tenant and x.${p("code")} = v_code
      and x.${p("id")} is distinct from save_funding_product.product_id
  ) then
    ${invalid("the organization already has a funding product with this code")}
  end if;
  if save_funding_product.product_id is null then
    insert into ${products} (${p("tenant")}, ${p("code")}, ${p("title")}, ${p("unit")}, ${p("rate")}, ${p("currency")}, ${p("validFrom")}, ${p("validUntil")})
    values (save_funding_product.tenant, v_code, v_title, v_unit, save_funding_product.rate, v_currency, save_funding_product.valid_from, save_funding_product.valid_until)
    returning * into v_row;
  else
    update ${products} x set
      ${p("code")} = v_code,
      ${p("title")} = v_title,
      ${p("unit")} = v_unit,
      ${p("rate")} = save_funding_product.rate,
      ${p("currency")} = v_currency,
      ${p("validFrom")} = save_funding_product.valid_from,
      ${p("validUntil")} = save_funding_product.valid_until${touch("products")}
    where x.${p("id")} = save_funding_product.product_id and x.${p("tenant")} = save_funding_product.tenant
    returning x.* into v_row;
    if not found then
      ${productNotFound}
    end if;
  end if;
  return ${productJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("save_funding_product")}(${idType}, text, text, text, bigint, text, date, date, uuid)`)}

create or replace function ${fn("list_funding_products")}(tenant ${idType}, include_expired boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${productJson(ctx, "x")} order by x.${p("code")}, x.${p("id")}), '[]'::jsonb)
  from ${products} x
  where x.${p("tenant")} = list_funding_products.tenant
    and (coalesce(list_funding_products.include_expired, false) or x.${p("validUntil")} is null or x.${p("validUntil")} >= current_date)
$$;
${userGrant(`${fn("list_funding_products")}(${idType}, boolean)`)}

-- Awards units of a product per period to a record, from a funder in
-- contacts, or changes an award (award_id); a key attrs leaves out keeps its
-- value. attrs holds funderId, productId, units, period (week, month or
-- total), startsOn, endsOn, reference, status (requested or active) and
-- fields, the extra columns by name.
create or replace function ${fn("save_funding_award")}(tenant ${idType}, subject_type text, subject_id text, attrs jsonb, award_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${awards}%rowtype;
  v_attrs jsonb := coalesce(save_funding_award.attrs, '{}'::jsonb);
  v_funder uuid;
  v_product uuid;
  v_units numeric;
  v_period text;
  v_starts date;
  v_ends date;
  v_reference text;
  v_status text;
begin
  if not ${allowed("save_funding_award.tenant", write)} then
    ${forbidden("not allowed to change funding awards")}
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    ${invalid("attrs is an object")}
  end if;
  ${fieldsCheck("v_attrs")}
  if save_funding_award.award_id is null then
    if not ${subjectInTenant(ctx, "save_funding_award.subject_type", "save_funding_award.subject_id", "save_funding_award.tenant")} then
      ${invalid("the record isn't in this organization")}
    end if;
    ${awardFields("v_attrs", undefined)}
  else
    select * into v_row from ${awards} x
    where x.${w("id")} = save_funding_award.award_id and x.${w("tenant")} = save_funding_award.tenant
    for update;
    if not found then
      ${awardNotFound}
    end if;
    if v_row.${w("subjectType")} <> save_funding_award.subject_type or v_row.${w("subjectId")} <> save_funding_award.subject_id then
      ${invalid("an award stays with its record")}
    end if;
    if v_row.${w("status")} in ('ended', 'canceled') then
      ${fail("FUNDING_AWARD_INACTIVE", "the funding award has ended", "22023")}
    end if;
    ${awardFields("v_attrs", "v_row")}
  end if;
  ${awardChecks("save_funding_award.tenant")}
  ${ctx.hook("before_funding_award_save", [
    [idType, "save_funding_award.tenant"],
    ["text", "save_funding_award.subject_type"],
    ["text", "save_funding_award.subject_id"],
    ["jsonb", "v_attrs"],
  ])}
  if save_funding_award.award_id is null then
    insert into ${awards} (${w("tenant")}, ${w("subjectType")}, ${w("subjectId")}, ${w("funder")}, ${w("product")}, ${w("units")}, ${w("period")}, ${w("startsOn")}, ${w("endsOn")}, ${w("reference")}, ${w("status")}${insertCol("awards", "createdBy")})
    values (save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_funder, v_product, v_units, v_period, v_starts, v_ends, v_reference, v_status${insertVal("awards", "createdBy", "(select auth.uid())")})
    returning * into v_row;${writeFields("v_attrs")}
    ${awardRecord(ctx, "funding_award.created", "v_row", "", "Funding awarded")}
  else
    update ${awards} x set
    ${awardSets}${touch("awards")}
    where x.${w("id")} = v_row.${w("id")}
    returning x.* into v_row;${writeFields("v_attrs")}
    ${awardRecord(ctx, "funding_award.updated", "v_row", "", "Funding award changed")}
  end if;
  ${ctx.hook("after_funding_award_save", [["uuid", `v_row.${w("id")}`]])}
  return ${awardJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("save_funding_award")}(${idType}, text, text, jsonb, uuid)`)}

-- Ends an award on ends_on (today by default), or cancels it (canceled).
-- Deliveries already registered stay.
create or replace function ${fn("end_funding_award")}(award_id uuid, ends_on date default null, canceled boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${awards}%rowtype;
  v_ends date;
begin
  select * into v_row from ${awards} x where x.${w("id")} = end_funding_award.award_id for update;
  if not found then
    ${awardNotFound}
  end if;
  if not ${allowed(`v_row.${w("tenant")}`, write)} then
    ${forbidden("not allowed to change funding awards")}
  end if;
  if v_row.${w("status")} in ('ended', 'canceled') then
    return ${awardJson(ctx, "v_row")};
  end if;
  v_ends := case
    when coalesce(end_funding_award.canceled, false) then coalesce(end_funding_award.ends_on, v_row.${w("endsOn")})
    else coalesce(end_funding_award.ends_on, least(current_date, coalesce(v_row.${w("endsOn")}, current_date)))
  end;
  if v_ends is not null and v_ends < v_row.${w("startsOn")} then
    if coalesce(end_funding_award.canceled, false) then
      v_ends := null;
    else
      ${invalid("an award ends on or after its start date; cancel it instead")}
    end if;
  end if;
  update ${awards} x set
    ${w("status")} = case when coalesce(end_funding_award.canceled, false) then 'canceled' else 'ended' end,
    ${w("endsOn")} = v_ends${touch("awards")}
  where x.${w("id")} = v_row.${w("id")}
  returning x.* into v_row;
  ${awardRecord(ctx, "funding_award.ended", "v_row", `, 'endsOn', v_row.${w("endsOn")}`, "Funding award ended")}
  return ${awardJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("end_funding_award")}(uuid, date, boolean)`)}

create or replace function ${fn("list_funding_awards")}(tenant ${idType}, subject_type text default null, subject_id text default null, include_ended boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${awardJson(ctx, "x")} || jsonb_build_object('product', ${productJson(ctx, "y")}) order by x.${w("startsOn")} desc, x.${w("id")}), '[]'::jsonb)
  from ${awards} x
  join ${products} y on y.${p("tenant")} = x.${w("tenant")} and y.${p("id")} = x.${w("product")}
  where x.${w("tenant")} = list_funding_awards.tenant
    and (list_funding_awards.subject_type is null or x.${w("subjectType")} = list_funding_awards.subject_type)
    and (list_funding_awards.subject_id is null or x.${w("subjectId")} = list_funding_awards.subject_id)
    and (coalesce(list_funding_awards.include_ended, false) or x.${w("status")} in ('requested', 'active'))
$$;
${userGrant(`${fn("list_funding_awards")}(${idType}, text, text, boolean)`)}

-- The units used against the units awarded, per period of the award from its
-- start to its end (today while it runs). Rejected deliveries don't count.
create or replace function ${fn("funding_award_usage")}(award_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'awardId', a.${w("id")},
    'units', a.${w("units")},
    'period', a.${w("period")},
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a.${w("units")},
        'used', s.used,
        'over', greatest(s.used - a.${w("units")}, 0),
        'under', greatest(a.${w("units")} - s.used, 0)
      ) order by s.start)
      from (
        select g.start, ${periodEnd(ctx, "a", "g.start")} as finish, (
          select coalesce(sum(x.${d("units")}), 0) from ${deliveries} x
          where x.${d("tenant")} = a.${w("tenant")} and x.${d("award")} = a.${w("id")} and x.${d("status")} <> 'rejected'
            and x.${d("deliveredOn")} >= g.start and x.${d("deliveredOn")} < ${periodEnd(ctx, "a", "g.start")}
        ) as used
        from (
          select pg_catalog.generate_series(
            ${periodStart(ctx, "a", `a.${w("startsOn")}`)}::timestamp,
            coalesce(a.${w("endsOn")}, current_date)::timestamp,
            case a.${w("period")} when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a.${w("period")} <> 'total'
          union all
          select a.${w("startsOn")} where a.${w("period")} = 'total'
        ) g
      ) s
    ), '[]'::jsonb)
  )
  from ${awards} a
  where a.${w("id")} = funding_award_usage.award_id
$$;
${userGrant(`${fn("funding_award_usage")}(uuid)`)}

-- Registers care delivered on an award: units on a day, from a time entry, a
-- booking or by hand (manual). A source registered before returns its
-- delivery, so registering it twice is safe. Crossing the units of a period
-- emits funding_award.exceeded.
create or replace function ${fn("register_funding_delivery")}(award_id uuid, delivered_on date, units numeric, source_type text default 'manual', source_id text default null, performer_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${deliveries}%rowtype;
  v_award ${awards}%rowtype;
  v_product ${products}%rowtype;
  v_source text := coalesce(nullif(trim(register_funding_delivery.source_type), ''), 'manual');
  v_source_id text := nullif(trim(register_funding_delivery.source_id), '');
  v_note text := nullif(trim(register_funding_delivery.note), '');
  v_start date;
  v_used numeric;${notifies ? "\n  v_claims text;" : ""}
begin
  select * into v_award from ${awards} x where x.${w("id")} = register_funding_delivery.award_id;
  if not found then
    ${awardNotFound}
  end if;
  if not ${allowed(`v_award.${w("tenant")}`, register)} then
    ${forbidden("not allowed to register funded care")}
  end if;
  if v_source not in ${sqlList(DELIVERY_SOURCES)} then
    ${invalid("source_type is time_entry, booking or manual")}
  end if;
  if v_source <> 'manual' and v_source_id is null then
    ${invalid("a delivery from a time entry or booking needs its source_id")}
  end if;
  if v_source_id is not null then
    select * into v_row from ${deliveries} x
    where x.${d("tenant")} = v_award.${w("tenant")} and x.${d("sourceType")} = v_source and x.${d("sourceId")} = v_source_id;
    if found then
      return ${deliveryJson(ctx, "v_row")};
    end if;
  end if;
  if register_funding_delivery.delivered_on is null then
    ${invalid("a delivery needs the day it was delivered")}
  end if;
  if register_funding_delivery.units is null or register_funding_delivery.units <= 0 then
    ${invalid("a delivery needs units above zero")}
  end if;
  if v_note is not null and length(v_note) > 2000 then
    ${invalid("a note is at most 2000 characters")}
  end if;
  if v_award.${w("status")} <> 'active'
    or register_funding_delivery.delivered_on < v_award.${w("startsOn")}
    or register_funding_delivery.delivered_on > coalesce(v_award.${w("endsOn")}, register_funding_delivery.delivered_on) then
    ${fail("FUNDING_AWARD_INACTIVE", "the funding award isn't active on that day", "22023")}
  end if;
  select * into v_product from ${products} x where x.${p("tenant")} = v_award.${w("tenant")} and x.${p("id")} = v_award.${w("product")};
  if (v_product.${p("validFrom")} is not null and register_funding_delivery.delivered_on < v_product.${p("validFrom")})
    or (v_product.${p("validUntil")} is not null and register_funding_delivery.delivered_on > v_product.${p("validUntil")}) then
    ${invalid("the funding product isn't valid on that day")}
  end if;${sourceCheck()}
  ${ctx.hook("before_funding_delivery_register", [
    ["uuid", `v_award.${w("id")}`],
    ["date", "register_funding_delivery.delivered_on"],
    ["numeric", "register_funding_delivery.units"],
  ])}
  insert into ${deliveries} (${d("tenant")}, ${d("award")}, ${d("sourceType")}, ${d("sourceId")}, ${d("deliveredOn")}, ${d("units")}, ${d("performer")}${insertCol("deliveries", "note")})
  values (v_award.${w("tenant")}, v_award.${w("id")}, v_source, v_source_id, register_funding_delivery.delivered_on, register_funding_delivery.units, coalesce(register_funding_delivery.performer_id, (select auth.uid()))${insertVal("deliveries", "note", "v_note")})
  returning * into v_row;
  ${ctx.record({
    type: "funding_delivery.registered",
    payload: `jsonb_build_object('organizationId', v_row.${d("tenant")}, 'fundingAwardId', v_row.${d("award")}, 'fundingDeliveryId', v_row.${d("id")}, 'subjectType', v_award.${w("subjectType")}, 'subjectId', v_award.${w("subjectId")}, 'sourceType', v_row.${d("sourceType")}, 'sourceId', v_row.${d("sourceId")}, 'deliveredOn', v_row.${d("deliveredOn")}, 'units', v_row.${d("units")})`,
    subject: `'funding-awards/' || v_row.${d("award")}::text`,
    tenant: `v_row.${d("tenant")}`,
    audit: {
      category: "data",
      targetType: "funding_delivery",
      recordId: `v_row.${d("id")}::text`,
      summary: "'Funded care registered'",
    },
  })}
  ${exceeded}
  ${ctx.hook("after_funding_delivery_register", [["uuid", `v_row.${d("id")}`]])}
  return ${deliveryJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("register_funding_delivery")}(uuid, date, numeric, text, text, uuid, text)`)}

-- Approves registered deliveries for a claim (approved true) or rejects them.
-- A delivery a claim holds can't change. Returns how many changed.
create or replace function ${fn("approve_funding_deliveries")}(ids uuid[], approved boolean default true)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${deliveries}%rowtype;
  v_status text := case when coalesce(approve_funding_deliveries.approved, true) then 'approved' else 'rejected' end;
  v_found integer := 0;
  v_changed integer := 0;
begin
  for v_row in
    select * from ${deliveries} x
    where x.${d("id")} = any (coalesce(approve_funding_deliveries.ids, '{}'::uuid[]))
    order by x.${d("id")}
    for update
  loop
    v_found := v_found + 1;
    if not ${allowed(`v_row.${d("tenant")}`, approve)} then
      ${forbidden("not allowed to approve funded care")}
    end if;
    if v_row.${d("status")} = 'claimed' then
      ${fail("FUNDING_DELIVERY_CLAIMED", "a claim holds this delivery", "22023")}
    end if;
    if v_row.${d("status")} <> v_status then
      update ${deliveries} x set ${d("status")} = v_status where x.${d("id")} = v_row.${d("id")};
      v_changed := v_changed + 1;
    end if;
  end loop;
  if v_found < (select count(distinct i) from unnest(coalesce(approve_funding_deliveries.ids, '{}'::uuid[])) i) then
    ${deliveryNotFound}
  end if;
  return v_changed;
end;
$$;
${userGrant(`${fn("approve_funding_deliveries")}(uuid[], boolean)`)}

-- The deliveries of an organization, newest first. filter holds awardId,
-- status, since and until (days), and limit (500 by default, 1000 at most).
create or replace function ${fn("list_funding_deliveries")}(tenant ${idType}, filter jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.row order by z.day desc, z.id), '[]'::jsonb)
  from (
    select ${deliveryJson(ctx, "x")} as row, x.${d("deliveredOn")} as day, x.${d("id")} as id
    from ${deliveries} x
    where x.${d("tenant")} = list_funding_deliveries.tenant
      and (list_funding_deliveries.filter ->> 'awardId' is null or x.${d("award")} = (list_funding_deliveries.filter ->> 'awardId')::uuid)
      and (list_funding_deliveries.filter ->> 'status' is null or x.${d("status")} = list_funding_deliveries.filter ->> 'status')
      and (list_funding_deliveries.filter ->> 'since' is null or x.${d("deliveredOn")} >= (list_funding_deliveries.filter ->> 'since')::date)
      and (list_funding_deliveries.filter ->> 'until' is null or x.${d("deliveredOn")} <= (list_funding_deliveries.filter ->> 'until')::date)
    order by x.${d("deliveredOn")} desc, x.${d("id")}
    limit least(greatest(coalesce((list_funding_deliveries.filter ->> 'limit')::integer, 500), 1), 1000)
  ) z
$$;
${userGrant(`${fn("list_funding_deliveries")}(${idType}, jsonb)`)}
`;
}
