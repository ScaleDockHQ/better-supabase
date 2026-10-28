import type { AcknowledgementsEvents } from "../../blocks/acknowledgements/events.ts";
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
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<AcknowledgementsEvents> = {
  "acknowledgement_assignment.created": {
    subject: "acknowledgement-assignments",
    payload: [
      "organizationId",
      "subjectType",
      "subjectId",
      "assignmentId",
      "principalType",
      "principalId",
      "dueOn",
    ],
  },
  "acknowledgement_assignment.deleted": {
    subject: "acknowledgement-assignments",
    payload: ["organizationId", "assignmentId"],
  },
  "acknowledgement.created": {
    subject: "acknowledgements",
    payload: [
      "organizationId",
      "subjectType",
      "subjectId",
      "versionId",
      "userId",
      "method",
    ],
  },
  "acknowledgement.expired": {
    subject: "acknowledgements",
    payload: [
      "organizationId",
      "subjectType",
      "subjectId",
      "versionId",
      "userId",
      "dueOn",
    ],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    acknowledgement: { table: "acknowledgements", singular: "acknowledgement" },
    acknowledgement_assignment: {
      table: "assignments",
      singular: "acknowledgement_assignment",
    },
  },
  events: EVENTS,
  hooks: [],
  options: ["extraColumns", "on"],
  tables: {
    assignments: {
      name: "acknowledgement_assignments",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        principalType: "principal_type",
        principalId: "principal_id",
        dueInDays: "due_in_days",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: ["createdBy"],
    },
    acknowledgements: {
      name: "acknowledgements",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        version: "version_id",
        user: "user_id",
        method: "method",
        signature: "signature_id",
        acknowledgedAt: "acknowledged_at",
      },
      optional: ["signature"],
    },
  },
};

/** The tables and their read policies. */
function tables(ctx: BlockSqlContext): string {
  const assignments = ctx.table("assignments");
  const acks = ctx.table("acknowledgements");
  const a = (column: string): string => ctx.col("assignments", column);
  const k = (column: string): string => ctx.col("acknowledgements", column);

  const permissions = moduleOperations("acknowledgements");

  const read = ctx.permission("read", permissions.read);

  const extras = ctx.extraColumns("assignments", [
    "id",
    "tenant",
    "subjectType",
    "subjectId",
    "principalType",
    "principalId",
    "dueInDays",
    "createdBy",
    "createdAt",
  ]);

  return `
create table if not exists ${assignments} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("subjectType")} text not null,
  ${a("subjectId")} text not null,
  ${a("principalType")} text not null check (${a("principalType")} in ('user', 'team', 'role')),
  ${a("principalId")} text not null,
  ${a("dueInDays")} integer check (${a("dueInDays")} between 1 and 365),
  ${a("createdBy")} uuid default auth.uid(),
  ${a("createdAt")} timestamptz not null default now(),
  unique (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("principalType")}, ${a("principalId")})
);
create index if not exists ${ctx.tableName("assignments").name}_principal_idx on ${assignments} (${a("tenant")}, ${a("principalType")}, ${a("principalId")});${addExtraColumns(assignments, extras)}
${lockTable(assignments, { read: true })}
${renderPolicy(makePolicy({ table: assignments, name: `${ctx.tableName("assignments").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(a("tenant"), read) }))}

