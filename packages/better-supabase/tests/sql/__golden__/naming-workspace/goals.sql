-- ==== schema supabase/schemas/900_better_supabase_100_goals.sql
-- better-supabase module: goals
-- @bsb-block goals@2 managed
-- @bsb-hash sha256:23d64287064d6a5acedbc15e389880389484664537fa183994f58e3a5be801ba
-- Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
create table "better_supabase"."goals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_goals_name_check check (length("name") >= 1 and length("name") <= 200),
  "metric" text not null constraint bsb_goals_metric_check check ("metric" ~ '^[a-z][a-z0-9_.-]{0,80}$'),
  "owner_id" uuid,
  "team_id" uuid,
  "period_start" date not null,
  "period_end" date not null,
  "currency" char(3) constraint bsb_goals_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "goal" bigint not null constraint bsb_goals_goal_check check ("goal" > 0),
  "actual" bigint not null default 0,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_goals_check check ("period_end" >= "period_start")
);
create index "goals_period_idx" on "better_supabase"."goals" ("tenant_id", "period_start", "period_end") where "archived_at" is null;
alter table "better_supabase"."goals" enable row level security;
revoke all on "better_supabase"."goals" from public, anon, authenticated;
grant select on "better_supabase"."goals" to authenticated;
grant all on "better_supabase"."goals" to service_role;
create policy bsb_goals_read on "better_supabase"."goals"
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
      insert into "better_supabase"."goals" ("tenant_id", "name", "metric", "owner_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
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
      and (goal_progress.owner is null or x."owner_id" = goal_progress.owner)
  ) p
$$;
revoke execute on function "better_supabase"."goal_progress"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."goal_progress"(uuid, date, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."goals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('goals.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."goals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."goals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."goals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_100_goals.sql
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
