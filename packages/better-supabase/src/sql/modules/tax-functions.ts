import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { linked } from "./banking-sql.ts";
import { EPOCH, taxSql } from "./tax-sql.ts";

/** Codes and rates: save, list, the rate on a day and the code for a text. */
export function taxFunctions(ctx: BlockSqlContext): string {
  const q = taxSql(ctx);
  const { c, r, fn } = q;
  const idType = ctx.idType;
  const accounting = linked(ctx, "accounting");
  const entities = linked(ctx, "legal-entities");

  const accountCheck = (value: string): string =>
    accounting === undefined
      ? ""
      : `
  if ${value} is not null and not exists (
    select 1 from ${accounting.table("accounts")} y
    where y.${accounting.col("accounts", "id")} = ${value} and y.${accounting.col("accounts", "tenant")} = tax_code_write.tenant
  ) then
    ${q.codeInvalid("a tax code's account must be an account of the organization")}
  end if;`;

  const entityCheck =
    entities === undefined
      ? ""
      : `
  if v_entity is not null and not exists (
    select 1 from ${entities.table("entities")} y
    where y.${entities.col("entities", "id")} = v_entity and y.${entities.col("entities", "tenant")} = tax_code_write.tenant
  ) then
    ${q.codeInvalid("a tax code's legal entity must be a legal entity of the organization")}
  end if;`;

  const created = q.recordCode(
    "tax_code.created",
    "v_row",
    "Created a tax code",
  );

  const updated = q.recordCode(
    "tax_code.updated",
    "v_row",
    "Changed a tax code",
  );

  return `
-- The rate a tax code charges on a day, in basis points; null when no rate
-- covers the day. A code that doesn't charge a rate (exempt, zero, reverse
-- charge, intra-EU, export) always gives 0.
create or replace function ${fn("tax_rate_on")}(code_id uuid, on_date date)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when x.${c("type")} not in (${q.rateTypeList}) then 0
    else (
      select y.${r("rateBps")} from ${q.rates} y
      where y.${r("taxCode")} = x.${c("id")} and y.${r("validFrom")} <= tax_rate_on.on_date
        and (y.${r("validTo")} is null or y.${r("validTo")} >= tax_rate_on.on_date)
      order by y.${r("validFrom")} desc limit 1
    )
  end
  from ${q.codes} x where x.${c("id")} = tax_rate_on.code_id
$$;
${userGrant(`${fn("tax_rate_on")}(uuid, date)`)}

-- The tax code a code text names: the legal entity's own code first, then the
-- organization's. Null when there is none.
create or replace function ${fn("resolve_tax_code")}(tenant ${idType}, code text, legal_entity uuid default null)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select x.${c("id")} from ${q.codes} x
  where x.${c("tenant")} = resolve_tax_code.tenant and x.${c("code")} = resolve_tax_code.code
    and x.${c("archivedAt")} is null
    and (x.${c("legalEntity")} is null or x.${c("legalEntity")} = resolve_tax_code.legal_entity)
  order by (x.${c("legalEntity")} is null), x.${c("id")} limit 1
$$;
${userGrant(`${fn("resolve_tax_code")}(${idType}, text, uuid)`)}

-- Adds a rate to a code from valid_from on. A rate that starts after the
-- code's earlier open rate closes it the day before; without valid_to the rate
-- runs until the next later rate. A rate with the same start is replaced.
-- Internal: save_tax_rate and the import check who may call it.
create or replace function ${fn("tax_rate_write")}(tenant ${idType}, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code ${q.codes}%rowtype;
  v_from date := coalesce(tax_rate_write.valid_from, date '${EPOCH}');
  v_to date := tax_rate_write.valid_to;
  v_row ${q.rates}%rowtype;
begin
  select * into v_code from ${q.codes} x
  where x.${c("id")} = tax_rate_write.tax_code and x.${c("tenant")} = tax_rate_write.tenant for update;
  if not found then
    ${q.codeMissing}
  end if;
  if v_code.${c("type")} not in (${q.rateTypeList}) then
    ${q.rateInvalid("only a sales, purchase or margin code has a rate")}
  end if;
  if tax_rate_write.rate_bps is null or tax_rate_write.rate_bps < 0 or tax_rate_write.rate_bps > 100000 then
    ${q.rateInvalid("a rate is 0 to 100000 basis points")}
  end if;
  if v_to is not null and v_to < v_from then
    ${q.rateInvalid("a rate can't end before it starts")}
  end if;
  if v_to is null then
    select min(y.${r("validFrom")}) - 1 into v_to from ${q.rates} y
    where y.${r("taxCode")} = v_code.${c("id")} and y.${r("validFrom")} > v_from;
  end if;
  if v_to is not null and exists (
    select 1 from ${q.rates} y
    where y.${r("taxCode")} = v_code.${c("id")} and y.${r("validFrom")} > v_from and y.${r("validFrom")} <= v_to
  ) then
    ${q.rateInvalid("the rate would overlap a later rate of the code")}
  end if;
  update ${q.rates} y set ${r("validTo")} = v_from - 1
  where y.${r("taxCode")} = v_code.${c("id")} and y.${r("validFrom")} < v_from
    and (y.${r("validTo")} is null or y.${r("validTo")} >= v_from);
  insert into ${q.rates} (${r("tenant")}, ${r("taxCode")}, ${r("rateBps")}, ${r("validFrom")}, ${r("validTo")})
  values (tax_rate_write.tenant, v_code.${c("id")}, tax_rate_write.rate_bps, v_from, v_to)
  on conflict (${r("taxCode")}, ${r("validFrom")}) do update
    set ${r("rateBps")} = excluded.${r("rateBps")}, ${r("validTo")} = excluded.${r("validTo")}
  returning * into v_row;
  update ${q.codes} x set ${c("updatedAt")} = now() where x.${c("id")} = v_code.${c("id")};
  return ${q.rateJson("v_row")};
end;
$$;
revoke execute on function ${fn("tax_rate_write")}(${idType}, uuid, integer, date, date) from public, anon, authenticated;

-- Creates or changes a tax code. input: { code, name, type, legalEntityId?,
-- salesAccountId?, purchaseAccountId?, returnBoxes?, archived?, rateBps?,
-- validFrom? }. rateBps adds a rate from validFrom (the epoch for a new code,
-- today for an existing one). Internal: save_tax_code and the import check who
-- may call it.
create or replace function ${fn("tax_code_write")}(tenant ${idType}, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${q.codes}%rowtype;
  v_created boolean := false;
  v_type text;
  v_entity uuid;
  v_sales uuid;
  v_purchase uuid;
  v_boxes text[];
  v_rate integer;
  v_from date;
begin
  if jsonb_typeof(tax_code_write.input) is distinct from 'object' then
    ${q.codeInvalid("input must be an object")}
  end if;
  if tax_code_write.code_id is not null then
    select * into v_row from ${q.codes} x
    where x.${c("id")} = tax_code_write.code_id and x.${c("tenant")} = tax_code_write.tenant for update;
    if not found then
      ${q.codeMissing}
    end if;
  end if;
  v_type := coalesce(tax_code_write.input ->> 'type', v_row.${c("type")});
  if v_type is null or v_type not in (${q.typeList}) then
    ${q.codeInvalid("a tax code's type is sales, purchase, exempt, zero, reverse_charge, intra_eu_goods, intra_eu_services, export or margin")}
  end if;
  v_entity := case when tax_code_write.input ? 'legalEntityId'
    then nullif(tax_code_write.input ->> 'legalEntityId', '')::uuid else v_row.${c("legalEntity")} end;${entityCheck}
  v_sales := case when tax_code_write.input ? 'salesAccountId'
    then nullif(tax_code_write.input ->> 'salesAccountId', '')::uuid else v_row.${c("salesAccount")} end;${accountCheck("v_sales")}
  v_purchase := case when tax_code_write.input ? 'purchaseAccountId'
    then nullif(tax_code_write.input ->> 'purchaseAccountId', '')::uuid else v_row.${c("purchaseAccount")} end;${accountCheck("v_purchase")}
  if tax_code_write.input ? 'returnBoxes' then
    if jsonb_typeof(tax_code_write.input -> 'returnBoxes') is distinct from 'array' then
      ${q.codeInvalid("returnBoxes must be a list of box names")}
    end if;
    select coalesce(array_agg(trim(b.value) order by b.ordinality), '{}') into v_boxes
    from jsonb_array_elements_text(tax_code_write.input -> 'returnBoxes') with ordinality b;
  else
    v_boxes := coalesce(v_row.${c("returnBoxes")}, '{}');
  end if;
  if v_row.${c("id")} is null then
    v_created := true;
    insert into ${q.codes} (${c("tenant")}, ${c("legalEntity")}, ${c("code")}, ${c("name")}, ${c("type")}, ${c("salesAccount")}, ${c("purchaseAccount")}, ${c("returnBoxes")}, ${c("archivedAt")})
    values (tax_code_write.tenant, v_entity, trim(tax_code_write.input ->> 'code'), trim(tax_code_write.input ->> 'name'), v_type, v_sales, v_purchase, v_boxes,
      case when coalesce((tax_code_write.input ->> 'archived')::boolean, false) then now() end)
    returning * into v_row;
  else
    update ${q.codes} x set
      ${c("legalEntity")} = v_entity,
      ${c("code")} = coalesce(trim(tax_code_write.input ->> 'code'), x.${c("code")}),
      ${c("name")} = coalesce(trim(tax_code_write.input ->> 'name'), x.${c("name")}),
      ${c("type")} = v_type,
      ${c("salesAccount")} = v_sales,
      ${c("purchaseAccount")} = v_purchase,
      ${c("returnBoxes")} = v_boxes,
      ${c("archivedAt")} = case when tax_code_write.input ? 'archived'
        then case when (tax_code_write.input ->> 'archived')::boolean then coalesce(x.${c("archivedAt")}, now()) end
        else x.${c("archivedAt")} end,
      ${c("updatedAt")} = now()
    where x.${c("id")} = v_row.${c("id")}
    returning * into v_row;
  end if;
  if tax_code_write.input ? 'rateBps' and tax_code_write.input -> 'rateBps' <> 'null'::jsonb then
    v_rate := (tax_code_write.input ->> 'rateBps')::integer;
    v_from := coalesce(nullif(tax_code_write.input ->> 'validFrom', '')::date, case when v_created then date '${EPOCH}' else current_date end);
    perform ${fn("tax_rate_write")}(tax_code_write.tenant, v_row.${c("id")}, v_rate, v_from, null);
    select * into v_row from ${q.codes} x where x.${c("id")} = v_row.${c("id")};
  end if;
  if v_created then
    ${created}
  else
    ${updated}
  end if;
  return ${q.codeJson("v_row")};
exception
  when check_violation or not_null_violation then
    ${q.codeInvalid("a tax code has a code of 1 to 50 characters and a name of 1 to 200")}
  when unique_violation then
    ${q.codeInvalid("the organization already has a tax code with this code")}
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    ${q.codeInvalid("ids must be uuids, rateBps an integer and validFrom a date")}
end;
$$;
revoke execute on function ${fn("tax_code_write")}(${idType}, jsonb, uuid) from public, anon, authenticated;

create or replace function ${fn("save_tax_code")}(tenant ${idType}, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("save_tax_code.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage tax codes")}
  end if;
  return ${fn("tax_code_write")}(save_tax_code.tenant, save_tax_code.input, save_tax_code.code_id);
end;
$$;
${userGrant(`${fn("save_tax_code")}(${idType}, jsonb, uuid)`)}

create or replace function ${fn("save_tax_rate")}(tenant ${idType}, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("save_tax_rate.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage tax rates")}
  end if;
  return ${fn("tax_rate_write")}(save_tax_rate.tenant, save_tax_rate.tax_code, save_tax_rate.rate_bps, save_tax_rate.valid_from, save_tax_rate.valid_to);
end;
$$;
${userGrant(`${fn("save_tax_rate")}(${idType}, uuid, integer, date, date)`)}

-- The organization's tax codes with their rate history. With a legal entity,
-- the codes it can use: its own and the organization's.
create or replace function ${fn("list_tax_codes")}(tenant ${idType}, include_archived boolean default false, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_tax_codes.tenant", q.read)} then
    ${q.forbidden("not allowed to read tax codes")}
  end if;
  return coalesce((
    select jsonb_agg(${q.codeJson("x")} order by x.${c("code")}, x.${c("id")})
    from ${q.codes} x
    where x.${c("tenant")} = list_tax_codes.tenant
      and (coalesce(list_tax_codes.include_archived, false) or x.${c("archivedAt")} is null)
      and (list_tax_codes.legal_entity is null or x.${c("legalEntity")} is null or x.${c("legalEntity")} = list_tax_codes.legal_entity)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_tax_codes")}(${idType}, boolean, uuid)`)}
