import type { InspectionsEvents } from "../../blocks/inspections/events.ts";
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

const EVENTS: BlockSqlEvents<InspectionsEvents> = {
  "inspection_program.created": {
    subject: "inspection-programs",
    payload: ["organizationId", "programId"],
  },
  "inspection_program.updated": {
    subject: "inspection-programs",
    payload: ["organizationId", "programId"],
  },
  "inspection_program.approved": {
    subject: "inspection-programs",
    payload: ["organizationId", "programId"],
  },
  "inspection_program.closed": {
    subject: "inspection-programs",
    payload: ["organizationId", "programId"],
  },
  "inspection.scheduled": {
    subject: "inspections",
    payload: ["organizationId", "inspectionId", "number"],
  },
  "inspection.updated": {
    subject: "inspections",
    payload: ["organizationId", "inspectionId", "number", "changed"],
  },
  "inspection.started": {
    subject: "inspections",
    payload: ["organizationId", "inspectionId", "number"],
  },
  "inspection.completed": {
    subject: "inspections",
    payload: ["organizationId", "inspectionId", "number"],
  },
  "inspection.closed": {
    subject: "inspections",
    payload: ["organizationId", "inspectionId", "number"],
  },
  "inspection.cancelled": {
    subject: "inspections",
    payload: ["organizationId", "inspectionId", "number"],
  },
  "inspection_finding.created": {
    subject: "inspection-findings",
    payload: ["organizationId", "inspectionId", "findingId", "type"],
  },
  "inspection_finding.updated": {
    subject: "inspection-findings",
    payload: ["organizationId", "inspectionId", "findingId"],
  },
  "inspection_finding.deleted": {
    subject: "inspection-findings",
    payload: ["organizationId", "inspectionId", "findingId"],
  },
  "inspection_finding.case_raised": {
    subject: "inspection-findings",
    payload: ["organizationId", "inspectionId", "findingId", "caseId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    inspection: {
      table: "inspections",
      singular: "inspection",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["number", "scope", "summary"] },
      },
    },
    inspection_program: { table: "programs", singular: "inspection_program" },
    inspection_finding: { table: "findings", singular: "inspection_finding" },
  },
  events: EVENTS,
  hooks: [],
  options: ["extraColumns", "kinds", "findingTypes", "caseFindingTypes"],
  tables: {
    programs: {
      name: "inspection_programs",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        periodStart: "period_start",
        periodEnd: "period_end",
        owner: "owner_id",
        status: "status",
        notes: "notes",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["owner", "notes", "archivedAt", "createdAt", "updatedAt"],
    },
    inspections: {
      name: "inspections",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        program: "program_id",
        number: "number",
        kind: "kind",
        title: "title",
        scope: "scope",
        criteria: "criteria",
        auditeeType: "auditee_type",
        auditeeId: "auditee_id",
        lead: "lead_id",
        plannedStart: "planned_start",
        plannedEnd: "planned_end",
        startedAt: "started_at",
        completedAt: "completed_at",
        closedAt: "closed_at",
        status: "status",
        summary: "summary",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "program",
        "scope",
        "criteria",
        "auditeeType",
        "auditeeId",
        "lead",
        "plannedStart",
        "plannedEnd",
        "startedAt",
        "completedAt",
        "closedAt",
        "summary",
        "createdBy",
        "createdAt",
        "updatedAt",
      ],
    },
    findings: {
      name: "inspection_findings",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        inspection: "inspection_id",
        number: "number",
        type: "type",
        title: "title",
        description: "description",
        clause: "clause",
        case: "case_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "clause", "case", "createdBy", "createdAt", "updatedAt"],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const programs = ctx.table("programs");
  const inspections = ctx.table("inspections");
  const findings = ctx.table("findings");
  const p = (column: string): string => ctx.col("programs", column);
  const i = (column: string): string => ctx.col("inspections", column);
  const f = (column: string): string => ctx.col("findings", column);
  const permissions = moduleOperations("inspections");
  const read = ctx.permission("read", permissions.read);

  const extras = ctx.extraColumns("inspections", [
    "id",
    "tenant",
    "program",
    "number",
    "kind",
    "title",
    "scope",
    "criteria",
    "auditeeType",
    "auditeeId",
    "lead",
    "plannedStart",
    "plannedEnd",
    "startedAt",
    "completedAt",
    "closedAt",
    "status",
    "summary",
    "createdBy",
    "createdAt",
    "updatedAt",
  ]);

  return `
create table if not exists ${programs} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),
  ${p("periodStart")} date not null,
  ${p("periodEnd")} date not null check (${p("periodEnd")} >= ${p("periodStart")}),
  ${p("owner")} uuid,
  ${p("status")} text not null default 'draft' check (${p("status")} in ('draft', 'approved', 'closed')),
  ${p("notes")} text,
  ${p("archivedAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now()
);
${lockTable(programs, { read: true })}
${renderPolicy(makePolicy({ table: programs, name: `${ctx.tableName("programs").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(p("tenant"), read) }))}

