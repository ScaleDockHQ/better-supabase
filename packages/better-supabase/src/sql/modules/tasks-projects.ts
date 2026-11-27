import type { BlockSqlContext } from "../context.ts";
import type { TaskNames } from "./tasks-functions.ts";

import { sqlString } from "../../core/template.ts";
import { entityType } from "../resolved-names.ts";
import { fail, userGrant } from "../shared.ts";
import { actorPayload } from "./tasks-coordination-shared.ts";

/** Tables and columns a project page adds on top of the task row. */
export function projectWorkSql(ctx: BlockSqlContext): string {
  const parts: string[] = [];

  const alter = (table: string, logical: string, definition: string): void => {
    if (ctx.has(table, logical)) {
      parts.push(
        `alter table ${ctx.table(table)} add column if not exists ${ctx.col(table, logical)} ${definition};`,
      );
    }
  };

  alter("items", "milestone", "uuid");
  alter("items", "duplicateOf", "uuid");
  alter("items", "snoozedUntil", "timestamptz");
  alter("projects", "template", "boolean not null default false");
  alter("iterations", "number", "integer");
  alter("iterations", "description", "text");

  if (ctx.hasTable("projects") && ctx.hasTable("milestones")) {
    const m = (column: string): string => ctx.col("milestones", column);

    parts.push(`
create table if not exists ${ctx.table("milestones")} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("project")} uuid not null references ${ctx.table("projects")} (${ctx.col("projects", "id")}) on delete cascade,
  ${m("name")} text not null check (length(${m("name")}) between 1 and 200),
  ${m("description")} text,
  ${m("targetOn")} date,
  ${m("rank")} text collate "C" not null default 'V',
  ${m("createdAt")} timestamptz not null default now(),
  ${m("updatedAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("milestones_project_idx")} on ${ctx.table("milestones")} (${m("project")}, ${m("rank")});`);
  }

  if (ctx.hasTable("iterations") && ctx.hasTable("cadences")) {
    const d = (column: string): string => ctx.col("cadences", column);

    parts.push(`
create table if not exists ${ctx.table("cadences")} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("team")} uuid not null,
  ${d("weeks")} smallint not null check (${d("weeks")} between 1 and 8),
  ${d("cooldownDays")} smallint not null default 0 check (${d("cooldownDays")} between 0 and 28),
  ${d("startWeekday")} smallint not null default 1 check (${d("startWeekday")} between 1 and 7),
  ${d("upcoming")} smallint not null default 2 check (${d("upcoming")} between 0 and 12),
  ${d("rollover")} boolean not null default true,
  ${d("createdAt")} timestamptz not null default now(),
  unique (${d("tenant")}, ${d("team")})
);`);
  }

  if (ctx.hasTable("iterations") && ctx.hasTable("snapshots")) {
    const s = (column: string): string => ctx.col("snapshots", column);

    parts.push(`
create table if not exists ${ctx.table("snapshots")} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("iteration")} uuid not null references ${ctx.table("iterations")} (${ctx.col("iterations", "id")}) on delete cascade,
  ${s("day")} date not null,
  ${s("scope")} integer not null,
  ${s("started")} integer not null,
  ${s("completed")} integer not null,
  unique (${s("iteration")}, ${s("day")})
);`);
  }

  if (
    ctx.text("identifiers", "tenant") === "project" &&
    ctx.hasTable("identifiers")
  ) {
    const k = (column: string): string => ctx.col("identifiers", column);
    const items = ctx.tableName("items");

    parts.push(`
create table if not exists ${ctx.table("identifiers")} (
  ${k("tenant")} ${ctx.idType} not null,
  ${k("identifier")} text not null,
  ${k("item")} uuid not null references ${ctx.table("items")} (${ctx.col("items", "id")}) on delete cascade,
  ${k("createdAt")} timestamptz not null default now(),
  primary key (${k("tenant")}, ${k("identifier")})
);
alter table ${ctx.table("items")} drop constraint if exists ${ctx.naming.rename(`${items.name}_tenant_id_number_key`)};

create or replace function ${ctx.fn("remember_task_identifier")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.${ctx.col("items", "identifier")} is distinct from new.${ctx.col("items", "identifier")} then
    insert into ${ctx.table("identifiers")} (${k("tenant")}, ${k("identifier")}, ${k("item")})
    values (old.${ctx.col("items", "tenant")}, old.${ctx.col("items", "identifier")}, old.${ctx.col("items", "id")})
    on conflict do nothing;
  end if;
  insert into ${ctx.table("identifiers")} (${k("tenant")}, ${k("identifier")}, ${k("item")})
  values (new.${ctx.col("items", "tenant")}, new.${ctx.col("items", "identifier")}, new.${ctx.col("items", "id")})
  on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists ${ctx.naming.rename("remember_task_identifier")} on ${ctx.table("items")};
create trigger ${ctx.naming.rename("remember_task_identifier")}
  after insert or update of ${ctx.col("items", "identifier")} on ${ctx.table("items")}
  for each row execute function ${ctx.fn("remember_task_identifier")}();`);
  }

  return parts.join("\n");
}

