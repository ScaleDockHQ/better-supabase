SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.update_member_roles (
  organization uuid,
  members      uuid[],
  role         text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_member_roles"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.update_member_roles (
  organization uuid,
  members      uuid[],
  role         text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  one uuid;
  succeeded jsonb := '[]'::jsonb;
  failed jsonb := '[]'::jsonb;
  failure_hint text;
  failure_message text;
begin
  if coalesce(cardinality(members), 0) > 500 then
    raise exception 'A bulk call takes at most 500 members' using errcode = '22023', hint = 'BULK_TOO_MANY';
  end if;
  for one in select distinct m from unnest(members) m loop
    begin
      perform "better_supabase"."update_member_role"(organization, one, role);
      succeeded := succeeded || to_jsonb(one::text);
    exception when others then
      get stacked diagnostics failure_hint = pg_exception_hint, failure_message = message_text;
      failed := failed || jsonb_build_object('id', one::text, 'code', failure_hint, 'message', failure_message);
    end;
  end loop;
  return jsonb_build_object('succeeded', succeeded, 'failed', failed);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."update_member_roles"(uuid, uuid[], text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_member_roles"(uuid, uuid[], text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_member_roles"(uuid, uuid[], text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_member_roles"(uuid, uuid[], text) TO "authenticated", "service_role";
