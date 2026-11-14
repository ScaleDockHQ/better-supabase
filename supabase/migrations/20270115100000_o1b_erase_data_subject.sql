SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.erase_data_subject (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."erase_data_subject"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.erase_data_subject (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."data_subject_requests";
  v_count bigint;
  v_removed jsonb := '{}'::jsonb;
  v_blanked jsonb := '{}'::jsonb;
  v_kept jsonb := '{}'::jsonb;
  v_held jsonb := '{}'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."data_subject_requests" x where x."id" = erase_data_subject.request_id for update;
  if v_row."id" is null then
    raise exception 'request not found' using errcode = 'P0002', hint = 'DSAR_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if v_row."kind" <> 'erasure' then
    raise exception 'only an erasure request is executed' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'the request is already fulfilled or refused' using errcode = '55000', hint = 'DSAR_CLOSED';
  end if;
  if v_row."verified_at" is null then
    raise exception 'verify the requester''s identity first' using errcode = '55000', hint = 'DSAR_UNVERIFIED';
  end if;
  if v_row."subject_type" is null then
    raise exception 'an erasure request names the record to erase' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;

  if "better_supabase"."is_held"('audit', v_row."tenant_id"::text) then
    select count(*) into v_count from "better_supabase"."data_subject_requests" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
    v_held := v_held || jsonb_build_object('better_supabase.data_subject_requests', v_count);
  else
    select count(*) into v_count from "better_supabase"."data_subject_requests" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
      v_kept := v_kept || jsonb_build_object('better_supabase.data_subject_requests', v_count);
  end if;

  if "better_supabase"."is_held"('audit', v_row."tenant_id"::text) then
    select count(*) into v_count from "better_supabase"."field_changes" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
    v_held := v_held || jsonb_build_object('better_supabase.field_changes', v_count);
  else
    with blank as (update "better_supabase"."field_changes" x set "old_value" = null, "new_value" = null, "changed_by" = null where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id" returning 1) select count(*) into v_count from blank;
      v_blanked := v_blanked || jsonb_build_object('better_supabase.field_changes', v_count);
  end if;

  if "better_supabase"."is_held"('personal_data', v_row."tenant_id"::text) then
    select count(*) into v_count from "better_supabase"."consents" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
    v_held := v_held || jsonb_build_object('better_supabase.consents', v_count);
  else
    with blank as (update "better_supabase"."consents" x set "grantor_id" = null, "withdrawn_reason" = null, "signature_id" = null where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id" returning 1) select count(*) into v_count from blank;
      v_blanked := v_blanked || jsonb_build_object('better_supabase.consents', v_count);
  end if;

  if "better_supabase"."is_held"('personal_data', v_row."tenant_id"::text) then
    select count(*) into v_count from "better_supabase"."consent_signals" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id";
    v_held := v_held || jsonb_build_object('better_supabase.consent_signals', v_count);
  else
    with gone as (delete from "better_supabase"."consent_signals" x where x."tenant_id"::text = v_row."tenant_id"::text and x."subject_type" = v_row."subject_type" and x."subject_id" = v_row."subject_id" returning 1) select count(*) into v_count from gone;
      v_removed := v_removed || jsonb_build_object('better_supabase.consent_signals', v_count);
  end if;
  return jsonb_build_object('removed', v_removed, 'blanked', v_blanked, 'kept', v_kept, 'held', v_held);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."erase_data_subject"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."erase_data_subject"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."erase_data_subject"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."erase_data_subject"(uuid) TO "authenticated", "service_role";
