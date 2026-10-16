import type { ExtraColumn, ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import { fail, pageSize, userGrant, writeExtraColumns } from "../shared.ts";
import { watchSql } from "../watch-sql.ts";

export interface WorkItemNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  /** The identifier prefix without number-sequences, such as `TASK-`. */
  readonly prefix: string;
  /** The most assignees an item takes; 0 for no limit. */
  readonly maxAssignees: number;
  readonly service: string;
  /** `options.extraColumns`: create writes them from attrs.fields, update by name. */
  readonly extras: readonly ExtraColumn[];
}

/** The fields `update_work_items` writes, by camelCase name. */
function fields(w: (column: string) => string): readonly {
  readonly field: string;
  readonly set: (v: string) => string;
}[] {
  const text = (column: string) => (v: string) =>
    `${w(column)} = nullif(trim(${v} #>> '{}'), '')`;
  const cast = (column: string, type: string) => (v: string) =>
    `${w(column)} = (${v} #>> '{}')::${type}`;
  return [
    { field: "title", set: (v) => `${w("title")} = trim(${v} #>> '{}')` },
    { field: "body", set: text("body") },
    { field: "parentId", set: cast("parent", "uuid") },
    { field: "teamId", set: cast("team", "uuid") },
    { field: "projectId", set: cast("project", "uuid") },
    { field: "iterationId", set: cast("iteration", "uuid") },
    { field: "priority", set: cast("priority", "smallint") },
    { field: "estimate", set: cast("estimate", "numeric") },
    { field: "progress", set: cast("progress", "smallint") },
    { field: "startAt", set: cast("startAt", "timestamptz") },
    { field: "endAt", set: cast("endAt", "timestamptz") },
    { field: "dueAt", set: cast("dueAt", "timestamptz") },
    { field: "stageId", set: cast("stage", "uuid") },
    { field: "closeReason", set: text("closeReason") },
  ];
}

export function workItemFunctions(
  ctx: ModuleContext,
  n: WorkItemNames,
): string {
  const { fn, t, c } = n;
  const w = (column: string): string => c("items", column);
  const a = (column: string): string => c("assignees", column);
  const editable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${w("tenant")}`, n.write)})`;
  const row = (alias: string): string =>
    `to_jsonb(${alias}) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra.${a("user")} order by ra.${a("createdAt")}, ra.${a("user")}) from ${t("assignees")} ra where ra.${a("item")} = ${alias}.${w("id")}), '[]'::jsonb))`;
  const record = (type: string, alias: string, extra = ""): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${alias}.${w("tenant")}, 'workItemId', ${alias}.${w("id")}, 'subjectType', 'work_item', 'subjectId', ${alias}.${w("id")}::text, 'title', ${alias}.${w("title")}${extra})`,
      subject: `'work-items/' || ${alias}.${w("id")}::text`,
      tenant: `${alias}.${w("tenant")}::text`,
      audit: false,
    });
  const writes = [
    ...fields(w).map(
      (field) => `      when ${sqlString(field.field)} then
        update ${t("items")} x set ${field.set("v_change -> 'value'")} where x.${w("id")} = v_item;`,
    ),
    ...n.extras.map(
      (extra) => `      when ${sqlString(extra.name)} then
        update ${t("items")} x set ${extra.ident} = (jsonb_populate_record(null::${t("items")}, jsonb_build_object(${sqlString(extra.name)}, v_change -> 'value'))).${extra.ident} where x.${w("id")} = v_item;`,
    ),
  ].join("\n");
  const watch = watchSql(ctx, {
    tenant: "v_row." + w("tenant"),
    user: "v_user",
    subjectType: "'work_item'",
    subjectId: "v_row." + w("id") + "::text",
  });
  const notify = ctx.installed("notifications")
    ? `
  if cardinality(v_new) > 0 then
    ${ctx.notify(
      `jsonb_build_object(
      'type', 'work_item.assigned',
      'tenant', v_row.${w("tenant")},
      'actor', auth.uid(),
      'subject_type', 'work_item',
      'subject_id', v_row.${w("id")}::text,
      'summary', v_row.${w("title")},
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'work_item.assigned:' || v_row.${w("id")}::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row.${w("id")})
    )`,
      { indent: "    " },
    )}
  end if;`
    : "";
  const limit =
    n.maxAssignees === 0
      ? ""
      : `
  if cardinality(v_users) > ${String(n.maxAssignees)} then
    ${fail("WORK_ITEM_ASSIGNEES_LIMIT", `an item takes at most ${String(n.maxAssignees)} assignees`, "22023")}
  end if;`;
  const p = (column: string): string => c("projects", column);
  const i = (column: string): string => c("iterations", column);
  const manageGuard = (
    tenant: string,
  ): string => `if not (${n.service} or ${ctx.scope.can(tenant, n.manage)}) then
    ${fail("WORK_ITEM_FORBIDDEN", "not allowed to manage projects and iterations")}
  end if;`;
  const projects = ctx.hasTable("projects")
    ? `
