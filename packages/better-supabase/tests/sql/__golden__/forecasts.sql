-- ==== alone: schema supabase/schemas/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block forecasts@1 managed
-- @bsb-hash sha256:65c54708936471f3d3b98b559584142b6f695350bf563f0c23f1bec4b22fa957
-- Snapshots of the deals forecast call over time: the totals by category and every deal they counted, a list per period, and what changed between two snapshots (added, removed, won, lost, moved).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Forecasts: snapshots of the forecast call over time, with the deals each
-- one counted, and what changed between two of them.
create table "better_supabase"."forecast_snapshots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade,
  "period_start" date not null,
  "period_end" date not null,
  "currency" text not null constraint bsb_forecast_snapshots_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "target" bigint constraint bsb_forecast_snapshots_target_check check ("target" >= 0),
  "totals" jsonb not null constraint bsb_forecast_snapshots_totals_check check (jsonb_typeof("totals") = 'object'),
  "deal_count" integer not null default 0,
  "taken_by" uuid references auth.users (id) on delete set null,
  "taken_at" timestamptz not null default clock_timestamp(),
  constraint bsb_forecast_snapshots_check check ("period_end" >= "period_start")
);
create index forecast_snapshots_period_idx on "better_supabase"."forecast_snapshots" ("tenant_id", "period_start", "period_end", "taken_at" desc);
create index forecast_snapshots_pipeline_idx on "better_supabase"."forecast_snapshots" ("pipeline_id") where "pipeline_id" is not null;
create index forecast_snapshots_taken_by_idx on "better_supabase"."forecast_snapshots" ("taken_by") where "taken_by" is not null;
alter table "better_supabase"."forecast_snapshots" enable row level security;
revoke all on "better_supabase"."forecast_snapshots" from public, anon, authenticated;
grant select on "better_supabase"."forecast_snapshots" to authenticated;
grant all on "better_supabase"."forecast_snapshots" to service_role;
create table "better_supabase"."forecast_snapshot_deals" (
  "snapshot_id" uuid not null references "better_supabase"."forecast_snapshots" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "deal_id" uuid not null,
  "name" text not null,
  "owner_id" uuid,
  "stage_id" uuid,
  "forecast_category" text,
  "outcome" text not null,
  "amount" bigint not null,
  "expected_close_on" date,
  "closed_at" timestamptz,
  primary key ("snapshot_id", "deal_id")
);
create index forecast_snapshot_deals_deal_idx on "better_supabase"."forecast_snapshot_deals" ("tenant_id", "deal_id");
alter table "better_supabase"."forecast_snapshot_deals" enable row level security;
revoke all on "better_supabase"."forecast_snapshot_deals" from public, anon, authenticated;
grant select on "better_supabase"."forecast_snapshot_deals" to authenticated;
grant all on "better_supabase"."forecast_snapshot_deals" to service_role;
create policy bsb_forecast_snapshots_read on "better_supabase"."forecast_snapshots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));
create policy bsb_forecast_snapshot_deals_read on "better_supabase"."forecast_snapshot_deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));

-- Takes a snapshot of the forecast call for one currency between since and
-- until: the deal_forecast totals for the whole organization and every deal
-- they count (open deals closing in the period, deals closed in it). Needs
-- forecasts.snapshot. Returns the snapshot without its deals.
create or replace function "better_supabase"."take_forecast_snapshot"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
  v_currency text := upper(take_forecast_snapshot.currency);
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', take_forecast_snapshot.tenant, 'forecasts.snapshot'), false)) then
    raise exception 'Taking a forecast snapshot needs the forecasts.snapshot permission' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if take_forecast_snapshot.since is null or take_forecast_snapshot.until is null
    or take_forecast_snapshot.until < take_forecast_snapshot.since
    or take_forecast_snapshot.until - take_forecast_snapshot.since > 366 then
    raise exception 'until must be on or after since, at most a year later' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter code' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.target < 0 then
    raise exception 'target must not be negative' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.pipeline is not null and not exists (
    select 1 from "better_supabase"."pipelines" x
    where x."id" = take_forecast_snapshot.pipeline and x."tenant_id" = take_forecast_snapshot.tenant
  ) then
    raise exception 'The organization has no pipeline with this id' using errcode = 'P0002', hint = 'FORECAST_PIPELINE_UNKNOWN';
  end if;
  insert into "better_supabase"."forecast_snapshots" ("tenant_id", "pipeline_id", "period_start", "period_end", "currency", "target", "totals", "taken_by")
  values (take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, "better_supabase"."deal_forecast"(take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, null), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."forecast_snapshot_deals" ("snapshot_id", "tenant_id", "deal_id", "name", "owner_id", "stage_id", "forecast_category", "outcome", "amount", "expected_close_on", "closed_at")
  select v_row."id", x."tenant_id", x."id", x."name", x."owner_id", x."stage_id", x."forecast_category"::text, x."outcome"::text, x."amount", x."expected_close_on", x."closed_at"
  from "better_supabase"."deals" x
  where x."tenant_id" = take_forecast_snapshot.tenant
    and x."currency" = v_currency
    and x."archived_at" is null
    and (take_forecast_snapshot.pipeline is null or x."pipeline_id" = take_forecast_snapshot.pipeline)
    and (
      (x."outcome" = 'open' and x."expected_close_on" between take_forecast_snapshot.since and take_forecast_snapshot.until)
      or (x."outcome" <> 'open' and x."closed_at"::date between take_forecast_snapshot.since and take_forecast_snapshot.until)
    );
  get diagnostics v_count = row_count;
  update "better_supabase"."forecast_snapshots" x set "deal_count" = v_count
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at");
end;
$$;
revoke execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) to authenticated, service_role;

-- The organization's snapshots, newest first, optionally of one pipeline and
-- of the period between since and until. Needs forecasts.read.
create or replace function "better_supabase"."forecast_snapshots"(tenant uuid, pipeline uuid default null, since date default null, until date default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.taken_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as item, x."taken_at" as taken_at, x."id" as id
    from "better_supabase"."forecast_snapshots" x
    where x."tenant_id" = forecast_snapshots.tenant
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'forecasts.read'), false))
      and (forecast_snapshots.pipeline is null or x."pipeline_id" = forecast_snapshots.pipeline)
      and (forecast_snapshots.since is null or x."period_start" = forecast_snapshots.since)
      and (forecast_snapshots.until is null or x."period_end" = forecast_snapshots.until)
    order by x."taken_at" desc, x."id"
    limit least(greatest(coalesce(forecast_snapshots.max_count, 50), 1), 200)
  ) z
$$;
revoke execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) from public, anon;
grant execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) to authenticated, service_role;

