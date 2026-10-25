-- ==== alone: schema supabase/schemas/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block vercel-marketplace@2 managed
-- @bsb-hash sha256:ec4a98ace9c843299a6b22c887be0387a4b58a0dabf58b65cc42b030a825d512
-- Vercel Marketplace provider state: installations per configuration id, provisioned resources with their tenant and secret handles, access tokens sealed in Vault, plans, invoices kept by event time and meter reports sent to Vercel per period. Only the service role calls it; createVercelMarketplace() in better-supabase/blocks/vercel-marketplace serves the Partner API, verifies webhooks, exchanges SSO codes and reports usage.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Vercel Marketplace: the teams that installed the integration, the resources
-- they provisioned, the plans, Vercel's invoices and the meter reports sent to
-- Vercel. Only the service role writes; the app's own tables point at an
-- installation through its tenant.
create table if not exists "better_supabase"."marketplace_installations" (
  "id" uuid primary key default gen_random_uuid(),
  "configuration_id" text not null unique,
  "team_id" text,
  "user_id" text,
  "tenant" text,
  "status" text not null default 'active' check ("status" in ('active', 'suspended', 'removed')),
  "metadata" jsonb not null default '{}'::jsonb,
  "removed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_installations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_installations";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_installations"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant_created: the installation created its tenant, so removing the
-- installation may delete it. access_token_secret_id: the Vault secret with
-- the access token Vercel handed out at installation.
alter table "better_supabase"."marketplace_installations" add column if not exists "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_installations" add column if not exists "access_token_secret_id" uuid;
create index if not exists marketplace_installations_tenant_idx on "better_supabase"."marketplace_installations" ("tenant") where "tenant" is not null;
alter table "better_supabase"."marketplace_installations" enable row level security;
revoke all on "better_supabase"."marketplace_installations" from anon, authenticated;
grant all on "better_supabase"."marketplace_installations" to service_role;

create table if not exists "better_supabase"."marketplace_plans" (
  "id" text primary key,
  "name" text not null,
  "kind" text not null default 'subscription' check ("kind" in ('subscription', 'prepayment')),
  "details" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_plans" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_plans";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_plans"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_plans" enable row level security;
revoke all on "better_supabase"."marketplace_plans" from anon, authenticated;
grant all on "better_supabase"."marketplace_plans" to service_role;

create table if not exists "better_supabase"."marketplace_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "name" text not null,
  "plan_id" text references "better_supabase"."marketplace_plans" ("id") on delete set null,
  "status" text not null default 'ready' check ("status" in ('pending', 'ready', 'suspended', 'deleted')),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_resources" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_resources";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_resources"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant: the app's tenant the provision hook created or chose for the
-- resource. secret_refs: the app's handles for the secrets it handed out
-- (never the values), so a rotation can revoke the previous ones.
alter table "better_supabase"."marketplace_resources" add column if not exists "tenant" text;
alter table "better_supabase"."marketplace_resources" add column if not exists "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_resources" add column if not exists "secret_refs" jsonb not null default '[]'::jsonb;
create index if not exists marketplace_resources_plan_idx on "better_supabase"."marketplace_resources" ("plan_id") where "plan_id" is not null;
alter table "better_supabase"."marketplace_resources" enable row level security;
revoke all on "better_supabase"."marketplace_resources" from anon, authenticated;
grant all on "better_supabase"."marketplace_resources" to service_role;

create table if not exists "better_supabase"."marketplace_invoices" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "state" text not null default 'pending',
  "period_start" timestamptz,
  "period_end" timestamptz,
  "total" numeric not null default 0,
  "currency" text not null default 'usd',
  "items" jsonb not null default '[]'::jsonb,
  "event_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_invoices" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_invoices";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_invoices"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_invoices" enable row level security;
revoke all on "better_supabase"."marketplace_invoices" from anon, authenticated;
grant all on "better_supabase"."marketplace_invoices" to service_role;

create table if not exists "better_supabase"."marketplace_meter_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "resource_external_id" text not null default '',
  "meter_id" text not null,
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "quantity" numeric not null check ("quantity" >= 0),
  "reported_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end")
);
-- reported_quantity: the total Vercel accepted for the period, so the next
-- report sends the rest as dayValue.
alter table "better_supabase"."marketplace_meter_reports" add column if not exists "reported_quantity" numeric not null default 0;
alter table "better_supabase"."marketplace_meter_reports" enable row level security;
revoke all on "better_supabase"."marketplace_meter_reports" from anon, authenticated;
grant all on "better_supabase"."marketplace_meter_reports" to service_role;

