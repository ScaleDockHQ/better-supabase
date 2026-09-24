-- Tenants come from a top-level claim (custom access token hook) or from
-- app_metadata (set through the Auth admin API).
create or replace function better_supabase.current_org_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(coalesce(auth.jwt() ->> 'org_id', auth.jwt() -> 'app_metadata' ->> 'org_id'), '')::uuid
$$;