-- One snapshot with its deals, the largest amount first.
create or replace function "better_supabase"."forecast_snapshot"(snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
begin
  select * into v_row from "better_supabase"."forecast_snapshots" x where x."id" = forecast_snapshot.snapshot;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at") || jsonb_build_object('deals', (
    select coalesce(jsonb_agg(jsonb_build_object('dealId', y."deal_id", 'name', y."name", 'ownerId', y."owner_id", 'stageId', y."stage_id", 'forecast', y."forecast_category"::text, 'outcome', y."outcome"::text, 'amount', y."amount"::text, 'closeOn', y."expected_close_on", 'closedAt', y."closed_at") order by y."amount" desc, y."deal_id"), '[]'::jsonb)
    from "better_supabase"."forecast_snapshot_deals" y where y."snapshot_id" = v_row."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."forecast_snapshot"(uuid) from public, anon;
grant execute on function "better_supabase"."forecast_snapshot"(uuid) to authenticated, service_role;

-- What changed between two snapshots of one organization and currency: each
-- deal that was added, removed, won, lost or changed its amount, forecast
-- category, stage, owner or close date, with its values in both.
create or replace function "better_supabase"."forecast_changes"(from_snapshot uuid, to_snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."forecast_snapshots";
  v_to "better_supabase"."forecast_snapshots";
begin
  select * into v_from from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.from_snapshot;
  select * into v_to from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.to_snapshot;
  if v_from."id" is null or v_to."id" is null
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'forecasts.read'), false)) or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_to."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  if v_from."tenant_id" <> v_to."tenant_id" or v_from."currency" <> v_to."currency" then
    raise exception 'Both snapshots must be of one organization and currency' using errcode = '22023', hint = 'FORECAST_MISMATCH';
  end if;
  return jsonb_build_object(
    'from', jsonb_build_object('id', v_from."id", 'organizationId', v_from."tenant_id", 'pipelineId', v_from."pipeline_id", 'since', v_from."period_start", 'until', v_from."period_end", 'currency', v_from."currency", 'target', v_from."target"::text, 'totals', v_from."totals", 'dealCount', v_from."deal_count", 'takenBy', v_from."taken_by", 'takenAt', v_from."taken_at"),
    'to', jsonb_build_object('id', v_to."id", 'organizationId', v_to."tenant_id", 'pipelineId', v_to."pipeline_id", 'since', v_to."period_start", 'until', v_to."period_end", 'currency', v_to."currency", 'target', v_to."target"::text, 'totals', v_to."totals", 'dealCount', v_to."deal_count", 'takenBy', v_to."taken_by", 'takenAt', v_to."taken_at"),
    'deals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'dealId', coalesce(b."deal_id", a."deal_id"),
        'name', coalesce(b."name", a."name"),
        'change', case
      when a."deal_id" is null then 'added'
      when b."deal_id" is null then 'removed'
      when a."outcome" = 'open' and b."outcome" = 'won' then 'won'
      when a."outcome" = 'open' and b."outcome" = 'lost' then 'lost'
      else 'changed'
    end,
        'before', case when a."deal_id" is null then null else jsonb_build_object('dealId', a."deal_id", 'name', a."name", 'ownerId', a."owner_id", 'stageId', a."stage_id", 'forecast', a."forecast_category"::text, 'outcome', a."outcome"::text, 'amount', a."amount"::text, 'closeOn', a."expected_close_on", 'closedAt', a."closed_at") end,
        'after', case when b."deal_id" is null then null else jsonb_build_object('dealId', b."deal_id", 'name', b."name", 'ownerId', b."owner_id", 'stageId', b."stage_id", 'forecast', b."forecast_category"::text, 'outcome', b."outcome"::text, 'amount', b."amount"::text, 'closeOn', b."expected_close_on", 'closedAt', b."closed_at") end
      ) order by coalesce(b."amount", a."amount") desc, coalesce(b."deal_id", a."deal_id")), '[]'::jsonb)
      from (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_from."id") a
      full join (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_to."id") b on b."deal_id" = a."deal_id"
      where a."deal_id" is null or b."deal_id" is null
      or a."amount" <> b."amount"
      or a."outcome" <> b."outcome"
      or a."forecast_category" is distinct from b."forecast_category"
      or a."stage_id" is distinct from b."stage_id"
      or a."expected_close_on" is distinct from b."expected_close_on"
      or a."owner_id" is distinct from b."owner_id"
    ));
end;
$$;
revoke execute on function "better_supabase"."forecast_changes"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."forecast_changes"(uuid, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshot_deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshot_deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshot_deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshot_deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:1a236d3062db7e93bf2739b0ee553543da0d1d3546fd673f331fd49953cbf0af
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block forecasts@1 managed
-- @bsb-hash sha256:8d26d67c388d08d8c284ed3abe35e54c3b424d5770e885f0c7c5f14e27c9aa57
-- Snapshots of the deals forecast call over time: the totals by category and every deal they counted, a list per period, and what changed between two snapshots (added, removed, won, lost, moved).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Forecasts: snapshots of the forecast call over time, with the deals each
-- one counted, and what changed between two of them.
create table "better_supabase"."forecast_snapshots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade,
  "period_start" date not null,
  "period_end" date not null,
  "currency" text not null constraint bsb_forecast_snapshots_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "target" bigint constraint bsb_forecast_snapshots_target_check check ("target" >= 0),
  "totals" jsonb not null constraint bsb_forecast_snapshots_totals_check check (jsonb_typeof("totals") = 'object'),
  "deal_count" integer not null default 0,
  "taken_by" uuid references auth.users (id) on delete set null,
  "taken_at" timestamptz not null default clock_timestamp(),
  constraint bsb_forecast_snapshots_check check ("period_end" >= "period_start")
);
create index forecast_snapshots_period_idx on "better_supabase"."forecast_snapshots" ("tenant_id", "period_start", "period_end", "taken_at" desc);
create index forecast_snapshots_pipeline_idx on "better_supabase"."forecast_snapshots" ("pipeline_id") where "pipeline_id" is not null;
create index forecast_snapshots_taken_by_idx on "better_supabase"."forecast_snapshots" ("taken_by") where "taken_by" is not null;
alter table "better_supabase"."forecast_snapshots" enable row level security;
revoke all on "better_supabase"."forecast_snapshots" from public, anon, authenticated;
grant select on "better_supabase"."forecast_snapshots" to authenticated;
grant all on "better_supabase"."forecast_snapshots" to service_role;
create table "better_supabase"."forecast_snapshot_deals" (
  "snapshot_id" uuid not null references "better_supabase"."forecast_snapshots" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "deal_id" uuid not null,
  "name" text not null,
  "owner_id" uuid,
  "stage_id" uuid,
  "forecast_category" text,
  "outcome" text not null,
  "amount" bigint not null,
  "expected_close_on" date,
  "closed_at" timestamptz,
  primary key ("snapshot_id", "deal_id")
);
create index forecast_snapshot_deals_deal_idx on "better_supabase"."forecast_snapshot_deals" ("tenant_id", "deal_id");
alter table "better_supabase"."forecast_snapshot_deals" enable row level security;
revoke all on "better_supabase"."forecast_snapshot_deals" from public, anon, authenticated;
grant select on "better_supabase"."forecast_snapshot_deals" to authenticated;
grant all on "better_supabase"."forecast_snapshot_deals" to service_role;
create policy bsb_forecast_snapshots_read on "better_supabase"."forecast_snapshots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));
create policy bsb_forecast_snapshot_deals_read on "better_supabase"."forecast_snapshot_deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));

-- Takes a snapshot of the forecast call for one currency between since and
-- until: the deal_forecast totals for the whole organization and every deal
-- they count (open deals closing in the period, deals closed in it). Needs
-- forecasts.snapshot. Returns the snapshot without its deals.
create or replace function "better_supabase"."take_forecast_snapshot"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
  v_currency text := upper(take_forecast_snapshot.currency);
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', take_forecast_snapshot.tenant, 'forecasts.snapshot'), false)) then
    raise exception 'Taking a forecast snapshot needs the forecasts.snapshot permission' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if take_forecast_snapshot.since is null or take_forecast_snapshot.until is null
    or take_forecast_snapshot.until < take_forecast_snapshot.since
    or take_forecast_snapshot.until - take_forecast_snapshot.since > 366 then
    raise exception 'until must be on or after since, at most a year later' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter code' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.target < 0 then
    raise exception 'target must not be negative' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.pipeline is not null and not exists (
    select 1 from "better_supabase"."pipelines" x
    where x."id" = take_forecast_snapshot.pipeline and x."tenant_id" = take_forecast_snapshot.tenant
  ) then
    raise exception 'The organization has no pipeline with this id' using errcode = 'P0002', hint = 'FORECAST_PIPELINE_UNKNOWN';
  end if;
  insert into "better_supabase"."forecast_snapshots" ("tenant_id", "pipeline_id", "period_start", "period_end", "currency", "target", "totals", "taken_by")
  values (take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, "better_supabase"."deal_forecast"(take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, null), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."forecast_snapshot_deals" ("snapshot_id", "tenant_id", "deal_id", "name", "owner_id", "stage_id", "forecast_category", "outcome", "amount", "expected_close_on", "closed_at")
  select v_row."id", x."tenant_id", x."id", x."name", x."owner_id", x."stage_id", x."forecast_category"::text, x."outcome"::text, x."amount", x."expected_close_on", x."closed_at"
  from "better_supabase"."deals" x
  where x."tenant_id" = take_forecast_snapshot.tenant
    and x."currency" = v_currency
    and x."archived_at" is null
    and (take_forecast_snapshot.pipeline is null or x."pipeline_id" = take_forecast_snapshot.pipeline)
    and (
      (x."outcome" = 'open' and x."expected_close_on" between take_forecast_snapshot.since and take_forecast_snapshot.until)
      or (x."outcome" <> 'open' and x."closed_at"::date between take_forecast_snapshot.since and take_forecast_snapshot.until)
    );
  get diagnostics v_count = row_count;
  update "better_supabase"."forecast_snapshots" x set "deal_count" = v_count
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('forecast_snapshot.created', jsonb_build_object('organizationId', v_row."tenant_id", 'snapshotId', v_row."id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'dealCount', v_row."deal_count"), 'forecast-snapshots/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/forecasts');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at");
end;
$$;
revoke execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) to authenticated, service_role;

-- The organization's snapshots, newest first, optionally of one pipeline and
-- of the period between since and until. Needs forecasts.read.
create or replace function "better_supabase"."forecast_snapshots"(tenant uuid, pipeline uuid default null, since date default null, until date default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.taken_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as item, x."taken_at" as taken_at, x."id" as id
    from "better_supabase"."forecast_snapshots" x
    where x."tenant_id" = forecast_snapshots.tenant
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'forecasts.read'), false))
      and (forecast_snapshots.pipeline is null or x."pipeline_id" = forecast_snapshots.pipeline)
      and (forecast_snapshots.since is null or x."period_start" = forecast_snapshots.since)
      and (forecast_snapshots.until is null or x."period_end" = forecast_snapshots.until)
    order by x."taken_at" desc, x."id"
    limit least(greatest(coalesce(forecast_snapshots.max_count, 50), 1), 200)
  ) z
