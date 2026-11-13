SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.field_key_status()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."field_key_status"() $function$;

CREATE OR REPLACE FUNCTION api.marketplace_installation_for (
  tenant text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."marketplace_installation_for"($1) $function$;

CREATE OR REPLACE FUNCTION api.marketplace_resources_for (
  tenant text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."marketplace_resources_for"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.field_key_status()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role read field key status' using errcode = '42501', hint = 'FIELD_KEY_STATUS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'owner', o.owner,
      'has_key', exists (select 1 from vault.secrets s where s.name = 'bs:field-key:' || o.owner),
      'has_lookup_key', exists (select 1 from vault.secrets s where s.name = 'bs:field-lookup-key:' || o.owner)
    ) order by o.owner)
    from (
      select substr(s.name, 14) as owner
      from vault.secrets s
      where v_service and left(s.name, 13) = 'bs:field-key:'
      union
      select 'tenant:' || (m.id)::text
      from better_supabase.member_organization_ids() as m(id)
      where not v_service
    ) o
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.marketplace_installation_for (
  tenant text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (select 1 from better_supabase.member_organization_ids() as m(id) where m.id::text = marketplace_installation_for.tenant) then
    return null;
  end if;
  return (
    select to_jsonb(x) - 'access_token_secret_id'
    from "better_supabase"."marketplace_installations" x
    where x."tenant" = marketplace_installation_for.tenant and x."status"::text <> 'removed'
    order by x."created_at" desc
    limit 1
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.marketplace_resources_for (
  tenant text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (select 1 from better_supabase.member_organization_ids() as m(id) where m.id::text = marketplace_resources_for.tenant) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(y) - 'secret_refs' order by y."created_at"), '[]'::jsonb)
    from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where y."tenant" = marketplace_resources_for.tenant and y."status"::text <> 'deleted'
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."field_key_status"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."field_key_status"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."marketplace_installation_for"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."marketplace_installation_for"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."marketplace_resources_for"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."marketplace_resources_for"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."field_key_status"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."field_key_status"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."marketplace_installation_for"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."marketplace_installation_for"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."marketplace_resources_for"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."marketplace_resources_for"(text) TO "authenticated", "service_role";
