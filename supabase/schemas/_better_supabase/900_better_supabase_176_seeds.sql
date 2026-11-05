-- better-supabase module: seeds
-- @bsb-block seeds@1 managed
-- @bsb-hash sha256:285aa4fd85de8c980bac44cb7c13dd7eeddbfc73c2fb8918444156de5adc212b
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
  perform "better_supabase"."seed_attachments_defaults"(p_tenant, p_variants ->> 'attachments', p_locale);
  perform "better_supabase"."seed_inbox_defaults"(p_tenant, p_variants ->> 'inbox', p_locale);
  perform "better_supabase"."seed_calendar_defaults"(p_tenant, p_variants ->> 'calendar', p_locale);
  perform "better_supabase"."seed_cases_defaults"(p_tenant, p_variants ->> 'cases', p_locale);
  perform "better_supabase"."seed_pipelines_defaults"(p_tenant, p_variants ->> 'pipelines', p_locale);
  perform "better_supabase"."seed_risks_defaults"(p_tenant, p_variants ->> 'risks', p_locale);
  perform "better_supabase"."seed_tax_defaults"(p_tenant, p_variants ->> 'tax', p_locale);
  perform "better_supabase"."seed_accounting_defaults"(p_tenant, p_variants ->> 'accounting', p_locale);
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
