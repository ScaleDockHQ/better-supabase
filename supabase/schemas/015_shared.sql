create schema if not exists better_supabase;

-- Kept in its own schema so it stays out of the generated `public` types.
create schema if not exists rbac;

-- Tenants come from a top-level claim (custom access token hook) or from
-- app_metadata (set through the Auth admin API).
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '')::uuid
$$;
