-- better-supabase module: periods
-- @bsb-block periods@1 managed
-- @bsb-hash sha256:3fe8379d257ec8458b0b6a7d66ab472099920d88b0d7c0830646be538bdeb230
-- Dated periods per kind with open, locked and closed states, a lookup by date and a close protocol where blocks contribute close blockers and an on-close step.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Periods: one table of dated ranges per kind with a status, a lookup by date
-- and a close protocol. Blocks add kinds through contributions; closing asks
-- each kind's blockers first and runs its on-close step in the same transaction.
-- Kinds installed now: fiscal_period, commission_period.
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
  perform "better_supabase".emit_event('period.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status"), 'periods/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/periods');
  perform better_supabase.audit_event(
    event_type => 'period.created',
    category => 'data',
    target_type => 'period',
    record_id => v_row."id"::text,
    target_label => v_row."kind" || ' ' || v_row."starts_on"::text,
    summary => 'period created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_period"(uuid, text, date, date) from public, anon;
grant execute on function "better_supabase"."create_period"(uuid, text, date, date) to authenticated, service_role;

-- The period of a kind that holds a date, or null. A kind a block gave a
-- cadence (commission_period: month) gets its calendar period created the first time
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (period_for.tenant is not null and coalesce(better_supabase.can('tenant', period_for.tenant, 'periods.read'), false))) then
    raise exception 'not allowed to read periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."periods" x
  where x."tenant_id" = period_for.tenant and x."kind" = period_for.kind
    and period_for.on_date between x."starts_on" and x."ends_on";
  if found then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
  end if;
  if period_for.kind = 'commission_period' then
      insert into "better_supabase"."periods" ("tenant_id", "kind", "starts_on", "ends_on")
      values (period_for.tenant, period_for.kind, date_trunc('month', period_for.on_date::timestamp)::date, (date_trunc('month', period_for.on_date::timestamp) + case 'month' when 'week' then interval '1 week' when 'month' then interval '1 month' when 'quarter' then interval '3 months' else interval '1 year' end - interval '1 day')::date)
      on conflict do nothing;
      select * into v_row from "better_supabase"."periods" x
      where x."tenant_id" = period_for.tenant and x."kind" = period_for.kind
        and period_for.on_date between x."starts_on" and x."ends_on";
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
  if v_row."kind" = 'fiscal_period' then
    v_blockers := v_blockers || coalesce("better_supabase"."accounting_range_close_blockers"(v_row."tenant_id", v_row."starts_on", v_row."ends_on"), '{}'::text[]);
  end if;
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
  perform "better_supabase".emit_event('period.locked', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status"), 'periods/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/periods');
  perform better_supabase.audit_event(
    event_type => 'period.locked',
    category => 'data',
    target_type => 'period',
    record_id => v_row."id"::text,
    target_label => v_row."kind" || ' ' || v_row."starts_on"::text,
    summary => 'period locked',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status")
  );
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
  if v_row."kind" = 'fiscal_period' then
    perform "better_supabase"."accounting_close_range"(v_row."tenant_id", v_row."starts_on", v_row."ends_on");
  end if;
  if v_row."kind" = 'commission_period' then
    perform "better_supabase"."commission_close_range"(v_row."tenant_id", v_row."starts_on", v_row."ends_on");
  end if;
  update "better_supabase"."periods" x set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('period.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status"), 'periods/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/periods');
  perform better_supabase.audit_event(
    event_type => 'period.closed',
    category => 'data',
    target_type => 'period',
    record_id => v_row."id"::text,
    target_label => v_row."kind" || ' ' || v_row."starts_on"::text,
    summary => 'period closed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status")
  );
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
  perform "better_supabase".emit_event('period.reopened', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'reason', nullif(trim(reopen_period.reason), '')), 'periods/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/periods');
  perform better_supabase.audit_event(
    event_type => 'period.reopened',
    category => 'data',
    target_type => 'period',
    record_id => v_row."id"::text,
    target_label => v_row."kind" || ' ' || v_row."starts_on"::text,
    summary => 'period reopened',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'reason', nullif(trim(reopen_period.reason), ''))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_period"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_period"(uuid, text) to authenticated, service_role;

-- An organization's periods, newest first. filters is { kind, status, limit }.
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
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_periods.tenant is not null and coalesce(better_supabase.can('tenant', list_periods.tenant, 'periods.read'), false))) then
    raise exception 'not allowed to read periods' using errcode = '42501', hint = 'PERIOD_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'kind', y."kind", 'startsOn', y."starts_on", 'endsOn', y."ends_on", 'status', y."status", 'closedAt', y."closed_at", 'closedBy', y."closed_by", 'createdAt', y."created_at") order by y."starts_on" desc, y."kind")
    from (
      select * from "better_supabase"."periods" z
      where z."tenant_id" = list_periods.tenant
        and (not v_filters ? 'kind' or z."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."starts_on" desc, z."kind"
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('periods.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."periods" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."periods" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."periods" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.periods deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"period","event_prefix":"period"}');

-- blocks.periods.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_period"(tenant uuid, kind text, starts_on date, ends_on date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_period"($1, $2, $3, $4) $$;
revoke execute on function "api"."create_period"(uuid, text, date, date) from public, anon;
grant execute on function "api"."create_period"(uuid, text, date, date) to authenticated, service_role;

create or replace function "api"."period_for"(tenant uuid, kind text, on_date date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."period_for"($1, $2, $3) $$;
revoke execute on function "api"."period_for"(uuid, text, date) from public, anon;
grant execute on function "api"."period_for"(uuid, text, date) to authenticated, service_role;

create or replace function "api"."period_is_open"(tenant uuid, kind text, on_date date)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."period_is_open"($1, $2, $3) $$;
revoke execute on function "api"."period_is_open"(uuid, text, date) from public, anon;
grant execute on function "api"."period_is_open"(uuid, text, date) to authenticated, service_role;

create or replace function "api"."period_close_blockers"(period_id uuid)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."period_close_blockers"($1) $$;
revoke execute on function "api"."period_close_blockers"(uuid) from public, anon;
grant execute on function "api"."period_close_blockers"(uuid) to authenticated, service_role;

create or replace function "api"."lock_period"(period_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."lock_period"($1) $$;
revoke execute on function "api"."lock_period"(uuid) from public, anon;
grant execute on function "api"."lock_period"(uuid) to authenticated, service_role;

create or replace function "api"."close_period"(period_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_period"($1) $$;
revoke execute on function "api"."close_period"(uuid) from public, anon;
grant execute on function "api"."close_period"(uuid) to authenticated, service_role;

create or replace function "api"."reopen_period"(period_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reopen_period"($1, $2) $$;
revoke execute on function "api"."reopen_period"(uuid, text) from public, anon;
grant execute on function "api"."reopen_period"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_periods"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_periods"($1, $2) $$;
revoke execute on function "api"."list_periods"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_periods"(uuid, jsonb) to authenticated, service_role;
