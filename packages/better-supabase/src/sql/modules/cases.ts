import type { CasesEvents } from "../../blocks/cases/events.ts";
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

const EVENTS: BlockSqlEvents<CasesEvents> = {
  "case.created": {
    subject: "cases",
    payload: ["organizationId", "caseId", "kind", "number"],
  },
  "case.updated": {
    subject: "cases",
    payload: ["organizationId", "caseId", "kind", "number", "changed"],
  },
  "case.root_cause_recorded": {
    subject: "cases",
    payload: ["organizationId", "caseId", "kind", "number"],
  },
  "case.action_added": {
    subject: "cases",
    payload: ["organizationId", "caseId", "actionId", "type"],
  },
  "case.action_completed": {
    subject: "cases",
    payload: ["organizationId", "caseId", "actionId"],
  },
  "case.effectiveness_recorded": {
    subject: "cases",
    payload: ["organizationId", "caseId", "kind", "number", "effective"],
  },
  "case.closed": {
    subject: "cases",
    payload: ["organizationId", "caseId", "kind", "number"],
  },
  "case.reopened": {
    subject: "cases",
    payload: ["organizationId", "caseId", "kind", "number"],
  },
  "case.cancelled": {
    subject: "cases",
    payload: ["organizationId", "caseId", "kind", "number"],
  },
  "case_kind.created": {
    subject: "case-kinds",
    payload: ["organizationId", "kindId", "key"],
  },
  "case_kind.updated": {
    subject: "case-kinds",
    payload: ["organizationId", "kindId", "key"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    case: {
      table: "cases",
      singular: "case",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["number", "description", "rootCause"] },
        deletedAt: "archivedAt",
      },
    },
    case_kind: { table: "kinds", singular: "case_kind" },
    case_action: { table: "actions", singular: "case_action" },
  },
  events: EVENTS,
  hooks: [
    "before_case_open",
    "after_case_open",
    "before_case_update",
    "after_case_update",
    "before_case_close",
    "after_case_close",
  ],
  options: ["extraColumns", "kinds", "severities", "sources"],
  tables: {
    kinds: {
      name: "case_kinds",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        prefix: "prefix",
        requiresRootCause: "requires_root_cause",
        requiresActions: "requires_actions",
        requiresEffectiveness: "requires_effectiveness",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["archivedAt", "createdAt", "updatedAt"],
    },
    cases: {
      name: "cases",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind_id",
        number: "number",
        title: "title",
        description: "description",
        severity: "severity",
        source: "source",
        reporter: "reporter_id",
        owner: "owner_id",
        occurredAt: "occurred_at",
        detectedAt: "detected_at",
        dueOn: "due_on",
        status: "status",
        rootCause: "root_cause",
        effective: "effective",
        effectivenessDueOn: "effectiveness_due_on",
        closedAt: "closed_at",
        closedBy: "closed_by",
        closeNote: "close_note",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "reporter",
        "owner",
        "occurredAt",
        "dueOn",
        "rootCause",
        "effective",
        "effectivenessDueOn",
        "closedAt",
        "closedBy",
        "closeNote",
        "archivedAt",
        "createdBy",
        "createdAt",
        "updatedAt",
      ],
    },
    actions: {
      name: "case_actions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        case: "case_id",
        type: "type",
        title: "title",
        assignee: "assignee_id",
        dueAt: "due_at",
        required: "required",
        completedAt: "completed_at",
        createdAt: "created_at",
      },
      optional: ["assignee", "dueAt", "completedAt", "createdAt"],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const kinds = ctx.table("kinds");
  const cases = ctx.table("cases");
  const actions = ctx.table("actions");
  const k = (column: string): string => ctx.col("kinds", column);
  const c = (column: string): string => ctx.col("cases", column);
  const a = (column: string): string => ctx.col("actions", column);
  const permissions = moduleOperations("cases");
  const read = ctx.permission("read", permissions.read);

  const extras = ctx.extraColumns("cases", [
    "id",
    "tenant",
    "kind",
    "number",
    "title",
    "description",
    "severity",
    "source",
    "reporter",
    "owner",
    "occurredAt",
    "detectedAt",
    "dueOn",
    "status",
    "rootCause",
    "effective",
    "effectivenessDueOn",
    "closedAt",
    "closedBy",
    "closeNote",
    "archivedAt",
    "createdBy",
    "createdAt",
    "updatedAt",
  ]);

  return `
create table if not exists ${kinds} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("key")} text not null check (${k("key")} ~ '^[a-z][a-z0-9_]{0,40}$'),
  ${k("name")} text not null,
  ${k("prefix")} text not null check (${k("prefix")} ~ '^[A-Z]{1,6}$'),
  ${k("requiresRootCause")} boolean not null default true,
  ${k("requiresActions")} boolean not null default true,
  ${k("requiresEffectiveness")} boolean not null default false,
  ${k("archivedAt")} timestamptz,
  ${k("createdAt")} timestamptz not null default now(),
  ${k("updatedAt")} timestamptz not null default now(),
  unique (${k("tenant")}, ${k("key")})
);
${lockTable(kinds, { read: true })}
${renderPolicy(makePolicy({ table: kinds, name: `${ctx.tableName("kinds").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(k("tenant"), read) }))}

