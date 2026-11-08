import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlUpgrade } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { recordingsOn } from "./activities-recordings.ts";

const COLUMN = "action_items";

/**
 * Copies each note's `action_items` into tasks through the tasks block's
 * `create_task` and links them in the note actions table. A note whose activity
 * already has linked tasks is skipped. An item is an object with a `text` (or
 * `title`), an optional `ownerId` and an optional `dueAt`; an owner or due date
 * that doesn't parse is dropped from the task, never the item.
 */
function copyActionItems(ctx: BlockSqlContext): string {
  const notes = ctx.table("notes");
  const actions = ctx.table("actions");
  const n = (column: string): string => ctx.col("notes", column);
  const a = (column: string): string => ctx.col("actions", column);
  const tasks = ctx.of("tasks");

  return `do $$
declare
  v_note record;
  v_item jsonb;
  v_title text;
  v_owner uuid;
  v_due timestamptz;
  v_task uuid;
  v_position integer;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'the activities upgrade copies action_items into tasks as the service role or the migration role';
  end if;
  for v_note in
    select x.${n("activity")} as id, x.${n("tenant")} as tenant, x.${COLUMN} as items
    from ${notes} x
    where jsonb_typeof(x.${COLUMN}) = 'array'
      and jsonb_array_length(x.${COLUMN}) > 0
      and not exists (select 1 from ${actions} y where y.${a("activity")} = x.${n("activity")})
    order by x.${n("activity")}
  loop
    v_position := 0;
    for v_item in select e.value from jsonb_array_elements(v_note.items) e loop
      v_position := v_position + 1;
      v_title := left(nullif(btrim(coalesce(v_item ->> 'text', v_item ->> 'title', '')), ''), 500);
      if v_title is null then
        v_title := 'Action item ' || v_position;
      end if;
      v_owner := null;
      v_due := null;
      begin
        v_owner := (v_item ->> 'ownerId')::uuid;
      exception when others then
        v_owner := null;
      end;
      begin
        v_due := (v_item ->> 'dueAt')::timestamptz;
      exception when others then
        v_due := null;
      end;
      v_task := (${tasks.fn("create_task")}(
        v_note.tenant,
        jsonb_strip_nulls(jsonb_build_object('title', v_title, 'dueAt', v_due)),
        case when v_owner is null then '{}'::uuid[] else array[v_owner] end
      ) ->> 'id')::uuid;
      insert into ${actions} (${a("tenant")}, ${a("activity")}, ${a("task")})
      values (v_note.tenant, v_note.id, v_task);
    end loop;
  end loop;
end;
$$;`;
}

/**
 * The step to version 4: the `action_items` of an activity's notes become tasks
 * and the column goes (ADR 0149 did the same for postmortems). It runs before
 * the schema diff. When the column holds items and the tasks block can't take
 * them, it stops and says what to do, because the diff would otherwise drop
 * them.
 */
export const NOTE_ACTION_ITEMS_TO_TASKS: BlockSqlUpgrade = {
  from: 3,
  description:
    "Activity notes' action_items are copied into tasks through create_task and the column is dropped. Without the tasks block the items are only dropped when the column is empty.",
  sql: (ctx) => {
    if (ctx.mode === "custom" || !recordingsOn(ctx)) {
      return "";
    }

    const table = ctx.table("notes");

    const withTasks =
      ctx.installed("tasks") && ctx.of("tasks").mode !== "custom";

    const regclass = `to_regclass(${sqlString(table)})`;
    const exists = `exists (select 1 from pg_attribute where attrelid = ${regclass} and attname = ${sqlString(COLUMN)} and not attisdropped)`;

    const holds = `exists (select 1 from ${table} x where jsonb_typeof(x.${COLUMN}) = 'array' and jsonb_array_length(x.${COLUMN}) > 0)`;

    const tasks = withTasks ? ctx.of("tasks") : undefined;
    const a = (column: string): string => ctx.col("actions", column);

    // The link table is created here so the items have somewhere to go before
    // the schema diff runs; the diff adds its indexes, policy and grants.
    const link =
      tasks === undefined
        ? ""
        : `create table if not exists ${ctx.table("actions")} (
        ${a("id")} uuid primary key default gen_random_uuid(),
        ${a("tenant")} ${ctx.idType} not null,
        ${a("activity")} uuid not null references ${ctx.table("activities")} (${ctx.col("activities", "id")}) on delete cascade,
        ${a("task")} uuid not null references ${tasks.table("items")} (${tasks.col("items", "id")}) on delete cascade,${ctx.has("actions", "createdAt") ? `\n        ${a("createdAt")} timestamptz not null default now(),` : ""}
        unique (${a("activity")}, ${a("task")})
      );`;

    const move =
      tasks === undefined
        ? `    if ${holds} then
      raise exception 'activity notes still hold action items and the tasks block is not installed: install tasks to keep them as tasks, or clear the column, then run upgrade again';
    end if;`
        : `    if ${holds} then
      if to_regclass(${sqlString(tasks.table("items"))}) is null then
        raise exception 'activity notes still hold action items and the tasks table is not installed yet: run upgrade again once the tasks block is applied, or clear the column';
      end if;
      ${link}
      execute ${sqlString(copyActionItems(ctx))};
    end if;`;

    return `-- Activity note action items are tasks now: copy what is left and drop the column.
do $upgrade$
begin
  if ${regclass} is not null and ${exists} then
${move}
    alter table ${table} drop column ${COLUMN};
  end if;
end;
$upgrade$;`;
  },
};
