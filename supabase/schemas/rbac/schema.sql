-- Kept in its own schema so it stays out of the generated `public` types.
create schema if not exists rbac;

grant usage on schema rbac to supabase_auth_admin, authenticated;