create table if not exists ${cases} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("kind")} uuid not null,
  ${c("number")} text not null,
  ${c("title")} text not null check (length(${c("title")}) between 1 and 200),
  ${c("description")} text,
  ${c("severity")} text,
  ${c("source")} text,
  ${c("reporter")} uuid,
  ${c("owner")} uuid,
  ${c("occurredAt")} timestamptz,
  ${c("detectedAt")} timestamptz not null default now(),
  ${c("dueOn")} date,
  ${c("status")} text not null default 'open' check (${c("status")} in ('open', 'closed', 'canceled')),
  ${c("rootCause")} text,
  ${c("effective")} boolean,
  ${c("effectivenessDueOn")} date,
  ${c("closedAt")} timestamptz,
  ${c("closedBy")} uuid,
  ${c("closeNote")} text,
  ${c("archivedAt")} timestamptz,
  ${c("createdBy")} uuid default auth.uid(),
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  unique (${c("tenant")}, ${c("number")}),
  foreign key (${c("tenant")}, ${c("kind")}) references ${kinds} (${k("tenant")}, ${k("id")})
);${addExtraColumns(cases, extras)}
create index if not exists ${ctx.tableName("cases").name}_status_idx on ${cases} (${c("tenant")}, ${c("status")});
create index if not exists ${ctx.tableName("cases").name}_kind_idx on ${cases} (${c("tenant")}, ${c("kind")});
create index if not exists ${ctx.tableName("cases").name}_owner_idx on ${cases} (${c("owner")}) where ${c("owner")} is not null;
${lockTable(cases, { read: true })}
${renderPolicy(makePolicy({ table: cases, name: `${ctx.tableName("cases").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(c("tenant"), read) }))}

create table if not exists ${actions} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("case")} uuid not null,
  ${a("type")} text not null check (${a("type")} in ('containment', 'correction', 'corrective', 'preventive', 'improvement')),
  ${a("title")} text not null check (length(${a("title")}) between 1 and 200),
  ${a("assignee")} uuid,
  ${a("dueAt")} timestamptz,
  ${a("required")} boolean not null default true,
  ${a("completedAt")} timestamptz,
  ${a("createdAt")} timestamptz not null default now(),
  foreign key (${a("case")}) references ${cases} (${c("id")}) on delete cascade
);
create index if not exists ${ctx.tableName("actions").name}_parent_idx on ${actions} (${a("case")});
${lockTable(actions, { read: true })}
${renderPolicy(makePolicy({ table: actions, name: `${ctx.tableName("actions").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(a("tenant"), read) }))}
`;
}

function functions(ctx: BlockSqlContext): string {
  const kinds = ctx.table("kinds");
  const cases = ctx.table("cases");
  const actions = ctx.table("actions");
  const k = (column: string): string => ctx.col("kinds", column);
  const c = (column: string): string => ctx.col("cases", column);
  const a = (column: string): string => ctx.col("actions", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("cases");
  const read = ctx.permission("read", permissions.read);
  const create = ctx.permission("create", permissions.create);
  const write = ctx.permission("write", permissions.write);
  const close = ctx.permission("close", permissions.close);
  const manage = ctx.permission("manage", permissions.manage);
  const members = ctx.of("memberships");
  const memberships = members.table("memberships");
  const mt = members.col("memberships", "tenant");
  const mu = members.col("memberships", "user");

  const allowed = (tenant: string, permission: string): string =>
    `(select auth.uid()) is not null and ${ctx.can("tenant", tenant, permission)}`;

  const forbidden = (message: string): string =>
    fail("CASE_FORBIDDEN", message);

  const notFound = fail("CASE_NOT_FOUND", "case not found", "P0002");

  const caseJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'kindId', ${row}.${c("kind")}, 'number', ${row}.${c("number")}, 'title', ${row}.${c("title")}, 'description', ${row}.${c("description")}, 'severity', ${row}.${c("severity")}, 'source', ${row}.${c("source")}, 'reporterId', ${row}.${c("reporter")}, 'ownerId', ${row}.${c("owner")}, 'occurredAt', ${row}.${c("occurredAt")}, 'detectedAt', ${row}.${c("detectedAt")}, 'dueOn', ${row}.${c("dueOn")}, 'status', ${row}.${c("status")}, 'rootCause', ${row}.${c("rootCause")}, 'effective', ${row}.${c("effective")}, 'effectivenessDueOn', ${row}.${c("effectivenessDueOn")}, 'closedAt', ${row}.${c("closedAt")}, 'closedBy', ${row}.${c("closedBy")}, 'closeNote', ${row}.${c("closeNote")}, 'archivedAt', ${row}.${c("archivedAt")}, 'createdAt', ${row}.${c("createdAt")}, 'updatedAt', ${row}.${c("updatedAt")})`;

  const kindJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${k("id")}, 'organizationId', ${row}.${k("tenant")}, 'key', ${row}.${k("key")}, 'name', ${row}.${k("name")}, 'prefix', ${row}.${k("prefix")}, 'requiresRootCause', ${row}.${k("requiresRootCause")}, 'requiresActions', ${row}.${k("requiresActions")}, 'requiresEffectiveness', ${row}.${k("requiresEffectiveness")}, 'archivedAt', ${row}.${k("archivedAt")}, 'createdAt', ${row}.${k("createdAt")}, 'updatedAt', ${row}.${k("updatedAt")})`;

  const actionJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'caseId', ${row}.${a("case")}, 'type', ${row}.${a("type")}, 'title', ${row}.${a("title")}, 'assigneeId', ${row}.${a("assignee")}, 'dueAt', ${row}.${a("dueAt")}, 'required', ${row}.${a("required")}, 'completedAt', ${row}.${a("completedAt")}, 'createdAt', ${row}.${a("createdAt")})`;

  return `
create or replace function ${fn("save_case_kind")}(tenant ${ctx.idType}, key text, name text, prefix text, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${kinds}%rowtype;
  v_created boolean := false;
begin
  if not ${allowed("save_case_kind.tenant", manage)} then
    ${forbidden("not allowed to manage case kinds")}
  end if;
  if save_case_kind.key !~ '^[a-z][a-z0-9_]{0,40}$' or save_case_kind.prefix !~ '^[A-Z]{1,6}$' then
    ${fail("CASE_KIND_INVALID", "key and prefix are invalid", "22023")}
  end if;
  if save_case_kind.kind_id is null then
    insert into ${kinds} (${k("tenant")}, ${k("key")}, ${k("name")}, ${k("prefix")}, ${k("requiresRootCause")}, ${k("requiresActions")}, ${k("requiresEffectiveness")})
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false))
    on conflict (${k("tenant")}, ${k("key")}) do update
      set ${k("name")} = excluded.${k("name")}, ${k("prefix")} = excluded.${k("prefix")},
        ${k("requiresRootCause")} = excluded.${k("requiresRootCause")},
        ${k("requiresActions")} = excluded.${k("requiresActions")},
        ${k("requiresEffectiveness")} = excluded.${k("requiresEffectiveness")},
        ${k("updatedAt")} = now()
    returning * into v_row;
    v_created := true;
  else
    update ${kinds} x set ${k("key")} = save_case_kind.key, ${k("name")} = trim(save_case_kind.name), ${k("prefix")} = save_case_kind.prefix,
      ${k("requiresRootCause")} = coalesce(save_case_kind.requires_root_cause, true),
      ${k("requiresActions")} = coalesce(save_case_kind.requires_actions, true),
      ${k("requiresEffectiveness")} = coalesce(save_case_kind.requires_effectiveness, false),
      ${k("updatedAt")} = now()
      where x.${k("id")} = save_case_kind.kind_id and x.${k("tenant")} = save_case_kind.tenant
      returning * into v_row;
    if not found then
      ${fail("CASE_KIND_NOT_FOUND", "case kind not found", "P0002")}
    end if;
  end if;
  if v_created then
    ${ctx.record({
      type: "case_kind.created",
      payload: `jsonb_build_object('organizationId', v_row.${k("tenant")}, 'kindId', v_row.${k("id")}, 'key', v_row.${k("key")})`,
      subject: `'case-kinds/' || v_row.${k("id")}::text`,
      tenant: `v_row.${k("tenant")}`,
      audit: {
        category: "data",
        targetType: "case_kind",
        recordId: `v_row.${k("id")}::text`,
        summary: "'saved case kind'",
      },
    })}
  else
    ${ctx.record({
      type: "case_kind.updated",
      payload: `jsonb_build_object('organizationId', v_row.${k("tenant")}, 'kindId', v_row.${k("id")}, 'key', v_row.${k("key")})`,
      subject: `'case-kinds/' || v_row.${k("id")}::text`,
      tenant: `v_row.${k("tenant")}`,
      audit: {
        category: "data",
        targetType: "case_kind",
        recordId: `v_row.${k("id")}::text`,
        summary: "'saved case kind'",
      },
    })}
  end if;
  return ${kindJson("v_row")};
end;
$$;
${userGrant(`${fn("save_case_kind")}(${ctx.idType}, text, text, text, boolean, boolean, boolean, uuid)`)}

create or replace function ${fn("archive_case_kind")}(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${kinds}%rowtype;
begin
  select * into v_row from ${kinds} x where x.${k("id")} = archive_case_kind.kind_id;
  if not found then
    ${fail("CASE_KIND_NOT_FOUND", "case kind not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${k("tenant")}`, manage)} then
    ${forbidden("not allowed to manage case kinds")}
  end if;
  update ${kinds} x set ${k("archivedAt")} = now(), ${k("updatedAt")} = now() where x.${k("id")} = v_row.${k("id")} returning * into v_row;
  return ${kindJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_case_kind")}(uuid)`)}

create or replace function ${fn("list_case_kinds")}(tenant ${ctx.idType}, include_archived boolean default false)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${kindJson("x")} order by x.${k("key")}), '[]'::jsonb)
  from ${kinds} x
  where x.${k("tenant")} = $1 and (include_archived or x.${k("archivedAt")} is null)
    and ${ctx.scope.check(`x.${k("tenant")}`, read)}
