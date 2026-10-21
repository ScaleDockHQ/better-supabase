SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.attachment_authors (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(y."id"::text, jsonb_build_object('id', pr."id", 'name', coalesce(nullif(pr."full_name", ''), nullif(trim(concat_ws(' ', pr."first_name", pr."last_name")), ''), pr."username"), 'avatarUrl', pr."avatar_url")), '{}'::jsonb)
  from "better_supabase"."attachments" y
  join "better_supabase"."profiles" pr on pr."id" = y."uploaded_by"
  where y."id" = any ($1)
    and y."organization_id" in (select better_supabase.tenant_ids_with('attachments.read'))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_authors (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(y."id"::text, jsonb_build_object('id', pr."id", 'name', coalesce(nullif(pr."full_name", ''), nullif(trim(concat_ws(' ', pr."first_name", pr."last_name")), ''), pr."username"), 'avatarUrl', pr."avatar_url")), '{}'::jsonb)
  from "better_supabase"."comments" y
  join "better_supabase"."profiles" pr on pr."id" = y."author_id"
  where y."id" = any ($1)
    and y."organization_id" in (select better_supabase.tenant_ids_with('comments.read'))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_attachments (
  tenant       uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with page as (
    select * from "better_supabase"."attachments" y
    where y."organization_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  ),
  m as (select "better_supabase"."attachment_authors"(array(select p."id" from page p)) as authors)
  select coalesce(jsonb_agg(to_jsonb(a.*) || jsonb_build_object('author', m.authors -> a."id"::text) order by a."created_at", a."id"), '[]'::jsonb)
  from page a, m
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_comments (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 100,
  skip         integer                  DEFAULT 0,
  after_id     uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with page as (
    select * from "better_supabase"."comments" y
    where y."organization_id" = list_comments.tenant
      and y."subject_type" = list_comments.subject_type
      and y."subject_id" = list_comments.subject_id
      and (list_comments.after is null
        or (y."created_at", y."id") > (list_comments.after, coalesce(list_comments.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by y."created_at", y."id"
    limit least(greatest(coalesce(list_comments.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ),
  m as (select "better_supabase"."comment_authors"(array(select p."id" from page p)) as authors)
  select coalesce(jsonb_agg(to_jsonb(x.*) || jsonb_build_object('author', m.authors -> x."id"::text) order by x."created_at", x."id"), '[]'::jsonb)
  from page x, m
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."attachment_authors"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attachment_authors"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."comment_authors"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."comment_authors"(uuid[]) TO "authenticated", "service_role";
