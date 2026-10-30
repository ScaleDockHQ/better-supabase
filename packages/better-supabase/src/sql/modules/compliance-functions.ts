import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  CONTROL_RESERVED,
  evidenceAttachments,
  FRAMEWORK_KINDS,
  optionalField,
} from "./compliance-shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The arguments of save_control before it took a source and a jurisdiction. */
const PREVIOUS_CONTROL_ARGS = "uuid, text, text, text, uuid, boolean, uuid";

/** The framework, control, evidence and evidence task functions. */
export function complianceFunctions(ctx: BlockSqlContext): string {
  const frameworks = ctx.table("frameworks");
  const controls = ctx.table("controls");
  const evidence = ctx.table("evidence");
  const tasks = ctx.table("tasks");
  const f = (column: string): string => ctx.col("frameworks", column);
  const k = (column: string): string => ctx.col("controls", column);
  const e = (column: string): string => ctx.col("evidence", column);
  const t = (column: string): string => ctx.col("tasks", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("compliance");
  const manage = ctx.permission("manage", permissions.manage);
  const collect = ctx.permission("collect", permissions.collect);
  const members = ctx.of("memberships");
  const attachments = evidenceAttachments(ctx);
  const controlType = sqlString(ctx.resolved.entityNaming.rename("control"));
  const extras = ctx.extraColumns("controls", CONTROL_RESERVED);
  const extra = extraFieldsArg(extras);

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const field = (table: string, row: string, column: string): string =>
    optionalField(ctx, table, row, column);

  const insertCol = (table: string, column: string): string =>
    has(table, column) ? `, ${ctx.col(table, column)}` : "";

  const insertVal = (table: string, column: string, value: string): string =>
    has(table, column) ? `, ${value}` : "";

  const touch = (table: string): string =>
    has(table, "updatedAt") ? `, ${ctx.col(table, "updatedAt")} = now()` : "";

  const labels = ["source", "jurisdiction"].filter((column) =>
    has("controls", column),
  );

  const labelSets = (row: string): string =>
    labels.map((column) => `, ${k(column)} = ${row}.${k(column)}`).join("");

  const labelUpdates = labels
    .map(
      (column) => `${k(column)} = nullif(trim(save_control.${column}), ''), `,
    )
    .join("");

  const assignee = has("tasks", "assignee");
  const owner = has("controls", "owner");

  const frameworkSets = [
    `${f("name")} = excluded.${f("name")}${has("frameworks", "kind") ? `, ${f("kind")} = excluded.${f("kind")}` : ""}${has("frameworks", "version") ? `, ${f("version")} = excluded.${f("version")}` : ""}`,
    [
      has("frameworks", "description")
        ? `${f("description")} = excluded.${f("description")}`
        : "",
      has("frameworks", "updatedAt") ? `${f("updatedAt")} = now()` : "",
    ]
      .filter((set) => set !== "")
      .join(", "),
  ]
    .filter((line) => line !== "")
    .join(",\n      ");

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("CONTROL_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("CONTROL_INVALID", message, "22023");

  const controlNotFound = fail(
    "CONTROL_NOT_FOUND",
    "control not found",
    "P0002",
  );

  const isMember = (tenant: string, user: string): string =>
    `exists (select 1 from ${members.table("memberships")} m where m.${members.col("memberships", "tenant")} = ${tenant} and m.${members.col("memberships", "user")} = ${user})`;

  const overdue = (row: string): string =>
    `(${row}.${t("active")} and ${row}.${t("dueOn")} < current_date)`;

  const valid = (row: string): string =>
    `(${row}.${e("validUntil")} is null or ${row}.${e("validUntil")} >= current_date)`;

  // not_applicable, failing (an overdue task, or evidence that lapsed),
  // passing (current evidence) or not_started (no evidence yet).
  const status = (row: string): string => `case
    when not ${row}.${k("applicable")} then 'not_applicable'
    when exists (select 1 from ${tasks} st where st.${t("control")} = ${row}.${k("id")} and ${overdue("st")}) then 'failing'
    when exists (select 1 from ${evidence} se where se.${e("control")} = ${row}.${k("id")} and ${valid("se")}) then 'passing'
    when exists (select 1 from ${evidence} se where se.${e("control")} = ${row}.${k("id")}) then 'failing'
    else 'not_started'
  end`;

  const controlJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${k("id")}, 'organizationId', ${row}.${k("tenant")}, 'frameworkId', ${row}.${k("framework")}, 'code', ${row}.${k("code")}, 'title', ${row}.${k("title")}, 'description', ${field("controls", row, "description")}, 'ownerId', ${field("controls", row, "owner")}, 'applicable', ${row}.${k("applicable")}, 'source', ${field("controls", row, "source")}, 'jurisdiction', ${field("controls", row, "jurisdiction")}, 'status', ${status(row)}, 'createdAt', ${field("controls", row, "createdAt")}, 'updatedAt', ${field("controls", row, "updatedAt")}${extraFieldsJson(row, extras)})`;

  const frameworkJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${f("id")}, 'organizationId', ${row}.${f("tenant")}, 'key', ${row}.${f("key")}, 'name', ${row}.${f("name")}, 'kind', ${has("frameworks", "kind") ? `${row}.${f("kind")}` : "'standard'"}, 'version', ${field("frameworks", row, "version")}, 'description', ${field("frameworks", row, "description")}, 'createdAt', ${field("frameworks", row, "createdAt")}, 'updatedAt', ${field("frameworks", row, "updatedAt")})`;

  const evidenceJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${e("id")}, 'organizationId', ${row}.${e("tenant")}, 'controlId', ${row}.${e("control")}, 'evidenceTaskId', ${row}.${e("task")}, 'attachmentId', ${row}.${e("attachment")}, 'note', ${field("evidence", row, "note")}, 'collectedBy', ${row}.${e("collectedBy")}, 'collectedAt', ${row}.${e("collectedAt")}, 'validUntil', ${row}.${e("validUntil")}, 'valid', ${valid(row)})`;

  const taskJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, 'controlId', ${row}.${t("control")}, 'title', ${row}.${t("title")}, 'assigneeId', ${field("tasks", row, "assignee")}, 'intervalDays', ${row}.${t("intervalDays")}, 'dueOn', ${row}.${t("dueOn")}, 'lastCollectedAt', ${field("tasks", row, "lastCollectedAt")}, 'active', ${row}.${t("active")}, 'overdue', ${overdue(row)}, 'createdAt', ${field("tasks", row, "createdAt")}, 'updatedAt', ${field("tasks", row, "updatedAt")})`;

  const attachmentCheck =
    attachments === undefined
      ? `if add_control_evidence.attachment_id is not null then
    ${invalid("evidence files need the attachments module")}
  end if;`
      : `if add_control_evidence.attachment_id is not null and not exists (
    select 1 from ${attachments.table("attachments")} a
    where a.${attachments.col("attachments", "id")} = add_control_evidence.attachment_id
      and a.${attachments.col("attachments", "tenant")} = v_control.${k("tenant")}
  ) then
    ${invalid("the attachment isn't a file in this organization")}
  end if;`;

  // The assignee hears about a missed task, or the control's owner without one.
  const recipient = assignee
    ? `coalesce(v_task.${t("assignee")}, v_owner)`
    : "v_owner";

  const overdueNotify = ctx.installed("notifications")
    ? `if ${recipient} is not null then
      ${ctx.notify(
        `jsonb_build_object(
        'type', 'evidence_task.missed',
        'tenant', v_task.${t("tenant")},
        'actor', null,
        'subject_type', ${controlType},
        'subject_id', v_task.${t("control")}::text,
        'summary', v_task.${t("title")},
        'recipients', to_jsonb(array[${recipient}]),
        'key', 'evidence_task.missed:' || v_task.${t("id")}::text || ':' || v_task.${t("dueOn")}::text,
        'data', jsonb_build_object('evidenceTaskId', v_task.${t("id")}, 'dueOn', v_task.${t("dueOn")})
      )`,
        { indent: "      " },
      )}
    end if;`
    : "";

  return `
-- Creates or updates a framework (SOC 2, ISO 27001, an internal one) by key.
-- kind is standard, legal (a register of legal obligations), internal or
-- contract.
drop function if exists ${fn("save_control_framework")}(${idType}, text, text, text, text);
create or replace function ${fn("save_control_framework")}(tenant ${idType}, key text, name text, version text default null, description text default null, kind text default 'standard')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${frameworks}%rowtype;
begin
  if not ${allowed("save_control_framework.tenant", manage)} then
    ${forbidden("not allowed to manage controls")}
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in (${FRAMEWORK_KINDS.map((item) => `'${item}'`).join(", ")}) then
    ${invalid(`kind must be one of ${FRAMEWORK_KINDS.join(", ")}`)}
  end if;
  insert into ${frameworks} (${f("tenant")}, ${f("key")}, ${f("name")}${insertCol("frameworks", "kind")}${insertCol("frameworks", "version")}${insertCol("frameworks", "description")})
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name)${insertVal("frameworks", "kind", "save_control_framework.kind")}${insertVal("frameworks", "version", "nullif(trim(save_control_framework.version), '')")}${insertVal("frameworks", "description", "nullif(trim(save_control_framework.description), '')")})
  on conflict (${f("tenant")}, ${f("key")}) do update
    set ${frameworkSets}
  returning * into v_row;
  return ${frameworkJson("v_row")};
end;
$$;
${userGrant(`${fn("save_control_framework")}(${idType}, text, text, text, text, text)`)}

create or replace function ${fn("list_control_frameworks")}(tenant ${idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${frameworkJson("x")} order by x.${f("name")}), '[]'::jsonb)
  from ${frameworks} x
  where x.${f("tenant")} = list_control_frameworks.tenant
$$;
${userGrant(`${fn("list_control_frameworks")}(${idType})`)}

-- Creates a control in a framework, or changes one (control_id). Without
-- control_id, a control with the same code in the framework is updated.
-- source names where an obligation comes from (a law or a clause) and
-- jurisdiction where it applies.
drop function if exists ${fn("save_control")}(${PREVIOUS_CONTROL_ARGS});
drop function if exists ${fn("save_control")}(${PREVIOUS_CONTROL_ARGS}, jsonb);
${extra.drop(fn("save_control"), `${PREVIOUS_CONTROL_ARGS}, text, text`)}
create or replace function ${fn("save_control")}(framework_id uuid, code text, title text, description text default null, owner_id uuid default null, applicable boolean default true, control_id uuid default null, source text default null, jurisdiction text default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_framework ${frameworks}%rowtype;
  v_row ${controls}%rowtype;
  v_new boolean;
begin
  select * into v_framework from ${frameworks} x where x.${f("id")} = save_control.framework_id;
  if not found then
    ${fail("CONTROL_FRAMEWORK_NOT_FOUND", "framework not found", "P0002")}
  end if;
  if not ${allowed(`v_framework.${f("tenant")}`, manage)} then
    ${forbidden("not allowed to manage controls")}
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    ${invalid("a control needs a code and a title")}
  end if;
${
  owner
    ? `  if save_control.owner_id is not null and not ${isMember(`v_framework.${f("tenant")}`, "save_control.owner_id")} then
    ${invalid("the owner must be a member of the organization")}
  end if;
`
    : ""
}  if save_control.control_id is null then
    insert into ${controls} (${k("tenant")}, ${k("framework")}, ${k("code")}, ${k("title")}${insertCol("controls", "description")}${insertCol("controls", "owner")}${insertCol("controls", "source")}${insertCol("controls", "jurisdiction")}, ${k("applicable")})
    values (v_framework.${f("tenant")}, v_framework.${f("id")}, trim(save_control.code), trim(save_control.title)${insertVal("controls", "description", "nullif(trim(save_control.description), '')")}${insertVal("controls", "owner", "save_control.owner_id")}${insertVal("controls", "source", "nullif(trim(save_control.source), '')")}${insertVal("controls", "jurisdiction", "nullif(trim(save_control.jurisdiction), '')")}, coalesce(save_control.applicable, true))
    on conflict (${k("framework")}, ${k("code")}) do update
      set ${k("title")} = excluded.${k("title")}${has("controls", "description") ? `, ${k("description")} = excluded.${k("description")}` : ""}${labelSets("excluded")},
        ${owner ? `${k("owner")} = excluded.${k("owner")}, ` : ""}${k("applicable")} = excluded.${k("applicable")}${touch("controls")}
    returning * into v_row;
  else
    update ${controls} x set ${k("code")} = trim(save_control.code), ${k("title")} = trim(save_control.title),
      ${has("controls", "description") ? `${k("description")} = nullif(trim(save_control.description), ''), ` : ""}${labelUpdates}${owner ? `${k("owner")} = save_control.owner_id,\n      ` : ""}${k("applicable")} = coalesce(save_control.applicable, true)${touch("controls")}
      where x.${k("id")} = save_control.control_id and x.${k("framework")} = v_framework.${f("id")}
      returning * into v_row;
    if not found then
      ${controlNotFound}
    end if;
  end if;${writeExtraColumns(controls, extras, "save_control.fields", `x.${k("id")} = v_row.${k("id")}`, "v_row")}
  ${ctx.record({
    type: "control.saved",
    payload: `jsonb_build_object('organizationId', v_row.${k("tenant")}, 'controlId', v_row.${k("id")}, 'frameworkId', v_row.${k("framework")}, 'code', v_row.${k("code")})`,
    subject: `'controls/' || v_row.${k("id")}::text`,
    tenant: `v_row.${k("tenant")}`,
    audit: {
      category: "data",
      targetType: "control",
      recordId: `v_row.${k("id")}::text`,
      summary: `'saved control ' || v_row.${k("code")}`,
    },
  })}
  return ${controlJson("v_row")};
end;
$$;
${userGrant(`${fn("save_control")}(${PREVIOUS_CONTROL_ARGS}, text, text${extra.type})`)}

-- A control with its evidence (the newest first) and its evidence tasks.
create or replace function ${fn("get_control")}(control_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row ${controls}%rowtype;
begin
  select * into v_row from ${controls} x where x.${k("id")} = get_control.control_id;
  if not found then
    ${controlNotFound}
  end if;
  return ${controlJson("v_row")} || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(${evidenceJson("y")} order by y.${e("collectedAt")} desc), '[]'::jsonb)
      from (select * from ${evidence} z where z.${e("control")} = v_row.${k("id")} order by z.${e("collectedAt")} desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(${taskJson("y")} order by y.${t("dueOn")}), '[]'::jsonb)
      from ${tasks} y where y.${t("control")} = v_row.${k("id")})
  );
end;
$$;
${userGrant(`${fn("get_control")}(uuid)`)}

-- The controls the caller can read, by framework and code. status filters on
-- the computed status.
create or replace function ${fn("list_controls")}(tenant ${idType}, framework_id uuid default null, status text default null, owner_id uuid default null, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y.${k("framework")} as framework, y.${k("code")} as code, ${controlJson("y")} as doc
    from ${controls} y
    where y.${k("tenant")} = list_controls.tenant
      and (list_controls.framework_id is null or y.${k("framework")} = list_controls.framework_id)
      and (list_controls.owner_id is null${owner ? ` or y.${k("owner")} = list_controls.owner_id` : ""})
      and (list_controls.status is null or ${status("y")} = list_controls.status)
    order by y.${k("framework")}, y.${k("code")}
    limit ${pageSize("list_controls.page_size", 200, 1000)}
  ) x
$$;
${userGrant(`${fn("list_controls")}(${idType}, uuid, text, uuid, integer)`)}

-- Records evidence for a control: an attachment on it, a note, or both. With
-- task_id it answers that recurring task, whose due date moves interval_days
-- past today; valid_until then defaults to that date. The task's assignee
-- may collect without the collect permission.
create or replace function ${fn("add_control_evidence")}(control_id uuid, attachment_id uuid default null, note text default null, valid_until date default null, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control ${controls}%rowtype;
  v_task ${tasks}%rowtype;
  v_row ${evidence}%rowtype;
begin
  select * into v_control from ${controls} x where x.${k("id")} = add_control_evidence.control_id;
  if not found then
    ${controlNotFound}
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from ${tasks} x
      where x.${t("id")} = add_control_evidence.task_id and x.${t("control")} = v_control.${k("id")}
      for update;
    if not found then
      ${fail("EVIDENCE_TASK_NOT_FOUND", "the evidence task isn't a task of this control", "P0002")}
    end if;
  end if;
  if not (${allowed(`v_control.${k("tenant")}`, collect)}${assignee ? ` or (v_task.${t("assignee")} is not null and coalesce(v_task.${t("assignee")} = auth.uid(), false))` : ""}) then
    ${forbidden("not allowed to collect evidence")}
  end if;
  ${
    has("evidence", "note")
      ? `if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    ${invalid("evidence needs an attachment or a note")}
  end if;`
      : `if add_control_evidence.attachment_id is null then
    ${invalid("evidence needs an attachment")}
  end if;`
  }
  ${attachmentCheck}
  insert into ${evidence} (${e("tenant")}, ${e("control")}, ${e("task")}, ${e("attachment")}${insertCol("evidence", "note")}, ${e("collectedBy")}, ${e("validUntil")})
  values (v_control.${k("tenant")}, v_control.${k("id")}, v_task.${t("id")}, add_control_evidence.attachment_id,
    ${has("evidence", "note") ? "nullif(trim(add_control_evidence.note), ''), " : ""}auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task.${t("intervalDays")}))
  returning * into v_row;
  if v_task.${t("id")} is not null then
    update ${tasks} x set ${t("dueOn")} = current_date + x.${t("intervalDays")}${has("tasks", "lastCollectedAt") ? `, ${t("lastCollectedAt")} = now()` : ""},
      ${t("notifiedFor")} = null${touch("tasks")}
      where x.${t("id")} = v_task.${t("id")};
  end if;
  ${ctx.record({
    type: "control.evidence_added",
    payload: `jsonb_build_object('organizationId', v_row.${e("tenant")}, 'controlId', v_row.${e("control")}, 'evidenceId', v_row.${e("id")}, 'evidenceTaskId', v_row.${e("task")})`,
    subject: `'controls/' || v_row.${e("control")}::text`,
    tenant: `v_row.${e("tenant")}`,
    audit: {
      category: "data",
      targetType: "control",
      recordId: `v_row.${e("control")}::text`,
      summary: `'collected evidence for control ' || v_control.${k("code")}`,
    },
  })}
  return ${evidenceJson("v_row")};
end;
$$;
${userGrant(`${fn("add_control_evidence")}(uuid, uuid, text, date, uuid)`)}

create or replace function ${fn("remove_control_evidence")}(evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${evidence}%rowtype;
begin
  select * into v_row from ${evidence} x where x.${e("id")} = remove_control_evidence.evidence_id;
  if not found then
    ${fail("CONTROL_EVIDENCE_NOT_FOUND", "evidence not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${e("tenant")}`, manage)} then
    ${forbidden("not allowed to manage controls")}
  end if;
  delete from ${evidence} x where x.${e("id")} = v_row.${e("id")};
  return ${evidenceJson("v_row")};