$$;
${userGrant(`${fn("list_case_kinds")}(${ctx.idType}, boolean)`)}

create or replace function ${fn("open_case")}(tenant ${ctx.idType}, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind ${kinds}%rowtype;
  v_row ${cases}%rowtype;
  v_number text;
begin
  if not ${allowed("open_case.tenant", create)} then
    ${forbidden("not allowed to create cases")}
  end if;
  select * into v_kind from ${kinds} x where x.${k("tenant")} = open_case.tenant and x.${k("key")} = open_case.kind;
  if not found then
    ${fail("CASE_KIND_NOT_FOUND", "case kind not found", "P0002")}
  end if;
  if v_kind.${k("archivedAt")} is not null then
    ${fail("CASE_KIND_ARCHIVED", "the case kind is archived", "55000")}
  end if;
  if open_case.owner_id is not null and not exists (select 1 from ${memberships} m where m.${mt} = open_case.tenant and m.${mu} = open_case.owner_id) then
    ${fail("CASE_INVALID", "the owner must be a member", "22023")}
  end if;
  select v_kind.${k("prefix")} || '-' || to_char(current_date, 'YYYY') || '-' || lpad((count(*) + 1)::text, 4, '0') into v_number
    from ${cases} x where x.${c("tenant")} = open_case.tenant and x.${c("kind")} = v_kind.${k("id")};
  insert into ${cases} (${c("tenant")}, ${c("kind")}, ${c("number")}, ${c("title")}, ${c("description")}, ${c("severity")}, ${c("source")}, ${c("occurredAt")}, ${c("owner")}, ${c("dueOn")})
  values (open_case.tenant, v_kind.${k("id")}, v_number, trim(open_case.title), open_case.description, open_case.severity, open_case.source, open_case.occurred_at, open_case.owner_id, open_case.due_on)
  returning * into v_row;
  ${ctx.hook("before_case_open", [["uuid", `v_row.${c("id")}`]])}
  ${ctx.record({
    type: "case.created",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'caseId', v_row.${c("id")}, 'kind', v_kind.${k("key")}, 'number', v_row.${c("number")})`,
    subject: `'cases/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "case",
      recordId: `v_row.${c("id")}::text`,
      summary: `'opened case ' || v_row.${c("number")}`,
    },
  })}
  ${ctx.hook("after_case_open", [["uuid", `v_row.${c("id")}`]])}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("open_case")}(${ctx.idType}, text, text, text, text, text, timestamptz, uuid, date)`)}

create or replace function ${fn("update_case")}(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${cases}%rowtype;
  v_changed text[] := '{}';
begin
  select * into v_row from ${cases} x where x.${c("id")} = update_case.case_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, write)} then
    ${forbidden("not allowed to change cases")}
  end if;
  if v_row.${c("status")} <> 'open' then
    ${fail("CASE_CLOSED", "a closed case can't change", "55000")}
  end if;
  if changes ? 'title' then v_row.${c("title")} := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row.${c("description")} := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'severity' then v_row.${c("severity")} := changes ->> 'severity'; v_changed := array_append(v_changed, 'severity'); end if;
  if changes ? 'ownerId' then v_row.${c("owner")} := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'dueOn' then v_row.${c("dueOn")} := (changes ->> 'dueOn')::date; v_changed := array_append(v_changed, 'dueOn'); end if;
  if changes ? 'occurredAt' then v_row.${c("occurredAt")} := (changes ->> 'occurredAt')::timestamptz; v_changed := array_append(v_changed, 'occurredAt'); end if;
  update ${cases} x set ${c("title")} = v_row.${c("title")}, ${c("description")} = v_row.${c("description")}, ${c("severity")} = v_row.${c("severity")}, ${c("owner")} = v_row.${c("owner")}, ${c("dueOn")} = v_row.${c("dueOn")}, ${c("occurredAt")} = v_row.${c("occurredAt")}, ${c("updatedAt")} = now()
    where x.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${ctx.record({
    type: "case.updated",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'caseId', v_row.${c("id")}, 'kind', '', 'number', v_row.${c("number")}, 'changed', to_jsonb(v_changed))`,
    subject: `'cases/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "case",
      recordId: `v_row.${c("id")}::text`,
      summary: `'changed case ' || v_row.${c("number")}`,
    },
  })}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("update_case")}(uuid, jsonb)`)}

