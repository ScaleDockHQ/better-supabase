SET local check_function_bodies = off;

DROP TRIGGER "bsb_drive_node_path" ON "better_supabase"."drive_nodes";

CREATE OR REPLACE FUNCTION better_supabase.drive_node_path()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
-- @bsb same-tenant-guard column=parent_id
declare
  v_parent_path text;
  v_parent_tenant text;
  v_parent_kind text;
begin
  if new."parent_id" is null then
    new."path" := '/' || new."id"::text || '/';
    return new;
  end if;
  select x."path", x."tenant_id"::text, x."kind" into v_parent_path, v_parent_tenant, v_parent_kind
  from "better_supabase"."drive_nodes" x where x."id" = new."parent_id";
  if v_parent_path is null or v_parent_tenant is distinct from new."tenant_id"::text then
    raise exception 'the parent folder does not exist in this organization' using errcode = '23503', hint = 'DRIVE_PARENT_NOT_FOUND';
  end if;
  if v_parent_kind <> 'folder' then
    raise exception 'a file can''t hold other items' using errcode = '22023', hint = 'DRIVE_PARENT_NOT_FOLDER';
  end if;
  if v_parent_path like '%/' || new."id"::text || '/%' then
    raise exception 'a folder can''t move into itself or its own subfolder' using errcode = '22023', hint = 'DRIVE_MOVE_CYCLE';
  end if;
  new."path" := v_parent_path || new."id"::text || '/';
  return new;
end;
$function$;

CREATE TRIGGER bsb_drive_node_path
  BEFORE INSERT OR UPDATE OF parent_id, tenant_id ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.drive_node_path();
