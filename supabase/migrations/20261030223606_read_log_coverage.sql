SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."activities_of"(text, text, text[], timestamp WITH time zone, integer);

DROP FUNCTION "better_supabase"."list_attachments"(uuid, text, text);

CREATE OR REPLACE FUNCTION better_supabase.activities_of (
  subject_type text,
  subject_id   text,
  types        text[],
  before       timestamp with time zone,
  page_size    integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb) into v_rows
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."activities" x
    join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
    where k."subject_type" = activities_of.subject_type and k."subject_id" = activities_of.subject_id
      and (activities_of.types is null or x."type" = any (activities_of.types))
      and (activities_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < activities_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(activities_of.page_size, 50), 1), 200)
  ) p;
  if jsonb_array_length(v_rows) > 0 then
    perform "better_supabase"."record_subject_read"(activities_of.subject_type, activities_of.subject_id, null, 'activities', 'activities_of');
  end if;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_attachments (
  tenant       uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_files jsonb;
begin
  with page as (
    select * from "better_supabase"."attachments" y
    where y."organization_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  ),
  m as (select "better_supabase"."attachment_authors"(array(select p."id" from page p)) as authors)
  select coalesce(jsonb_agg((to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) || jsonb_build_object('author', m.authors -> a."id"::text) order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a, m;
  if jsonb_array_length(v_files) > 0 and list_attachments.subject_type is not null and list_attachments.subject_id is not null then
    perform "better_supabase"."record_subject_read"(list_attachments.subject_type, list_attachments.subject_id, null, 'attachments', 'list_attachments');
  end if;
  return v_files;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."activities_of"(text, text, text[], timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."activities_of"(text, text, text[], timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_attachments"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_attachments"(uuid, text, text) TO "authenticated", "service_role";