end;
$$;
${userGrant(`${fn("remove_control_evidence")}(uuid)`)}

-- Creates a recurring evidence task on a control, or changes one (task_id).
-- due_on defaults to today: the first evidence is due now.
create or replace function ${fn("save_evidence_task")}(control_id uuid, title text, interval_days integer, due_on date default null, assignee_id uuid default null, active boolean default true, task_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_control ${controls}%rowtype;
  v_row ${tasks}%rowtype;
begin
  select * into v_control from ${controls} x where x.${k("id")} = save_evidence_task.control_id;
  if not found then
    ${controlNotFound}
  end if;
  if not ${allowed(`v_control.${k("tenant")}`, manage)} then
    ${forbidden("not allowed to manage controls")}
  end if;
  if nullif(trim(save_evidence_task.title), '') is null then
    ${invalid("an evidence task needs a title")}
  end if;
  if save_evidence_task.interval_days is null or save_evidence_task.interval_days not between 1 and 3650 then
    ${invalid("interval_days must be from 1 to 3650")}
  end if;
${
  assignee
    ? `  if save_evidence_task.assignee_id is not null and not ${isMember(`v_control.${k("tenant")}`, "save_evidence_task.assignee_id")} then
    ${invalid("the assignee must be a member of the organization")}
  end if;
`
    : ""
}  if save_evidence_task.task_id is null then
    insert into ${tasks} (${t("tenant")}, ${t("control")}, ${t("title")}${insertCol("tasks", "assignee")}, ${t("intervalDays")}, ${t("dueOn")}, ${t("active")})
    values (v_control.${k("tenant")}, v_control.${k("id")}, trim(save_evidence_task.title)${insertVal("tasks", "assignee", "save_evidence_task.assignee_id")},
      save_evidence_task.interval_days, coalesce(save_evidence_task.due_on, current_date), coalesce(save_evidence_task.active, true))
    returning * into v_row;
  else
    update ${tasks} x set ${t("title")} = trim(save_evidence_task.title)${assignee ? `, ${t("assignee")} = save_evidence_task.assignee_id` : ""},
      ${t("intervalDays")} = save_evidence_task.interval_days, ${t("dueOn")} = coalesce(save_evidence_task.due_on, x.${t("dueOn")}),
      ${t("active")} = coalesce(save_evidence_task.active, true)${touch("tasks")}
      where x.${t("id")} = save_evidence_task.task_id and x.${t("control")} = v_control.${k("id")}
      returning * into v_row;
    if not found then
      ${fail("EVIDENCE_TASK_NOT_FOUND", "the evidence task isn't a task of this control", "P0002")}
    end if;
  end if;
  return ${taskJson("v_row")};
end;
$$;
${userGrant(`${fn("save_evidence_task")}(uuid, text, integer, date, uuid, boolean, uuid)`)}

-- The evidence tasks the caller can read, the earliest due first.
create or replace function ${fn("list_evidence_tasks")}(tenant ${idType}, control_id uuid default null, assignee_id uuid default null, overdue_only boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${taskJson("x")} || jsonb_build_object('controlCode', y.${k("code")}, 'controlTitle', y.${k("title")}) order by x.${t("dueOn")}, x.${t("id")}), '[]'::jsonb)
  from ${tasks} x
  join ${controls} y on y.${k("id")} = x.${t("control")}
  where x.${t("tenant")} = list_evidence_tasks.tenant
    and (list_evidence_tasks.control_id is null or x.${t("control")} = list_evidence_tasks.control_id)
    and (list_evidence_tasks.assignee_id is null${assignee ? ` or x.${t("assignee")} = list_evidence_tasks.assignee_id` : ""})
    and (not coalesce(list_evidence_tasks.overdue_only, false) or ${overdue("x")})
