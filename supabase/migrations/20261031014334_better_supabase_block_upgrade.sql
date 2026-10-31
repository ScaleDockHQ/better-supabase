-- better-supabase upgrade: steps that run before the schema diff.

-- incidents: version 2 to 3. Postmortem action_items are copied into tasks through add_incident_postmortem_action and the column is dropped. Without the tasks block the items are only dropped when the column is empty.
-- Postmortem action items are tasks now (ADR 0149): copy what is left and drop the column.
do $upgrade$
begin
  if to_regclass('"better_supabase"."incident_postmortems"') is not null and exists (select 1 from pg_attribute where attrelid = to_regclass('"better_supabase"."incident_postmortems"') and attname = 'action_items' and not attisdropped) then
    if exists (select 1 from "better_supabase"."incident_postmortems" x where jsonb_typeof(x.action_items) = 'array' and jsonb_array_length(x.action_items) > 0) then
      if not (to_regprocedure('"better_supabase"."add_incident_postmortem_action"(uuid, text, uuid, timestamptz)') is not null) then
        raise exception 'incident_postmortems.action_items still holds action items and the tasks actions are not installed yet: write them down or clear the column, then run upgrade again';
      end if;
      execute 'do $$
declare
  v_post record;
  v_item jsonb;
  v_title text;
  v_assignee uuid;
  v_due timestamptz;
  v_position integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> ''role'', ''''), session_user::text) in (''service_role'', ''postgres'', ''supabase_admin'')) then
    raise exception ''the incidents upgrade copies action_items into tasks as the service role or the migration role'';
  end if;
  for v_post in
    select x."id" as id, x.action_items as items
    from "better_supabase"."incident_postmortems" x
    where jsonb_typeof(x.action_items) = ''array''
      and jsonb_array_length(x.action_items) > 0
      and not exists (select 1 from "better_supabase"."incident_postmortem_actions" y where y."postmortem_id" = x."id")
    order by x."id"
  loop
    v_position := 0;
    for v_item in select e.value from jsonb_array_elements(v_post.items) e loop
      v_position := v_position + 1;
      v_title := case jsonb_typeof(v_item)
        when ''string'' then v_item #>> ''{}''
        when ''object'' then coalesce(v_item ->> ''title'', v_item ->> ''text'', v_item ->> ''name'', v_item ->> ''description'')
        else v_item::text
      end;
      v_title := left(nullif(btrim(coalesce(v_title, '''')), ''''), 500);
      if v_title is null then
        v_title := ''Action item '' || v_position;
      end if;
      v_assignee := null;
      v_due := null;
      if jsonb_typeof(v_item) = ''object'' then
        begin
          v_assignee := (v_item ->> ''assigneeId'')::uuid;
        exception when others then
          v_assignee := null;
        end;
        begin
          v_due := (v_item ->> ''dueAt'')::timestamptz;
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
$$;';
    end if;
    alter table "better_supabase"."incident_postmortems" drop column action_items;
  end if;
end;
$upgrade$;
