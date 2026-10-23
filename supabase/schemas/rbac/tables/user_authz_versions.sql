-- A per-user authorization version, a neutral fixture for
-- `subscribeAuthzVersions`. A change to a user's role bumps the version, the
-- access token hook copies it into the `authz_ver` claim, and the broadcast
-- trigger tells servers to evict the user from their version cache.
create table rbac.user_authz_versions (
  user_id uuid primary key references auth.users on delete cascade,
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

create trigger user_authz_versions_broadcast
  after insert or update on rbac.user_authz_versions
  for each row execute function rbac.broadcast_authz_version();

alter table rbac.user_authz_versions enable row level security;

create policy "Auth admin reads authorization versions" on rbac.user_authz_versions
  as permissive for select
  to supabase_auth_admin
  using (true);

grant select on rbac.user_authz_versions to supabase_auth_admin;

revoke all on rbac.user_authz_versions from authenticated, anon, public;
