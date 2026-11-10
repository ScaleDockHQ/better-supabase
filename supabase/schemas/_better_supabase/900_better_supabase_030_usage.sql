-- better-supabase module: usage
-- @bsb-block usage@8 managed
-- @bsb-hash sha256:3a03dcfa4fe8f99ab94d5a2fc87af4ffe0819110d4bd62ab843e6e76e2dbabe9
-- Usage counters per tenant, meter and day with idempotent increments, quotas per tenant or plan, within_quota() for policies and consume_quota(), which raises quota_exceeded. unreported_usage() feeds reportUsageToStripe.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Usage per tenant, meter and UTC day. Quotas sum the days of their period.
create table "better_supabase"."usage_counters" (
  "tenant_id" uuid not null,
  "meter" text not null constraint bsb_usage_counters_meter_check check ("meter" ~ '^[a-z][a-z0-9_.:-]{0,63}$'),
  "day" date not null,
  "value" numeric not null default 0 constraint bsb_usage_counters_value_check check ("value" >= 0),
  "reported_value" numeric not null default 0 constraint bsb_usage_counters_reported_value_check check ("reported_value" >= 0),
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "meter", "day")
);
-- Quantities are numeric, so a meter can count fractions (GB-hours, credits).
alter table "better_supabase"."usage_counters" alter column "value" type numeric;
alter table "better_supabase"."usage_counters" alter column "reported_value" type numeric;
create index usage_counters_unreported_idx on "better_supabase"."usage_counters" ("day")
  where "value" > "reported_value";
alter table "better_supabase"."usage_counters" enable row level security;
revoke all on "better_supabase"."usage_counters" from public, anon, authenticated;
grant select on "better_supabase"."usage_counters" to authenticated;
grant all on "better_supabase"."usage_counters" to service_role;
create policy bsb_usage_counters_read on "better_supabase"."usage_counters"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('usage.read')));

-- One row per idempotency key, so a retried increment counts once.
create table "better_supabase"."usage_events" (
  "tenant_id" uuid not null,
  "meter" text not null,
  "idempotency_key" text not null,
  "quantity" numeric not null,
  "recorded_at" timestamptz not null default now(),
  primary key ("tenant_id", "meter", "idempotency_key")
);
alter table "better_supabase"."usage_events" alter column "quantity" type numeric;

-- options.history: one row per recorded quantity, with who (actor_id) and
-- what (source, metadata) used it, for a usage page.
create table "better_supabase"."usage_history" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "meter" text not null,
  "quantity" numeric not null,
  "actor_id" uuid,
  "source" text constraint bsb_usage_history_source_check check (length("source") <= 200),
  "metadata" jsonb not null default '{}',
  "recorded_at" timestamptz not null default now()
);
create index usage_history_tenant_idx on "better_supabase"."usage_history" ("tenant_id", "recorded_at" desc, "id" desc);
alter table "better_supabase"."usage_history" enable row level security;
revoke all on "better_supabase"."usage_history" from public, anon, authenticated;
grant select on "better_supabase"."usage_history" to authenticated;
grant all on "better_supabase"."usage_history" to service_role;
create policy bsb_usage_history_read on "better_supabase"."usage_history"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('usage.read')));

create index usage_events_recorded_at_idx on "better_supabase"."usage_events" ("recorded_at");
alter table "better_supabase"."usage_events" enable row level security;
revoke all on "better_supabase"."usage_events" from public, anon, authenticated;
grant all on "better_supabase"."usage_events" to service_role;

-- A tenant row overrides the plan rows; of several plan rows the highest
-- limit wins. A null limit is unlimited, so it wins over every limit.
create table "better_supabase"."usage_quotas" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "plan" text,
  "meter" text not null constraint bsb_usage_quotas_meter_check check ("meter" ~ '^[a-z][a-z0-9_.:-]{0,63}$'),
  "limit" numeric constraint bsb_usage_quotas_limit_check check ("limit" >= 0),
  "period" text not null default 'month' constraint bsb_usage_quotas_period_check check ("period" in ('day', 'week', 'month', 'year', 'billing')),
  "created_at" timestamptz not null default now(),
  constraint bsb_usage_quotas_check check (("tenant_id" is null) <> ("plan" is null)),
  unique nulls not distinct ("tenant_id", "plan", "meter")
);
alter table "better_supabase"."usage_quotas" alter column "limit" type numeric;
alter table "better_supabase"."usage_quotas" alter column "limit" drop not null;
alter table "better_supabase"."usage_quotas" enable row level security;
revoke all on "better_supabase"."usage_quotas" from public, anon, authenticated;
grant select on "better_supabase"."usage_quotas" to authenticated;
grant all on "better_supabase"."usage_quotas" to service_role;
create policy bsb_usage_quotas_read on "better_supabase"."usage_quotas"
  for select to authenticated
  using ("tenant_id" is null or "tenant_id" in (select better_supabase.tenant_ids_with('usage.read')));

-- The bigint signatures and return types before quantities were numeric.

-- The signatures before usage carried a source, metadata and actor.

