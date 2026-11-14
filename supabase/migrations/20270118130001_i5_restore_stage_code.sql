SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.restore_pipeline_stage (
  stage uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_pipeline_archived timestamptz;
  v_stage uuid := restore_pipeline_stage.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", y."archived_at"
    into v_tenant, v_pipeline, v_pipeline_archived
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = restore_pipeline_stage.stage and x."archived_at" is not null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  if v_pipeline_archived is not null then
    raise exception 'the pipeline of this stage is archived; restore the pipeline first' using errcode = '55000', hint = 'PIPELINE_NOT_FOUND';
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = null, "updated_at" = now() where x."id" = restore_pipeline_stage.stage;
  perform "better_supabase".emit_event('pipeline_stage.restored', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.restored',
    category => 'configuration',
    target_type => 'pipeline_stage',
    record_id => v_stage::text,
    summary => 'restored a pipeline stage',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage)
  );
  return true;
end;
$function$;
