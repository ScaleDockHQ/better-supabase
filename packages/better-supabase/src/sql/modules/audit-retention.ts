import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

/**
 * `purge_audit_log`, which honours an `audit_retention(tenant)` hook, and
 * `audit_events_tenants` for a retention callback in TypeScript.
 */
export function retention(ctx: ModuleContext): string {
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const id = ctx.idType;
  const hook = ctx.hookTarget("audit_retention");
  const signature = sqlString(`${hook}(${id})`);
  return `-- Deletes up to batch entries older than older_than and returns how many.
-- With an audit_retention(tenant) function, each tenant keeps its own
-- interval (a plan's days, say); null falls back to older_than. With
-- for_tenant, only entries of tenant (null: entries without one).
-- Nightly with pg_cron or the jobs drain route:
--   select better_supabase.purge_audit_log();
drop function if exists better_supabase.purge_audit_log(interval, integer);
create or replace function better_supabase.purge_audit_log(
  older_than interval default '1 year',
  batch integer default 10000,
  tenant ${id} default null,
  for_tenant boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  purged integer;
begin
  perform set_config('better_supabase.audit_purge', 'on', true);
  if not for_tenant and to_regprocedure(${signature}) is not null then
    -- Not a literal name, so plpgsql_check passes without the hook.
    execute format(
      ${sqlString(`with gone as (
      delete from ${log}
      where ${c("id")} in (
        select l.${c("id")} from ${log} l
        where l.${c("occurredAt")} < now() - coalesce(%s(l.${c("tenant")}), $1)
        order by l.${c("occurredAt")}
        limit $2
      )
      returning 1
    )
    select count(*)::integer from gone`)},
      to_regprocedure(${signature})::oid::regproc
    ) into purged using older_than, batch;
  else
    with gone as (
      delete from ${log}
      where ${c("id")} in (
        select l.${c("id")} from ${log} l
        where l.${c("occurredAt")} < now() - older_than
          and (not for_tenant or l.${c("tenant")} is not distinct from purge_audit_log.tenant)
        order by l.${c("occurredAt")}
        limit batch
      )
      returning 1
    )
    select count(*)::integer into purged from gone;
  end if;
  perform set_config('better_supabase.audit_purge', 'off', true);
  return purged;
end;
$$;
revoke execute on function better_supabase.purge_audit_log(interval, integer, ${id}, boolean) from public, anon, authenticated;
grant execute on function better_supabase.purge_audit_log(interval, integer, ${id}, boolean) to service_role;

-- Tenants with entries older than older_than, for a retention callback in TypeScript.
create or replace function better_supabase.audit_events_tenants(older_than interval default '1 day')
returns setof ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select distinct l.${c("tenant")} from ${log} l
  where l.${c("occurredAt")} < now() - older_than
$$;
revoke execute on function better_supabase.audit_events_tenants(interval) from public, anon, authenticated;
grant execute on function better_supabase.audit_events_tenants(interval) to service_role;`;
}
