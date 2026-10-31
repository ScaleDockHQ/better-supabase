import type { BlockSqlContext } from "../context.ts";

import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The legal entity and its settings: writers, readers and the resolvers. */
export function legalEntityFunctions(ctx: BlockSqlContext): string {
  const entities = ctx.table("entities");
  const settings = ctx.table("settings");
  const e = (column: string): string => ctx.col("entities", column);
  const s = (column: string): string => ctx.col("settings", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("legal-entities");
  const manage = ctx.permission("manage", permissions.manage);
  const own = ctx.of("settings");
  const org = own.table("organization");
  const o = (column: string): string => own.col("organization", column);

  const allowed = (tenant: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, manage)})`;

  const forbidden = fail(
    "LEGAL_ENTITY_FORBIDDEN",
    "not allowed to manage legal entities",
  );

  const invalid = (message: string): string =>
    fail("LEGAL_ENTITY_INVALID", message, "22023");

  const missing = fail(
    "LEGAL_ENTITY_NOT_FOUND",
    "legal entity not found",
    "P0002",
  );

  const lock = (tenant: string): string =>
    `perform pg_advisory_xact_lock(hashtextextended('legal_entities:' || ${tenant}::text, 0));`;

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${e("id")}, 'organizationId', ${row}.${e("tenant")}, 'code', ${row}.${e("code")}, 'name', ${row}.${e("name")}, 'address', ${row}.${e("address")}, 'vatNumber', ${row}.${e("vatNumber")}, 'cocNumber', ${row}.${e("cocNumber")}, 'iban', ${row}.${e("iban")}, 'bic', ${row}.${e("bic")}, 'logoAttachmentId', ${row}.${e("logoAttachment")}, 'defaultCurrency', ${row}.${e("defaultCurrency")}, 'fiscal', ${row}.${e("fiscal")}, 'isDefault', ${row}.${e("isDefault")}, 'archivedAt', ${row}.${e("archivedAt")}, 'createdAt', ${row}.${e("createdAt")}, 'updatedAt', ${row}.${e("updatedAt")})`;

  const record = (
    verb: "created" | "updated",
    row: string,
    summary: string,
  ): string =>
    ctx.record({
      type: `legal_entity.${verb}`,
      payload: `jsonb_build_object('organizationId', ${row}.${e("tenant")}, 'legalEntityId', ${row}.${e("id")}, 'code', ${row}.${e("code")}, 'isDefault', ${row}.${e("isDefault")})`,
      subject: `'legal-entities/' || ${row}.${e("id")}::text`,
      tenant: `${row}.${e("tenant")}`,
      audit: {
        category: "data",
        targetType: "legal_entity",
        recordId: `${row}.${e("id")}::text`,
        summary,
      },
    });

  const updated = (row: string, summary: string): string =>
    record("updated", row, summary);

  return `
-- Checks the fiscal settings and fills the defaults: the first month of the
-- fiscal year (1 to 12) and the tax period (monthly or quarterly).
create or replace function ${fn("legal_entity_fiscal")}(fiscal jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_month text;
  v_period text;
begin
  if legal_entity_fiscal.fiscal is null or jsonb_typeof(legal_entity_fiscal.fiscal) <> 'object' then
    ${invalid("fiscal must be an object")}
  end if;
  v_month := coalesce(legal_entity_fiscal.fiscal ->> 'fiscalYearStartMonth', '1');
  v_period := coalesce(legal_entity_fiscal.fiscal ->> 'taxPeriod', 'quarterly');
  if v_month !~ '^[0-9]{1,2}$' or v_month::integer < 1 or v_month::integer > 12 then
    ${invalid("fiscalYearStartMonth must be a month from 1 to 12")}
  end if;
  if v_period not in ('monthly', 'quarterly') then
    ${invalid("taxPeriod must be monthly or quarterly")}
  end if;
  return jsonb_build_object('fiscalYearStartMonth', v_month::integer, 'taxPeriod', v_period);
end;
$$;
revoke execute on function ${fn("legal_entity_fiscal")}(jsonb) from public, anon, authenticated;

-- Creates a legal entity. The first entity of an organization becomes its
-- default, and is_default makes a later one the default instead.
create or replace function ${fn("create_legal_entity")}(tenant ${idType}, code text, name text, address jsonb default null, vat_number text default null, coc_number text default null, iban text default null, bic text default null, logo_attachment_id uuid default null, default_currency text default null, fiscal jsonb default null, is_default boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entities}%rowtype;
  v_default boolean;
begin
  if not ${allowed("create_legal_entity.tenant")} then
    ${forbidden}
  end if;
  if nullif(trim(create_legal_entity.code), '') is null or nullif(trim(create_legal_entity.name), '') is null then
    ${invalid("a legal entity needs a code and a name")}
  end if;
  ${ctx.hook("before_legal_entity_create", [[idType, "create_legal_entity.tenant"]])}
  ${lock("create_legal_entity.tenant")}
  if exists (select 1 from ${entities} x where x.${e("tenant")} = create_legal_entity.tenant and x.${e("code")} = trim(create_legal_entity.code)) then
    ${fail("LEGAL_ENTITY_CODE_TAKEN", "a legal entity with this code exists", "23505")}
  end if;
  v_default := coalesce(create_legal_entity.is_default, false)
    or not exists (select 1 from ${entities} x where x.${e("tenant")} = create_legal_entity.tenant and x.${e("isDefault")});
  if v_default then
    update ${entities} x set ${e("isDefault")} = false, ${e("updatedAt")} = now()
      where x.${e("tenant")} = create_legal_entity.tenant and x.${e("isDefault")};
  end if;
  insert into ${entities} (${e("tenant")}, ${e("code")}, ${e("name")}, ${e("address")}, ${e("vatNumber")}, ${e("cocNumber")}, ${e("iban")}, ${e("bic")}, ${e("logoAttachment")}, ${e("defaultCurrency")}, ${e("fiscal")}, ${e("isDefault")})
  values (create_legal_entity.tenant, trim(create_legal_entity.code), trim(create_legal_entity.name), coalesce(create_legal_entity.address, '{}'::jsonb),
    nullif(trim(create_legal_entity.vat_number), ''), nullif(trim(create_legal_entity.coc_number), ''), nullif(replace(trim(create_legal_entity.iban), ' ', ''), ''), nullif(trim(create_legal_entity.bic), ''),
    create_legal_entity.logo_attachment_id, nullif(upper(trim(create_legal_entity.default_currency)), ''),
    ${fn("legal_entity_fiscal")}(coalesce(create_legal_entity.fiscal, '{}'::jsonb)), v_default)
  returning * into v_row;
  ${record("created", "v_row", `'created legal entity ' || v_row.${e("code")}`)}
  ${ctx.hook("after_legal_entity_create", [["uuid", `v_row.${e("id")}`]])}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("create_legal_entity")}(${idType}, text, text, jsonb, text, text, text, text, uuid, text, jsonb, boolean)`)}