create table if not exists ${acks} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("subjectType")} text not null,
  ${k("subjectId")} text not null,
  ${k("version")} uuid not null,
  ${k("user")} uuid not null,
  ${k("method")} text not null default 'click' check (${k("method")} in ('click', 'signature')),
  ${k("signature")} uuid,
  ${k("acknowledgedAt")} timestamptz not null default now(),
  unique (${k("subjectType")}, ${k("subjectId")}, ${k("version")}, ${k("user")})
);
create index if not exists ${ctx.tableName("acknowledgements").name}_user_idx on ${acks} (${k("tenant")}, ${k("user")});
create index if not exists ${ctx.tableName("acknowledgements").name}_subject_idx on ${acks} (${k("subjectType")}, ${k("subjectId")}, ${k("version")});
${lockTable(acks, { read: true })}
${renderPolicy(makePolicy({ table: acks, name: `${ctx.tableName("acknowledgements").name}_read`, command: "select", roles: ["authenticated"], using: `${k("user")} = (select auth.uid()) or ${ctx.scope.check(k("tenant"), read)}` }))}
`;
}

/** The functions. */
function functions(ctx: BlockSqlContext): string {
  const assignments = ctx.table("assignments");
  const acks = ctx.table("acknowledgements");
  const a = (column: string): string => ctx.col("assignments", column);
  const k = (column: string): string => ctx.col("acknowledgements", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("acknowledgements");

  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const acknowledge = ctx.permission("acknowledge", permissions.acknowledge);
  const members = ctx.of("memberships");
  const memberships = members.table("memberships");
  const mt = members.col("memberships", "tenant");
  const mu = members.col("memberships", "user");
  const mr = members.col("memberships", "role");
  const versions = ctx.of("versions");
  const versionTable = versions.table("versions");
  const vst = versions.col("versions", "subjectType");
  const vsi = versions.col("versions", "subjectId");
  const vid = versions.col("versions", "id");
  const vnum = versions.col("versions", "number");
  const vfrozen = versions.col("versions", "frozen");
  const vcreated = versions.col("versions", "createdAt");

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("ACKNOWLEDGEMENT_FORBIDDEN", message);

  const currentVersionCreated = (type: string, id: string): string =>
    `(select v.${vcreated} from ${versionTable} v where v.${vst} = ${type} and v.${vsi} = ${id} and v.${vfrozen} order by v.${vnum} desc limit 1)`;

  const covered = (type: string, id: string, tenant: string, user: string): string =>
    `exists (select 1 from ${assignments} x where x.${a("tenant")} = ${tenant} and x.${a("subjectType")} = ${type} and x.${a("subjectId")} = ${id} and (
      (x.${a("principalType")} = 'user' and x.${a("principalId")} = ${user}::text)
      or (x.${a("principalType")} = 'role' and x.${a("principalId")} = (select m.${mr} from ${memberships} m where m.${mt} = ${tenant} and m.${mu} = ${user})::text)
      ${ctx.installed("teams") ? `or (x.${a("principalType")} = 'team' and exists (select 1 from ${ctx.of("teams").table("members")} tm where tm.${ctx.of("teams").col("members", "team")}::text = x.${a("principalId")} and tm.${ctx.of("teams").col("members", "user")} = ${user}))` : ""}
    ))`;

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'subjectType', ${row}.${a("subjectType")}, 'subjectId', ${row}.${a("subjectId")}, 'principalType', ${row}.${a("principalType")}, 'principalId', ${row}.${a("principalId")}, 'dueInDays', ${row}.${a("dueInDays")}, 'createdBy', ${row}.${a("createdBy")}, 'createdAt', ${row}.${a("createdAt")})`;

  return `
-- The current frozen version of a record: the newest frozen version in versions.
create or replace function ${fn("current_acknowledgement_version")}(subject_type text, subject_id text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v.${vid}
  from ${versionTable} v
  where v.${vst} = $1 and v.${vsi} = $2 and v.${vfrozen}
  order by v.${vnum} desc
  limit 1
$$;
revoke execute on function ${fn("current_acknowledgement_version")}(text, text) from public, anon, authenticated;

-- Assigns a record's current version to a user, a team or a role.
create or replace function ${fn("assign_acknowledgement")}(tenant ${ctx.idType}, subject_type text, subject_id text, principal_type text, principal_id text, due_in_days integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${assignments}%rowtype;
  v_version uuid;
begin
  if not ${allowed("assign_acknowledgement.tenant", manage)} then
    ${forbidden("not allowed to assign acknowledgements")}
  end if;
  if principal_type not in ('user', 'team', 'role') then
    ${fail("ACKNOWLEDGEMENT_PRINCIPAL_INVALID", "principal_type must be user, team or role", "22023")}
  end if;
  if principal_type = 'user' and not exists (
    select 1 from ${memberships} m where m.${mt} = assign_acknowledgement.tenant and m.${mu} = assign_acknowledgement.principal_id::uuid
  ) then
    ${fail("ACKNOWLEDGEMENT_PRINCIPAL_INVALID", "the user must be a member of the organization", "22023")}
  end if;
  ${
    ctx.installed("teams")
      ? `if principal_type = 'team' and not exists (
    select 1 from ${ctx.of("teams").table("teams")} t where t.${ctx.of("teams").col("teams", "tenant")} = assign_acknowledgement.tenant and t.${ctx.of("teams").col("teams", "id")}::text = assign_acknowledgement.principal_id
  ) then
    ${fail("ACKNOWLEDGEMENT_PRINCIPAL_INVALID", "the team must exist in the organization", "22023")}
  end if;`
      : ""
  }
  if principal_type = 'role' and not exists (
    select 1 from ${memberships} m where m.${mt} = assign_acknowledgement.tenant and m.${mr}::text = assign_acknowledgement.principal_id
  ) then
    ${fail("ACKNOWLEDGEMENT_PRINCIPAL_INVALID", "the role must exist in the organization", "22023")}
  end if;
  v_version := ${fn("current_acknowledgement_version")}(subject_type, subject_id);
  if v_version is null then
    ${fail("ACKNOWLEDGEMENT_NO_VERSION", "the record has no frozen version to acknowledge", "22023")}
  end if;
  insert into ${assignments} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("principalType")}, ${a("principalId")}, ${a("dueInDays")})
  values (assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days)
  on conflict (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("principalType")}, ${a("principalId")}) do update
    set ${a("dueInDays")} = excluded.${a("dueInDays")}
  returning * into v_row;
  ${ctx.record({
    type: "acknowledgement_assignment.created",
    payload: `jsonb_build_object('organizationId', v_row.${a("tenant")}, 'subjectType', v_row.${a("subjectType")}, 'subjectId', v_row.${a("subjectId")}, 'assignmentId', v_row.${a("id")}, 'principalType', v_row.${a("principalType")}, 'principalId', v_row.${a("principalId")}, 'dueOn', case when v_row.${a("dueInDays")} is null then null else (${currentVersionCreated(`v_row.${a("subjectType")}`, `v_row.${a("subjectId")}`)}::date + v_row.${a("dueInDays")})::text end)`,
    subject: `'acknowledgement-assignments/' || v_row.${a("id")}::text`,
    tenant: `v_row.${a("tenant")}`,
    audit: {
      category: "data",
      targetType: "acknowledgement_assignment",
      recordId: `v_row.${a("id")}::text`,
      summary: "'assigned acknowledgement'",
    },
  })}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("assign_acknowledgement")}(${ctx.idType}, text, text, text, text, integer)`)}

