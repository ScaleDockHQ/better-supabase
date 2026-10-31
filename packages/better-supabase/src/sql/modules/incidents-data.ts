import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlUpgrade } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";

const COLUMN = "action_items";

/**
 * Copies each postmortem's `action_items` into tasks through
 * `add_incident_postmortem_action`. A postmortem that already has linked
 * actions is skipped. An item is a string or an object with a `title` (or
 * `text`, `name`, `description`), an optional `assigneeId` and an optional
 * `dueAt`; a value that doesn't parse is dropped from the task, never the
 * item.
 */
function copyActionItems(ctx: BlockSqlContext): string {
  const postmortems = ctx.table("postmortems");
  const actions = ctx.table("actions");
  const pm = (column: string): string => ctx.col("postmortems", column);
  const a = (column: string): string => ctx.col("actions", column);
  const add = ctx.fn("add_incident_postmortem_action");

  return `do $$
declare
  v_post record;
  v_item jsonb;
  v_title text;
  v_assignee uuid;
  v_due timestamptz;
  v_position integer;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'the incidents upgrade copies action_items into tasks as the service role or the migration role';
  end if;
  for v_post in
    select x.${pm("id")} as id, x.${COLUMN} as items
    from ${postmortems} x
    where jsonb_typeof(x.${COLUMN}) = 'array'
      and jsonb_array_length(x.${COLUMN}) > 0
      and not exists (select 1 from ${actions} y where y.${a("postmortem")} = x.${pm("id")})
    order by x.${pm("id")}
  loop
    v_position := 0;
    for v_item in select e.value from jsonb_array_elements(v_post.items) e loop
      v_position := v_position + 1;
      v_title := case jsonb_typeof(v_item)
        when 'string' then v_item #>> '{}'
        when 'object' then coalesce(v_item ->> 'title', v_item ->> 'text', v_item ->> 'name', v_item ->> 'description')
        else v_item::text
      end;
      v_title := left(nullif(btrim(coalesce(v_title, '')), ''), 500);
      if v_title is null then
        v_title := 'Action item ' || v_position;
      end if;
      v_assignee := null;
      v_due := null;
      if jsonb_typeof(v_item) = 'object' then
        begin
          v_assignee := (v_item ->> 'assigneeId')::uuid;
        exception when others then
          v_assignee := null;
        end;
        begin
          v_due := (v_item ->> 'dueAt')::timestamptz;
        exception when others then
          v_due := null;
        end;
      end if;
      begin
        perform ${add}(v_post.id, v_title, v_assignee, v_due);
      exception when others then
        if v_assignee is null and v_due is null then
          raise;
        end if;
        perform ${add}(v_post.id, v_title, null, null);
      end;
    end loop;
  end loop;
end;
$$;`;
}

/**
 * The step to version 3: postmortem `action_items` become tasks and the column
 * goes (ADR 0149). It runs before the schema diff. When the module has no
 * `add_incident_postmortem_action` yet (a 0.46 database) and the column holds
 * items, it stops and says what to do, because the diff would otherwise drop
 * them.
 */
export const ACTION_ITEMS_TO_TASKS: BlockSqlUpgrade = {
  from: 2,
  description:
    "Postmortem action_items are copied into tasks through add_incident_postmortem_action and the column is dropped. Without the tasks block the items are only dropped when the column is empty.",
  sql: (ctx) => {
    if (ctx.mode === "custom") {
      return "";
    }

    const table = ctx.table("postmortems");
    const withTasks = ctx.installed("tasks") && ctx.hasTable("actions");

    const regclass = `to_regclass(${sqlString(table)})`;
    const exists = `exists (select 1 from pg_attribute where attrelid = ${regclass} and attname = ${sqlString(COLUMN)} and not attisdropped)`;

    const holds = `exists (select 1 from ${table} x where jsonb_typeof(x.${COLUMN}) = 'array' and jsonb_array_length(x.${COLUMN}) > 0)`;

    const ready = `to_regprocedure(${sqlString(`${ctx.fn("add_incident_postmortem_action")}(uuid, text, uuid, timestamptz)`)}) is not null`;

    const move = withTasks
      ? `    if ${holds} then
      if not (${ready}) then
        raise exception 'incident_postmortems.action_items still holds action items and the tasks actions are not installed yet: write them down or clear the column, then run upgrade again';
      end if;
      execute ${sqlString(copyActionItems(ctx))};
    end if;`
      : `    if ${holds} then
      raise exception 'incident_postmortems.action_items still holds action items and the tasks block is not installed: install tasks to keep them as tasks, or clear the column, then run upgrade again';
    end if;`;

    return `-- Postmortem action items are tasks now (ADR 0149): copy what is left and drop the column.
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