create table if not exists ${inspections} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("program")} uuid,
  ${i("number")} text not null,
  ${i("kind")} text not null,
  ${i("title")} text not null check (length(${i("title")}) between 1 and 200),
  ${i("scope")} text,
  ${i("criteria")} text,
  ${i("auditeeType")} text,
  ${i("auditeeId")} text,
  ${i("lead")} uuid,
  ${i("plannedStart")} date,
  ${i("plannedEnd")} date,
  ${i("startedAt")} timestamptz,
  ${i("completedAt")} timestamptz,
  ${i("closedAt")} timestamptz,
  ${i("status")} text not null default 'planned' check (${i("status")} in ('planned', 'in_progress', 'reporting', 'closed', 'cancelled')),
  ${i("summary")} text,
  ${i("createdBy")} uuid default auth.uid(),
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now(),
  unique (${i("tenant")}, ${i("number")}),
  foreign key (${i("program")}) references ${programs} (${p("id")}) on delete set null
);${addExtraColumns(inspections, extras)}
create index if not exists ${ctx.tableName("inspections").name}_status_idx on ${inspections} (${i("tenant")}, ${i("status")});
${lockTable(inspections, { read: true })}
${renderPolicy(makePolicy({ table: inspections, name: `${ctx.tableName("inspections").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(i("tenant"), read) }))}

create table if not exists ${findings} (
  ${f("id")} uuid primary key default gen_random_uuid(),
  ${f("tenant")} ${ctx.idType} not null,
  ${f("inspection")} uuid not null,
  ${f("number")} integer not null,
  ${f("type")} text not null,
  ${f("title")} text not null check (length(${f("title")}) between 1 and 200),
  ${f("description")} text,
  ${f("clause")} text,
  ${f("case")} uuid,
  ${f("createdBy")} uuid default auth.uid(),
  ${f("createdAt")} timestamptz not null default now(),
  ${f("updatedAt")} timestamptz not null default now(),
  unique (${f("inspection")}, ${f("number")}),
  foreign key (${f("inspection")}) references ${inspections} (${i("id")}) on delete cascade
);
create index if not exists ${ctx.tableName("findings").name}_parent_idx on ${findings} (${f("inspection")});
${lockTable(findings, { read: true })}
${renderPolicy(makePolicy({ table: findings, name: `${ctx.tableName("findings").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(f("tenant"), read) }))}
`;
}

function functions(ctx: BlockSqlContext): string {
  const programs = ctx.table("programs");
  const inspections = ctx.table("inspections");
  const findings = ctx.table("findings");
  const p = (column: string): string => ctx.col("programs", column);
  const i = (column: string): string => ctx.col("inspections", column);
  const f = (column: string): string => ctx.col("findings", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("inspections");
  const read = ctx.permission("read", permissions.read);
  const write = ctx.permission("write", permissions.write);
  const manage = ctx.permission("manage", permissions.manage);

  const allowed = (tenant: string, permission: string): string =>
    `(select auth.uid()) is not null and ${ctx.can("tenant", tenant, permission)}`;

  const programJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'name', ${row}.${p("name")}, 'periodStart', ${row}.${p("periodStart")}, 'periodEnd', ${row}.${p("periodEnd")}, 'ownerId', ${row}.${p("owner")}, 'status', ${row}.${p("status")}, 'notes', ${row}.${p("notes")})`;

  const inspectionJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${i("id")}, 'organizationId', ${row}.${i("tenant")}, 'programId', ${row}.${i("program")}, 'number', ${row}.${i("number")}, 'kind', ${row}.${i("kind")}, 'title', ${row}.${i("title")}, 'scope', ${row}.${i("scope")}, 'criteria', ${row}.${i("criteria")}, 'auditeeType', ${row}.${i("auditeeType")}, 'auditeeId', ${row}.${i("auditeeId")}, 'leadId', ${row}.${i("lead")}, 'plannedStart', ${row}.${i("plannedStart")}, 'plannedEnd', ${row}.${i("plannedEnd")}, 'startedAt', ${row}.${i("startedAt")}, 'completedAt', ${row}.${i("completedAt")}, 'closedAt', ${row}.${i("closedAt")}, 'status', ${row}.${i("status")}, 'summary', ${row}.${i("summary")})`;

  const findingJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${f("id")}, 'organizationId', ${row}.${f("tenant")}, 'inspectionId', ${row}.${f("inspection")}, 'number', ${row}.${f("number")}, 'type', ${row}.${f("type")}, 'title', ${row}.${f("title")}, 'description', ${row}.${f("description")}, 'clause', ${row}.${f("clause")}, 'caseId', ${row}.${f("case")})`;

  return `
create or replace function ${fn("save_inspection_program")}(tenant ${ctx.idType}, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${programs}%rowtype;
  v_created boolean := false;
begin
  if not ${allowed("save_inspection_program.tenant", manage)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to manage inspection programs")}
  end if;
  if save_inspection_program.period_end < save_inspection_program.period_start then
    ${fail("INSPECTION_INVALID", "the period ends before it starts", "22023")}
  end if;
  if save_inspection_program.program_id is null then
    insert into ${programs} (${p("tenant")}, ${p("name")}, ${p("periodStart")}, ${p("periodEnd")}, ${p("owner")}, ${p("notes")})
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id, save_inspection_program.notes)
    returning * into v_row;
    v_created := true;
  else
    update ${programs} x set ${p("name")} = trim(save_inspection_program.name), ${p("periodStart")} = save_inspection_program.period_start, ${p("periodEnd")} = save_inspection_program.period_end, ${p("owner")} = save_inspection_program.owner_id, ${p("notes")} = save_inspection_program.notes, ${p("updatedAt")} = now()
      where x.${p("id")} = save_inspection_program.program_id and x.${p("tenant")} = save_inspection_program.tenant
      returning * into v_row;
    if not found then
      ${fail("INSPECTION_PROGRAM_NOT_FOUND", "inspection program not found", "P0002")}
    end if;
  end if;
  if v_created then
    ${ctx.record({
      type: "inspection_program.created",
      payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'programId', v_row.${p("id")})`,
      subject: `'inspection-programs/' || v_row.${p("id")}::text`,
      tenant: `v_row.${p("tenant")}`,
      audit: {
        category: "data",
        targetType: "inspection_program",
        recordId: `v_row.${p("id")}::text`,
        summary: "'saved inspection program'",
      },
    })}
  else
    ${ctx.record({
      type: "inspection_program.updated",
      payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'programId', v_row.${p("id")})`,
      subject: `'inspection-programs/' || v_row.${p("id")}::text`,
      tenant: `v_row.${p("tenant")}`,
      audit: {
        category: "data",
        targetType: "inspection_program",
        recordId: `v_row.${p("id")}::text`,
        summary: "'saved inspection program'",
      },
    })}
  end if;
  return ${programJson("v_row")};
end;
$$;
${userGrant(`${fn("save_inspection_program")}(${ctx.idType}, text, date, date, uuid, text, uuid)`)}

create or replace function ${fn("approve_inspection_program")}(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${programs}%rowtype;
begin
  select * into v_row from ${programs} x where x.${p("id")} = approve_inspection_program.program_id;
  if not found then
    ${fail("INSPECTION_PROGRAM_NOT_FOUND", "inspection program not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${p("tenant")}`, manage)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to manage inspection programs")}
  end if;
  update ${programs} x set ${p("status")} = 'approved', ${p("updatedAt")} = now() where x.${p("id")} = v_row.${p("id")} returning * into v_row;
  ${ctx.record({
    type: "inspection_program.approved",
    payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'programId', v_row.${p("id")})`,
    subject: `'inspection-programs/' || v_row.${p("id")}::text`,
    tenant: `v_row.${p("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection_program",
      recordId: `v_row.${p("id")}::text`,
      summary: "'approved inspection program'",
    },
  })}
  return ${programJson("v_row")};
end;
$$;
${userGrant(`${fn("approve_inspection_program")}(uuid)`)}

create or replace function ${fn("close_inspection_program")}(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${programs}%rowtype;
begin
  select * into v_row from ${programs} x where x.${p("id")} = close_inspection_program.program_id;
  if not found then
    ${fail("INSPECTION_PROGRAM_NOT_FOUND", "inspection program not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${p("tenant")}`, manage)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to manage inspection programs")}
  end if;
  update ${programs} x set ${p("status")} = 'closed', ${p("updatedAt")} = now() where x.${p("id")} = v_row.${p("id")} returning * into v_row;
  ${ctx.record({
    type: "inspection_program.closed",
    payload: `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'programId', v_row.${p("id")})`,
    subject: `'inspection-programs/' || v_row.${p("id")}::text`,
    tenant: `v_row.${p("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection_program",
      recordId: `v_row.${p("id")}::text`,
      summary: "'closed inspection program'",
    },
  })}
  return ${programJson("v_row")};
end;
$$;
${userGrant(`${fn("close_inspection_program")}(uuid)`)}

create or replace function ${fn("list_inspection_programs")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${programJson("x")} order by x.${p("periodStart")} desc), '[]'::jsonb)
  from ${programs} x
  where x.${p("tenant")} = $1 and ${ctx.scope.check(`x.${p("tenant")}`, read)}
$$;
${userGrant(`${fn("list_inspection_programs")}(${ctx.idType})`)}

create or replace function ${fn("schedule_inspection")}(tenant ${ctx.idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
begin
  if not ${allowed("schedule_inspection.tenant", manage)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to schedule inspections")}
  end if;
  insert into ${inspections} (${i("tenant")}, ${i("program")}, ${i("number")}, ${i("kind")}, ${i("title")}, ${i("scope")}, ${i("criteria")}, ${i("auditeeType")}, ${i("auditeeId")}, ${i("lead")}, ${i("plannedStart")}, ${i("plannedEnd")})
  values (schedule_inspection.tenant, (input ->> 'programId')::uuid, 'AUD-' || to_char(current_date, 'YYYY') || '-' || lpad(((select count(*) + 1 from ${inspections} x where x.${i("tenant")} = schedule_inspection.tenant))::text, 3, '0'), coalesce(input ->> 'kind', 'internal_audit'), trim(input ->> 'title'), input ->> 'scope', input ->> 'criteria', input #>> '{auditee,type}', input #>> '{auditee,id}', (input ->> 'leadId')::uuid, (input ->> 'plannedStart')::date, (input ->> 'plannedEnd')::date)
  returning * into v_row;
  ${ctx.record({
    type: "inspection.scheduled",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'inspectionId', v_row.${i("id")}, 'number', v_row.${i("number")})`,
    subject: `'inspections/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection",
      recordId: `v_row.${i("id")}::text`,
      summary: `'scheduled inspection ' || v_row.${i("number")}`,
    },
  })}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("schedule_inspection")}(${ctx.idType}, jsonb)`)}

create or replace function ${fn("update_inspection")}(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
  v_changed text[] := '{}';
begin
  select * into v_row from ${inspections} x where x.${i("id")} = update_inspection.inspection_id for update;
  if not found then
    ${fail("INSPECTION_NOT_FOUND", "inspection not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, manage)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to change inspections")}
  end if;
  if v_row.${i("status")} in ('closed', 'cancelled') then
    ${fail("INSPECTION_STATUS_INVALID", "a closed inspection can't change", "55000")}
  end if;
  if changes ? 'title' then v_row.${i("title")} := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'scope' then v_row.${i("scope")} := changes ->> 'scope'; v_changed := array_append(v_changed, 'scope'); end if;
  if changes ? 'criteria' then v_row.${i("criteria")} := changes ->> 'criteria'; v_changed := array_append(v_changed, 'criteria'); end if;
  if changes ? 'leadId' then v_row.${i("lead")} := (changes ->> 'leadId')::uuid; v_changed := array_append(v_changed, 'leadId'); end if;
  if changes ? 'plannedStart' then v_row.${i("plannedStart")} := (changes ->> 'plannedStart')::date; v_changed := array_append(v_changed, 'plannedStart'); end if;
  if changes ? 'plannedEnd' then v_row.${i("plannedEnd")} := (changes ->> 'plannedEnd')::date; v_changed := array_append(v_changed, 'plannedEnd'); end if;
  update ${inspections} x set ${i("title")} = v_row.${i("title")}, ${i("scope")} = v_row.${i("scope")}, ${i("criteria")} = v_row.${i("criteria")}, ${i("lead")} = v_row.${i("lead")}, ${i("plannedStart")} = v_row.${i("plannedStart")}, ${i("plannedEnd")} = v_row.${i("plannedEnd")}, ${i("updatedAt")} = now()
    where x.${i("id")} = v_row.${i("id")} returning * into v_row;
  ${ctx.record({
    type: "inspection.updated",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'inspectionId', v_row.${i("id")}, 'number', v_row.${i("number")}, 'changed', to_jsonb(v_changed))`,
    subject: `'inspections/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection",
      recordId: `v_row.${i("id")}::text`,
      summary: `'changed inspection ' || v_row.${i("number")}`,
    },
  })}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("update_inspection")}(uuid, jsonb)`)}

create or replace function ${fn("start_inspection")}(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
begin
  select * into v_row from ${inspections} x where x.${i("id")} = start_inspection.inspection_id for update;
  if not found then
    ${fail("INSPECTION_NOT_FOUND", "inspection not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, write)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to run inspections")}
  end if;
  if v_row.${i("status")} <> 'planned' then
    ${fail("INSPECTION_STATUS_INVALID", "only a planned inspection can start", "55000")}
  end if;
  update ${inspections} x set ${i("status")} = 'in_progress', ${i("startedAt")} = now(), ${i("updatedAt")} = now() where x.${i("id")} = v_row.${i("id")} returning * into v_row;
  ${ctx.record({
    type: "inspection.started",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'inspectionId', v_row.${i("id")}, 'number', v_row.${i("number")})`,
    subject: `'inspections/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection",
      recordId: `v_row.${i("id")}::text`,
      summary: `'started inspection ' || v_row.${i("number")}`,
    },
  })}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("start_inspection")}(uuid)`)}

