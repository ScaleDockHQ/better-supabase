-- ==== schema supabase/schemas/900_better_supabase_136_forecasts.sql
-- better-supabase module: forecasts
-- @bsb-block forecasts@1 managed
-- @bsb-hash sha256:bdbc46da9af62afdd46245261d63f8d19ae35190ef24b378adc0af5bd9f64435
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

-- The organization's snapshots as a keyset page, newest first (ADR 1077).
-- Needs forecasts.read. filters is { pipelineId, currency, since, until (each a
-- value or a list), sort (takenAt, since, dealCount), direction, facet, count,
-- limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_forecast_snapshots"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_forecast_snapshots.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_forecast_snapshots.tenant, 'forecasts.read'), false)) then
    raise exception 'You need forecasts.read to list forecast snapshots' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('currency', 'pipelineId') then
      raise exception 'facet is one of currency, pipelineId' using errcode = '22023', hint = 'FORECAST_INVALID';
    end if;
    with s as (
      select (case v_facet when 'currency' then (x."currency")::text when 'pipelineId' then (coalesce(x."pipeline_id"::text, ''))::text end) as v
      from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('takenAt', 'since', 'dealCount') then
    raise exception 'sort is one of takenAt, since, dealCount' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."taken_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."taken_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."taken_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."taken_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."taken_at" <= (v_after ->> 0)::timestamptz and ((x."taken_at" < (v_after ->> 0)::timestamptz) or (x."taken_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."taken_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'takenAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."taken_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."taken_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."taken_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'takenAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."taken_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."taken_at" <= (v_after ->> 0)::timestamptz and ((x."taken_at" < (v_after ->> 0)::timestamptz) or (x."taken_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."taken_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'since' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."period_start")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."period_start", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."period_start" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'since' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."period_start")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."period_start" <= (v_after ->> 0)::date and ((x."period_start" < (v_after ->> 0)::date) or (x."period_start" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."period_start" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dealCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."deal_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."deal_count", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."deal_count" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dealCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'pipelineId', x."pipeline_id", 'since', x."period_start", 'until', x."period_end", 'currency', x."currency", 'target', x."target"::text, 'totals', x."totals", 'dealCount', x."deal_count", 'takenBy', x."taken_by", 'takenAt', x."taken_at") as j, jsonb_build_array((x."deal_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
        and (v_after is null or (x."deal_count" <= (v_after ->> 0)::integer and ((x."deal_count" < (v_after ->> 0)::integer) or (x."deal_count" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."deal_count" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."forecast_snapshots" x
      where x."tenant_id" = page_forecast_snapshots.tenant
        and (not (v_filters -> 'pipelineId' is not null and jsonb_typeof(v_filters -> 'pipelineId') <> 'null' and not (jsonb_typeof(v_filters -> 'pipelineId') = 'array' and jsonb_array_length(v_filters -> 'pipelineId') = 0)) or x."pipeline_id" = any((case when jsonb_typeof(v_filters -> 'pipelineId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pipelineId')) else array[v_filters ->> 'pipelineId'] end)::uuid[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or x."currency" = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (not (v_filters -> 'since' is not null and jsonb_typeof(v_filters -> 'since') <> 'null' and not (jsonb_typeof(v_filters -> 'since') = 'array' and jsonb_array_length(v_filters -> 'since') = 0)) or x."period_start" = any((case when jsonb_typeof(v_filters -> 'since') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'since')) else array[v_filters ->> 'since'] end)::date[]))
        and (not (v_filters -> 'until' is not null and jsonb_typeof(v_filters -> 'until') <> 'null' and not (jsonb_typeof(v_filters -> 'until') = 'array' and jsonb_array_length(v_filters -> 'until') = 0)) or x."period_end" = any((case when jsonb_typeof(v_filters -> 'until') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'until')) else array[v_filters ->> 'until'] end)::date[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_forecast_snapshots"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_forecast_snapshots"(uuid, jsonb) to authenticated, service_role;

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
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshots" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshots" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshots" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."forecast_snapshot_deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('forecasts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."forecast_snapshot_deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."forecast_snapshot_deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."forecast_snapshot_deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_136_forecasts.sql
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
