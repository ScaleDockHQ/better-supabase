SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.list_applications (
  job   uuid,
  state text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_applications"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_booking_resources (
  tenant           uuid,
  include_inactive boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_booking_resources"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_booking_services (
  tenant           uuid,
  include_inactive boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_booking_services"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_jobs (
  tenant uuid,
  status text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_jobs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_applications (
  job   uuid,
  state text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = list_applications.job
    and (list_applications.state is null or x."state" = list_applications.state)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_booking_resources (
  tenant           uuid,
  include_inactive boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rs."id", 'name', rs."name", 'kind', rs."kind",
    'capacity', rs."capacity", 'tz', rs."tz", 'active', rs."active",
    'calendarId', rs."calendar_id",
    'hostUserId', rs."host_user_id"
  ) order by rs."name", rs."id"), '[]'::jsonb)
  from "better_supabase"."booking_resources" rs
  where rs."tenant_id" = list_booking_resources.tenant
    and (list_booking_resources.include_inactive or rs."active")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_booking_services (
  tenant           uuid,
  include_inactive boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', sv."id", 'name', sv."name",
    'duration', sv."duration"::text,
    'bufferBefore', sv."buffer_before"::text,
    'bufferAfter', sv."buffer_after"::text,
    'resourceKinds', to_jsonb(sv."resource_kinds"),
    'active', sv."active"
  ) order by sv."name", sv."id"), '[]'::jsonb)
  from "better_supabase"."booking_services" sv
  where sv."tenant_id" = list_booking_services.tenant
    and (list_booking_services.include_inactive or sv."active")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_jobs (
  tenant uuid,
  status text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."job_openings" x
  where x."tenant_id" = list_jobs.tenant
    and (list_jobs.status is null or x."status" = list_jobs.status)
$function$;

REVOKE ALL ON FUNCTION "api"."list_applications"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_applications"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_booking_resources"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_booking_resources"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_booking_services"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_booking_services"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_jobs"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_jobs"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_applications"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_applications"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_booking_resources"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_booking_resources"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_booking_services"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_booking_services"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_jobs"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_jobs"(uuid, text) TO "authenticated", "service_role";
