-- ==== alone: throws
-- The entitlements module needs auth.entitlements.customer: the table.column with each tenant's Stripe customer id. With the managed billing or organizations module it defaults to that module's customer column.

-- ==== with every module: schema supabase/schemas/900_better_supabase_16_entitlements.sql
-- better-supabase module: entitlements
-- @bsb-block entitlements@1 managed
-- Active Stripe entitlements per tenant from the Stripe Sync Engine, feature_claims() for the access token hook, and has_entitlement() and tenant_ids_with_entitlement() for RLS.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;

-- Lookup keys of the tenant's active entitlements, from the Stripe Sync
-- Engine's stripe.active_entitlements. Empty before the engine is installed.
create or replace function better_supabase.tenant_entitlements(tenant uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer_id text := better_supabase.tenant_stripe_customer(tenant);
begin
  if customer_id is null or to_regclass('stripe.active_entitlements') is null then
    return '{}';
  end if;
  return coalesce((
    select array_agg(distinct e.lookup_key order by e.lookup_key)
    from stripe.active_entitlements e
    where e.customer = customer_id
      and e.lookup_key is not null
  ), '{}');
end
$$;

revoke execute on function better_supabase.tenant_entitlements(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlements(uuid) to service_role, supabase_auth_admin;

-- The value of a feature for the tenant: true when it has the key, null
-- otherwise. Numeric limits come from the plan catalog's value column.
create or replace function better_supabase.tenant_entitlement_value(tenant uuid, key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when key = any (better_supabase.tenant_entitlements(tenant)) then 'true'::jsonb end
$$;

revoke execute on function better_supabase.tenant_entitlement_value(uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.tenant_entitlement_value(uuid, text) to service_role;

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
    from "better_supabase"."memberships" m
    cross join lateral (select better_supabase.tenant_entitlements(m."organization_id") as keys) e
    where m."user_id" = feature_claims.user_id
      and cardinality(e.keys) > 0
    order by 1
  ) r
$$;

revoke execute on function better_supabase.feature_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.feature_claims(uuid) to service_role, supabase_auth_admin;

-- config.entitlements: better_supabase.billing_customers.stripe_customer_id
create or replace function better_supabase.tenant_stripe_customer(tenant uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (select t."stripe_customer_id" from "better_supabase"."billing_customers" t where t."organization_id" = tenant);
end
$$;

create or replace function better_supabase.stripe_customer_tenants(customer text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select t."organization_id" from "better_supabase"."billing_customers" t where t."stripe_customer_id" = customer;
end
$$;

-- Users whose features claim carries the customer's entitlements, for
-- invalidating their sessions after entitlements.active_entitlement_summary.updated.
create or replace function better_supabase.entitlement_members(customer text)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct m."user_id"
  from "better_supabase"."memberships" m
  where m."organization_id" in (select better_supabase.stripe_customer_tenants(customer))
$$;

revoke execute on function better_supabase.tenant_stripe_customer(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.stripe_customer_tenants(text) from public, anon, authenticated;
revoke execute on function better_supabase.entitlement_members(text) from public, anon, authenticated;
grant execute on function better_supabase.entitlement_members(text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_16_entitlements.sql
-- better-supabase module: entitlements
-- @bsb-block-data entitlements
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('entitlements', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: throws
-- The entitlements module needs auth.entitlements.customer: the table.column with each tenant's Stripe customer id. With the managed billing or organizations module it defaults to that module's customer column.

-- ==== api schema: throws
-- The entitlements module needs auth.entitlements.customer: the table.column with each tenant's Stripe customer id. With the managed billing or organizations module it defaults to that module's customer column.
