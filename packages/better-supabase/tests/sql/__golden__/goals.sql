-- ==== alone: schema supabase/schemas/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block goals@2 managed
-- @bsb-hash sha256:3af2f97882bbb2c2c7a805d7ce5c741d5f1ea725662bdf8fd17830849b6732af
-- Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
create table if not exists "better_supabase"."goals" (
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
create index if not exists "goals_period_idx" on "better_supabase"."goals" ("tenant_id", "period_start", "period_end") where "archived_at" is null;
alter table "better_supabase"."goals" enable row level security;
revoke all on "better_supabase"."goals" from public, anon, authenticated;
grant select on "better_supabase"."goals" to authenticated;
grant all on "better_supabase"."goals" to service_role;
drop policy if exists goals_read on "better_supabase"."goals";
create policy goals_read on "better_supabase"."goals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')));

-- Creates or changes a target: name, metric, ownerId, teamId, periodStart,
-- periodEnd, currency (for amount metrics), goal, actual (for a metric no
-- block computes), archived.
create or replace function "better_supabase"."save_goal"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_goal.target;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_goal.tenant, 'goals.manage'), false)) then
    raise exception 'not allowed to manage targets' using errcode = '42501', hint = 'GOAL_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."goals" ("tenant_id", "name", "metric", "owner_user_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
      values (save_goal.tenant, save_goal.attrs ->> 'name', save_goal.attrs ->> 'metric', (save_goal.attrs ->> 'ownerId')::uuid,
        (save_goal.attrs ->> 'teamId')::uuid, (save_goal.attrs ->> 'periodStart')::date, (save_goal.attrs ->> 'periodEnd')::date,
        upper(save_goal.attrs ->> 'currency'), (save_goal.attrs ->> 'goal')::bigint, coalesce((save_goal.attrs ->> 'actual')::bigint, 0))
      returning "id" into v_id;
    else
      update "better_supabase"."goals" x set
        "name" = coalesce(save_goal.attrs ->> 'name', x."name"),
        "goal" = coalesce((save_goal.attrs ->> 'goal')::bigint, x."goal"),
        "actual" = coalesce((save_goal.attrs ->> 'actual')::bigint, x."actual"),
        "period_start" = coalesce((save_goal.attrs ->> 'periodStart')::date, x."period_start"),
        "period_end" = coalesce((save_goal.attrs ->> 'periodEnd')::date, x."period_end"),
        "archived_at" = case when coalesce((save_goal.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_goal.tenant;
      if not found then
        raise exception 'target not found' using errcode = 'P0002', hint = 'GOAL_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a target needs a name, a metric, a period and a positive goal' using errcode = '22023', hint = 'GOAL_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('goal', x."goal"::text, 'actual', x."actual"::text)) from "better_supabase"."goals" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) to authenticated, service_role;

-- The targets whose period contains on, with their actual value and
-- attainment. Built-in metrics: none installed. Others read actual.
create or replace function "better_supabase"."goal_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."goals" x
    cross join lateral (select x."actual" as value) v
    where x."tenant_id" = goal_progress.tenant and x."archived_at" is null
      and coalesce(goal_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (goal_progress.owner is null or x."owner_user_id" = goal_progress.owner)
  ) p
$$;
revoke execute on function "better_supabase"."goal_progress"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."goal_progress"(uuid, date, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
create policy bsb_tenant_scope_select on "better_supabase"."goals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
create policy bsb_tenant_scope_insert on "better_supabase"."goals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
create policy bsb_tenant_scope_update on "better_supabase"."goals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
create policy bsb_tenant_scope_delete on "better_supabase"."goals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:6ccbb19a784390c80a73f1c3058be7d0e9d5e8f5641194f8c64fcbae29905639
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block goals@2 managed
-- @bsb-hash sha256:aed47da38459a64cc3de798572d8618cf784647a124fbf2032e4c4adbbc6f1d4
-- Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
create table if not exists "better_supabase"."goals" (
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
create index if not exists "goals_period_idx" on "better_supabase"."goals" ("tenant_id", "period_start", "period_end") where "archived_at" is null;
alter table "better_supabase"."goals" enable row level security;
revoke all on "better_supabase"."goals" from public, anon, authenticated;
grant select on "better_supabase"."goals" to authenticated;
grant all on "better_supabase"."goals" to service_role;
drop policy if exists goals_read on "better_supabase"."goals";
create policy goals_read on "better_supabase"."goals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')));

-- Creates or changes a target: name, metric, ownerId, teamId, periodStart,
-- periodEnd, currency (for amount metrics), goal, actual (for a metric no
-- block computes), archived.
create or replace function "better_supabase"."save_goal"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_goal.target;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_goal.tenant, 'goals.manage'), false)) then
    raise exception 'not allowed to manage targets' using errcode = '42501', hint = 'GOAL_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."goals" ("tenant_id", "name", "metric", "owner_user_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
      values (save_goal.tenant, save_goal.attrs ->> 'name', save_goal.attrs ->> 'metric', (save_goal.attrs ->> 'ownerId')::uuid,
        (save_goal.attrs ->> 'teamId')::uuid, (save_goal.attrs ->> 'periodStart')::date, (save_goal.attrs ->> 'periodEnd')::date,
        upper(save_goal.attrs ->> 'currency'), (save_goal.attrs ->> 'goal')::bigint, coalesce((save_goal.attrs ->> 'actual')::bigint, 0))
      returning "id" into v_id;
    else
      update "better_supabase"."goals" x set
        "name" = coalesce(save_goal.attrs ->> 'name', x."name"),
        "goal" = coalesce((save_goal.attrs ->> 'goal')::bigint, x."goal"),
        "actual" = coalesce((save_goal.attrs ->> 'actual')::bigint, x."actual"),
        "period_start" = coalesce((save_goal.attrs ->> 'periodStart')::date, x."period_start"),
        "period_end" = coalesce((save_goal.attrs ->> 'periodEnd')::date, x."period_end"),
        "archived_at" = case when coalesce((save_goal.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_goal.tenant;
      if not found then
        raise exception 'target not found' using errcode = 'P0002', hint = 'GOAL_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a target needs a name, a metric, a period and a positive goal' using errcode = '22023', hint = 'GOAL_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('goal', x."goal"::text, 'actual', x."actual"::text)) from "better_supabase"."goals" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) to authenticated, service_role;

-- The targets whose period contains on, with their actual value and
-- attainment. Built-in metrics: deals.won_amount, deals.won_count, work_items.completed, invoices.paid_amount. Others read actual.
create or replace function "better_supabase"."goal_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."goals" x
    cross join lateral (select case x."metric"
        when 'deals.won_amount' then (select coalesce(sum(d."amount"), 0) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_user_id" is null or d."owner_user_id" = x."owner_user_id") and d."currency" = x."currency")
        when 'deals.won_count' then (select count(*) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_user_id" is null or d."owner_user_id" = x."owner_user_id"))
        when 'work_items.completed' then (select count(*) from "better_supabase"."tasks" w
      where w."tenant_id" = x."tenant_id" and w."state" = 'completed' and w."closed_at"::date between x."period_start" and x."period_end"
        and (x."team_id" is null or w."team_id" = x."team_id")
        and (x."owner_user_id" is null or exists (select 1 from "better_supabase"."task_assignees" a where a."task_id" = w."id" and a."user_id" = x."owner_user_id")))
        when 'invoices.paid_amount' then (select coalesce(sum(e."amount"), 0) from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."managed_by" = 'invoices' and a."code" = 'invoices:cash:' || x."currency" and y."effective_at"::date between x."period_start" and x."period_end")
        else x."actual"
      end as value) v
    where x."tenant_id" = goal_progress.tenant and x."archived_at" is null
      and coalesce(goal_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (goal_progress.owner is null or x."owner_user_id" = goal_progress.owner)
  ) p
$$;
revoke execute on function "better_supabase"."goal_progress"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."goal_progress"(uuid, date, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
create policy bsb_tenant_scope_select on "better_supabase"."goals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
create policy bsb_tenant_scope_insert on "better_supabase"."goals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
create policy bsb_tenant_scope_update on "better_supabase"."goals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
create policy bsb_tenant_scope_delete on "better_supabase"."goals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
do $$
begin
  perform better_supabase.audit('better_supabase.goals', target_type => 'goal', event_prefix => 'goal', deferred => true);
end;
$$;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:6ccbb19a784390c80a73f1c3058be7d0e9d5e8f5641194f8c64fcbae29905639
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block goals@2 managed
-- @bsb-hash sha256:c4bcfb6f23b3c9763523ffc1a0b65f27f286a7aac5e1995816a7ab9c8d2e81c8
-- Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."goals";
    drop policy if exists bsb_tenant_scope_select on "app_private"."goals";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."goals";
    drop policy if exists bsb_tenant_scope_update on "app_private"."goals";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."goals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
create table if not exists "app_private"."goals" (
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
create index if not exists "goals_period_idx" on "app_private"."goals" ("tenant_id", "period_start", "period_end") where "archived_at" is null;
alter table "app_private"."goals" enable row level security;
revoke all on "app_private"."goals" from public, anon, authenticated;
grant select on "app_private"."goals" to authenticated;
grant all on "app_private"."goals" to service_role;
drop policy if exists goals_read on "app_private"."goals";
create policy goals_read on "app_private"."goals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')));

-- Creates or changes a target: name, metric, ownerId, teamId, periodStart,
-- periodEnd, currency (for amount metrics), goal, actual (for a metric no
-- block computes), archived.
create or replace function "app_private"."save_goal"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_goal.target;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_goal.tenant, 'goals.manage'), false)) then
    raise exception 'not allowed to manage targets' using errcode = '42501', hint = 'GOAL_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "app_private"."goals" ("tenant_id", "name", "metric", "owner_user_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
      values (save_goal.tenant, save_goal.attrs ->> 'name', save_goal.attrs ->> 'metric', (save_goal.attrs ->> 'ownerId')::uuid,
        (save_goal.attrs ->> 'teamId')::uuid, (save_goal.attrs ->> 'periodStart')::date, (save_goal.attrs ->> 'periodEnd')::date,
        upper(save_goal.attrs ->> 'currency'), (save_goal.attrs ->> 'goal')::bigint, coalesce((save_goal.attrs ->> 'actual')::bigint, 0))
      returning "id" into v_id;
    else
      update "app_private"."goals" x set
        "name" = coalesce(save_goal.attrs ->> 'name', x."name"),
        "goal" = coalesce((save_goal.attrs ->> 'goal')::bigint, x."goal"),
        "actual" = coalesce((save_goal.attrs ->> 'actual')::bigint, x."actual"),
        "period_start" = coalesce((save_goal.attrs ->> 'periodStart')::date, x."period_start"),
        "period_end" = coalesce((save_goal.attrs ->> 'periodEnd')::date, x."period_end"),
        "archived_at" = case when coalesce((save_goal.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_goal.tenant;
      if not found then
        raise exception 'target not found' using errcode = 'P0002', hint = 'GOAL_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a target needs a name, a metric, a period and a positive goal' using errcode = '22023', hint = 'GOAL_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('goal', x."goal"::text, 'actual', x."actual"::text)) from "app_private"."goals" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."save_goal"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_goal"(uuid, uuid, jsonb) to authenticated, service_role;

-- The targets whose period contains on, with their actual value and
-- attainment. Built-in metrics: none installed. Others read actual.
create or replace function "app_private"."goal_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "app_private"."goals" x
    cross join lateral (select x."actual" as value) v
    where x."tenant_id" = goal_progress.tenant and x."archived_at" is null
      and coalesce(goal_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (goal_progress.owner is null or x."owner_user_id" = goal_progress.owner)
  ) p
$$;
revoke execute on function "app_private"."goal_progress"(uuid, date, uuid) from public, anon;
grant execute on function "app_private"."goal_progress"(uuid, date, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."goals";
drop policy if exists bsb_tenant_scope_select on "app_private"."goals";
create policy bsb_tenant_scope_select on "app_private"."goals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."goals";
create policy bsb_tenant_scope_insert on "app_private"."goals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."goals";
create policy bsb_tenant_scope_update on "app_private"."goals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."goals";
create policy bsb_tenant_scope_delete on "app_private"."goals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:6ccbb19a784390c80a73f1c3058be7d0e9d5e8f5641194f8c64fcbae29905639
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block goals@2 managed
-- @bsb-hash sha256:3fb6e7acf68859a4093c62660b41f22187e17725781bc174a5783cb8491c8029
-- Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
create table if not exists "better_supabase"."goals" (
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
create index if not exists "goals_period_idx" on "better_supabase"."goals" ("tenant_id", "period_start", "period_end") where "archived_at" is null;
alter table "better_supabase"."goals" enable row level security;
revoke all on "better_supabase"."goals" from public, anon, authenticated;
grant select on "better_supabase"."goals" to authenticated;
grant all on "better_supabase"."goals" to service_role;
drop policy if exists goals_read on "better_supabase"."goals";
create policy goals_read on "better_supabase"."goals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')));

-- Creates or changes a target: name, metric, ownerId, teamId, periodStart,
-- periodEnd, currency (for amount metrics), goal, actual (for a metric no
-- block computes), archived.
create or replace function "better_supabase"."save_goal"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_goal.target;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_goal.tenant, 'goals.manage'), false)) then
    raise exception 'not allowed to manage targets' using errcode = '42501', hint = 'GOAL_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."goals" ("tenant_id", "name", "metric", "owner_user_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
      values (save_goal.tenant, save_goal.attrs ->> 'name', save_goal.attrs ->> 'metric', (save_goal.attrs ->> 'ownerId')::uuid,
        (save_goal.attrs ->> 'teamId')::uuid, (save_goal.attrs ->> 'periodStart')::date, (save_goal.attrs ->> 'periodEnd')::date,
        upper(save_goal.attrs ->> 'currency'), (save_goal.attrs ->> 'goal')::bigint, coalesce((save_goal.attrs ->> 'actual')::bigint, 0))
      returning "id" into v_id;
    else
      update "better_supabase"."goals" x set
        "name" = coalesce(save_goal.attrs ->> 'name', x."name"),
        "goal" = coalesce((save_goal.attrs ->> 'goal')::bigint, x."goal"),
        "actual" = coalesce((save_goal.attrs ->> 'actual')::bigint, x."actual"),
        "period_start" = coalesce((save_goal.attrs ->> 'periodStart')::date, x."period_start"),
        "period_end" = coalesce((save_goal.attrs ->> 'periodEnd')::date, x."period_end"),
        "archived_at" = case when coalesce((save_goal.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_goal.tenant;
      if not found then
        raise exception 'target not found' using errcode = 'P0002', hint = 'GOAL_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a target needs a name, a metric, a period and a positive goal' using errcode = '22023', hint = 'GOAL_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('goal', x."goal"::text, 'actual', x."actual"::text)) from "better_supabase"."goals" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) to authenticated, service_role;

-- The targets whose period contains on, with their actual value and
-- attainment. Built-in metrics: none installed. Others read actual.
create or replace function "better_supabase"."goal_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."goals" x
    cross join lateral (select x."actual" as value) v
    where x."tenant_id" = goal_progress.tenant and x."archived_at" is null
      and coalesce(goal_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (goal_progress.owner is null or x."owner_user_id" = goal_progress.owner)
  ) p
$$;
revoke execute on function "better_supabase"."goal_progress"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."goal_progress"(uuid, date, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
create policy bsb_tenant_scope_select on "better_supabase"."goals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
create policy bsb_tenant_scope_insert on "better_supabase"."goals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
create policy bsb_tenant_scope_update on "better_supabase"."goals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
create policy bsb_tenant_scope_delete on "better_supabase"."goals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.goals.api: entry points for the Data API.
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

create or replace function "api"."save_goal"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_goal"($1, $2, $3) $$;
revoke execute on function "api"."save_goal"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_goal"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."goal_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."goal_progress"($1, $2, $3) $$;
revoke execute on function "api"."goal_progress"(uuid, date, uuid) from public, anon;
grant execute on function "api"."goal_progress"(uuid, date, uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:6ccbb19a784390c80a73f1c3058be7d0e9d5e8f5641194f8c64fcbae29905639
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block goals@2 managed
-- @bsb-hash sha256:d5f020db2291c9e83342b28b49319818ee9a39767159e853ad8b9c8655196760
-- Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
-- better_supabase.goals is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."goals" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."goals" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."goals" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."goals" add column if not exists "metric" text check ("metric" ~ '^[a-z][a-z0-9_.-]{0,80}$');
alter table "better_supabase"."goals" add column if not exists "owner_user_id" uuid;
alter table "better_supabase"."goals" add column if not exists "team_id" uuid;
alter table "better_supabase"."goals" add column if not exists "period_start" date;
alter table "better_supabase"."goals" add column if not exists "period_end" date;
alter table "better_supabase"."goals" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."goals" add column if not exists "goal" bigint check ("goal" > 0);
alter table "better_supabase"."goals" add column if not exists "actual" bigint not null default 0;
alter table "better_supabase"."goals" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."goals" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."goals" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "goals_period_idx" on "better_supabase"."goals" ("tenant_id", "period_start", "period_end") where "archived_at" is null;
alter table "better_supabase"."goals" enable row level security;
grant select on "better_supabase"."goals" to authenticated;
grant all on "better_supabase"."goals" to service_role;
drop policy if exists bsb_goals_select on "better_supabase"."goals";
create policy bsb_goals_select on "better_supabase"."goals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')));

-- Creates or changes a target: name, metric, ownerId, teamId, periodStart,
-- periodEnd, currency (for amount metrics), goal, actual (for a metric no
-- block computes), archived.
create or replace function "better_supabase"."save_goal"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_goal.target;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_goal.tenant, 'goals.manage'), false)) then
    raise exception 'not allowed to manage targets' using errcode = '42501', hint = 'GOAL_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."goals" ("tenant_id", "name", "metric", "owner_user_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
      values (save_goal.tenant, save_goal.attrs ->> 'name', save_goal.attrs ->> 'metric', (save_goal.attrs ->> 'ownerId')::uuid,
        (save_goal.attrs ->> 'teamId')::uuid, (save_goal.attrs ->> 'periodStart')::date, (save_goal.attrs ->> 'periodEnd')::date,
        upper(save_goal.attrs ->> 'currency'), (save_goal.attrs ->> 'goal')::bigint, coalesce((save_goal.attrs ->> 'actual')::bigint, 0))
      returning "id" into v_id;
    else
      update "better_supabase"."goals" x set
        "name" = coalesce(save_goal.attrs ->> 'name', x."name"),
        "goal" = coalesce((save_goal.attrs ->> 'goal')::bigint, x."goal"),
        "actual" = coalesce((save_goal.attrs ->> 'actual')::bigint, x."actual"),
        "period_start" = coalesce((save_goal.attrs ->> 'periodStart')::date, x."period_start"),
        "period_end" = coalesce((save_goal.attrs ->> 'periodEnd')::date, x."period_end"),
        "archived_at" = case when coalesce((save_goal.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_goal.tenant;
      if not found then
        raise exception 'target not found' using errcode = 'P0002', hint = 'GOAL_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a target needs a name, a metric, a period and a positive goal' using errcode = '22023', hint = 'GOAL_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('goal', x."goal"::text, 'actual', x."actual"::text)) from "better_supabase"."goals" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) to authenticated, service_role;

-- The targets whose period contains on, with their actual value and
-- attainment. Built-in metrics: none installed. Others read actual.
create or replace function "better_supabase"."goal_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."goals" x
    cross join lateral (select x."actual" as value) v
    where x."tenant_id" = goal_progress.tenant and x."archived_at" is null
      and coalesce(goal_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (goal_progress.owner is null or x."owner_user_id" = goal_progress.owner)
  ) p
$$;
revoke execute on function "better_supabase"."goal_progress"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."goal_progress"(uuid, date, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
create policy bsb_tenant_scope_select on "better_supabase"."goals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
create policy bsb_tenant_scope_insert on "better_supabase"."goals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
create policy bsb_tenant_scope_update on "better_supabase"."goals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
create policy bsb_tenant_scope_delete on "better_supabase"."goals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:6ccbb19a784390c80a73f1c3058be7d0e9d5e8f5641194f8c64fcbae29905639
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block goals@2 managed
-- @bsb-hash sha256:f8cc230b949fa988e9cc65a4657f2951f2b433406924c3518b9c639df32130d3
-- Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
create table if not exists "better_supabase"."goals" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
create index if not exists "goals_period_idx" on "better_supabase"."goals" ("org_id", "period_start", "period_end") where "archived_at" is null;
alter table "better_supabase"."goals" enable row level security;
revoke all on "better_supabase"."goals" from public, anon, authenticated;
grant select on "better_supabase"."goals" to authenticated;
grant all on "better_supabase"."goals" to service_role;
drop policy if exists goals_read on "better_supabase"."goals";
create policy goals_read on "better_supabase"."goals"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('goals.read')));

-- Creates or changes a target: name, metric, ownerId, teamId, periodStart,
-- periodEnd, currency (for amount metrics), goal, actual (for a metric no
-- block computes), archived.
create or replace function "better_supabase"."save_goal"(tenant uuid, target uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_goal.target;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_goal.tenant, 'goals.manage'), false)) then
    raise exception 'not allowed to manage targets' using errcode = '42501', hint = 'GOAL_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."goals" ("org_id", "name", "metric", "owner_user_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
      values (save_goal.tenant, save_goal.attrs ->> 'name', save_goal.attrs ->> 'metric', (save_goal.attrs ->> 'ownerId')::uuid,
        (save_goal.attrs ->> 'teamId')::uuid, (save_goal.attrs ->> 'periodStart')::date, (save_goal.attrs ->> 'periodEnd')::date,
        upper(save_goal.attrs ->> 'currency'), (save_goal.attrs ->> 'goal')::bigint, coalesce((save_goal.attrs ->> 'actual')::bigint, 0))
      returning "id" into v_id;
    else
      update "better_supabase"."goals" x set
        "name" = coalesce(save_goal.attrs ->> 'name', x."name"),
        "goal" = coalesce((save_goal.attrs ->> 'goal')::bigint, x."goal"),
        "actual" = coalesce((save_goal.attrs ->> 'actual')::bigint, x."actual"),
        "period_start" = coalesce((save_goal.attrs ->> 'periodStart')::date, x."period_start"),
        "period_end" = coalesce((save_goal.attrs ->> 'periodEnd')::date, x."period_end"),
        "archived_at" = case when coalesce((save_goal.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."org_id" = save_goal.tenant;
      if not found then
        raise exception 'target not found' using errcode = 'P0002', hint = 'GOAL_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a target needs a name, a metric, a period and a positive goal' using errcode = '22023', hint = 'GOAL_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('goal', x."goal"::text, 'actual', x."actual"::text)) from "better_supabase"."goals" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_goal"(uuid, uuid, jsonb) to authenticated, service_role;

-- The targets whose period contains on, with their actual value and
-- attainment. Built-in metrics: none installed. Others read actual.
create or replace function "better_supabase"."goal_progress"(tenant uuid, on_date date, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."goals" x
    cross join lateral (select x."actual" as value) v
    where x."org_id" = goal_progress.tenant and x."archived_at" is null
      and coalesce(goal_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (goal_progress.owner is null or x."owner_user_id" = goal_progress.owner)
  ) p
$$;
revoke execute on function "better_supabase"."goal_progress"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."goal_progress"(uuid, date, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."goals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."goals";
create policy bsb_tenant_scope_select on "better_supabase"."goals" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('goals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."goals";
create policy bsb_tenant_scope_insert on "better_supabase"."goals" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."goals";
create policy bsb_tenant_scope_update on "better_supabase"."goals" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."goals";
create policy bsb_tenant_scope_delete on "better_supabase"."goals" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:6ccbb19a784390c80a73f1c3058be7d0e9d5e8f5641194f8c64fcbae29905639
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
