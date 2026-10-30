import type { BlockSqlContext } from "../context.ts";

import { SERVICE_CALLER } from "../shared.ts";

/**
 * The data step that copies the `action_items` of postmortems written before
 * the tasks block into tasks, through `add_incident_postmortem_action`. It
 * leaves the column as it is and skips a postmortem that already has linked
 * actions, so running it again adds nothing. An item is a string or an object
 * with a `title` (or `text`, `name`, `description`), an optional `assigneeId`
 * and an optional `dueAt`; a value that doesn't parse is dropped from the task,
 * never the item.
 */
export function copyActionItems(ctx: BlockSqlContext): string {
  if (
    ctx.mode === "custom" ||
    !ctx.installed("tasks") ||
    !ctx.has("postmortems", "actionItems") ||
    !ctx.hasTable("actions")
  ) {
    return "";
  }

  const postmortems = ctx.table("postmortems");
  const actions = ctx.table("actions");
  const pm = (column: string): string => ctx.col("postmortems", column);
  const a = (column: string): string => ctx.col("actions", column);
  const add = ctx.fn("add_incident_postmortem_action");

  return `-- Copies each postmortem's action_items into tasks once. The caller is the service role.
do $$
declare
  v_post record;
  v_item jsonb;
  v_title text;
  v_assignee uuid;
  v_due timestamptz;
  v_position integer;
begin
  if not (${SERVICE_CALLER}) then
    return;
  end if;
  for v_post in
    select x.${pm("id")} as id, x.${pm("actionItems")} as items
    from ${postmortems} x
    where jsonb_typeof(x.${pm("actionItems")}) = 'array'
      and jsonb_array_length(x.${pm("actionItems")}) > 0
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
