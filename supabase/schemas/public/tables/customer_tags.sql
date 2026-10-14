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

revoke all on public.customer_tags from anon, authenticated;

grant select, insert, update, delete on public.customer_tags to authenticated;

grant all on public.customer_tags to service_role;
