SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.list_jobs (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', j.id,
    'title', j.title,
    'status', j.status,
    'location', j.location
  ) order by j.created_at desc), '[]'::jsonb)
  from better_supabase.job_openings j
  where j.tenant_id = list_jobs.tenant;
$function$;