${taxCodeImport(ctx)}`;
}

/** The import targets of tax codes and rates (ADR 0141). */
function taxCodeImport(ctx: BlockSqlContext): string {
  const q = taxSql(ctx);
  const { c, fn } = q;
  const idType = ctx.idType;

  return `
-- The import target of the tax_code entity: item.data is the input of
-- save_tax_code, with rateBps and validFrom for the first rate.
create or replace function ${fn("import_tax_code")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType} := (import_tax_code.item ->> 'tenant')::${idType};
  v_row jsonb;
begin
  if jsonb_typeof(import_tax_code.item -> 'data') is distinct from 'object' then
    ${fail("IMPORT_ITEM_INVALID", "a tax code item needs data", "22023")}
  end if;
  v_row := ${fn("tax_code_write")}(v_tenant, import_tax_code.item -> 'data', import_tax_code.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
${serviceGrant(`${fn("import_tax_code")}(uuid, jsonb, text)`)}

-- When a tax code last changed, for the conflict check of imports.
create or replace function ${fn("tax_code_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x.${c("updatedAt")} from ${q.codes} x where x.${c("id")}::text = tax_code_updated_at.subject_id
$$;
${serviceGrant(`${fn("tax_code_updated_at")}(text)`)}

-- The import target of the tax_rate entity: item.data is { taxCodeId or
-- taxCode (the code text), rateBps, validFrom?, validTo? }.
create or replace function ${fn("import_tax_rate")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${idType} := (import_tax_rate.item ->> 'tenant')::${idType};
  v_data jsonb := import_tax_rate.item -> 'data';
  v_code uuid;
  v_row jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    ${fail("IMPORT_ITEM_INVALID", "a tax rate item needs data", "22023")}
  end if;
  begin
    v_code := coalesce(nullif(v_data ->> 'taxCodeId', '')::uuid, ${fn("resolve_tax_code")}(v_tenant, v_data ->> 'taxCode'));
    v_row := ${fn("tax_rate_write")}(v_tenant, v_code, (v_data ->> 'rateBps')::integer, nullif(v_data ->> 'validFrom', '')::date, nullif(v_data ->> 'validTo', '')::date);
  exception
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      ${fail("IMPORT_ITEM_INVALID", "a tax rate needs a tax code, a rate in basis points and valid dates", "22023")}
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$$;
${serviceGrant(`${fn("import_tax_rate")}(uuid, jsonb, text)`)}
`;
}

const plain = (qualified: string): string => qualified.replaceAll('"', "");

/** What `contributes.imports` returns: tax codes (with a rate) and rates. */
export function taxImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return own.mode === "custom"
    ? []
    : [
        {
          entity: "tax_code",
          subjectType: "tax_code",
          write: plain(own.fn("import_tax_code")),
          updatedAt: plain(own.fn("tax_code_updated_at")),
        },
        {
          entity: "tax_rate",
          subjectType: "tax_rate",
          write: plain(own.fn("import_tax_rate")),
        },
      ];
}