$$;
revoke execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) from public, anon;
grant execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) to authenticated, service_role;

-- One snapshot with its deals, the largest amount first.
create or replace function "better_supabase"."forecast_snapshot"(snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
begin
  select * into v_row from "better_supabase"."forecast_snapshots" x where x."id" = forecast_snapshot.snapshot;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at") || jsonb_build_object('deals', (
    select coalesce(jsonb_agg(jsonb_build_object('dealId', y."deal_id", 'name', y."name", 'ownerId', y."owner_id", 'stageId', y."stage_id", 'forecast', y."forecast_category"::text, 'outcome', y."outcome"::text, 'amount', y."amount"::text, 'closeOn', y."expected_close_on", 'closedAt', y."closed_at") order by y."amount" desc, y."deal_id"), '[]'::jsonb)
    from "better_supabase"."forecast_snapshot_deals" y where y."snapshot_id" = v_row."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."forecast_snapshot"(uuid) from public, anon;
grant execute on function "better_supabase"."forecast_snapshot"(uuid) to authenticated, service_role;

-- What changed between two snapshots of one organization and currency: each
-- deal that was added, removed, won, lost or changed its amount, forecast
-- category, stage, owner or close date, with its values in both.
create or replace function "better_supabase"."forecast_changes"(from_snapshot uuid, to_snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."forecast_snapshots";
  v_to "better_supabase"."forecast_snapshots";
begin
  select * into v_from from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.from_snapshot;
  select * into v_to from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.to_snapshot;
  if v_from."id" is null or v_to."id" is null
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'forecasts.read'), false)) or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_to."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  if v_from."tenant_id" <> v_to."tenant_id" or v_from."currency" <> v_to."currency" then
    raise exception 'Both snapshots must be of one organization and currency' using errcode = '22023', hint = 'FORECAST_MISMATCH';
  end if;
  return jsonb_build_object(
    'from', jsonb_build_object('id', v_from."id", 'organizationId', v_from."tenant_id", 'pipelineId', v_from."pipeline_id", 'since', v_from."period_start", 'until', v_from."period_end", 'currency', v_from."currency", 'target', v_from."target"::text, 'totals', v_from."totals", 'dealCount', v_from."deal_count", 'takenBy', v_from."taken_by", 'takenAt', v_from."taken_at"),
    'to', jsonb_build_object('id', v_to."id", 'organizationId', v_to."tenant_id", 'pipelineId', v_to."pipeline_id", 'since', v_to."period_start", 'until', v_to."period_end", 'currency', v_to."currency", 'target', v_to."target"::text, 'totals', v_to."totals", 'dealCount', v_to."deal_count", 'takenBy', v_to."taken_by", 'takenAt', v_to."taken_at"),
    'deals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'dealId', coalesce(b."deal_id", a."deal_id"),
        'name', coalesce(b."name", a."name"),
        'change', case
      when a."deal_id" is null then 'added'
      when b."deal_id" is null then 'removed'
      when a."outcome" = 'open' and b."outcome" = 'won' then 'won'
      when a."outcome" = 'open' and b."outcome" = 'lost' then 'lost'
      else 'changed'
    end,
        'before', case when a."deal_id" is null then null else jsonb_build_object('dealId', a."deal_id", 'name', a."name", 'ownerId', a."owner_id", 'stageId', a."stage_id", 'forecast', a."forecast_category"::text, 'outcome', a."outcome"::text, 'amount', a."amount"::text, 'closeOn', a."expected_close_on", 'closedAt', a."closed_at") end,
        'after', case when b."deal_id" is null then null else jsonb_build_object('dealId', b."deal_id", 'name', b."name", 'ownerId', b."owner_id", 'stageId', b."stage_id", 'forecast', b."forecast_category"::text, 'outcome', b."outcome"::text, 'amount', b."amount"::text, 'closeOn', b."expected_close_on", 'closedAt', b."closed_at") end
      ) order by coalesce(b."amount", a."amount") desc, coalesce(b."deal_id", a."deal_id")), '[]'::jsonb)
      from (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_from."id") a
      full join (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_to."id") b on b."deal_id" = a."deal_id"
      where a."deal_id" is null or b."deal_id" is null
      or a."amount" <> b."amount"
      or a."outcome" <> b."outcome"
      or a."forecast_category" is distinct from b."forecast_category"
      or a."stage_id" is distinct from b."stage_id"
      or a."expected_close_on" is distinct from b."expected_close_on"
      or a."owner_id" is distinct from b."owner_id"
    ));
end;
$$;
revoke execute on function "better_supabase"."forecast_changes"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."forecast_changes"(uuid, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshot_deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshot_deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshot_deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshot_deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.forecast_snapshots deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"forecast_snapshot","event_prefix":"forecast_snapshot"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:1a236d3062db7e93bf2739b0ee553543da0d1d3546fd673f331fd49953cbf0af
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block forecasts@1 managed
-- @bsb-hash sha256:511b2af4bbc53584fb4eb6648bed9ed8383c3e69b92db3bcf2d71ea85190ba69
-- Snapshots of the deals forecast call over time: the totals by category and every deal they counted, a list per period, and what changed between two snapshots (added, removed, won, lost, moved).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Forecasts: snapshots of the forecast call over time, with the deals each
-- one counted, and what changed between two of them.
create table "app_private"."forecast_snapshots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade,
  "period_start" date not null,
  "period_end" date not null,
  "currency" text not null constraint bsb_forecast_snapshots_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "target" bigint constraint bsb_forecast_snapshots_target_check check ("target" >= 0),
  "totals" jsonb not null constraint bsb_forecast_snapshots_totals_check check (jsonb_typeof("totals") = 'object'),
  "deal_count" integer not null default 0,
  "taken_by" uuid references auth.users (id) on delete set null,
  "taken_at" timestamptz not null default clock_timestamp(),
  constraint bsb_forecast_snapshots_check check ("period_end" >= "period_start")
);
create index forecast_snapshots_period_idx on "app_private"."forecast_snapshots" ("tenant_id", "period_start", "period_end", "taken_at" desc);
create index forecast_snapshots_pipeline_idx on "app_private"."forecast_snapshots" ("pipeline_id") where "pipeline_id" is not null;
create index forecast_snapshots_taken_by_idx on "app_private"."forecast_snapshots" ("taken_by") where "taken_by" is not null;
alter table "app_private"."forecast_snapshots" enable row level security;
revoke all on "app_private"."forecast_snapshots" from public, anon, authenticated;
grant select on "app_private"."forecast_snapshots" to authenticated;
grant all on "app_private"."forecast_snapshots" to service_role;
create table "app_private"."forecast_snapshot_deals" (
  "snapshot_id" uuid not null references "app_private"."forecast_snapshots" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "deal_id" uuid not null,
  "name" text not null,
  "owner_id" uuid,
  "stage_id" uuid,
  "forecast_category" text,
  "outcome" text not null,
  "amount" bigint not null,
  "expected_close_on" date,
  "closed_at" timestamptz,
  primary key ("snapshot_id", "deal_id")
);
create index forecast_snapshot_deals_deal_idx on "app_private"."forecast_snapshot_deals" ("tenant_id", "deal_id");
alter table "app_private"."forecast_snapshot_deals" enable row level security;
revoke all on "app_private"."forecast_snapshot_deals" from public, anon, authenticated;
grant select on "app_private"."forecast_snapshot_deals" to authenticated;
grant all on "app_private"."forecast_snapshot_deals" to service_role;
create policy bsb_forecast_snapshots_read on "app_private"."forecast_snapshots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));
create policy bsb_forecast_snapshot_deals_read on "app_private"."forecast_snapshot_deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));

