import type { QualificationsEvents } from "../../blocks/qualifications/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<QualificationsEvents> = {
  "qualification_type.created": {
    subject: "qualification-types",
    payload: ["organizationId", "typeId", "key"],
  },
  "qualification_type.updated": {
    subject: "qualification-types",
    payload: ["organizationId", "typeId", "key"],
  },
  "qualification.granted": {
    subject: "qualifications",
    payload: ["organizationId", "qualificationId", "typeKey", "holderType", "holderId"],
  },
  "qualification.revoked": {
    subject: "qualifications",
    payload: ["organizationId", "qualificationId"],
  },
  "qualification.expired": {
    subject: "qualifications",
    payload: ["organizationId", "qualificationId", "holderType", "holderId", "expiresOn"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    qualification: { table: "qualifications", singular: "qualification", primary: true },
    qualification_type: { table: "types", singular: "qualification_type" },
    qualification_requirement: {
      table: "requirements",
      singular: "qualification_requirement",
    },
  },
  events: EVENTS,
  hooks: [],
  options: ["extraColumns", "holderTypes", "renewalWindowDays"],
  tables: {
    types: {
      name: "qualification_types",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        description: "description",
        holderTypes: "holder_types",
        validForMonths: "valid_for_months",
        evidenceRequired: "evidence_required",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "validForMonths", "archivedAt", "createdAt", "updatedAt"],
    },
    requirements: {
      name: "qualification_requirements",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        type: "type_id",
        targetType: "target_type",
        targetValue: "target_value",
        createdAt: "created_at",
      },
      optional: ["createdAt"],
    },
    qualifications: {
      name: "qualifications",
      app: {},
      lifecycle: { tenant: "tenant", user: "grantedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        type: "type_id",
        holderType: "holder_type",
        holderId: "holder_id",
        grantedOn: "granted_on",
        expiresOn: "expires_on",
        revokedAt: "revoked_at",
        revokeReason: "revoke_reason",
        evidenceNote: "evidence_note",
        source: "source",
        grantedBy: "granted_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "expiresOn",
        "revokedAt",
        "revokeReason",
        "evidenceNote",
        "grantedBy",
        "createdAt",
        "updatedAt",
      ],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const types = ctx.table("types");
  const reqs = ctx.table("requirements");
  const quals = ctx.table("qualifications");
  const t = (column: string): string => ctx.col("types", column);
  const r = (column: string): string => ctx.col("requirements", column);
  const q = (column: string): string => ctx.col("qualifications", column);
  const permissions = moduleOperations("qualifications");
  const read = ctx.permission("read", permissions.read);

  const extras = ctx.extraColumns("types", [
    "id",
    "tenant",
    "key",
    "name",
    "description",
    "holderTypes",
    "validForMonths",
    "evidenceRequired",
    "archivedAt",
    "createdAt",
    "updatedAt",
  ]);

  return `
create table if not exists ${types} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("key")} text not null check (${t("key")} ~ '^[a-z][a-z0-9_]{0,40}$'),
  ${t("name")} text not null,
  ${t("description")} text,
  ${t("holderTypes")} text[] not null default array['member']::text[],
  ${t("validForMonths")} integer check (${t("validForMonths")} between 1 and 240),
  ${t("evidenceRequired")} boolean not null default false,
  ${t("archivedAt")} timestamptz,
  ${t("createdAt")} timestamptz not null default now(),
  ${t("updatedAt")} timestamptz not null default now(),
  unique (${t("tenant")}, ${t("key")})
);${addExtraColumns(types, extras)}
${lockTable(types, { read: true })}
${renderPolicy(makePolicy({ table: types, name: `${ctx.tableName("types").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(t("tenant"), read) }))}