-- The signature before the report could skip meters and tenants.


-- The quota that applies to tenant and meter, or no row. An unlimited quota
-- is a row with a null quota_limit.
create or replace function "better_supabase"."usage_quota"(tenant uuid, meter text)
returns table (quota_limit numeric, period text)
language sql
stable
security definer
set search_path = ''
as $$
  select q."limit", q."period"
  from "better_supabase"."usage_quotas" q
  where q."meter" = usage_quota.meter
    and (q."tenant_id" = usage_quota.tenant or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (better_supabase.tenant_entitlements(tenant)) or q."plan" = any (better_supabase.tenant_plans(tenant)))))
  order by (q."tenant_id" is not null) desc, q."limit" desc nulls first
  limit 1
$$;

-- Sets the quota of one tenant or one plan (exactly one of them) on a meter;
-- a null quota_limit is unlimited. A tenant quota overrides the plan's.
create or replace function "better_supabase"."set_usage_quota"(
  tenant uuid,
  plan text,
  meter text,
  quota_limit numeric,
  period text default 'month'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  changed integer;
begin
  if (tenant is null) = (plan is null) then
    raise exception 'set_usage_quota needs a tenant or a plan, not both' using errcode = '22023', hint = 'USAGE_QUOTA_TARGET';
  end if;
  update "better_supabase"."usage_quotas" q
  set "limit" = quota_limit, "period" = coalesce(period, 'month')
  where q."meter" = meter
    and q."tenant_id" is not distinct from tenant
    and q."plan" is not distinct from plan;
  if not found then
    insert into "better_supabase"."usage_quotas" ("tenant_id", "plan", "meter", "limit", "period")
    values (tenant, plan, meter, quota_limit, coalesce(period, 'month'));
  end if;
end
$$;

-- Removes the quota of one tenant or plan on a meter; true when there was one.
create or replace function "better_supabase"."remove_usage_quota"(tenant uuid, plan text, meter text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if (tenant is null) = (plan is null) then
    raise exception 'remove_usage_quota needs a tenant or a plan, not both' using errcode = '22023', hint = 'USAGE_QUOTA_TARGET';
  end if;
  delete from "better_supabase"."usage_quotas" q
  where q."meter" = meter
    and q."tenant_id" is not distinct from tenant
    and q."plan" is not distinct from plan;
  return found;
end
$$;

-- The window of a period for tenant: the current UTC day, week, month or
-- year, or with 'billing' the app's usage_billing_period(tenant) (the
-- subscription's current period, say), falling back to the month.
create or replace function "better_supabase"."usage_window"(tenant uuid, period text default 'month')
returns table (starts_at timestamptz, ends_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_period text := coalesce(usage_window.period, 'month');
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_period = 'billing' then
    if to_regprocedure('"public"."usage_billing_period"(uuid)') is not null then
      -- Not a literal name, so plpgsql_check passes without the hook.
      execute format('select h.starts_at, h.ends_at from %s($1) h', to_regprocedure('"public"."usage_billing_period"(uuid)')::oid::regproc)
        into v_start, v_end using usage_window.tenant;
    end if;
    if v_start is null or v_end is null or v_end <= v_start then
      v_period := 'month';
      v_start := null;
    end if;
  end if;
  if v_start is null then
    v_start := date_trunc(v_period, now() at time zone 'utc') at time zone 'utc';
    v_end := v_start + ('1 ' || v_period)::interval;
  end if;
  return query select v_start, v_end;
end;
$$;

-- The first UTC day of the window of period that holds day, which can be
-- in an earlier window than now. Earlier billing periods are assumed to be as
-- long as the current one; past 120 of them it falls back to the month.
create or replace function "better_supabase"."usage_window_start"(tenant uuid, period text, day date)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_length interval;
  v_steps integer := 0;
begin
  if usage_window_start.period is null then
    return usage_window_start.day;
  end if;
  if usage_window_start.period <> 'billing' then
    return date_trunc(usage_window_start.period, usage_window_start.day)::date;
  end if;
  select w.starts_at, w.ends_at into v_start, v_end
  from "better_supabase"."usage_window"(usage_window_start.tenant, 'billing') w;
  v_length := age(v_end, v_start);
  while usage_window_start.day < (v_start at time zone 'utc')::date and v_steps < 120 loop
    v_start := v_start - v_length;
    v_steps := v_steps + 1;
  end loop;
  if usage_window_start.day < (v_start at time zone 'utc')::date then
    return date_trunc('month', usage_window_start.day)::date;
  end if;
  return (v_start at time zone 'utc')::date;
end;
$$;

-- Usage of meter in the current window of period, counted by UTC day.
create or replace function "better_supabase"."usage_used"(tenant uuid, meter text, period text default 'month')
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(c."value"), 0)::numeric
  from "better_supabase"."usage_counters" c, "better_supabase"."usage_window"(usage_used.tenant, usage_used.period) w
  where c."tenant_id" = usage_used.tenant
    and c."meter" = usage_used.meter
    and c."day" >= (w.starts_at at time zone 'utc')::date
    and c."day" < greatest((w.ends_at at time zone 'utc')::date, (w.starts_at at time zone 'utc')::date + 1)
$$;

-- The meter catalog (options.meters): meter to { unit, category, label }.
create or replace function "better_supabase"."usage_meters"()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '{}'::jsonb
$$;

-- { meter, used, limit, remaining, unlimited, period, resets_at }; limit and
-- remaining are null without a quota and for an unlimited one. Needs usage.read,
-- like usage_overview.
create or replace function "better_supabase"."usage_status"(tenant uuid, meter text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota record;
  used numeric;
  win record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  select * into quota from "better_supabase"."usage_quota"(tenant, meter);
  select * into win from "better_supabase"."usage_window"(tenant, coalesce(quota.period, 'month'));
  used := "better_supabase"."usage_used"(tenant, meter, coalesce(quota.period, 'month'));
  return jsonb_build_object(
    'meter', meter,
    'used', used,
    'limit', quota.quota_limit,
    'remaining', case when quota.quota_limit is null then null else greatest(quota.quota_limit - used, 0) end,
    'unlimited', quota.period is not null and quota.quota_limit is null,
    'period', coalesce(quota.period, 'month'),
    'resets_at', win.ends_at,
    'starts_at', win.starts_at
  ) || coalesce("better_supabase"."usage_meters"() -> meter, '{}'::jsonb);
end;
$$;

create or replace function "better_supabase"."usage_overview"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg("better_supabase"."usage_status"(usage_overview.tenant, m.meter) order by m.meter), '[]'::jsonb)
    from (
      select jsonb_object_keys("better_supabase"."usage_meters"()) as meter
      union
      select q."meter" from "better_supabase"."usage_quotas" q
      where q."tenant_id" = usage_overview.tenant
        or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (better_supabase.tenant_entitlements(usage_overview.tenant)) or q."plan" = any (better_supabase.tenant_plans(usage_overview.tenant))))
      union
      select distinct c."meter" from "better_supabase"."usage_counters" c
      where c."tenant_id" = usage_overview.tenant
    ) m
  );