-- Takes a snapshot of the forecast call for one currency between since and
-- until: the deal_forecast totals for the whole organization and every deal
-- they count (open deals closing in the period, deals closed in it). Needs
-- forecasts.snapshot. Returns the snapshot without its deals.
create or replace function "app_private"."take_forecast_snapshot"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."forecast_snapshots";
  v_currency text := upper(take_forecast_snapshot.currency);
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', take_forecast_snapshot.tenant, 'forecasts.snapshot'), false)) then
    raise exception 'Taking a forecast snapshot needs the forecasts.snapshot permission' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if take_forecast_snapshot.since is null or take_forecast_snapshot.until is null
    or take_forecast_snapshot.until < take_forecast_snapshot.since
    or take_forecast_snapshot.until - take_forecast_snapshot.since > 366 then
    raise exception 'until must be on or after since, at most a year later' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter code' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.target < 0 then
    raise exception 'target must not be negative' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.pipeline is not null and not exists (
    select 1 from "better_supabase"."pipelines" x
    where x."id" = take_forecast_snapshot.pipeline and x."tenant_id" = take_forecast_snapshot.tenant
  ) then
    raise exception 'The organization has no pipeline with this id' using errcode = 'P0002', hint = 'FORECAST_PIPELINE_UNKNOWN';
  end if;
  insert into "app_private"."forecast_snapshots" ("tenant_id", "pipeline_id", "period_start", "period_end", "currency", "target", "totals", "taken_by")
  values (take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, "better_supabase"."deal_forecast"(take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, null), auth.uid())
  returning * into v_row;
  insert into "app_private"."forecast_snapshot_deals" ("snapshot_id", "tenant_id", "deal_id", "name", "owner_id", "stage_id", "forecast_category", "outcome", "amount", "expected_close_on", "closed_at")
  select v_row."id", x."tenant_id", x."id", x."name", x."owner_id", x."stage_id", x."forecast_category"::text, x."outcome"::text, x."amount", x."expected_close_on", x."closed_at"
  from "better_supabase"."deals" x
  where x."tenant_id" = take_forecast_snapshot.tenant
    and x."currency" = v_currency
    and x."archived_at" is null
    and (take_forecast_snapshot.pipeline is null or x."pipeline_id" = take_forecast_snapshot.pipeline)
    and (
      (x."outcome" = 'open' and x."expected_close_on" between take_forecast_snapshot.since and take_forecast_snapshot.until)
      or (x."outcome" <> 'open' and x."closed_at"::date between take_forecast_snapshot.since and take_forecast_snapshot.until)
    );
  get diagnostics v_count = row_count;
  update "app_private"."forecast_snapshots" x set "deal_count" = v_count
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at");
end;
$$;
revoke execute on function "app_private"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) from public, anon;
grant execute on function "app_private"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) to authenticated, service_role;

-- The organization's snapshots, newest first, optionally of one pipeline and
-- of the period between since and until. Needs forecasts.read.
create or replace function "app_private"."forecast_snapshots"(tenant uuid, pipeline uuid default null, since date default null, until date default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.taken_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as item, x."taken_at" as taken_at, x."id" as id
    from "app_private"."forecast_snapshots" x
    where x."tenant_id" = forecast_snapshots.tenant
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'forecasts.read'), false))
      and (forecast_snapshots.pipeline is null or x."pipeline_id" = forecast_snapshots.pipeline)
      and (forecast_snapshots.since is null or x."period_start" = forecast_snapshots.since)
      and (forecast_snapshots.until is null or x."period_end" = forecast_snapshots.until)
    order by x."taken_at" desc, x."id"
    limit least(greatest(coalesce(forecast_snapshots.max_count, 50), 1), 200)
  ) z
$$;
revoke execute on function "app_private"."forecast_snapshots"(uuid, uuid, date, date, integer) from public, anon;
grant execute on function "app_private"."forecast_snapshots"(uuid, uuid, date, date, integer) to authenticated, service_role;

-- One snapshot with its deals, the largest amount first.
create or replace function "app_private"."forecast_snapshot"(snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."forecast_snapshots";
begin
  select * into v_row from "app_private"."forecast_snapshots" x where x."id" = forecast_snapshot.snapshot;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at") || jsonb_build_object('deals', (
    select coalesce(jsonb_agg(jsonb_build_object('dealId', y."deal_id", 'name', y."name", 'ownerId', y."owner_id", 'stageId', y."stage_id", 'forecast', y."forecast_category"::text, 'outcome', y."outcome"::text, 'amount', y."amount"::text, 'closeOn', y."expected_close_on", 'closedAt', y."closed_at") order by y."amount" desc, y."deal_id"), '[]'::jsonb)
    from "app_private"."forecast_snapshot_deals" y where y."snapshot_id" = v_row."id"
  ));
end;
$$;
revoke execute on function "app_private"."forecast_snapshot"(uuid) from public, anon;
grant execute on function "app_private"."forecast_snapshot"(uuid) to authenticated, service_role;

-- What changed between two snapshots of one organization and currency: each
-- deal that was added, removed, won, lost or changed its amount, forecast
-- category, stage, owner or close date, with its values in both.
create or replace function "app_private"."forecast_changes"(from_snapshot uuid, to_snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from "app_private"."forecast_snapshots";
  v_to "app_private"."forecast_snapshots";
begin
  select * into v_from from "app_private"."forecast_snapshots" x where x."id" = forecast_changes.from_snapshot;
  select * into v_to from "app_private"."forecast_snapshots" x where x."id" = forecast_changes.to_snapshot;
  if v_from."id" is null or v_to."id" is null
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'forecasts.read'), false)) or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_to."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  if v_from."tenant_id" <> v_to."tenant_id" or v_from."currency" <> v_to."currency" then
    raise exception 'Both snapshots must be of one organization and currency' using errcode = '22023', hint = 'FORECAST_MISMATCH';
  end if;
  return jsonb_build_object(
    'from', jsonb_build_object('id', v_from."id", 'organizationId', v_from."tenant_id", 'pipelineId', v_from."pipeline_id", 'since', v_from."period_start", 'until', v_from."period_end", 'currency', v_from."currency", 'target', v_from."target"::text, 'totals', v_from."totals", 'dealCount', v_from."deal_count", 'takenBy', v_from."taken_by", 'takenAt', v_from."taken_at"),
    'to', jsonb_build_object('id', v_to."id", 'organizationId', v_to."tenant_id", 'pipelineId', v_to."pipeline_id", 'since', v_to."period_start", 'until', v_to."period_end", 'currency', v_to."currency", 'target', v_to."target"::text, 'totals', v_to."totals", 'dealCount', v_to."deal_count", 'takenBy', v_to."taken_by", 'takenAt', v_to."taken_at"),
    'deals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'dealId', coalesce(b."deal_id", a."deal_id"),
        'name', coalesce(b."name", a."name"),
        'change', case
      when a."deal_id" is null then 'added'
      when b."deal_id" is null then 'removed'
      when a."outcome" = 'open' and b."outcome" = 'won' then 'won'
      when a."outcome" = 'open' and b."outcome" = 'lost' then 'lost'
      else 'changed'
    end,
        'before', case when a."deal_id" is null then null else jsonb_build_object('dealId', a."deal_id", 'name', a."name", 'ownerId', a."owner_id", 'stageId', a."stage_id", 'forecast', a."forecast_category"::text, 'outcome', a."outcome"::text, 'amount', a."amount"::text, 'closeOn', a."expected_close_on", 'closedAt', a."closed_at") end,
        'after', case when b."deal_id" is null then null else jsonb_build_object('dealId', b."deal_id", 'name', b."name", 'ownerId', b."owner_id", 'stageId', b."stage_id", 'forecast', b."forecast_category"::text, 'outcome', b."outcome"::text, 'amount', b."amount"::text, 'closeOn', b."expected_close_on", 'closedAt', b."closed_at") end
      ) order by coalesce(b."amount", a."amount") desc, coalesce(b."deal_id", a."deal_id")), '[]'::jsonb)
      from (select * from "app_private"."forecast_snapshot_deals" where "snapshot_id" = v_from."id") a
      full join (select * from "app_private"."forecast_snapshot_deals" where "snapshot_id" = v_to."id") b on b."deal_id" = a."deal_id"
      where a."deal_id" is null or b."deal_id" is null
      or a."amount" <> b."amount"
      or a."outcome" <> b."outcome"
      or a."forecast_category" is distinct from b."forecast_category"
      or a."stage_id" is distinct from b."stage_id"
      or a."expected_close_on" is distinct from b."expected_close_on"
      or a."owner_id" is distinct from b."owner_id"
    ));
