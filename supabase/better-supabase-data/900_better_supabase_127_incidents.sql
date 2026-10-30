-- better-supabase module: incidents
-- @bsb-block-data incidents
-- @bsb-hash sha256:1eeb15f697702a059d52e1b9121e1ab623141c33018f267de7f4ee198fc98c45
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Copies each postmortem's action_items into tasks once. The caller is the service role.
do $$
declare
  v_post record;
  v_item jsonb;
  v_title text;
  v_assignee uuid;
  v_due timestamptz;
  v_position integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    return;
  end if;
  for v_post in
    select x."id" as id, x."action_items" as items
    from "better_supabase"."incident_postmortems" x
    where jsonb_typeof(x."action_items") = 'array'
      and jsonb_array_length(x."action_items") > 0
      and not exists (select 1 from "better_supabase"."incident_postmortem_actions" y where y."postmortem_id" = x."id")
    order by x."id"
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
        perform "better_supabase"."add_incident_postmortem_action"(v_post.id, v_title, v_assignee, v_due);
      exception when others then
        if v_assignee is null and v_due is null then
          raise;
        end if;
        perform "better_supabase"."add_incident_postmortem_action"(v_post.id, v_title, null, null);
      end;
    end loop;
  end loop;
end;
$$;

insert into better_supabase.blocks (name, version, mode)
values ('incidents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