create or replace function ${fn("record_case_root_cause")}(case_id uuid, root_cause text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${cases}%rowtype;
begin
  select * into v_row from ${cases} x where x.${c("id")} = record_case_root_cause.case_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, write)} then
    ${forbidden("not allowed to change cases")}
  end if;
  if v_row.${c("status")} <> 'open' then
    ${fail("CASE_CLOSED", "a closed case can't change", "55000")}
  end if;
  update ${cases} x set ${c("rootCause")} = trim(record_case_root_cause.root_cause), ${c("updatedAt")} = now() where x.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${ctx.record({
    type: "case.root_cause_recorded",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'caseId', v_row.${c("id")}, 'kind', '', 'number', v_row.${c("number")})`,
    subject: `'cases/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "case",
      recordId: `v_row.${c("id")}::text`,
      summary: `'recorded root cause for ' || v_row.${c("number")}`,
    },
  })}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("record_case_root_cause")}(uuid, text)`)}

create or replace function ${fn("create_case_action")}(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case ${cases}%rowtype;
  v_row ${actions}%rowtype;
begin
  select * into v_case from ${cases} x where x.${c("id")} = create_case_action.case_id;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_case.${c("tenant")}`, write)} then
    ${forbidden("not allowed to change cases")}
  end if;
  if v_case.${c("status")} <> 'open' then
    ${fail("CASE_CLOSED", "a closed case can't change", "55000")}
  end if;
  if create_case_action.type not in ('containment', 'correction', 'corrective', 'preventive', 'improvement') then
    ${fail("CASE_INVALID", "the action type is invalid", "22023")}
  end if;
  insert into ${actions} (${a("tenant")}, ${a("case")}, ${a("type")}, ${a("title")}, ${a("assignee")}, ${a("dueAt")}, ${a("required")})
  values (v_case.${c("tenant")}, v_case.${c("id")}, create_case_action.type, trim(create_case_action.title), create_case_action.assignee_id, create_case_action.due_at, coalesce(create_case_action.required, true))
  returning * into v_row;
  ${ctx.record({
    type: "case.action_added",
    payload: `jsonb_build_object('organizationId', v_row.${a("tenant")}, 'caseId', v_row.${a("case")}, 'actionId', v_row.${a("id")}, 'type', v_row.${a("type")})`,
    subject: `'cases/' || v_row.${a("case")}::text`,
    tenant: `v_row.${a("tenant")}`,
    audit: {
      category: "data",
      targetType: "case_action",
      recordId: `v_row.${a("id")}::text`,
      summary: "'added case action'",
    },
  })}
  return ${actionJson("v_row")};