end;
$$;
revoke execute on function "app_private"."forecast_changes"(uuid, uuid) from public, anon;
grant execute on function "app_private"."forecast_changes"(uuid, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."forecast_snapshots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."forecast_snapshots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."forecast_snapshots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."forecast_snapshots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."forecast_snapshot_deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."forecast_snapshot_deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."forecast_snapshot_deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."forecast_snapshot_deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:1a236d3062db7e93bf2739b0ee553543da0d1d3546fd673f331fd49953cbf0af
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block forecasts@1 managed
-- @bsb-hash sha256:b9555f460c25af1b92d2fc893f4efd8207860098be80a53fa15924d0c4a5ebb9
-- Snapshots of the deals forecast call over time: the totals by category and every deal they counted, a list per period, and what changed between two snapshots (added, removed, won, lost, moved).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Forecasts: snapshots of the forecast call over time, with the deals each
-- one counted, and what changed between two of them.
create table "better_supabase"."forecast_snapshots" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade,
  "period_start" date not null,
  "period_end" date not null,
  "currency" text not null constraint bsb_forecast_snapshots_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "target" bigint constraint bsb_forecast_snapshots_target_check check ("target" >= 0),
  "totals" jsonb not null constraint bsb_forecast_snapshots_totals_check check (jsonb_typeof("totals") = 'object'),
  "deal_count" integer not null default 0,
  "taken_by" uuid references auth.users (id) on delete set null,
  "taken_at" timestamptz not null default clock_timestamp(),
  constraint bsb_forecast_snapshots_check check ("period_end" >= "period_start")
);
create index forecast_snapshots_period_idx on "better_supabase"."forecast_snapshots" ("tenant_id", "period_start", "period_end", "taken_at" desc);
create index forecast_snapshots_pipeline_idx on "better_supabase"."forecast_snapshots" ("pipeline_id") where "pipeline_id" is not null;
create index forecast_snapshots_taken_by_idx on "better_supabase"."forecast_snapshots" ("taken_by") where "taken_by" is not null;
alter table "better_supabase"."forecast_snapshots" enable row level security;
revoke all on "better_supabase"."forecast_snapshots" from public, anon, authenticated;
grant select on "better_supabase"."forecast_snapshots" to authenticated;
grant all on "better_supabase"."forecast_snapshots" to service_role;
create table "better_supabase"."forecast_snapshot_deals" (
  "snapshot_id" uuid not null references "better_supabase"."forecast_snapshots" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "deal_id" uuid not null,
  "name" text not null,
  "owner_id" uuid,
  "stage_id" uuid,
  "forecast_category" text,
  "outcome" text not null,
  "amount" bigint not null,
  "expected_close_on" date,
  "closed_at" timestamptz,
  primary key ("snapshot_id", "deal_id")
);
create index forecast_snapshot_deals_deal_idx on "better_supabase"."forecast_snapshot_deals" ("tenant_id", "deal_id");
alter table "better_supabase"."forecast_snapshot_deals" enable row level security;
revoke all on "better_supabase"."forecast_snapshot_deals" from public, anon, authenticated;
grant select on "better_supabase"."forecast_snapshot_deals" to authenticated;
grant all on "better_supabase"."forecast_snapshot_deals" to service_role;
create policy bsb_forecast_snapshots_read on "better_supabase"."forecast_snapshots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));
create policy bsb_forecast_snapshot_deals_read on "better_supabase"."forecast_snapshot_deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));

-- Takes a snapshot of the forecast call for one currency between since and
-- until: the deal_forecast totals for the whole organization and every deal
-- they count (open deals closing in the period, deals closed in it). Needs
-- forecasts.snapshot. Returns the snapshot without its deals.
create or replace function "better_supabase"."take_forecast_snapshot"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
  v_currency text := upper(take_forecast_snapshot.currency);
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', take_forecast_snapshot.tenant, 'forecasts.snapshot'), false)) then
    raise exception 'Taking a forecast snapshot needs the forecasts.snapshot permission' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if take_forecast_snapshot.since is null or take_forecast_snapshot.until is null
    or take_forecast_snapshot.until < take_forecast_snapshot.since
    or take_forecast_snapshot.until - take_forecast_snapshot.since > 366 then
    raise exception 'until must be on or after since, at most a year later' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter code' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.target < 0 then
    raise exception 'target must not be negative' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.pipeline is not null and not exists (
    select 1 from "better_supabase"."pipelines" x
    where x."id" = take_forecast_snapshot.pipeline and x."tenant_id" = take_forecast_snapshot.tenant
  ) then
    raise exception 'The organization has no pipeline with this id' using errcode = 'P0002', hint = 'FORECAST_PIPELINE_UNKNOWN';
  end if;
  insert into "better_supabase"."forecast_snapshots" ("tenant_id", "pipeline_id", "period_start", "period_end", "currency", "target", "totals", "taken_by")
  values (take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, "better_supabase"."deal_forecast"(take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, null), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."forecast_snapshot_deals" ("snapshot_id", "tenant_id", "deal_id", "name", "owner_id", "stage_id", "forecast_category", "outcome", "amount", "expected_close_on", "closed_at")
  select v_row."id", x."tenant_id", x."id", x."name", x."owner_id", x."stage_id", x."forecast_category"::text, x."outcome"::text, x."amount", x."expected_close_on", x."closed_at"
  from "better_supabase"."deals" x
  where x."tenant_id" = take_forecast_snapshot.tenant
    and x."currency" = v_currency
    and x."archived_at" is null
    and (take_forecast_snapshot.pipeline is null or x."pipeline_id" = take_forecast_snapshot.pipeline)
    and (
      (x."outcome" = 'open' and x."expected_close_on" between take_forecast_snapshot.since and take_forecast_snapshot.until)
      or (x."outcome" <> 'open' and x."closed_at"::date between take_forecast_snapshot.since and take_forecast_snapshot.until)
    );
  get diagnostics v_count = row_count;
  update "better_supabase"."forecast_snapshots" x set "deal_count" = v_count
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at");
end;
$$;
revoke execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) to authenticated, service_role;

-- The organization's snapshots, newest first, optionally of one pipeline and
-- of the period between since and until. Needs forecasts.read.
create or replace function "better_supabase"."forecast_snapshots"(tenant uuid, pipeline uuid default null, since date default null, until date default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.taken_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as item, x."taken_at" as taken_at, x."id" as id
    from "better_supabase"."forecast_snapshots" x
    where x."tenant_id" = forecast_snapshots.tenant
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'forecasts.read'), false))
      and (forecast_snapshots.pipeline is null or x."pipeline_id" = forecast_snapshots.pipeline)
      and (forecast_snapshots.since is null or x."period_start" = forecast_snapshots.since)
      and (forecast_snapshots.until is null or x."period_end" = forecast_snapshots.until)
    order by x."taken_at" desc, x."id"
    limit least(greatest(coalesce(forecast_snapshots.max_count, 50), 1), 200)
  ) z
$$;
revoke execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) from public, anon;
grant execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) to authenticated, service_role;

-- One snapshot with its deals, the largest amount first.
create or replace function "better_supabase"."forecast_snapshot"(snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
begin
  select * into v_row from "better_supabase"."forecast_snapshots" x where x."id" = forecast_snapshot.snapshot;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at") || jsonb_build_object('deals', (
    select coalesce(jsonb_agg(jsonb_build_object('dealId', y."deal_id", 'name', y."name", 'ownerId', y."owner_id", 'stageId', y."stage_id", 'forecast', y."forecast_category"::text, 'outcome', y."outcome"::text, 'amount', y."amount"::text, 'closeOn', y."expected_close_on", 'closedAt', y."closed_at") order by y."amount" desc, y."deal_id"), '[]'::jsonb)
    from "better_supabase"."forecast_snapshot_deals" y where y."snapshot_id" = v_row."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."forecast_snapshot"(uuid) from public, anon;
grant execute on function "better_supabase"."forecast_snapshot"(uuid) to authenticated, service_role;

-- What changed between two snapshots of one organization and currency: each
-- deal that was added, removed, won, lost or changed its amount, forecast
-- category, stage, owner or close date, with its values in both.
create or replace function "better_supabase"."forecast_changes"(from_snapshot uuid, to_snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."forecast_snapshots";
  v_to "better_supabase"."forecast_snapshots";
begin
  select * into v_from from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.from_snapshot;
  select * into v_to from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.to_snapshot;
  if v_from."id" is null or v_to."id" is null
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'forecasts.read'), false)) or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_to."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  if v_from."tenant_id" <> v_to."tenant_id" or v_from."currency" <> v_to."currency" then
    raise exception 'Both snapshots must be of one organization and currency' using errcode = '22023', hint = 'FORECAST_MISMATCH';
  end if;
  return jsonb_build_object(
    'from', jsonb_build_object('id', v_from."id", 'organizationId', v_from."tenant_id", 'pipelineId', v_from."pipeline_id", 'since', v_from."period_start", 'until', v_from."period_end", 'currency', v_from."currency", 'target', v_from."target"::text, 'totals', v_from."totals", 'dealCount', v_from."deal_count", 'takenBy', v_from."taken_by", 'takenAt', v_from."taken_at"),
    'to', jsonb_build_object('id', v_to."id", 'organizationId', v_to."tenant_id", 'pipelineId', v_to."pipeline_id", 'since', v_to."period_start", 'until', v_to."period_end", 'currency', v_to."currency", 'target', v_to."target"::text, 'totals', v_to."totals", 'dealCount', v_to."deal_count", 'takenBy', v_to."taken_by", 'takenAt', v_to."taken_at"),
    'deals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'dealId', coalesce(b."deal_id", a."deal_id"),
        'name', coalesce(b."name", a."name"),
        'change', case
      when a."deal_id" is null then 'added'
      when b."deal_id" is null then 'removed'
      when a."outcome" = 'open' and b."outcome" = 'won' then 'won'
      when a."outcome" = 'open' and b."outcome" = 'lost' then 'lost'
      else 'changed'
    end,
        'before', case when a."deal_id" is null then null else jsonb_build_object('dealId', a."deal_id", 'name', a."name", 'ownerId', a."owner_id", 'stageId', a."stage_id", 'forecast', a."forecast_category"::text, 'outcome', a."outcome"::text, 'amount', a."amount"::text, 'closeOn', a."expected_close_on", 'closedAt', a."closed_at") end,
        'after', case when b."deal_id" is null then null else jsonb_build_object('dealId', b."deal_id", 'name', b."name", 'ownerId', b."owner_id", 'stageId', b."stage_id", 'forecast', b."forecast_category"::text, 'outcome', b."outcome"::text, 'amount', b."amount"::text, 'closeOn', b."expected_close_on", 'closedAt', b."closed_at") end
      ) order by coalesce(b."amount", a."amount") desc, coalesce(b."deal_id", a."deal_id")), '[]'::jsonb)
      from (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_from."id") a
      full join (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_to."id") b on b."deal_id" = a."deal_id"
      where a."deal_id" is null or b."deal_id" is null
      or a."amount" <> b."amount"
      or a."outcome" <> b."outcome"
      or a."forecast_category" is distinct from b."forecast_category"
      or a."stage_id" is distinct from b."stage_id"
      or a."expected_close_on" is distinct from b."expected_close_on"
      or a."owner_id" is distinct from b."owner_id"
    ));
