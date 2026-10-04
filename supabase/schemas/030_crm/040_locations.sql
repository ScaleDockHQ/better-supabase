create table public.locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  customer_id uuid not null,
  label text not null,
  city text,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint locations_customer_id_fkey foreign key (customer_id, organization_id)
    references public.customers (id, organization_id) on delete cascade
);

create index locations_customer_id_idx on public.locations (customer_id, organization_id);
create index locations_organization_id_idx on public.locations (organization_id);

create trigger locations_set_updated_at before update on public.locations
  for each row execute function better_supabase.set_updated_at();

alter table public.locations enable row level security;

create policy locations_tenant on public.locations
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));