create table if not exists ${reqs} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("type")} uuid not null,
  ${r("targetType")} text not null check (${r("targetType")} in ('role', 'team', 'job_title', 'asset_kind', 'segment', 'holder')),
  ${r("targetValue")} text not null,
  ${r("createdAt")} timestamptz not null default now(),
  unique (${r("type")}, ${r("targetType")}, ${r("targetValue")}),
  foreign key (${r("type")}) references ${types} (${t("id")}) on delete cascade
);
create index if not exists ${ctx.tableName("requirements").name}_type_idx on ${reqs} (${r("type")});
${lockTable(reqs, { read: true })}
${renderPolicy(makePolicy({ table: reqs, name: `${ctx.tableName("requirements").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(r("tenant"), read) }))}

create table if not exists ${quals} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${ctx.idType} not null,
  ${q("type")} uuid not null,
  ${q("holderType")} text not null,
  ${q("holderId")} text not null,
  ${q("grantedOn")} date not null default current_date,
  ${q("expiresOn")} date,
  ${q("revokedAt")} timestamptz,
  ${q("revokeReason")} text,
  ${q("evidenceNote")} text,
  ${q("source")} text not null default 'manual' check (${q("source")} in ('manual', 'course', 'import')),
  ${q("grantedBy")} uuid default auth.uid(),
  ${q("createdAt")} timestamptz not null default now(),
  ${q("updatedAt")} timestamptz not null default now(),
  foreign key (${q("type")}) references ${types} (${t("id")}) on delete restrict
);
create index if not exists ${ctx.tableName("qualifications").name}_holder_idx on ${quals} (${q("tenant")}, ${q("holderType")}, ${q("holderId")});
create index if not exists ${ctx.tableName("qualifications").name}_expiry_idx on ${quals} (${q("type")}, ${q("expiresOn")});
${lockTable(quals, { read: true })}
${renderPolicy(makePolicy({ table: quals, name: `${ctx.tableName("qualifications").name}_read`, command: "select", roles: ["authenticated"], using: `${ctx.scope.check(q("tenant"), read)} or (${q("holderType")} = 'member' and ${q("holderId")} = (select auth.uid())::text)` }))}
`;
}

function functions(ctx: BlockSqlContext): string {
  const types = ctx.table("types");
  const reqs = ctx.table("requirements");
  const quals = ctx.table("qualifications");
  const t = (column: string): string => ctx.col("types", column);
  const r = (column: string): string => ctx.col("requirements", column);
  const q = (column: string): string => ctx.col("qualifications", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("qualifications");
  const read = ctx.permission("read", permissions.read);
  const grant = ctx.permission("grant", permissions.grant);
  const manage = ctx.permission("manage", permissions.manage);
  const members = ctx.of("memberships");
  const memberships = members.table("memberships");
  const mt = members.col("memberships", "tenant");
  const mu = members.col("memberships", "user");
  const mr = members.col("memberships", "role");

  const allowed = (tenant: string, permission: string): string =>
    `(select auth.uid()) is not null and ${ctx.can("tenant", tenant, permission)}`;

  const typeJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, 'key', ${row}.${t("key")}, 'name', ${row}.${t("name")}, 'description', ${row}.${t("description")}, 'holderTypes', ${row}.${t("holderTypes")}, 'validForMonths', ${row}.${t("validForMonths")}, 'evidenceRequired', ${row}.${t("evidenceRequired")}, 'archivedAt', ${row}.${t("archivedAt")}, 'createdAt', ${row}.${t("createdAt")}, 'updatedAt', ${row}.${t("updatedAt")})`;

  const qualJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${q("id")}, 'organizationId', ${row}.${q("tenant")}, 'typeId', ${row}.${q("type")}, 'holderType', ${row}.${q("holderType")}, 'holderId', ${row}.${q("holderId")}, 'grantedOn', ${row}.${q("grantedOn")}, 'expiresOn', ${row}.${q("expiresOn")}, 'revokedAt', ${row}.${q("revokedAt")}, 'revokeReason', ${row}.${q("revokeReason")}, 'evidenceNote', ${row}.${q("evidenceNote")}, 'source', ${row}.${q("source")}, 'grantedBy', ${row}.${q("grantedBy")}, 'createdAt', ${row}.${q("createdAt")}, 'updatedAt', ${row}.${q("updatedAt")})`;

  return `
create or replace function ${fn("save_qualification_type")}(tenant ${ctx.idType}, key text, name text, holder_types text[] default array['member']::text[], valid_for_months integer default null, evidence_required boolean default false, description text default null, type_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${types}%rowtype;
  v_created boolean := false;
begin
  if not ${allowed("save_qualification_type.tenant", manage)} then
    ${fail("QUALIFICATION_FORBIDDEN", "not allowed to manage qualification types")}
  end if;
  if save_qualification_type.key !~ '^[a-z][a-z0-9_]{0,40}$' or cardinality(coalesce(save_qualification_type.holder_types, array['member']::text[])) = 0 then
    ${fail("QUALIFICATION_TYPE_INVALID", "the key or holder types are invalid", "22023")}
  end if;
  if save_qualification_type.type_id is null then
    insert into ${types} (${t("tenant")}, ${t("key")}, ${t("name")}, ${t("description")}, ${t("holderTypes")}, ${t("validForMonths")}, ${t("evidenceRequired")})
    values (save_qualification_type.tenant, save_qualification_type.key, trim(save_qualification_type.name), save_qualification_type.description, coalesce(save_qualification_type.holder_types, array['member']::text[]), save_qualification_type.valid_for_months, coalesce(save_qualification_type.evidence_required, false))
    on conflict (${t("tenant")}, ${t("key")}) do update
      set ${t("name")} = excluded.${t("name")}, ${t("description")} = excluded.${t("description")}, ${t("holderTypes")} = excluded.${t("holderTypes")}, ${t("validForMonths")} = excluded.${t("validForMonths")}, ${t("evidenceRequired")} = excluded.${t("evidenceRequired")}, ${t("updatedAt")} = now()
    returning * into v_row;
    v_created := true;
  else
    update ${types} x set ${t("key")} = save_qualification_type.key, ${t("name")} = trim(save_qualification_type.name), ${t("description")} = save_qualification_type.description, ${t("holderTypes")} = coalesce(save_qualification_type.holder_types, array['member']::text[]), ${t("validForMonths")} = save_qualification_type.valid_for_months, ${t("evidenceRequired")} = coalesce(save_qualification_type.evidence_required, false), ${t("updatedAt")} = now()
      where x.${t("id")} = save_qualification_type.type_id and x.${t("tenant")} = save_qualification_type.tenant
      returning * into v_row;
    if not found then
      ${fail("QUALIFICATION_TYPE_NOT_FOUND", "qualification type not found", "P0002")}
    end if;
  end if;
  if v_created then
    ${ctx.record({
      type: "qualification_type.created",
      payload: `jsonb_build_object('organizationId', v_row.${t("tenant")}, 'typeId', v_row.${t("id")}, 'key', v_row.${t("key")})`,
      subject: `'qualification-types/' || v_row.${t("id")}::text`,
      tenant: `v_row.${t("tenant")}`,
      audit: {
        category: "data",
        targetType: "qualification_type",
        recordId: `v_row.${t("id")}::text`,
        summary: "'saved qualification type'",
      },
    })}
  else
    ${ctx.record({
      type: "qualification_type.updated",
      payload: `jsonb_build_object('organizationId', v_row.${t("tenant")}, 'typeId', v_row.${t("id")}, 'key', v_row.${t("key")})`,
      subject: `'qualification-types/' || v_row.${t("id")}::text`,
      tenant: `v_row.${t("tenant")}`,
      audit: {
        category: "data",
        targetType: "qualification_type",
        recordId: `v_row.${t("id")}::text`,
        summary: "'saved qualification type'",
      },
    })}
  end if;
  return ${typeJson("v_row")};
end;
$$;
${userGrant(`${fn("save_qualification_type")}(${ctx.idType}, text, text, text[], integer, boolean, text, uuid)`)}

create or replace function ${fn("archive_qualification_type")}(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${types}%rowtype;
begin
  select * into v_row from ${types} x where x.${t("id")} = archive_qualification_type.type_id;
  if not found then
    ${fail("QUALIFICATION_TYPE_NOT_FOUND", "qualification type not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${t("tenant")}`, manage)} then
    ${fail("QUALIFICATION_FORBIDDEN", "not allowed to manage qualification types")}
  end if;
  update ${types} x set ${t("archivedAt")} = now(), ${t("updatedAt")} = now() where x.${t("id")} = v_row.${t("id")} returning * into v_row;
  return ${typeJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_qualification_type")}(uuid)`)}

create or replace function ${fn("list_qualification_types")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${typeJson("x")} order by x.${t("key")}), '[]'::jsonb)
  from ${types} x
  where x.${t("tenant")} = $1 and ${ctx.scope.check(`x.${t("tenant")}`, read)}
$$;
${userGrant(`${fn("list_qualification_types")}(${ctx.idType})`)}

create or replace function ${fn("add_qualification_requirement")}(type_id uuid, target_type text, target_value text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type ${types}%rowtype;
  v_row ${reqs}%rowtype;
begin
  select * into v_type from ${types} x where x.${t("id")} = add_qualification_requirement.type_id;
  if not found then
    ${fail("QUALIFICATION_TYPE_NOT_FOUND", "qualification type not found", "P0002")}
  end if;
  if not ${allowed(`v_type.${t("tenant")}`, manage)} then
    ${fail("QUALIFICATION_FORBIDDEN", "not allowed to manage qualification requirements")}
  end if;
  if add_qualification_requirement.target_type not in ('role', 'team', 'job_title', 'asset_kind', 'segment', 'holder') then
    ${fail("QUALIFICATION_REQUIREMENT_INVALID", "the requirement target is invalid", "22023")}
  end if;
  insert into ${reqs} (${r("tenant")}, ${r("type")}, ${r("targetType")}, ${r("targetValue")})
  values (v_type.${t("tenant")}, v_type.${t("id")}, add_qualification_requirement.target_type, add_qualification_requirement.target_value)
  on conflict (${r("type")}, ${r("targetType")}, ${r("targetValue")}) do update set ${r("targetValue")} = excluded.${r("targetValue")}
  returning * into v_row;
  return jsonb_build_object('id', v_row.${r("id")}, 'typeId', v_row.${r("type")}, 'targetType', v_row.${r("targetType")}, 'targetValue', v_row.${r("targetValue")});
end;
$$;
${userGrant(`${fn("add_qualification_requirement")}(uuid, text, text)`)}

create or replace function ${fn("remove_qualification_requirement")}(requirement_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reqs}%rowtype;
begin
  select * into v_row from ${reqs} x where x.${r("id")} = remove_qualification_requirement.requirement_id;
  if not found then
    ${fail("QUALIFICATION_REQUIREMENT_INVALID", "requirement not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${r("tenant")}`, manage)} then
    ${fail("QUALIFICATION_FORBIDDEN", "not allowed to manage qualification requirements")}
  end if;
  delete from ${reqs} x where x.${r("id")} = v_row.${r("id")};
  return true;
end;
$$;
${userGrant(`${fn("remove_qualification_requirement")}(uuid)`)}

create or replace function ${fn("list_qualification_requirements")}(type_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${r("id")}, 'typeId', x.${r("type")}, 'targetType', x.${r("targetType")}, 'targetValue', x.${r("targetValue")})), '[]'::jsonb)
  from ${reqs} x
  where x.${r("type")} = $1
$$;
${userGrant(`${fn("list_qualification_requirements")}(uuid)`)}

create or replace function ${fn("grant_qualification")}(tenant ${ctx.idType}, type_key text, holder_type text, holder_id text, granted_on date default current_date, evidence_note text default null, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type ${types}%rowtype;
  v_row ${quals}%rowtype;
begin
  if not ${allowed("grant_qualification.tenant", grant)} then
    ${fail("QUALIFICATION_FORBIDDEN", "not allowed to grant qualifications")}
  end if;
  select * into v_type from ${types} x where x.${t("tenant")} = grant_qualification.tenant and x.${t("key")} = grant_qualification.type_key;
  if not found or v_type.${t("archivedAt")} is not null then
    ${fail("QUALIFICATION_TYPE_NOT_FOUND", "qualification type not found or archived", "P0002")}
  end if;
  if not grant_qualification.holder_type = any(v_type.${t("holderTypes")}) then
    ${fail("QUALIFICATION_HOLDER_INVALID", "the holder type is not allowed for this type", "22023")}
  end if;
  if v_type.${t("evidenceRequired")} and nullif(trim(coalesce(grant_qualification.evidence_note, '')), '') is null then
    ${fail("QUALIFICATION_EVIDENCE_REQUIRED", "evidence is required", "22023")}
  end if;
  insert into ${quals} (${q("tenant")}, ${q("type")}, ${q("holderType")}, ${q("holderId")}, ${q("grantedOn")}, ${q("expiresOn")}, ${q("evidenceNote")}, ${q("source")})
  values (grant_qualification.tenant, v_type.${t("id")}, grant_qualification.holder_type, grant_qualification.holder_id, coalesce(grant_qualification.granted_on, current_date), case when v_type.${t("validForMonths")} is null then null else (coalesce(grant_qualification.granted_on, current_date) + make_interval(months => v_type.${t("validForMonths")}))::date end, grant_qualification.evidence_note, coalesce(grant_qualification.source, 'manual'))
  returning * into v_row;
  ${ctx.record({
    type: "qualification.granted",
    payload: `jsonb_build_object('organizationId', v_row.${q("tenant")}, 'qualificationId', v_row.${q("id")}, 'typeKey', v_type.${t("key")}, 'holderType', v_row.${q("holderType")}, 'holderId', v_row.${q("holderId")})`,
    subject: `'qualifications/' || v_row.${q("id")}::text`,
    tenant: `v_row.${q("tenant")}`,
    audit: {
      category: "data",
      targetType: "qualification",
      recordId: `v_row.${q("id")}::text`,
      summary: `'granted qualification ' || v_type.${t("key")}`,
    },
  })}
  return ${qualJson("v_row")};
end;
$$;
${userGrant(`${fn("grant_qualification")}(${ctx.idType}, text, text, text, date, text, text)`)}

create or replace function ${fn("revoke_qualification")}(qualification_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${quals}%rowtype;
begin
  select * into v_row from ${quals} x where x.${q("id")} = revoke_qualification.qualification_id;
  if not found then
    ${fail("QUALIFICATION_NOT_FOUND", "qualification not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${q("tenant")}`, manage)} then
    ${fail("QUALIFICATION_FORBIDDEN", "not allowed to revoke qualifications")}
  end if;
  update ${quals} x set ${q("revokedAt")} = now(), ${q("revokeReason")} = revoke_qualification.reason, ${q("updatedAt")} = now() where x.${q("id")} = v_row.${q("id")} returning * into v_row;
  ${ctx.record({
    type: "qualification.revoked",
    payload: `jsonb_build_object('organizationId', v_row.${q("tenant")}, 'qualificationId', v_row.${q("id")})`,
    subject: `'qualifications/' || v_row.${q("id")}::text`,
    tenant: `v_row.${q("tenant")}`,
    audit: {
      category: "data",
      targetType: "qualification",
      recordId: `v_row.${q("id")}::text`,
      summary: "'revoked qualification'",
    },
  })}
  return ${qualJson("v_row")};
end;
$$;
${userGrant(`${fn("revoke_qualification")}(uuid, text)`)}

create or replace function ${fn("qualifications_of")}(holder_type text, holder_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${qualJson("x")} || jsonb_build_object('status', case when x.${q("revokedAt")} is not null then 'revoked' when x.${q("expiresOn")} is not null and x.${q("expiresOn")} < current_date then 'expired' when x.${q("expiresOn")} is not null and x.${q("expiresOn")} <= current_date + 30 then 'expiring' else 'valid' end) order by x.${q("grantedOn")} desc), '[]'::jsonb)
  from ${quals} x
  where x.${q("holderType")} = $1 and x.${q("holderId")} = $2
    and ${ctx.scope.check(`x.${q("tenant")}`, read)}
$$;
${userGrant(`${fn("qualifications_of")}(text, text)`)}

create or replace function ${fn("qualification_gaps")}(tenant ${ctx.idType}, holder_type text default 'member')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('holderType', m.${mu}, 'holderId', m.${mu}::text, 'typeKey', ty.${t("key")}, 'typeName', ty.${t("name")}, 'status', case when q.${q("id")} is null then 'missing' when q.${q("expiresOn")} < current_date then 'expired' else 'expiring' end, 'expiresOn', q.${q("expiresOn")})), '[]'::jsonb)
  from ${memberships} m
  join ${reqs} rq on rq.${r("tenant")} = m.${mt} and rq.${r("targetType")} = 'role' and rq.${r("targetValue")} = m.${mr}::text
  join ${types} ty on ty.${t("id")} = rq.${r("type")} and ty.${t("archivedAt")} is null
  left join lateral (
    select x.* from ${quals} x
    where x.${q("tenant")} = m.${mt} and x.${q("type")} = ty.${t("id")} and x.${q("holderType")} = 'member' and x.${q("holderId")} = m.${mu}::text
      and x.${q("revokedAt")} is null and (x.${q("expiresOn")} is null or x.${q("expiresOn")} >= current_date)
    order by x.${q("grantedOn")} desc limit 1
  ) q on true
  where m.${mt} = $1
    and (q.${q("id")} is null or q.${q("expiresOn")} <= current_date + 30)
$$;
${userGrant(`${fn("qualification_gaps")}(${ctx.idType}, text)`)}

create or replace function ${fn("notify_expiring_qualifications")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select x.* from ${quals} x
    where x.${q("revokedAt")} is null and x.${q("expiresOn")} is not null and x.${q("expiresOn")} <= current_date + 30
  loop
    ${ctx.record({
      type: "qualification.expired",
      payload: `jsonb_build_object('organizationId', v_row.${q("tenant")}, 'qualificationId', v_row.${q("id")}, 'holderType', v_row.${q("holderType")}, 'holderId', v_row.${q("holderId")}, 'expiresOn', v_row.${q("expiresOn")}::text)`,
      subject: `'qualifications/' || v_row.${q("id")}::text`,
      tenant: `v_row.${q("tenant")}`,
      audit: {
        category: "data",
        targetType: "qualification",
        recordId: `v_row.${q("id")}::text`,
        summary: "'qualification expiring'",
      },
    })}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("notify_expiring_qualifications")}()`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Qualifications: types, requirements, holdings for members, companies and
-- assets, gaps, expiry and renewal.
${tables(ctx)}${functions(ctx)}`;
}

function contract(_ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_qualification_type",
      args: ["{id}", "text", "text", "text[]", "integer", "boolean", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "archive_qualification_type", args: ["uuid"], returns: "jsonb" },
    { name: "list_qualification_types", args: ["{id}"], returns: "jsonb" },
    {
      name: "add_qualification_requirement",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "remove_qualification_requirement",
      args: ["uuid"],
      returns: "boolean",
    },
    {
      name: "list_qualification_requirements",
      args: ["uuid"],
      returns: "jsonb",
    },
    {
      name: "grant_qualification",
      args: ["{id}", "text", "text", "text", "date", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "revoke_qualification",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "qualifications_of",
      args: ["text", "text"],
      returns: "jsonb",
    },
    {
      name: "qualification_gaps",
      args: ["{id}", "text"],
      returns: "jsonb",
    },
    {
      name: "notify_expiring_qualifications",
      args: [],
      returns: "integer",
    },
  ];
}

export const QUALIFICATIONS: BlockSqlDefinition = {
  name: "qualifications",
  scopes: ["tenant"],
  title: "Qualifications",
  description:
    "Qualification types and requirements, holdings for members, companies and assets, gaps by role, expiry and renewal notifications.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