end;
$$;
revoke execute on function "better_supabase"."forecast_changes"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."forecast_changes"(uuid, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshot_deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshot_deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshot_deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshot_deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.forecasts.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."take_forecast_snapshot"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."take_forecast_snapshot"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) from public, anon;
grant execute on function "api"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) to authenticated, service_role;

create or replace function "api"."forecast_snapshots"(tenant uuid, pipeline uuid default null, since date default null, until date default null, max_count integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."forecast_snapshots"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."forecast_snapshots"(uuid, uuid, date, date, integer) from public, anon;
grant execute on function "api"."forecast_snapshots"(uuid, uuid, date, date, integer) to authenticated, service_role;

create or replace function "api"."forecast_snapshot"(snapshot uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."forecast_snapshot"($1) $$;
revoke execute on function "api"."forecast_snapshot"(uuid) from public, anon;
grant execute on function "api"."forecast_snapshot"(uuid) to authenticated, service_role;

create or replace function "api"."forecast_changes"(from_snapshot uuid, to_snapshot uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."forecast_changes"($1, $2) $$;
revoke execute on function "api"."forecast_changes"(uuid, uuid) from public, anon;
grant execute on function "api"."forecast_changes"(uuid, uuid) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:1a236d3062db7e93bf2739b0ee553543da0d1d3546fd673f331fd49953cbf0af
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block forecasts@1 managed
-- @bsb-hash sha256:5323f5ed2ee1d3ed0bb8c48900c8a4c068b590796b52fd89ea1305e2d0a414a6
-- Snapshots of the deals forecast call over time: the totals by category and every deal they counted, a list per period, and what changed between two snapshots (added, removed, won, lost, moved).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Forecasts: snapshots of the forecast call over time, with the deals each
-- one counted, and what changed between two of them.
-- better_supabase.forecast_snapshots is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."forecast_snapshots" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."forecast_snapshots" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."forecast_snapshots" add column if not exists "pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade;
alter table "better_supabase"."forecast_snapshots" add column if not exists "period_start" date;
alter table "better_supabase"."forecast_snapshots" add column if not exists "period_end" date;
alter table "better_supabase"."forecast_snapshots" add column if not exists "currency" text constraint bsb_forecast_snapshots_currency_check check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."forecast_snapshots" add column if not exists "target" bigint constraint bsb_forecast_snapshots_target_check check ("target" >= 0);
alter table "better_supabase"."forecast_snapshots" add column if not exists "totals" jsonb constraint bsb_forecast_snapshots_totals_check check (jsonb_typeof("totals") = 'object');
alter table "better_supabase"."forecast_snapshots" add column if not exists "deal_count" integer not null default 0;
alter table "better_supabase"."forecast_snapshots" add column if not exists "taken_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."forecast_snapshots" add column if not exists "taken_at" timestamptz not null default clock_timestamp();
create index if not exists forecast_snapshots_period_idx on "better_supabase"."forecast_snapshots" ("tenant_id", "period_start", "period_end", "taken_at" desc);
create index if not exists forecast_snapshots_pipeline_idx on "better_supabase"."forecast_snapshots" ("pipeline_id") where "pipeline_id" is not null;
create index if not exists forecast_snapshots_taken_by_idx on "better_supabase"."forecast_snapshots" ("taken_by") where "taken_by" is not null;
alter table "better_supabase"."forecast_snapshots" enable row level security;
grant select on "better_supabase"."forecast_snapshots" to authenticated;
grant all on "better_supabase"."forecast_snapshots" to service_role;
-- better_supabase.forecast_snapshot_deals is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "snapshot_id" uuid references "better_supabase"."forecast_snapshots" ("id") on delete cascade;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "deal_id" uuid;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "name" text;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "owner_id" uuid;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "stage_id" uuid;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "forecast_category" text;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "outcome" text;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "amount" bigint;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "expected_close_on" date;
alter table "better_supabase"."forecast_snapshot_deals" add column if not exists "closed_at" timestamptz;
create index if not exists forecast_snapshot_deals_deal_idx on "better_supabase"."forecast_snapshot_deals" ("tenant_id", "deal_id");
alter table "better_supabase"."forecast_snapshot_deals" enable row level security;
grant select on "better_supabase"."forecast_snapshot_deals" to authenticated;
grant all on "better_supabase"."forecast_snapshot_deals" to service_role;
create policy bsb_forecast_snapshots_select on "better_supabase"."forecast_snapshots"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));
create policy bsb_forecast_snapshot_deals_select on "better_supabase"."forecast_snapshot_deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')));

-- Takes a snapshot of the forecast call for one currency between since and
-- until: the deal_forecast totals for the whole organization and every deal
-- they count (open deals closing in the period, deals closed in it). Needs
-- forecasts.snapshot. Returns the snapshot without its deals.
create or replace function "better_supabase"."take_forecast_snapshot"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
  v_currency text := upper(take_forecast_snapshot.currency);
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', take_forecast_snapshot.tenant, 'forecasts.snapshot'), false)) then
    raise exception 'Taking a forecast snapshot needs the forecasts.snapshot permission' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if take_forecast_snapshot.since is null or take_forecast_snapshot.until is null
    or take_forecast_snapshot.until < take_forecast_snapshot.since
    or take_forecast_snapshot.until - take_forecast_snapshot.since > 366 then
    raise exception 'until must be on or after since, at most a year later' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter code' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.target < 0 then
    raise exception 'target must not be negative' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.pipeline is not null and not exists (
    select 1 from "better_supabase"."pipelines" x
    where x."id" = take_forecast_snapshot.pipeline and x."tenant_id" = take_forecast_snapshot.tenant
  ) then
    raise exception 'The organization has no pipeline with this id' using errcode = 'P0002', hint = 'FORECAST_PIPELINE_UNKNOWN';
  end if;
  insert into "better_supabase"."forecast_snapshots" ("tenant_id", "pipeline_id", "period_start", "period_end", "currency", "target", "totals", "taken_by")
  values (take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, "better_supabase"."deal_forecast"(take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, null), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."forecast_snapshot_deals" ("snapshot_id", "tenant_id", "deal_id", "name", "owner_id", "stage_id", "forecast_category", "outcome", "amount", "expected_close_on", "closed_at")
  select v_row."id", x."tenant_id", x."id", x."name", x."owner_id", x."stage_id", better_supabase.as_column_type(x."forecast_category"::text, (null::"better_supabase"."forecast_snapshot_deals")."forecast_category"), better_supabase.as_column_type(x."outcome"::text, (null::"better_supabase"."forecast_snapshot_deals")."outcome"), x."amount", x."expected_close_on", x."closed_at"
  from "better_supabase"."deals" x
  where x."tenant_id" = take_forecast_snapshot.tenant
    and x."currency" = v_currency
    and x."archived_at" is null
    and (take_forecast_snapshot.pipeline is null or x."pipeline_id" = take_forecast_snapshot.pipeline)
    and (
      (x."outcome" = 'open' and x."expected_close_on" between take_forecast_snapshot.since and take_forecast_snapshot.until)
      or (x."outcome" <> 'open' and x."closed_at"::date between take_forecast_snapshot.since and take_forecast_snapshot.until)
    );
  get diagnostics v_count = row_count;
  update "better_supabase"."forecast_snapshots" x set "deal_count" = v_count
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at");
end;
$$;
revoke execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) to authenticated, service_role;

-- The organization's snapshots, newest first, optionally of one pipeline and
-- of the period between since and until. Needs forecasts.read.
create or replace function "better_supabase"."forecast_snapshots"(tenant uuid, pipeline uuid default null, since date default null, until date default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.taken_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as item, x."taken_at" as taken_at, x."id" as id
    from "better_supabase"."forecast_snapshots" x
    where x."tenant_id" = forecast_snapshots.tenant
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'forecasts.read'), false))
      and (forecast_snapshots.pipeline is null or x."pipeline_id" = forecast_snapshots.pipeline)
      and (forecast_snapshots.since is null or x."period_start" = forecast_snapshots.since)
      and (forecast_snapshots.until is null or x."period_end" = forecast_snapshots.until)
    order by x."taken_at" desc, x."id"
    limit least(greatest(coalesce(forecast_snapshots.max_count, 50), 1), 200)
  ) z
