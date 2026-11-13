-- ==== schema supabase/schemas/900_better_supabase_112_vercel_marketplace.sql
-- better-supabase module: vercel-marketplace
-- @bsb-block vercel-marketplace@2 managed
-- @bsb-hash sha256:23ed1a63645829ae4806e8f21515f70b34b1be9724a401a7597ddae6eb15806c
-- Vercel Marketplace provider state: installations per configuration id, provisioned resources with their tenant and secret handles, access tokens sealed in Vault, plans, invoices kept by event time and meter reports sent to Vercel per period. Only the service role calls it; createVercelMarketplace() in better-supabase/blocks/vercel-marketplace serves the Partner API, verifies webhooks, exchanges SSO codes and reports usage.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Vercel Marketplace: the teams that installed the integration, the resources
-- they provisioned, the plans, Vercel's invoices and the meter reports sent to
-- Vercel. Only the service role writes; the app's own tables point at an
-- installation through its tenant.
create table "better_supabase"."marketplace_installations" (
  "id" uuid primary key default gen_random_uuid(),
  "configuration_id" text not null unique,
  "team_id" text,
  "user_id" text,
  "tenant" text,
  "status" text not null default 'active' constraint bsb_marketplace_installations_status_check check ("status" in ('active', 'suspended', 'removed')),
  "metadata" jsonb not null default '{}'::jsonb,
  "removed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_installations" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."marketplace_installations"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
-- tenant_created: the installation created its tenant, so removing the
-- installation may delete it. access_token_secret_id: the Vault secret with
-- the access token Vercel handed out at installation.
alter table "better_supabase"."marketplace_installations" add column "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_installations" add column "access_token_secret_id" uuid;
create index marketplace_installations_tenant_idx on "better_supabase"."marketplace_installations" ("tenant") where "tenant" is not null;
alter table "better_supabase"."marketplace_installations" enable row level security;
revoke all on "better_supabase"."marketplace_installations" from public, anon, authenticated;
grant all on "better_supabase"."marketplace_installations" to service_role;

create table "better_supabase"."marketplace_plans" (
  "id" text primary key,
  "name" text not null,
  "kind" text not null default 'subscription' constraint bsb_marketplace_plans_kind_check check ("kind" in ('subscription', 'prepayment')),
  "details" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."marketplace_plans" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."marketplace_plans"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_plans" enable row level security;
revoke all on "better_supabase"."marketplace_plans" from public, anon, authenticated;
grant all on "better_supabase"."marketplace_plans" to service_role;

create table "better_supabase"."marketplace_resources" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "external_id" text not null,
  "name" text not null,
  "plan_id" text references "better_supabase"."marketplace_plans" ("id") on delete set null,
  "status" text not null default 'ready' constraint bsb_marketplace_resources_status_check check ("status" in ('pending', 'ready', 'suspended', 'deleted')),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "external_id")
);
alter table "better_supabase"."marketplace_resources" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."marketplace_resources"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
-- tenant: the app's tenant the provision hook created or chose for the
-- resource. secret_refs: the app's handles for the secrets it handed out
-- (never the values), so a rotation can revoke the previous ones.
alter table "better_supabase"."marketplace_resources" add column "tenant" text;
alter table "better_supabase"."marketplace_resources" add column "tenant_created" boolean not null default false;
alter table "better_supabase"."marketplace_resources" add column "secret_refs" jsonb not null default '[]'::jsonb;
create index marketplace_resources_plan_idx on "better_supabase"."marketplace_resources" ("plan_id") where "plan_id" is not null;
alter table "better_supabase"."marketplace_resources" enable row level security;
revoke all on "better_supabase"."marketplace_resources" from public, anon, authenticated;
grant all on "better_supabase"."marketplace_resources" to service_role;

create table "better_supabase"."marketplace_invoices" (
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
alter table "better_supabase"."marketplace_invoices" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."marketplace_invoices"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."marketplace_invoices" enable row level security;
revoke all on "better_supabase"."marketplace_invoices" from public, anon, authenticated;
grant all on "better_supabase"."marketplace_invoices" to service_role;

create table "better_supabase"."marketplace_meter_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "installation_id" uuid not null references "better_supabase"."marketplace_installations" ("id") on delete cascade,
  "resource_external_id" text not null default '',
  "meter_id" text not null,
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "quantity" numeric not null constraint bsb_marketplace_meter_reports_quantity_check check ("quantity" >= 0),
  "reported_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("installation_id", "resource_external_id", "meter_id", "period_start", "period_end")
);
-- reported_quantity: the total Vercel accepted for the period, so the next
-- report sends the rest as dayValue.
alter table "better_supabase"."marketplace_meter_reports" add column "reported_quantity" numeric not null default 0;
alter table "better_supabase"."marketplace_meter_reports" enable row level security;
revoke all on "better_supabase"."marketplace_meter_reports" from public, anon, authenticated;
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
  v_inserted boolean;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  v_inserted := not exists (select 1 from "better_supabase"."marketplace_installations" x where x."configuration_id" = upsert_marketplace_installation.configuration_id);
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
  if v_inserted then
    null;
  else
    null;
  end if;
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

-- Tenant reads for a signed-in member of the tenant an installation or a
-- resource is linked to (link_marketplace_tenant, set_marketplace_resource_state).
-- They leave out the Vault handle of the access token and the app's secret
-- handles, so a settings page can show them without the service role.
create or replace function "better_supabase"."marketplace_installation_for"(tenant text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (select 1 from unnest(array[(select auth.uid())]) as m(id) where m.id::text = marketplace_installation_for.tenant) then
    return null;
  end if;
  return (
    select to_jsonb(x) - 'access_token_secret_id'
    from "better_supabase"."marketplace_installations" x
    where x."tenant" = marketplace_installation_for.tenant and x."status"::text <> 'removed'
    order by x."created_at" desc
    limit 1
  );
end;
$$;

create or replace function "better_supabase"."marketplace_resources_for"(tenant text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (select 1 from unnest(array[(select auth.uid())]) as m(id) where m.id::text = marketplace_resources_for.tenant) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(y) - 'secret_refs' order by y."created_at"), '[]'::jsonb)
    from "better_supabase"."marketplace_resources" y join "better_supabase"."marketplace_installations" x on x."id" = y."installation_id"
    where y."tenant" = marketplace_resources_for.tenant and y."status"::text <> 'deleted'
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
revoke execute on function "better_supabase"."marketplace_installation_for"(text) from public, anon;
grant execute on function "better_supabase"."marketplace_installation_for"(text) to authenticated, service_role;
revoke execute on function "better_supabase"."marketplace_resources_for"(text) from public, anon;
grant execute on function "better_supabase"."marketplace_resources_for"(text) to authenticated, service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_112_vercel_marketplace.sql
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
