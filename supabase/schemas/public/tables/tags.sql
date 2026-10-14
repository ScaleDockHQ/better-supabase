create table public.tags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  color text not null default 'gray' check (color in ('gray', 'red', 'green', 'blue')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tags_organization_id_name_key unique (organization_id, name),
  constraint tags_id_organization_id_key unique (id, organization_id)
);

create trigger tags_set_updated_at before update on public.tags
  for each row execute function better_supabase.set_updated_at();

alter table public.tags enable row level security;

create policy tags_tenant on public.tags
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));

revoke all on public.tags from anon, authenticated;

grant select, insert, update, delete on public.tags to authenticated;

grant all on public.tags to service_role;
