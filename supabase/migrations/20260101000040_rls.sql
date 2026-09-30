alter table public.organizations enable row level security;
alter table public.contacts enable row level security;
alter table public.customers enable row level security;
alter table public.locations enable row level security;
alter table public.tags enable row level security;
alter table public.customer_tags enable row level security;
alter table public.notes enable row level security;

create policy organizations_member_select on public.organizations
  for select to authenticated
  using (id = (select better_supabase.current_tenant_id()));

create policy contacts_tenant on public.contacts
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));

create policy customers_tenant on public.customers
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));

create policy locations_tenant on public.locations
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));

create policy tags_tenant on public.tags
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));

create policy customer_tags_tenant on public.customer_tags
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));

create policy notes_tenant on public.notes
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));

revoke all on all tables in schema public from anon, authenticated;
grant select on public.organizations to authenticated;
grant select, insert, update, delete on
  public.contacts,
  public.customers,
  public.locations,
  public.tags,
  public.customer_tags,
  public.notes
to authenticated;
grant all on all tables in schema public to service_role;