-- Changes the keys present in patch (code, name, address, vat_number,
-- coc_number, iban, bic, logo_attachment_id, default_currency, fiscal).
create or replace function ${fn("update_legal_entity")}(legal_entity_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entities}%rowtype;
  v_old ${entities}%rowtype;
begin
  select * into v_old from ${entities} x where x.${e("id")} = update_legal_entity.legal_entity_id;
  if not found then
    ${missing}
  end if;
  if not ${allowed(`v_old.${e("tenant")}`)} then
    ${forbidden}
  end if;
  if update_legal_entity.patch is null or jsonb_typeof(update_legal_entity.patch) <> 'object' then
    ${invalid("patch must be an object")}
  end if;
  ${ctx.hook("before_legal_entity_update", [["uuid", "update_legal_entity.legal_entity_id"]])}
  if update_legal_entity.patch ? 'code' and nullif(trim(update_legal_entity.patch ->> 'code'), '') is null then
    ${invalid("code can't be empty")}
  end if;
  if update_legal_entity.patch ? 'name' and nullif(trim(update_legal_entity.patch ->> 'name'), '') is null then
    ${invalid("name can't be empty")}
  end if;
  if update_legal_entity.patch ? 'code' and exists (
    select 1 from ${entities} x
    where x.${e("tenant")} = v_old.${e("tenant")} and x.${e("code")} = trim(update_legal_entity.patch ->> 'code') and x.${e("id")} <> v_old.${e("id")}
  ) then
    ${fail("LEGAL_ENTITY_CODE_TAKEN", "a legal entity with this code exists", "23505")}
  end if;
  update ${entities} x set
    ${e("code")} = case when update_legal_entity.patch ? 'code' then trim(update_legal_entity.patch ->> 'code') else x.${e("code")} end,
    ${e("name")} = case when update_legal_entity.patch ? 'name' then trim(update_legal_entity.patch ->> 'name') else x.${e("name")} end,
    ${e("address")} = case when update_legal_entity.patch ? 'address' then coalesce(update_legal_entity.patch -> 'address', '{}'::jsonb) else x.${e("address")} end,
    ${e("vatNumber")} = case when update_legal_entity.patch ? 'vat_number' then nullif(trim(update_legal_entity.patch ->> 'vat_number'), '') else x.${e("vatNumber")} end,
    ${e("cocNumber")} = case when update_legal_entity.patch ? 'coc_number' then nullif(trim(update_legal_entity.patch ->> 'coc_number'), '') else x.${e("cocNumber")} end,
    ${e("iban")} = case when update_legal_entity.patch ? 'iban' then nullif(replace(trim(update_legal_entity.patch ->> 'iban'), ' ', ''), '') else x.${e("iban")} end,
    ${e("bic")} = case when update_legal_entity.patch ? 'bic' then nullif(trim(update_legal_entity.patch ->> 'bic'), '') else x.${e("bic")} end,
    ${e("logoAttachment")} = case when update_legal_entity.patch ? 'logo_attachment_id' then nullif(update_legal_entity.patch ->> 'logo_attachment_id', '')::uuid else x.${e("logoAttachment")} end,
    ${e("defaultCurrency")} = case when update_legal_entity.patch ? 'default_currency' then nullif(upper(trim(update_legal_entity.patch ->> 'default_currency')), '') else x.${e("defaultCurrency")} end,
    ${e("fiscal")} = case when update_legal_entity.patch ? 'fiscal' then ${fn("legal_entity_fiscal")}(x.${e("fiscal")} || coalesce(update_legal_entity.patch -> 'fiscal', '{}'::jsonb)) else x.${e("fiscal")} end,
    ${e("updatedAt")} = now()
  where x.${e("id")} = v_old.${e("id")}
  returning * into v_row;
  ${updated("v_row", `'updated legal entity ' || v_row.${e("code")}`)}
  ${ctx.hook("after_legal_entity_update", [["uuid", `v_row.${e("id")}`]])}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("update_legal_entity")}(uuid, jsonb)`)}

-- Makes an active legal entity the organization's default.
create or replace function ${fn("set_default_legal_entity")}(legal_entity_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entities}%rowtype;
begin
  select * into v_row from ${entities} x where x.${e("id")} = set_default_legal_entity.legal_entity_id;
  if not found then
    ${missing}
  end if;
  if not ${allowed(`v_row.${e("tenant")}`)} then
    ${forbidden}
  end if;
  ${lock(`v_row.${e("tenant")}`)}
  if v_row.${e("archivedAt")} is not null then
    ${fail("LEGAL_ENTITY_ARCHIVED", "an archived legal entity can't be the default", "22023")}
  end if;
  update ${entities} x set ${e("isDefault")} = false, ${e("updatedAt")} = now()
    where x.${e("tenant")} = v_row.${e("tenant")} and x.${e("isDefault")} and x.${e("id")} <> v_row.${e("id")};
  update ${entities} x set ${e("isDefault")} = true, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${updated("v_row", `'made legal entity ' || v_row.${e("code")} || ' the default'`)}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("set_default_legal_entity")}(uuid)`)}