end;
$$;
${userGrant(`${fn("create_case_action")}(uuid, text, text, uuid, timestamptz, boolean)`)}

create or replace function ${fn("complete_case_action")}(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${actions}%rowtype;
begin
  select * into v_row from ${actions} x where x.${a("id")} = complete_case_action.action_id;
  if not found then
    ${fail("CASE_ACTION_NOT_FOUND", "case action not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${a("tenant")}`, write)} then
    ${forbidden("not allowed to change cases")}
  end if;
  update ${actions} x set ${a("completedAt")} = now() where x.${a("id")} = v_row.${a("id")} returning * into v_row;
  ${ctx.record({
    type: "case.action_completed",
    payload: `jsonb_build_object('organizationId', v_row.${a("tenant")}, 'caseId', v_row.${a("case")}, 'actionId', v_row.${a("id")})`,
    subject: `'cases/' || v_row.${a("case")}::text`,
    tenant: `v_row.${a("tenant")}`,
    audit: {
      category: "data",
      targetType: "case_action",
      recordId: `v_row.${a("id")}::text`,
      summary: "'completed case action'",
    },
  })}
  return ${actionJson("v_row")};
end;
$$;
${userGrant(`${fn("complete_case_action")}(uuid)`)}

create or replace function ${fn("remove_case_action")}(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${actions}%rowtype;
begin
  select * into v_row from ${actions} x where x.${a("id")} = remove_case_action.action_id;
  if not found then
    ${fail("CASE_ACTION_NOT_FOUND", "case action not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${a("tenant")}`, write)} then
    ${forbidden("not allowed to change cases")}
  end if;
  delete from ${actions} x where x.${a("id")} = v_row.${a("id")};
  return ${actionJson("v_row")};
end;
$$;
${userGrant(`${fn("remove_case_action")}(uuid)`)}

create or replace function ${fn("record_case_effectiveness")}(case_id uuid, effective boolean, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${cases}%rowtype;
begin
  select * into v_row from ${cases} x where x.${c("id")} = record_case_effectiveness.case_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, write)} then
    ${forbidden("not allowed to change cases")}
  end if;
  update ${cases} x set ${c("effective")} = record_case_effectiveness.effective, ${c("updatedAt")} = now() where x.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${ctx.record({
    type: "case.effectiveness_recorded",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'caseId', v_row.${c("id")}, 'kind', '', 'number', v_row.${c("number")}, 'effective', v_row.${c("effective")})`,
    subject: `'cases/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "case",
      recordId: `v_row.${c("id")}::text`,
      summary: `'recorded effectiveness for ' || v_row.${c("number")}`,
    },
  })}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("record_case_effectiveness")}(uuid, boolean, text)`)}

create or replace function ${fn("case_close_blockers")}(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_case ${cases}%rowtype;
  v_kind ${kinds}%rowtype;
  v_blockers text[] := '{}';
begin
  select * into v_case from ${cases} x where x.${c("id")} = case_close_blockers.case_id;
  if not found then
    return v_blockers;
  end if;
  select * into v_kind from ${kinds} x where x.${k("id")} = v_case.${c("kind")};
  if v_kind.${k("requiresRootCause")} and v_case.${c("rootCause")} is null then
    v_blockers := array_append(v_blockers, 'CASE_ROOT_CAUSE_REQUIRED');
  end if;
  if v_kind.${k("requiresActions")} and not exists (select 1 from ${actions} x where x.${a("case")} = v_case.${c("id")}) then
    v_blockers := array_append(v_blockers, 'CASE_ACTIONS_REQUIRED');
  end if;
  if exists (select 1 from ${actions} x where x.${a("case")} = v_case.${c("id")} and x.${a("required")} and x.${a("completedAt")} is null) then
    v_blockers := array_append(v_blockers, 'CASE_ACTIONS_OPEN');
  end if;
  if v_kind.${k("requiresEffectiveness")} and v_case.${c("effective")} is distinct from true then
    v_blockers := array_append(v_blockers, 'CASE_EFFECTIVENESS_REQUIRED');
  end if;
  return v_blockers;
end;
$$;
${userGrant(`${fn("case_close_blockers")}(uuid)`)}

create or replace function ${fn("close_case")}(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${cases}%rowtype;
  v_blockers text[];
begin
  select * into v_row from ${cases} x where x.${c("id")} = close_case.case_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, close)} then
    ${forbidden("not allowed to close cases")}
  end if;
  if v_row.${c("status")} <> 'open' then
    ${fail("CASE_CLOSED", "the case is not open", "55000")}
  end if;
  v_blockers := ${fn("case_close_blockers")}(v_row.${c("id")});
  if cardinality(v_blockers) > 0 then
    ${fail("CASE_ACTIONS_OPEN", "the case has open blockers", "22023")}
  end if;
  update ${cases} x set ${c("status")} = 'closed', ${c("closedAt")} = now(), ${c("closedBy")} = auth.uid(), ${c("closeNote")} = close_case.note, ${c("updatedAt")} = now() where x.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${ctx.record({
    type: "case.closed",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'caseId', v_row.${c("id")}, 'kind', '', 'number', v_row.${c("number")})`,
    subject: `'cases/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "case",
      recordId: `v_row.${c("id")}::text`,
      summary: `'closed case ' || v_row.${c("number")}`,
    },
  })}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("close_case")}(uuid, text)`)}

