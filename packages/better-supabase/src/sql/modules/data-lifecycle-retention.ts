import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleTableSpec,
} from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, fail, lockTable } from "../shared.ts";

/**
 * The record kinds the modules' purges look up, so a policy or a hold names
 * one; apps may add their own kinds for their own purges.
 */
export const RETENTION_KINDS = [
  "audit",
  "outbox",
  "webhook_deliveries",
  "webhooks",
  "inbound_events",
  "job_archive",
  "usage",
  "notifications",
  "workflow_runs",
  "ai_chats",
  "trash",
  "scim_sync_log",
] as const;

export const RETENTION_TABLES: Readonly<Record<string, ModuleTableSpec>> = {
  policies: {
    name: "retention_policies",
    columns: {
      id: "id",
      tenant: "organization_id",
      plan: "plan",
      kind: "kind",
      keep: "keep",
      updatedAt: "updated_at",
    },
    lifecycle: { tenant: "tenant", export: false },
  },
  holds: {
    name: "legal_holds",
    columns: {
      id: "id",
      tenant: "organization_id",
      kind: "kind",
      reason: "reason",
      placedBy: "placed_by",
      placedAt: "placed_at",
      releasedBy: "released_by",
      releasedAt: "released_at",
    },
  },
};

export const RETENTION_CONTRACT: readonly ModuleContractFunction[] = [
  { name: "retention_for", args: ["text", "text"], returns: "interval" },
  { name: "retention_floor", args: ["text"], returns: "interval" },
  { name: "is_held", args: ["text", "text"], returns: "boolean" },
  {
    name: "retention_cutoff",
    args: ["text", "interval"],
    returns: "timestamptz",
  },
  {
    name: "set_retention_policy",
    args: ["text", "interval", "{id}", "text"],
    returns: "jsonb",
  },
  {
    name: "remove_retention_policy",
    args: ["text", "{id}", "text"],
    returns: "boolean",
  },
  { name: "list_retention_policies", args: ["text"], returns: "jsonb" },
  {
    name: "place_legal_hold",
    args: ["text", "{id}", "text"],
    returns: "jsonb",
  },
  { name: "release_legal_hold", args: ["uuid"], returns: "jsonb" },
  { name: "list_legal_holds", args: ["boolean"], returns: "jsonb" },
];

/**
 * Retention policies per kind (for a tenant, a plan or every tenant) and
 * legal holds, which the modules' purges read through `ctx.retention` and
 * `ctx.held`, and `purge_organization` checks.
 */
