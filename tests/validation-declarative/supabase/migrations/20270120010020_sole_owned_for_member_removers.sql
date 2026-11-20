-- The organizations whose last owner the member is: removing their
-- memberships (leaving, or deleting the account) would fail the owner check.
-- A member reads their own and the service role any member's; for another
-- member, the caller gets the organizations where they may remove members
-- (blocks.organizations.permissions.removeMember), so an offboarding run by
-- HR can ask first. It never raises for another member.
create or replace function "better_supabase"."sole_owned_organizations"(member uuid default null)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member uuid := coalesce(member, auth.uid());
  v_all boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_member = auth.uid();
begin
  if v_member is null then
    raise exception 'Only the member or the service role can read this' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return coalesce((
    select array_agg(m."organization_id" order by m."organization_id")
    from "public"."memberships" m
    where m."user_id" = v_member and m."role" = 'owner'
      and (v_all or coalesce(better_supabase.member_can(auth.uid(), m."organization_id", 'members.remove'), false))
      and exists (select 1 from "public"."organizations" o where o."id" = m."organization_id")
      and not exists (
        select 1 from "public"."memberships" y
        where y."organization_id" = m."organization_id" and y."user_id" <> v_member and y."role" = 'owner'
      )
  ), '{}');
end;
$$;
revoke execute on function "better_supabase"."sole_owned_organizations"(uuid) from public, anon;
grant execute on function "better_supabase"."sole_owned_organizations"(uuid) to authenticated, service_role;