$$;
${userGrant(`${fn("list_evidence_tasks")}(${idType}, uuid, uuid, boolean)`)}

-- The status rollup per framework: how many controls pass, fail, haven't
-- started or are out of scope, and how many evidence tasks are overdue.
create or replace function ${fn("control_posture")}(tenant ${idType}, framework_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'frameworkId', w.${f("id")}, 'key', w.${f("key")}, 'name', w.${f("name")}, 'version', ${field("frameworks", "w", "version")},
    'total', coalesce(r.total, 0), 'passing', coalesce(r.passing, 0), 'failing', coalesce(r.failing, 0),
    'notStarted', coalesce(r.not_started, 0), 'notApplicable', coalesce(r.not_applicable, 0),
    'overdueTasks', (select count(*) from ${tasks} ot join ${controls} oc on oc.${k("id")} = ot.${t("control")} where oc.${k("framework")} = w.${f("id")} and ${overdue("ot")})
  ) order by w.${f("name")}), '[]'::jsonb)
  from ${frameworks} w
  left join lateral (
    select count(*) as total,
      count(*) filter (where s.status = 'passing') as passing,
      count(*) filter (where s.status = 'failing') as failing,
      count(*) filter (where s.status = 'not_started') as not_started,
      count(*) filter (where s.status = 'not_applicable') as not_applicable
    from (select ${status("y")} as status from ${controls} y where y.${k("framework")} = w.${f("id")}) s
  ) r on true
  where w.${f("tenant")} = control_posture.tenant
    and (control_posture.framework_id is null or w.${f("id")} = control_posture.framework_id)
