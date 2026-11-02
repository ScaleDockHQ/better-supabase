-- better-supabase module: seeds
-- @bsb-block seeds@1 managed
-- @bsb-hash sha256:e3ee57f3e6959e24446ba9e0a5f861500727ced9dc9b4bbf23ff77b1e4ec2b8b
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Applies the defaults of every installed module to an organization. Call it
-- from the organization's create hook or with `better-supabase db seed --defaults`.
create or replace function "better_supabase".seed_tenant_defaults(p_tenant uuid, p_variants jsonb default '{}'::jsonb, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  null;
end;
$$;
revoke execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
