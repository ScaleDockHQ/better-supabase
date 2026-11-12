-- Adds the work.setState bulk action: bulk_row dispatches it to public.work_bulk_state,
-- and the action list of bulk_apply and start_bulk names it. EX-921.
CREATE OR REPLACE FUNCTION better_supabase.bulk_apply (
  tenant       uuid,
  subject_type text,
  ids          text[],
  action       text,
  args         jsonb,
  atomic       boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_chunk text[] := coalesce(bulk_apply.ids, array[]::text[]);
  v_id text;
  v_ok integer := 0;
  v_failed integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
  v_state text;
begin
  if not coalesce(better_supabase.can('tenant', bulk_apply.tenant, 'bulk_actions.run'), false) then
    raise exception 'not allowed to run bulk actions' using errcode = '42501', hint = 'BULK_FORBIDDEN';
  end if;
  if not (bulk_apply.action = any (array['tags.set', 'stateMachine.transition', 'relations.link', 'trash.trash', 'collections.add', 'work.setState'])) then
    raise exception 'unknown bulk action' using errcode = '22023', hint = 'BULK_ACTION_UNKNOWN';
  end if;
  if cardinality(v_chunk) > 500 then
    raise exception 'more than 500 rows; start a background run' using errcode = '22023', hint = 'BULK_TOO_MANY';
  end if;
  foreach v_id in array v_chunk loop
    begin
      perform "better_supabase"."bulk_row"(bulk_apply.tenant, bulk_apply.subject_type, v_id, bulk_apply.action, coalesce(bulk_apply.args, '{}'::jsonb));
      v_ok := v_ok + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', true));
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint, v_state = returned_sqlstate;
      if coalesce(bulk_apply.atomic, false) then
        raise exception using message = v_message, hint = coalesce(v_hint, ''), errcode = v_state;
      end if;
      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', false, 'error', jsonb_build_object('code', nullif(v_hint, ''), 'message', v_message, 'sqlstate', v_state)));
    end;
  end loop;
  return jsonb_build_object('total', cardinality(v_chunk), 'succeeded', v_ok, 'failed', v_failed, 'results', v_results);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bulk_row (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  args         jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_tag uuid;
begin
  case bulk_row.action
    when 'tags.set' then
      for v_tag in select value::uuid from jsonb_array_elements_text(coalesce(bulk_row.args -> 'add', '[]'::jsonb)) loop
        perform "better_supabase"."tag"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, v_tag);
      end loop;
      for v_tag in select value::uuid from jsonb_array_elements_text(coalesce(bulk_row.args -> 'remove', '[]'::jsonb)) loop
        perform "better_supabase"."untag"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, v_tag);
      end loop;
    when 'stateMachine.transition' then
      perform "better_supabase"."transition"(bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'to', bulk_row.args ->> 'reason', bulk_row.args -> 'actor');
    when 'relations.link' then
      perform "better_supabase"."link"(bulk_row.tenant, bulk_row.args ->> 'kind', bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'targetType', bulk_row.args ->> 'targetId', bulk_row.args -> 'data');
    when 'trash.trash' then
      perform "better_supabase"."trash"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id);
    when 'collections.add' then
      perform "better_supabase"."add_collection_entries"((bulk_row.args ->> 'collectionId')::uuid, array[bulk_row.subject_id], bulk_row.subject_type);
    when 'work.setState' then
      perform "public"."work_bulk_state"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, bulk_row.args);
    else
      raise exception 'unknown bulk action' using errcode = '22023', hint = 'BULK_ACTION_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_bulk (
  tenant       uuid,
  subject_type text,
  ids          text[],
  action       text,
  args         jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_total integer := cardinality(coalesce(start_bulk.ids, array[]::text[]));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', start_bulk.tenant, 'bulk_actions.run'), false) then
    raise exception 'not allowed to run bulk actions' using errcode = '42501', hint = 'BULK_FORBIDDEN';
  end if;
  if not (start_bulk.action = any (array['tags.set', 'stateMachine.transition', 'relations.link', 'trash.trash', 'collections.add', 'work.setState'])) then
    raise exception 'unknown bulk action' using errcode = '22023', hint = 'BULK_ACTION_UNKNOWN';
  end if;
  if v_total > 100000 then
    raise exception 'a background run takes at most 100000 rows' using errcode = '22023', hint = 'BULK_TOO_MANY';
  end if;
  
  insert into "better_supabase"."bulk_runs" ("tenant_id", "subject_type", "action", "args", "ids", "created_by")
  values (start_bulk.tenant, start_bulk.subject_type, start_bulk.action, coalesce(start_bulk.args, '{}'::jsonb), coalesce(start_bulk.ids, array[]::text[]), auth.uid())
  returning "id" into v_id;
  perform "better_supabase"."enqueue_job"(queue => 'bulk-actions', payload => jsonb_build_object('run', v_id), dedupe_key => 'bulk:' || v_id::text, dedupe_running => false);
  return jsonb_build_object('id', v_id, 'total', v_total, 'topic', 'bulk:' || v_id::text);
end;
$function$;

CREATE OR REPLACE FUNCTION public.work_bulk_state (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  args         jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_to text := work_bulk_state.args ->> 'to';
begin
  if not better_supabase.actor_may_write() then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (
    (auth.role() = 'service_role')
    or coalesce(better_supabase.can('tenant', work_bulk_state.tenant, 'tasks.write'), false)
  ) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_to is null then
    raise exception 'args.to is required' using errcode = '22023', hint = 'BULK_STATE_ARGS';
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(work_bulk_state.args ->> 'reason', ''), true);
  update better_supabase.work_items x
  set state = v_to
  where x.id = work_bulk_state.subject_id::uuid
    and x.tenant_id = work_bulk_state.tenant
    and x.archived_at is null;
  if not found then
    perform set_config('better_supabase.transition_reason', '', true);
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  perform set_config('better_supabase.transition_reason', '', true);
end;
$function$;

REVOKE ALL ON FUNCTION "public"."work_bulk_state"(uuid, text, text, jsonb) FROM PUBLIC, "anon";

COMMENT ON FUNCTION "public"."work_bulk_state"(uuid, text, text, jsonb) IS 'Bulk action work.setState: sets a work item''s state after the tasks.write check.';


GRANT EXECUTE ON FUNCTION "public"."work_bulk_state"(uuid, text, text, jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."work_bulk_state"(uuid, text, text, jsonb) TO "service_role";