/**
 * When identifiers are per project, a task in project WEB is numbered WEB-130
 * from that project's own counter. The previous identifier stays in
 * task_identifiers so a move can still be looked up.
 */
export function projectIdentifierSql(
  ctx: BlockSqlContext,
  n: TaskNames,
): string {
  if (
    ctx.text("identifiers", "tenant") !== "project" ||
    !ctx.has("items", "project") ||
    !ctx.hasTable("projects")
  ) {
    return "";
  }

  const { t, c } = n;
  const w = (column: string): string => c("items", column);
  const p = (column: string): string => c("projects", column);

  return `
  if nullif(create_task.attrs ->> 'projectId', '') is not null then
    declare
      v_key text;
    begin
      select x.${p("key")} into v_key from ${t("projects")} x
      where x.${p("id")} = (create_task.attrs ->> 'projectId')::uuid
        and x.${p("tenant")} = create_task.tenant;
      if v_key is null then
        ${fail("TASK_PROJECT_NOT_FOUND", "project not found", "P0002")}
      end if;
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_task.tenant::text || ':' || v_key, 0));
      select coalesce(max(x.${w("number")}), 0) + 1 into v_seq from ${t("items")} x
      where x.${w("tenant")} = create_task.tenant and x.${w("project")} = (create_task.attrs ->> 'projectId')::uuid;
      v_identifier := v_key || '-' || v_seq::text;
    end;
  end if;`;
}