-- Archives a legal entity, or restores it. The default can't be archived:
-- make another one the default first.
create or replace function ${fn("set_legal_entity_archived")}(legal_entity_id uuid, archived boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${entities}%rowtype;
begin
  select * into v_row from ${entities} x where x.${e("id")} = set_legal_entity_archived.legal_entity_id;
  if not found then
    ${missing}
  end if;
  if not ${allowed(`v_row.${e("tenant")}`)} then
    ${forbidden}
  end if;
  ${lock(`v_row.${e("tenant")}`)}
  if coalesce(set_legal_entity_archived.archived, true) and v_row.${e("isDefault")} then
    ${fail("LEGAL_ENTITY_DEFAULT", "make another legal entity the default before archiving this one", "22023")}
  end if;
  update ${entities} x set
    ${e("archivedAt")} = case when coalesce(set_legal_entity_archived.archived, true) then coalesce(x.${e("archivedAt")}, now()) else null end,
    ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${updated("v_row", `case when v_row.${e("archivedAt")} is null then 'restored legal entity ' else 'archived legal entity ' end || v_row.${e("code")}`)}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("set_legal_entity_archived")}(uuid, boolean)`)}

create or replace function ${fn("get_legal_entity")}(legal_entity_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row ${entities}%rowtype;
begin
  select * into v_row from ${entities} x where x.${e("id")} = get_legal_entity.legal_entity_id;
  if not found then
    ${missing}
  end if;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("get_legal_entity")}(uuid)`)}

-- The default entity first, then by code.
create or replace function ${fn("list_legal_entities")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("x")} order by x.${e("isDefault")} desc, x.${e("code")}), '[]'::jsonb)
  from ${entities} x
  where x.${e("tenant")} = list_legal_entities.tenant
    and (coalesce(list_legal_entities.include_archived, false) or x.${e("archivedAt")} is null)