create or replace function ${fn("reopen_case")}(case_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${cases}%rowtype;
begin
  select * into v_row from ${cases} x where x.${c("id")} = reopen_case.case_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, close)} then
    ${forbidden("not allowed to reopen cases")}
  end if;
  update ${cases} x set ${c("status")} = 'open', ${c("closedAt")} = null, ${c("closedBy")} = null, ${c("closeNote")} = null, ${c("updatedAt")} = now() where x.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${ctx.record({
    type: "case.reopened",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'caseId', v_row.${c("id")}, 'kind', '', 'number', v_row.${c("number")})`,
    subject: `'cases/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "case",
      recordId: `v_row.${c("id")}::text`,
      summary: `'reopened case ' || v_row.${c("number")}`,
    },
  })}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("reopen_case")}(uuid, text)`)}

create or replace function ${fn("cancel_case")}(case_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${cases}%rowtype;
begin
  select * into v_row from ${cases} x where x.${c("id")} = cancel_case.case_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, close)} then
    ${forbidden("not allowed to cancel cases")}
  end if;
  update ${cases} x set ${c("status")} = 'canceled', ${c("closeNote")} = cancel_case.reason, ${c("updatedAt")} = now() where x.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${ctx.record({
    type: "case.cancelled",
    payload: `jsonb_build_object('organizationId', v_row.${c("tenant")}, 'caseId', v_row.${c("id")}, 'kind', '', 'number', v_row.${c("number")})`,
    subject: `'cases/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "case",
      recordId: `v_row.${c("id")}::text`,
      summary: `'canceled case ' || v_row.${c("number")}`,
    },
  })}
  return ${caseJson("v_row")};
