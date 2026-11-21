import type { BlockSqlContext } from "../context.ts";
import type { TaskNames } from "./tasks-functions.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, userGrant } from "../shared.ts";
import { load, taskRecord } from "./tasks-coordination-shared.ts";

/** Ordering: appending on create, move and move many with an inline rebalance. */
export function orderSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  h: { readonly row: (alias: string) => string },
): string {
  const { fn, t } = n;
  const w = (column: string): string => n.c("items", column);

  if (!ctx.installed("rank")) {
    return "";
  }

  const rank = ctx.of("rank");

  const lane = (alias: string): string =>
    `${alias}.${w("tenant")} = v_row.${w("tenant")} and ${alias}.${w("stage")} is not distinct from v_stage and ${alias}.${w("archivedAt")} is null and ${alias}.${w("id")} <> v_row.${w("id")}`;

  return `
-- Puts a task at a place in a lane (a stage's column): after afterId, before
-- beforeId, or at the end. Moving to another stage with stageId changes its
-- stage. When the neighbours share a rank key the lane is rebalanced and the
-- move retried once.
create or replace function ${fn("move_task")}(task uuid, stage uuid default null, before uuid default null, after uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_stage uuid;
  v_prev text;
  v_next text;
  v_rank text;
  v_tries integer := 0;
begin
  ${load(ctx, n, "move_task", n.write)}
  if v_row.${w("closedAt")} is not null and move_task.stage is null then
    ${fail("TASK_CLOSED", "a closed task keeps its place", "55000")}
  end if;
  v_stage := coalesce(move_task.stage, v_row.${w("stage")});
  loop
    v_prev := null;
    v_next := null;
    if move_task.after is not null then
      select x.${w("rank")} into v_prev from ${t("items")} x where x.${w("id")} = move_task.after and ${lane("x")};
      if not found then
        ${fail("TASK_MOVE_INVALID", "the task to place after isn't in that lane", "22023")}
      end if;
    end if;
    if move_task.before is not null then
      select x.${w("rank")} into v_next from ${t("items")} x where x.${w("id")} = move_task.before and ${lane("x")};
      if not found then
        ${fail("TASK_MOVE_INVALID", "the task to place before isn't in that lane", "22023")}
      end if;
    end if;
    if move_task.after is not null and move_task.before is null then
      select min(x.${w("rank")} collate "C") into v_next from ${t("items")} x where ${lane("x")} and x.${w("rank")} collate "C" > v_prev collate "C";
    elsif move_task.before is not null and move_task.after is null then
      select max(x.${w("rank")} collate "C") into v_prev from ${t("items")} x where ${lane("x")} and x.${w("rank")} collate "C" < v_next collate "C";
    elsif move_task.before is null and move_task.after is null then
      select max(x.${w("rank")} collate "C") into v_prev from ${t("items")} x where ${lane("x")};
    end if;
    exit when v_prev is null or v_next is null or v_prev collate "C" < v_next collate "C";
    if v_tries > 0 then
      ${fail("TASK_RANK_CONFLICT", "the neighbours share a rank key", "22023")}
    end if;
    v_tries := v_tries + 1;
    with ordered as (
      select x.${w("id")} as id, row_number() over (order by x.${w("rank")} collate "C", x.${w("number")}, x.${w("id")}) as nth, count(*) over () as total
      from ${t("items")} x
      where x.${w("tenant")} = v_row.${w("tenant")} and x.${w("stage")} is not distinct from v_stage and x.${w("archivedAt")} is null)
    update ${t("items")} y set ${w("rank")} = ${rank.fn("rank_key")}(o.nth, o.total) from ordered o where y.${w("id")} = o.id;
  end loop;
  v_rank := ${rank.fn("rank_between")}(v_prev, v_next);
  update ${t("items")} x set ${w("stage")} = v_stage, ${w("rank")} = v_rank where x.${w("id")} = v_row.${w("id")};
  select * into v_row from ${t("items")} x where x.${w("id")} = v_row.${w("id")};
  ${taskRecord(ctx, n, "task.updated", "v_row", ", 'fields', jsonb_build_array('stageId', 'rank')")}
  return (select ${h.row("x")} from ${t("items")} x where x.${w("id")} = v_row.${w("id")});
end;
$$;
${userGrant(`${fn("move_task")}(uuid, uuid, uuid, uuid)`)}

-- Applies a list of { ${n.e("taskId")}, stageId, beforeId, afterId } moves, each on
-- its own. Returns { accepted, rejected } like update_tasks.
create or replace function ${fn("move_tasks")}(moves jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_move jsonb;
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
begin
  if not (better_supabase.actor_may_write()) then
    ${fail("ACTOR_READ_ONLY", "This session is read-only")}
  end if;
  if jsonb_typeof(coalesce(move_tasks.moves, '[]')) <> 'array' then
    ${fail("TASK_CHANGES_INVALID", "moves must be a list", "22023")}
  end if;
  for v_move in select value from jsonb_array_elements(move_tasks.moves) loop
    begin
      perform ${fn("move_task")}((v_move ->> ${sqlString(n.e("taskId"))})::uuid, (v_move ->> 'stageId')::uuid, (v_move ->> 'beforeId')::uuid, (v_move ->> 'afterId')::uuid);
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object(${sqlString(n.e("taskId"))}, v_move ->> ${sqlString(n.e("taskId"))}));
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object(${sqlString(n.e("taskId"))}, v_move ->> ${sqlString(n.e("taskId"))}, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
${userGrant(`${fn("move_tasks")}(jsonb)`)}
`;
}