$$;
${userGrant(`${fn("list_legal_entities")}(${idType}, boolean)`)}

-- The legal entity a row belongs to: the given one when it is the
-- organization's, otherwise the organization's default. Null means the
-- organization has no legal entity yet, which is how a single-entity
-- organization runs with no configuration. Other modules call this with a
-- legal_entity_id column that may be null.
create or replace function ${fn("legal_entity_of")}(tenant ${idType}, id uuid default null)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if legal_entity_of.id is not null then
    select x.${e("id")} into v_id from ${entities} x
      where x.${e("id")} = legal_entity_of.id and x.${e("tenant")} = legal_entity_of.tenant;
    if v_id is null then
      ${missing}
    end if;
    return v_id;
  end if;
  select x.${e("id")} into v_id from ${entities} x
    where x.${e("tenant")} = legal_entity_of.tenant and x.${e("isDefault")};
  return v_id;
end;
$$;
${userGrant(`${fn("legal_entity_of")}(${idType}, uuid)`)}

create or replace function ${fn("get_legal_entity_settings")}(legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.${s("key")}, s.${s("value")}), '{}'::jsonb)
  from ${settings} s
  where s.${s("entity")} = get_legal_entity_settings.legal_entity_id
$$;
${userGrant(`${fn("get_legal_entity_settings")}(uuid)`)}

-- Stores one setting of a legal entity. value takes the same envelope as
-- set_organization_setting: { "value": ... }.
create or replace function ${fn("set_legal_entity_setting")}(legal_entity_id uuid, key text, value jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType};
  v_value jsonb;
begin
  select x.${e("tenant")} into v_tenant from ${entities} x where x.${e("id")} = set_legal_entity_setting.legal_entity_id;
  if v_tenant is null then
    ${missing}
  end if;
  if not ${allowed("v_tenant")} then
    ${forbidden}
  end if;
  insert into ${settings} (${s("tenant")}, ${s("entity")}, ${s("key")}, ${s("value")})
  values (v_tenant, set_legal_entity_setting.legal_entity_id, set_legal_entity_setting.key, coalesce(set_legal_entity_setting.value -> 'value', 'null'::jsonb))
  on conflict (${s("entity")}, ${s("key")}) do update
    set ${s("value")} = excluded.${s("value")}, ${s("updatedBy")} = auth.uid(), ${s("updatedAt")} = now()
  returning ${s("value")} into v_value;
  return v_value;
end;
$$;
${userGrant(`${fn("set_legal_entity_setting")}(uuid, text, jsonb)`)}

create or replace function ${fn("reset_legal_entity_setting")}(legal_entity_id uuid, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType};
begin
  select x.${e("tenant")} into v_tenant from ${entities} x where x.${e("id")} = reset_legal_entity_setting.legal_entity_id;
  if v_tenant is null then
    ${missing}
  end if;
  if not ${allowed("v_tenant")} then
    ${forbidden}
  end if;
  delete from ${settings} s
    where s.${s("entity")} = reset_legal_entity_setting.legal_entity_id and s.${s("key")} = reset_legal_entity_setting.key;
  return found;
end;
$$;
${userGrant(`${fn("reset_legal_entity_setting")}(uuid, text)`)}

-- One setting for a legal entity: its own value, else the organization's
-- value, else { "source": "default", "value": null }, where the caller applies
-- the code default. Without a legal entity the organization's default entity
-- answers. Reads as the caller, so the settings the caller may not read count
-- as unset.
create or replace function ${fn("resolve_setting")}(tenant ${idType}, key text, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entity uuid;
  v_value jsonb;
begin
  v_entity := ${fn("legal_entity_of")}(resolve_setting.tenant, resolve_setting.legal_entity);
  if v_entity is not null then
    select s.${s("value")} into v_value from ${settings} s
      where s.${s("entity")} = v_entity and s.${s("key")} = resolve_setting.key;
    if found then
      return jsonb_build_object('value', v_value, 'source', 'legal_entity', 'legalEntityId', v_entity);
    end if;
  end if;
  select s.${o("value")} into v_value from ${org} s
    where s.${o("tenant")} = resolve_setting.tenant and s.${o("key")} = resolve_setting.key;
  if found then
    return jsonb_build_object('value', v_value, 'source', 'organization', 'legalEntityId', v_entity);
  end if;
  return jsonb_build_object('value', null, 'source', 'default', 'legalEntityId', v_entity);
end;
$$;
${userGrant(`${fn("resolve_setting")}(${idType}, text, uuid)`)}
`;
}
