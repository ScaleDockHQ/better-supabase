import type { VercelMarketplaceEvents } from "../../blocks/vercel-marketplace/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  updatedAt,
} from "../shared.ts";

const EVENTS: BlockSqlEvents<VercelMarketplaceEvents> = {
  "marketplace_installation.upserted": {
    subject: "marketplace-installations",
    payload: ["installationId", "configurationId", "teamId"],
  },
  "marketplace_installation.removed": {
    subject: "marketplace-installations",
    payload: ["installationId", "configurationId", "teamId"],
  },
  "marketplace_invoice.state_changed": {
    subject: "marketplace-invoices",
    payload: ["installationId", "invoiceId", "externalId", "state"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["currency"],
  tables: {
    installations: {
      name: "marketplace_installations",
      columns: {
        id: "id",
        configurationId: "configuration_id",
        teamId: "team_id",
        userId: "user_id",
        tenant: "tenant",
        tenantCreated: "tenant_created",
        accessTokenSecret: "access_token_secret_id",
        status: "status",
        metadata: "metadata",
        removedAt: "removed_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    resources: {
      name: "marketplace_resources",
      columns: {
        id: "id",
        installation: "installation_id",
        externalId: "external_id",
        name: "name",
        plan: "plan_id",
        status: "status",
        metadata: "metadata",
        tenant: "tenant",
        tenantCreated: "tenant_created",
        secretRefs: "secret_refs",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    plans: {
      name: "marketplace_plans",
      columns: {
        id: "id",
        name: "name",
        kind: "kind",
        details: "details",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    invoices: {
      name: "marketplace_invoices",
      columns: {
        id: "id",
        installation: "installation_id",
        externalId: "external_id",
        state: "state",
        periodStart: "period_start",
        periodEnd: "period_end",
        total: "total",
        currency: "currency",
        items: "items",
        eventAt: "event_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    meterReports: {
      name: "marketplace_meter_reports",
      columns: {
        id: "id",
        installation: "installation_id",
        resourceExternalId: "resource_external_id",
        meterId: "meter_id",
        periodStart: "period_start",
        periodEnd: "period_end",
        quantity: "quantity",
        reportedQuantity: "reported_quantity",
        reportedAt: "reported_at",
        createdAt: "created_at",
      },
    },
  },
};

const STATUSES = "('active', 'suspended', 'removed')";

const guard = `
  if not (${SERVICE_CALLER}) then
    ${fail("MARKETPLACE_FORBIDDEN", "only the service role manages Marketplace installations")}
  end if;`;

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const fn = (name: string): string => ctx.fn(name);
  const i = ctx.table("installations");
  const r = ctx.table("resources");
  const p = ctx.table("plans");
  const v = ctx.table("invoices");
  const m = ctx.table("meterReports");
  const ic = (logical: string): string => ctx.col("installations", logical);
  const rc = (logical: string): string => ctx.col("resources", logical);
  const pc = (logical: string): string => ctx.col("plans", logical);
  const vc = (logical: string): string => ctx.col("invoices", logical);
  const mc = (logical: string): string => ctx.col("meterReports", logical);
  const currency = sqlString(ctx.text("currency", "usd"));

  const installationEvent = (type: string, row: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('installationId', ${row}.${ic("id")}, 'configurationId', ${row}.${ic("configurationId")}, 'teamId', ${row}.${ic("teamId")})`,
      subject: `'marketplace-installations/' || ${row}.${ic("id")}`,
      audit: {
        category: "configuration",
        targetType: "marketplace_installation",
        recordId: `${row}.${ic("id")}::text`,
      },
    });

  const missing = (): string =>
    fail(
      "MARKETPLACE_INSTALLATION_NOT_FOUND",
      "No installation has this configuration id",
      "P0002",
    );

  return `${schemaPreamble(ctx)}
-- Vercel Marketplace: the teams that installed the integration, the resources
-- they provisioned, the plans, Vercel's invoices and the meter reports sent to
-- Vercel. Only the service role writes; the app's own tables point at an
-- installation through its tenant.
create table if not exists ${i} (
  ${ic("id")} uuid primary key default gen_random_uuid(),
  ${ic("configurationId")} text not null unique,
  ${ic("teamId")} text,
  ${ic("userId")} text,
  ${ic("tenant")} text,
  ${ic("status")} text not null default 'active' check (${ic("status")} in ${STATUSES}),
  ${ic("metadata")} jsonb not null default '{}'::jsonb,
  ${ic("removedAt")} timestamptz,
  ${ic("createdAt")} timestamptz not null default now()
);
${updatedAt(i, ic("updatedAt"))}
-- tenant_created: the installation created its tenant, so removing the
-- installation may delete it. access_token_secret_id: the Vault secret with
-- the access token Vercel handed out at installation.
alter table ${i} add column if not exists ${ic("tenantCreated")} boolean not null default false;
alter table ${i} add column if not exists ${ic("accessTokenSecret")} uuid;
create index if not exists ${ctx.naming.rename("marketplace_installations_tenant_idx")} on ${i} (${ic("tenant")}) where ${ic("tenant")} is not null;
${lockTable(i)}

create table if not exists ${p} (
  ${pc("id")} text primary key,
  ${pc("name")} text not null,
  ${pc("kind")} text not null default 'subscription' check (${pc("kind")} in ('subscription', 'prepayment')),
  ${pc("details")} jsonb not null default '{}'::jsonb,
  ${pc("createdAt")} timestamptz not null default now()
);
${updatedAt(p, pc("updatedAt"))}
${lockTable(p)}

create table if not exists ${r} (
  ${rc("id")} uuid primary key default gen_random_uuid(),
  ${rc("installation")} uuid not null references ${i} (${ic("id")}) on delete cascade,
  ${rc("externalId")} text not null,
  ${rc("name")} text not null,
  ${rc("plan")} text references ${p} (${pc("id")}) on delete set null,
  ${rc("status")} text not null default 'ready' check (${rc("status")} in ('pending', 'ready', 'suspended', 'deleted')),
  ${rc("metadata")} jsonb not null default '{}'::jsonb,
  ${rc("createdAt")} timestamptz not null default now(),
  unique (${rc("installation")}, ${rc("externalId")})
);
${updatedAt(r, rc("updatedAt"))}
-- tenant: the app's tenant the provision hook created or chose for the
-- resource. secret_refs: the app's handles for the secrets it handed out
-- (never the values), so a rotation can revoke the previous ones.
alter table ${r} add column if not exists ${rc("tenant")} text;
alter table ${r} add column if not exists ${rc("tenantCreated")} boolean not null default false;
alter table ${r} add column if not exists ${rc("secretRefs")} jsonb not null default '[]'::jsonb;
create index if not exists ${ctx.naming.rename("marketplace_resources_plan_idx")} on ${r} (${rc("plan")}) where ${rc("plan")} is not null;
${lockTable(r)}

create table if not exists ${v} (
  ${vc("id")} uuid primary key default gen_random_uuid(),
  ${vc("installation")} uuid not null references ${i} (${ic("id")}) on delete cascade,
  ${vc("externalId")} text not null,
  ${vc("state")} text not null default 'pending',
  ${vc("periodStart")} timestamptz,
  ${vc("periodEnd")} timestamptz,
  ${vc("total")} numeric not null default 0,
  ${vc("currency")} text not null default ${currency},
  ${vc("items")} jsonb not null default '[]'::jsonb,
  ${vc("eventAt")} timestamptz not null default now(),
  ${vc("createdAt")} timestamptz not null default now(),
  unique (${vc("installation")}, ${vc("externalId")})
);
${updatedAt(v, vc("updatedAt"))}
${lockTable(v)}

create table if not exists ${m} (
  ${mc("id")} uuid primary key default gen_random_uuid(),
  ${mc("installation")} uuid not null references ${i} (${ic("id")}) on delete cascade,
  ${mc("resourceExternalId")} text not null default '',
  ${mc("meterId")} text not null,
  ${mc("periodStart")} timestamptz not null,
  ${mc("periodEnd")} timestamptz not null,
  ${mc("quantity")} numeric not null check (${mc("quantity")} >= 0),
  ${mc("reportedAt")} timestamptz,
  ${mc("createdAt")} timestamptz not null default now(),
  unique (${mc("installation")}, ${mc("resourceExternalId")}, ${mc("meterId")}, ${mc("periodStart")}, ${mc("periodEnd")})
);
-- reported_quantity: the total Vercel accepted for the period, so the next
-- report sends the rest as dayValue.
alter table ${m} add column if not exists ${mc("reportedQuantity")} numeric not null default 0;
${lockTable(m)}

-- Records an installation (or reactivates a removed one) for a configuration id.
create or replace function ${fn("upsert_marketplace_installation")}(configuration_id text, team_id text default null, user_id text default null, tenant text default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${i};
begin${guard}
  insert into ${i} (${ic("configurationId")}, ${ic("teamId")}, ${ic("userId")}, ${ic("tenant")}, ${ic("metadata")})
  values (upsert_marketplace_installation.configuration_id, upsert_marketplace_installation.team_id, upsert_marketplace_installation.user_id, upsert_marketplace_installation.tenant, coalesce(upsert_marketplace_installation.metadata, '{}'::jsonb))
  on conflict (${ic("configurationId")}) do update set
    ${ic("teamId")} = coalesce(excluded.${ic("teamId")}, ${i}.${ic("teamId")}),
    ${ic("userId")} = coalesce(excluded.${ic("userId")}, ${i}.${ic("userId")}),
    ${ic("tenant")} = coalesce(excluded.${ic("tenant")}, ${i}.${ic("tenant")}),
    ${ic("metadata")} = ${i}.${ic("metadata")} || excluded.${ic("metadata")},
    ${ic("status")} = case when ${i}.${ic("status")} = 'removed' then 'active' else ${i}.${ic("status")} end,
    ${ic("removedAt")} = case when ${i}.${ic("status")} = 'removed' then null else ${i}.${ic("removedAt")} end
  returning * into v_row;
  ${installationEvent("marketplace_installation.upserted", "v_row")}
  return to_jsonb(v_row);
end;
$$;

-- The installation for a configuration id, or null.
create or replace function ${fn("marketplace_installation")}(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (select to_jsonb(x) from ${i} x where x.${ic("configurationId")} = marketplace_installation.configuration_id);
end;
$$;

-- Marks the installation removed and its resources deleted (Vercel
-- integration-configuration.removed); the rows stay for invoices and audit.
create or replace function ${fn("remove_marketplace_installation")}(configuration_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${i};
begin${guard}
  update ${i} x set ${ic("status")} = 'removed', ${ic("removedAt")} = coalesce(x.${ic("removedAt")}, now())
  where x.${ic("configurationId")} = remove_marketplace_installation.configuration_id
  returning * into v_row;
  if v_row.${ic("id")} is null then
    return null;
  end if;
  if v_row.${ic("accessTokenSecret")} is not null then
    delete from vault.secrets vs where vs.id = v_row.${ic("accessTokenSecret")};
    update ${i} x set ${ic("accessTokenSecret")} = null where x.${ic("id")} = v_row.${ic("id")}
    returning * into v_row;
  end if;
  update ${r} y set ${rc("status")} = 'deleted' where y.${rc("installation")} = v_row.${ic("id")} and y.${rc("status")} <> 'deleted';
  ${installationEvent("marketplace_installation.removed", "v_row")}
  return to_jsonb(v_row);
end;
$$;

-- Creates or updates a plan Vercel bills against.
create or replace function ${fn("upsert_marketplace_plan")}(id text, name text, kind text default 'subscription', details jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${p};
begin${guard}
  insert into ${p} (${pc("id")}, ${pc("name")}, ${pc("kind")}, ${pc("details")})
  values (upsert_marketplace_plan.id, upsert_marketplace_plan.name, coalesce(upsert_marketplace_plan.kind, 'subscription'), coalesce(upsert_marketplace_plan.details, '{}'::jsonb))
  on conflict (${pc("id")}) do update set ${pc("name")} = excluded.${pc("name")}, ${pc("kind")} = excluded.${pc("kind")}, ${pc("details")} = excluded.${pc("details")}
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Provisions or updates a resource of an installation.
create or replace function ${fn("upsert_marketplace_resource")}(configuration_id text, external_id text, name text, plan_id text default null, status text default 'ready', metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row ${r};
begin${guard}
  select x.${ic("id")} into v_installation from ${i} x where x.${ic("configurationId")} = upsert_marketplace_resource.configuration_id;
  if v_installation is null then
    ${missing()}
  end if;
  insert into ${r} (${rc("installation")}, ${rc("externalId")}, ${rc("name")}, ${rc("plan")}, ${rc("status")}, ${rc("metadata")})
  values (v_installation, upsert_marketplace_resource.external_id, upsert_marketplace_resource.name, upsert_marketplace_resource.plan_id, coalesce(upsert_marketplace_resource.status, 'ready'), coalesce(upsert_marketplace_resource.metadata, '{}'::jsonb))
  on conflict (${rc("installation")}, ${rc("externalId")}) do update set
    ${rc("name")} = excluded.${rc("name")},
    ${rc("plan")} = coalesce(excluded.${rc("plan")}, ${r}.${rc("plan")}),
    ${rc("status")} = excluded.${rc("status")},
    ${rc("metadata")} = ${r}.${rc("metadata")} || excluded.${rc("metadata")}
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Stores an invoice Vercel sent, or its newer state. An older event never
-- overwrites a newer one (event_at guard), so redelivery in any order is safe.
create or replace function ${fn("record_marketplace_invoice")}(configuration_id text, external_id text, state text, period_start timestamptz default null, period_end timestamptz default null, total numeric default null, currency text default null, items jsonb default null, event_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row ${v};
  v_before text;
begin${guard}
  select x.${ic("id")} into v_installation from ${i} x where x.${ic("configurationId")} = record_marketplace_invoice.configuration_id;
  if v_installation is null then
    ${missing()}
  end if;
  select y.${vc("state")} into v_before from ${v} y where y.${vc("installation")} = v_installation and y.${vc("externalId")} = record_marketplace_invoice.external_id;
  insert into ${v} (${vc("installation")}, ${vc("externalId")}, ${vc("state")}, ${vc("periodStart")}, ${vc("periodEnd")}, ${vc("total")}, ${vc("currency")}, ${vc("items")}, ${vc("eventAt")})
  values (v_installation, record_marketplace_invoice.external_id, record_marketplace_invoice.state, record_marketplace_invoice.period_start, record_marketplace_invoice.period_end, coalesce(record_marketplace_invoice.total, 0), coalesce(record_marketplace_invoice.currency, ${currency}), coalesce(record_marketplace_invoice.items, '[]'::jsonb), coalesce(record_marketplace_invoice.event_at, now()))
  on conflict (${vc("installation")}, ${vc("externalId")}) do update set
    ${vc("state")} = excluded.${vc("state")},
    ${vc("periodStart")} = coalesce(excluded.${vc("periodStart")}, ${v}.${vc("periodStart")}),
    ${vc("periodEnd")} = coalesce(excluded.${vc("periodEnd")}, ${v}.${vc("periodEnd")}),
    ${vc("total")} = case when record_marketplace_invoice.total is null then ${v}.${vc("total")} else excluded.${vc("total")} end,
    ${vc("currency")} = case when record_marketplace_invoice.currency is null then ${v}.${vc("currency")} else excluded.${vc("currency")} end,
    ${vc("items")} = case when record_marketplace_invoice.items is null then ${v}.${vc("items")} else excluded.${vc("items")} end,
    ${vc("eventAt")} = excluded.${vc("eventAt")}
  where ${v}.${vc("eventAt")} <= excluded.${vc("eventAt")}
  returning * into v_row;
  if v_row.${vc("id")} is null then
    select y.* into v_row from ${v} y where y.${vc("installation")} = v_installation and y.${vc("externalId")} = record_marketplace_invoice.external_id;
  elsif v_before is distinct from v_row.${vc("state")} then
    ${ctx.record({
      type: "marketplace_invoice.state_changed",
      payload: `jsonb_build_object('installationId', v_installation, 'invoiceId', v_row.${vc("id")}, 'externalId', v_row.${vc("externalId")}, 'state', v_row.${vc("state")})`,
      subject: `'marketplace-invoices/' || v_row.${vc("id")}`,
      audit: {
        category: "billing",
        targetType: "marketplace_invoice",
        recordId: `v_row.${vc("id")}::text`,
      },
    })}
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Records a meter quantity for a period before it is sent to Vercel. The same
-- installation, resource, meter and period keep one row, so a retry updates it.
create or replace function ${fn("record_marketplace_meter_report")}(configuration_id text, meter_id text, period_start timestamptz, period_end timestamptz, quantity numeric, resource_external_id text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row ${m};
begin${guard}
  select x.${ic("id")} into v_installation from ${i} x where x.${ic("configurationId")} = record_marketplace_meter_report.configuration_id;
  if v_installation is null then
    ${missing()}
  end if;
  insert into ${m} (${mc("installation")}, ${mc("resourceExternalId")}, ${mc("meterId")}, ${mc("periodStart")}, ${mc("periodEnd")}, ${mc("quantity")})
  values (v_installation, coalesce(record_marketplace_meter_report.resource_external_id, ''), record_marketplace_meter_report.meter_id, record_marketplace_meter_report.period_start, record_marketplace_meter_report.period_end, record_marketplace_meter_report.quantity)
  on conflict (${mc("installation")}, ${mc("resourceExternalId")}, ${mc("meterId")}, ${mc("periodStart")}, ${mc("periodEnd")}) do update set
    ${mc("quantity")} = excluded.${mc("quantity")},
    ${mc("reportedAt")} = case when ${m}.${mc("quantity")} = excluded.${mc("quantity")} then ${m}.${mc("reportedAt")} end
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- Marks reports as sent once Vercel accepted them, at their current quantity.
create or replace function ${fn("mark_marketplace_meter_reported")}(ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin${guard}
  update ${m} x set ${mc("reportedAt")} = now(), ${mc("reportedQuantity")} = x.${mc("quantity")} where x.${mc("id")} = any (mark_marketplace_meter_reported.ids) and x.${mc("reportedAt")} is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Records what Vercel accepted: reports is [{ id, quantity }], the totals
-- sent. A report whose quantity grew since stays unreported, with the rest
-- left for the next call.
create or replace function ${fn("mark_marketplace_meter_sent")}(reports jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin${guard}
  update ${m} x set
    ${mc("reportedQuantity")} = (y.value ->> 'quantity')::numeric,
    ${mc("reportedAt")} = case when x.${mc("quantity")} = (y.value ->> 'quantity')::numeric then now() end
  from jsonb_array_elements(coalesce(mark_marketplace_meter_sent.reports, '[]'::jsonb)) y
  where x.${mc("id")} = (y.value ->> 'id')::uuid;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Reports Vercel has not accepted yet, oldest period first.
create or replace function ${fn("unreported_marketplace_meter_reports")}(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.${mc("periodStart")}, x.${mc("meterId")}), '[]'::jsonb)
    from ${m} x join ${i} y on y.${ic("id")} = x.${mc("installation")}
    where y.${ic("configurationId")} = unreported_marketplace_meter_reports.configuration_id and x.${mc("reportedAt")} is null
  );
end;
$$;

-- Seals the access token Vercel handed out for an installation in Vault.
create or replace function ${fn("seal_marketplace_access_token")}(configuration_id text, access_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${i};
begin${guard}
  select * into v_row from ${i} x where x.${ic("configurationId")} = seal_marketplace_access_token.configuration_id;
  if v_row.${ic("id")} is null then
    ${missing()}
  end if;
  if v_row.${ic("accessTokenSecret")} is null then
    update ${i} x set ${ic("accessTokenSecret")} = vault.create_secret(
      seal_marketplace_access_token.access_token,
      'bs:marketplace:' || v_row.${ic("configurationId")} || ':' || gen_random_uuid()::text,
      'better-supabase Vercel Marketplace access token'
    ) where x.${ic("id")} = v_row.${ic("id")};
  else
    perform vault.update_secret(v_row.${ic("accessTokenSecret")}, seal_marketplace_access_token.access_token);
  end if;
end;
$$;

-- The sealed access token of an installation, or null.
create or replace function ${fn("marketplace_access_token")}(configuration_id text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (
    select ds.decrypted_secret from ${i} x
    join vault.decrypted_secrets ds on ds.id = x.${ic("accessTokenSecret")}
    where x.${ic("configurationId")} = marketplace_access_token.configuration_id
  );
end;
$$;

-- Links the app's tenant to an installation; created says the installation
-- made it, so removing the installation may delete it.
create or replace function ${fn("link_marketplace_tenant")}(configuration_id text, tenant text, created boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${i};
begin${guard}
  update ${i} x set ${ic("tenant")} = link_marketplace_tenant.tenant, ${ic("tenantCreated")} = coalesce(link_marketplace_tenant.created, false)
  where x.${ic("configurationId")} = link_marketplace_tenant.configuration_id
  returning * into v_row;
  if v_row.${ic("id")} is null then
    ${missing()}
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Stores the tenant and secret handles the provision hook returned; null
-- keeps the stored value.
create or replace function ${fn("set_marketplace_resource_state")}(configuration_id text, external_id text, tenant text default null, tenant_created boolean default null, secret_refs text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${r};
begin${guard}
  update ${r} y set
    ${rc("tenant")} = coalesce(set_marketplace_resource_state.tenant, y.${rc("tenant")}),
    ${rc("tenantCreated")} = coalesce(set_marketplace_resource_state.tenant_created, y.${rc("tenantCreated")}),
    ${rc("secretRefs")} = coalesce(to_jsonb(set_marketplace_resource_state.secret_refs), y.${rc("secretRefs")})
  from ${i} x
  where x.${ic("id")} = y.${rc("installation")}
    and x.${ic("configurationId")} = set_marketplace_resource_state.configuration_id
    and y.${rc("externalId")} = set_marketplace_resource_state.external_id
  returning y.* into v_row;
  if v_row.${rc("id")} is null then
    ${fail("MARKETPLACE_RESOURCE_NOT_FOUND", "The installation has no resource with this id", "P0002")}
  end if;
  return to_jsonb(v_row);
end;
$$;

-- A resource of an installation, or null.
create or replace function ${fn("marketplace_resource")}(configuration_id text, external_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (
    select to_jsonb(y) from ${r} y join ${i} x on x.${ic("id")} = y.${rc("installation")}
    where x.${ic("configurationId")} = marketplace_resource.configuration_id and y.${rc("externalId")} = marketplace_resource.external_id
  );
end;
$$;

-- The resources of an installation that are not deleted.
create or replace function ${fn("marketplace_resources")}(configuration_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (
    select coalesce(jsonb_agg(to_jsonb(y) order by y.${rc("createdAt")}), '[]'::jsonb)
    from ${r} y join ${i} x on x.${ic("id")} = y.${rc("installation")}
    where x.${ic("configurationId")} = marketplace_resources.configuration_id and y.${rc("status")} <> 'deleted'
  );
end;
$$;

-- Marks a resource deleted; the row stays for invoices and audit.
create or replace function ${fn("delete_marketplace_resource")}(configuration_id text, external_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${r};
begin${guard}
  update ${r} y set ${rc("status")} = 'deleted'
  from ${i} x
  where x.${ic("id")} = y.${rc("installation")}
    and x.${ic("configurationId")} = delete_marketplace_resource.configuration_id
    and y.${rc("externalId")} = delete_marketplace_resource.external_id
  returning y.* into v_row;
  return case when v_row.${rc("id")} is null then null else to_jsonb(v_row) end;
end;
$$;

${serviceGrant(`${fn("upsert_marketplace_installation")}(text, text, text, text, jsonb)`)}
${serviceGrant(`${fn("marketplace_installation")}(text)`)}
${serviceGrant(`${fn("remove_marketplace_installation")}(text)`)}
${serviceGrant(`${fn("upsert_marketplace_plan")}(text, text, text, jsonb)`)}
${serviceGrant(`${fn("upsert_marketplace_resource")}(text, text, text, text, text, jsonb)`)}
${serviceGrant(`${fn("record_marketplace_invoice")}(text, text, text, timestamptz, timestamptz, numeric, text, jsonb, timestamptz)`)}
${serviceGrant(`${fn("record_marketplace_meter_report")}(text, text, timestamptz, timestamptz, numeric, text)`)}
${serviceGrant(`${fn("mark_marketplace_meter_reported")}(uuid[])`)}
${serviceGrant(`${fn("unreported_marketplace_meter_reports")}(text)`)}
${serviceGrant(`${fn("mark_marketplace_meter_sent")}(jsonb)`)}
${serviceGrant(`${fn("seal_marketplace_access_token")}(text, text)`)}
${serviceGrant(`${fn("marketplace_access_token")}(text)`)}
${serviceGrant(`${fn("link_marketplace_tenant")}(text, text, boolean)`)}
${serviceGrant(`${fn("set_marketplace_resource_state")}(text, text, text, boolean, text[])`)}
${serviceGrant(`${fn("marketplace_resource")}(text, text)`)}
${serviceGrant(`${fn("marketplace_resources")}(text)`)}
${serviceGrant(`${fn("delete_marketplace_resource")}(text, text)`)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "upsert_marketplace_installation",
      args: ["text", "text", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "marketplace_installation", args: ["text"], returns: "jsonb" },
    {
      name: "remove_marketplace_installation",
      args: ["text"],
      returns: "jsonb",
    },
    {
      name: "upsert_marketplace_plan",
      args: ["text", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "upsert_marketplace_resource",
      args: ["text", "text", "text", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "record_marketplace_invoice",
      args: [
        "text",
        "text",
        "text",
        "timestamptz",
        "timestamptz",
        "numeric",
        "text",
        "jsonb",
        "timestamptz",
      ],
      returns: "jsonb",
    },
    {
      name: "record_marketplace_meter_report",
      args: ["text", "text", "timestamptz", "timestamptz", "numeric", "text"],
      returns: "jsonb",
    },
    {
      name: "mark_marketplace_meter_reported",
      args: ["uuid[]"],
      returns: "integer",
    },
    {
      name: "unreported_marketplace_meter_reports",
      args: ["text"],
      returns: "jsonb",
    },
    {
      name: "mark_marketplace_meter_sent",
      args: ["jsonb"],
      returns: "integer",
    },
    {
      name: "seal_marketplace_access_token",
      args: ["text", "text"],
      returns: "void",
    },
    { name: "marketplace_access_token", args: ["text"], returns: "text" },
    {
      name: "link_marketplace_tenant",
      args: ["text", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "set_marketplace_resource_state",
      args: ["text", "text", "text", "boolean", "jsonb"],
      returns: "jsonb",
    },
    { name: "marketplace_resource", args: ["text", "text"], returns: "jsonb" },
    { name: "marketplace_resources", args: ["text"], returns: "jsonb" },
    {
      name: "delete_marketplace_resource",
      args: ["text", "text"],
      returns: "jsonb",
    },
  ];
}

export const VERCEL_MARKETPLACE: BlockSqlDefinition = {
  name: "vercel-marketplace",
  title: "Vercel Marketplace",
  description:
    "Vercel Marketplace provider state: installations per configuration id, provisioned resources with their tenant and secret handles, access tokens sealed in Vault, plans, invoices kept by event time and meter reports sent to Vercel per period. Only the service role calls it; createVercelMarketplace() in better-supabase/blocks/vercel-marketplace serves the Partner API, verifies webhooks, exchanges SSO codes and reports usage.",
  requires: [],
  integrates: ["outbox", "audit"],
  target: "schema",
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Seals installation access tokens in Vault, keeps each resource's tenant and secret handles for the Partner API, and reports usage per period with reported_quantity.",
      // Rows reported before reported_quantity existed were accepted at their quantity.
      sql: (ctx) => {
        const table = ctx.table("meterReports");
        const column = (name: string): string => ctx.col("meterReports", name);

        return [
          `alter table ${table} add column if not exists ${column("reportedQuantity")} numeric not null default 0;`,
          `update ${table} set ${column("reportedQuantity")} = ${column("quantity")} where ${column("reportedAt")} is not null;`,
        ].join("\n");
      },
    },
  ],
  names: NAMES,
  contract,
  build,
};