-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived.
create or replace function ${fn("save_project")}(tenant ${ctx.idType}, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_project.project;
begin
  ${manageGuard("save_project.tenant")}
  begin
    if v_id is null then
      insert into ${t("projects")} (${p("tenant")}, ${p("key")}, ${p("name")}, ${p("owner")}, ${p("status")}, ${p("startOn")}, ${p("targetOn")})
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date)
      returning ${p("id")} into v_id;
    else
      update ${t("projects")} x set
        ${p("key")} = coalesce(upper(save_project.attrs ->> 'key'), x.${p("key")}),
        ${p("name")} = coalesce(save_project.attrs ->> 'name', x.${p("name")}),
        ${p("owner")} = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x.${p("owner")} end,
        ${p("status")} = coalesce(save_project.attrs ->> 'status', x.${p("status")}),
        ${p("startOn")} = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x.${p("startOn")} end,
        ${p("targetOn")} = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x.${p("targetOn")} end,
        ${p("archivedAt")} = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x.${p("archivedAt")}, now()) end) else x.${p("archivedAt")} end,
        ${p("updatedAt")} = now()
      where x.${p("id")} = v_id and x.${p("tenant")} = save_project.tenant;
      if not found then
        ${fail("WORK_ITEM_PROJECT_NOT_FOUND", "project not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("WORK_ITEM_PROJECT_KEY_TAKEN", "another project has this key", "23505")}
  when check_violation or not_null_violation then
    ${fail("WORK_ITEM_PROJECT_INVALID", "a project needs a key of capitals and a name, and ends after it starts", "22023")}
  end;
  return (select to_jsonb(x) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y.${w("state")} = 'completed') / count(*) filter (where y.${w("state")} <> 'canceled')) end
      from ${t("items")} y where y.${w("project")} = x.${p("id")} and y.${w("archivedAt")} is null
    )) from ${t("projects")} x where x.${p("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_project")}(${ctx.idType}, uuid, jsonb)`)}
`
    : "";
  const iterations = ctx.hasTable("iterations")
    ? `
-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function ${fn("save_iteration")}(tenant ${ctx.idType}, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_iteration.iteration;
begin
  ${manageGuard("save_iteration.tenant")}
  begin
    if v_id is null then
      insert into ${t("iterations")} (${i("tenant")}, ${i("team")}, ${i("name")}, ${i("startsOn")}, ${i("endsOn")})
      values (save_iteration.tenant, (save_iteration.attrs ->> 'teamId')::uuid, save_iteration.attrs ->> 'name',
        (save_iteration.attrs ->> 'startsOn')::date, (save_iteration.attrs ->> 'endsOn')::date)
      returning ${i("id")} into v_id;
    else
      update ${t("iterations")} x set
        ${i("name")} = coalesce(save_iteration.attrs ->> 'name', x.${i("name")}),
        ${i("startsOn")} = coalesce((save_iteration.attrs ->> 'startsOn')::date, x.${i("startsOn")}),
        ${i("endsOn")} = coalesce((save_iteration.attrs ->> 'endsOn')::date, x.${i("endsOn")})
      where x.${i("id")} = v_id and x.${i("tenant")} = save_iteration.tenant;
      if not found then
        ${fail("WORK_ITEM_ITERATION_NOT_FOUND", "iteration not found", "P0002")}
      end if;
    end if;
  exception when check_violation or not_null_violation then
    ${fail("WORK_ITEM_ITERATION_INVALID", "an iteration needs a name and ends on or after it starts", "22023")}
  end;
  return (select to_jsonb(x) from ${t("iterations")} x where x.${i("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_iteration")}(${ctx.idType}, uuid, jsonb)`)}
`
    : "";
  return `
