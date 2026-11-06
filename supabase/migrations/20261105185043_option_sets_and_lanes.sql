SET local check_function_bodies = off;

DROP FUNCTION "api"."archive_pipeline_stage"(uuid);

DROP FUNCTION "api"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text);

DROP FUNCTION "better_supabase"."archive_pipeline_stage"(uuid);

DROP FUNCTION "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text);

ALTER TABLE "better_supabase"."pipeline_stages"
  ADD COLUMN "icon" text;

CREATE OR REPLACE FUNCTION api.archive_pipeline_stage (
  stage   uuid,
  move_to uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_pipeline_stage"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_pipeline_stage (
  pipeline           uuid,
  stage              uuid,
  key                text,
  name               text,
  category           text,
  probability        integer,
  rotting_after_days integer,
  wip_limit          integer,
  color              text,
  icon               text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_pipeline_stage"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_pipeline_stage (
  stage   uuid,
  move_to uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
  v_to uuid := archive_pipeline_stage.move_to;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", x."outcome", y."subject_type"
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = archive_pipeline_stage.stage and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  case v_subject_type
    when 'deal' then
      perform 1 from "better_supabase"."deals" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'work_item' then
      perform 1 from "better_supabase"."work_items" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'maintenance_request' then
      perform 1 from "better_supabase"."maintenance_requests" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'application' then
      perform 1 from "better_supabase"."applications" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'case' then
      perform 1 from "better_supabase"."cases" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    else
      v_used := false;
  end case;
  if archive_pipeline_stage.move_to is not null then
    if archive_pipeline_stage.move_to = archive_pipeline_stage.stage or not exists (
      select 1 from "better_supabase"."pipeline_stages" x
      where x."id" = archive_pipeline_stage.move_to and x."pipeline_id" = v_pipeline and x."archived_at" is null
    ) then
      raise exception 'move_to must be another active stage of the same pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_REPLACEMENT_INVALID';
    end if;
  end if;
  if v_used and archive_pipeline_stage.move_to is null then
    raise exception 'records are in this stage; move them first or name a stage to move them to' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "better_supabase"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  if v_used then
    -- The stage trigger lets this one change through even where the allowed
    -- stage changes would not.
    perform set_config('bsb.lane_move', v_stage::text || ':' || v_to::text, true);
    case v_subject_type
    when 'deal' then
      update "better_supabase"."deals" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    when 'work_item' then
      update "better_supabase"."work_items" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    when 'maintenance_request' then
      update "better_supabase"."maintenance_requests" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    when 'application' then
      update "better_supabase"."applications" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    when 'case' then
      update "better_supabase"."cases" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    else
      null;
  end case;
    perform set_config('bsb.lane_move', '', true);
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  perform "better_supabase".emit_event('pipeline_stage.archived', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.archived',
    category => 'configuration',
    target_type => 'pipeline_stage',
    record_id => v_stage::text,
    summary => 'archived a pipeline stage',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_application()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'application', new."job_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'application'
    and p."scope_id" is not distinct from new."job_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'application' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'application', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'application', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'application',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_case()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'case', new."kind_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'case'
    and p."scope_id" is not distinct from new."kind_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'case' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'case', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'case', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'case',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_deal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'deal', null);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'deal'
    and p."scope_id" is not distinct from null;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'deal' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'deal', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, new."amount", new."currency", auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'deal', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'deal',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_user_id" is not null and (tg_op = 'INSERT' or new."owner_user_id" is distinct from old."owner_user_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_maintenance_request()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'maintenance_request', new."team_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'maintenance_request'
    and p."scope_id" is not distinct from new."team_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'maintenance_request', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'maintenance_request' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'maintenance_request', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'maintenance_request',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'maintenance_request', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'work_item', new."team_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'work_item'
    and p."scope_id" is not distinct from new."team_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'work_item', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'work_item' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_user_id")
    values (new."tenant_id", 'work_item', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'work_item',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'work_item', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pipeline_board (
  subject_type text,
  pipeline     uuid,
  owner        uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case pipeline_board.subject_type
    when 'deal' then
      return (
        with rows as (
          select r."stage_id" as stage_id, r."currency"::text as currency, r."amount"::bigint as amount,
            r."amount" * coalesce(r."probability", st."probability", 0) / 100.0 as weighted
          from "better_supabase"."deals" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and r."archived_at" is null and (pipeline_board.owner is null or r."owner_user_id" = pipeline_board.owner)
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'work_item' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."work_items" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and r."archived_at" is null
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'maintenance_request' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."maintenance_requests" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'application' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."applications" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and (pipeline_board.owner is null or r."owner_user_id" = pipeline_board.owner)
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'case' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."cases" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and r."archived_at" is null
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_pipeline_stage (
  pipeline           uuid,
  stage              uuid,
  key                text,
  name               text,
  category           text,
  probability        integer,
  rotting_after_days integer,
  wip_limit          integer,
  color              text,
  icon               text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = save_pipeline_stage.pipeline and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  case v_subject_type
    when 'deal' then
      v_outcome := case save_pipeline_stage.category
      when 'open' then 'open'
      when 'won' then 'success'
      when 'lost' then 'failure'
    end;
    when 'work_item' then
      v_outcome := case save_pipeline_stage.category
      when 'triage' then 'open'
      when 'backlog' then 'open'
      when 'unstarted' then 'open'
      when 'started' then 'open'
      when 'completed' then 'success'
      when 'canceled' then 'failure'
    end;
    when 'maintenance_request' then
      v_outcome := case save_pipeline_stage.category
      when 'triage' then 'open'
      when 'backlog' then 'open'
      when 'unstarted' then 'open'
      when 'started' then 'open'
      when 'completed' then 'success'
      when 'canceled' then 'failure'
    end;
    when 'application' then
      v_outcome := case save_pipeline_stage.category
      when 'active' then 'open'
      when 'hired' then 'success'
      when 'rejected' then 'failure'
      when 'withdrawn' then 'failure'
    end;
    when 'case' then
      v_outcome := case save_pipeline_stage.category
      when 'open' then 'open'
      when 'closed' then 'success'
      when 'canceled' then 'failure'
    end;
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
  if v_outcome is null then
    raise exception 'this subject type has no such category' using errcode = '22023', hint = 'PIPELINE_CATEGORY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline_stage.pipeline, save_pipeline_stage.stage, save_pipeline_stage.key, save_pipeline_stage.category;
    end if;
  end;
  begin
    if v_stage is null then
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "icon", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome, save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color, save_pipeline_stage.icon,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline)) then (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from "better_supabase"."pipeline_stages" x where x."id" = v_stage and x."outcome" <> v_outcome) then
        case v_subject_type
    when 'deal' then
      perform 1 from "better_supabase"."deals" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'work_item' then
      perform 1 from "better_supabase"."work_items" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'maintenance_request' then
      perform 1 from "better_supabase"."maintenance_requests" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'application' then
      perform 1 from "better_supabase"."applications" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'case' then
      perform 1 from "better_supabase"."cases" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    else
      v_used := false;
  end case;
        if v_used then
          raise exception 'records are in this stage; its outcome can''t change' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
        end if;
      end if;
      update "better_supabase"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = save_pipeline_stage.category, "outcome" = v_outcome, "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "icon" = save_pipeline_stage.icon, "updated_at" = now()
      where x."id" = v_stage and x."pipeline_id" = save_pipeline_stage.pipeline;
      if not found then
        raise exception 'stage not found' using errcode = 'P0002', hint = 'PIPELINE_STAGE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another stage of this pipeline has this key' using errcode = '23505', hint = 'PIPELINE_STAGE_KEY_TAKEN';
  end;
  if save_pipeline_stage.stage is null then
    perform "better_supabase".emit_event('pipeline_stage.created', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.created',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'created stage ' || save_pipeline_stage.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category)
  );
  else
    perform "better_supabase".emit_event('pipeline_stage.updated', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.updated',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'updated stage ' || save_pipeline_stage.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category)
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_stage;
    end if;
  end;
  return (select to_jsonb(x) from "better_supabase"."pipeline_stages" x where x."id" = v_stage);
end;
$function$;

ALTER TABLE "better_supabase"."pipeline_stages"
  ADD CONSTRAINT "pipeline_stages_icon_check" CHECK ((length(icon) <= 100));

REVOKE ALL ON FUNCTION "api"."archive_pipeline_stage"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_pipeline_stage"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_pipeline_stage"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_pipeline_stage"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_pipeline_stage"(uuid, uuid, text, text, text, integer, integer, integer, text, text) TO "authenticated", "service_role";
