SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_care_plans (
  plan_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_care_plans"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_versions (
  version_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_versions"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_run_steps_for (
  runs    uuid[],
  per_run integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_run_steps_for"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_applications_for_jobs (
  jobs  uuid[],
  state text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_applications_for_jobs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.templates_get_many (
  template_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."templates_get_many"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_care_plans (
  plan_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg("better_supabase"."care_plan_json"(x."id") order by array_position(get_care_plans.plan_ids, x."id")), '[]'::jsonb)
  from "better_supabase"."care_plans" x
  where x."id" = any (get_care_plans.plan_ids)
    and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_versions (
  version_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return (
  with wanted as (
    select x.* from "better_supabase"."versions" x where x."id" = any (get_versions.version_ids)
  ),
  allowed as materialized (
    select q."tenant_id", q."subject_type", q."subject_id"
    from (select distinct w."tenant_id", w."subject_type", w."subject_id" from wanted w) q
    where coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', q."tenant_id", 'versions.read'), false) and case q."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (q."subject_id")::uuid and s."organization_id" = q."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (q."subject_id")::uuid and s."organization_id" = q."tenant_id") and coalesce(better_supabase.can('tenant', q."tenant_id", 'customers.read'), false)
    else false
  end and q."subject_type" <> 'ai_document')
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'number', v."number", 'label', v."label", 'source', v."source", 'frozen', v."frozen", 'contentHash', v."content_hash", 'storagePath', v."storage_path", 'fileSha256', v."file_hash", 'hashVersion', v."hash_version", 'subjectType', v."subject_type", 'subjectId', v."subject_id", 'createdBy', v."created_by", 'createdAt', v."created_at") || jsonb_build_object('content', v."content") order by array_position(get_versions.version_ids, v."id")), '[]'::jsonb)
  from wanted v
  join allowed a on a."tenant_id" = v."tenant_id" and a."subject_type" = v."subject_type" and a."subject_id" = v."subject_id"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_run_steps_for (
  runs    uuid[],
  per_run integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with readable_chats as materialized (
    select c.chat
    from (
      select distinct x."chat_id" as chat from "better_supabase"."ai_runs" x where x."id" = any (list_ai_run_steps_for.runs)
    ) c
    where "better_supabase"."ai_chat_can_read"(c.chat)
  ),
  ranked as (
    select x.*, row_number() over (partition by x."run_id" order by x."started_at", x."id") as step_rank
    from "better_supabase"."ai_run_steps" x
    join "better_supabase"."ai_runs" r on r."id" = x."run_id"
    where x."run_id" = any (list_ai_run_steps_for.runs)
      and r."chat_id" in (select chat from readable_chats)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'run_id', x."run_id", 'chat_id', x."chat_id", 'step_key', x."step_key", 'label', x."label", 'status', x."status", 'detail', x."detail", 'started_at', x."started_at", 'ended_at', x."ended_at") order by x."run_id", x.step_rank), '[]'::jsonb)
  from ranked x
  where x.step_rank <= greatest(coalesce(list_ai_run_steps_for.per_run, 50), 1)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_applications_for_jobs (
  jobs  uuid[],
  state text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by array_position(list_applications_for_jobs.jobs, x."job_id"), x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = any (list_applications_for_jobs.jobs)
    and (list_applications_for_jobs.state is null or x."state" = list_applications_for_jobs.state)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.templates_get_many (
  template_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'scope', x."scope",
    'brand', x."brand",
    'key', x."key",
    'type', x."type",
    'name', x."name",
    'language', x."language",
    'isDefault', x."is_default",
    'settings', x."settings",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'publishedVersion', (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."id" and y."published_at" is not null order by y."version" desc limit 1),
    'upstreamVersion', case when x."forked_from" is not null then (select y."version" from "better_supabase"."template_versions" y where y."template_id" = x."forked_from" and y."published_at" is not null order by y."version" desc limit 1) end,
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
    'published', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is not null
      order by y."version" desc limit 1),
    'draft', (select jsonb_build_object(
    'id', y."id",
    'template', y."template_id",
    'version', y."version",
    'hash', y."hash",
    'publishedAt', y."published_at",
    'createdBy', y."created_by",
    'createdAt', y."created_at",
    'body', y."body"
  ) from "better_supabase"."template_versions" y
      where y."template_id" = x."id" and y."published_at" is null))
    order by array_position(templates_get_many.template_ids, x."id")), '[]'::jsonb)
  from "better_supabase"."templates" x
  where x."id" = any (templates_get_many.template_ids)
$function$;

REVOKE ALL ON FUNCTION "api"."get_care_plans"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_care_plans"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_versions"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_versions"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_run_steps_for"(uuid[], integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_run_steps_for"(uuid[], integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_applications_for_jobs"(uuid[], text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_applications_for_jobs"(uuid[], text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."templates_get_many"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."templates_get_many"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_care_plans"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_care_plans"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_versions"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_versions"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_run_steps_for"(uuid[], integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_run_steps_for"(uuid[], integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_applications_for_jobs"(uuid[], text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_applications_for_jobs"(uuid[], text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."templates_get_many"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."templates_get_many"(uuid[]) TO "authenticated", "service_role";