/** Milestone, triage, clone, cadence and snapshot functions. */
export function projectWorkFunctions(
  ctx: BlockSqlContext,
  n: TaskNames,
): string {
  const { fn, t, c } = n;
  const w = (column: string): string => c("items", column);

  const can = (tenant: string): string =>
    `${n.service} or ${ctx.scope.can(tenant, n.manage)}`;

  const parts: string[] = [];

  if (ctx.hasTable("milestones") && ctx.hasTable("projects")) {
    const m = (column: string): string => c("milestones", column);
    const type = sqlString(entityType(ctx.resolved, "project_milestone"));

    const recorded = (event: string): string =>
      ctx.record({
        type: event,
        payload: `jsonb_build_object('organizationId', v_row.${m("tenant")}, 'projectId', v_row.${m("project")}, 'milestoneId', v_row.${m("id")}, 'subjectType', ${type}, 'subjectId', v_row.${m("id")}::text, 'key', v_project.${c("projects", "key")}, 'name', v_row.${m("name")}${actorPayload(n)})`,
        subject: `'milestones/' || v_row.${m("id")}::text`,
        tenant: `v_row.${m("tenant")}::text`,
        row: "v_row",
        audit: false,
      });

    parts.push(`
create or replace function ${fn("save_milestone")}(tenant ${ctx.idType}, id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("milestones")};
  v_project ${t("projects")};
begin
  select * into v_project from ${t("projects")} p
  where p.${c("projects", "id")} = (save_milestone.attrs ->> 'projectId')::uuid
    and p.${c("projects", "tenant")} = save_milestone.tenant;
  if v_project.${c("projects", "id")} is null then
    ${fail("TASK_PROJECT_NOT_FOUND", "project not found", "P0002")}
  end if;
  if not (${can(`v_project.${c("projects", "tenant")}`)}) then
    ${fail("TASK_FORBIDDEN", "not allowed to change the project", "42501")}
  end if;
  if save_milestone.id is null then
    insert into ${t("milestones")} (${m("tenant")}, ${m("project")}, ${m("name")}, ${m("description")}, ${m("targetOn")}, ${m("rank")})
    values (save_milestone.tenant, v_project.${c("projects", "id")}, save_milestone.attrs ->> 'name', nullif(save_milestone.attrs ->> 'description', ''), nullif(save_milestone.attrs ->> 'targetOn', '')::date, coalesce(nullif(save_milestone.attrs ->> 'rank', ''), 'V'))
    returning * into v_row;
    ${recorded("project_milestone.created")}
  else
    update ${t("milestones")} x set
      ${m("name")} = coalesce(save_milestone.attrs ->> 'name', x.${m("name")}),
      ${m("description")} = case when save_milestone.attrs ? 'description' then nullif(save_milestone.attrs ->> 'description', '') else x.${m("description")} end,
      ${m("targetOn")} = case when save_milestone.attrs ? 'targetOn' then nullif(save_milestone.attrs ->> 'targetOn', '')::date else x.${m("targetOn")} end,
      ${m("rank")} = coalesce(nullif(save_milestone.attrs ->> 'rank', ''), x.${m("rank")}),
      ${m("updatedAt")} = now()
    where x.${m("id")} = save_milestone.id and x.${m("tenant")} = save_milestone.tenant
    returning * into v_row;
    if v_row.${m("id")} is null then
      ${fail("TASK_MILESTONE_NOT_FOUND", "milestone not found", "P0002")}
    end if;
    ${recorded("project_milestone.updated")}
  end if;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("save_milestone")}(${ctx.idType}, uuid, jsonb)`)}

create or replace function ${fn("page_milestones")}(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.${m("rank")}, x.${m("id")}), '[]'::jsonb)
  from ${t("milestones")} x where x.${m("project")} = page_milestones.project
$$;
${userGrant(`${fn("page_milestones")}(uuid)`)}

create or replace function ${fn("remove_milestone")}(milestone uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("milestones")};
begin
  delete from ${t("milestones")} x
  where x.${m("id")} = remove_milestone.milestone and (${can(`x.${m("tenant")}`)})
  returning * into v_row;
  if v_row.${m("id")} is null then
    return false;
  end if;
  ${recorded("project_milestone.deleted")}
  return true;
end;
$$;
${userGrant(`${fn("remove_milestone")}(uuid)`)}`);
  }

  if (ctx.has("projects", "health")) {
    parts.push(`
create or replace function ${fn("set_project_health")}(project uuid, health text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("projects")};
begin
  if set_project_health.health is not null and set_project_health.health not in ('on_track', 'at_risk', 'off_track') then
    ${fail("TASK_PROJECT_INVALID", "health must be on_track, at_risk or off_track", "22023")}
  end if;
  update ${t("projects")} x set
    ${c("projects", "health")} = set_project_health.health,
    ${c("projects", "healthAt")} = now(),
    ${c("projects", "updatedAt")} = now()
  where x.${c("projects", "id")} = set_project_health.project
  returning * into v_row;
  return v_row.${c("projects", "id")} is not null;
end;
$$;
${userGrant(`${fn("set_project_health")}(uuid, text)`)}`);
  }

  parts.push(`