end;
$$;
${userGrant(`${fn("cancel_case")}(uuid, text)`)}

create or replace function ${fn("get_case")}(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${cases}%rowtype;
  v_actions jsonb;
begin
  select * into v_row from ${cases} x where x.${c("id")} = get_case.case_id;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`, read)} then
    ${forbidden("not allowed to read cases")}
  end if;
  select coalesce(jsonb_agg(${actionJson("x")} order by x.${a("createdAt")}), '[]'::jsonb) into v_actions from ${actions} x where x.${a("case")} = v_row.${c("id")};
  return ${caseJson("v_row")} || jsonb_build_object('actions', v_actions, 'blockers', to_jsonb(${fn("case_close_blockers")}(v_row.${c("id")})));
end;
$$;
${userGrant(`${fn("get_case")}(uuid)`)}

create or replace function ${fn("list_cases")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${caseJson("x")} order by x.${c("detectedAt")} desc), '[]'::jsonb)
  from ${cases} x
  where x.${c("tenant")} = $1
    and ${ctx.scope.check(`x.${c("tenant")}`, read)}
    and (not (filters ? 'status') or x.${c("status")} = filters ->> 'status')
    and (not (filters ? 'severity') or x.${c("severity")} = filters ->> 'severity')
    and (not (filters ? 'owner') or x.${c("owner")} = (filters ->> 'owner')::uuid)
    and (not (filters ? 'search') or x.${c("title")} ilike '%' || (filters ->> 'search') || '%' or x.${c("number")} ilike '%' || (filters ->> 'search') || '%')
  limit least(coalesce((filters ->> 'limit')::integer, 100), 200)
$$;
${userGrant(`${fn("list_cases")}(${ctx.idType}, jsonb)`)}

create or replace function ${fn("case_stats")}(tenant ${ctx.idType}, since date default null, until date default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', key, 'count', count) order by count desc), '[]'::jsonb)
  from (
    select coalesce(x.${c("severity")}, 'unspecified') as key, count(*) as count
    from ${cases} x
    where x.${c("tenant")} = $1
      and ${ctx.scope.check(`x.${c("tenant")}`, read)}
      and ($2 is null or x.${c("detectedAt")}::date >= $2)
      and ($3 is null or x.${c("detectedAt")}::date <= $3)
    group by 1
  ) s
$$;
${userGrant(`${fn("case_stats")}(${ctx.idType}, date, date)`)}

create or replace function ${fn("notify_due_case_effectiveness")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from ${cases} x where x.${c("status")} = 'open' and x.${c("effective")} is null and x.${c("effectivenessDueOn")} is not null and x.${c("effectivenessDueOn")} <= current_date
  loop
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("notify_due_case_effectiveness")}()`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Cases: nonconformities, complaints, incidents, observations, improvements and
-- change requests, with a kind, actions, a root cause and a closure guard.
${tables(ctx)}${functions(ctx)}`;
}

function contract(_ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_case_kind",
      args: ["{id}", "text", "text", "text", "boolean", "boolean", "boolean", "uuid"],
      returns: "jsonb",
    },
    { name: "archive_case_kind", args: ["uuid"], returns: "jsonb" },
    { name: "list_case_kinds", args: ["{id}", "boolean"], returns: "jsonb" },
    {
      name: "open_case",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        "text",
        "timestamptz",
        "uuid",
        "date",
      ],
      returns: "jsonb",
    },
    { name: "update_case", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "record_case_root_cause", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "create_case_action",
      args: ["uuid", "text", "text", "uuid", "timestamptz", "boolean"],
      returns: "jsonb",
    },
    { name: "complete_case_action", args: ["uuid"], returns: "jsonb" },
    { name: "remove_case_action", args: ["uuid"], returns: "jsonb" },
    {
      name: "record_case_effectiveness",
      args: ["uuid", "boolean", "text"],
      returns: "jsonb",
    },
    { name: "case_close_blockers", args: ["uuid"], returns: "text[]" },
    { name: "close_case", args: ["uuid", "text"], returns: "jsonb" },
    { name: "reopen_case", args: ["uuid", "text"], returns: "jsonb" },
    { name: "cancel_case", args: ["uuid", "text"], returns: "jsonb" },
    { name: "get_case", args: ["uuid"], returns: "jsonb" },
    { name: "list_cases", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "case_stats", args: ["{id}", "date", "date"], returns: "jsonb" },
    { name: "notify_due_case_effectiveness", args: [], returns: "integer" },
  ];
}

export const CASES: BlockSqlDefinition = {
  name: "cases",
  scopes: ["tenant"],
  title: "Cases",
  description:
    "Nonconformities, complaints, safety incidents, near misses, observations, improvements, change requests and audit findings, with a kind, actions, a root cause, an effectiveness check and a closure guard.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
