-- The organizations whose last owner the member is: removing their
-- memberships (leaving, or deleting the account) would fail the owner check.
-- A member reads their own; the service role passes any member.
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
begin
  if v_member is null or (not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and v_member is distinct from auth.uid()) then
    raise exception 'Only the member or the service role can read this' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return coalesce((
    select array_agg(m."organization_id" order by m."organization_id")
    from "public"."memberships" m
    where m."user_id" = v_member and m."role" = 'owner'
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
