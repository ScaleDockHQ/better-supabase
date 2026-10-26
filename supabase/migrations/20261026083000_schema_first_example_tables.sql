SET local check_function_bodies = off;

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
  if not coalesce(better_supabase.can('tenant', bulk_apply.tenant, 'bulk.run'), false) then
    raise exception 'not allowed to run bulk actions' using errcode = '42501', hint = 'BULK_FORBIDDEN';
  end if;
  if not (bulk_apply.action = any (array['tags.set', 'stateMachine.transition', 'relations.link', 'trash.trash'])) then
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
      perform "better_supabase"."transition"(bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'to', bulk_row.args ->> 'reason');
    when 'relations.link' then
      perform "better_supabase"."link"(bulk_row.tenant, bulk_row.args ->> 'kind', bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'targetType', bulk_row.args ->> 'targetId', bulk_row.args -> 'data');
    when 'trash.trash' then
      perform "better_supabase"."trash"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id);
    else
      raise exception 'unknown bulk action' using errcode = '22023', hint = 'BULK_ACTION_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_reindex (
  subject_type text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer := 0;
  v_id text;
begin
  if search_reindex.subject_type is null or search_reindex.subject_type = 'message' then
    for v_id in select s."id"::text from "better_supabase"."messages" s loop
      if "better_supabase"."search_refresh"('message', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'channel' then
    for v_id in select s."id"::text from "better_supabase"."channels" s loop
      if "better_supabase"."search_refresh"('channel', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'company' then
    for v_id in select s."id"::text from "better_supabase"."companies" s loop
      if "better_supabase"."search_refresh"('company', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'person' then
    for v_id in select s."id"::text from "better_supabase"."people" s loop
      if "better_supabase"."search_refresh"('person', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'deal' then
    for v_id in select s."id"::text from "better_supabase"."deals" s loop
      if "better_supabase"."search_refresh"('deal', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'course' then
    for v_id in select s."id"::text from "better_supabase"."courses" s loop
      if "better_supabase"."search_refresh"('course', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'post' then
    for v_id in select s."id"::text from "better_supabase"."posts" s loop
      if "better_supabase"."search_refresh"('post', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'engagement' then
    for v_id in select s."id"::text from "better_supabase"."engagements" s loop
      if "better_supabase"."search_refresh"('engagement', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'work_item' then
    for v_id in select s."id"::text from "better_supabase"."work_items" s loop
      if "better_supabase"."search_refresh"('work_item', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'employee' then
    for v_id in select s."id"::text from "better_supabase"."employees" s loop
      if "better_supabase"."search_refresh"('employee', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'product' then
    for v_id in select s."id"::text from "better_supabase"."products" s loop
      if "better_supabase"."search_refresh"('product', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'product_variant' then
    for v_id in select s."id"::text from "better_supabase"."product_variants" s loop
      if "better_supabase"."search_refresh"('product_variant', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'calendar_event' then
    for v_id in select s."id"::text from "better_supabase"."calendar_events" s loop
      if "better_supabase"."search_refresh"('calendar_event', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'content_entry' then
    for v_id in select s."id"::text from "better_supabase"."content_entries" s loop
      if "better_supabase"."search_refresh"('content_entry', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'customer' then
    for v_id in select s."id"::text from "public"."customers" s loop
      if "better_supabase"."search_refresh"('customer', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'drive_node' then
    for v_id in select s."id"::text from "better_supabase"."drive_nodes" s loop
      if "better_supabase"."search_refresh"('drive_node', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'project' then
    for v_id in select s."id"::text from "public"."projects" s loop
      if "better_supabase"."search_refresh"('project', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  return v_count;
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
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', start_bulk.tenant, 'bulk.run'), false) then
    raise exception 'not allowed to run bulk actions' using errcode = '42501', hint = 'BULK_FORBIDDEN';
  end if;
  if not (start_bulk.action = any (array['tags.set', 'stateMachine.transition', 'relations.link', 'trash.trash'])) then
    raise exception 'unknown bulk action' using errcode = '22023', hint = 'BULK_ACTION_UNKNOWN';
  end if;
  if v_total > 100000 then
    raise exception 'a background run takes at most 100000 rows' using errcode = '22023', hint = 'BULK_TOO_MANY';
  end if;
  
  insert into "better_supabase"."bulk_runs" ("tenant_id", "subject_type", "action", "args", "ids", "created_by")
  values (start_bulk.tenant, start_bulk.subject_type, start_bulk.action, coalesce(start_bulk.args, '{}'::jsonb), coalesce(start_bulk.ids, array[]::text[]), auth.uid())
  returning "id" into v_id;
  perform "better_supabase"."enqueue_job"(queue => 'bulk', payload => jsonb_build_object('run', v_id), dedupe_key => 'bulk:' || v_id::text, dedupe_running => false);
  return jsonb_build_object('id', v_id, 'total', v_total, 'topic', 'bulk:' || v_id::text);
end;
$function$;

COMMENT ON TABLE "public"."client_notes" IS '@bsb encrypted diagnosis=text birth_date=date';

COMMENT ON TABLE "public"."projects" IS '@bsb subject type=project id-type=uuid tenant=organization_id title=name url=/projects/{id} deleted-at=deleted_at search versions=name,budget_minor,currency; server internal_notes';

COMMENT ON TABLE "public"."tasks" IS '@bsb subject type=task id-type=uuid tenant=organization_id title=title url=/projects/{project_id} rank=rank rank-group=status; events include="status, project_id"';
