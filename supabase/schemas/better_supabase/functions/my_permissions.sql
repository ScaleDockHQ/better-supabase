-- The keys the signed-in user holds in a tenant, for `usePermissions` and
-- `<Can>`. In custom mode the app writes it next to the contract. With
-- `keys`, the ones can() grants; without them, the role's list, wildcards
-- as granted.
create or replace function better_supabase.my_permissions(tenant uuid, keys text[] default null)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when auth.uid() is null or my_permissions.tenant is null then '{}'::text[]
    when my_permissions.keys is not null then coalesce((
      select array_agg(distinct k order by k)
      from unnest(my_permissions.keys) as k
      where better_supabase.can('tenant', my_permissions.tenant, k)
    ), '{}'::text[])
    else coalesce(better_supabase.role_permissions(
      better_supabase.organization_member_role(my_permissions.tenant, auth.uid())
    ), '{}'::text[])
  end
$$;

revoke execute on function better_supabase.my_permissions(uuid, text[]) from public;

grant execute on function better_supabase.my_permissions(uuid, text[]) to anon, authenticated, service_role;