end;
$$;

-- For policies: whether quantity more fits the tenant's quota. False for a
-- caller outside the tenant, so it can't probe another tenant's usage.
--   with check (better_supabase.within_quota(organization_id, 'projects'))
create or replace function "better_supabase"."within_quota"(tenant uuid, meter text, quantity bigint default 1)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.has_organization_role(tenant), false)) then
    return false;
  end if;
  select * into quota from "better_supabase"."usage_quota"(tenant, meter);
  if quota.quota_limit is null then
    return true;
  end if;
  return "better_supabase"."usage_used"(tenant, meter, quota.period) + quantity <= quota.quota_limit;
end;
$$;

-- Adds quantity once per idempotency key, for usage.record or the service
-- role. Returns { recorded, used, today }: recorded is false for a key seen
-- before, used is the usage in the quota's period and today the UTC day's. With options.history, also keeps
-- who (the caller, or actor for the service role) and what (source,
-- metadata) used it.
create or replace function "better_supabase"."record_usage"(
  tenant uuid,
  meter text,
  quantity numeric default 1,
  idempotency_key text default null,
  source text default null,
  metadata jsonb default null,
  actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  today date := (now() at time zone 'utc')::date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.record'), false)) then
    raise exception 'Not allowed to record usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  if quantity is null or quantity < 0 then
    raise exception 'quantity must be zero or more' using errcode = '22023', hint = 'USAGE_QUANTITY';
  end if;
  if idempotency_key is not null then
    insert into "better_supabase"."usage_events" ("tenant_id", "meter", "idempotency_key", "quantity")
    values (tenant, meter, idempotency_key, quantity)
    on conflict do nothing;
    if not found then
      return jsonb_build_object('recorded', false, 'used', "better_supabase"."usage_used"(tenant, meter, coalesce((select q.period from "better_supabase"."usage_quota"(tenant, meter) q), 'month')), 'today', "better_supabase"."usage_used"(tenant, meter, 'day'));
    end if;
  end if;
  insert into "better_supabase"."usage_counters" as c ("tenant_id", "meter", "day", "value")
  values (tenant, meter, today, quantity)
  on conflict ("tenant_id", "meter", "day") do update
    set "value" = c."value" + excluded."value", "updated_at" = now();
  insert into "better_supabase"."usage_history" ("tenant_id", "meter", "quantity", "actor_id", "source", "metadata")
  values (tenant, meter, quantity,
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce(record_usage.actor, auth.uid()) else auth.uid() end,
    record_usage.source, coalesce(record_usage.metadata, '{}'));
  return jsonb_build_object('recorded', true, 'used', "better_supabase"."usage_used"(tenant, meter, coalesce((select q.period from "better_supabase"."usage_quota"(tenant, meter) q), 'month')), 'today', "better_supabase"."usage_used"(tenant, meter, 'day'));
end;
$$;

-- Like record_usage, but first checks the quota and raises quota_exceeded
-- (SQLSTATE BSQ29) without recording when quantity does not fit. A transaction
-- lock per tenant and meter, not today's counter row, serializes the calls, so
-- calls on either side of UTC midnight cannot both take the last unit.
create or replace function "better_supabase"."consume_quota"(
  tenant uuid,
  meter text,
  quantity numeric default 1,
  idempotency_key text default null,
  source text default null,
  metadata jsonb default null,
  actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  quota record;
  used numeric;
  win record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.record'), false)) then
    raise exception 'Not allowed to record usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.consume_quota'), hashtext(tenant::text || '/' || meter));
  if idempotency_key is not null and exists (
    select 1 from "better_supabase"."usage_events" e
    where e."tenant_id" = consume_quota.tenant and e."meter" = consume_quota.meter and e."idempotency_key" = consume_quota.idempotency_key
  ) then
    return jsonb_build_object('recorded', false, 'used', "better_supabase"."usage_used"(tenant, meter, coalesce((select q.period from "better_supabase"."usage_quota"(tenant, meter) q), 'month')), 'today', "better_supabase"."usage_used"(tenant, meter, 'day'));
  end if;
  select * into quota from "better_supabase"."usage_quota"(tenant, meter);
  if quota.quota_limit is not null then
    used := "better_supabase"."usage_used"(tenant, meter, quota.period);
    if used + quantity > quota.quota_limit then
      select * into win from "better_supabase"."usage_window"(tenant, quota.period);
      raise exception 'Quota for % exceeded', meter using
        errcode = 'BSQ29',
        hint = 'QUOTA_EXCEEDED',
        detail = jsonb_build_object(
          'meter', meter,
          'limit', quota.quota_limit,
          'used', used,
          'retry_after', greatest(1, ceil(extract(epoch from win.ends_at - now()))::integer)
        )::text;
    end if;
  end if;
  return "better_supabase"."record_usage"(tenant, meter, quantity, idempotency_key, source, metadata, actor);
