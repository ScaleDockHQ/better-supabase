SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.drive_transfer_ownership (
  tenant    uuid,
  from_user uuid,
  to_user   uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_grant "better_supabase"."drive_grants"%rowtype;
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_drive_ids uuid[] := '{}';
  v_nodes integer := 0;
  v_drives integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_transfer_ownership.tenant, 'drive.manage'), false)) then
    raise exception 'you can''t transfer items in this organization' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and drive_transfer_ownership.from_user is distinct from auth.uid() then
    raise exception 'you can only transfer your own items' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_transfer_ownership.from_user is null or drive_transfer_ownership.to_user is null
    or drive_transfer_ownership.from_user = drive_transfer_ownership.to_user then
    raise exception 'name two different users to transfer between' using errcode = '22023', hint = 'DRIVE_TRANSFER_INVALID';
  end if;
  if not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = drive_transfer_ownership.tenant and mu."user_id" = drive_transfer_ownership.to_user
  ) then
    raise exception 'the new owner is not an active member of this organization' using errcode = 'P0002', hint = 'DRIVE_PRINCIPAL_NOT_FOUND';
  end if;
  for v_grant in
    select gr.* from "better_supabase"."drive_grants" gr
    where gr."tenant_id" = drive_transfer_ownership.tenant and gr."role"::text = 'owner'
      and gr."principal_type" = 'user' and gr."principal_id" = drive_transfer_ownership.from_user::text
  loop
    delete from "better_supabase"."drive_grants" gr where gr."node_id" = v_grant."node_id" and gr."principal_type" = 'user' and gr."principal_id" = drive_transfer_ownership.to_user::text;
    update "better_supabase"."drive_grants" set "principal_id" = drive_transfer_ownership.to_user::text where "id" = v_grant."id";
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_grant."node_id";
    v_nodes := v_nodes + 1;
    perform "better_supabase".emit_event('drive_node.ownership_transferred', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.ownership_transferred',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'ownership transferred',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text)
  );
  end loop;
  return jsonb_build_object('nodes', v_nodes, 'drives', v_drives);
end;
$function$;
