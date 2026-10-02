create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  kvk text,
  status text not null default 'lead' check (status in ('lead', 'active', 'archived')),
  primary_contact_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid,
  updated_by uuid,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- The object path in the customer-logos bucket, never a URL: signed URLs
  -- expire and public URLs pin the project host.
  logo_path text,
  -- Archived customers keep their KvK number, so restoring one can't create a
  -- duplicate. The key is not partial on archived_at for that reason.
  constraint customers_organization_id_kvk_key unique (organization_id, kvk),
  constraint customers_id_organization_id_key unique (id, organization_id),
  -- Foreign key checks bypass RLS; the tenant column in the key stops a row
  -- from pointing at another organization's contact.
  constraint customers_primary_contact_id_fkey foreign key (primary_contact_id, organization_id)
    references public.contacts (id, organization_id) on delete set null (primary_contact_id)
);

create index customers_primary_contact_id_idx on public.customers (primary_contact_id, organization_id);
create index customers_organization_id_created_by_idx on public.customers (organization_id, created_by);
create index customers_organization_id_status_idx on public.customers (organization_id, status);
create index customers_active_idx on public.customers (organization_id, created_at desc)
  where archived_at is null;
create index customers_name_trgm_idx on public.customers using gin (name extensions.gin_trgm_ops);

create trigger customers_set_updated_at before update on public.customers
  for each row execute function public.set_updated_at();

alter table public.customers enable row level security;

create policy customers_tenant on public.customers
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));