end;
$$;

-- Records several meters at once, all or none: entries is [{ meter, quantity }],
-- each checked against its quota first when check is true (a quota_exceeded
-- on one records nothing). idempotency_key is per batch. Returns { recorded,
-- used: { meter: usage in its quota period }, today: { meter: today's usage } }.
create or replace function "better_supabase"."record_usage_batch"(
  tenant uuid,
  entries jsonb,
  idempotency_key text default null,
  "check" boolean default false,
  source text default null,
  metadata jsonb default null,
  actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry jsonb;
  outcome jsonb;
  recorded boolean := false;
  used jsonb := '{}';
  today_used jsonb := '{}';
begin
  -- A JSON text of the array, as a transport that sends arrays as text passes it.
  if jsonb_typeof(entries) = 'string' then
    entries := (entries #>> '{}')::jsonb;
  end if;
  if jsonb_typeof(entries) <> 'array' or jsonb_array_length(entries) = 0 then
    raise exception 'entries must be a non-empty array of { meter, quantity }' using errcode = '22023', hint = 'USAGE_ENTRIES';
  end if;
  for entry in select value from jsonb_array_elements(entries) loop
    if jsonb_typeof(entry -> 'meter') <> 'string' then
      raise exception 'Every entry needs a meter' using errcode = '22023', hint = 'USAGE_ENTRIES';
    end if;
    if record_usage_batch."check" then
      outcome := "better_supabase"."consume_quota"(tenant, entry ->> 'meter', coalesce((entry ->> 'quantity')::numeric, 1),
        case when idempotency_key is null then null else idempotency_key || ':' || (entry ->> 'meter') end,
        source, metadata, actor);
    else
      outcome := "better_supabase"."record_usage"(tenant, entry ->> 'meter', coalesce((entry ->> 'quantity')::numeric, 1),
        case when idempotency_key is null then null else idempotency_key || ':' || (entry ->> 'meter') end,
        source, metadata, actor);
    end if;
    recorded := recorded or (outcome ->> 'recorded')::boolean;
    used := used || jsonb_build_object(entry ->> 'meter', outcome -> 'used');
    today_used := today_used || jsonb_build_object(entry ->> 'meter', outcome -> 'today');
  end loop;
  return jsonb_build_object('recorded', recorded, 'used', used, 'today', today_used);
end;
$$;

-- Server-side, for reportUsageToStripe: counters with unreported usage, with
-- the quota that includes some of it (included, null without a quota) and the
-- usage of the earlier days of that quota's window (window_before), so the
-- report can send only the overage. skip_meters and skip_tenants leave out
-- counters the report can't send yet, so they don't fill every batch.
create or replace function "better_supabase"."unreported_usage"(
  max_rows integer default 500,
  skip_meters text[] default '{}',
  skip_tenants uuid[] default '{}'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id', c."tenant_id",
    'meter', c."meter",
    'day', c."day",
    'value', c."value",
    'reported_value', c."reported_value",
    'included', q.quota_limit,
    'unlimited', q.period is not null and q.quota_limit is null,
    'window_before', (
      select coalesce(sum(o."value"), 0)
      from "better_supabase"."usage_counters" o
      where o."tenant_id" = c."tenant_id" and o."meter" = c."meter"
        and o."day" < c."day"
        and o."day" >= w.since
    )
  ) order by c."day", c."meter"), '[]'::jsonb)
  from (
    select * from "better_supabase"."usage_counters" c
    where c."value" > c."reported_value"
      and c."meter" <> all (coalesce(unreported_usage.skip_meters, '{}'))
      and c."tenant_id" <> all (coalesce(unreported_usage.skip_tenants, '{}'))
    order by c."day"
    limit max_rows
  ) c
  left join lateral "better_supabase"."usage_quota"(c."tenant_id", c."meter") q on true
  cross join lateral (
    select "better_supabase"."usage_window_start"(c."tenant_id", q.period, c."day") as since
  ) w
$$;

-- Marks a counter as reported up to value; never moves it backwards.
create or replace function "better_supabase"."mark_usage_reported"(tenant uuid, meter text, day date, value numeric)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update "better_supabase"."usage_counters" c set "reported_value" = greatest(c."reported_value", mark_usage_reported.value)
    where c."tenant_id" = mark_usage_reported.tenant
      and c."meter" = mark_usage_reported.meter
      and c."day" = mark_usage_reported.day
    returning 1
  )
  select exists (select 1 from updated)
$$;

-- A tenant's usage history, newest first, of one meter when given, before
-- before_id for the next page. [] without options.history. Needs usage.read.
create or replace function "better_supabase"."usage_history"(tenant uuid, meter text default null, max_rows integer default 100, before_id bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', h."id", 'meter', h."meter", 'quantity', h."quantity",
      'actor', h."actor_id", 'source', h."source", 'metadata', h."metadata",
      'recorded_at', h."recorded_at"
    ) order by h."id" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."usage_history" h
      where h."tenant_id" = usage_history.tenant
        and (usage_history.meter is null or h."meter" = usage_history.meter)
        and (before_id is null or h."id" < before_id)
      order by h."id" desc
      limit least(greatest(coalesce(max_rows, 100), 1), 1000)
    ) h
  );
