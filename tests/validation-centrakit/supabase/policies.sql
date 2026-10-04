-- CentraKit's own policies on the adopted tables, loaded after the kit. The
-- refactor swaps public.org_ids_with_permission for better_supabase.tenant_ids_with.
create policy webhook_destinations_select on centrakit.webhook_destinations
  for select to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('organization.webhooks.view')));
create policy webhook_destinations_insert on centrakit.webhook_destinations
  for insert to authenticated
  with check (organization_id in (select better_supabase.tenant_ids_with('organization.webhooks.manage')));
create policy webhook_destinations_update on centrakit.webhook_destinations
  for update to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('organization.webhooks.manage')))
  with check (organization_id in (select better_supabase.tenant_ids_with('organization.webhooks.manage')));
create policy webhook_destinations_delete on centrakit.webhook_destinations
  for delete to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('organization.webhooks.manage')));
