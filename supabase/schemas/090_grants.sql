grant usage on schema better_supabase to anon, authenticated, service_role, supabase_auth_admin;
grant all on public.memberships to service_role;
revoke execute on function better_supabase.clear_tenant_claim() from public, anon, authenticated;

revoke all on
  public.plans,
  public.plan_features,
  public.subscriptions
from anon, authenticated;
grant select on public.plans, public.plan_features, public.subscriptions to authenticated;

revoke all on
  public.organizations,
  public.memberships,
  public.contacts,
  public.customers,
  public.locations,
  public.tags,
  public.customer_tags,
  public.notes,
  public.notifications
from anon, authenticated;
grant select on public.organizations, public.memberships to authenticated;
grant select, insert, update, delete on
  public.contacts,
  public.customers,
  public.locations,
  public.tags,
  public.customer_tags,
  public.notes,
  public.notifications
to authenticated;
grant all on all tables in schema public to service_role;

grant usage on schema rbac to supabase_auth_admin, authenticated;
grant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function rbac.custom_access_token_hook(jsonb) from authenticated, anon, public;
grant select on rbac.user_roles to supabase_auth_admin;
revoke all on rbac.user_roles from authenticated, anon, public;
revoke execute on function rbac.authorize(rbac.app_permission) from public, anon;
grant execute on function rbac.authorize(rbac.app_permission) to authenticated;

revoke execute on function public.rs_workspace_summary(jsonb) from public, anon, authenticated;
grant execute on function public.rs_workspace_summary(jsonb) to authenticated;

revoke execute on function "public"."search_notes"(extensions.vector, integer) from public, anon;
grant execute on function "public"."search_notes"(extensions.vector, integer) to authenticated, service_role;

revoke execute on function better_supabase.track_realtime(regclass, text, text) from public, anon, authenticated;
revoke execute on function better_supabase.untrack_realtime(regclass) from public, anon, authenticated;

revoke execute on function public.customers_by_status(text, integer) from public, anon;
grant execute on function public.customers_by_status(text, integer) to authenticated, service_role;
revoke execute on function public.customer_note_counts(uuid[]) from public, anon;
grant execute on function public.customer_note_counts(uuid[]) to authenticated, service_role;
