-- better-supabase module: targets
-- @bs-module targets@1 managed
-- Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
create table if not exists "better_supabase"."targets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "metric" text not null check ("metric" ~ '^[a-z][a-z0-9_.-]{0,80}$'),
  "owner_user_id" uuid,
  "team_id" uuid,
  "period_start" date not null,
  "period_end" date not null,
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "goal" bigint not null check ("goal" > 0),
  "actual" bigint not null default 0,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start")
);
create index if not exists targets_period_idx on "better_supabase"."targets" ("tenant_id", "period_start", "period_end") where "archived_at" is null;
alter table "better_supabase"."targets" enable row level security;
revoke all on "better_supabase"."targets" from anon, authenticated;
grant select on "better_supabase"."targets" to authenticated;
grant all on "better_supabase"."targets" to service_role;
drop policy if exists targets_read on "better_supabase"."targets";
create policy targets_read on "better_supabase"."targets" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('targets.read')));

-- Creates or changes a target: name, metric, ownerId, teamId, periodStart,
-- periodEnd, currency (for amount metrics), goal, actual (for a metric no
-- block computes), archived.
create or replace function "better_supabase"."save_target"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_target.target;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_target.tenant, 'targets.manage'), false)) then
    raise exception 'not allowed to manage targets' using errcode = '42501', hint = 'TARGET_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."targets" ("tenant_id", "name", "metric", "owner_user_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
      values (save_target.tenant, save_target.attrs ->> 'name', save_target.attrs ->> 'metric', (save_target.attrs ->> 'ownerId')::uuid,
        (save_target.attrs ->> 'teamId')::uuid, (save_target.attrs ->> 'periodStart')::date, (save_target.attrs ->> 'periodEnd')::date,
        upper(save_target.attrs ->> 'currency'), (save_target.attrs ->> 'goal')::bigint, coalesce((save_target.attrs ->> 'actual')::bigint, 0))
      returning "id" into v_id;
    else
      update "better_supabase"."targets" x set
        "name" = coalesce(save_target.attrs ->> 'name', x."name"),
        "goal" = coalesce((save_target.attrs ->> 'goal')::bigint, x."goal"),
        "actual" = coalesce((save_target.attrs ->> 'actual')::bigint, x."actual"),
        "period_start" = coalesce((save_target.attrs ->> 'periodStart')::date, x."period_start"),
        "period_end" = coalesce((save_target.attrs ->> 'periodEnd')::date, x."period_end"),
        "archived_at" = case when coalesce((save_target.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_target.tenant;
      if not found then
        raise exception 'target not found' using errcode = 'P0002', hint = 'TARGET_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a target needs a name, a metric, a period and a positive goal' using errcode = '22023', hint = 'TARGET_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('goal', x."goal"::text, 'actual', x."actual"::text)) from "better_supabase"."targets" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_target"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_target"(uuid, uuid, jsonb) to authenticated, service_role;

-- The targets whose period contains on, with their actual value and
-- attainment. Built-in metrics: deals.won_amount, deals.won_count, work_items.completed, invoices.paid_amount. Others read actual.
create or replace function "better_supabase"."target_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."targets" x
    cross join lateral (select case x."metric"
        when 'deals.won_amount' then (select coalesce(sum(d."amount"), 0) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_user_id" is null or d."owner_user_id" = x."owner_user_id") and d."currency" = x."currency")
        when 'deals.won_count' then (select count(*) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_user_id" is null or d."owner_user_id" = x."owner_user_id"))
        when 'work_items.completed' then (select count(*) from "better_supabase"."work_items" w
      where w."tenant_id" = x."tenant_id" and w."state" = 'completed' and w."closed_at"::date between x."period_start" and x."period_end"
        and (x."team_id" is null or w."team_id" = x."team_id")
        and (x."owner_user_id" is null or exists (select 1 from "better_supabase"."work_item_assignees" a where a."work_item_id" = w."id" and a."user_id" = x."owner_user_id")))
        when 'invoices.paid_amount' then (select coalesce(sum(e."amount"), 0) from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."managed_by" = 'invoices' and a."code" = 'invoices:cash:' || x."currency" and y."effective_at"::date between x."period_start" and x."period_end")
        else x."actual"
      end as value) v
    where x."tenant_id" = target_progress.tenant and x."archived_at" is null
      and coalesce(target_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (target_progress.owner is null or x."owner_user_id" = target_progress.owner)
  ) p
$$;
revoke execute on function "better_supabase"."target_progress"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."target_progress"(uuid, date, uuid) to authenticated, service_role;

-- blocks.targets.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."save_target"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_target"($1, $2, $3) $$;
revoke execute on function "api"."save_target"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_target"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."target_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."target_progress"($1, $2, $3) $$;
revoke execute on function "api"."target_progress"(uuid, date, uuid) from public, anon;
grant execute on function "api"."target_progress"(uuid, date, uuid) to authenticated, service_role;

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
