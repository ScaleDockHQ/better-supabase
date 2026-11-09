drop function if exists public.my_organizations();

create or replace function public.my_organizations(
  page_size integer default 50,
  after_last_used_at timestamptz default null,
  after_name text default null,
  after_id uuid default null
)
returns table (id uuid, name text, slug text, role text, plan text, last_used_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from better_supabase.app_my_organizations(
    page_size,
    after_last_used_at,
    after_name,
    after_id
  )
$$;

revoke execute on function public.my_organizations(integer, timestamptz, text, uuid) from public, anon;

grant execute on function public.my_organizations(integer, timestamptz, text, uuid) to authenticated, service_role;
