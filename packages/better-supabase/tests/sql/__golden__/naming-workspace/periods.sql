-- ==== schema supabase/schemas/900_better_supabase_171_periods.sql
-- better-supabase module: periods
-- @bsb-block periods@1 managed
-- @bsb-hash sha256:909082d85f9054133a33e7f1479fc642515ec764a52332aa362b425e64bf7af0
-- Dated periods per kind with open, locked and closed states, a lookup by date and a close protocol where blocks contribute close blockers and an on-close step.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Periods: one table of dated ranges per kind with a status, a lookup by date
-- and a close protocol. Blocks add kinds through contributions; closing asks
-- each kind's blockers first and runs its on-close step in the same transaction.
-- Kinds installed now: none.
create table "better_supabase"."periods" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null constraint bsb_periods_kind_check check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "starts_on" date not null,
  "ends_on" date not null,
  "status" text not null default 'open' constraint bsb_periods_status_check check ("status" in ('open', 'locked', 'closed')),
  "closed_at" timestamptz,
  "closed_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_periods_check check ("ends_on" >= "starts_on"),
  unique ("tenant_id", "kind", "starts_on")
);
create index "periods_range_idx" on "better_supabase"."periods" ("tenant_id", "kind", "starts_on", "ends_on");
alter table "better_supabase"."periods" enable row level security;
revoke all on "better_supabase"."periods" from public, anon, authenticated;
grant select on "better_supabase"."periods" to authenticated;
grant all on "better_supabase"."periods" to service_role;
create policy bsb_periods_read on "better_supabase"."periods"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('periods.read')));

-- Creates a period of a kind. The range may not overlap another period of the
-- same kind in the organization. Needs periods.write.
create or replace function "better_supabase"."create_period"(tenant uuid, kind text, starts_on date, ends_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."periods";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_period.tenant is not null and coalesce(better_supabase.can('tenant', create_period.tenant, 'periods.write'), false))) then
    raise exception 'not allowed to create periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  if create_period.kind is null or create_period.kind !~ '^[a-z][a-z0-9_]{0,62}$' or create_period.starts_on is null
    or create_period.ends_on is null or create_period.ends_on < create_period.starts_on then
    raise exception 'a period needs a lower case kind and a range that ends on or after it starts' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."periods" x
    where x."tenant_id" = create_period.tenant and x."kind" = create_period.kind
      and daterange(x."starts_on", x."ends_on", '[]') && daterange(create_period.starts_on, create_period.ends_on, '[]')
  ) then
    raise exception 'the range overlaps a period of this kind' using errcode = '23P01', hint = 'PERIOD_OVERLAP';
  end if;
  insert into "better_supabase"."periods" ("tenant_id", "kind", "starts_on", "ends_on")
  values (create_period.tenant, create_period.kind, create_period.starts_on, create_period.ends_on)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_period"(uuid, text, date, date) from public, anon;
grant execute on function "better_supabase"."create_period"(uuid, text, date, date) to authenticated, service_role;

-- The period of a kind that holds a date, or null. A kind a block gave a
-- cadence gets its calendar period created the first time
-- a date in it is asked for. Needs periods.read.
create or replace function "better_supabase"."period_for"(tenant uuid, kind text, on_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."periods";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (period_for.tenant is not null and coalesce(better_supabase.can('tenant', period_for.tenant, 'periods.read'), false))) then
    raise exception 'not allowed to read periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."periods" x
  where x."tenant_id" = period_for.tenant and x."kind" = period_for.kind
    and period_for.on_date between x."starts_on" and x."ends_on";
  if found then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
  end if;
  if v_row."id" is null then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."period_for"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."period_for"(uuid, text, date) to authenticated, service_role;

-- Whether writes dated on_date may still land in the kind's period: true when
-- there is no period or it is open. Blocks call it before they write.
create or replace function "better_supabase"."period_is_open"(tenant uuid, kind text, on_date date)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select not exists (
    select 1 from "better_supabase"."periods" x
    where x."tenant_id" = period_is_open.tenant and x."kind" = period_is_open.kind
      and period_is_open.on_date between x."starts_on" and x."ends_on"
      and x."status" <> 'open'
  )
$$;
revoke execute on function "better_supabase"."period_is_open"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."period_is_open"(uuid, text, date) to authenticated, service_role;

