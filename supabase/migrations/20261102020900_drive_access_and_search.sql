SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.drive_node_access (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_node_access"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_search (
  tenant    uuid,
  query     text,
  page_size integer DEFAULT 25
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_search"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_access (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'role', "better_supabase"."drive_role"(drive_node_access.node),
    'read', "better_supabase"."drive_can"(drive_node_access.node, 'viewer'),
    'comment', "better_supabase"."drive_can"(drive_node_access.node, 'editor'),
    'download', "better_supabase"."drive_can_download"(drive_node_access.node),
    'upload', "better_supabase"."drive_can_upload"(drive_node_access.node),
    'write', "better_supabase"."drive_can"(drive_node_access.node, 'editor'),
    'share', "better_supabase"."drive_can"(drive_node_access.node, 'owner')
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_search (
  tenant    uuid,
  query     text,
  page_size integer DEFAULT 25
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_like text := '%' || replace(replace(replace(btrim(coalesce(drive_search.query, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_search.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if btrim(coalesce(drive_search.query, '')) = '' then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (coalesce((c.r)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"), 'downloadable', "better_supabase"."drive_can_download"((c.r)."id"))) order by (c.r)."kind" <> 'folder', (c.r)."name", (c.r)."id"), '[]'::jsonb)
    from (
      select x as r from "better_supabase"."drive_nodes" x
      where x."tenant_id" = drive_search.tenant and x."deleted_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (x."name" ilike v_like escape '\'
      or exists (select 1 from "better_supabase"."drive_node_texts" t where t."node_id" = x."id" and t."content" ilike v_like escape '\'))
      order by x."kind" <> 'folder', x."name", x."id"
      limit least(greatest(coalesce(drive_search.page_size, 25), 1), 100)
    ) c
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."drive_node_access"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_node_access"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_search"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_search"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_node_access"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_node_access"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_search"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_search"(uuid, text, integer) TO "authenticated", "service_role";
