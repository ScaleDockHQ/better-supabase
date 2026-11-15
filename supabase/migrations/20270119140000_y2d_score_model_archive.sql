SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_score_model"(uuid);

DROP FUNCTION "api"."list_score_models"(uuid, text);

DROP FUNCTION "better_supabase"."delete_score_model"(uuid);

DROP FUNCTION "better_supabase"."list_score_models"(uuid, text);

ALTER TABLE "better_supabase"."score_models"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_score_model (
  model_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_score_model"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_score_models (
  tenant           uuid,
  subject_type     text    DEFAULT NULL::text,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_score_models"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.purge_score_model (
  model_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_score_model"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_score_model (
  model_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_score_model"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_score_model (
  model_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = archive_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('score_model.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.archived',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'archived score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.compute_score (
  tenant       uuid,
  model_key    text,
  subject_type text,
  subject_id   text,
  subject      jsonb,
  time_zone    text  DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_model "better_supabase"."score_models";
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current "better_supabase"."scores";
  v_row "better_supabase"."scores";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', compute_score.tenant, 'scores.compute'), false)) then
    raise exception 'not allowed to compute scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  select * into v_model from "better_supabase"."score_models" x where x."tenant_id" = compute_score.tenant and x."key" = compute_score.model_key;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if v_model."archived_at" is not null then
    raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
  end if;
  if not v_model."enabled" then
    raise exception 'the score model is turned off' using errcode = '55000', hint = 'SCORES_MODEL_DISABLED';
  end if;
  if compute_score.subject_type is distinct from v_model."subject_type" then
    raise exception 'the score model scores another subject type' using errcode = '22023', hint = 'SCORES_SUBJECT_MISMATCH';
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    raise exception 'subject must be an object and subject_id set' using errcode = '22023', hint = 'SCORES_SUBJECT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_model."subject_type");
  for v_entry in select x.value from jsonb_array_elements(v_model."rules") x loop
    v_matched := coalesce("better_supabase"."rule_matches"(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model."metrics") x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := coalesce((select y."score" from "better_supabase"."reaction_scores" y where y."tenant_id" = compute_score.tenant and y."subject_type" = compute_score.subject_type and y."subject_id" = compute_score.subject_id), 0);
    else
      v_value := "better_supabase"."rule_numeric"(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model."bands") x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from "better_supabase"."scores" x
  where x."model_id" = v_model."id" and x."subject_type" = compute_score.subject_type
    and x."subject_id" = compute_score.subject_id and x."is_current"
  for update;
  if found and v_current."score" = v_total and v_current."band" is not distinct from v_band
    and v_current."model_version" = v_model."version" and v_current."breakdown" = v_breakdown then
    return jsonb_build_object('id', v_current."id", 'organizationId', v_current."tenant_id", 'modelId', v_current."model_id", 'modelKey', v_model."key", 'modelVersion', v_current."model_version", 'subjectType', v_current."subject_type", 'subjectId', v_current."subject_id", 'score', v_current."score", 'band', v_current."band", 'breakdown', v_current."breakdown", 'current', v_current."is_current", 'computedAt', v_current."computed_at") || jsonb_build_object('changed', false);
  end if;
  update "better_supabase"."scores" x set "is_current" = false where x."id" = v_current."id";
  insert into "better_supabase"."scores" ("tenant_id", "model_id", "model_version", "subject_type", "subject_id", "score", "band", "breakdown", "computed_at")
  values (compute_score.tenant, v_model."id", v_model."version", compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  perform "better_supabase".emit_event('score.changed', jsonb_build_object('organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'previousScore', v_current."score", 'band', v_row."band", 'previousBand', v_current."band"), 'scores/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'modelVersion', v_row."model_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'band', v_row."band", 'breakdown', v_row."breakdown", 'current', v_row."is_current", 'computedAt', v_row."computed_at") || jsonb_build_object('changed', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_score_model (
  model_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."score_models";
begin
  select * into v_row from "better_supabase"."score_models" x where x."id" = get_score_model.model_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at") || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y."version", 'rules', y."rules", 'metrics', y."metrics", 'bands', y."bands", 'savedBy', y."saved_by", 'savedAt', y."saved_at") order by y."version" desc)
    from "better_supabase"."score_model_versions" y where y."model_id" = v_row."id"
  ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_score_models (
  tenant           uuid,
  subject_type     text    DEFAULT NULL::text,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."key")
    from "better_supabase"."score_models" x
    where x."tenant_id" = list_score_models.tenant
      and (list_score_models.subject_type is null or x."subject_type" = list_score_models.subject_type)
      and (coalesce(list_score_models.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_score_model (
  model_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = purge_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to purge score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  delete from "better_supabase"."score_models" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('score_model.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.purged',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'purged score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_score_model (
  model_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = restore_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('score_model.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.restored',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'restored score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_score_model (
  tenant uuid,
  model  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."tenant_id" = save_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if v_old."archived_at" is not null then
      raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field', 'votes')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field or votes), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."tenant_id" = save_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (save_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'archivedAt', v_old."archived_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    perform "better_supabase".emit_event('score_model.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.created',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  else
    perform "better_supabase".emit_event('score_model.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.updated',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_scores (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', subject_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'modelId', x."model_id", 'modelKey', y."key", 'modelVersion', x."model_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'score', x."score", 'band', x."band", 'breakdown', x."breakdown", 'current', x."is_current", 'computedAt', x."computed_at") || jsonb_build_object('modelName', y."name") order by y."key")
    from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
    where x."tenant_id" = subject_scores.tenant and x."subject_type" = subject_scores.subject_type
      and x."subject_id" = subject_scores.subject_id and x."is_current"
      and y."archived_at" is null
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.top_scores (
  tenant    uuid,
  model_key text,
  band      text    DEFAULT NULL::text,
  min_score numeric DEFAULT NULL::numeric,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', top_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', top_scores.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."score" desc, z."computed_at" desc)
    from (
      select x.*
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = top_scores.tenant and y."key" = top_scores.model_key and x."is_current"
      and y."archived_at" is null
        and (top_scores.band is null or x."band" = top_scores.band)
        and (top_scores.min_score is null or x."score" >= top_scores.min_score)
      order by x."score" desc, x."computed_at" desc
      limit least(greatest(coalesce(top_scores.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_score_models"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_score_models"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_score_models"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_score_models"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_score_model"(uuid) TO "authenticated", "service_role";