-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function ${fn("create_work_item")}(tenant ${ctx.idType}, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row ${t("items")};
begin
  if not (${n.service} or ${ctx.scope.can("create_work_item.tenant", n.write)}) then
    ${fail("WORK_ITEM_FORBIDDEN", "not allowed to change work items")}
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    ${fail("WORK_ITEM_TITLE_REQUIRED", "a title is required", "23502")}
  end if;
  ${ctx.hook("before_work_item_create", [
    [ctx.idType, "create_work_item.tenant"],
    ["jsonb", "create_work_item.attrs"],
  ])}
  ${assignNumberSql(
    ctx,
    "work_item",
    "create_work_item.tenant",
    { seq: "v_seq", identifier: "v_identifier" },
    {
      table: t("items"),
      seq: w("number"),
      tenant: w("tenant"),
      prefix: n.prefix,
    },
  )}
  begin
    insert into ${t("items")} (${w("tenant")}, ${w("number")}, ${w("identifier")}, ${w("title")}, ${w("body")}, ${w("parent")}, ${w("team")}, ${w("project")}, ${w("iteration")},
      ${w("priority")}, ${w("estimate")}, ${w("progress")}, ${w("startAt")}, ${w("endAt")}, ${w("dueAt")}, ${w("pipeline")}, ${w("stage")}, ${w("createdBy")})
    values (create_work_item.tenant, v_seq, v_identifier, trim(create_work_item.attrs ->> 'title'), create_work_item.attrs ->> 'body',
      (create_work_item.attrs ->> 'parentId')::uuid, (create_work_item.attrs ->> 'teamId')::uuid, (create_work_item.attrs ->> 'projectId')::uuid,
      (create_work_item.attrs ->> 'iterationId')::uuid, coalesce((create_work_item.attrs ->> 'priority')::smallint, 0),
      (create_work_item.attrs ->> 'estimate')::numeric, (create_work_item.attrs ->> 'progress')::smallint,
      (create_work_item.attrs ->> 'startAt')::timestamptz, (create_work_item.attrs ->> 'endAt')::timestamptz, (create_work_item.attrs ->> 'dueAt')::timestamptz,
      (create_work_item.attrs ->> 'pipelineId')::uuid, (create_work_item.attrs ->> 'stageId')::uuid, auth.uid())
    returning ${w("id")} into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    ${fail("WORK_ITEM_ATTRS_INVALID", "a work item field has an invalid value", "22023")}
  end;${writeExtraColumns(t("items"), n.extras, "(create_work_item.attrs -> 'fields')", `x.${w("id")} = v_id`)}
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform ${fn("set_work_item_assignees")}(v_id, create_work_item.assignees);
  end if;
  select * into v_row from ${t("items")} x where x.${w("id")} = v_id;
  ${record("work_item.created", "v_row")}
  ${ctx.hook("after_work_item_create", [["uuid", "v_id"]])}
  return (select ${row("x")} from ${t("items")} x where x.${w("id")} = v_id);
end;
$$;
${userGrant(`${fn("create_work_item")}(${ctx.idType}, jsonb, uuid[])`)}

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }.
create or replace function ${fn("update_work_items")}(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row ${t("items")};
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
begin
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    ${fail("WORK_ITEM_CHANGES_INVALID", "changes must be a list of { workItemId, field, value }", "22023")}
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from ${t("items")} x where x.${w("id")} = v_item and ${editable("x")} and x.${w("archivedAt")} is null) then
        ${fail("WORK_ITEM_NOT_FOUND", "no such work item you can edit", "P0002")}
      end if;
      ${ctx.hook("before_work_item_update", [
        ["uuid", "v_item"],
        ["text", "v_field"],
        ["jsonb", "v_change -> 'value'"],
      ])}
      case v_field
${writes}
      else
        ${fail("WORK_ITEM_FIELD_UNKNOWN", "that field can't be written", "22023")}
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      ${ctx.hook("after_work_item_update", [
        ["uuid", "v_item"],
        ["text", "v_field"],
      ])}
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from ${t("items")} x where x.${w("id")} = any (v_touched) loop
    ${record("work_item.updated", "v_row", `, 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row.${w("id")})`)}
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
${userGrant(`${fn("update_work_items")}(jsonb)`)}

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified.
create or replace function ${fn("set_work_item_assignees")}(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_new uuid[];
  v_user uuid;
  v_claims text;
begin
  select * into v_row from ${t("items")} x where x.${w("id")} = set_work_item_assignees.work_item and ${editable("x")};
  if v_row.${w("id")} is null then
    ${fail("WORK_ITEM_NOT_FOUND", "no such work item you can edit", "P0002")}
  end if;${limit}
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from ${t("assignees")} y where y.${a("item")} = v_row.${w("id")} and y.${a("user")} = x));
  delete from ${t("assignees")} y where y.${a("item")} = v_row.${w("id")} and not (y.${a("user")} = any (v_users));
  insert into ${t("assignees")} (${a("tenant")}, ${a("item")}, ${a("user")})
  select v_row.${w("tenant")}, v_row.${w("id")}, x from unnest(v_users) x
  on conflict do nothing;${
    watch === ""
      ? ""
      : `
  foreach v_user in array v_users loop
    ${watch}
  end loop;`
  }${notify}
  ${record("work_item.assigned", "v_row", ", 'assigneeIds', to_jsonb(v_users)")}
  return cardinality(v_users);
