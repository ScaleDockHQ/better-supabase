SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.record_summary (
  subject_type text,
  subject_id   text,
  sections     text[],
  seen_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_summary"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.record_summary (
  subject_type text,
  subject_id   text,
  sections     text[],
  seen_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_counts jsonb := '{}'::jsonb;
  v_unread jsonb := '{}'::jsonb;
  v_count bigint;
  v_latest timestamptz;
begin
  if coalesce(cardinality(record_summary.sections), 0) > 20 then
    raise exception 'record_summary takes at most 20 sections'
      using errcode = '22023', hint = 'RECORD_SECTIONS_TOO_MANY';
  end if;
  if not "better_supabase"."can_subject"(record_summary.subject_type, record_summary.subject_id, 'read') then
    return null;
  end if;
  if 'comments' = any (record_summary.sections) then
    select count(*), max(x."created_at")
      into v_count, v_latest
      from "better_supabase"."comments" x
      where x."subject_type"::text = record_summary.subject_type
        and x."subject_id"::text = record_summary.subject_id
        and x."deleted_at" is null;
    v_counts := v_counts || jsonb_build_object('comments', v_count);
    v_unread := v_unread || jsonb_build_object('comments',
      record_summary.seen_at is not null and v_latest is not null and v_latest > record_summary.seen_at);
  end if;
  if 'attachments' = any (record_summary.sections) then
    select count(*), max(x."uploaded_at")
      into v_count, v_latest
      from "better_supabase"."attachments" x
      where x."subject_type"::text = record_summary.subject_type
        and x."subject_id"::text = record_summary.subject_id
        and x."uploaded_at" is not null and x."status" <> 'infected';
    v_counts := v_counts || jsonb_build_object('attachments', v_count);
    v_unread := v_unread || jsonb_build_object('attachments',
      record_summary.seen_at is not null and v_latest is not null and v_latest > record_summary.seen_at);
  end if;
  return jsonb_build_object(
    'type', record_summary.subject_type,
    'id', record_summary.subject_id,
    'title', "better_supabase"."subject_title"(record_summary.subject_type, record_summary.subject_id),
    'url', "better_supabase"."subject_url"(record_summary.subject_type, record_summary.subject_id),
    'counts', v_counts,
    'unread', v_unread);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."record_summary"(text, text, text[], timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_summary"(text, text, text[], timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_summary"(text, text, text[], timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_summary"(text, text, text[], timestamp WITH time zone) TO "authenticated", "service_role";