/** Time in stage, and the realtime topic of a tenant's tasks. */
export function liveSql(ctx: BlockSqlContext, n: TaskNames): string {
  const { fn, t } = n;
  const w = (column: string): string => n.c("items", column);
  const type = sqlString(n.type);
  const hist = ctx.of("pipelines");
  const hc = (column: string): string => hist.col("history", column);

  const changed = (
    name: string,
    table: string,
    tenant: string,
    task: string,
  ): string => `
create or replace function ${fn(name)}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text;
  v_task uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant := old.${tenant}::text;
    v_task := old.${task};
  else
    v_tenant := new.${tenant}::text;
    v_task := new.${task};
  end if;
  ${ctx.broadcast("'tasks:' || v_tenant", "'changed'", "jsonb_build_object('id', v_task, 'change', lower(tg_op), 'table', tg_table_name)")}
  return null;
end;
$$;
revoke execute on function ${fn(name)}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger(name)} on ${table};
create trigger ${ctx.trigger(name)}
  after insert or update or delete on ${table}
  for each row execute function ${fn(name)}();`;

  return `
-- The stages a task has been in, oldest first, with the seconds spent in each.
-- The current stage is open: exitedAt is null and seconds run to now.
create or replace function ${fn("task_stage_times")}(task uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'stageId', h.${hc("toStage")},${hist.has("history", "stageName") ? ` 'stageName', h.${hc("stageName")},` : ""}${hist.has("history", "category") ? ` 'category', h.${hc("category")}::text,` : ""}
    'enteredAt', h.${hc("enteredAt")}, 'exitedAt', h.${hc("exitedAt")},
    'seconds', round(extract(epoch from (coalesce(h.${hc("exitedAt")}, now()) - h.${hc("enteredAt")})))::bigint
  ) order by h.${hc("enteredAt")}), '[]'::jsonb)
  from ${hist.table("history")} h
  join ${t("items")} x on x.${w("id")}::text = h.${hc("subjectId")} and x.${w("tenant")} = h.${hc("tenant")}
  where x.${w("id")} = task_stage_times.task and h.${hc("subjectType")} = ${type}
    and (${n.service} or ${ctx.scope.can(`x.${w("tenant")}`, n.read)}));
end;
$$;
${userGrant(`${fn("task_stage_times")}(uuid)`)}

-- Tells tasks:<tenant> that a task or its claim changed. The payload carries
-- ids only; readers fetch the rows through the API.${changed("tasks_changed", t("items"), w("tenant"), w("id"))}${ctx.hasTable("claims") ? changed("task_claims_changed", t("claims"), n.c("claims", "tenant"), n.c("claims", "task")) : ""}

-- Members join tasks:{tenant}.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        ${renderPolicy(
          makePolicy({
            table: "realtime.messages",
            name: ctx.trigger("tasks_receive"),
            command: "select",
            roles: ["authenticated"],
            using: `realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'tasks:%'
        and substr((select realtime.topic()), 7) in (select x::text from ${ctx.scope.ids(n.read)} x)`,
          }),
          { target: "realtime.messages" },
        )}
  end if;
end;
$do$;
`;
}
