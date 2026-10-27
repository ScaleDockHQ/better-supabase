-- Folds the keys of a resource the caller holds every action of into
-- `resource.*`, the wildcard `permissionMatches()` and `can()` read, so an
-- organization's keys fit the access token hook's budget.
create or replace function rbac.compact_permission_keys(granted text[])
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(k order by k), '{}'::text[])
  from (
    select c.resource || '.*' as k
    from (
      select split_part(p.key, '.', 1) as resource,
        bool_and(p.key = any(granted)) as every
      from better_supabase.permissions p
      group by 1
    ) c
    where c.every
    union all
    select g
    from unnest(granted) g
    where exists (
      select 1 from better_supabase.permissions p
      where split_part(p.key, '.', 1) = split_part(g, '.', 1)
        and not p.key = any(granted)
    )
    or not exists (
      select 1 from better_supabase.permissions p
      where split_part(p.key, '.', 1) = split_part(g, '.', 1)
    )
  ) keys
$$;

revoke execute on function rbac.compact_permission_keys(text[]) from authenticated, anon, public;
grant execute on function rbac.compact_permission_keys(text[]) to supabase_auth_admin;