create or replace function ${fn("accept_task")}(task uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  update ${t("items")} x set ${w("state")} = 'backlog', ${w("updatedAt")} = now()
  where x.${w("id")} = accept_task.task and x.${w("state")} = 'triage' and (${can(`x.${w("tenant")}`)})
  returning * into v_row;
  if v_row.${w("id")} is null then
    ${fail("TASK_NOT_FOUND", "no triage item to accept", "P0002")}
  end if;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("accept_task")}(uuid)`)}

create or replace function ${fn("decline_task")}(task uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  update ${t("items")} x set ${w("state")} = 'canceled', ${w("closeReason")} = 'not_planned', ${w("closedAt")} = now(), ${w("updatedAt")} = now()
  where x.${w("id")} = decline_task.task and (${can(`x.${w("tenant")}`)})
  returning * into v_row;
  if v_row.${w("id")} is null then
    ${fail("TASK_NOT_FOUND", "no such work item", "P0002")}
  end if;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("decline_task")}(uuid)`)}

create or replace function ${fn("snooze_task")}(task uuid, until timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  update ${t("items")} x set ${ctx.has("items", "snoozedUntil") ? `${w("snoozedUntil")} = snooze_task.until, ` : ""}${w("updatedAt")} = now()
  where x.${w("id")} = snooze_task.task and (${can(`x.${w("tenant")}`)})
  returning * into v_row;
  if v_row.${w("id")} is null then
    ${fail("TASK_NOT_FOUND", "no such work item", "P0002")}
  end if;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("snooze_task")}(uuid, timestamptz)`)}`);

  if (ctx.has("items", "duplicateOf")) {
    const notifications = ctx.installed("notifications")
      ? ctx.of("notifications")
      : undefined;

    const copy =
      notifications?.hasTable("subscriptions") === true
        ? `
  insert into ${notifications.table("subscriptions")} (${notifications.col("subscriptions", "user")}, ${notifications.col("subscriptions", "subjectType")}, ${notifications.col("subscriptions", "subjectId")}, ${notifications.col("subscriptions", "level")}${notifications.has("subscriptions", "tenant") ? `, ${notifications.col("subscriptions", "tenant")}` : ""})
  select s.${notifications.col("subscriptions", "user")}, s.${notifications.col("subscriptions", "subjectType")}, v_original.${w("id")}::text, s.${notifications.col("subscriptions", "level")}${notifications.has("subscriptions", "tenant") ? `, s.${notifications.col("subscriptions", "tenant")}` : ""}
  from ${notifications.table("subscriptions")} s
  where s.${notifications.col("subscriptions", "subjectType")} = ${sqlString(n.type)}
    and s.${notifications.col("subscriptions", "subjectId")} = v_row.${w("id")}::text
    and not exists (
      select 1 from ${notifications.table("subscriptions")} have
      where have.${notifications.col("subscriptions", "user")} = s.${notifications.col("subscriptions", "user")}
        and have.${notifications.col("subscriptions", "subjectType")} = s.${notifications.col("subscriptions", "subjectType")}
        and have.${notifications.col("subscriptions", "subjectId")} = v_original.${w("id")}::text
    );`
        : "";

    parts.push(`
create or replace function ${fn("mark_duplicate")}(task uuid, original uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_original ${t("items")};
begin
  select * into v_original from ${t("items")} x where x.${w("id")} = mark_duplicate.original;
  select * into v_row from ${t("items")} x where x.${w("id")} = mark_duplicate.task and x.${w("tenant")} = v_original.${w("tenant")};
  if v_row.${w("id")} is null or v_original.${w("id")} is null then
    ${fail("TASK_NOT_FOUND", "no such work item", "P0002")}
  end if;
  if not (${can(`v_row.${w("tenant")}`)}) then
    ${fail("TASK_FORBIDDEN", "not allowed to change work items", "42501")}
  end if;
  update ${t("items")} x set ${w("state")} = 'canceled', ${w("closeReason")} = 'duplicate', ${w("duplicateOf")} = v_original.${w("id")}, ${w("closedAt")} = now(), ${w("updatedAt")} = now()
  where x.${w("id")} = v_row.${w("id")}
  returning * into v_row;${copy}
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("mark_duplicate")}(uuid, uuid)`)}`);
  }

  if (ctx.hasTable("projects")) {
    parts.push(`