$$;
revoke execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) from public, anon;
grant execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) to authenticated, service_role;

-- One snapshot with its deals, the largest amount first.
create or replace function "better_supabase"."forecast_snapshot"(snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
begin
  select * into v_row from "better_supabase"."forecast_snapshots" x where x."id" = forecast_snapshot.snapshot;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at") || jsonb_build_object('deals', (
    select coalesce(jsonb_agg(jsonb_build_object('dealId', y."deal_id", 'name', y."name", 'ownerId', y."owner_id", 'stageId', y."stage_id", 'forecast', y."forecast_category"::text, 'outcome', y."outcome"::text, 'amount', y."amount"::text, 'closeOn', y."expected_close_on", 'closedAt', y."closed_at") order by y."amount" desc, y."deal_id"), '[]'::jsonb)
    from "better_supabase"."forecast_snapshot_deals" y where y."snapshot_id" = v_row."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."forecast_snapshot"(uuid) from public, anon;
grant execute on function "better_supabase"."forecast_snapshot"(uuid) to authenticated, service_role;

-- What changed between two snapshots of one organization and currency: each
-- deal that was added, removed, won, lost or changed its amount, forecast
-- category, stage, owner or close date, with its values in both.
create or replace function "better_supabase"."forecast_changes"(from_snapshot uuid, to_snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."forecast_snapshots";
  v_to "better_supabase"."forecast_snapshots";
begin
  select * into v_from from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.from_snapshot;
  select * into v_to from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.to_snapshot;
  if v_from."id" is null or v_to."id" is null
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'forecasts.read'), false)) or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_to."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  if v_from."tenant_id" <> v_to."tenant_id" or v_from."currency" <> v_to."currency" then
    raise exception 'Both snapshots must be of one organization and currency' using errcode = '22023', hint = 'FORECAST_MISMATCH';
  end if;
  return jsonb_build_object(
    'from', jsonb_build_object('id', v_from."id", 'organizationId', v_from."tenant_id", 'pipelineId', v_from."pipeline_id", 'since', v_from."period_start", 'until', v_from."period_end", 'currency', v_from."currency", 'target', v_from."target"::text, 'totals', v_from."totals", 'dealCount', v_from."deal_count", 'takenBy', v_from."taken_by", 'takenAt', v_from."taken_at"),
    'to', jsonb_build_object('id', v_to."id", 'organizationId', v_to."tenant_id", 'pipelineId', v_to."pipeline_id", 'since', v_to."period_start", 'until', v_to."period_end", 'currency', v_to."currency", 'target', v_to."target"::text, 'totals', v_to."totals", 'dealCount', v_to."deal_count", 'takenBy', v_to."taken_by", 'takenAt', v_to."taken_at"),
    'deals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'dealId', coalesce(b."deal_id", a."deal_id"),
        'name', coalesce(b."name", a."name"),
        'change', case
      when a."deal_id" is null then 'added'
      when b."deal_id" is null then 'removed'
      when a."outcome" = 'open' and b."outcome" = 'won' then 'won'
      when a."outcome" = 'open' and b."outcome" = 'lost' then 'lost'
      else 'changed'
    end,
        'before', case when a."deal_id" is null then null else jsonb_build_object('dealId', a."deal_id", 'name', a."name", 'ownerId', a."owner_id", 'stageId', a."stage_id", 'forecast', a."forecast_category"::text, 'outcome', a."outcome"::text, 'amount', a."amount"::text, 'closeOn', a."expected_close_on", 'closedAt', a."closed_at") end,
        'after', case when b."deal_id" is null then null else jsonb_build_object('dealId', b."deal_id", 'name', b."name", 'ownerId', b."owner_id", 'stageId', b."stage_id", 'forecast', b."forecast_category"::text, 'outcome', b."outcome"::text, 'amount', b."amount"::text, 'closeOn', b."expected_close_on", 'closedAt', b."closed_at") end
      ) order by coalesce(b."amount", a."amount") desc, coalesce(b."deal_id", a."deal_id")), '[]'::jsonb)
      from (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_from."id") a
      full join (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_to."id") b on b."deal_id" = a."deal_id"
      where a."deal_id" is null or b."deal_id" is null
      or a."amount" <> b."amount"
      or a."outcome" <> b."outcome"
      or a."forecast_category" is distinct from b."forecast_category"
      or a."stage_id" is distinct from b."stage_id"
      or a."expected_close_on" is distinct from b."expected_close_on"
      or a."owner_id" is distinct from b."owner_id"
    ));
end;
$$;
revoke execute on function "better_supabase"."forecast_changes"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."forecast_changes"(uuid, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshots" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshot_deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshot_deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshot_deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshot_deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:1a236d3062db7e93bf2739b0ee553543da0d1d3546fd673f331fd49953cbf0af
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block forecasts@1 managed
-- @bsb-hash sha256:3bb98915b20586c372f2491f381128fd72574288b10d32759ff84733e05fe4b7
-- Snapshots of the deals forecast call over time: the totals by category and every deal they counted, a list per period, and what changed between two snapshots (added, removed, won, lost, moved).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Forecasts: snapshots of the forecast call over time, with the deals each
-- one counted, and what changed between two of them.
create table "better_supabase"."forecast_snapshots" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade,
  "period_start" date not null,
  "period_end" date not null,
  "currency" text not null constraint bsb_forecast_snapshots_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "target" bigint constraint bsb_forecast_snapshots_target_check check ("target" >= 0),
  "totals" jsonb not null constraint bsb_forecast_snapshots_totals_check check (jsonb_typeof("totals") = 'object'),
  "deal_count" integer not null default 0,
  "taken_by" uuid references auth.users (id) on delete set null,
  "taken_at" timestamptz not null default clock_timestamp(),
  constraint bsb_forecast_snapshots_check check ("period_end" >= "period_start")
);
create index forecast_snapshots_period_idx on "better_supabase"."forecast_snapshots" ("org_id", "period_start", "period_end", "taken_at" desc);
create index forecast_snapshots_pipeline_idx on "better_supabase"."forecast_snapshots" ("pipeline_id") where "pipeline_id" is not null;
create index forecast_snapshots_taken_by_idx on "better_supabase"."forecast_snapshots" ("taken_by") where "taken_by" is not null;
alter table "better_supabase"."forecast_snapshots" enable row level security;
revoke all on "better_supabase"."forecast_snapshots" from public, anon, authenticated;
grant select on "better_supabase"."forecast_snapshots" to authenticated;
grant all on "better_supabase"."forecast_snapshots" to service_role;
create table "better_supabase"."forecast_snapshot_deals" (
  "snapshot_id" uuid not null references "better_supabase"."forecast_snapshots" ("id") on delete cascade,
  "org_id" uuid not null,
  "deal_id" uuid not null,
  "name" text not null,
  "owner_id" uuid,
  "stage_id" uuid,
  "forecast_category" text,
  "outcome" text not null,
  "amount" bigint not null,
  "expected_close_on" date,
  "closed_at" timestamptz,
  primary key ("snapshot_id", "deal_id")
);
create index forecast_snapshot_deals_deal_idx on "better_supabase"."forecast_snapshot_deals" ("org_id", "deal_id");
alter table "better_supabase"."forecast_snapshot_deals" enable row level security;
revoke all on "better_supabase"."forecast_snapshot_deals" from public, anon, authenticated;
grant select on "better_supabase"."forecast_snapshot_deals" to authenticated;
grant all on "better_supabase"."forecast_snapshot_deals" to service_role;
create policy bsb_forecast_snapshots_read on "better_supabase"."forecast_snapshots"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('forecasts.read')));
create policy bsb_forecast_snapshot_deals_read on "better_supabase"."forecast_snapshot_deals"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('forecasts.read')));

