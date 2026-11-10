SET local check_function_bodies = off;

create or replace function "better_supabase"."status_state"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
  v_next text[];
  v_life "better_supabase"."subject_lifecycles"%rowtype;
  v_order text[];
begin
  case status_state.subject_type
    when 'work_item' then
      select s."state"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."work_items" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_next := case v_status when 'triage' then '{backlog,unstarted,started,completed,canceled}'::text[] when 'backlog' then '{triage,unstarted,started,completed,canceled}'::text[] when 'unstarted' then '{triage,backlog,started,completed,canceled}'::text[] when 'started' then '{triage,backlog,unstarted,completed,canceled}'::text[] when 'completed' then '{triage,backlog,unstarted,started,canceled}'::text[] when 'canceled' then '{triage,backlog,unstarted,started,completed}'::text[] else '{}'::text[] end;
      v_step := array_position('{triage,backlog,unstarted,started,completed}'::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'work_item', 'subjectId', status_state.subject_id,
        'status', v_status, 'next', to_jsonb(v_next), 'order', to_jsonb('{triage,backlog,unstarted,started,completed}'::text[]), 'step', v_step, 'steps', 5, 'progress', case when v_step is null then null when 5 = 1 then 1 else round((v_step - 1)::numeric / 4, 4) end,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    when 'change_request' then
      select s."status"::text, s."organization_id"::text into v_status, v_tenant
      from "public"."change_requests" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      select * into v_life from "better_supabase"."subject_lifecycles" x
      where x."subject_type" = 'change_request' and x."subject_id" = status_state.subject_id;
      v_paused := v_life."paused_at" is not null and (v_life."pause_expires_at" is null or v_life."pause_expires_at" > now());
      v_order := coalesce(array(select jsonb_array_elements_text("better_supabase"."lifecycle_graph"(v_life."workflow_version_id") -> 'order')), '{}'::text[]);
      v_next := coalesce(array(select jsonb_array_elements_text("better_supabase"."lifecycle_graph"(v_life."workflow_version_id") -> 'transitions' -> v_status)), '{}'::text[]);
      if v_paused then
        v_next := '{}'::text[];
      end if;
      v_step := array_position(v_order, v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'change_request', 'subjectId', status_state.subject_id,
        'status', v_status, 'next', to_jsonb(v_next), 'order', to_jsonb(v_order), 'step', v_step, 'steps', nullif(cardinality(v_order), 0), 'progress', case when v_step is null then null when cardinality(v_order) = 1 then 1 else round((v_step - 1)::numeric / (cardinality(v_order) - 1), 4) end,
        'version', v_life."version", 'flags', to_jsonb(coalesce(v_life."flags", '{}')),
        'paused', v_paused, 'pausedAt', case when v_paused then v_life."paused_at" end,
        'pausedUntil', case when v_paused then v_life."pause_expires_at" end,
        'pauseReason', case when v_paused then v_life."pause_reason" end, 'workflow', 'change-requests', 'workflowVersionId', v_life."workflow_version_id");
    when 'drive_node' then
      select s."document_status"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."drive_nodes" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_next := case when v_status is null then '{draft}'::text[] else case v_status when 'draft' then '{in_review}'::text[] when 'in_review' then '{draft,effective}'::text[] when 'effective' then '{obsolete}'::text[] else '{}'::text[] end end;
      v_step := array_position(null::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'drive_node', 'subjectId', status_state.subject_id,
        'status', v_status, 'next', to_jsonb(v_next), 'order', to_jsonb(null::text[]), 'step', v_step, 'steps', null, 'progress', null,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$$;