-- Records an installation (or reactivates a removed one) for a configuration id.
create or replace function "better_supabase"."upsert_marketplace_installation"(configuration_id text, team_id text default null, user_id text default null, tenant text default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "better_supabase"."marketplace_installations" ("configuration_id", "team_id", "user_id", "tenant", "metadata")
  values (upsert_marketplace_installation.configuration_id, upsert_marketplace_installation.team_id, upsert_marketplace_installation.user_id, upsert_marketplace_installation.tenant, coalesce(upsert_marketplace_installation.metadata, '{}'::jsonb))
  on conflict ("configuration_id") do update set
    "team_id" = coalesce(excluded."team_id", "better_supabase"."marketplace_installations"."team_id"),
    "user_id" = coalesce(excluded."user_id", "better_supabase"."marketplace_installations"."user_id"),
    "tenant" = coalesce(excluded."tenant", "better_supabase"."marketplace_installations"."tenant"),
    "metadata" = "better_supabase"."marketplace_installations"."metadata" || excluded."metadata",
    "status" = case when "better_supabase"."marketplace_installations"."status" = 'removed' then 'active' else "better_supabase"."marketplace_installations"."status" end,
    "removed_at" = case when "better_supabase"."marketplace_installations"."status" = 'removed' then null else "better_supabase"."marketplace_installations"."removed_at" end
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- The installation for a configuration id, or null.
create or replace function "better_supabase"."marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (select to_jsonb(x) from "better_supabase"."marketplace_installations" x where x."configuration_id" = marketplace_installation.configuration_id);
end;
$$;

-- Marks the installation removed and its resources deleted (Vercel
-- integration-configuration.removed); the rows stay for invoices and audit.
create or replace function "better_supabase"."remove_marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_installations" x set "status" = 'removed', "removed_at" = coalesce(x."removed_at", now())
  where x."configuration_id" = remove_marketplace_installation.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  if v_row."access_token_secret_id" is not null then
    delete from vault.secrets vs where vs.id = v_row."access_token_secret_id";
    update "better_supabase"."marketplace_installations" x set "access_token_secret_id" = null where x."id" = v_row."id"
    returning * into v_row;
  end if;
  update "better_supabase"."marketplace_resources" y set "status" = 'deleted' where y."installation_id" = v_row."id" and y."status" <> 'deleted';
  null;
  return to_jsonb(v_row);
end;
$$;

-- Creates or updates a plan Vercel bills against.
create or replace function "better_supabase"."upsert_marketplace_plan"(id text, name text, kind text default 'subscription', details jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."marketplace_plans";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "better_supabase"."marketplace_plans" ("id", "name", "kind", "details")
  values (upsert_marketplace_plan.id, upsert_marketplace_plan.name, coalesce(upsert_marketplace_plan.kind, 'subscription'), coalesce(upsert_marketplace_plan.details, '{}'::jsonb))
  on conflict ("id") do update set "name" = excluded."name", "kind" = excluded."kind", "details" = excluded."details"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Provisions or updates a resource of an installation.
create or replace function "better_supabase"."upsert_marketplace_resource"(configuration_id text, external_id text, name text, plan_id text default null, status text default 'ready', metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = upsert_marketplace_resource.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_resources" ("installation_id", "external_id", "name", "plan_id", "status", "metadata")
  values (v_installation, upsert_marketplace_resource.external_id, upsert_marketplace_resource.name, upsert_marketplace_resource.plan_id, coalesce(upsert_marketplace_resource.status, 'ready'), coalesce(upsert_marketplace_resource.metadata, '{}'::jsonb))
  on conflict ("installation_id", "external_id") do update set
    "name" = excluded."name",
    "plan_id" = coalesce(excluded."plan_id", "better_supabase"."marketplace_resources"."plan_id"),
    "status" = excluded."status",
    "metadata" = "better_supabase"."marketplace_resources"."metadata" || excluded."metadata"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Stores an invoice Vercel sent, or its newer state. An older event never
-- overwrites a newer one (event_at guard), so redelivery in any order is safe.
create or replace function "better_supabase"."record_marketplace_invoice"(configuration_id text, external_id text, state text, period_start timestamptz default null, period_end timestamptz default null, total numeric default null, currency text default null, items jsonb default null, event_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_invoices";
  v_before text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_invoice.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  select y."state" into v_before from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  insert into "better_supabase"."marketplace_invoices" ("installation_id", "external_id", "state", "period_start", "period_end", "total", "currency", "items", "event_at")
  values (v_installation, record_marketplace_invoice.external_id, record_marketplace_invoice.state, record_marketplace_invoice.period_start, record_marketplace_invoice.period_end, coalesce(record_marketplace_invoice.total, 0), coalesce(record_marketplace_invoice.currency, 'usd'), coalesce(record_marketplace_invoice.items, '[]'::jsonb), coalesce(record_marketplace_invoice.event_at, now()))
  on conflict ("installation_id", "external_id") do update set
    "state" = excluded."state",
    "period_start" = coalesce(excluded."period_start", "better_supabase"."marketplace_invoices"."period_start"),
    "period_end" = coalesce(excluded."period_end", "better_supabase"."marketplace_invoices"."period_end"),
    "total" = case when record_marketplace_invoice.total is null then "better_supabase"."marketplace_invoices"."total" else excluded."total" end,
    "currency" = case when record_marketplace_invoice.currency is null then "better_supabase"."marketplace_invoices"."currency" else excluded."currency" end,
    "items" = case when record_marketplace_invoice.items is null then "better_supabase"."marketplace_invoices"."items" else excluded."items" end,
    "event_at" = excluded."event_at"
  where "better_supabase"."marketplace_invoices"."event_at" <= excluded."event_at"
  returning * into v_row;
  if v_row."id" is null then
    select y.* into v_row from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  elsif v_before is distinct from v_row."state" then
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Records a meter quantity for a period before it is sent to Vercel. The same
-- installation, resource, meter and period keep one row, so a retry updates it.
create or replace function "better_supabase"."record_marketplace_meter_report"(configuration_id text, meter_id text, period_start timestamptz, period_end timestamptz, quantity numeric, resource_external_id text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_meter_reports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_meter_report.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_meter_reports" ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end", "quantity")
  values (v_installation, coalesce(record_marketplace_meter_report.resource_external_id, ''), record_marketplace_meter_report.meter_id, record_marketplace_meter_report.period_start, record_marketplace_meter_report.period_end, record_marketplace_meter_report.quantity)
  on conflict ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end") do update set
    "quantity" = excluded."quantity",
    "reported_at" = case when "better_supabase"."marketplace_meter_reports"."quantity" = excluded."quantity" then "better_supabase"."marketplace_meter_reports"."reported_at" end
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Marks reports as sent once Vercel accepted them, at their current quantity.
create or replace function "better_supabase"."mark_marketplace_meter_reported"(ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_meter_reports" x set "reported_at" = now(), "reported_quantity" = x."quantity" where x."id" = any (mark_marketplace_meter_reported.ids) and x."reported_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Records what Vercel accepted: reports is [{ id, quantity }], the totals
-- sent. A report whose quantity grew since stays unreported, with the rest
-- left for the next call.
create or replace function "better_supabase"."mark_marketplace_meter_sent"(reports jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_meter_reports" x set
    "reported_quantity" = (y.value ->> 'quantity')::numeric,
    "reported_at" = case when x."quantity" = (y.value ->> 'quantity')::numeric then now() end
  from jsonb_array_elements(coalesce(mark_marketplace_meter_sent.reports, '[]'::jsonb)) y
  where x."id" = (y.value ->> 'id')::uuid;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Reports Vercel has not accepted yet, oldest period first.
create or replace function "better_supabase"."unreported_marketplace_meter_reports"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."period_start", x."meter_id"), '[]'::jsonb)
    from "better_supabase"."marketplace_meter_reports" x join "better_supabase"."marketplace_installations" y on y."id" = x."installation_id"
    where y."configuration_id" = unreported_marketplace_meter_reports.configuration_id and x."reported_at" is null
  );
end;
$$;

-- Seals the access token Vercel handed out for an installation in Vault.
create or replace function "better_supabase"."seal_marketplace_access_token"(configuration_id text, access_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."marketplace_installations" x where x."configuration_id" = seal_marketplace_access_token.configuration_id;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  if v_row."access_token_secret_id" is null then
    update "better_supabase"."marketplace_installations" x set "access_token_secret_id" = vault.create_secret(
      seal_marketplace_access_token.access_token,
      'bs:marketplace:' || v_row."configuration_id" || ':' || gen_random_uuid()::text,
      'better-supabase Vercel Marketplace access token'
    ) where x."id" = v_row."id";
  else
    perform vault.update_secret(v_row."access_token_secret_id", seal_marketplace_access_token.access_token);
  end if;
end;
$$;

-- The sealed access token of an installation, or null.
create or replace function "better_supabase"."marketplace_access_token"(configuration_id text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select ds.decrypted_secret from "better_supabase"."marketplace_installations" x
    join vault.decrypted_secrets ds on ds.id = x."access_token_secret_id"
    where x."configuration_id" = marketplace_access_token.configuration_id
  );
end;
$$;

-- Links the app's tenant to an installation; created says the installation
-- made it, so removing the installation may delete it.
create or replace function "better_supabase"."link_marketplace_tenant"(configuration_id text, tenant text, created boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_installations" x set "tenant" = link_marketplace_tenant.tenant, "tenant_created" = coalesce(link_marketplace_tenant.created, false)
  where x."configuration_id" = link_marketplace_tenant.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Stores the tenant and secret handles the provision hook returned; null
-- keeps the stored value.
create or replace function "better_supabase"."set_marketplace_resource_state"(configuration_id text, external_id text, tenant text default null, tenant_created boolean default null, secret_refs text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_resources" y set
    "tenant" = coalesce(set_marketplace_resource_state.tenant, y."tenant"),
    "tenant_created" = coalesce(set_marketplace_resource_state.tenant_created, y."tenant_created"),
    "secret_refs" = coalesce(to_jsonb(set_marketplace_resource_state.secret_refs), y."secret_refs")
  from "better_supabase"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = set_marketplace_resource_state.configuration_id
    and y."external_id" = set_marketplace_resource_state.external_id
  returning y.* into v_row;
  if v_row."id" is null then
    raise exception 'The installation has no resource with this id' using errcode = 'P0002', hint = 'MARKETPLACE_RESOURCE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- A resource of an installation, or null.
create or replace function "better_supabase"."marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select to_jsonb(y) from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resource.configuration_id and y."external_id" = marketplace_resource.external_id
  );
end;
$$;

-- The resources of an installation that are not deleted.
create or replace function "better_supabase"."marketplace_resources"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(y) order by y."created_at"), '[]'::jsonb)
    from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resources.configuration_id and y."status" <> 'deleted'
  );
end;
$$;

-- Marks a resource deleted; the row stays for invoices and audit.
create or replace function "better_supabase"."delete_marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_resources" y set "status" = 'deleted'
  from "better_supabase"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = delete_marketplace_resource.configuration_id
    and y."external_id" = delete_marketplace_resource.external_id
  returning y.* into v_row;
  return case when v_row."id" is null then null else to_jsonb(v_row) end;
end;
$$;

revoke execute on function "better_supabase"."upsert_marketplace_installation"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_installation"(text, text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_installation"(text) to service_role;
revoke execute on function "better_supabase"."remove_marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."remove_marketplace_installation"(text) to service_role;
revoke execute on function "better_supabase"."upsert_marketplace_plan"(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_plan"(text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) to service_role;
revoke execute on function "better_supabase"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) to service_role;
revoke execute on function "better_supabase"."mark_marketplace_meter_reported"(uuid[]) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_marketplace_meter_reported"(uuid[]) to service_role;
revoke execute on function "better_supabase"."unreported_marketplace_meter_reports"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."unreported_marketplace_meter_reports"(text) to service_role;
revoke execute on function "better_supabase"."mark_marketplace_meter_sent"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_marketplace_meter_sent"(jsonb) to service_role;
revoke execute on function "better_supabase"."seal_marketplace_access_token"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."seal_marketplace_access_token"(text, text) to service_role;
revoke execute on function "better_supabase"."marketplace_access_token"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_access_token"(text) to service_role;
revoke execute on function "better_supabase"."link_marketplace_tenant"(text, text, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."link_marketplace_tenant"(text, text, boolean) to service_role;
revoke execute on function "better_supabase"."set_marketplace_resource_state"(text, text, text, boolean, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."set_marketplace_resource_state"(text, text, text, boolean, text[]) to service_role;
revoke execute on function "better_supabase"."marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_resource"(text, text) to service_role;
revoke execute on function "better_supabase"."marketplace_resources"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_resources"(text) to service_role;
revoke execute on function "better_supabase"."delete_marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_marketplace_resource"(text, text) to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block-data vercel-marketplace
-- @bsb-hash sha256:eca90ca783032ddd52748019cbe99ad19f1851c3a083f1ad16f09d788b76da8b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('vercel-marketplace', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block vercel-marketplace@2 managed
-- @bsb-hash sha256:a34a26c35453a2cfe77d90bef2a948522df2c3b78d77137617fb6eceb2e8f091
-- Vercel Marketplace provider state: installations per configuration id, provisioned resources with their tenant and secret handles, access tokens sealed in Vault, plans, invoices kept by event time and meter reports sent to Vercel per period. Only the service role calls it; createVercelMarketplace() in better-supabase/blocks/vercel-marketplace serves the Partner API, verifies webhooks, exchanges SSO codes and reports usage.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Vercel Marketplace: the teams that installed the integration, the resources
-- they provisioned, the plans, Vercel's invoices and the meter reports sent to
-- Vercel. Only the service role writes; the app's own tables point at an
-- installation through its tenant.
create table if not exists "better_supabase"."marketplace_installations" (
  "id" uuid primary key default gen_random_uuid(),
  "configuration_id" text not null unique,
  "team_id" text,
  "user_id" text,
  "tenant" text,
  "status" text not null default 'active' check ("status" in ('active', 'suspended', 'removed')),
  "metadata" jsonb not null default '{}'::jsonb,
  "removed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_installations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_installations";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_installations"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant_created: the installation created its tenant, so removing the
-- installation may delete it. access_token_secret_id: the Vault secret with
-- the access token Vercel handed out at installation.
alter table "better_supabase"."marketplace_installations" add column if not exists "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_installations" add column if not exists "access_token_secret_id" uuid;
create index if not exists marketplace_installations_tenant_idx on "better_supabase"."marketplace_installations" ("tenant") where "tenant" is not null;
alter table "better_supabase"."marketplace_installations" enable row level security;
revoke all on "better_supabase"."marketplace_installations" from anon, authenticated;
grant all on "better_supabase"."marketplace_installations" to service_role;

create table if not exists "better_supabase"."marketplace_plans" (
  "id" text primary key,
  "name" text not null,
  "kind" text not null default 'subscription' check ("kind" in ('subscription', 'prepayment')),
  "details" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_plans" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_plans";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_plans"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_plans" enable row level security;
revoke all on "better_supabase"."marketplace_plans" from anon, authenticated;
grant all on "better_supabase"."marketplace_plans" to service_role;

create table if not exists "better_supabase"."marketplace_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "name" text not null,
  "plan_id" text references "better_supabase"."marketplace_plans" ("id") on delete set null,
  "status" text not null default 'ready' check ("status" in ('pending', 'ready', 'suspended', 'deleted')),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_resources" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_resources";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_resources"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant: the app's tenant the provision hook created or chose for the
-- resource. secret_refs: the app's handles for the secrets it handed out
-- (never the values), so a rotation can revoke the previous ones.
alter table "better_supabase"."marketplace_resources" add column if not exists "tenant" text;
alter table "better_supabase"."marketplace_resources" add column if not exists "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_resources" add column if not exists "secret_refs" jsonb not null default '[]'::jsonb;
create index if not exists marketplace_resources_plan_idx on "better_supabase"."marketplace_resources" ("plan_id") where "plan_id" is not null;
alter table "better_supabase"."marketplace_resources" enable row level security;
revoke all on "better_supabase"."marketplace_resources" from anon, authenticated;
grant all on "better_supabase"."marketplace_resources" to service_role;

create table if not exists "better_supabase"."marketplace_invoices" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "state" text not null default 'pending',
  "period_start" timestamptz,
  "period_end" timestamptz,
  "total" numeric not null default 0,
  "currency" text not null default 'usd',
  "items" jsonb not null default '[]'::jsonb,
  "event_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_invoices" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_invoices";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_invoices"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_invoices" enable row level security;
revoke all on "better_supabase"."marketplace_invoices" from anon, authenticated;
grant all on "better_supabase"."marketplace_invoices" to service_role;

create table if not exists "better_supabase"."marketplace_meter_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "resource_external_id" text not null default '',
  "meter_id" text not null,
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "quantity" numeric not null check ("quantity" >= 0),
  "reported_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end")
);
-- reported_quantity: the total Vercel accepted for the period, so the next
-- report sends the rest as dayValue.
alter table "better_supabase"."marketplace_meter_reports" add column if not exists "reported_quantity" numeric not null default 0;
alter table "better_supabase"."marketplace_meter_reports" enable row level security;
revoke all on "better_supabase"."marketplace_meter_reports" from anon, authenticated;
grant all on "better_supabase"."marketplace_meter_reports" to service_role;

-- Records an installation (or reactivates a removed one) for a configuration id.
create or replace function "better_supabase"."upsert_marketplace_installation"(configuration_id text, team_id text default null, user_id text default null, tenant text default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "better_supabase"."marketplace_installations" ("configuration_id", "team_id", "user_id", "tenant", "metadata")
  values (upsert_marketplace_installation.configuration_id, upsert_marketplace_installation.team_id, upsert_marketplace_installation.user_id, upsert_marketplace_installation.tenant, coalesce(upsert_marketplace_installation.metadata, '{}'::jsonb))
  on conflict ("configuration_id") do update set
    "team_id" = coalesce(excluded."team_id", "better_supabase"."marketplace_installations"."team_id"),
    "user_id" = coalesce(excluded."user_id", "better_supabase"."marketplace_installations"."user_id"),
    "tenant" = coalesce(excluded."tenant", "better_supabase"."marketplace_installations"."tenant"),
    "metadata" = "better_supabase"."marketplace_installations"."metadata" || excluded."metadata",
    "status" = case when "better_supabase"."marketplace_installations"."status" = 'removed' then 'active' else "better_supabase"."marketplace_installations"."status" end,
    "removed_at" = case when "better_supabase"."marketplace_installations"."status" = 'removed' then null else "better_supabase"."marketplace_installations"."removed_at" end
  returning * into v_row;
  perform "better_supabase".emit_event('marketplace_installation.upserted', jsonb_build_object('installationId', v_row."id", 'configurationId', v_row."configuration_id", 'teamId', v_row."team_id"), 'marketplace-installations/' || v_row."id", null, null, 'better-supabase/vercel-marketplace');
  perform better_supabase.audit_event(
    event_type => 'marketplace_installation.upserted',
    category => 'configuration',
    target_type => 'marketplace_installation',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('installationId', v_row."id", 'configurationId', v_row."configuration_id", 'teamId', v_row."team_id")
  );
  return to_jsonb(v_row);
end;
$$;

-- The installation for a configuration id, or null.
create or replace function "better_supabase"."marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (select to_jsonb(x) from "better_supabase"."marketplace_installations" x where x."configuration_id" = marketplace_installation.configuration_id);
end;
$$;

-- Marks the installation removed and its resources deleted (Vercel
-- integration-configuration.removed); the rows stay for invoices and audit.
create or replace function "better_supabase"."remove_marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_installations" x set "status" = 'removed', "removed_at" = coalesce(x."removed_at", now())
  where x."configuration_id" = remove_marketplace_installation.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  if v_row."access_token_secret_id" is not null then
    delete from vault.secrets vs where vs.id = v_row."access_token_secret_id";
    update "better_supabase"."marketplace_installations" x set "access_token_secret_id" = null where x."id" = v_row."id"
    returning * into v_row;
  end if;
  update "better_supabase"."marketplace_resources" y set "status" = 'deleted' where y."installation_id" = v_row."id" and y."status" <> 'deleted';
  perform "better_supabase".emit_event('marketplace_installation.removed', jsonb_build_object('installationId', v_row."id", 'configurationId', v_row."configuration_id", 'teamId', v_row."team_id"), 'marketplace-installations/' || v_row."id", null, null, 'better-supabase/vercel-marketplace');
  perform better_supabase.audit_event(
    event_type => 'marketplace_installation.removed',
    category => 'configuration',
    target_type => 'marketplace_installation',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('installationId', v_row."id", 'configurationId', v_row."configuration_id", 'teamId', v_row."team_id")
  );
  return to_jsonb(v_row);
end;
$$;

-- Creates or updates a plan Vercel bills against.
create or replace function "better_supabase"."upsert_marketplace_plan"(id text, name text, kind text default 'subscription', details jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."marketplace_plans";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "better_supabase"."marketplace_plans" ("id", "name", "kind", "details")
  values (upsert_marketplace_plan.id, upsert_marketplace_plan.name, coalesce(upsert_marketplace_plan.kind, 'subscription'), coalesce(upsert_marketplace_plan.details, '{}'::jsonb))
  on conflict ("id") do update set "name" = excluded."name", "kind" = excluded."kind", "details" = excluded."details"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Provisions or updates a resource of an installation.
create or replace function "better_supabase"."upsert_marketplace_resource"(configuration_id text, external_id text, name text, plan_id text default null, status text default 'ready', metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = upsert_marketplace_resource.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_resources" ("installation_id", "external_id", "name", "plan_id", "status", "metadata")
  values (v_installation, upsert_marketplace_resource.external_id, upsert_marketplace_resource.name, upsert_marketplace_resource.plan_id, coalesce(upsert_marketplace_resource.status, 'ready'), coalesce(upsert_marketplace_resource.metadata, '{}'::jsonb))
  on conflict ("installation_id", "external_id") do update set
    "name" = excluded."name",
    "plan_id" = coalesce(excluded."plan_id", "better_supabase"."marketplace_resources"."plan_id"),
    "status" = excluded."status",
    "metadata" = "better_supabase"."marketplace_resources"."metadata" || excluded."metadata"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Stores an invoice Vercel sent, or its newer state. An older event never
-- overwrites a newer one (event_at guard), so redelivery in any order is safe.
create or replace function "better_supabase"."record_marketplace_invoice"(configuration_id text, external_id text, state text, period_start timestamptz default null, period_end timestamptz default null, total numeric default null, currency text default null, items jsonb default null, event_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_invoices";
  v_before text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_invoice.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  select y."state" into v_before from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  insert into "better_supabase"."marketplace_invoices" ("installation_id", "external_id", "state", "period_start", "period_end", "total", "currency", "items", "event_at")
  values (v_installation, record_marketplace_invoice.external_id, record_marketplace_invoice.state, record_marketplace_invoice.period_start, record_marketplace_invoice.period_end, coalesce(record_marketplace_invoice.total, 0), coalesce(record_marketplace_invoice.currency, 'usd'), coalesce(record_marketplace_invoice.items, '[]'::jsonb), coalesce(record_marketplace_invoice.event_at, now()))
  on conflict ("installation_id", "external_id") do update set
    "state" = excluded."state",
    "period_start" = coalesce(excluded."period_start", "better_supabase"."marketplace_invoices"."period_start"),
    "period_end" = coalesce(excluded."period_end", "better_supabase"."marketplace_invoices"."period_end"),
    "total" = case when record_marketplace_invoice.total is null then "better_supabase"."marketplace_invoices"."total" else excluded."total" end,
    "currency" = case when record_marketplace_invoice.currency is null then "better_supabase"."marketplace_invoices"."currency" else excluded."currency" end,
    "items" = case when record_marketplace_invoice.items is null then "better_supabase"."marketplace_invoices"."items" else excluded."items" end,
    "event_at" = excluded."event_at"
  where "better_supabase"."marketplace_invoices"."event_at" <= excluded."event_at"
  returning * into v_row;
  if v_row."id" is null then
    select y.* into v_row from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  elsif v_before is distinct from v_row."state" then
    perform "better_supabase".emit_event('marketplace_invoice.state_changed', jsonb_build_object('installationId', v_installation, 'invoiceId', v_row."id", 'externalId', v_row."external_id", 'state', v_row."state"), 'marketplace-invoices/' || v_row."id", null, null, 'better-supabase/vercel-marketplace');
  perform better_supabase.audit_event(
    event_type => 'marketplace_invoice.state_changed',
    category => 'billing',
    target_type => 'marketplace_invoice',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('installationId', v_installation, 'invoiceId', v_row."id", 'externalId', v_row."external_id", 'state', v_row."state")
  );
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Records a meter quantity for a period before it is sent to Vercel. The same
-- installation, resource, meter and period keep one row, so a retry updates it.
create or replace function "better_supabase"."record_marketplace_meter_report"(configuration_id text, meter_id text, period_start timestamptz, period_end timestamptz, quantity numeric, resource_external_id text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_meter_reports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_meter_report.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_meter_reports" ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end", "quantity")
  values (v_installation, coalesce(record_marketplace_meter_report.resource_external_id, ''), record_marketplace_meter_report.meter_id, record_marketplace_meter_report.period_start, record_marketplace_meter_report.period_end, record_marketplace_meter_report.quantity)
  on conflict ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end") do update set
    "quantity" = excluded."quantity",
    "reported_at" = case when "better_supabase"."marketplace_meter_reports"."quantity" = excluded."quantity" then "better_supabase"."marketplace_meter_reports"."reported_at" end
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Marks reports as sent once Vercel accepted them, at their current quantity.
create or replace function "better_supabase"."mark_marketplace_meter_reported"(ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_meter_reports" x set "reported_at" = now(), "reported_quantity" = x."quantity" where x."id" = any (mark_marketplace_meter_reported.ids) and x."reported_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Records what Vercel accepted: reports is [{ id, quantity }], the totals
-- sent. A report whose quantity grew since stays unreported, with the rest
-- left for the next call.
create or replace function "better_supabase"."mark_marketplace_meter_sent"(reports jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_meter_reports" x set
    "reported_quantity" = (y.value ->> 'quantity')::numeric,
    "reported_at" = case when x."quantity" = (y.value ->> 'quantity')::numeric then now() end
  from jsonb_array_elements(coalesce(mark_marketplace_meter_sent.reports, '[]'::jsonb)) y
  where x."id" = (y.value ->> 'id')::uuid;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Reports Vercel has not accepted yet, oldest period first.
create or replace function "better_supabase"."unreported_marketplace_meter_reports"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."period_start", x."meter_id"), '[]'::jsonb)
    from "better_supabase"."marketplace_meter_reports" x join "better_supabase"."marketplace_installations" y on y."id" = x."installation_id"
    where y."configuration_id" = unreported_marketplace_meter_reports.configuration_id and x."reported_at" is null
  );
end;
$$;

-- Seals the access token Vercel handed out for an installation in Vault.
create or replace function "better_supabase"."seal_marketplace_access_token"(configuration_id text, access_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."marketplace_installations" x where x."configuration_id" = seal_marketplace_access_token.configuration_id;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  if v_row."access_token_secret_id" is null then
    update "better_supabase"."marketplace_installations" x set "access_token_secret_id" = vault.create_secret(
      seal_marketplace_access_token.access_token,
      'bs:marketplace:' || v_row."configuration_id" || ':' || gen_random_uuid()::text,
      'better-supabase Vercel Marketplace access token'
    ) where x."id" = v_row."id";
  else
    perform vault.update_secret(v_row."access_token_secret_id", seal_marketplace_access_token.access_token);
  end if;
end;
$$;

-- The sealed access token of an installation, or null.
create or replace function "better_supabase"."marketplace_access_token"(configuration_id text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select ds.decrypted_secret from "better_supabase"."marketplace_installations" x
    join vault.decrypted_secrets ds on ds.id = x."access_token_secret_id"
    where x."configuration_id" = marketplace_access_token.configuration_id
  );
end;
$$;

-- Links the app's tenant to an installation; created says the installation
-- made it, so removing the installation may delete it.
create or replace function "better_supabase"."link_marketplace_tenant"(configuration_id text, tenant text, created boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_installations" x set "tenant" = link_marketplace_tenant.tenant, "tenant_created" = coalesce(link_marketplace_tenant.created, false)
  where x."configuration_id" = link_marketplace_tenant.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Stores the tenant and secret handles the provision hook returned; null
-- keeps the stored value.
create or replace function "better_supabase"."set_marketplace_resource_state"(configuration_id text, external_id text, tenant text default null, tenant_created boolean default null, secret_refs text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_resources" y set
    "tenant" = coalesce(set_marketplace_resource_state.tenant, y."tenant"),
    "tenant_created" = coalesce(set_marketplace_resource_state.tenant_created, y."tenant_created"),
    "secret_refs" = coalesce(to_jsonb(set_marketplace_resource_state.secret_refs), y."secret_refs")
  from "better_supabase"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = set_marketplace_resource_state.configuration_id
    and y."external_id" = set_marketplace_resource_state.external_id
  returning y.* into v_row;
  if v_row."id" is null then
    raise exception 'The installation has no resource with this id' using errcode = 'P0002', hint = 'MARKETPLACE_RESOURCE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- A resource of an installation, or null.
create or replace function "better_supabase"."marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select to_jsonb(y) from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resource.configuration_id and y."external_id" = marketplace_resource.external_id
  );
end;
$$;

-- The resources of an installation that are not deleted.
create or replace function "better_supabase"."marketplace_resources"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(y) order by y."created_at"), '[]'::jsonb)
    from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resources.configuration_id and y."status" <> 'deleted'
  );
end;
$$;

-- Marks a resource deleted; the row stays for invoices and audit.
create or replace function "better_supabase"."delete_marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_resources" y set "status" = 'deleted'
  from "better_supabase"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = delete_marketplace_resource.configuration_id
    and y."external_id" = delete_marketplace_resource.external_id
  returning y.* into v_row;
  return case when v_row."id" is null then null else to_jsonb(v_row) end;
end;
$$;

revoke execute on function "better_supabase"."upsert_marketplace_installation"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_installation"(text, text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_installation"(text) to service_role;
revoke execute on function "better_supabase"."remove_marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."remove_marketplace_installation"(text) to service_role;
revoke execute on function "better_supabase"."upsert_marketplace_plan"(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_plan"(text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) to service_role;
revoke execute on function "better_supabase"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) to service_role;
revoke execute on function "better_supabase"."mark_marketplace_meter_reported"(uuid[]) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_marketplace_meter_reported"(uuid[]) to service_role;
revoke execute on function "better_supabase"."unreported_marketplace_meter_reports"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."unreported_marketplace_meter_reports"(text) to service_role;
revoke execute on function "better_supabase"."mark_marketplace_meter_sent"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_marketplace_meter_sent"(jsonb) to service_role;
revoke execute on function "better_supabase"."seal_marketplace_access_token"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."seal_marketplace_access_token"(text, text) to service_role;
revoke execute on function "better_supabase"."marketplace_access_token"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_access_token"(text) to service_role;
revoke execute on function "better_supabase"."link_marketplace_tenant"(text, text, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."link_marketplace_tenant"(text, text, boolean) to service_role;
revoke execute on function "better_supabase"."set_marketplace_resource_state"(text, text, text, boolean, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."set_marketplace_resource_state"(text, text, text, boolean, text[]) to service_role;
revoke execute on function "better_supabase"."marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_resource"(text, text) to service_role;
revoke execute on function "better_supabase"."marketplace_resources"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_resources"(text) to service_role;
revoke execute on function "better_supabase"."delete_marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_marketplace_resource"(text, text) to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block-data vercel-marketplace
-- @bsb-hash sha256:eca90ca783032ddd52748019cbe99ad19f1851c3a083f1ad16f09d788b76da8b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('vercel-marketplace', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block vercel-marketplace@2 managed
-- @bsb-hash sha256:86926634821aa1c621c88246314453f78b05e0c61225c92f23fe5014aec176e7
-- Vercel Marketplace provider state: installations per configuration id, provisioned resources with their tenant and secret handles, access tokens sealed in Vault, plans, invoices kept by event time and meter reports sent to Vercel per period. Only the service role calls it; createVercelMarketplace() in better-supabase/blocks/vercel-marketplace serves the Partner API, verifies webhooks, exchanges SSO codes and reports usage.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Vercel Marketplace: the teams that installed the integration, the resources
-- they provisioned, the plans, Vercel's invoices and the meter reports sent to
-- Vercel. Only the service role writes; the app's own tables point at an
-- installation through its tenant.
create table if not exists "app_private"."marketplace_installations" (
  "id" uuid primary key default gen_random_uuid(),
  "configuration_id" text not null unique,
  "team_id" text,
  "user_id" text,
  "tenant" text,
  "status" text not null default 'active' check ("status" in ('active', 'suspended', 'removed')),
  "metadata" jsonb not null default '{}'::jsonb,
  "removed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
alter table "app_private"."marketplace_installations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."marketplace_installations";
create trigger bsb_updated_at before update on "app_private"."marketplace_installations"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant_created: the installation created its tenant, so removing the
-- installation may delete it. access_token_secret_id: the Vault secret with
-- the access token Vercel handed out at installation.
alter table "app_private"."marketplace_installations" add column if not exists "tenant_created" boolean not null default false;
alter table "app_private"."marketplace_installations" add column if not exists "access_token_secret_id" uuid;
create index if not exists marketplace_installations_tenant_idx on "app_private"."marketplace_installations" ("tenant") where "tenant" is not null;
alter table "app_private"."marketplace_installations" enable row level security;
revoke all on "app_private"."marketplace_installations" from anon, authenticated;
grant all on "app_private"."marketplace_installations" to service_role;

create table if not exists "app_private"."marketplace_plans" (
  "id" text primary key,
  "name" text not null,
  "kind" text not null default 'subscription' check ("kind" in ('subscription', 'prepayment')),
  "details" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now()
);
alter table "app_private"."marketplace_plans" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."marketplace_plans";
create trigger bsb_updated_at before update on "app_private"."marketplace_plans"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "app_private"."marketplace_plans" enable row level security;
revoke all on "app_private"."marketplace_plans" from anon, authenticated;
grant all on "app_private"."marketplace_plans" to service_role;

create table if not exists "app_private"."marketplace_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "app_private"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "name" text not null,
  "plan_id" text references "app_private"."marketplace_plans" ("id") on delete set null,
  "status" text not null default 'ready' check ("status" in ('pending', 'ready', 'suspended', 'deleted')),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "app_private"."marketplace_resources" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."marketplace_resources";
create trigger bsb_updated_at before update on "app_private"."marketplace_resources"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant: the app's tenant the provision hook created or chose for the
-- resource. secret_refs: the app's handles for the secrets it handed out
-- (never the values), so a rotation can revoke the previous ones.
alter table "app_private"."marketplace_resources" add column if not exists "tenant" text;
alter table "app_private"."marketplace_resources" add column if not exists "tenant_created" boolean not null default false;
alter table "app_private"."marketplace_resources" add column if not exists "secret_refs" jsonb not null default '[]'::jsonb;
create index if not exists marketplace_resources_plan_idx on "app_private"."marketplace_resources" ("plan_id") where "plan_id" is not null;
alter table "app_private"."marketplace_resources" enable row level security;
revoke all on "app_private"."marketplace_resources" from anon, authenticated;
grant all on "app_private"."marketplace_resources" to service_role;

create table if not exists "app_private"."marketplace_invoices" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "app_private"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "state" text not null default 'pending',
  "period_start" timestamptz,
  "period_end" timestamptz,
  "total" numeric not null default 0,
  "currency" text not null default 'usd',
  "items" jsonb not null default '[]'::jsonb,
  "event_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "app_private"."marketplace_invoices" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."marketplace_invoices";
create trigger bsb_updated_at before update on "app_private"."marketplace_invoices"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "app_private"."marketplace_invoices" enable row level security;
revoke all on "app_private"."marketplace_invoices" from anon, authenticated;
grant all on "app_private"."marketplace_invoices" to service_role;

create table if not exists "app_private"."marketplace_meter_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "app_private"."marketplace_installations" ("id") on delete cascade,
  "resource_external_id" text not null default '',
  "meter_id" text not null,
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "quantity" numeric not null check ("quantity" >= 0),
  "reported_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end")
);
-- reported_quantity: the total Vercel accepted for the period, so the next
-- report sends the rest as dayValue.
alter table "app_private"."marketplace_meter_reports" add column if not exists "reported_quantity" numeric not null default 0;
alter table "app_private"."marketplace_meter_reports" enable row level security;
revoke all on "app_private"."marketplace_meter_reports" from anon, authenticated;
grant all on "app_private"."marketplace_meter_reports" to service_role;

-- Records an installation (or reactivates a removed one) for a configuration id.
create or replace function "app_private"."upsert_marketplace_installation"(configuration_id text, team_id text default null, user_id text default null, tenant text default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "app_private"."marketplace_installations" ("configuration_id", "team_id", "user_id", "tenant", "metadata")
  values (upsert_marketplace_installation.configuration_id, upsert_marketplace_installation.team_id, upsert_marketplace_installation.user_id, upsert_marketplace_installation.tenant, coalesce(upsert_marketplace_installation.metadata, '{}'::jsonb))
  on conflict ("configuration_id") do update set
    "team_id" = coalesce(excluded."team_id", "app_private"."marketplace_installations"."team_id"),
    "user_id" = coalesce(excluded."user_id", "app_private"."marketplace_installations"."user_id"),
    "tenant" = coalesce(excluded."tenant", "app_private"."marketplace_installations"."tenant"),
    "metadata" = "app_private"."marketplace_installations"."metadata" || excluded."metadata",
    "status" = case when "app_private"."marketplace_installations"."status" = 'removed' then 'active' else "app_private"."marketplace_installations"."status" end,
    "removed_at" = case when "app_private"."marketplace_installations"."status" = 'removed' then null else "app_private"."marketplace_installations"."removed_at" end
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- The installation for a configuration id, or null.
create or replace function "app_private"."marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (select to_jsonb(x) from "app_private"."marketplace_installations" x where x."configuration_id" = marketplace_installation.configuration_id);
end;
$$;

-- Marks the installation removed and its resources deleted (Vercel
-- integration-configuration.removed); the rows stay for invoices and audit.
create or replace function "app_private"."remove_marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "app_private"."marketplace_installations" x set "status" = 'removed', "removed_at" = coalesce(x."removed_at", now())
  where x."configuration_id" = remove_marketplace_installation.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  if v_row."access_token_secret_id" is not null then
    delete from vault.secrets vs where vs.id = v_row."access_token_secret_id";
    update "app_private"."marketplace_installations" x set "access_token_secret_id" = null where x."id" = v_row."id"
    returning * into v_row;
  end if;
  update "app_private"."marketplace_resources" y set "status" = 'deleted' where y."installation_id" = v_row."id" and y."status" <> 'deleted';
  null;
  return to_jsonb(v_row);
end;
$$;

-- Creates or updates a plan Vercel bills against.
create or replace function "app_private"."upsert_marketplace_plan"(id text, name text, kind text default 'subscription', details jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."marketplace_plans";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "app_private"."marketplace_plans" ("id", "name", "kind", "details")
  values (upsert_marketplace_plan.id, upsert_marketplace_plan.name, coalesce(upsert_marketplace_plan.kind, 'subscription'), coalesce(upsert_marketplace_plan.details, '{}'::jsonb))
  on conflict ("id") do update set "name" = excluded."name", "kind" = excluded."kind", "details" = excluded."details"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Provisions or updates a resource of an installation.
create or replace function "app_private"."upsert_marketplace_resource"(configuration_id text, external_id text, name text, plan_id text default null, status text default 'ready', metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "app_private"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "app_private"."marketplace_installations" x where x."configuration_id" = upsert_marketplace_resource.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "app_private"."marketplace_resources" ("installation_id", "external_id", "name", "plan_id", "status", "metadata")
  values (v_installation, upsert_marketplace_resource.external_id, upsert_marketplace_resource.name, upsert_marketplace_resource.plan_id, coalesce(upsert_marketplace_resource.status, 'ready'), coalesce(upsert_marketplace_resource.metadata, '{}'::jsonb))
  on conflict ("installation_id", "external_id") do update set
    "name" = excluded."name",
    "plan_id" = coalesce(excluded."plan_id", "app_private"."marketplace_resources"."plan_id"),
    "status" = excluded."status",
    "metadata" = "app_private"."marketplace_resources"."metadata" || excluded."metadata"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Stores an invoice Vercel sent, or its newer state. An older event never
-- overwrites a newer one (event_at guard), so redelivery in any order is safe.
create or replace function "app_private"."record_marketplace_invoice"(configuration_id text, external_id text, state text, period_start timestamptz default null, period_end timestamptz default null, total numeric default null, currency text default null, items jsonb default null, event_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "app_private"."marketplace_invoices";
  v_before text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "app_private"."marketplace_installations" x where x."configuration_id" = record_marketplace_invoice.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  select y."state" into v_before from "app_private"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  insert into "app_private"."marketplace_invoices" ("installation_id", "external_id", "state", "period_start", "period_end", "total", "currency", "items", "event_at")
  values (v_installation, record_marketplace_invoice.external_id, record_marketplace_invoice.state, record_marketplace_invoice.period_start, record_marketplace_invoice.period_end, coalesce(record_marketplace_invoice.total, 0), coalesce(record_marketplace_invoice.currency, 'usd'), coalesce(record_marketplace_invoice.items, '[]'::jsonb), coalesce(record_marketplace_invoice.event_at, now()))
  on conflict ("installation_id", "external_id") do update set
    "state" = excluded."state",
    "period_start" = coalesce(excluded."period_start", "app_private"."marketplace_invoices"."period_start"),
    "period_end" = coalesce(excluded."period_end", "app_private"."marketplace_invoices"."period_end"),
    "total" = case when record_marketplace_invoice.total is null then "app_private"."marketplace_invoices"."total" else excluded."total" end,
    "currency" = case when record_marketplace_invoice.currency is null then "app_private"."marketplace_invoices"."currency" else excluded."currency" end,
    "items" = case when record_marketplace_invoice.items is null then "app_private"."marketplace_invoices"."items" else excluded."items" end,
    "event_at" = excluded."event_at"
  where "app_private"."marketplace_invoices"."event_at" <= excluded."event_at"
  returning * into v_row;
  if v_row."id" is null then
    select y.* into v_row from "app_private"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  elsif v_before is distinct from v_row."state" then
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Records a meter quantity for a period before it is sent to Vercel. The same
-- installation, resource, meter and period keep one row, so a retry updates it.
create or replace function "app_private"."record_marketplace_meter_report"(configuration_id text, meter_id text, period_start timestamptz, period_end timestamptz, quantity numeric, resource_external_id text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "app_private"."marketplace_meter_reports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "app_private"."marketplace_installations" x where x."configuration_id" = record_marketplace_meter_report.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "app_private"."marketplace_meter_reports" ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end", "quantity")
  values (v_installation, coalesce(record_marketplace_meter_report.resource_external_id, ''), record_marketplace_meter_report.meter_id, record_marketplace_meter_report.period_start, record_marketplace_meter_report.period_end, record_marketplace_meter_report.quantity)
  on conflict ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end") do update set
    "quantity" = excluded."quantity",
    "reported_at" = case when "app_private"."marketplace_meter_reports"."quantity" = excluded."quantity" then "app_private"."marketplace_meter_reports"."reported_at" end
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Marks reports as sent once Vercel accepted them, at their current quantity.
create or replace function "app_private"."mark_marketplace_meter_reported"(ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "app_private"."marketplace_meter_reports" x set "reported_at" = now(), "reported_quantity" = x."quantity" where x."id" = any (mark_marketplace_meter_reported.ids) and x."reported_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Records what Vercel accepted: reports is [{ id, quantity }], the totals
-- sent. A report whose quantity grew since stays unreported, with the rest
-- left for the next call.
create or replace function "app_private"."mark_marketplace_meter_sent"(reports jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "app_private"."marketplace_meter_reports" x set
    "reported_quantity" = (y.value ->> 'quantity')::numeric,
    "reported_at" = case when x."quantity" = (y.value ->> 'quantity')::numeric then now() end
  from jsonb_array_elements(coalesce(mark_marketplace_meter_sent.reports, '[]'::jsonb)) y
  where x."id" = (y.value ->> 'id')::uuid;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Reports Vercel has not accepted yet, oldest period first.
create or replace function "app_private"."unreported_marketplace_meter_reports"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."period_start", x."meter_id"), '[]'::jsonb)
    from "app_private"."marketplace_meter_reports" x join "app_private"."marketplace_installations" y on y."id" = x."installation_id"
    where y."configuration_id" = unreported_marketplace_meter_reports.configuration_id and x."reported_at" is null
  );
end;
$$;

-- Seals the access token Vercel handed out for an installation in Vault.
create or replace function "app_private"."seal_marketplace_access_token"(configuration_id text, access_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."marketplace_installations" x where x."configuration_id" = seal_marketplace_access_token.configuration_id;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  if v_row."access_token_secret_id" is null then
    update "app_private"."marketplace_installations" x set "access_token_secret_id" = vault.create_secret(
      seal_marketplace_access_token.access_token,
      'bs:marketplace:' || v_row."configuration_id" || ':' || gen_random_uuid()::text,
      'better-supabase Vercel Marketplace access token'
    ) where x."id" = v_row."id";
  else
    perform vault.update_secret(v_row."access_token_secret_id", seal_marketplace_access_token.access_token);
  end if;
end;
$$;

-- The sealed access token of an installation, or null.
create or replace function "app_private"."marketplace_access_token"(configuration_id text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select ds.decrypted_secret from "app_private"."marketplace_installations" x
    join vault.decrypted_secrets ds on ds.id = x."access_token_secret_id"
    where x."configuration_id" = marketplace_access_token.configuration_id
  );
end;
$$;

-- Links the app's tenant to an installation; created says the installation
-- made it, so removing the installation may delete it.
create or replace function "app_private"."link_marketplace_tenant"(configuration_id text, tenant text, created boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "app_private"."marketplace_installations" x set "tenant" = link_marketplace_tenant.tenant, "tenant_created" = coalesce(link_marketplace_tenant.created, false)
  where x."configuration_id" = link_marketplace_tenant.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Stores the tenant and secret handles the provision hook returned; null
-- keeps the stored value.
create or replace function "app_private"."set_marketplace_resource_state"(configuration_id text, external_id text, tenant text default null, tenant_created boolean default null, secret_refs text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "app_private"."marketplace_resources" y set
    "tenant" = coalesce(set_marketplace_resource_state.tenant, y."tenant"),
    "tenant_created" = coalesce(set_marketplace_resource_state.tenant_created, y."tenant_created"),
    "secret_refs" = coalesce(to_jsonb(set_marketplace_resource_state.secret_refs), y."secret_refs")
  from "app_private"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = set_marketplace_resource_state.configuration_id
    and y."external_id" = set_marketplace_resource_state.external_id
  returning y.* into v_row;
  if v_row."id" is null then
    raise exception 'The installation has no resource with this id' using errcode = 'P0002', hint = 'MARKETPLACE_RESOURCE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- A resource of an installation, or null.
create or replace function "app_private"."marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select to_jsonb(y) from "app_private"."marketplace_resources" y join "app_private"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resource.configuration_id and y."external_id" = marketplace_resource.external_id
  );
end;
$$;

-- The resources of an installation that are not deleted.
create or replace function "app_private"."marketplace_resources"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(y) order by y."created_at"), '[]'::jsonb)
    from "app_private"."marketplace_resources" y join "app_private"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resources.configuration_id and y."status" <> 'deleted'
  );
end;
$$;

-- Marks a resource deleted; the row stays for invoices and audit.
create or replace function "app_private"."delete_marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "app_private"."marketplace_resources" y set "status" = 'deleted'
  from "app_private"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = delete_marketplace_resource.configuration_id
    and y."external_id" = delete_marketplace_resource.external_id
  returning y.* into v_row;
  return case when v_row."id" is null then null else to_jsonb(v_row) end;
end;
$$;

revoke execute on function "app_private"."upsert_marketplace_installation"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."upsert_marketplace_installation"(text, text, text, text, jsonb) to service_role;
revoke execute on function "app_private"."marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "app_private"."marketplace_installation"(text) to service_role;
revoke execute on function "app_private"."remove_marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "app_private"."remove_marketplace_installation"(text) to service_role;
revoke execute on function "app_private"."upsert_marketplace_plan"(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."upsert_marketplace_plan"(text, text, text, jsonb) to service_role;
revoke execute on function "app_private"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) to service_role;
revoke execute on function "app_private"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) to service_role;
revoke execute on function "app_private"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) from public, anon, authenticated;
grant execute on function "app_private"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) to service_role;
revoke execute on function "app_private"."mark_marketplace_meter_reported"(uuid[]) from public, anon, authenticated;
grant execute on function "app_private"."mark_marketplace_meter_reported"(uuid[]) to service_role;
revoke execute on function "app_private"."unreported_marketplace_meter_reports"(text) from public, anon, authenticated;
grant execute on function "app_private"."unreported_marketplace_meter_reports"(text) to service_role;
revoke execute on function "app_private"."mark_marketplace_meter_sent"(jsonb) from public, anon, authenticated;
grant execute on function "app_private"."mark_marketplace_meter_sent"(jsonb) to service_role;
revoke execute on function "app_private"."seal_marketplace_access_token"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."seal_marketplace_access_token"(text, text) to service_role;
revoke execute on function "app_private"."marketplace_access_token"(text) from public, anon, authenticated;
grant execute on function "app_private"."marketplace_access_token"(text) to service_role;
revoke execute on function "app_private"."link_marketplace_tenant"(text, text, boolean) from public, anon, authenticated;
grant execute on function "app_private"."link_marketplace_tenant"(text, text, boolean) to service_role;
revoke execute on function "app_private"."set_marketplace_resource_state"(text, text, text, boolean, text[]) from public, anon, authenticated;
grant execute on function "app_private"."set_marketplace_resource_state"(text, text, text, boolean, text[]) to service_role;
revoke execute on function "app_private"."marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."marketplace_resource"(text, text) to service_role;
revoke execute on function "app_private"."marketplace_resources"(text) from public, anon, authenticated;
grant execute on function "app_private"."marketplace_resources"(text) to service_role;
revoke execute on function "app_private"."delete_marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."delete_marketplace_resource"(text, text) to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block-data vercel-marketplace
-- @bsb-hash sha256:eca90ca783032ddd52748019cbe99ad19f1851c3a083f1ad16f09d788b76da8b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('vercel-marketplace', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block vercel-marketplace@2 managed
-- @bsb-hash sha256:7a6f6763c0c89cb8ad9339a09e0c935b788374f03df983c1ee1cf6cb2ce563f1
-- Vercel Marketplace provider state: installations per configuration id, provisioned resources with their tenant and secret handles, access tokens sealed in Vault, plans, invoices kept by event time and meter reports sent to Vercel per period. Only the service role calls it; createVercelMarketplace() in better-supabase/blocks/vercel-marketplace serves the Partner API, verifies webhooks, exchanges SSO codes and reports usage.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Vercel Marketplace: the teams that installed the integration, the resources
-- they provisioned, the plans, Vercel's invoices and the meter reports sent to
-- Vercel. Only the service role writes; the app's own tables point at an
-- installation through its tenant.
create table if not exists "better_supabase"."marketplace_installations" (
  "id" uuid primary key default gen_random_uuid(),
  "configuration_id" text not null unique,
  "team_id" text,
  "user_id" text,
  "tenant" text,
  "status" text not null default 'active' check ("status" in ('active', 'suspended', 'removed')),
  "metadata" jsonb not null default '{}'::jsonb,
  "removed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_installations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_installations";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_installations"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant_created: the installation created its tenant, so removing the
-- installation may delete it. access_token_secret_id: the Vault secret with
-- the access token Vercel handed out at installation.
alter table "better_supabase"."marketplace_installations" add column if not exists "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_installations" add column if not exists "access_token_secret_id" uuid;
create index if not exists marketplace_installations_tenant_idx on "better_supabase"."marketplace_installations" ("tenant") where "tenant" is not null;
alter table "better_supabase"."marketplace_installations" enable row level security;
revoke all on "better_supabase"."marketplace_installations" from anon, authenticated;
grant all on "better_supabase"."marketplace_installations" to service_role;

create table if not exists "better_supabase"."marketplace_plans" (
  "id" text primary key,
  "name" text not null,
  "kind" text not null default 'subscription' check ("kind" in ('subscription', 'prepayment')),
  "details" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_plans" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_plans";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_plans"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_plans" enable row level security;
revoke all on "better_supabase"."marketplace_plans" from anon, authenticated;
grant all on "better_supabase"."marketplace_plans" to service_role;

create table if not exists "better_supabase"."marketplace_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "name" text not null,
  "plan_id" text references "better_supabase"."marketplace_plans" ("id") on delete set null,
  "status" text not null default 'ready' check ("status" in ('pending', 'ready', 'suspended', 'deleted')),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_resources" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_resources";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_resources"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant: the app's tenant the provision hook created or chose for the
-- resource. secret_refs: the app's handles for the secrets it handed out
-- (never the values), so a rotation can revoke the previous ones.
alter table "better_supabase"."marketplace_resources" add column if not exists "tenant" text;
alter table "better_supabase"."marketplace_resources" add column if not exists "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_resources" add column if not exists "secret_refs" jsonb not null default '[]'::jsonb;
create index if not exists marketplace_resources_plan_idx on "better_supabase"."marketplace_resources" ("plan_id") where "plan_id" is not null;
alter table "better_supabase"."marketplace_resources" enable row level security;
revoke all on "better_supabase"."marketplace_resources" from anon, authenticated;
grant all on "better_supabase"."marketplace_resources" to service_role;

create table if not exists "better_supabase"."marketplace_invoices" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "state" text not null default 'pending',
  "period_start" timestamptz,
  "period_end" timestamptz,
  "total" numeric not null default 0,
  "currency" text not null default 'usd',
  "items" jsonb not null default '[]'::jsonb,
  "event_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_invoices" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_invoices";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_invoices"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_invoices" enable row level security;
revoke all on "better_supabase"."marketplace_invoices" from anon, authenticated;
grant all on "better_supabase"."marketplace_invoices" to service_role;

create table if not exists "better_supabase"."marketplace_meter_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "resource_external_id" text not null default '',
  "meter_id" text not null,
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "quantity" numeric not null check ("quantity" >= 0),
  "reported_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end")
);
-- reported_quantity: the total Vercel accepted for the period, so the next
-- report sends the rest as dayValue.
alter table "better_supabase"."marketplace_meter_reports" add column if not exists "reported_quantity" numeric not null default 0;
alter table "better_supabase"."marketplace_meter_reports" enable row level security;
revoke all on "better_supabase"."marketplace_meter_reports" from anon, authenticated;
grant all on "better_supabase"."marketplace_meter_reports" to service_role;

-- Records an installation (or reactivates a removed one) for a configuration id.
create or replace function "better_supabase"."upsert_marketplace_installation"(configuration_id text, team_id text default null, user_id text default null, tenant text default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "better_supabase"."marketplace_installations" ("configuration_id", "team_id", "user_id", "tenant", "metadata")
  values (upsert_marketplace_installation.configuration_id, upsert_marketplace_installation.team_id, upsert_marketplace_installation.user_id, upsert_marketplace_installation.tenant, coalesce(upsert_marketplace_installation.metadata, '{}'::jsonb))
  on conflict ("configuration_id") do update set
    "team_id" = coalesce(excluded."team_id", "better_supabase"."marketplace_installations"."team_id"),
    "user_id" = coalesce(excluded."user_id", "better_supabase"."marketplace_installations"."user_id"),
    "tenant" = coalesce(excluded."tenant", "better_supabase"."marketplace_installations"."tenant"),
    "metadata" = "better_supabase"."marketplace_installations"."metadata" || excluded."metadata",
    "status" = case when "better_supabase"."marketplace_installations"."status" = 'removed' then 'active' else "better_supabase"."marketplace_installations"."status" end,
    "removed_at" = case when "better_supabase"."marketplace_installations"."status" = 'removed' then null else "better_supabase"."marketplace_installations"."removed_at" end
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- The installation for a configuration id, or null.
create or replace function "better_supabase"."marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (select to_jsonb(x) from "better_supabase"."marketplace_installations" x where x."configuration_id" = marketplace_installation.configuration_id);
end;
$$;

-- Marks the installation removed and its resources deleted (Vercel
-- integration-configuration.removed); the rows stay for invoices and audit.
create or replace function "better_supabase"."remove_marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_installations" x set "status" = 'removed', "removed_at" = coalesce(x."removed_at", now())
  where x."configuration_id" = remove_marketplace_installation.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  if v_row."access_token_secret_id" is not null then
    delete from vault.secrets vs where vs.id = v_row."access_token_secret_id";
    update "better_supabase"."marketplace_installations" x set "access_token_secret_id" = null where x."id" = v_row."id"
    returning * into v_row;
  end if;
  update "better_supabase"."marketplace_resources" y set "status" = 'deleted' where y."installation_id" = v_row."id" and y."status" <> 'deleted';
  null;
  return to_jsonb(v_row);
end;
$$;

-- Creates or updates a plan Vercel bills against.
create or replace function "better_supabase"."upsert_marketplace_plan"(id text, name text, kind text default 'subscription', details jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."marketplace_plans";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "better_supabase"."marketplace_plans" ("id", "name", "kind", "details")
  values (upsert_marketplace_plan.id, upsert_marketplace_plan.name, coalesce(upsert_marketplace_plan.kind, 'subscription'), coalesce(upsert_marketplace_plan.details, '{}'::jsonb))
  on conflict ("id") do update set "name" = excluded."name", "kind" = excluded."kind", "details" = excluded."details"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Provisions or updates a resource of an installation.
create or replace function "better_supabase"."upsert_marketplace_resource"(configuration_id text, external_id text, name text, plan_id text default null, status text default 'ready', metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = upsert_marketplace_resource.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_resources" ("installation_id", "external_id", "name", "plan_id", "status", "metadata")
  values (v_installation, upsert_marketplace_resource.external_id, upsert_marketplace_resource.name, upsert_marketplace_resource.plan_id, coalesce(upsert_marketplace_resource.status, 'ready'), coalesce(upsert_marketplace_resource.metadata, '{}'::jsonb))
  on conflict ("installation_id", "external_id") do update set
    "name" = excluded."name",
    "plan_id" = coalesce(excluded."plan_id", "better_supabase"."marketplace_resources"."plan_id"),
    "status" = excluded."status",
    "metadata" = "better_supabase"."marketplace_resources"."metadata" || excluded."metadata"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Stores an invoice Vercel sent, or its newer state. An older event never
-- overwrites a newer one (event_at guard), so redelivery in any order is safe.
create or replace function "better_supabase"."record_marketplace_invoice"(configuration_id text, external_id text, state text, period_start timestamptz default null, period_end timestamptz default null, total numeric default null, currency text default null, items jsonb default null, event_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_invoices";
  v_before text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_invoice.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  select y."state" into v_before from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  insert into "better_supabase"."marketplace_invoices" ("installation_id", "external_id", "state", "period_start", "period_end", "total", "currency", "items", "event_at")
  values (v_installation, record_marketplace_invoice.external_id, record_marketplace_invoice.state, record_marketplace_invoice.period_start, record_marketplace_invoice.period_end, coalesce(record_marketplace_invoice.total, 0), coalesce(record_marketplace_invoice.currency, 'usd'), coalesce(record_marketplace_invoice.items, '[]'::jsonb), coalesce(record_marketplace_invoice.event_at, now()))
  on conflict ("installation_id", "external_id") do update set
    "state" = excluded."state",
    "period_start" = coalesce(excluded."period_start", "better_supabase"."marketplace_invoices"."period_start"),
    "period_end" = coalesce(excluded."period_end", "better_supabase"."marketplace_invoices"."period_end"),
    "total" = case when record_marketplace_invoice.total is null then "better_supabase"."marketplace_invoices"."total" else excluded."total" end,
    "currency" = case when record_marketplace_invoice.currency is null then "better_supabase"."marketplace_invoices"."currency" else excluded."currency" end,
    "items" = case when record_marketplace_invoice.items is null then "better_supabase"."marketplace_invoices"."items" else excluded."items" end,
    "event_at" = excluded."event_at"
  where "better_supabase"."marketplace_invoices"."event_at" <= excluded."event_at"
  returning * into v_row;
  if v_row."id" is null then
    select y.* into v_row from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  elsif v_before is distinct from v_row."state" then
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Records a meter quantity for a period before it is sent to Vercel. The same
-- installation, resource, meter and period keep one row, so a retry updates it.
create or replace function "better_supabase"."record_marketplace_meter_report"(configuration_id text, meter_id text, period_start timestamptz, period_end timestamptz, quantity numeric, resource_external_id text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_meter_reports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_meter_report.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_meter_reports" ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end", "quantity")
  values (v_installation, coalesce(record_marketplace_meter_report.resource_external_id, ''), record_marketplace_meter_report.meter_id, record_marketplace_meter_report.period_start, record_marketplace_meter_report.period_end, record_marketplace_meter_report.quantity)
  on conflict ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end") do update set
    "quantity" = excluded."quantity",
    "reported_at" = case when "better_supabase"."marketplace_meter_reports"."quantity" = excluded."quantity" then "better_supabase"."marketplace_meter_reports"."reported_at" end
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Marks reports as sent once Vercel accepted them, at their current quantity.
create or replace function "better_supabase"."mark_marketplace_meter_reported"(ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_meter_reports" x set "reported_at" = now(), "reported_quantity" = x."quantity" where x."id" = any (mark_marketplace_meter_reported.ids) and x."reported_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Records what Vercel accepted: reports is [{ id, quantity }], the totals
-- sent. A report whose quantity grew since stays unreported, with the rest
-- left for the next call.
create or replace function "better_supabase"."mark_marketplace_meter_sent"(reports jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_meter_reports" x set
    "reported_quantity" = (y.value ->> 'quantity')::numeric,
    "reported_at" = case when x."quantity" = (y.value ->> 'quantity')::numeric then now() end
  from jsonb_array_elements(coalesce(mark_marketplace_meter_sent.reports, '[]'::jsonb)) y
  where x."id" = (y.value ->> 'id')::uuid;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Reports Vercel has not accepted yet, oldest period first.
create or replace function "better_supabase"."unreported_marketplace_meter_reports"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."period_start", x."meter_id"), '[]'::jsonb)
    from "better_supabase"."marketplace_meter_reports" x join "better_supabase"."marketplace_installations" y on y."id" = x."installation_id"
    where y."configuration_id" = unreported_marketplace_meter_reports.configuration_id and x."reported_at" is null
  );
end;
$$;

-- Seals the access token Vercel handed out for an installation in Vault.
create or replace function "better_supabase"."seal_marketplace_access_token"(configuration_id text, access_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."marketplace_installations" x where x."configuration_id" = seal_marketplace_access_token.configuration_id;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  if v_row."access_token_secret_id" is null then
    update "better_supabase"."marketplace_installations" x set "access_token_secret_id" = vault.create_secret(
      seal_marketplace_access_token.access_token,
      'bs:marketplace:' || v_row."configuration_id" || ':' || gen_random_uuid()::text,
      'better-supabase Vercel Marketplace access token'
    ) where x."id" = v_row."id";
  else
    perform vault.update_secret(v_row."access_token_secret_id", seal_marketplace_access_token.access_token);
  end if;
end;
$$;

-- The sealed access token of an installation, or null.
create or replace function "better_supabase"."marketplace_access_token"(configuration_id text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select ds.decrypted_secret from "better_supabase"."marketplace_installations" x
    join vault.decrypted_secrets ds on ds.id = x."access_token_secret_id"
    where x."configuration_id" = marketplace_access_token.configuration_id
  );
end;
$$;

-- Links the app's tenant to an installation; created says the installation
-- made it, so removing the installation may delete it.
create or replace function "better_supabase"."link_marketplace_tenant"(configuration_id text, tenant text, created boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_installations" x set "tenant" = link_marketplace_tenant.tenant, "tenant_created" = coalesce(link_marketplace_tenant.created, false)
  where x."configuration_id" = link_marketplace_tenant.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Stores the tenant and secret handles the provision hook returned; null
-- keeps the stored value.
create or replace function "better_supabase"."set_marketplace_resource_state"(configuration_id text, external_id text, tenant text default null, tenant_created boolean default null, secret_refs text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_resources" y set
    "tenant" = coalesce(set_marketplace_resource_state.tenant, y."tenant"),
    "tenant_created" = coalesce(set_marketplace_resource_state.tenant_created, y."tenant_created"),
    "secret_refs" = coalesce(to_jsonb(set_marketplace_resource_state.secret_refs), y."secret_refs")
  from "better_supabase"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = set_marketplace_resource_state.configuration_id
    and y."external_id" = set_marketplace_resource_state.external_id
  returning y.* into v_row;
  if v_row."id" is null then
    raise exception 'The installation has no resource with this id' using errcode = 'P0002', hint = 'MARKETPLACE_RESOURCE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- A resource of an installation, or null.
create or replace function "better_supabase"."marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select to_jsonb(y) from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resource.configuration_id and y."external_id" = marketplace_resource.external_id
  );
end;
$$;

-- The resources of an installation that are not deleted.
create or replace function "better_supabase"."marketplace_resources"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(y) order by y."created_at"), '[]'::jsonb)
    from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resources.configuration_id and y."status" <> 'deleted'
  );
end;
$$;

-- Marks a resource deleted; the row stays for invoices and audit.
create or replace function "better_supabase"."delete_marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_resources" y set "status" = 'deleted'
  from "better_supabase"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = delete_marketplace_resource.configuration_id
    and y."external_id" = delete_marketplace_resource.external_id
  returning y.* into v_row;
  return case when v_row."id" is null then null else to_jsonb(v_row) end;
end;
$$;

revoke execute on function "better_supabase"."upsert_marketplace_installation"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_installation"(text, text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_installation"(text) to service_role;
revoke execute on function "better_supabase"."remove_marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."remove_marketplace_installation"(text) to service_role;
revoke execute on function "better_supabase"."upsert_marketplace_plan"(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_plan"(text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) to service_role;
revoke execute on function "better_supabase"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) to service_role;
revoke execute on function "better_supabase"."mark_marketplace_meter_reported"(uuid[]) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_marketplace_meter_reported"(uuid[]) to service_role;
revoke execute on function "better_supabase"."unreported_marketplace_meter_reports"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."unreported_marketplace_meter_reports"(text) to service_role;
revoke execute on function "better_supabase"."mark_marketplace_meter_sent"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_marketplace_meter_sent"(jsonb) to service_role;
revoke execute on function "better_supabase"."seal_marketplace_access_token"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."seal_marketplace_access_token"(text, text) to service_role;
revoke execute on function "better_supabase"."marketplace_access_token"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_access_token"(text) to service_role;
revoke execute on function "better_supabase"."link_marketplace_tenant"(text, text, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."link_marketplace_tenant"(text, text, boolean) to service_role;
revoke execute on function "better_supabase"."set_marketplace_resource_state"(text, text, text, boolean, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."set_marketplace_resource_state"(text, text, text, boolean, text[]) to service_role;
revoke execute on function "better_supabase"."marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_resource"(text, text) to service_role;
revoke execute on function "better_supabase"."marketplace_resources"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_resources"(text) to service_role;
revoke execute on function "better_supabase"."delete_marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_marketplace_resource"(text, text) to service_role;

-- blocks.vercel-marketplace.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."upsert_marketplace_installation"(configuration_id text, team_id text default null, user_id text default null, tenant text default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_marketplace_installation"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."upsert_marketplace_installation"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."upsert_marketplace_installation"(text, text, text, text, jsonb) to service_role;

create or replace function "api"."marketplace_installation"(configuration_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."marketplace_installation"($1) $$;
revoke execute on function "api"."marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "api"."marketplace_installation"(text) to service_role;

create or replace function "api"."remove_marketplace_installation"(configuration_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_marketplace_installation"($1) $$;
revoke execute on function "api"."remove_marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "api"."remove_marketplace_installation"(text) to service_role;

create or replace function "api"."upsert_marketplace_plan"(id text, name text, kind text default 'subscription', details jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_marketplace_plan"($1, $2, $3, $4) $$;
revoke execute on function "api"."upsert_marketplace_plan"(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."upsert_marketplace_plan"(text, text, text, jsonb) to service_role;

create or replace function "api"."upsert_marketplace_resource"(configuration_id text, external_id text, name text, plan_id text default null, status text default 'ready', metadata jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_marketplace_resource"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) to service_role;

create or replace function "api"."record_marketplace_invoice"(configuration_id text, external_id text, state text, period_start timestamptz default null, period_end timestamptz default null, total numeric default null, currency text default null, items jsonb default null, event_at timestamptz default now())
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_marketplace_invoice"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function "api"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) to service_role;

create or replace function "api"."record_marketplace_meter_report"(configuration_id text, meter_id text, period_start timestamptz, period_end timestamptz, quantity numeric, resource_external_id text default '')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_marketplace_meter_report"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) from public, anon, authenticated;
grant execute on function "api"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) to service_role;

create or replace function "api"."mark_marketplace_meter_reported"(ids uuid[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_marketplace_meter_reported"($1) $$;
revoke execute on function "api"."mark_marketplace_meter_reported"(uuid[]) from public, anon, authenticated;
grant execute on function "api"."mark_marketplace_meter_reported"(uuid[]) to service_role;

create or replace function "api"."unreported_marketplace_meter_reports"(configuration_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unreported_marketplace_meter_reports"($1) $$;
revoke execute on function "api"."unreported_marketplace_meter_reports"(text) from public, anon, authenticated;
grant execute on function "api"."unreported_marketplace_meter_reports"(text) to service_role;

create or replace function "api"."mark_marketplace_meter_sent"(reports jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_marketplace_meter_sent"($1) $$;
revoke execute on function "api"."mark_marketplace_meter_sent"(jsonb) from public, anon, authenticated;
grant execute on function "api"."mark_marketplace_meter_sent"(jsonb) to service_role;

create or replace function "api"."seal_marketplace_access_token"(configuration_id text, access_token text)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."seal_marketplace_access_token"($1, $2) $$;
revoke execute on function "api"."seal_marketplace_access_token"(text, text) from public, anon, authenticated;
grant execute on function "api"."seal_marketplace_access_token"(text, text) to service_role;

create or replace function "api"."marketplace_access_token"(configuration_id text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."marketplace_access_token"($1) $$;
revoke execute on function "api"."marketplace_access_token"(text) from public, anon, authenticated;
grant execute on function "api"."marketplace_access_token"(text) to service_role;

create or replace function "api"."link_marketplace_tenant"(configuration_id text, tenant text, created boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link_marketplace_tenant"($1, $2, $3) $$;
revoke execute on function "api"."link_marketplace_tenant"(text, text, boolean) from public, anon, authenticated;
grant execute on function "api"."link_marketplace_tenant"(text, text, boolean) to service_role;

create or replace function "api"."set_marketplace_resource_state"(configuration_id text, external_id text, tenant text default null, tenant_created boolean default null, secret_refs text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_marketplace_resource_state"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."set_marketplace_resource_state"(text, text, text, boolean, text[]) from public, anon, authenticated;
grant execute on function "api"."set_marketplace_resource_state"(text, text, text, boolean, text[]) to service_role;

create or replace function "api"."marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."marketplace_resource"($1, $2) $$;
revoke execute on function "api"."marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "api"."marketplace_resource"(text, text) to service_role;

create or replace function "api"."marketplace_resources"(configuration_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."marketplace_resources"($1) $$;
revoke execute on function "api"."marketplace_resources"(text) from public, anon, authenticated;
grant execute on function "api"."marketplace_resources"(text) to service_role;

create or replace function "api"."delete_marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_marketplace_resource"($1, $2) $$;
revoke execute on function "api"."delete_marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "api"."delete_marketplace_resource"(text, text) to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block-data vercel-marketplace
-- @bsb-hash sha256:eca90ca783032ddd52748019cbe99ad19f1851c3a083f1ad16f09d788b76da8b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('vercel-marketplace', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block vercel-marketplace@2 managed
-- @bsb-hash sha256:a0e9bef5265871b7d4e94d8cbb8f8186a423f575b76ea914f37c80321ee66adb
-- Vercel Marketplace provider state: installations per configuration id, provisioned resources with their tenant and secret handles, access tokens sealed in Vault, plans, invoices kept by event time and meter reports sent to Vercel per period. Only the service role calls it; createVercelMarketplace() in better-supabase/blocks/vercel-marketplace serves the Partner API, verifies webhooks, exchanges SSO codes and reports usage.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Vercel Marketplace: the teams that installed the integration, the resources
-- they provisioned, the plans, Vercel's invoices and the meter reports sent to
-- Vercel. Only the service role writes; the app's own tables point at an
-- installation through its tenant.
create table if not exists "better_supabase"."marketplace_installations" (
  "id" uuid primary key default gen_random_uuid(),
  "configuration_id" text not null unique,
  "team_id" text,
  "user_id" text,
  "org_id" text,
  "status" text not null default 'active' check ("status" in ('active', 'suspended', 'removed')),
  "metadata" jsonb not null default '{}'::jsonb,
  "removed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_installations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_installations";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_installations"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant_created: the installation created its tenant, so removing the
-- installation may delete it. access_token_secret_id: the Vault secret with
-- the access token Vercel handed out at installation.
alter table "better_supabase"."marketplace_installations" add column if not exists "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_installations" add column if not exists "access_token_secret_id" uuid;
create index if not exists marketplace_installations_tenant_idx on "better_supabase"."marketplace_installations" ("org_id") where "org_id" is not null;
alter table "better_supabase"."marketplace_installations" enable row level security;
revoke all on "better_supabase"."marketplace_installations" from anon, authenticated;
grant all on "better_supabase"."marketplace_installations" to service_role;

create table if not exists "better_supabase"."marketplace_plans" (
  "id" text primary key,
  "name" text not null,
  "kind" text not null default 'subscription' check ("kind" in ('subscription', 'prepayment')),
  "details" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_plans" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_plans";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_plans"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_plans" enable row level security;
revoke all on "better_supabase"."marketplace_plans" from anon, authenticated;
grant all on "better_supabase"."marketplace_plans" to service_role;

create table if not exists "better_supabase"."marketplace_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "name" text not null,
  "plan_id" text references "better_supabase"."marketplace_plans" ("id") on delete set null,
  "status" text not null default 'ready' check ("status" in ('pending', 'ready', 'suspended', 'deleted')),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_resources" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_resources";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_resources"
  for each row execute function better_supabase.set_updated_at('updated_at');
-- tenant: the app's tenant the provision hook created or chose for the
-- resource. secret_refs: the app's handles for the secrets it handed out
-- (never the values), so a rotation can revoke the previous ones.
alter table "better_supabase"."marketplace_resources" add column if not exists "org_id" text;
alter table "better_supabase"."marketplace_resources" add column if not exists "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_resources" add column if not exists "secret_refs" jsonb not null default '[]'::jsonb;
create index if not exists marketplace_resources_plan_idx on "better_supabase"."marketplace_resources" ("plan_id") where "plan_id" is not null;
alter table "better_supabase"."marketplace_resources" enable row level security;
revoke all on "better_supabase"."marketplace_resources" from anon, authenticated;
grant all on "better_supabase"."marketplace_resources" to service_role;

create table if not exists "better_supabase"."marketplace_invoices" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "state" text not null default 'pending',
  "period_start" timestamptz,
  "period_end" timestamptz,
  "total" numeric not null default 0,
  "currency" text not null default 'usd',
  "items" jsonb not null default '[]'::jsonb,
  "event_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_invoices" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."marketplace_invoices";
create trigger bsb_updated_at before update on "better_supabase"."marketplace_invoices"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_invoices" enable row level security;
revoke all on "better_supabase"."marketplace_invoices" from anon, authenticated;
grant all on "better_supabase"."marketplace_invoices" to service_role;

create table if not exists "better_supabase"."marketplace_meter_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "resource_external_id" text not null default '',
  "meter_id" text not null,
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "quantity" numeric not null check ("quantity" >= 0),
  "reported_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end")
);
-- reported_quantity: the total Vercel accepted for the period, so the next
-- report sends the rest as dayValue.
alter table "better_supabase"."marketplace_meter_reports" add column if not exists "reported_quantity" numeric not null default 0;
alter table "better_supabase"."marketplace_meter_reports" enable row level security;
revoke all on "better_supabase"."marketplace_meter_reports" from anon, authenticated;
grant all on "better_supabase"."marketplace_meter_reports" to service_role;

-- Records an installation (or reactivates a removed one) for a configuration id.
create or replace function "better_supabase"."upsert_marketplace_installation"(configuration_id text, team_id text default null, user_id text default null, tenant text default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "better_supabase"."marketplace_installations" ("configuration_id", "team_id", "user_id", "org_id", "metadata")
  values (upsert_marketplace_installation.configuration_id, upsert_marketplace_installation.team_id, upsert_marketplace_installation.user_id, upsert_marketplace_installation.tenant, coalesce(upsert_marketplace_installation.metadata, '{}'::jsonb))
  on conflict ("configuration_id") do update set
    "team_id" = coalesce(excluded."team_id", "better_supabase"."marketplace_installations"."team_id"),
    "user_id" = coalesce(excluded."user_id", "better_supabase"."marketplace_installations"."user_id"),
    "org_id" = coalesce(excluded."org_id", "better_supabase"."marketplace_installations"."org_id"),
    "metadata" = "better_supabase"."marketplace_installations"."metadata" || excluded."metadata",
    "status" = case when "better_supabase"."marketplace_installations"."status" = 'removed' then 'active' else "better_supabase"."marketplace_installations"."status" end,
    "removed_at" = case when "better_supabase"."marketplace_installations"."status" = 'removed' then null else "better_supabase"."marketplace_installations"."removed_at" end
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- The installation for a configuration id, or null.
create or replace function "better_supabase"."marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (select to_jsonb(x) from "better_supabase"."marketplace_installations" x where x."configuration_id" = marketplace_installation.configuration_id);
end;
$$;

-- Marks the installation removed and its resources deleted (Vercel
-- integration-configuration.removed); the rows stay for invoices and audit.
create or replace function "better_supabase"."remove_marketplace_installation"(configuration_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_installations" x set "status" = 'removed', "removed_at" = coalesce(x."removed_at", now())
  where x."configuration_id" = remove_marketplace_installation.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    return null;
  end if;
  if v_row."access_token_secret_id" is not null then
    delete from vault.secrets vs where vs.id = v_row."access_token_secret_id";
    update "better_supabase"."marketplace_installations" x set "access_token_secret_id" = null where x."id" = v_row."id"
    returning * into v_row;
  end if;
  update "better_supabase"."marketplace_resources" y set "status" = 'deleted' where y."installation_id" = v_row."id" and y."status" <> 'deleted';
  null;
  return to_jsonb(v_row);
end;
$$;

-- Creates or updates a plan Vercel bills against.
create or replace function "better_supabase"."upsert_marketplace_plan"(id text, name text, kind text default 'subscription', details jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."marketplace_plans";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  insert into "better_supabase"."marketplace_plans" ("id", "name", "kind", "details")
  values (upsert_marketplace_plan.id, upsert_marketplace_plan.name, coalesce(upsert_marketplace_plan.kind, 'subscription'), coalesce(upsert_marketplace_plan.details, '{}'::jsonb))
  on conflict ("id") do update set "name" = excluded."name", "kind" = excluded."kind", "details" = excluded."details"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Provisions or updates a resource of an installation.
create or replace function "better_supabase"."upsert_marketplace_resource"(configuration_id text, external_id text, name text, plan_id text default null, status text default 'ready', metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = upsert_marketplace_resource.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_resources" ("installation_id", "external_id", "name", "plan_id", "status", "metadata")
  values (v_installation, upsert_marketplace_resource.external_id, upsert_marketplace_resource.name, upsert_marketplace_resource.plan_id, coalesce(upsert_marketplace_resource.status, 'ready'), coalesce(upsert_marketplace_resource.metadata, '{}'::jsonb))
  on conflict ("installation_id", "external_id") do update set
    "name" = excluded."name",
    "plan_id" = coalesce(excluded."plan_id", "better_supabase"."marketplace_resources"."plan_id"),
    "status" = excluded."status",
    "metadata" = "better_supabase"."marketplace_resources"."metadata" || excluded."metadata"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Stores an invoice Vercel sent, or its newer state. An older event never
-- overwrites a newer one (event_at guard), so redelivery in any order is safe.
create or replace function "better_supabase"."record_marketplace_invoice"(configuration_id text, external_id text, state text, period_start timestamptz default null, period_end timestamptz default null, total numeric default null, currency text default null, items jsonb default null, event_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_invoices";
  v_before text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_invoice.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  select y."state" into v_before from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  insert into "better_supabase"."marketplace_invoices" ("installation_id", "external_id", "state", "period_start", "period_end", "total", "currency", "items", "event_at")
  values (v_installation, record_marketplace_invoice.external_id, record_marketplace_invoice.state, record_marketplace_invoice.period_start, record_marketplace_invoice.period_end, coalesce(record_marketplace_invoice.total, 0), coalesce(record_marketplace_invoice.currency, 'usd'), coalesce(record_marketplace_invoice.items, '[]'::jsonb), coalesce(record_marketplace_invoice.event_at, now()))
  on conflict ("installation_id", "external_id") do update set
    "state" = excluded."state",
    "period_start" = coalesce(excluded."period_start", "better_supabase"."marketplace_invoices"."period_start"),
    "period_end" = coalesce(excluded."period_end", "better_supabase"."marketplace_invoices"."period_end"),
    "total" = case when record_marketplace_invoice.total is null then "better_supabase"."marketplace_invoices"."total" else excluded."total" end,
    "currency" = case when record_marketplace_invoice.currency is null then "better_supabase"."marketplace_invoices"."currency" else excluded."currency" end,
    "items" = case when record_marketplace_invoice.items is null then "better_supabase"."marketplace_invoices"."items" else excluded."items" end,
    "event_at" = excluded."event_at"
  where "better_supabase"."marketplace_invoices"."event_at" <= excluded."event_at"
  returning * into v_row;
  if v_row."id" is null then
    select y.* into v_row from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  elsif v_before is distinct from v_row."state" then
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Records a meter quantity for a period before it is sent to Vercel. The same
-- installation, resource, meter and period keep one row, so a retry updates it.
create or replace function "better_supabase"."record_marketplace_meter_report"(configuration_id text, meter_id text, period_start timestamptz, period_end timestamptz, quantity numeric, resource_external_id text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_meter_reports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_meter_report.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_meter_reports" ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end", "quantity")
  values (v_installation, coalesce(record_marketplace_meter_report.resource_external_id, ''), record_marketplace_meter_report.meter_id, record_marketplace_meter_report.period_start, record_marketplace_meter_report.period_end, record_marketplace_meter_report.quantity)
  on conflict ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end") do update set
    "quantity" = excluded."quantity",
    "reported_at" = case when "better_supabase"."marketplace_meter_reports"."quantity" = excluded."quantity" then "better_supabase"."marketplace_meter_reports"."reported_at" end
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Marks reports as sent once Vercel accepted them, at their current quantity.
create or replace function "better_supabase"."mark_marketplace_meter_reported"(ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_meter_reports" x set "reported_at" = now(), "reported_quantity" = x."quantity" where x."id" = any (mark_marketplace_meter_reported.ids) and x."reported_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Records what Vercel accepted: reports is [{ id, quantity }], the totals
-- sent. A report whose quantity grew since stays unreported, with the rest
-- left for the next call.
create or replace function "better_supabase"."mark_marketplace_meter_sent"(reports jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_meter_reports" x set
    "reported_quantity" = (y.value ->> 'quantity')::numeric,
    "reported_at" = case when x."quantity" = (y.value ->> 'quantity')::numeric then now() end
  from jsonb_array_elements(coalesce(mark_marketplace_meter_sent.reports, '[]'::jsonb)) y
  where x."id" = (y.value ->> 'id')::uuid;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Reports Vercel has not accepted yet, oldest period first.
create or replace function "better_supabase"."unreported_marketplace_meter_reports"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."period_start", x."meter_id"), '[]'::jsonb)
    from "better_supabase"."marketplace_meter_reports" x join "better_supabase"."marketplace_installations" y on y."id" = x."installation_id"
    where y."configuration_id" = unreported_marketplace_meter_reports.configuration_id and x."reported_at" is null
  );
end;
$$;

-- Seals the access token Vercel handed out for an installation in Vault.
create or replace function "better_supabase"."seal_marketplace_access_token"(configuration_id text, access_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."marketplace_installations" x where x."configuration_id" = seal_marketplace_access_token.configuration_id;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  if v_row."access_token_secret_id" is null then
    update "better_supabase"."marketplace_installations" x set "access_token_secret_id" = vault.create_secret(
      seal_marketplace_access_token.access_token,
      'bs:marketplace:' || v_row."configuration_id" || ':' || gen_random_uuid()::text,
      'better-supabase Vercel Marketplace access token'
    ) where x."id" = v_row."id";
  else
    perform vault.update_secret(v_row."access_token_secret_id", seal_marketplace_access_token.access_token);
  end if;
end;
$$;

-- The sealed access token of an installation, or null.
create or replace function "better_supabase"."marketplace_access_token"(configuration_id text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select ds.decrypted_secret from "better_supabase"."marketplace_installations" x
    join vault.decrypted_secrets ds on ds.id = x."access_token_secret_id"
    where x."configuration_id" = marketplace_access_token.configuration_id
  );
end;
$$;

-- Links the app's tenant to an installation; created says the installation
-- made it, so removing the installation may delete it.
create or replace function "better_supabase"."link_marketplace_tenant"(configuration_id text, tenant text, created boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_installations";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_installations" x set "org_id" = link_marketplace_tenant.tenant, "tenant_created" = coalesce(link_marketplace_tenant.created, false)
  where x."configuration_id" = link_marketplace_tenant.configuration_id
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Stores the tenant and secret handles the provision hook returned; null
-- keeps the stored value.
create or replace function "better_supabase"."set_marketplace_resource_state"(configuration_id text, external_id text, tenant text default null, tenant_created boolean default null, secret_refs text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_resources" y set
    "org_id" = coalesce(set_marketplace_resource_state.tenant, y."org_id"),
    "tenant_created" = coalesce(set_marketplace_resource_state.tenant_created, y."tenant_created"),
    "secret_refs" = coalesce(to_jsonb(set_marketplace_resource_state.secret_refs), y."secret_refs")
  from "better_supabase"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = set_marketplace_resource_state.configuration_id
    and y."external_id" = set_marketplace_resource_state.external_id
  returning y.* into v_row;
  if v_row."id" is null then
    raise exception 'The installation has no resource with this id' using errcode = 'P0002', hint = 'MARKETPLACE_RESOURCE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- A resource of an installation, or null.
create or replace function "better_supabase"."marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select to_jsonb(y) from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resource.configuration_id and y."external_id" = marketplace_resource.external_id
  );
end;
$$;

-- The resources of an installation that are not deleted.
create or replace function "better_supabase"."marketplace_resources"(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(y) order by y."created_at"), '[]'::jsonb)
    from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where x."configuration_id" = marketplace_resources.configuration_id and y."status" <> 'deleted'
  );
end;
$$;

-- Marks a resource deleted; the row stays for invoices and audit.
create or replace function "better_supabase"."delete_marketplace_resource"(configuration_id text, external_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."marketplace_resources";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  update "better_supabase"."marketplace_resources" y set "status" = 'deleted'
  from "better_supabase"."marketplace_installations" x
  where x."id" = y."installation_id"
    and x."configuration_id" = delete_marketplace_resource.configuration_id
    and y."external_id" = delete_marketplace_resource.external_id
  returning y.* into v_row;
  return case when v_row."id" is null then null else to_jsonb(v_row) end;
end;
$$;

revoke execute on function "better_supabase"."upsert_marketplace_installation"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_installation"(text, text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_installation"(text) to service_role;
revoke execute on function "better_supabase"."remove_marketplace_installation"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."remove_marketplace_installation"(text) to service_role;
revoke execute on function "better_supabase"."upsert_marketplace_plan"(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_plan"(text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."upsert_marketplace_resource"(text, text, text, text, text, jsonb) to service_role;
revoke execute on function "better_supabase"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_marketplace_invoice"(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz) to service_role;
revoke execute on function "better_supabase"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) from public, anon, authenticated;
grant execute on function "better_supabase"."record_marketplace_meter_report"(text, text, timestamptz, timestamptz, numeric, text) to service_role;
revoke execute on function "better_supabase"."mark_marketplace_meter_reported"(uuid[]) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_marketplace_meter_reported"(uuid[]) to service_role;
revoke execute on function "better_supabase"."unreported_marketplace_meter_reports"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."unreported_marketplace_meter_reports"(text) to service_role;
revoke execute on function "better_supabase"."mark_marketplace_meter_sent"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_marketplace_meter_sent"(jsonb) to service_role;
revoke execute on function "better_supabase"."seal_marketplace_access_token"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."seal_marketplace_access_token"(text, text) to service_role;
revoke execute on function "better_supabase"."marketplace_access_token"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_access_token"(text) to service_role;
revoke execute on function "better_supabase"."link_marketplace_tenant"(text, text, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."link_marketplace_tenant"(text, text, boolean) to service_role;
revoke execute on function "better_supabase"."set_marketplace_resource_state"(text, text, text, boolean, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."set_marketplace_resource_state"(text, text, text, boolean, text[]) to service_role;
revoke execute on function "better_supabase"."marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_resource"(text, text) to service_role;
revoke execute on function "better_supabase"."marketplace_resources"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."marketplace_resources"(text) to service_role;
revoke execute on function "better_supabase"."delete_marketplace_resource"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_marketplace_resource"(text, text) to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block-data vercel-marketplace
-- @bsb-hash sha256:eca90ca783032ddd52748019cbe99ad19f1851c3a083f1ad16f09d788b76da8b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('vercel-marketplace', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