create or replace function ${fn("unassign_acknowledgement")}(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${assignments}%rowtype;
begin
  select * into v_row from ${assignments} x where x.${a("id")} = unassign_acknowledgement.assignment_id;
  if not found then
    ${fail("ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND", "assignment not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${a("tenant")}`, manage)} then
    ${forbidden("not allowed to manage acknowledgements")}
  end if;
  delete from ${assignments} x where x.${a("id")} = v_row.${a("id")};
  ${ctx.record({
    type: "acknowledgement_assignment.deleted",
    payload: `jsonb_build_object('organizationId', v_row.${a("tenant")}, 'assignmentId', v_row.${a("id")})`,
    subject: `'acknowledgement-assignments/' || v_row.${a("id")}::text`,
    tenant: `v_row.${a("tenant")}`,
    audit: {
      category: "data",
      targetType: "acknowledgement_assignment",
      recordId: `v_row.${a("id")}::text`,
      summary: "'removed acknowledgement assignment'",
    },
  })}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("unassign_acknowledgement")}(uuid)`)}

create or replace function ${fn("list_acknowledgement_assignments")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("x")} order by x.${a("createdAt")} desc), '[]'::jsonb)
  from ${assignments} x
  where x.${a("subjectType")} = $1 and x.${a("subjectId")} = $2
    and ${ctx.scope.check(`x.${a("tenant")}`, read)}
$$;
${userGrant(`${fn("list_acknowledgement_assignments")}(text, text)`)}

-- A member acknowledges the current version of a record they are assigned.
create or replace function ${fn("acknowledge")}(subject_type text, subject_id text, version_id uuid default null, signature_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${acks}%rowtype;
  v_tenant ${ctx.idType};
  v_version uuid;
  v_current uuid;
begin
  select m.${mt} into v_tenant from ${memberships} m where m.${mu} = auth.uid() limit 1;
  if v_tenant is null or not ${ctx.can("tenant", "v_tenant", acknowledge)} then
    ${forbidden("not allowed to acknowledge")}
  end if;
  v_current := ${fn("current_acknowledgement_version")}(subject_type, subject_id);
  if v_current is null then
    ${fail("ACKNOWLEDGEMENT_NO_VERSION", "the record has no frozen version to acknowledge", "22023")}
  end if;
  if version_id is not null and version_id <> v_current then
    ${fail("ACKNOWLEDGEMENT_VERSION_STALE", "the record has a newer version", "22023")}
  end if;
  if not ${covered("subject_type", "subject_id", "v_tenant", "auth.uid()")} then
    ${fail("ACKNOWLEDGEMENT_NOT_ASSIGNED", "you are not assigned this record", "42501")}
  end if;
  ${
    ctx.installed("signatures")
      ? `if signature_id is not null and not exists (
    select 1 from ${ctx.of("signatures").table("requests")} s
    where s.${ctx.of("signatures").col("requests", "id")} = acknowledge.signature_id
      and s.${ctx.of("signatures").col("requests", "status")} = 'completed'
      and s.${ctx.of("signatures").col("requests", "subjectType")} = acknowledge.subject_type
      and s.${ctx.of("signatures").col("requests", "subjectId")} = acknowledge.subject_id
  ) then
    ${fail("ACKNOWLEDGEMENT_SIGNATURE_INVALID", "the signature is not completed for this record", "22023")}
  end if;`
      : ""
  }
  insert into ${acks} (${k("tenant")}, ${k("subjectType")}, ${k("subjectId")}, ${k("version")}, ${k("user")}, ${k("method")}, ${k("signature")})
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, coalesce(acknowledge.version_id, v_current), auth.uid(), case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict (${k("subjectType")}, ${k("subjectId")}, ${k("version")}, ${k("user")}) do nothing
  returning * into v_row;
  if v_row.${k("id")} is null then
    select * into v_row from ${acks} x where x.${k("subjectType")} = acknowledge.subject_type and x.${k("subjectId")} = acknowledge.subject_id and x.${k("version")} = coalesce(acknowledge.version_id, v_current) and x.${k("user")} = auth.uid();
  else
    ${ctx.record({
      type: "acknowledgement.created",
      payload: `jsonb_build_object('organizationId', v_row.${k("tenant")}, 'subjectType', v_row.${k("subjectType")}, 'subjectId', v_row.${k("subjectId")}, 'versionId', v_row.${k("version")}, 'userId', v_row.${k("user")}, 'method', v_row.${k("method")})`,
      subject: `'acknowledgements/' || v_row.${k("id")}::text`,
      tenant: `v_row.${k("tenant")}`,
      audit: {
        category: "security",
        targetType: "acknowledgement",
        recordId: `v_row.${k("id")}::text`,
        summary: "'acknowledged record'",
      },
    })}
  end if;
  return jsonb_build_object('id', v_row.${k("id")}, 'organizationId', v_row.${k("tenant")}, 'subjectType', v_row.${k("subjectType")}, 'subjectId', v_row.${k("subjectId")}, 'versionId', v_row.${k("version")}, 'userId', v_row.${k("user")}, 'method', v_row.${k("method")}, 'signatureId', v_row.${k("signature")}, 'acknowledgedAt', v_row.${k("acknowledgedAt")});
end;
$$;
${userGrant(`${fn("acknowledge")}(text, text, uuid, uuid)`)}

create or replace function ${fn("list_my_acknowledgements")}(tenant ${ctx.idType}, pending_only boolean default true)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', x.${a("subjectType")},
    'subjectId', x.${a("subjectId")},
    'assignmentId', x.${a("id")},
    'versionId', ${fn("current_acknowledgement_version")}(x.${a("subjectType")}, x.${a("subjectId")}),
    'dueOn', case when x.${a("dueInDays")} is null then null else (${currentVersionCreated(`x.${a("subjectType")}`, `x.${a("subjectId")}`)}::date + x.${a("dueInDays")})::text end,
    'overdue', case when x.${a("dueInDays")} is not null and (${currentVersionCreated(`x.${a("subjectType")}`, `x.${a("subjectId")}`)}::date + x.${a("dueInDays")}) < current_date then true else false end,
    'acknowledgedAt', (select ack.${k("acknowledgedAt")} from ${acks} ack where ack.${k("subjectType")} = x.${a("subjectType")} and ack.${k("subjectId")} = x.${a("subjectId")} and ack.${k("version")} = ${fn("current_acknowledgement_version")}(x.${a("subjectType")}, x.${a("subjectId")}) and ack.${k("user")} = auth.uid())
  ) order by x.${a("createdAt")} desc), '[]'::jsonb)
  from ${assignments} x
  where x.${a("tenant")} = list_my_acknowledgements.tenant
    and ${covered(`x.${a("subjectType")}`, `x.${a("subjectId")}`, `x.${a("tenant")}`, "auth.uid()")}
    and (not list_my_acknowledgements.pending_only or not exists (
      select 1 from ${acks} ack where ack.${k("subjectType")} = x.${a("subjectType")} and ack.${k("subjectId")} = x.${a("subjectId")} and ack.${k("version")} = ${fn("current_acknowledgement_version")}(x.${a("subjectType")}, x.${a("subjectId")}) and ack.${k("user")} = auth.uid()
    ))
$$;
${userGrant(`${fn("list_my_acknowledgements")}(${ctx.idType}, boolean)`)}

create or replace function ${fn("acknowledgement_status")}(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_version uuid;
begin
  select x.${a("tenant")} into v_tenant from ${assignments} x where x.${a("subjectType")} = acknowledgement_status.subject_type and x.${a("subjectId")} = acknowledgement_status.subject_id limit 1;
  if v_tenant is null then
    ${fail("ACKNOWLEDGEMENT_NOT_ASSIGNED", "the record has no assignment", "P0002")}
  end if;
  if not ${ctx.can("tenant", "v_tenant", read)} then
    ${forbidden("not allowed to read acknowledgements")}
  end if;
  v_version := ${fn("current_acknowledgement_version")}(subject_type, subject_id);
  return jsonb_build_object(
    'versionId', v_version,
    'required', (select count(*) from ${assignments} x where x.${a("subjectType")} = acknowledgement_status.subject_type and x.${a("subjectId")} = acknowledgement_status.subject_id),
    'acknowledged', (select count(*) from ${acks} ack where ack.${k("subjectType")} = acknowledgement_status.subject_type and ack.${k("subjectId")} = acknowledgement_status.subject_id and ack.${k("version")} = v_version),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('userId', m.${mu}, 'dueOn', case when x.${a("dueInDays")} is null then null else (${currentVersionCreated("acknowledgement_status.subject_type", "acknowledgement_status.subject_id")}::date + x.${a("dueInDays")})::text end, 'overdue', case when x.${a("dueInDays")} is not null and (${currentVersionCreated("acknowledgement_status.subject_type", "acknowledgement_status.subject_id")}::date + x.${a("dueInDays")}) < current_date then true else false end)) from ${memberships} m join ${assignments} x on x.${a("tenant")} = m.${mt} and ((x.${a("principalType")} = 'user' and x.${a("principalId")} = m.${mu}::text) or (x.${a("principalType")} = 'role' and x.${a("principalId")} = m.${mr}::text)) where m.${mt} = v_tenant and x.${a("subjectType")} = acknowledgement_status.subject_type and x.${a("subjectId")} = acknowledgement_status.subject_id and not exists (select 1 from ${acks} ack where ack.${k("subjectType")} = acknowledgement_status.subject_type and ack.${k("subjectId")} = acknowledgement_status.subject_id and ack.${k("version")} = v_version and ack.${k("user")} = m.${mu})), '[]'::jsonb)
  );
end;
$$;
${userGrant(`${fn("acknowledgement_status")}(text, text)`)}

create or replace function ${fn("acknowledgements_of")}(subject_type text, subject_id text, version_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', x.${k("user")}, 'versionId', x.${k("version")}, 'method', x.${k("method")}, 'signatureId', x.${k("signature")}, 'acknowledgedAt', x.${k("acknowledgedAt")}) order by x.${k("acknowledgedAt")} desc), '[]'::jsonb)
  from ${acks} x
  where x.${k("subjectType")} = $1 and x.${k("subjectId")} = $2
    and ($3 is null or x.${k("version")} = $3)
    and ${ctx.scope.check(`x.${k("tenant")}`, read)}
$$;
${userGrant(`${fn("acknowledgements_of")}(text, text, uuid)`)}

create or replace function ${fn("notify_due_acknowledgements")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
  v_due date;
  v_version uuid;
begin
  for v_row in
    select x.*, ${currentVersionCreated(`x.${a("subjectType")}`, `x.${a("subjectId")}`)}::date as version_on,
      ${fn("current_acknowledgement_version")}(x.${a("subjectType")}, x.${a("subjectId")}) as version_id
    from ${assignments} x
    where x.${a("dueInDays")} is not null
  loop
    v_due := v_row.version_on + v_row.${a("dueInDays")};
    v_version := v_row.version_id;
    if v_version is not null and v_due <= current_date then
      ${ctx.notify(`jsonb_build_object('organizationId', v_row.${a("tenant")}, 'subjectType', v_row.${a("subjectType")}, 'subjectId', v_row.${a("subjectId")}, 'versionId', v_version, 'userId', v_row.${a("principalId")}, 'dueOn', v_due::text)`)}
      ${ctx.record({
        type: "acknowledgement.expired",
        payload: `jsonb_build_object('organizationId', v_row.${a("tenant")}, 'subjectType', v_row.${a("subjectType")}, 'subjectId', v_row.${a("subjectId")}, 'versionId', v_version, 'userId', v_row.${a("principalId")}, 'dueOn', v_due::text)`,
        subject: `'acknowledgements/' || v_version::text || '/' || v_row.${a("principalId")}`,
        tenant: `v_row.${a("tenant")}`,
        audit: {
          category: "data",
          targetType: "acknowledgement",
          recordId: `v_version::text`,
          summary: "'acknowledgement expired'",
        },
      })}
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_due_acknowledgements")}()`)}

