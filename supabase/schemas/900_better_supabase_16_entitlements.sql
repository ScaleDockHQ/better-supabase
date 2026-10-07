-- better-supabase module: entitlements (0.5.1)
-- @bs-module entitlements@1 managed
-- Active Stripe entitlements per tenant from the Stripe Sync Engine, feature_claims() for the access token hook, and has_entitlement() and tenant_ids_with_entitlement() for RLS.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;

-- Feature keys of the tenant's active plan (entitlements.source.plans):
-- public.subscriptions gives the plan, public.plan_features its features.
create or replace function better_supabase.tenant_entitlements(tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct f."feature_key"::text order by f."feature_key"::text), '{}')
    from "public"."subscriptions" s
    join "public"."plan_features" f on f."plan_key"::text = s."plan_key"::text
    where s."organization_id" = tenant_entitlements.tenant
      and s."status"::text = any (array['active', 'trialing']::text[])
      and f."included"
      and f."feature_key" is not null
$$;

revoke execute on function better_supabase.tenant_entitlements(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlements(uuid) to service_role, supabase_auth_admin;

-- The value of a feature for the tenant (entitlements.source.plans.features.value):
-- the largest number when several active plans set it, else the first
-- plan's value; true for a feature whose value is null, null without it.
create or replace function better_supabase.tenant_entitlement_value(tenant uuid, key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(to_jsonb(f."value"), 'true'::jsonb)
    from "public"."subscriptions" s
    join "public"."plan_features" f on f."plan_key"::text = s."plan_key"::text
    where s."organization_id" = tenant_entitlement_value.tenant
      and s."status"::text = any (array['active', 'trialing']::text[])
      and f."included"
      and f."feature_key"::text = tenant_entitlement_value.key
    order by case when jsonb_typeof(to_jsonb(f."value")) = 'number' then (to_jsonb(f."value") #>> '{}')::numeric end desc nulls last,
      s."plan_key"::text
    limit 1
$$;

revoke execute on function better_supabase.tenant_entitlement_value(uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlement_value(uuid, text) to service_role;

-- The tenant's active plan keys, so other modules (usage quotas) can match a
-- plan by its key as well as by its features.
create or replace function better_supabase.tenant_plans(tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct s."plan_key"::text order by s."plan_key"::text), '{}')
    from "public"."subscriptions" s
    where s."organization_id" = tenant_plans.tenant
      and s."status"::text = any (array['active', 'trialing']::text[])
      and s."plan_key" is not null
$$;

revoke execute on function better_supabase.tenant_plans(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_plans(uuid) to service_role;

-- using ((select better_supabase.has_entitlement(organization_id, 'exports')))
create or replace function better_supabase.has_entitlement(tenant uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select better_supabase.has_organization_role(tenant)
    and key = any (better_supabase.tenant_entitlements(tenant))
$$;

revoke execute on function better_supabase.has_entitlement(uuid, text) from public, anon;
grant execute on function better_supabase.has_entitlement(uuid, text) to authenticated, service_role;

-- The value of a feature for a member of the tenant: a number or text from
-- the plan catalog's value column, true for a feature without one, null
-- when the tenant lacks it or the caller is not a member.
create or replace function better_supabase.entitlement_value(tenant uuid, key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when better_supabase.has_organization_role(tenant) then better_supabase.tenant_entitlement_value(tenant, key) end
$$;

revoke execute on function better_supabase.entitlement_value(uuid, text) from public, anon;
grant execute on function better_supabase.entitlement_value(uuid, text) to authenticated, service_role;

-- Every tenant of the caller with `key`, for one set check per query instead of
-- one call per row:
--   using (organization_id in (select better_supabase.tenant_ids_with_entitlement('exports')))
create or replace function better_supabase.tenant_ids_with_entitlement(key text)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select t.id from better_supabase.member_organization_ids() as t(id)
  where key = any (better_supabase.tenant_entitlements(t.id))
$$;

revoke execute on function better_supabase.tenant_ids_with_entitlement(text) from public, anon;
grant execute on function better_supabase.tenant_ids_with_entitlement(text) to authenticated, service_role;

-- The `features` claim: { [tenant id]: lookup keys }, read by
-- hasEntitlement(). Tenants without entitlements are left out. Call it from
-- your custom access token hook:
--   return jsonb_set(event, '{claims,features}',
--     better_supabase.feature_claims((event ->> 'user_id')::uuid));
create or replace function better_supabase.feature_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(r.tenant, to_jsonb(r.keys)), '{}'::jsonb)
  from (
    select m."organization_id"::text as tenant, e.keys
    from "public"."memberships" m
    cross join lateral (select better_supabase.tenant_entitlements(m."organization_id") as keys) e
    where m."user_id" = feature_claims.user_id
      and cardinality(e.keys) > 0
    order by 1
  ) r
$$;

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;

-- sql.modules.entitlements.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."tenant_entitlements"(tenant uuid)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tenant_entitlements"($1) $$;
revoke execute on function "api"."tenant_entitlements"(uuid) from public, anon, authenticated;
grant execute on function "api"."tenant_entitlements"(uuid) to service_role;

create or replace function "api"."tenant_entitlement_value"(tenant uuid, key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tenant_entitlement_value"($1, $2) $$;
revoke execute on function "api"."tenant_entitlement_value"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."tenant_entitlement_value"(uuid, text) to service_role;

create or replace function "api"."tenant_plans"(tenant uuid)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tenant_plans"($1) $$;
revoke execute on function "api"."tenant_plans"(uuid) from public, anon, authenticated;
grant execute on function "api"."tenant_plans"(uuid) to service_role;

create or replace function "api"."has_entitlement"(tenant uuid, key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."has_entitlement"($1, $2) $$;
revoke execute on function "api"."has_entitlement"(uuid, text) from public, anon;
grant execute on function "api"."has_entitlement"(uuid, text) to authenticated, service_role;

create or replace function "api"."entitlement_value"(tenant uuid, key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."entitlement_value"($1, $2) $$;
revoke execute on function "api"."entitlement_value"(uuid, text) from public, anon;
grant execute on function "api"."entitlement_value"(uuid, text) to authenticated, service_role;

create or replace function "api"."tenant_ids_with_entitlement"(key text)
returns setof uuid
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."tenant_ids_with_entitlement"($1) $$;
revoke execute on function "api"."tenant_ids_with_entitlement"(text) from public, anon;
grant execute on function "api"."tenant_ids_with_entitlement"(text) to authenticated, service_role;

create or replace function "api"."feature_claims"(user_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."feature_claims"($1) $$;
revoke execute on function "api"."feature_claims"(uuid) from public, anon, authenticated;
grant execute on function "api"."feature_claims"(uuid) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
