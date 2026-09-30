create table public.tags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  color text not null default 'gray' check (color in ('gray', 'red', 'green', 'blue')),
  constraint tags_organization_id_name_key unique (organization_id, name)
);

create index tags_organization_id_idx on public.tags (organization_id);

alter table public.tags enable row level security;

create policy tags_tenant on public.tags
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));

create table public.customer_tags (
  customer_id uuid not null references public.customers (id) on delete cascade,
  tag_id uuid not null references public.tags (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  primary key (customer_id, tag_id)
);

create index customer_tags_tag_id_idx on public.customer_tags (tag_id);
create index customer_tags_organization_id_idx on public.customer_tags (organization_id);

alter table public.customer_tags enable row level security;

create policy customer_tags_tenant on public.customer_tags
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));