export function retentionSql(ctx: ModuleContext): string {
  const id = ctx.idType;
  const p = ctx.table("policies");
  const h = ctx.table("holds");
  const cp = (logical: string): string => ctx.col("policies", logical);
  const ch = (logical: string): string => ctx.col("holds", logical);
  const fn = (name: string): string => ctx.fn(name);
  // A tenant's plans come from the entitlements module; a tenant id that
  // isn't of its id type (an outbox row's text tenant) has no plan.
  const planId = ctx.installed("entitlements")
    ? ctx.of("entitlements").idType
    : undefined;
  const plans = planId
    ? `if pg_input_is_valid(retention_for.tenant, ${sqlString(planId)}) then
      select min(x.${cp("keep")}) into v_keep from ${p} x
      where x.${cp("kind")} = retention_for.kind and x.${cp("tenant")} is null
        and x.${cp("plan")} = any (better_supabase.tenant_plans(retention_for.tenant::${planId}));
      if v_keep is not null then
        return v_keep;
      end if;
    end if;`
    : "";
  const holdEvent = (type: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('holdId', v_row.${ch("id")}, 'organizationId', v_row.${ch("tenant")}::text, 'kind', v_row.${ch("kind")}, 'reason', v_row.${ch("reason")})`,
      subject: `'legal-holds/' || v_row.${ch("id")}::text`,
      tenant: `v_row.${ch("tenant")}`,
      audit: {
        category: "data",
        targetType: "legal_hold",
        recordId: `v_row.${ch("id")}::text`,
      },
    });

  return `-- How long each kind of record is kept: for one tenant, for the tenants
-- on a plan, or for every tenant (both null). A purge keeps a row while
-- retention_for says so, whatever its own older_than argument.
create table if not exists ${p} (
  ${cp("id")} uuid primary key default gen_random_uuid(),
  ${cp("tenant")} ${id},
  ${cp("plan")} text,
  ${cp("kind")} text not null check (${cp("kind")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${cp("keep")} interval not null check (${cp("keep")} > interval '0'),
  ${cp("updatedAt")} timestamptz not null default now(),
  check (${cp("tenant")} is null or ${cp("plan")} is null),
  unique nulls not distinct (${cp("kind")}, ${cp("tenant")}, ${cp("plan")})
);
create index if not exists ${ctx.naming.rename("retention_policies_tenant_idx")} on ${p} (${cp("tenant")}) where ${cp("tenant")} is not null;
${lockTable(p)}

-- Legal holds: while one is active (released_at null), no purge deletes
-- the records it covers. A null tenant holds every tenant, a null kind
-- every kind.
create table if not exists ${h} (
  ${ch("id")} uuid primary key default gen_random_uuid(),
  ${ch("tenant")} ${id},
  ${ch("kind")} text check (${ch("kind")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${ch("reason")} text not null check (length(${ch("reason")}) between 1 and 1000),
  ${ch("placedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${ch("placedAt")} timestamptz not null default now(),
  ${ch("releasedBy")} uuid references auth.users (id) on delete set null,
  ${ch("releasedAt")} timestamptz
);
create index if not exists ${ctx.naming.rename("legal_holds_active_idx")} on ${h} (${ch("tenant")}, ${ch("kind")}) where ${ch("releasedAt")} is null;
create index if not exists ${ctx.naming.rename("legal_holds_placed_by_idx")} on ${h} (${ch("placedBy")}) where ${ch("placedBy")} is not null;
create index if not exists ${ctx.naming.rename("legal_holds_released_by_idx")} on ${h} (${ch("releasedBy")}) where ${ch("releasedBy")} is not null;
${lockTable(h)}

-- The tenant's policy for a kind, else its plan's (the shortest when it has
-- several plans), else the policy for every tenant; null without one.
create or replace function ${fn("retention_for")}(kind text, tenant text default null)
returns interval
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_keep interval;
begin
  if retention_for.tenant is not null then
    select x.${cp("keep")} into v_keep from ${p} x
    where x.${cp("kind")} = retention_for.kind and x.${cp("tenant")}::text = retention_for.tenant;
    if v_keep is not null then
      return v_keep;
    end if;
    ${plans}
  end if;
  select x.${cp("keep")} into v_keep from ${p} x
  where x.${cp("kind")} = retention_for.kind and x.${cp("tenant")} is null and x.${cp("plan")} is null;
  return v_keep;
end;
$$;

-- The shortest time any policy keeps a kind, so a purge can bound its scan
-- on the timestamp index before it asks retention_for per row.
create or replace function ${fn("retention_floor")}(kind text)
returns interval
language sql
stable
security definer
set search_path = ''
as $$
  select min(x.${cp("keep")}) from ${p} x where x.${cp("kind")} = retention_floor.kind
$$;

-- Whether an active hold covers the kind for the tenant. A null tenant (a
-- row that belongs to no tenant) is covered only by a hold on every tenant.
create or replace function ${fn("is_held")}(kind text, tenant text default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${h} x
    where x.${ch("releasedAt")} is null
      and (x.${ch("kind")} is null or x.${ch("kind")} = is_held.kind)
      and (x.${ch("tenant")} is null or x.${ch("tenant")}::text = is_held.tenant)
  )
$$;

-- Before when every tenant's rows of a kind may go, so a purge can drop a
-- whole partition: null while any hold covers the kind, else the longest
-- policy or the fallback, whichever keeps more.
create or replace function ${fn("retention_cutoff")}(kind text, fallback interval)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1 from ${h} x
    where x.${ch("releasedAt")} is null
      and (x.${ch("kind")} is null or x.${ch("kind")} = retention_cutoff.kind)
  ) then null else now() - greatest(
    fallback,
    (select max(x.${cp("keep")}) from ${p} x where x.${cp("kind")} = retention_cutoff.kind)
  ) end
$$;

create or replace function ${fn("set_retention_policy")}(kind text, keep interval, tenant ${id} default null, plan text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${p};
begin
  if not (${SERVICE_CALLER}) then
    ${fail("RETENTION_FORBIDDEN", "Only the service role sets retention policies")}
  end if;
  insert into ${p} as x (${cp("kind")}, ${cp("keep")}, ${cp("tenant")}, ${cp("plan")})
  values (set_retention_policy.kind, set_retention_policy.keep, set_retention_policy.tenant, set_retention_policy.plan)
  on conflict (${cp("kind")}, ${cp("tenant")}, ${cp("plan")}) do update set
    ${cp("keep")} = excluded.${cp("keep")},
    ${cp("updatedAt")} = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function ${fn("remove_retention_policy")}(kind text, tenant ${id} default null, plan text default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER}) then
    ${fail("RETENTION_FORBIDDEN", "Only the service role removes retention policies")}
  end if;
  delete from ${p} x
  where x.${cp("kind")} = remove_retention_policy.kind
    and x.${cp("tenant")} is not distinct from remove_retention_policy.tenant
    and x.${cp("plan")} is not distinct from remove_retention_policy.plan;
  return found;
end;
$$;

create or replace function ${fn("list_retention_policies")}(kind text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x.${cp("kind")}, x.${cp("tenant")} nulls first, x.${cp("plan")} nulls first), '[]'::jsonb)
  from ${p} x
  where list_retention_policies.kind is null or x.${cp("kind")} = list_retention_policies.kind
$$;

create or replace function ${fn("place_legal_hold")}(reason text, tenant ${id} default null, kind text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${h};
begin
  if not (${SERVICE_CALLER}) then
    ${fail("LEGAL_HOLD_FORBIDDEN", "Only the service role places legal holds")}
  end if;
  insert into ${h} (${ch("reason")}, ${ch("tenant")}, ${ch("kind")}, ${ch("placedBy")})
  values (place_legal_hold.reason, place_legal_hold.tenant, place_legal_hold.kind, auth.uid())
  returning * into v_row;
  ${holdEvent("legal_hold.placed")}
  return to_jsonb(v_row);
end;
$$;

-- Releasing keeps the row, so the holds stay on record.
create or replace function ${fn("release_legal_hold")}(id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${h};
begin
  if not (${SERVICE_CALLER}) then
    ${fail("LEGAL_HOLD_FORBIDDEN", "Only the service role releases legal holds")}
  end if;
  update ${h} x set ${ch("releasedAt")} = now(), ${ch("releasedBy")} = auth.uid()
  where x.${ch("id")} = release_legal_hold.id and x.${ch("releasedAt")} is null
  returning * into v_row;
  if v_row.${ch("id")} is null then
    return null;
  end if;
  ${holdEvent("legal_hold.released")}
  return to_jsonb(v_row);
end;
$$;

create or replace function ${fn("list_legal_holds")}(include_released boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x.${ch("placedAt")} desc, x.${ch("id")}), '[]'::jsonb)
  from ${h} x
  where list_legal_holds.include_released or x.${ch("releasedAt")} is null
$$;

revoke execute on function ${fn("retention_for")}(text, text) from public, anon, authenticated;
revoke execute on function ${fn("retention_floor")}(text) from public, anon, authenticated;
revoke execute on function ${fn("is_held")}(text, text) from public, anon, authenticated;
revoke execute on function ${fn("retention_cutoff")}(text, interval) from public, anon, authenticated;
revoke execute on function ${fn("set_retention_policy")}(text, interval, ${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("remove_retention_policy")}(text, ${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("list_retention_policies")}(text) from public, anon, authenticated;
revoke execute on function ${fn("place_legal_hold")}(text, ${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("release_legal_hold")}(uuid) from public, anon, authenticated;
revoke execute on function ${fn("list_legal_holds")}(boolean) from public, anon, authenticated;
grant execute on function ${fn("retention_for")}(text, text) to service_role;
grant execute on function ${fn("retention_floor")}(text) to service_role;
grant execute on function ${fn("is_held")}(text, text) to service_role;
grant execute on function ${fn("retention_cutoff")}(text, interval) to service_role;
grant execute on function ${fn("set_retention_policy")}(text, interval, ${id}, text) to service_role;
grant execute on function ${fn("remove_retention_policy")}(text, ${id}, text) to service_role;
grant execute on function ${fn("list_retention_policies")}(text) to service_role;
grant execute on function ${fn("place_legal_hold")}(text, ${id}, text) to service_role;
grant execute on function ${fn("release_legal_hold")}(uuid) to service_role;
grant execute on function ${fn("list_legal_holds")}(boolean) to service_role;`;
}