create or replace function ${fn("add_inspection_finding")}(inspection_id uuid, type text, title text, description text default null, clause text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inspection ${inspections}%rowtype;
  v_row ${findings}%rowtype;
begin
  select * into v_inspection from ${inspections} x where x.${i("id")} = add_inspection_finding.inspection_id;
  if not found then
    ${fail("INSPECTION_NOT_FOUND", "inspection not found", "P0002")}
  end if;
  if not ${allowed(`v_inspection.${i("tenant")}`, write)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to add findings")}
  end if;
  if v_inspection.${i("status")} not in ('in_progress', 'reporting') then
    ${fail("INSPECTION_STATUS_INVALID", "findings need a running inspection", "55000")}
  end if;
  insert into ${findings} (${f("tenant")}, ${f("inspection")}, ${f("number")}, ${f("type")}, ${f("title")}, ${f("description")}, ${f("clause")})
  values (v_inspection.${i("tenant")}, v_inspection.${i("id")}, (select coalesce(max(x.${f("number")}), 0) + 1 from ${findings} x where x.${f("inspection")} = v_inspection.${i("id")}), add_inspection_finding.type, trim(add_inspection_finding.title), add_inspection_finding.description, add_inspection_finding.clause)
  returning * into v_row;
  ${ctx.record({
    type: "inspection_finding.created",
    payload: `jsonb_build_object('organizationId', v_row.${f("tenant")}, 'inspectionId', v_row.${f("inspection")}, 'findingId', v_row.${f("id")}, 'type', v_row.${f("type")})`,
    subject: `'inspection-findings/' || v_row.${f("id")}::text`,
    tenant: `v_row.${f("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection_finding",
      recordId: `v_row.${f("id")}::text`,
      summary: "'added inspection finding'",
    },
  })}
  return ${findingJson("v_row")};
end;
$$;
${userGrant(`${fn("add_inspection_finding")}(uuid, text, text, text, text)`)}

create or replace function ${fn("update_inspection_finding")}(finding_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${findings}%rowtype;
begin
  select * into v_row from ${findings} x where x.${f("id")} = update_inspection_finding.finding_id for update;
  if not found then
    ${fail("INSPECTION_FINDING_NOT_FOUND", "finding not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${f("tenant")}`, write)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to change findings")}
  end if;
  if changes ? 'type' then v_row.${f("type")} := changes ->> 'type'; end if;
  if changes ? 'title' then v_row.${f("title")} := changes ->> 'title'; end if;
  if changes ? 'description' then v_row.${f("description")} := changes ->> 'description'; end if;
  if changes ? 'clause' then v_row.${f("clause")} := changes ->> 'clause'; end if;
  update ${findings} x set ${f("type")} = v_row.${f("type")}, ${f("title")} = v_row.${f("title")}, ${f("description")} = v_row.${f("description")}, ${f("clause")} = v_row.${f("clause")}, ${f("updatedAt")} = now()
    where x.${f("id")} = v_row.${f("id")} returning * into v_row;
  ${ctx.record({
    type: "inspection_finding.updated",
    payload: `jsonb_build_object('organizationId', v_row.${f("tenant")}, 'inspectionId', v_row.${f("inspection")}, 'findingId', v_row.${f("id")})`,
    subject: `'inspection-findings/' || v_row.${f("id")}::text`,
    tenant: `v_row.${f("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection_finding",
      recordId: `v_row.${f("id")}::text`,
      summary: "'changed inspection finding'",
    },
  })}
  return ${findingJson("v_row")};
end;
$$;
${userGrant(`${fn("update_inspection_finding")}(uuid, jsonb)`)}

create or replace function ${fn("delete_inspection_finding")}(finding_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${findings}%rowtype;
begin
  select * into v_row from ${findings} x where x.${f("id")} = delete_inspection_finding.finding_id;
  if not found then
    ${fail("INSPECTION_FINDING_NOT_FOUND", "finding not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${f("tenant")}`, write)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to delete findings")}
  end if;
  if v_row.${f("case")} is not null then
    ${fail("INSPECTION_FINDING_HAS_CASE", "a finding with a case can't be deleted", "55000")}
  end if;
  delete from ${findings} x where x.${f("id")} = v_row.${f("id")};
  ${ctx.record({
    type: "inspection_finding.deleted",
    payload: `jsonb_build_object('organizationId', v_row.${f("tenant")}, 'inspectionId', v_row.${f("inspection")}, 'findingId', v_row.${f("id")})`,
    subject: `'inspection-findings/' || v_row.${f("id")}::text`,
    tenant: `v_row.${f("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection_finding",
      recordId: `v_row.${f("id")}::text`,
      summary: "'deleted inspection finding'",
    },
  })}
  return true;
end;
$$;
${userGrant(`${fn("delete_inspection_finding")}(uuid)`)}

create or replace function ${fn("raise_inspection_finding_case")}(finding_id uuid, kind text default 'finding')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_finding ${findings}%rowtype;
  v_case jsonb;
begin
  select * into v_finding from ${findings} x where x.${f("id")} = raise_inspection_finding_case.finding_id;
  if not found then
    ${fail("INSPECTION_FINDING_NOT_FOUND", "finding not found", "P0002")}
  end if;
  if not ${allowed(`v_finding.${f("tenant")}`, write)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to raise findings")}
  end if;
  if v_finding.${f("case")} is not null then
    ${fail("INSPECTION_FINDING_HAS_CASE", "the finding already has a case", "55000")}
  end if;
  ${
    ctx.installed("cases")
      ? `v_case := ${ctx.of("cases").fn("open_case")}(v_finding.${f("tenant")}, raise_inspection_finding_case.kind, v_finding.${f("title")}, v_finding.${f("description")}, null, 'inspection');`
      : fail("INSPECTION_CASES_NOT_INSTALLED", "install the cases block", "55000")
  }
  update ${findings} x set ${f("case")} = (v_case ->> 'id')::uuid, ${f("updatedAt")} = now() where x.${f("id")} = v_finding.${f("id")} returning * into v_finding;
  ${ctx.record({
    type: "inspection_finding.case_raised",
    payload: `jsonb_build_object('organizationId', v_finding.${f("tenant")}, 'inspectionId', v_finding.${f("inspection")}, 'findingId', v_finding.${f("id")}, 'caseId', v_finding.${f("case")})`,
    subject: `'inspection-findings/' || v_finding.${f("id")}::text`,
    tenant: `v_finding.${f("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection_finding",
      recordId: `v_finding.${f("id")}::text`,
      summary: "'raised a case from a finding'",
    },
  })}
  return v_case;
end;
$$;
${userGrant(`${fn("raise_inspection_finding_case")}(uuid, text)`)};

create or replace function ${fn("complete_inspection")}(inspection_id uuid, summary text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
begin
  select * into v_row from ${inspections} x where x.${i("id")} = complete_inspection.inspection_id for update;
  if not found then
    ${fail("INSPECTION_NOT_FOUND", "inspection not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, write)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to complete inspections")}
  end if;
  if v_row.${i("status")} <> 'in_progress' then
    ${fail("INSPECTION_STATUS_INVALID", "only a running inspection can complete", "55000")}
  end if;
  update ${inspections} x set ${i("status")} = 'reporting', ${i("completedAt")} = now(), ${i("summary")} = complete_inspection.summary, ${i("updatedAt")} = now() where x.${i("id")} = v_row.${i("id")} returning * into v_row;
  ${ctx.record({
    type: "inspection.completed",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'inspectionId', v_row.${i("id")}, 'number', v_row.${i("number")})`,
    subject: `'inspections/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection",
      recordId: `v_row.${i("id")}::text`,
      summary: `'completed inspection ' || v_row.${i("number")}`,
    },
  })}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("complete_inspection")}(uuid, text)`)}

create or replace function ${fn("close_inspection")}(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
  v_open uuid[];
begin
  select * into v_row from ${inspections} x where x.${i("id")} = close_inspection.inspection_id for update;
  if not found then
    ${fail("INSPECTION_NOT_FOUND", "inspection not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, manage)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to close inspections")}
  end if;
  if v_row.${i("status")} <> 'reporting' then
    ${fail("INSPECTION_STATUS_INVALID", "only a reporting inspection can close", "55000")}
  end if;
  select array_agg(x.${f("id")}) into v_open from ${findings} x where x.${f("inspection")} = v_row.${i("id")} and x.${f("type")} in ('major_nonconformity', 'minor_nonconformity') and x.${f("case")} is null;
  if v_open is not null then
    ${fail("INSPECTION_FINDINGS_OPEN", "nonconformities need a case before closing", "22023")}
  end if;
  update ${inspections} x set ${i("status")} = 'closed', ${i("closedAt")} = now(), ${i("updatedAt")} = now() where x.${i("id")} = v_row.${i("id")} returning * into v_row;
  ${ctx.record({
    type: "inspection.closed",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'inspectionId', v_row.${i("id")}, 'number', v_row.${i("number")})`,
    subject: `'inspections/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection",
      recordId: `v_row.${i("id")}::text`,
      summary: `'closed inspection ' || v_row.${i("number")}`,
    },
  })}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("close_inspection")}(uuid)`)}

create or replace function ${fn("cancel_inspection")}(inspection_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
begin
  select * into v_row from ${inspections} x where x.${i("id")} = cancel_inspection.inspection_id for update;
  if not found then
    ${fail("INSPECTION_NOT_FOUND", "inspection not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, manage)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to cancel inspections")}
  end if;
  update ${inspections} x set ${i("status")} = 'cancelled', ${i("summary")} = cancel_inspection.reason, ${i("updatedAt")} = now() where x.${i("id")} = v_row.${i("id")} returning * into v_row;
  ${ctx.record({
    type: "inspection.cancelled",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'inspectionId', v_row.${i("id")}, 'number', v_row.${i("number")})`,
    subject: `'inspections/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}`,
    audit: {
      category: "data",
      targetType: "inspection",
      recordId: `v_row.${i("id")}::text`,
      summary: `'cancelled inspection ' || v_row.${i("number")}`,
    },
  })}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("cancel_inspection")}(uuid, text)`)}

create or replace function ${fn("get_inspection")}(inspection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
  v_findings jsonb;
begin
  select * into v_row from ${inspections} x where x.${i("id")} = get_inspection.inspection_id;
  if not found then
    ${fail("INSPECTION_NOT_FOUND", "inspection not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${i("tenant")}`, read)} then
    ${fail("INSPECTION_FORBIDDEN", "not allowed to read inspections")}
  end if;
  select coalesce(jsonb_agg(${findingJson("x")} order by x.${f("number")}), '[]'::jsonb) into v_findings from ${findings} x where x.${f("inspection")} = v_row.${i("id")};
  return ${inspectionJson("v_row")} || jsonb_build_object('findings', v_findings);
