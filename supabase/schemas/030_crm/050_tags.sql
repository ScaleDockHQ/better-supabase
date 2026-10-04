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

create table public.customer_tags (
  customer_id uuid not null,
  tag_id uuid not null,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (customer_id, tag_id),
  constraint customer_tags_customer_id_fkey foreign key (customer_id, organization_id)
    references public.customers (id, organization_id) on delete cascade,
  constraint customer_tags_tag_id_fkey foreign key (tag_id, organization_id)
    references public.tags (id, organization_id) on delete cascade
);

create index customer_tags_customer_id_idx on public.customer_tags (customer_id, organization_id);
create index customer_tags_tag_id_idx on public.customer_tags (tag_id, organization_id);
create index customer_tags_organization_id_idx on public.customer_tags (organization_id);

alter table public.customer_tags enable row level security;

create policy customer_tags_tenant on public.customer_tags
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));
