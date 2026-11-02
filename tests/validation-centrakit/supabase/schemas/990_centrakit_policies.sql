-- CentraKit's own policies on the adopted tables, loaded after the block. The
-- refactor swaps public.organization_ids_with_permission for better_supabase.tenant_ids_with.
create policy webhook_destinations_select on centrakit.webhook_destinations
  for select to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('webhook.view')));
create policy webhook_destinations_insert on centrakit.webhook_destinations
  for insert to authenticated
  with check (organization_id in (select better_supabase.tenant_ids_with('webhook.manage')));
create policy webhook_destinations_update on centrakit.webhook_destinations
  for update to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('webhook.manage')))
  with check (organization_id in (select better_supabase.tenant_ids_with('webhook.manage')));
create policy webhook_destinations_delete on centrakit.webhook_destinations
  for delete to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('webhook.manage')));

create policy customers_member on centrakit.customers
  for all to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('crm.read')))
  with check (organization_id in (select better_supabase.tenant_ids_with('crm.read')));
create policy customer_contacts_member on centrakit.customer_contacts
  for all to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('crm.read')))
  with check (organization_id in (select better_supabase.tenant_ids_with('crm.read')));

-- Organization members see every project; project members see their own.
create policy projects_member on centrakit.projects
  for select to authenticated
  using (
    organization_id in (select centrakit.authz_organization_member_ids())
    or id in (select pm.project_id from centrakit.project_members pm where pm.user_id = (select auth.uid()))
  );
create policy project_members_own on centrakit.project_members
  for select to authenticated
  using (user_id = (select auth.uid()));
create policy tasks_member on centrakit.tasks
  for all to authenticated
  using (organization_id in (select centrakit.authz_organization_member_ids()))
  with check (organization_id in (select centrakit.authz_organization_member_ids()));

-- CentraKit's file tree reads through the provider's row grants, which reach
-- nodes shared from another organization. The drive module's own read policy
-- and tenant scope are replaced here so a grant outside the member's
-- organizations stays visible; the restrictive scope stays, with the grant
-- branch repeated (ADR 0099/0104).
drop policy if exists bsb_file_node_select on centrakit.file_node;
drop policy if exists bsb_tenant_scope_select on centrakit.file_node;
create policy file_node_select on centrakit.file_node
  for select to authenticated
  using (id::text in (select centrakit.authz_file_node_rows('fileNode.read')));
create policy bsb_tenant_scope_select on centrakit.file_node as restrictive
  for select to public
  using (
    organization_id in (select better_supabase.member_organization_ids())
    or id::text in (select centrakit.authz_file_node_rows('fileNode.read'))
  );
