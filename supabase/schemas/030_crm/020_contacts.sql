create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  email text not null,
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Target of the composite foreign keys that keep children in the same tenant.
  constraint contacts_id_organization_id_key unique (id, organization_id)
);

create index contacts_organization_id_idx on public.contacts (organization_id);

create trigger contacts_set_updated_at before update on public.contacts
  for each row execute function public.set_updated_at();

alter table public.contacts enable row level security;

create policy contacts_tenant on public.contacts
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));