`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("versions").mode === "custom") {
    throw new TypeError(
      "blocks.acknowledgements needs the versions tables; versions can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- Acknowledgements: which member read which version of a record, and the
-- assignments that make a version due.
${tables(ctx)}${functions(ctx)}`;
}

function contract(_ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "assign_acknowledgement",
      args: ["{id}", "text", "text", "text", "text", "integer"],
      returns: "jsonb",
    },
    { name: "unassign_acknowledgement", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_acknowledgement_assignments",
      args: ["text", "text"],
      returns: "jsonb",
    },
    {
      name: "acknowledge",
      args: ["text", "text", "uuid", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_my_acknowledgements",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "acknowledgement_status",
      args: ["text", "text"],
      returns: "jsonb",
    },
    {
      name: "acknowledgements_of",
      args: ["text", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "notify_due_acknowledgements", args: [], returns: "integer" },
  ];
}

export const ACKNOWLEDGEMENTS: BlockSqlDefinition = {
  name: "acknowledgements",
  scopes: ["tenant"],
  title: "Acknowledgements",
  description:
    "Which member acknowledged which version of a record, with assignments to users, teams and roles, a due date, an effectiveness status and overdue notifications.",
  requires: ["memberships", "permissions", "subjects", "versions"],
  integrates: ["teams", "notifications", "signatures", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
