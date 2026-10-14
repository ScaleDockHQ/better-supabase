create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger organizations_set_updated_at before update on public.organizations
  for each row execute function better_supabase.set_updated_at();

alter table public.organizations enable row level security;

create policy organizations_member_select on public.organizations
  for select to authenticated
  using (id = (select better_supabase.current_tenant_id()));

revoke all on public.organizations from anon, authenticated;

grant select on public.organizations to authenticated;

grant all on public.organizations to service_role;