end;
$$;
${userGrant(`${fn("set_work_item_assignees")}(uuid, uuid[])`)}

create or replace function ${fn("archive_work_item")}(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  update ${t("items")} x set ${w("archivedAt")} = case when archive_work_item.archived then coalesce(x.${w("archivedAt")}, now()) end
  where x.${w("id")} = archive_work_item.work_item and ${editable("x")}
  returning * into v_row;
  if v_row.${w("id")} is null then
    return false;
  end if;
  if archive_work_item.archived then
    ${record("work_item.archived", "v_row")}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("archive_work_item")}(uuid, boolean)`)}

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function ${fn("delete_work_item")}(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  delete from ${t("items")} x
  where x.${w("id")} = delete_work_item.work_item
    and (${n.service} or x.${w("createdBy")} = auth.uid() or ${ctx.scope.can(`x.${w("tenant")}`, n.manage)})
  returning * into v_row;
  if v_row.${w("id")} is null then
    return false;
  end if;
  ${record("work_item.deleted", "v_row")}
  return true;
end;
$$;
${userGrant(`${fn("delete_work_item")}(uuid)`)}

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function ${fn("work_item_tree")}(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from ${t("items")} x where x.${w("id")} = work_item_tree.root
    union all
    select y.*, tree.depth + 1 from ${t("items")} y join tree on y.${w("parent")} = tree.${w("id")}
    where tree.depth < 100 and y.${w("archivedAt")} is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree.${w("id")}, 'parentId', tree.${w("parent")}, 'identifier', tree.${w("identifier")}, 'title', tree.${w("title")},
    'state', tree.${w("state")}, 'startAt', tree.${w("startAt")}, 'endAt', tree.${w("endAt")}, 'dueAt', tree.${w("dueAt")},
    'locked', tree.${w("locked")}, 'depth', tree.depth,
    'progress', coalesce(tree.${w("progress")}, (
      select case when count(*) filter (where ch.${w("state")} <> 'canceled') = 0 then
          case tree.${w("state")} when 'completed' then 100 else 0 end
        else round(100.0 * count(*) filter (where ch.${w("state")} = 'completed') / count(*) filter (where ch.${w("state")} <> 'canceled'))::integer end
      from ${t("items")} ch where ch.${w("parent")} = tree.${w("id")} and ch.${w("archivedAt")} is null))
  ) order by tree.depth, tree.${w("rank")} collate "C", tree.${w("id")}), '[]'::jsonb)
  from tree
$$;
${userGrant(`${fn("work_item_tree")}(uuid)`)}

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function ${fn("list_work_items")}(tenant ${ctx.idType}, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select ${row("x")} as value, x.${w("number")} as number
    from ${t("items")} x
    where x.${w("tenant")} = list_work_items.tenant and x.${w("archivedAt")} is null
      and (list_work_items.filter ->> 'teamId' is null or x.${w("team")} = (list_work_items.filter ->> 'teamId')::uuid)
      and (list_work_items.filter ->> 'projectId' is null or x.${w("project")} = (list_work_items.filter ->> 'projectId')::uuid)
      and (list_work_items.filter ->> 'iterationId' is null or x.${w("iteration")} = (list_work_items.filter ->> 'iterationId')::uuid)
      and (list_work_items.filter ->> 'parentId' is null or x.${w("parent")} = (list_work_items.filter ->> 'parentId')::uuid)
      and (list_work_items.filter ->> 'assigneeId' is null or exists (select 1 from ${t("assignees")} y where y.${a("item")} = x.${w("id")} and y.${a("user")} = (list_work_items.filter ->> 'assigneeId')::uuid))
      and (list_work_items.filter -> 'states' is null or x.${w("state")} = any (array(select jsonb_array_elements_text(list_work_items.filter -> 'states'))))
      and (coalesce((list_work_items.filter ->> 'open')::boolean, false) = false or x.${w("closedAt")} is null)
      and (list_work_items.search is null or x.${w("title")} ilike '%' || list_work_items.search || '%' or x.${w("identifier")} ilike list_work_items.search || '%')
      and (list_work_items.after is null or x.${w("number")} < (select z.${w("number")} from ${t("items")} z where z.${w("id")} = list_work_items.after))
    order by x.${w("number")} desc
    limit ${pageSize("list_work_items.page_size", 50, 200)}
  ) p
$$;
${userGrant(`${fn("list_work_items")}(${ctx.idType}, jsonb, text, uuid, integer)`)}
${projects}${iterations}`;
}