create or replace function ${fn("clone_project")}(source uuid, shift_days integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src ${t("projects")};
  v_row ${t("projects")};
  v_task record;
  v_copy jsonb;
begin
  select * into v_src from ${t("projects")} x where x.${c("projects", "id")} = clone_project.source;
  if v_src.${c("projects", "id")} is null then
    ${fail("TASK_PROJECT_NOT_FOUND", "project not found", "P0002")}
  end if;
  if not (${can(`v_src.${c("projects", "tenant")}`)}) then
    ${fail("TASK_FORBIDDEN", "not allowed to change the project", "42501")}
  end if;
  insert into ${t("projects")} (${c("projects", "tenant")}, ${c("projects", "key")}, ${c("projects", "name")}, ${c("projects", "status")}${ctx.has("projects", "description") ? `, ${c("projects", "description")}` : ""}${ctx.has("projects", "template") ? `, ${c("projects", "template")}` : ""}${ctx.has("projects", "startOn") ? `, ${c("projects", "startOn")}` : ""}${ctx.has("projects", "targetOn") ? `, ${c("projects", "targetOn")}` : ""})
  values (v_src.${c("projects", "tenant")}, v_src.${c("projects", "key")} || 'C', v_src.${c("projects", "name")}, 'planned'${ctx.has("projects", "description") ? `, v_src.${c("projects", "description")}` : ""}${ctx.has("projects", "template") ? ", false" : ""}${ctx.has("projects", "startOn") ? `, v_src.${c("projects", "startOn")} + clone_project.shift_days` : ""}${ctx.has("projects", "targetOn") ? `, v_src.${c("projects", "targetOn")} + clone_project.shift_days` : ""})
  returning * into v_row;
  ${
    ctx.hasTable("milestones")
      ? `insert into ${t("milestones")} (${c("milestones", "tenant")}, ${c("milestones", "project")}, ${c("milestones", "name")}, ${c("milestones", "description")}, ${c("milestones", "targetOn")}, ${c("milestones", "rank")})
  select m.${c("milestones", "tenant")}, v_row.${c("projects", "id")}, m.${c("milestones", "name")}, m.${c("milestones", "description")}, m.${c("milestones", "targetOn")} + clone_project.shift_days, m.${c("milestones", "rank")}
  from ${t("milestones")} m where m.${c("milestones", "project")} = v_src.${c("projects", "id")};`
      : ""
  }
  ${
    ctx.has("items", "project")
      ? `for v_task in select i.${w("id")} from ${t("items")} i where i.${w("project")} = v_src.${c("projects", "id")} and i.${w("parent")} is null loop
    v_copy := ${fn("clone_task")}(v_task.${w("id")}, jsonb_build_object('projectId', v_row.${c("projects", "id")}));
  end loop;
  ${
    ctx.has("items", "startAt")
      ? `update ${t("items")} i set ${w("startAt")} = i.${w("startAt")} + make_interval(days => clone_project.shift_days) where i.${w("project")} = v_row.${c("projects", "id")} and clone_project.shift_days <> 0;`
      : ""
  }
  ${
    ctx.has("items", "endAt")
      ? `update ${t("items")} i set ${w("endAt")} = i.${w("endAt")} + make_interval(days => clone_project.shift_days) where i.${w("project")} = v_row.${c("projects", "id")} and clone_project.shift_days <> 0;`
      : ""
  }`
      : ""
  }
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("clone_project")}(uuid, integer)`)}`);
  }

  if (ctx.hasTable("cadences") && ctx.hasTable("iterations")) {
    parts.push(`
create or replace function ${fn("save_iteration_cadence")}(tenant ${ctx.idType}, team uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("cadences")};
begin
  if not (${can("save_iteration_cadence.tenant")}) then
    ${fail("TASK_FORBIDDEN", "not allowed to change cycles", "42501")}
  end if;
  insert into ${t("cadences")} (${c("cadences", "tenant")}, ${c("cadences", "team")}, ${c("cadences", "weeks")}, ${c("cadences", "cooldownDays")}, ${c("cadences", "startWeekday")}, ${c("cadences", "upcoming")}, ${c("cadences", "rollover")})
  values (save_iteration_cadence.tenant, save_iteration_cadence.team,
    coalesce((save_iteration_cadence.attrs ->> 'weeks')::smallint, 2),
    coalesce((save_iteration_cadence.attrs ->> 'cooldownDays')::smallint, 0),
    coalesce((save_iteration_cadence.attrs ->> 'startWeekday')::smallint, 1),
    coalesce((save_iteration_cadence.attrs ->> 'upcoming')::smallint, 2),
    coalesce((save_iteration_cadence.attrs ->> 'rollover')::boolean, true))
  on conflict (${c("cadences", "tenant")}, ${c("cadences", "team")}) do update set
    ${c("cadences", "weeks")} = excluded.${c("cadences", "weeks")},
    ${c("cadences", "cooldownDays")} = excluded.${c("cadences", "cooldownDays")},
    ${c("cadences", "startWeekday")} = excluded.${c("cadences", "startWeekday")},
    ${c("cadences", "upcoming")} = excluded.${c("cadences", "upcoming")},
    ${c("cadences", "rollover")} = excluded.${c("cadences", "rollover")}
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${fn("save_iteration_cadence")}(${ctx.idType}, uuid, jsonb)`)}

