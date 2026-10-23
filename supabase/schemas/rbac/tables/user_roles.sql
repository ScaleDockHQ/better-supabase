-- Role-based access control, following Supabase's RBAC guide: roles live in a
-- table, the custom access token hook copies the user's role into a top-level
-- `user_role` claim, and `authorize()` checks a permission for RLS. The hook
-- also writes the per-organization `memberships` and `features` claims the
-- Next.js example reads. It is a minimal fixture: apps with an authorization
-- provider take the hook, `role_permissions`, `authorize()` and the policies
-- from the provider and keep none of this. The permission rows are data, so
-- they live in the baseline migration.
create table rbac.user_roles (
  user_id uuid primary key references auth.users on delete cascade,
  role rbac.app_role not null
);

create trigger user_roles_bump_authz_version
  after insert or update or delete on rbac.user_roles
  for each row execute function rbac.bump_authz_version();

alter table rbac.user_roles enable row level security;

create policy "Auth admin reads user roles" on rbac.user_roles
  as permissive for select
  to supabase_auth_admin
  using (true);

grant select on rbac.user_roles to supabase_auth_admin;

revoke all on rbac.user_roles from authenticated, anon, public;