end;
$$;

-- Who and what used a meter in the current window of its quota period:
-- [{ actor, source, quantity }], largest first. [] without options.history.
create or replace function "better_supabase"."usage_breakdown"(tenant uuid, meter text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota record;
  win record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  select * into quota from "better_supabase"."usage_quota"(tenant, meter);
  select * into win from "better_supabase"."usage_window"(tenant, coalesce(quota.period, 'month'));
  return (
    select coalesce(jsonb_agg(jsonb_build_object('actor', b.actor, 'source', b.source, 'quantity', b.quantity) order by b.quantity desc), '[]'::jsonb)
    from (
      select h."actor_id" as actor, h."source" as source, sum(h."quantity") as quantity
      from "better_supabase"."usage_history" h
      where h."tenant_id" = usage_breakdown.tenant and h."meter" = usage_breakdown.meter
        and h."recorded_at" >= win.starts_at and h."recorded_at" < win.ends_at
      group by 1, 2
    ) b
  );
end;
$$;

-- Deletes up to batch history rows older than older_than; returns how many.
create or replace function "better_supabase"."purge_usage_history"(older_than interval default '400 days', batch integer default 10000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  purged integer;
begin
  with gone as (
    delete from "better_supabase"."usage_history" where "id" in (
      select h."id" from "better_supabase"."usage_history" h
      where (h."recorded_at" < now() - least(older_than, "better_supabase"."retention_floor"('usage'))
      and h."recorded_at" < now() - coalesce("better_supabase"."retention_for_memo"('usage', (h."tenant_id")::text), older_than)
      and not "better_supabase"."is_held_memo"('usage', (h."tenant_id")::text))
      order by h."id" limit batch
    )
    returning 1
  )
  select count(*)::integer into purged from gone;
  return purged;
end;
$$;

-- Deletes up to batch idempotency keys older than older_than; returns how
-- many. A retry with a purged key counts again, so keep them longer than
-- any client retries.
create or replace function "better_supabase"."purge_usage_events"(older_than interval default '30 days', batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from "better_supabase"."usage_events" x
    where (x."tenant_id", x."meter", x."idempotency_key") in (
      select e."tenant_id", e."meter", e."idempotency_key" from "better_supabase"."usage_events" e
      where e."recorded_at" < now() - coalesce(older_than, '30 days')
      order by e."recorded_at" limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;

revoke execute on function "better_supabase"."usage_history"(uuid, text, integer, bigint) from public, anon;
revoke execute on function "better_supabase"."usage_breakdown"(uuid, text) from public, anon;
revoke execute on function "better_supabase"."purge_usage_history"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."usage_history"(uuid, text, integer, bigint) to authenticated, service_role;
grant execute on function "better_supabase"."usage_breakdown"(uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."purge_usage_history"(interval, integer) to service_role;
revoke execute on function "better_supabase"."purge_usage_events"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_usage_events"(interval, integer) to service_role;
revoke execute on function "better_supabase"."usage_window"(uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."usage_meters"() from public;
grant execute on function "better_supabase"."usage_window"(uuid, text) to service_role;
revoke execute on function "better_supabase"."usage_window_start"(uuid, text, date) from public, anon, authenticated;
grant execute on function "better_supabase"."usage_window_start"(uuid, text, date) to service_role;
grant execute on function "better_supabase"."usage_meters"() to anon, authenticated, service_role;
revoke execute on function "better_supabase"."usage_quota"(uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."usage_used"(uuid, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."usage_status"(uuid, text) from public, anon;
revoke execute on function "better_supabase"."usage_overview"(uuid) from public, anon;
grant execute on function "better_supabase"."usage_overview"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."within_quota"(uuid, text, bigint) from public, anon;
revoke execute on function "better_supabase"."record_usage"(uuid, text, numeric, text, text, jsonb, uuid) from public, anon;
revoke execute on function "better_supabase"."consume_quota"(uuid, text, numeric, text, text, jsonb, uuid) from public, anon;
revoke execute on function "better_supabase"."record_usage_batch"(uuid, jsonb, text, boolean, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."record_usage_batch"(uuid, jsonb, text, boolean, text, jsonb, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."unreported_usage"(integer, text[], uuid[]) from public, anon, authenticated;
revoke execute on function "better_supabase"."mark_usage_reported"(uuid, text, date, numeric) from public, anon, authenticated;
grant execute on function "better_supabase"."usage_quota"(uuid, text) to service_role;
revoke execute on function "better_supabase"."set_usage_quota"(uuid, text, text, numeric, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."remove_usage_quota"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_usage_quota"(uuid, text, text, numeric, text) to service_role;
grant execute on function "better_supabase"."remove_usage_quota"(uuid, text, text) to service_role;
grant execute on function "better_supabase"."usage_used"(uuid, text, text) to service_role;
grant execute on function "better_supabase"."usage_status"(uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."within_quota"(uuid, text, bigint) to authenticated, service_role;
grant execute on function "better_supabase"."record_usage"(uuid, text, numeric, text, text, jsonb, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."consume_quota"(uuid, text, numeric, text, text, jsonb, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."unreported_usage"(integer, text[], uuid[]) to service_role;
grant execute on function "better_supabase"."mark_usage_reported"(uuid, text, date, numeric) to service_role;

-- What one unit of a meter costs: unit_amount in minor units of currency
-- (ADR 0024), and how many units each billing period includes for free.
create table "better_supabase"."usage_meter_prices" (
  "meter" text not null constraint bsb_usage_meter_prices_meter_check check (length("meter") >= 1 and length("meter") <= 100),
  "currency" text not null constraint bsb_usage_meter_prices_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "unit_amount" bigint not null constraint bsb_usage_meter_prices_unit_amount_check check ("unit_amount" >= 0),
  "included" numeric not null default 0 constraint bsb_usage_meter_prices_included_check check ("included" >= 0),
  "label" text constraint bsb_usage_meter_prices_label_check check (length("label") <= 200),
  primary key ("meter", "currency")
);
alter table "better_supabase"."usage_meter_prices" enable row level security;
revoke all on "better_supabase"."usage_meter_prices" from public, anon, authenticated;
grant all on "better_supabase"."usage_meter_prices" to service_role;

-- One row per tenant and billed period, so billing a period twice returns the
-- first invoice.
create table "better_supabase"."usage_billed_periods" (
  "tenant_id" uuid not null,
  "period_start" date not null,
  "period_end" date not null,
  "invoice_id" uuid not null,
  "billed_at" timestamptz not null default now(),
  constraint "bsb_usage_billed_periods_period_key" primary key ("tenant_id", "period_start", "period_end")
);
alter table "better_supabase"."usage_billed_periods" enable row level security;
revoke all on "better_supabase"."usage_billed_periods" from public, anon, authenticated;
grant all on "better_supabase"."usage_billed_periods" to service_role;

-- Sets the price of one meter in one currency; service role only.
create or replace function "better_supabase"."set_usage_price"(meter text, currency text, unit_amount bigint, included numeric default 0, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role sets usage prices' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  insert into "better_supabase"."usage_meter_prices" as p ("meter", "currency", "unit_amount", "included", "label")
  values (set_usage_price.meter, upper(set_usage_price.currency), set_usage_price.unit_amount, coalesce(set_usage_price.included, 0), set_usage_price.label)
  on conflict ("meter", "currency") do update
    set "unit_amount" = excluded."unit_amount", "included" = excluded."included", "label" = excluded."label";
  return jsonb_build_object('meter', set_usage_price.meter, 'currency', upper(set_usage_price.currency), 'unit_amount', set_usage_price.unit_amount);
exception when check_violation then
  raise exception 'The usage price is invalid' using errcode = '22023', hint = 'USAGE_PRICE_INVALID';
end;
$$;

-- Rates the usage history of [period_start, period_end) (UTC days) by the meter
-- prices into one draft invoice: per meter, the quantity beyond the included
-- units times the unit amount. A meter without a price in the currency, or
-- with nothing beyond its included units, adds no line. Billing the same
-- period again returns the first invoice with created = false; a period with
-- nothing to bill returns invoice_id = null. attrs adds invoice fields
-- (company, contact, termsDays); service role only.
create or replace function "better_supabase"."bill_usage_period"(tenant uuid, period_start date, period_end date, currency text default 'EUR', attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_currency text := upper(coalesce(bill_usage_period.currency, 'EUR'));
  v_existing uuid;
  v_lines jsonb;
  v_invoice jsonb;
  v_title text;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role bills usage' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  if bill_usage_period.period_start is null or bill_usage_period.period_end is null or bill_usage_period.period_end <= bill_usage_period.period_start then
    raise exception 'The billing period must end after it starts' using errcode = '22023', hint = 'USAGE_PERIOD_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(bill_usage_period.tenant::text || bill_usage_period.period_start::text || bill_usage_period.period_end::text, 0));
  select b."invoice_id" into v_existing from "better_supabase"."usage_billed_periods" b
  where b."tenant_id" = bill_usage_period.tenant
    and b."period_start" = bill_usage_period.period_start
    and b."period_end" = bill_usage_period.period_end;
  if found then
    return jsonb_build_object('invoice_id', v_existing, 'created', false, 'lines', 0);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'description', coalesce(p."label", u.meter) || ' ' || bill_usage_period.period_start::text || ' to ' || bill_usage_period.period_end::text,
      'quantity', round(u.total - p."included", 4),
      'unitAmount', p."unit_amount"
    ) order by u.meter), '[]'::jsonb)
  into v_lines
  from (
    select h."meter" as meter, sum(h."quantity") as total
    from "better_supabase"."usage_history" h
    where h."tenant_id" = bill_usage_period.tenant
      and h."recorded_at" >= (bill_usage_period.period_start::timestamp at time zone 'UTC')
      and h."recorded_at" < (bill_usage_period.period_end::timestamp at time zone 'UTC')
    group by h."meter"
  ) u
  join "better_supabase"."usage_meter_prices" p on p."meter" = u.meter and p."currency" = v_currency
  where round(u.total - p."included", 4) > 0;
  if jsonb_array_length(v_lines) = 0 then
    return jsonb_build_object('invoice_id', null, 'created', false, 'lines', 0);
  end if;
  v_title := 'Usage ' || bill_usage_period.period_start::text || ' to ' || bill_usage_period.period_end::text;
  v_invoice := "better_supabase"."create_invoice"(
    bill_usage_period.tenant,
    coalesce(bill_usage_period.attrs, '{}'::jsonb) || jsonb_build_object('title', v_title, 'currency', v_currency),
    v_lines
  );
  insert into "better_supabase"."usage_billed_periods" ("tenant_id", "period_start", "period_end", "invoice_id")
  values (bill_usage_period.tenant, bill_usage_period.period_start, bill_usage_period.period_end, (v_invoice ->> 'id')::uuid);
  return jsonb_build_object('invoice_id', (v_invoice ->> 'id')::uuid, 'created', true, 'lines', jsonb_array_length(v_lines));
end;
$$;

revoke execute on function "better_supabase"."set_usage_price"(text, text, bigint, numeric, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_usage_price"(text, text, bigint, numeric, text) to service_role;
revoke execute on function "better_supabase"."bill_usage_period"(uuid, date, date, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."bill_usage_period"(uuid, date, date, text, jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."usage_counters" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('usage.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."usage_counters" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."usage_counters" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."usage_counters" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."usage_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('usage.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."usage_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."usage_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."usage_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."usage_quotas" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" is null or "tenant_id" in (select better_supabase.tenant_ids_with('usage.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."usage_quotas" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."usage_quotas" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."usage_quotas" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.usage.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."usage_history"(tenant uuid, meter text default null, max_rows integer default 100, before_id bigint default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."usage_history"($1, $2, $3, $4) $$;
revoke execute on function "api"."usage_history"(uuid, text, integer, bigint) from public, anon;
grant execute on function "api"."usage_history"(uuid, text, integer, bigint) to authenticated, service_role;

create or replace function "api"."usage_breakdown"(tenant uuid, meter text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."usage_breakdown"($1, $2) $$;
revoke execute on function "api"."usage_breakdown"(uuid, text) from public, anon;
grant execute on function "api"."usage_breakdown"(uuid, text) to authenticated, service_role;

create or replace function "api"."purge_usage_history"(older_than interval default '400 days', batch integer default 10000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_usage_history"($1, $2) $$;
revoke execute on function "api"."purge_usage_history"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."purge_usage_history"(interval, integer) to service_role;

create or replace function "api"."purge_usage_events"(older_than interval default '30 days', batch integer default 10000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_usage_events"($1, $2) $$;
revoke execute on function "api"."purge_usage_events"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."purge_usage_events"(interval, integer) to service_role;

create or replace function "api"."usage_window"(tenant uuid, period text default 'month')
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."usage_window"($1, $2) $$;
revoke execute on function "api"."usage_window"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."usage_window"(uuid, text) to service_role;

create or replace function "api"."usage_window_start"(tenant uuid, period text, day date)
returns date
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."usage_window_start"($1, $2, $3) $$;
revoke execute on function "api"."usage_window_start"(uuid, text, date) from public, anon, authenticated;
grant execute on function "api"."usage_window_start"(uuid, text, date) to service_role;

create or replace function "api"."usage_meters"()
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$ select "better_supabase"."usage_meters"() $$;
revoke execute on function "api"."usage_meters"() from public;
grant execute on function "api"."usage_meters"() to anon, authenticated, service_role;

create or replace function "api"."usage_overview"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."usage_overview"($1) $$;
revoke execute on function "api"."usage_overview"(uuid) from public, anon;
grant execute on function "api"."usage_overview"(uuid) to authenticated, service_role;

create or replace function "api"."record_usage_batch"(tenant uuid, entries jsonb, idempotency_key text default null, "check" boolean default false, source text default null, metadata jsonb default null, actor uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_usage_batch"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."record_usage_batch"(uuid, jsonb, text, boolean, text, jsonb, uuid) from public, anon;
grant execute on function "api"."record_usage_batch"(uuid, jsonb, text, boolean, text, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."usage_quota"(tenant uuid, meter text)
returns table (quota_limit numeric, period text)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."usage_quota"($1, $2) $$;
revoke execute on function "api"."usage_quota"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."usage_quota"(uuid, text) to service_role;

create or replace function "api"."set_usage_quota"(tenant uuid, plan text, meter text, quota_limit numeric, period text default 'month')
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_usage_quota"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."set_usage_quota"(uuid, text, text, numeric, text) from public, anon, authenticated;
grant execute on function "api"."set_usage_quota"(uuid, text, text, numeric, text) to service_role;

create or replace function "api"."remove_usage_quota"(tenant uuid, plan text, meter text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_usage_quota"($1, $2, $3) $$;
revoke execute on function "api"."remove_usage_quota"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."remove_usage_quota"(uuid, text, text) to service_role;

create or replace function "api"."usage_used"(tenant uuid, meter text, period text default 'month')
returns numeric
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."usage_used"($1, $2, $3) $$;
revoke execute on function "api"."usage_used"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."usage_used"(uuid, text, text) to service_role;

create or replace function "api"."usage_status"(tenant uuid, meter text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."usage_status"($1, $2) $$;
revoke execute on function "api"."usage_status"(uuid, text) from public, anon;
grant execute on function "api"."usage_status"(uuid, text) to authenticated, service_role;

create or replace function "api"."within_quota"(tenant uuid, meter text, quantity bigint default 1)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."within_quota"($1, $2, $3) $$;
revoke execute on function "api"."within_quota"(uuid, text, bigint) from public, anon;
grant execute on function "api"."within_quota"(uuid, text, bigint) to authenticated, service_role;

create or replace function "api"."record_usage"(tenant uuid, meter text, quantity numeric default 1, idempotency_key text default null, source text default null, metadata jsonb default null, actor uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_usage"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."record_usage"(uuid, text, numeric, text, text, jsonb, uuid) from public, anon;
grant execute on function "api"."record_usage"(uuid, text, numeric, text, text, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."consume_quota"(tenant uuid, meter text, quantity numeric default 1, idempotency_key text default null, source text default null, metadata jsonb default null, actor uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."consume_quota"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."consume_quota"(uuid, text, numeric, text, text, jsonb, uuid) from public, anon;
grant execute on function "api"."consume_quota"(uuid, text, numeric, text, text, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."unreported_usage"(max_rows integer default 500, skip_meters text[] default '{}', skip_tenants uuid[] default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."unreported_usage"($1, $2, $3) $$;
revoke execute on function "api"."unreported_usage"(integer, text[], uuid[]) from public, anon, authenticated;
grant execute on function "api"."unreported_usage"(integer, text[], uuid[]) to service_role;

create or replace function "api"."mark_usage_reported"(tenant uuid, meter text, day date, value numeric)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_usage_reported"($1, $2, $3, $4) $$;
revoke execute on function "api"."mark_usage_reported"(uuid, text, date, numeric) from public, anon, authenticated;
grant execute on function "api"."mark_usage_reported"(uuid, text, date, numeric) to service_role;

create or replace function "api"."set_usage_price"(meter text, currency text, unit_amount bigint, included numeric default 0, label text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_usage_price"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."set_usage_price"(text, text, bigint, numeric, text) from public, anon, authenticated;
grant execute on function "api"."set_usage_price"(text, text, bigint, numeric, text) to service_role;

create or replace function "api"."bill_usage_period"(tenant uuid, period_start date, period_end date, currency text default 'EUR', attrs jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bill_usage_period"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."bill_usage_period"(uuid, date, date, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."bill_usage_period"(uuid, date, date, text, jsonb) to service_role;