$$;
${userGrant(`${fn("control_posture")}(${idType}, uuid)`)}

-- Reports each active evidence task past its due date once per lapse: an
-- evidence_task.missed event and, with notifications, a notification to the
-- assignee (or the control's owner). Run it daily from a job.
create or replace function ${fn("notify_overdue_evidence_tasks")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task ${tasks}%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from ${tasks} x
    where ${overdue("x")} and x.${t("notifiedFor")} is distinct from x.${t("dueOn")}
    for update skip locked
  loop
    ${owner ? `select y.${k("owner")} into v_owner from ${controls} y where y.${k("id")} = v_task.${t("control")};` : "v_owner := null;"}
    ${ctx.record({
      type: "evidence_task.missed",
      payload: `jsonb_build_object('organizationId', v_task.${t("tenant")}, 'evidenceTaskId', v_task.${t("id")}, 'controlId', v_task.${t("control")}, 'assigneeId', ${field("tasks", "v_task", "assignee")}, 'dueOn', v_task.${t("dueOn")})`,
      subject: `'evidence-tasks/' || v_task.${t("id")}::text`,
      tenant: `v_task.${t("tenant")}`,
      audit: {
        category: "data",
        targetType: "evidence_task",
        recordId: `v_task.${t("id")}::text`,
        summary: `'evidence task overdue: ' || v_task.${t("title")}`,
      },
    })}
    ${overdueNotify}
    update ${tasks} x set ${t("notifiedFor")} = v_task.${t("dueOn")} where x.${t("id")} = v_task.${t("id")};
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_overdue_evidence_tasks")}()`)}
`;
}
