import type { BlockSqlContext } from "../context.ts";
import type { InspectionsSql } from "./inspections-sql.ts";

import { assignNumberSql } from "../numbering-sql.ts";
import { fail, serviceGrant, userGrant, writeExtraColumns } from "../shared.ts";
import { inspectionsSql } from "./inspections-sql.ts";
import { INSPECTION_MEMBER_ROLES } from "./inspections-values.ts";

const UUID =
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";

function programFunctions(ctx: BlockSqlContext, q: InspectionsSql): string {
  const { fn, p, programs, programJson, has } = q;
  const idType = ctx.idType;

  const notes = has("programs", "notes")
    ? `
  if length(save_inspection_program.notes) > 10000 then
    ${q.invalid("notes is at most 10000 characters")}
  end if;`
    : `
  if nullif(trim(save_inspection_program.notes), '') is not null then
    ${q.invalid("the programmes table has no notes column")}
  end if;`;

  const notesCol = has("programs", "notes") ? `, ${p("notes")}` : "";

  const notesValue = has("programs", "notes")
    ? ", nullif(trim(save_inspection_program.notes), '')"
    : "";

  const notesSet = has("programs", "notes")
    ? `\n      ${p("notes")} = nullif(trim(save_inspection_program.notes), ''),`
    : "";

  /** Loads `v_row` by `func.program_id` for update, for a manager. */
  const load = (
    func: string,
  ): string => `select * into v_row from ${programs} x where x.${p("id")} = ${func}.program_id for update;
  if not found then
    ${q.programMissing}
  end if;
  if not ${q.allowed(`v_row.${p("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage audit programmes")}
  end if;`;

  return `
-- Creates an audit programme for a period or, with program_id, changes one.
-- A new programme starts as a draft; a closed one takes no changes.
create or replace function ${fn("save_inspection_program")}(tenant ${idType}, name text, period_start date, period_end date, owner_id uuid default null, notes text default null, program_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${programs};
begin
  if not ${q.allowed("save_inspection_program.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage audit programmes")}
  end if;
  if coalesce(length(trim(save_inspection_program.name)), 0) not between 1 and 200 then
    ${q.invalid("a programme needs a name of 1 to 200 characters")}
  end if;
  if save_inspection_program.period_start is null or save_inspection_program.period_end is null
    or save_inspection_program.period_end < save_inspection_program.period_start then
    ${q.invalid("a programme needs a period that ends on or after its start")}
  end if;${notes}
  if save_inspection_program.program_id is null then
    insert into ${programs} (${p("tenant")}, ${p("name")}, ${p("periodStart")}, ${p("periodEnd")}, ${p("owner")}${notesCol})
    values (save_inspection_program.tenant, trim(save_inspection_program.name), save_inspection_program.period_start, save_inspection_program.period_end, save_inspection_program.owner_id${notesValue})
    returning * into v_row;
    ${q.recordProgram("inspection_program.created", "v_row", "audit programme created")}
  else
    select * into v_row from ${programs} x
    where x.${p("id")} = save_inspection_program.program_id and x.${p("tenant")} = save_inspection_program.tenant
    for update;
    if not found then
      ${q.programMissing}
    end if;
    if v_row.${p("status")} = 'closed' then
      ${q.invalid("the programme is closed")}
    end if;
    update ${programs} x set
      ${p("name")} = trim(save_inspection_program.name),
      ${p("periodStart")} = save_inspection_program.period_start,
      ${p("periodEnd")} = save_inspection_program.period_end,
      ${p("owner")} = save_inspection_program.owner_id,${notesSet}
      ${p("updatedAt")} = now()
    where x.${p("id")} = v_row.${p("id")}
    returning * into v_row;
    ${q.recordProgram("inspection_program.updated", "v_row", "audit programme updated")}
  end if;
  return ${programJson("v_row")};
end;
$$;
${userGrant(`${fn("save_inspection_program")}(${idType}, text, date, date, uuid, text, uuid)`)}

-- Approves a draft programme.
create or replace function ${fn("approve_inspection_program")}(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${programs};
begin
  ${load("approve_inspection_program")}
  if v_row.${p("status")} <> 'draft' then
    ${q.invalid("only a draft programme can be approved")}
  end if;
  update ${programs} x set ${p("status")} = 'approved', ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  ${q.recordProgram("inspection_program.approved", "v_row", "audit programme approved")}
  return ${programJson("v_row")};
end;
$$;
${userGrant(`${fn("approve_inspection_program")}(uuid)`)}

-- Closes a programme. Its inspections stay; no new ones join it.
create or replace function ${fn("close_inspection_program")}(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${programs};
begin
  ${load("close_inspection_program")}
  if v_row.${p("status")} = 'closed' then
    ${q.invalid("the programme is already closed")}
  end if;
  update ${programs} x set ${p("status")} = 'closed', ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  ${q.recordProgram("inspection_program.closed", "v_row", "audit programme closed")}
  return ${programJson("v_row")};
end;
$$;
${userGrant(`${fn("close_inspection_program")}(uuid)`)}

-- The organization's programmes, the latest period first.
create or replace function ${fn("list_inspection_programs")}(tenant ${idType})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${q.allowed("list_inspection_programs.tenant", q.read)} then
    ${q.forbidden("not allowed to read inspections")}
  end if;
  return coalesce((
    select jsonb_agg(${programJson("x")} order by x.${p("periodStart")} desc, x.${p("name")})
    from ${programs} x
    where x.${p("tenant")} = list_inspection_programs.tenant and x.${p("archivedAt")} is null
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_inspection_programs")}(${idType})`)}
`;
}

/** The team writer: replaces an inspection's members and returns its lead. */
function teamFunction(ctx: BlockSqlContext, q: InspectionsSql): string {
  const { fn, m, members } = q;
  const idType = ctx.idType;
  const ms = ctx.of("memberships");
  const roles = INSPECTION_MEMBER_ROLES.map((role) => `'${role}'`).join(", ");

  return `
-- Replaces the members of an inspection with team, [{ userId, role }]. Every
-- member belongs to the organization and one at most leads. Returns the lead.
-- The other functions call it; it is not an entry point.
create or replace function ${fn("inspection_set_team")}(inspection_id uuid, tenant ${idType}, team jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(inspection_set_team.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    ${q.invalid("members must be a list")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '${UUID}'
      or coalesce(e ->> 'role', '') not in (${roles})
  ) then
    ${q.invalid("each member needs a userId and a role of lead, auditor, observer or auditee")}
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    ${q.invalid("a user is listed twice")}
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead') > 1 then
    ${q.invalid("an inspection has one lead")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from ${ms.table("memberships")} y
      where y.${ms.col("memberships", "tenant")} = inspection_set_team.tenant
        and y.${ms.col("memberships", "user")} = (e ->> 'userId')::uuid
    )
  ) then
    ${q.invalid("every member must belong to the organization")}
  end if;
  delete from ${members} x where x.${m("inspection")} = inspection_set_team.inspection_id;
  insert into ${members} (${m("inspection")}, ${m("tenant")}, ${m("user")}, ${m("role")})
  select inspection_set_team.inspection_id, inspection_set_team.tenant, (e ->> 'userId')::uuid, e ->> 'role'
  from jsonb_array_elements(v_team) e;
  return (select (e ->> 'userId')::uuid from jsonb_array_elements(v_team) e where e ->> 'role' = 'lead');
end;
$$;
${serviceGrant(`${fn("inspection_set_team")}(uuid, ${idType}, jsonb)`)}

-- team with lead_id as its lead: another lead becomes an auditor.
create or replace function ${fn("inspection_team_with_lead")}(team jsonb, lead_id uuid)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when inspection_team_with_lead.lead_id is null then coalesce(inspection_team_with_lead.team, '[]'::jsonb)
  else coalesce((
    select jsonb_agg(case when e ->> 'role' = 'lead' then e || '{"role": "auditor"}'::jsonb else e end)
    from jsonb_array_elements(coalesce(inspection_team_with_lead.team, '[]'::jsonb)) e
    where jsonb_typeof(e) <> 'object' or e ->> 'userId' is distinct from inspection_team_with_lead.lead_id::text
  ), '[]'::jsonb) || jsonb_build_array(jsonb_build_object('userId', inspection_team_with_lead.lead_id, 'role', 'lead')) end;
$$;
${serviceGrant(`${fn("inspection_team_with_lead")}(jsonb, uuid)`)}
`;
}

/** The checks schedule and update run on the resolved `v_*` values. */
function inspectionChecks(q: InspectionsSql, src: string): string {
  const { p, programs, has } = q;
  const forms = q.forms;

  const optionalText = (column: string, max: number): string =>
    has("inspections", column)
      ? `
  if length(${src} ->> '${column}') > ${String(max)} then
    ${q.invalid(`${column} is at most ${String(max)} characters`)}
  end if;`
      : `
  if nullif(trim(${src} ->> '${column}'), '') is not null then
    ${q.invalid(`the inspections table has no ${column} column`)}
  end if;`;

  return `if v_kind is null or not (v_kind = any (${q.kinds})) then
    ${fail("INSPECTION_KIND_UNKNOWN", "the kind is not one of options.kinds", "22023")}
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    ${q.invalid("an inspection needs a title of 1 to 300 characters")}
  end if;
  if v_end < v_start then
    ${q.invalid("plannedEnd is on or after plannedStart")}
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    ${q.invalid("auditee needs a type and an id")}
  end if;${optionalText("scope", 10_000)}${optionalText("criteria", 10_000)}
  if ${src} ? 'fields' and jsonb_typeof(${src} -> 'fields') not in ('object', 'null') then
    ${q.invalid("fields must be an object")}
  end if;
  if v_program is not null and not exists (
    select 1 from ${programs} y where y.${p("id")} = v_program and y.${p("tenant")} = v_tenant and y.${p("status")} <> 'closed'
  ) then
    ${q.programMissing}
  end if;
  if v_form is not null and not exists (
    select 1 from ${forms.table("forms")} y where y.${forms.col("forms", "id")} = v_form and y.${forms.col("forms", "tenant")}::text = v_tenant::text
  ) then
    ${q.invalid("the checklist form is not a form of this organization")}
  end if;`;
}

/** Loads `v_row` by `func.inspection_id` for update. */
function load(q: InspectionsSql, func: string): string {
  const { i, inspections } = q;

  return `select * into v_row from ${inspections} x where x.${i("id")} = ${func}.inspection_id for update;
  if not found then
    ${q.missing}
  end if;`;
}

function scheduleFunctions(ctx: BlockSqlContext, q: InspectionsSql): string {
  const { fn, i, m, inspections, members, extras, inspectionJson, has } = q;
  const idType = ctx.idType;

  const opt = (["scope", "criteria"] as const).filter((column) =>
    has("inspections", column),
  );

  const numberAssign = assignNumberSql(
    ctx,
    ctx.resolved.entityNaming.rename("inspection"),
    "schedule_inspection.tenant",
    { seq: "v_seq", identifier: "v_number" },
    {
      table: inspections,
      seq: i("sequence"),
      tenant: i("tenant"),
      prefix: "AUD-",
    },
  );

  const resolved = (src: string, row?: string): string => {
    const pick = (key: string, cast: string, column: string): string =>
      row === undefined
        ? `nullif(${src} ->> '${key}', '')${cast}`
        : `case when ${src} ? '${key}' then nullif(${src} ->> '${key}', '')${cast} else ${row}.${i(column)} end`;

    return `v_kind := ${row === undefined ? `${src} ->> 'kind'` : `coalesce(${src} ->> 'kind', ${row}.${i("kind")})`};
  v_title := ${row === undefined ? `trim(${src} ->> 'title')` : `case when ${src} ? 'title' then trim(${src} ->> 'title') else ${row}.${i("title")} end`};
  v_program := ${pick("programId", "::uuid", "program")};
  v_start := ${pick("plannedStart", "::date", "plannedStart")};
  v_end := ${pick("plannedEnd", "::date", "plannedEnd")};
  v_form := ${pick("checklistFormId", "::uuid", "checklistForm")};
  v_auditee_type := ${row === undefined ? `nullif(${src} -> 'auditee' ->> 'type', '')` : `case when ${src} ? 'auditee' then nullif(${src} -> 'auditee' ->> 'type', '') else ${row}.${i("auditeeType")} end`};
  v_auditee_id := ${row === undefined ? `nullif(${src} -> 'auditee' ->> 'id', '')` : `case when ${src} ? 'auditee' then nullif(${src} -> 'auditee' ->> 'id', '') else ${row}.${i("auditeeId")} end`};`;
  };

  const vars = `  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;`;

  return `
-- Schedules an inspection: input is { programId, kind, title, scope,
-- criteria, auditee: { type, id }, leadId, plannedStart, plannedEnd,
-- checklistFormId, members: [{ userId, role }], fields }. It starts planned.
create or replace function ${fn("schedule_inspection")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
  v_tenant ${idType} := schedule_inspection.tenant;
${vars}
  v_seq bigint;
  v_number text;
begin
  if not ${q.allowed("schedule_inspection.tenant", q.manage)} then
    ${q.forbidden("not allowed to schedule inspections")}
  end if;
  if jsonb_typeof(schedule_inspection.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  ${resolved("schedule_inspection.input")}
  ${inspectionChecks(q, "schedule_inspection.input")}
  ${ctx.hook("before_inspection_schedule", [
    [idType, "schedule_inspection.tenant"],
    ["jsonb", "schedule_inspection.input"],
  ])}
  ${numberAssign}
  insert into ${inspections} (${i("tenant")}, ${i("program")}, ${i("number")}, ${i("sequence")}, ${i("kind")}, ${i("title")}${opt.map((column) => `, ${i(column)}`).join("")}, ${i("auditeeType")}, ${i("auditeeId")}, ${i("plannedStart")}, ${i("plannedEnd")}, ${i("checklistForm")}${has("inspections", "createdBy") ? `, ${i("createdBy")}` : ""})
  values (schedule_inspection.tenant, v_program, v_number, v_seq, v_kind, v_title${opt.map((column) => `, nullif(trim(schedule_inspection.input ->> '${column}'), '')`).join("")}, v_auditee_type, v_auditee_id, v_start, v_end, v_form${has("inspections", "createdBy") ? ", auth.uid()" : ""})
  returning * into v_row;${writeExtraColumns(inspections, extras, "coalesce(schedule_inspection.input -> 'fields', '{}'::jsonb)", `x.${i("id")} = v_row.${i("id")}`, "v_row")}
  v_lead := ${fn("inspection_set_team")}(v_row.${i("id")}, v_row.${i("tenant")},
    ${fn("inspection_team_with_lead")}(schedule_inspection.input -> 'members', nullif(schedule_inspection.input ->> 'leadId', '')::uuid));
  update ${inspections} x set ${i("lead")} = v_lead where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${q.record("inspection.scheduled", "v_row", "inspection scheduled")}
  ${ctx.hook("after_inspection_schedule", [["uuid", `v_row.${i("id")}`]])}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("schedule_inspection")}(${idType}, jsonb)`)}

-- Changes an open inspection: the keys of schedule_inspection except members.
-- The checklist form changes only while it is planned. Needs
-- inspections.manage, or inspections.write as its lead.
create or replace function ${fn("update_inspection")}(inspection_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
  v_tenant ${idType};
${vars}
begin
  ${load(q, "update_inspection")}
  v_tenant := v_row.${i("tenant")};
  if not ${q.acts("v_tenant", `v_row.${i("id")}`, ["lead"])} then
    ${q.forbidden("not allowed to change this inspection")}
  end if;
  if v_row.${i("status")} in ('closed', 'canceled') then
    ${q.invalid("a closed or canceled inspection takes no changes")}
  end if;
  if jsonb_typeof(update_inspection.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;
  ${resolved("update_inspection.changes", "v_row")}
  if v_form is distinct from v_row.${i("checklistForm")} and v_row.${i("status")} <> 'planned' then
    ${q.invalid("the checklist form changes only before the inspection starts")}
  end if;
  ${inspectionChecks(q, "update_inspection.changes")}
  update ${inspections} x set
    ${i("program")} = v_program,
    ${i("kind")} = v_kind,
    ${i("title")} = v_title,${opt.map((column) => `\n    ${i(column)} = case when update_inspection.changes ? '${column}' then nullif(trim(update_inspection.changes ->> '${column}'), '') else x.${i(column)} end,`).join("")}
    ${i("auditeeType")} = v_auditee_type,
    ${i("auditeeId")} = v_auditee_id,
    ${i("plannedStart")} = v_start,
    ${i("plannedEnd")} = v_end,
    ${i("checklistForm")} = v_form,
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;${writeExtraColumns(inspections, extras, "coalesce(update_inspection.changes -> 'fields', '{}'::jsonb)", `x.${i("id")} = v_row.${i("id")}`, "v_row")}
  if update_inspection.changes ? 'leadId' and nullif(update_inspection.changes ->> 'leadId', '')::uuid is not null then
    v_lead := ${fn("inspection_set_team")}(v_row.${i("id")}, v_tenant, ${fn("inspection_team_with_lead")}(
      (select coalesce(jsonb_agg(jsonb_build_object('userId', y.${m("user")}, 'role', y.${m("role")})), '[]'::jsonb) from ${members} y where y.${m("inspection")} = v_row.${i("id")}),
      (update_inspection.changes ->> 'leadId')::uuid));
    update ${inspections} x set ${i("lead")} = v_lead where x.${i("id")} = v_row.${i("id")}
    returning * into v_row;
  end if;
  ${q.record("inspection.updated", "v_row", "inspection updated")}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("update_inspection")}(uuid, jsonb)`)}

-- Replaces the team of an open inspection with members, [{ userId, role }].
-- Needs inspections.manage, or inspections.write as its lead.
create or replace function ${fn("set_inspection_members")}(inspection_id uuid, members jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
  v_lead uuid;
begin
  ${load(q, "set_inspection_members")}
  if not ${q.acts(`v_row.${i("tenant")}`, `v_row.${i("id")}`, ["lead"])} then
    ${q.forbidden("not allowed to change this inspection's team")}
  end if;
  if v_row.${i("status")} in ('closed', 'canceled') then
    ${q.invalid("a closed or canceled inspection takes no changes")}
  end if;
  v_lead := ${fn("inspection_set_team")}(v_row.${i("id")}, v_row.${i("tenant")}, set_inspection_members.members);
  update ${inspections} x set ${i("lead")} = v_lead, ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${q.record("inspection.updated", "v_row", "inspection team changed")}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("set_inspection_members")}(uuid, jsonb)`)}
`;
}

function runFunctions(ctx: BlockSqlContext, q: InspectionsSql): string {
  const { fn, i, f, inspections, findings, inspectionJson, has } = q;
  const forms = q.forms;
  const save = forms.fn("form_submission_save");
  const s = (column: string): string => forms.col("submissions", column);

  const summary = has("inspections", "summary")
    ? `
  if length(complete_inspection.summary) > 20000 then
    ${q.invalid("summary is at most 20000 characters")}
  end if;`
    : `
  if nullif(trim(complete_inspection.summary), '') is not null then
    ${q.invalid("the inspections table has no summary column")}
  end if;`;

  const summarySet = has("inspections", "summary")
    ? `\n    ${i("summary")} = coalesce(nullif(trim(complete_inspection.summary), ''), x.${i("summary")}),`
    : "";

  return `
-- Starts a planned inspection as its lead or an auditor. With a checklist
-- form it opens a draft submission of that form on the inspection.
create or replace function ${fn("start_inspection")}(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
  v_submission jsonb;
begin
  ${load(q, "start_inspection")}
  if not ${q.acts(`v_row.${i("tenant")}`, `v_row.${i("id")}`, ["lead", "auditor"])} then
    ${q.forbidden("not allowed to start this inspection")}
  end if;
  if v_row.${i("status")} <> 'planned' then
    ${q.statusInvalid("v_row", "in_progress")}
  end if;
  if v_row.${i("checklistForm")} is not null and v_row.${i("checklistSubmission")} is null then
    v_submission := ${save}(v_row.${i("checklistForm")}, '{}'::jsonb, ${q.subject}, v_row.${i("id")}::text, auth.uid(), 'member', true, null);
  end if;
  update ${inspections} x set
    ${i("status")} = 'in_progress',
    ${i("startedAt")} = now(),
    ${i("checklistSubmission")} = coalesce((v_submission ->> 'id')::uuid, x.${i("checklistSubmission")}),
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${q.record("inspection.started", "v_row", "inspection started")}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("start_inspection")}(uuid)`)}

-- Saves the answers of the checklist of an inspection in progress, as its
-- lead or an auditor, as a draft or (draft false) submitted and validated.
create or replace function ${fn("save_inspection_checklist")}(inspection_id uuid, answers jsonb, draft boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
  v_respondent uuid;
begin
  ${load(q, "save_inspection_checklist")}
  if not ${q.acts(`v_row.${i("tenant")}`, `v_row.${i("id")}`, ["lead", "auditor"])} then
    ${q.forbidden("not allowed to fill in this checklist")}
  end if;
  if v_row.${i("status")} <> 'in_progress' then
    ${q.invalid("the checklist is filled in while the inspection is in progress")}
  end if;
  if v_row.${i("checklistSubmission")} is null then
    ${q.invalid("the inspection has no checklist")}
  end if;
  select x.${s("respondent")} into v_respondent from ${forms.table("submissions")} x
  where x.${s("id")} = v_row.${i("checklistSubmission")};
  return ${save}(v_row.${i("checklistForm")}, save_inspection_checklist.answers, ${q.subject}, v_row.${i("id")}::text,
    v_respondent, 'member', coalesce(save_inspection_checklist.draft, true), v_row.${i("checklistSubmission")});
end;
$$;
${userGrant(`${fn("save_inspection_checklist")}(uuid, jsonb, boolean)`)}

-- Ends the fieldwork of an inspection in progress as its lead: the checklist,
-- when there is one, is submitted. The inspection moves to reporting.
create or replace function ${fn("complete_inspection")}(inspection_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
begin
  ${load(q, "complete_inspection")}
  if not ${q.acts(`v_row.${i("tenant")}`, `v_row.${i("id")}`, ["lead"])} then
    ${q.forbidden("not allowed to complete this inspection")}
  end if;
  if v_row.${i("status")} <> 'in_progress' then
    ${q.statusInvalid("v_row", "reporting")}
  end if;${summary}
  if v_row.${i("checklistForm")} is not null and not exists (
    select 1 from ${forms.table("submissions")} y
    where y.${s("id")} = v_row.${i("checklistSubmission")} and y.${s("status")}::text in ('submitted', 'accepted')
  ) then
    ${fail("INSPECTION_CHECKLIST_INCOMPLETE", "submit the checklist before completing the inspection", "55000")}
  end if;
  update ${inspections} x set
    ${i("status")} = 'reporting',
    ${i("completedAt")} = now(),${summarySet}
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${q.record("inspection.completed", "v_row", "inspection completed")}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("complete_inspection")}(uuid, text)`)}

-- Closes an inspection in reporting as its lead. Every finding of a type in
-- options.caseFindingTypes needs a case first; the detail lists those without.
create or replace function ${fn("close_inspection")}(inspection_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
  v_open jsonb;
begin
  ${load(q, "close_inspection")}
  if not ${q.acts(`v_row.${i("tenant")}`, `v_row.${i("id")}`, ["lead"])} then
    ${q.forbidden("not allowed to close this inspection")}
  end if;
  if v_row.${i("status")} <> 'reporting' then
    ${q.statusInvalid("v_row", "closed")}
  end if;
  select jsonb_agg(y.${f("id")} order by y.${f("number")}) into v_open from ${findings} y
  where y.${f("tenant")} = v_row.${i("tenant")} and y.${f("inspection")} = v_row.${i("id")}
    and y.${f("type")} = any (${q.caseFindingTypes}) and y.${f("case")} is null;
  if v_open is not null then
    raise exception 'raise a case for every nonconformity before closing' using errcode = '55000', hint = 'INSPECTION_FINDINGS_OPEN', detail = jsonb_build_object('findingIds', v_open)::text;
  end if;
  ${ctx.hook("before_inspection_close", [["uuid", `v_row.${i("id")}`]])}
  update ${inspections} x set
    ${i("status")} = 'closed',
    ${i("closedAt")} = now(),
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${q.record("inspection.closed", "v_row", "inspection closed")}
  ${ctx.hook("after_inspection_close", [["uuid", `v_row.${i("id")}`]])}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("close_inspection")}(uuid)`)}

-- Cancels an inspection that hasn't closed. Needs inspections.manage.
create or replace function ${fn("cancel_inspection")}(inspection_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${inspections};
begin
  ${load(q, "cancel_inspection")}
  if not ${q.allowed(`v_row.${i("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to cancel inspections")}
  end if;
  if v_row.${i("status")} in ('closed', 'canceled') then
    ${q.statusInvalid("v_row", "canceled")}
  end if;
  if length(cancel_inspection.reason) > 4000 then
    ${q.invalid("reason is at most 4000 characters")}
  end if;
  update ${inspections} x set ${i("status")} = 'canceled', ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${q.record("inspection.cancelled", "v_row", "inspection canceled", ", 'reason', nullif(trim(cancel_inspection.reason), '')")}
  return ${inspectionJson("v_row")};
end;
$$;
${userGrant(`${fn("cancel_inspection")}(uuid, text)`)}
`;
}

export function inspectionFunctions(ctx: BlockSqlContext): string {
  const q = inspectionsSql(ctx);

  return `${programFunctions(ctx, q)}${teamFunction(ctx, q)}${scheduleFunctions(ctx, q)}${runFunctions(ctx, q)}`;
}