create or replace function ${fn("iteration_burnup")}(iteration uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'day', s.${c("snapshots", "day")},
    'scope', s.${c("snapshots", "scope")},
    'started', s.${c("snapshots", "started")},
    'completed', s.${c("snapshots", "completed")}
  ) order by s.${c("snapshots", "day")}), '[]'::jsonb)
  from ${t("snapshots")} s where s.${c("snapshots", "iteration")} = iteration_burnup.iteration
$$;
${userGrant(`${fn("iteration_burnup")}(uuid)`)}

create or replace function ${fn("roll_iterations")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_iteration ${t("iterations")};
begin
  ${
    ctx.has("items", "snoozedUntil")
      ? `update ${t("items")} x set ${w("snoozedUntil")} = null, ${w("updatedAt")} = now()
  where x.${w("snoozedUntil")} is not null and x.${w("snoozedUntil")} <= now();`
      : ""
  }
  ${
    ctx.has("iterations", "team") && ctx.has("iterations", "number")
      ? `insert into ${t("iterations")} (${c("iterations", "tenant")}, ${c("iterations", "team")}, ${c("iterations", "name")}, ${c("iterations", "number")}, ${c("iterations", "startsOn")}, ${c("iterations", "endsOn")})
  select cadence.${c("cadences", "tenant")}, cadence.${c("cadences", "team")},
    'Cycle ' || (coalesce(last.number, 0) + 1),
    coalesce(last.number, 0) + 1,
    coalesce(last.ends_on, current_date) + cadence.${c("cadences", "cooldownDays")} + 1,
    coalesce(last.ends_on, current_date) + cadence.${c("cadences", "cooldownDays")} + cadence.${c("cadences", "weeks")} * 7
  from ${t("cadences")} cadence
  left join lateral (
    select i.${c("iterations", "number")} as number, i.${c("iterations", "endsOn")} as ends_on
    from ${t("iterations")} i
    where i.${c("iterations", "team")} = cadence.${c("cadences", "team")}
    order by i.${c("iterations", "endsOn")} desc
    limit 1
  ) last on true
  where (
    select count(*) from ${t("iterations")} i
    where i.${c("iterations", "team")} = cadence.${c("cadences", "team")}
      and i.${c("iterations", "startsOn")} > current_date
  ) < cadence.${c("cadences", "upcoming")};`
      : ""
  }
  insert into ${t("snapshots")} (${c("snapshots", "tenant")}, ${c("snapshots", "iteration")}, ${c("snapshots", "day")}, ${c("snapshots", "scope")}, ${c("snapshots", "started")}, ${c("snapshots", "completed")})
  select i.${c("iterations", "tenant")}, i.${c("iterations", "id")}, current_date,
    count(t.*)::integer,
    count(t.*) filter (where t.${w("state")} = 'started')::integer,
    count(t.*) filter (where t.${w("state")} = 'completed')::integer
  from ${t("iterations")} i
  left join ${t("items")} t on t.${w("iteration")} = i.${c("iterations", "id")}
  where current_date between i.${c("iterations", "startsOn")} and i.${c("iterations", "endsOn")}
  group by i.${c("iterations", "tenant")}, i.${c("iterations", "id")}
  on conflict (${c("snapshots", "iteration")}, ${c("snapshots", "day")}) do update set
    ${c("snapshots", "scope")} = excluded.${c("snapshots", "scope")},
    ${c("snapshots", "started")} = excluded.${c("snapshots", "started")},
    ${c("snapshots", "completed")} = excluded.${c("snapshots", "completed")};
  get diagnostics v_count = row_count;
  ${
    ctx.has("iterations", "team") && ctx.has("items", "iteration")
      ? `update ${t("items")} task set ${w("iteration")} = nxt.${c("iterations", "id")}
  from ${t("iterations")} ended
  join ${t("cadences")} cadence on cadence.${c("cadences", "team")} = ended.${c("iterations", "team")} and cadence.${c("cadences", "rollover")}
  join lateral (
    select i.${c("iterations", "id")} from ${t("iterations")} i
    where i.${c("iterations", "team")} = ended.${c("iterations", "team")} and i.${c("iterations", "startsOn")} > ended.${c("iterations", "endsOn")}
    order by i.${c("iterations", "startsOn")}
    limit 1
  ) nxt on true
  where ended.${c("iterations", "endsOn")} = current_date - 1
    and task.${w("iteration")} = ended.${c("iterations", "id")}
    and task.${w("state")} not in ('completed', 'canceled');`
      : ""
  }
  for v_iteration in select * from ${t("iterations")} i where i.${c("iterations", "startsOn")} = current_date loop
    ${ctx.record({
      type: "iteration.started",
      payload: `jsonb_build_object('organizationId', v_iteration.${c("iterations", "tenant")}, 'iterationId', v_iteration.${c("iterations", "id")}, 'subjectType', ${sqlString(entityType(ctx.resolved, "iteration"))}, 'subjectId', v_iteration.${c("iterations", "id")}::text, 'name', v_iteration.${c("iterations", "name")}${actorPayload(n)})`,
      subject: `'iterations/' || v_iteration.${c("iterations", "id")}::text`,
      tenant: `v_iteration.${c("iterations", "tenant")}::text`,
      row: "v_iteration",
      audit: false,
    })}
  end loop;
  for v_iteration in select * from ${t("iterations")} i where i.${c("iterations", "endsOn")} = current_date - 1 loop
    ${ctx.record({
      type: "iteration.completed",
      payload: `jsonb_build_object('organizationId', v_iteration.${c("iterations", "tenant")}, 'iterationId', v_iteration.${c("iterations", "id")}, 'subjectType', ${sqlString(entityType(ctx.resolved, "iteration"))}, 'subjectId', v_iteration.${c("iterations", "id")}::text, 'name', v_iteration.${c("iterations", "name")}${actorPayload(n)})`,
      subject: `'iterations/' || v_iteration.${c("iterations", "id")}::text`,
      tenant: `v_iteration.${c("iterations", "tenant")}::text`,
      row: "v_iteration",
      audit: false,
    })}
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("roll_iterations")}()`)}`);
  }

  if (ctx.hasTable("identifiers")) {
    parts.push(`
create or replace function ${fn("resolve_task_identifier")}(tenant ${ctx.idType}, identifier text)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (select x.${w("id")} from ${t("items")} x where x.${w("tenant")} = resolve_task_identifier.tenant and x.${w("identifier")} = resolve_task_identifier.identifier),
    (select k.${c("identifiers", "item")} from ${t("identifiers")} k where k.${c("identifiers", "tenant")} = resolve_task_identifier.tenant and k.${c("identifiers", "identifier")} = resolve_task_identifier.identifier)
  )
$$;
${userGrant(`${fn("resolve_task_identifier")}(${ctx.idType}, text)`)}`);
  }

  return parts.join("\n");
}