-- Takes a snapshot of the forecast call for one currency between since and
-- until: the deal_forecast totals for the whole organization and every deal
-- they count (open deals closing in the period, deals closed in it). Needs
-- forecasts.snapshot. Returns the snapshot without its deals.
create or replace function "better_supabase"."take_forecast_snapshot"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
  v_currency text := upper(take_forecast_snapshot.currency);
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', take_forecast_snapshot.tenant, 'forecasts.snapshot'), false)) then
    raise exception 'Taking a forecast snapshot needs the forecasts.snapshot permission' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if take_forecast_snapshot.since is null or take_forecast_snapshot.until is null
    or take_forecast_snapshot.until < take_forecast_snapshot.since
    or take_forecast_snapshot.until - take_forecast_snapshot.since > 366 then
    raise exception 'until must be on or after since, at most a year later' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter code' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.target < 0 then
    raise exception 'target must not be negative' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.pipeline is not null and not exists (
    select 1 from "better_supabase"."pipelines" x
    where x."id" = take_forecast_snapshot.pipeline and x."org_id" = take_forecast_snapshot.tenant
  ) then
    raise exception 'The organization has no pipeline with this id' using errcode = 'P0002', hint = 'FORECAST_PIPELINE_UNKNOWN';
  end if;
  insert into "better_supabase"."forecast_snapshots" ("org_id", "pipeline_id", "period_start", "period_end", "currency", "target", "totals", "taken_by")
  values (take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, "better_supabase"."deal_forecast"(take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, null), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."forecast_snapshot_deals" ("snapshot_id", "org_id", "deal_id", "name", "owner_id", "stage_id", "forecast_category", "outcome", "amount", "expected_close_on", "closed_at")
  select v_row."id", x."org_id", x."id", x."name", x."owner_id", x."stage_id", x."forecast_category"::text, x."outcome"::text, x."amount", x."expected_close_on", x."closed_at"
  from "better_supabase"."deals" x
  where x."org_id" = take_forecast_snapshot.tenant
    and x."currency" = v_currency
    and x."archived_at" is null
    and (take_forecast_snapshot.pipeline is null or x."pipeline_id" = take_forecast_snapshot.pipeline)
    and (
      (x."outcome" = 'open' and x."expected_close_on" between take_forecast_snapshot.since and take_forecast_snapshot.until)
      or (x."outcome" <> 'open' and x."closed_at"::date between take_forecast_snapshot.since and take_forecast_snapshot.until)
    );
  get diagnostics v_count = row_count;
  update "better_supabase"."forecast_snapshots" x set "deal_count" = v_count
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at");
end;
$$;
revoke execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."take_forecast_snapshot"(uuid, uuid, date, date, text, bigint) to authenticated, service_role;

-- The organization's snapshots, newest first, optionally of one pipeline and
-- of the period between since and until. Needs forecasts.read.
create or replace function "better_supabase"."forecast_snapshots"(tenant uuid, pipeline uuid default null, since date default null, until date default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.taken_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as item, x."taken_at" as taken_at, x."id" as id
    from "better_supabase"."forecast_snapshots" x
    where x."org_id" = forecast_snapshots.tenant
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."org_id", 'forecasts.read'), false))
      and (forecast_snapshots.pipeline is null or x."pipeline_id" = forecast_snapshots.pipeline)
      and (forecast_snapshots.since is null or x."period_start" = forecast_snapshots.since)
      and (forecast_snapshots.until is null or x."period_end" = forecast_snapshots.until)
    order by x."taken_at" desc, x."id"
    limit least(greatest(coalesce(forecast_snapshots.max_count, 50), 1), 200)
  ) z
$$;
revoke execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) from public, anon;
grant execute on function "better_supabase"."forecast_snapshots"(uuid, uuid, date, date, integer) to authenticated, service_role;

-- One snapshot with its deals, the largest amount first.
create or replace function "better_supabase"."forecast_snapshot"(snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forecast_snapshots";
begin
  select * into v_row from "better_supabase"."forecast_snapshots" x where x."id" = forecast_snapshot.snapshot;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at") || jsonb_build_object('deals', (
    select coalesce(jsonb_agg(jsonb_build_object('dealId', y."deal_id", 'name', y."name", 'ownerId', y."owner_id", 'stageId', y."stage_id", 'forecast', y."forecast_category"::text, 'outcome', y."outcome"::text, 'amount', y."amount"::text, 'closeOn', y."expected_close_on", 'closedAt', y."closed_at") order by y."amount" desc, y."deal_id"), '[]'::jsonb)
    from "better_supabase"."forecast_snapshot_deals" y where y."snapshot_id" = v_row."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."forecast_snapshot"(uuid) from public, anon;
grant execute on function "better_supabase"."forecast_snapshot"(uuid) to authenticated, service_role;

-- What changed between two snapshots of one organization and currency: each
-- deal that was added, removed, won, lost or changed its amount, forecast
-- category, stage, owner or close date, with its values in both.
create or replace function "better_supabase"."forecast_changes"(from_snapshot uuid, to_snapshot uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from "better_supabase"."forecast_snapshots";
  v_to "better_supabase"."forecast_snapshots";
begin
  select * into v_from from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.from_snapshot;
  select * into v_to from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.to_snapshot;
  if v_from."id" is null or v_to."id" is null
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."org_id", 'forecasts.read'), false)) or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_to."org_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  if v_from."org_id" <> v_to."org_id" or v_from."currency" <> v_to."currency" then
    raise exception 'Both snapshots must be of one organization and currency' using errcode = '22023', hint = 'FORECAST_MISMATCH';
  end if;
  return jsonb_build_object(
    'from', jsonb_build_object('id', v_from."id", 'organizationId', v_from."org_id", 'pipelineId', v_from."pipeline_id", 'since', v_from."period_start", 'until', v_from."period_end", 'currency', v_from."currency", 'target', v_from."target"::text, 'totals', v_from."totals", 'dealCount', v_from."deal_count", 'takenBy', v_from."taken_by", 'takenAt', v_from."taken_at"),
    'to', jsonb_build_object('id', v_to."id", 'organizationId', v_to."org_id", 'pipelineId', v_to."pipeline_id", 'since', v_to."period_start", 'until', v_to."period_end", 'currency', v_to."currency", 'target', v_to."target"::text, 'totals', v_to."totals", 'dealCount', v_to."deal_count", 'takenBy', v_to."taken_by", 'takenAt', v_to."taken_at"),
    'deals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'dealId', coalesce(b."deal_id", a."deal_id"),
        'name', coalesce(b."name", a."name"),
        'change', case
      when a."deal_id" is null then 'added'
      when b."deal_id" is null then 'removed'
      when a."outcome" = 'open' and b."outcome" = 'won' then 'won'
      when a."outcome" = 'open' and b."outcome" = 'lost' then 'lost'
      else 'changed'
    end,
        'before', case when a."deal_id" is null then null else jsonb_build_object('dealId', a."deal_id", 'name', a."name", 'ownerId', a."owner_id", 'stageId', a."stage_id", 'forecast', a."forecast_category"::text, 'outcome', a."outcome"::text, 'amount', a."amount"::text, 'closeOn', a."expected_close_on", 'closedAt', a."closed_at") end,
        'after', case when b."deal_id" is null then null else jsonb_build_object('dealId', b."deal_id", 'name', b."name", 'ownerId', b."owner_id", 'stageId', b."stage_id", 'forecast', b."forecast_category"::text, 'outcome', b."outcome"::text, 'amount', b."amount"::text, 'closeOn', b."expected_close_on", 'closedAt', b."closed_at") end
      ) order by coalesce(b."amount", a."amount") desc, coalesce(b."deal_id", a."deal_id")), '[]'::jsonb)
      from (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_from."id") a
      full join (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_to."id") b on b."deal_id" = a."deal_id"
      where a."deal_id" is null or b."deal_id" is null
      or a."amount" <> b."amount"
      or a."outcome" <> b."outcome"
      or a."forecast_category" is distinct from b."forecast_category"
      or a."stage_id" is distinct from b."stage_id"
      or a."expected_close_on" is distinct from b."expected_close_on"
      or a."owner_id" is distinct from b."owner_id"
    ));
end;
$$;
revoke execute on function "better_supabase"."forecast_changes"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."forecast_changes"(uuid, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshots" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshots" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshots" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshots" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshot_deals" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshot_deals" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshot_deals" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshot_deals" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:1a236d3062db7e93bf2739b0ee553543da0d1d3546fd673f331fd49953cbf0af
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