-- What keeps a period from closing, from every block that contributes its
-- kind. An empty array means it can close. Needs periods.read.
create or replace function "better_supabase"."period_close_blockers"(period_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."periods";
  v_blockers text[] := '{}';
begin
  select * into v_row from "better_supabase"."periods" x where x."id" = period_close_blockers.period_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.read'), false))) then
    raise exception 'no such period' using errcode = 'P0002', hint = 'PERIOD_NOT_FOUND';
  end if;
  -- No installed block adds blockers.
  return v_blockers;
end;
$$;
revoke execute on function "better_supabase"."period_close_blockers"(uuid) from public, anon;
grant execute on function "better_supabase"."period_close_blockers"(uuid) to authenticated, service_role;

-- Stops writes into an open period without closing it. Needs periods.manage.
create or replace function "better_supabase"."lock_period"(period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."periods";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."periods" x where x."id" = lock_period.period_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.read'), false))) then
    raise exception 'no such period' using errcode = 'P0002', hint = 'PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.manage'), false))) then
    raise exception 'not allowed to lock periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
  end if;
  update "better_supabase"."periods" x set "status" = 'locked' where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."lock_period"(uuid) from public, anon;
grant execute on function "better_supabase"."lock_period"(uuid) to authenticated, service_role;

-- Closes a period. It fails with PERIOD_CLOSE_BLOCKED while any contributing
-- block names a blocker; otherwise it runs each block's on-close step and marks
-- the period closed in one transaction. Closing a closed period returns it
-- unchanged. Needs periods.manage.
create or replace function "better_supabase"."close_period"(period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."periods";
  v_blockers text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."periods" x where x."id" = close_period.period_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.read'), false))) then
    raise exception 'no such period' using errcode = 'P0002', hint = 'PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.manage'), false))) then
    raise exception 'not allowed to close periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
  end if;
  v_blockers := "better_supabase"."period_close_blockers"(v_row."id");
  if cardinality(v_blockers) > 0 then
    raise exception 'the period can''t close yet: %', array_to_string(v_blockers, ', ') using errcode = '55000', hint = 'PERIOD_CLOSE_BLOCKED', detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
  end if;
  -- No installed block adds an on-close step.
  update "better_supabase"."periods" x set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
  where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."close_period"(uuid) from public, anon;
grant execute on function "better_supabase"."close_period"(uuid) to authenticated, service_role;

-- Reopens a locked or closed period. The on-close steps of the blocks are not
-- undone. Needs periods.manage.
create or replace function "better_supabase"."reopen_period"(period_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."periods";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."periods" x where x."id" = reopen_period.period_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.read'), false))) then
    raise exception 'no such period' using errcode = 'P0002', hint = 'PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'periods.manage'), false))) then
    raise exception 'not allowed to reopen periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  if v_row."status" = 'open' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
  end if;
  update "better_supabase"."periods" x set "status" = 'open', "closed_at" = null, "closed_by" = null
  where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_period"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_period"(uuid, text) to authenticated, service_role;

-- An organization's periods, newest first. filters is { kind (a value or a
-- list), status (a value or a list), sort, direction, facet, count, limit,
-- after, offset, paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_periods"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_periods.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_periods.tenant is not null and coalesce(better_supabase.can('tenant', list_periods.tenant, 'periods.read'), false))) then
    raise exception 'not allowed to read periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind', 'status') then
      raise exception 'facet is one of kind, status' using errcode = '22023', hint = 'PERIOD_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text when 'status' then (x."status")::text end) as v
      from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn') then
    raise exception 'sort is one of startsOn, endsOn' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."starts_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_on", x."kind", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."starts_on" asc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."starts_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."kind" > (v_after ->> 1)::text) or (x."starts_on" = (v_after ->> 0)::date and x."kind" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."starts_on" desc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."starts_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_on", x."kind", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."starts_on" asc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."starts_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."kind" > (v_after ->> 1)::text) or (x."starts_on" = (v_after ->> 0)::date and x."kind" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."starts_on" desc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on", x."kind", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."ends_on" asc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'PERIOD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."kind")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" <= (v_after ->> 0)::date and ((x."ends_on" < (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."kind" > (v_after ->> 1)::text) or (x."ends_on" = (v_after ->> 0)::date and x."kind" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" desc, x."kind" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."periods" x
      where x."tenant_id" = list_periods.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_periods"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_periods"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."periods" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('periods.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."periods" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."periods" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."periods" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_171_periods.sql
-- better-supabase module: periods
-- @bsb-block-data periods
-- @bsb-hash sha256:55b2a755e5f3596258569ee15d709290a25c624a8555a3d7247d9afd0e501f9b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('periods', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
