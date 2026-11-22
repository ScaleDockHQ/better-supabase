-- The organizations whose last owner the member is: removing their
-- memberships (leaving, or deleting the account) would fail the owner check.
-- A member reads their own and the service role any member's. Another member's
-- list needs the remove permission (blocks.organizations.permissions.removeMember
-- or options.soleOwnedPermission) in every organization the list would name, and
-- in at least one organization of the member, so an offboarding run by HR can ask
-- first. Without it the call raises instead of returning a partial list.
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
  v_ids uuid[];
begin
  if v_member is null then
    raise exception 'Only the member or the service role can read this' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not v_all and not exists (select 1 from "better_supabase"."memberships" m
    where m."user_id" = v_member
      and coalesce(better_supabase.member_can(auth.uid(), m."organization_id", 'members.remove'), false)) then
    raise exception 'Not allowed to read this member''s organizations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  v_ids := coalesce((
    select array_agg(m."organization_id" order by m."organization_id")
    from "better_supabase"."memberships" m
    where m."user_id" = v_member and m."role" = 'owner'
      and exists (select 1 from "better_supabase"."organizations" o where o."id" = m."organization_id")
      and not exists (
        select 1 from "better_supabase"."memberships" y
        where y."organization_id" = m."organization_id" and y."user_id" <> v_member and y."role" = 'owner' and y."disabled_at" is null
      )
  ), '{}');
  if not v_all and exists (
    select 1 from unnest(v_ids) t (id)
    where not coalesce(better_supabase.member_can(auth.uid(), t.id, 'members.remove'), false)
  ) then
    raise exception 'Not allowed to read this member''s organizations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return v_ids;
end;
$$;
revoke execute on function "better_supabase"."sole_owned_organizations"(uuid) from public, anon;
grant execute on function "better_supabase"."sole_owned_organizations"(uuid) to authenticated, service_role;
