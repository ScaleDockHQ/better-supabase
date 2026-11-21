-- Why a member does or doesn't hold one key in a tenant: the answer member_can
-- gives, the roles the member holds, the granted keys that match and a reason.
create or replace function better_supabase.explain_permission(tenant uuid, member uuid, permission text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
  from "public"."memberships" m
  where m."organization_id" = explain_permission.tenant and m."user_id" = explain_permission.member;
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
$$;
revoke execute on function better_supabase.explain_permission(uuid, uuid, text) from public, anon;
grant execute on function better_supabase.explain_permission(uuid, uuid, text) to authenticated, service_role;