end;
$$;
${userGrant(`${fn("get_inspection")}(uuid)`)}

create or replace function ${fn("list_inspections")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${inspectionJson("x")} order by x.${i("plannedStart")} desc nulls last), '[]'::jsonb)
  from ${inspections} x
  where x.${i("tenant")} = $1
    and ${ctx.scope.check(`x.${i("tenant")}`, read)}
    and (not (filters ? 'programId') or x.${i("program")} = (filters ->> 'programId')::uuid)
    and (not (filters ? 'kind') or x.${i("kind")} = filters ->> 'kind')
    and (not (filters ? 'status') or x.${i("status")} = filters ->> 'status')
    and (not (filters ? 'leadId') or x.${i("lead")} = (filters ->> 'leadId')::uuid)
$$;
${userGrant(`${fn("list_inspections")}(${ctx.idType}, jsonb)`)}

create or replace function ${fn("notify_due_inspections")}()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from ${inspections} x where x.${i("status")} = 'planned' and x.${i("plannedStart")} is not null and x.${i("plannedStart")} <= current_date
$$;
${userGrant(`${fn("notify_due_inspections")}()`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Inspections: programs, scheduled audits and inspections, findings and a
-- close guard that needs a case for each nonconformity.
${tables(ctx)}${functions(ctx)}`;
}

function contract(_ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_inspection_program",
      args: ["{id}", "text", "date", "date", "uuid", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "approve_inspection_program", args: ["uuid"], returns: "jsonb" },
    { name: "close_inspection_program", args: ["uuid"], returns: "jsonb" },
    { name: "list_inspection_programs", args: ["{id}"], returns: "jsonb" },
    { name: "schedule_inspection", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "update_inspection", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "start_inspection", args: ["uuid"], returns: "jsonb" },
    {
      name: "add_inspection_finding",
      args: ["uuid", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "update_inspection_finding",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_inspection_finding", args: ["uuid"], returns: "boolean" },
    {
      name: "raise_inspection_finding_case",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    { name: "complete_inspection", args: ["uuid", "text"], returns: "jsonb" },
    { name: "close_inspection", args: ["uuid"], returns: "jsonb" },
    { name: "cancel_inspection", args: ["uuid", "text"], returns: "jsonb" },
    { name: "get_inspection", args: ["uuid"], returns: "jsonb" },
    { name: "list_inspections", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "notify_due_inspections", args: [], returns: "integer" },
  ];
}

export const INSPECTIONS: BlockSqlDefinition = {
  name: "inspections",
  scopes: ["tenant"],
  title: "Inspections",
  description:
    "Audit and inspection programs, scheduled audits and inspections, findings, a case raised from a finding and a close guard.",
  requires: ["memberships", "permissions"],
  integrates: ["cases", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
