SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."add_team_member"(uuid, uuid);

DROP FUNCTION "better_supabase"."remove_member"(uuid, uuid);

DROP FUNCTION "better_supabase"."remove_team_member"(uuid, uuid);

CREATE TABLE "better_supabase"."declared_defaults" (
  "kind"     text    NOT NULL,
  "subject"  text    NOT NULL,
  "key"      text    NOT NULL,
  "position" integer NOT NULL DEFAULT 0,
  "value"    jsonb   NOT NULL,
  CONSTRAINT "declared_defaults_pkey" PRIMARY KEY (kind, subject, key)
);

ALTER TABLE "better_supabase"."declared_defaults"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION better_supabase.attachment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return attachment_subject_readable.subject_type is null or case attachment_subject_readable.subject_type
    when 'job' then exists (select 1 from "public"."jobs" s where s."id" = (case when attachment_subject_readable.subject_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (attachment_subject_readable.subject_id)::uuid end) and s."organization_id" = attachment_subject_readable.tenant)
    else false
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_team_member (
  team   uuid,
  member uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = create_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = create_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  values (create_team_member.team, create_team_member.member, v_tenant)
  on conflict do nothing;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.declared_defaults_of (
  kind    text,
  subject text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_agg(d.value order by d.position, d.key)
  from better_supabase.declared_defaults d
  where d.kind = declared_defaults_of.kind and d.subject = declared_defaults_of.subject
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_member (
  organization uuid,
  member       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  current_role_value text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select m."role"::text into current_role_value from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from "better_supabase"."memberships" where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'removed';
    end if;
  end;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_team_member (
  team   uuid,
  member uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = delete_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."team_members"
  where "team_id" = delete_team_member.team and "user_id" = delete_team_member.member;
  null;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.explain_permission (
  tenant     uuid,
  member     uuid,
  permission text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_allowed boolean;
  v_member boolean;
  v_roles jsonb;
  v_matched text[];
  v_override boolean;
  v_reason text;
begin
  if not (coalesce(auth.jwt() ->> 'role', '') = 'service_role' or explain_permission.member is not distinct from auth.uid()
    or coalesce(better_supabase.member_can(auth.uid(), explain_permission.tenant, 'members.read'), false)) then
    raise exception 'Not allowed to explain this member''s permissions' using errcode = '42501', hint = 'PERMISSIONS_FORBIDDEN';
  end if;
  v_allowed := coalesce(better_supabase.member_can(explain_permission.member, explain_permission.tenant, explain_permission.permission), false);
  select count(*) > 0, coalesce(jsonb_agg(m."role"::text), '[]'::jsonb) into v_member, v_roles
  from "better_supabase"."memberships" m
  where m."organization_id" = explain_permission.tenant and m."user_id" = explain_permission.member and m."disabled_at" is null;
  v_matched := coalesce((
    select array_agg(k.key order by k.key)
    from unnest(better_supabase.member_permissions(explain_permission.member, explain_permission.tenant)) k(key)
    where better_supabase.permission_matches(k.key, explain_permission.permission)
  ), '{}'::text[]);
  v_override := null::boolean;
  v_reason := case
    when v_allowed then case when v_override is true then 'granted_by_override' else 'granted_by_role' end
    when better_supabase.user_disabled(explain_permission.member) then 'member_disabled'
    when better_supabase.tenant_disabled(explain_permission.tenant) then 'organization_disabled'
    when not v_member then 'not_a_member'
    when v_override is false then 'denied_by_override'
    when (explain_permission.member is distinct from auth.uid() or better_supabase.cap_allows(explain_permission.permission)) is not true then 'not_in_scope'
    else 'role_lacks_key'
  end;
  return jsonb_build_object(
    'permission', explain_permission.permission,
    'userId', explain_permission.member,
    'organizationId', explain_permission.tenant,
    'allowed', v_allowed,
    'reason', v_reason,
    'roles', v_roles,
    'matchedBy', to_jsonb(v_matched),
    'override', v_override
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'permissions.explain' then 'members.read'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
  end
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."create_team_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_team_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."declared_defaults_of"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."declared_defaults_of"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_team_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_team_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."explain_permission"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."explain_permission"(uuid, uuid, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."declared_defaults" TO "service_role";
