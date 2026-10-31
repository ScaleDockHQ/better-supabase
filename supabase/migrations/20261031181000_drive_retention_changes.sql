SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.drive_changes (
  tenant    uuid,
  after     text    DEFAULT NULL::text,
  page_size integer DEFAULT 200,
  drive     uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_changes"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.drive_retention_kind (
  label text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_retention_kind"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_retention_sweep (
  tenant     uuid    DEFAULT NULL::uuid,
  batch_size integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_retention_sweep"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_changes (
  tenant    uuid,
  after     text    DEFAULT NULL::text,
  page_size integer DEFAULT 200,
  drive     uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_at timestamptz;
  v_id uuid;
  v_size integer := least(greatest(coalesce(drive_changes.page_size, 200), 1), 500);
  v_row "better_supabase"."drive_nodes"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_more boolean := false;
  v_cursor text := drive_changes.after;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_changes.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_changes.after is not null then
    begin
      v_at := split_part(drive_changes.after, '|', 1)::timestamptz;
      v_id := split_part(drive_changes.after, '|', 2)::uuid;
    exception when others then
      raise exception 'the changes cursor is not valid' using errcode = '22023', hint = 'DRIVE_CURSOR_INVALID';
    end;
  end if;
  for v_row in
    select * from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_changes.tenant
      and (v_at is null or (x."updated_at", x."id") > (v_at, v_id))
      and x."updated_at" <= now() - interval '5 seconds'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
    order by x."updated_at", x."id"
    limit v_size + 1
  loop
    v_count := v_count + 1;
    if v_count > v_size then
      v_more := true;
      exit;
    end if;
    v_items := v_items || jsonb_build_array(case when v_row."deleted_at" is not null
        then jsonb_build_object('removed', true, 'id', v_row."id")
        else jsonb_build_object('removed', false, 'node', ("better_supabase"."drive_node_json"(v_row) || jsonb_build_object('role', "better_supabase"."drive_role"((v_row)."id"), 'readOnly', (coalesce((v_row)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_row)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_row)."id")))) end);
    v_cursor := to_char(v_row."updated_at" at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || v_row."id"::text;
  end loop;
  return jsonb_build_object('changes', v_items, 'cursor', v_cursor, 'more', v_more);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_bin_touch()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if new."deleted_at" is distinct from old."deleted_at" then
    new."updated_at" := now();
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_retention_kind (
  label text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select 'drive_label_' || left(coalesce(nullif(btrim(regexp_replace(lower(drive_retention_kind.label), '[^a-z0-9]+', '_', 'g'), '_'), ''), 'label'), 50)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_retention_sweep (
  tenant     uuid    DEFAULT NULL::uuid,
  batch_size integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node uuid;
  v_binned integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'not allowed to sweep retention' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  for v_node in
    select x."id" from "better_supabase"."drive_nodes" x
    where (drive_retention_sweep.tenant is null or x."tenant_id" = drive_retention_sweep.tenant) and x."deleted_at" is null
      and exists (
        select 1 from "better_supabase"."taggings" lg
        join "better_supabase"."tags" lt on lt."id" = lg."tag_id"
        where lg."subject_type" = 'drive_node' and lg."subject_id" = x."id"::text
          and "better_supabase"."retention_for"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text) is not null
          and coalesce(x."updated_at", x."created_at") < now() - "better_supabase"."retention_for"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text)
          and not "better_supabase"."is_held"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text)
      )
      and not "better_supabase"."drive_node_held"(x."id")
    order by coalesce(x."updated_at", x."created_at"), x."id"
    limit least(greatest(coalesce(drive_retention_sweep.batch_size, 100), 1), 1000)
  loop
    begin
      perform "better_supabase"."drive_trash"(v_node);
      v_binned := v_binned + 1;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
  return v_binned;
end;
$function$;

CREATE TRIGGER bsb_drive_node_bin_touch
  BEFORE UPDATE OF deleted_at ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.drive_node_bin_touch();

REVOKE ALL ON FUNCTION "api"."drive_changes"(uuid, text, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_changes"(uuid, text, integer, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_retention_kind"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_retention_kind"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_retention_sweep"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_retention_sweep"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_changes"(uuid, text, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_changes"(uuid, text, integer, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_retention_kind"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_retention_kind"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_retention_sweep"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_retention_sweep"(uuid, integer) TO "service_role";
