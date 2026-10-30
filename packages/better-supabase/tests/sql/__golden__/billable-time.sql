-- ==== alone: schema supabase/schemas/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block billable-time@1 managed
-- @bsb-hash sha256:23acd5719dddb225bbcf30f45d7bf8f042888129921a38dcaca71949d3cdc93e
-- A rate card for time entries, by member, record or organization with effective dates, and draft invoices from unbilled billable time with one line per record, member or entry, in bigint minor units. Billed entries lock until the invoice is voided.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Billable time: a rate card for time entries and invoices drafted from
-- unbilled time, in bigint minor units.

create table if not exists "better_supabase"."time_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid,
  "subject_type" text,
  "subject_id" text,
  -- Minor units of currency per hour (ADR 0037).
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "effective_from" date not null default current_date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null)),
  unique nulls not distinct ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
);
-- What an hour costs the organization, in the rate's currency (project costing).
alter table "better_supabase"."time_rates" add column if not exists "cost_amount" bigint check ("cost_amount" >= 0);
create index if not exists "time_rates_lookup_idx" on "better_supabase"."time_rates" ("tenant_id", "subject_type", "subject_id", "user_id", "effective_from" desc);
alter table "better_supabase"."time_rates" enable row level security;
revoke all on "better_supabase"."time_rates" from public, anon, authenticated;
grant select on "better_supabase"."time_rates" to authenticated;
grant all on "better_supabase"."time_rates" to service_role;
drop policy if exists "time_rates_read" on "better_supabase"."time_rates";
create policy time_rates_read on "better_supabase"."time_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- One row per billed time entry: the invoice and the rate it was billed at.
create table if not exists "better_supabase"."time_invoice_entries" (
  "entry_id" uuid primary key references "better_supabase"."time_entries" ("id") on delete restrict,
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "rate" bigint not null,
  "currency" char(3) not null,
  "seconds" bigint not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "time_invoice_entries_invoice_idx" on "better_supabase"."time_invoice_entries" ("invoice_id");
create index if not exists "time_invoice_entries_tenant_idx" on "better_supabase"."time_invoice_entries" ("tenant_id");
alter table "better_supabase"."time_invoice_entries" enable row level security;
revoke all on "better_supabase"."time_invoice_entries" from public, anon, authenticated;
grant select on "better_supabase"."time_invoice_entries" to authenticated;
grant all on "better_supabase"."time_invoice_entries" to service_role;
drop policy if exists "time_invoice_entries_read" on "better_supabase"."time_invoice_entries";
create policy time_invoice_entries_read on "better_supabase"."time_invoice_entries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- A billed entry keeps what it was billed for: it can't be deleted, and its
-- time, billable flag and rate can't change until the invoice is voided. Its
-- record can, so a merge can move it.
create or replace function "better_supabase"."billable_time_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = old."id") then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- restrict_violation, so an organization purge retries the table later.
  if tg_op = 'DELETE' then
    raise exception 'this entry is on an invoice; void the invoice to delete it' using errcode = '23001', hint = 'TIME_ENTRY_INVOICED';
  end if;
  if old."started_at" is distinct from new."started_at" or old."ended_at" is distinct from new."ended_at" or old."billable" is distinct from new."billable" or old."rate" is distinct from new."rate" or old."rate_currency" is distinct from new."rate_currency" then
    raise exception 'this entry is on an invoice; void the invoice to change it' using errcode = '55000', hint = 'TIME_ENTRY_INVOICED';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_guard"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_guard on "better_supabase"."time_entries";
create trigger bsb_billable_time_guard
  before update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."billable_time_guard"();

-- Voiding an invoice releases its entries so they can be billed again.
create or replace function "better_supabase"."billable_time_release"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."time_invoice_entries" d where d."invoice_id" = new."id";
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_release"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_release on "better_supabase"."invoices";
create trigger bsb_billable_time_release
  after update of "status" on "better_supabase"."invoices"
  for each row when (new."status" = 'void' and old."status" <> 'void')
  execute function "better_supabase"."billable_time_release"();

-- Sets the hourly rate for a member, a record, both, or the organization
-- (neither), from effective_from (today by default), with what the hour costs
-- the organization (cost_amount, for project costing). The same key and day
-- replaces the rate.
drop function if exists "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);
create or replace function "better_supabase"."set_time_rate"(tenant uuid, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null, cost_amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_time_rate.tenant, 'billable_time.manage'), false)) then
    raise exception 'not allowed to change the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    raise exception 'a rate is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.cost_amount < 0 then
    raise exception 'a cost is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not false then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "cost_amount", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), set_time_rate.cost_amount, auth.uid())
  on conflict ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "cost_amount" = excluded."cost_amount", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_rate"(rate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_rates" x where x."id" = delete_time_rate.rate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'billable_time.manage'), false)) then
    raise exception 'no such rate you can change' using errcode = 'P0002', hint = 'TIME_RATE_NOT_FOUND';
  end if;
  delete from "better_supabase"."time_rates" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_rate"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_rate"(uuid) to authenticated, service_role;

-- The rate card, newest first per key. Filters narrow it to a member or a
-- record (organization-wide rates are those with neither).
create or replace function "better_supabase"."list_time_rates"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_time_rates.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'rate', q."rate"::text, 'currency', q."currency", 'effectiveFrom', q."effective_from", 'cost', q."cost_amount"::text, 'createdBy', q."created_by", 'createdAt', q."created_at") order by q."subject_type" nulls first, q."subject_id" nulls first, q."user_id" nulls first, q."effective_from" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = list_time_rates.tenant
        and (list_time_rates.user_id is null or x."user_id" = list_time_rates.user_id)
        and (list_time_rates.subject_type is null or (x."subject_type" = list_time_rates.subject_type and x."subject_id" = list_time_rates.subject_id))
      order by x."effective_from" desc
      limit least(greatest(coalesce(list_time_rates.page_size, 200), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) to authenticated, service_role;

-- The rate card entry that applies to a member's time on a record on a day:
-- member and record first, then the record, the member, the organization.
create or replace function "better_supabase"."time_rate"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, on_day date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', time_rate.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'userId', c."user_id", 'subjectType', c."subject_type", 'subjectId', c."subject_id", 'rate', c."rate"::text, 'currency', c."currency", 'effectiveFrom', c."effective_from", 'cost', c."cost_amount"::text, 'createdBy', c."created_by", 'createdAt', c."created_at") from "better_supabase"."time_rates" c
    where c."tenant_id" = time_rate.tenant
      and (c."user_id" is null or c."user_id" = time_rate.user_id)
      and (c."subject_type" is null or (c."subject_type" = time_rate.subject_type and c."subject_id" = time_rate.subject_id))
      and c."effective_from" <= coalesce(time_rate.on_day, current_date)
    order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) from public, anon;
grant execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) to authenticated, service_role;

-- What invoice_from_time would bill: the lines per currency, their totals,
-- and the billable entries no rate covers. scope: subject ({ type, id }),
-- userId, starts, ends (on started_at) and entryIds.
create or replace function "better_supabase"."unbilled_time"(tenant uuid, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(unbilled_time.scope, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', unbilled_time.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if unbilled_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text, 'currency', l.currency, 'amount', round(l.quantity * l.rate)::bigint::text, 'entryIds', l.entry_ids, 'subjectType', l.subject_type, 'subjectId', l.subject_id, 'userId', coalesce(l.member_text, l.user_text)) order by l.currency, l.first_at), '[]'::jsonb)
      from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object('amount', t.amount::text, 'currency', t.currency) order by t.currency), '[]'::jsonb)
      from (select l.currency, sum(round(l.quantity * l.rate))::bigint as amount
        from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l group by l.currency) t),
    'unrated', (select coalesce(jsonb_agg(u.id order by u.started_at), '[]'::jsonb)
      from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u where u.rate is null)
  );
end;
$$;
revoke execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) to authenticated, service_role;

-- Bills the unbilled time a scope selects on a new draft invoice. attrs go to
-- create_invoice (title, default Time; company; contact; termsDays; note); its currency
-- picks the entries in that currency, and without one the entries must share
-- one. Fails while a selected billable entry has no rate.
create or replace function "better_supabase"."invoice_from_time"(tenant uuid, attrs jsonb, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(invoice_from_time.scope, '{}'::jsonb);
  v_currency text := upper(invoice_from_time.attrs ->> 'currency');
  v_currencies text[];
  v_unrated integer;
  v_lines jsonb;
  v_entries jsonb;
  v_total bigint;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invoice_from_time.tenant, 'billable_time.invoice'), false)) then
    raise exception 'not allowed to invoice time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if invoice_from_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || invoice_from_time.tenant::text, 0));
  select count(*) filter (where u.rate is null), array_agg(distinct u.currency) filter (where u.rate is not null)
    into v_unrated, v_currencies
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u;
  if v_unrated > 0 then
    raise exception 'some billable entries have no rate; set one on the entry or the rate card' using errcode = '22023', hint = 'TIME_RATE_MISSING';
  end if;
  if v_currency is null then
    if coalesce(array_length(v_currencies, 1), 0) > 1 then
      raise exception 'the entries are billed in several currencies; name one' using errcode = '22023', hint = 'BILLABLE_TIME_CURRENCIES';
    end if;
    v_currency := v_currencies[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text) order by l.first_at), '[]'::jsonb),
    coalesce(jsonb_agg(l.entry_ids), '[]'::jsonb),
    coalesce(sum(round(l.quantity * l.rate)), 0)::bigint
    into v_lines, v_entries, v_total
  from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when invoice_from_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when invoice_from_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when invoice_from_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when invoice_from_time.group_by in ('member', 'entry') then u.user_id end,
      case when invoice_from_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l
  where l.currency = v_currency;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'no unbilled billable time matches' using errcode = 'P0002', hint = 'BILLABLE_TIME_EMPTY';
  end if;
  select coalesce(jsonb_agg(x.value order by x.value), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_entries) g, jsonb_array_elements(g.value) x;
  v_invoice := "better_supabase"."create_invoice"(invoice_from_time.tenant,
    (coalesce(invoice_from_time.attrs, '{}'::jsonb) - 'origin') || jsonb_build_object('currency', v_currency,
      'title', coalesce(nullif(trim(invoice_from_time.attrs ->> 'title'), ''), 'Time')), v_lines);
  insert into "better_supabase"."time_invoice_entries" ("entry_id", "tenant_id", "invoice_id", "rate", "currency", "seconds")
  select u.id, invoice_from_time.tenant, (v_invoice ->> 'id')::uuid, u.rate, u.currency, round(u.seconds)::bigint
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
  where u.id::text in (select jsonb_array_elements_text(v_entries));
  null;
  return jsonb_build_object('invoiceId', v_invoice ->> 'id', 'currency', v_currency, 'total', v_total::text, 'entryIds', v_entries);
end;
$$;
revoke execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) to authenticated, service_role;

-- The entries an invoice billed, with the rate and seconds it billed.
create or replace function "better_supabase"."list_invoiced_time"(invoice uuid, page_size integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."invoices" x where x."id" = list_invoiced_time.invoice;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'billable_time.read'), false)) then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('entryId', q."entry_id", 'invoiceId', q."invoice_id", 'userId', q.user_id,
      'subjectType', q.subject_type, 'subjectId', q.subject_id, 'startedAt', q.started_at, 'seconds', q."seconds",
      'rate', q."rate"::text, 'currency', q."currency", 'createdAt', q."created_at") order by q.started_at, q."entry_id"), '[]'::jsonb)
    from (
      select d.*, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id, x."started_at" as started_at
      from "better_supabase"."time_invoice_entries" d join "better_supabase"."time_entries" x on x."id" = d."entry_id"
      where d."invoice_id" = list_invoiced_time.invoice
      order by x."started_at"
      limit least(greatest(coalesce(list_invoiced_time.page_size, 500), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_invoiced_time"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_invoiced_time"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
create policy bsb_tenant_scope_select on "better_supabase"."time_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."time_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
create policy bsb_tenant_scope_update on "better_supabase"."time_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."time_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_select on "better_supabase"."time_invoice_entries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_update on "better_supabase"."time_invoice_entries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:e03d1cc092ec5ad01389ac485d7354915fad1cc6732344906a9f3d41034c5eb8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block billable-time@1 managed
-- @bsb-hash sha256:df9bf4ced12f796c31b6b83a2b1abba89e28f1edc26f688bd04613eadfd25aa8
-- A rate card for time entries, by member, record or organization with effective dates, and draft invoices from unbilled billable time with one line per record, member or entry, in bigint minor units. Billed entries lock until the invoice is voided.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Billable time: a rate card for time entries and invoices drafted from
-- unbilled time, in bigint minor units.

create table if not exists "better_supabase"."time_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid,
  "subject_type" text,
  "subject_id" text,
  -- Minor units of currency per hour (ADR 0037).
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "effective_from" date not null default current_date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null)),
  unique nulls not distinct ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
);
-- What an hour costs the organization, in the rate's currency (project costing).
alter table "better_supabase"."time_rates" add column if not exists "cost_amount" bigint check ("cost_amount" >= 0);
create index if not exists "time_rates_lookup_idx" on "better_supabase"."time_rates" ("tenant_id", "subject_type", "subject_id", "user_id", "effective_from" desc);
alter table "better_supabase"."time_rates" enable row level security;
revoke all on "better_supabase"."time_rates" from public, anon, authenticated;
grant select on "better_supabase"."time_rates" to authenticated;
grant all on "better_supabase"."time_rates" to service_role;
drop policy if exists "time_rates_read" on "better_supabase"."time_rates";
create policy time_rates_read on "better_supabase"."time_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- One row per billed time entry: the invoice and the rate it was billed at.
create table if not exists "better_supabase"."time_invoice_entries" (
  "entry_id" uuid primary key references "better_supabase"."time_entries" ("id") on delete restrict,
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "rate" bigint not null,
  "currency" char(3) not null,
  "seconds" bigint not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "time_invoice_entries_invoice_idx" on "better_supabase"."time_invoice_entries" ("invoice_id");
create index if not exists "time_invoice_entries_tenant_idx" on "better_supabase"."time_invoice_entries" ("tenant_id");
alter table "better_supabase"."time_invoice_entries" enable row level security;
revoke all on "better_supabase"."time_invoice_entries" from public, anon, authenticated;
grant select on "better_supabase"."time_invoice_entries" to authenticated;
grant all on "better_supabase"."time_invoice_entries" to service_role;
drop policy if exists "time_invoice_entries_read" on "better_supabase"."time_invoice_entries";
create policy time_invoice_entries_read on "better_supabase"."time_invoice_entries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- A billed entry keeps what it was billed for: it can't be deleted, and its
-- time, billable flag and rate can't change until the invoice is voided. Its
-- record can, so a merge can move it.
create or replace function "better_supabase"."billable_time_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = old."id") then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- restrict_violation, so an organization purge retries the table later.
  if tg_op = 'DELETE' then
    raise exception 'this entry is on an invoice; void the invoice to delete it' using errcode = '23001', hint = 'TIME_ENTRY_INVOICED';
  end if;
  if old."started_at" is distinct from new."started_at" or old."ended_at" is distinct from new."ended_at" or old."billable" is distinct from new."billable" or old."rate" is distinct from new."rate" or old."rate_currency" is distinct from new."rate_currency" then
    raise exception 'this entry is on an invoice; void the invoice to change it' using errcode = '55000', hint = 'TIME_ENTRY_INVOICED';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_guard"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_guard on "better_supabase"."time_entries";
create trigger bsb_billable_time_guard
  before update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."billable_time_guard"();

-- Voiding an invoice releases its entries so they can be billed again.
create or replace function "better_supabase"."billable_time_release"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."time_invoice_entries" d where d."invoice_id" = new."id";
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_release"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_release on "better_supabase"."invoices";
create trigger bsb_billable_time_release
  after update of "status" on "better_supabase"."invoices"
  for each row when (new."status" = 'void' and old."status" <> 'void')
  execute function "better_supabase"."billable_time_release"();

-- Sets the hourly rate for a member, a record, both, or the organization
-- (neither), from effective_from (today by default), with what the hour costs
-- the organization (cost_amount, for project costing). The same key and day
-- replaces the rate.
drop function if exists "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);
create or replace function "better_supabase"."set_time_rate"(tenant uuid, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null, cost_amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_time_rate.tenant, 'billable_time.manage'), false)) then
    raise exception 'not allowed to change the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    raise exception 'a rate is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.cost_amount < 0 then
    raise exception 'a cost is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not false then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "cost_amount", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), set_time_rate.cost_amount, auth.uid())
  on conflict ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "cost_amount" = excluded."cost_amount", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_rate"(rate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_rates" x where x."id" = delete_time_rate.rate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'billable_time.manage'), false)) then
    raise exception 'no such rate you can change' using errcode = 'P0002', hint = 'TIME_RATE_NOT_FOUND';
  end if;
  delete from "better_supabase"."time_rates" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_rate"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_rate"(uuid) to authenticated, service_role;

-- The rate card, newest first per key. Filters narrow it to a member or a
-- record (organization-wide rates are those with neither).
create or replace function "better_supabase"."list_time_rates"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_time_rates.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'rate', q."rate"::text, 'currency', q."currency", 'effectiveFrom', q."effective_from", 'cost', q."cost_amount"::text, 'createdBy', q."created_by", 'createdAt', q."created_at") order by q."subject_type" nulls first, q."subject_id" nulls first, q."user_id" nulls first, q."effective_from" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = list_time_rates.tenant
        and (list_time_rates.user_id is null or x."user_id" = list_time_rates.user_id)
        and (list_time_rates.subject_type is null or (x."subject_type" = list_time_rates.subject_type and x."subject_id" = list_time_rates.subject_id))
      order by x."effective_from" desc
      limit least(greatest(coalesce(list_time_rates.page_size, 200), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) to authenticated, service_role;

-- The rate card entry that applies to a member's time on a record on a day:
-- member and record first, then the record, the member, the organization.
create or replace function "better_supabase"."time_rate"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, on_day date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', time_rate.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'userId', c."user_id", 'subjectType', c."subject_type", 'subjectId', c."subject_id", 'rate', c."rate"::text, 'currency', c."currency", 'effectiveFrom', c."effective_from", 'cost', c."cost_amount"::text, 'createdBy', c."created_by", 'createdAt', c."created_at") from "better_supabase"."time_rates" c
    where c."tenant_id" = time_rate.tenant
      and (c."user_id" is null or c."user_id" = time_rate.user_id)
      and (c."subject_type" is null or (c."subject_type" = time_rate.subject_type and c."subject_id" = time_rate.subject_id))
      and c."effective_from" <= coalesce(time_rate.on_day, current_date)
    order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) from public, anon;
grant execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) to authenticated, service_role;

-- What invoice_from_time would bill: the lines per currency, their totals,
-- and the billable entries no rate covers. scope: subject ({ type, id }),
-- userId, starts, ends (on started_at) and entryIds.
create or replace function "better_supabase"."unbilled_time"(tenant uuid, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(unbilled_time.scope, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', unbilled_time.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if unbilled_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text, 'currency', l.currency, 'amount', round(l.quantity * l.rate)::bigint::text, 'entryIds', l.entry_ids, 'subjectType', l.subject_type, 'subjectId', l.subject_id, 'userId', coalesce(l.member_text, l.user_text)) order by l.currency, l.first_at), '[]'::jsonb)
      from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object('amount', t.amount::text, 'currency', t.currency) order by t.currency), '[]'::jsonb)
      from (select l.currency, sum(round(l.quantity * l.rate))::bigint as amount
        from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l group by l.currency) t),
    'unrated', (select coalesce(jsonb_agg(u.id order by u.started_at), '[]'::jsonb)
      from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u where u.rate is null)
  );
end;
$$;
revoke execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) to authenticated, service_role;

-- Bills the unbilled time a scope selects on a new draft invoice. attrs go to
-- create_invoice (title, default Time; company; contact; termsDays; note); its currency
-- picks the entries in that currency, and without one the entries must share
-- one. Fails while a selected billable entry has no rate.
create or replace function "better_supabase"."invoice_from_time"(tenant uuid, attrs jsonb, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(invoice_from_time.scope, '{}'::jsonb);
  v_currency text := upper(invoice_from_time.attrs ->> 'currency');
  v_currencies text[];
  v_unrated integer;
  v_lines jsonb;
  v_entries jsonb;
  v_total bigint;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invoice_from_time.tenant, 'billable_time.invoice'), false)) then
    raise exception 'not allowed to invoice time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if invoice_from_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || invoice_from_time.tenant::text, 0));
  select count(*) filter (where u.rate is null), array_agg(distinct u.currency) filter (where u.rate is not null)
    into v_unrated, v_currencies
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u;
  if v_unrated > 0 then
    raise exception 'some billable entries have no rate; set one on the entry or the rate card' using errcode = '22023', hint = 'TIME_RATE_MISSING';
  end if;
  if v_currency is null then
    if coalesce(array_length(v_currencies, 1), 0) > 1 then
      raise exception 'the entries are billed in several currencies; name one' using errcode = '22023', hint = 'BILLABLE_TIME_CURRENCIES';
    end if;
    v_currency := v_currencies[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text) order by l.first_at), '[]'::jsonb),
    coalesce(jsonb_agg(l.entry_ids), '[]'::jsonb),
    coalesce(sum(round(l.quantity * l.rate)), 0)::bigint
    into v_lines, v_entries, v_total
  from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when invoice_from_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when invoice_from_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when invoice_from_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when invoice_from_time.group_by in ('member', 'entry') then u.user_id end,
      case when invoice_from_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l
  where l.currency = v_currency;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'no unbilled billable time matches' using errcode = 'P0002', hint = 'BILLABLE_TIME_EMPTY';
  end if;
  select coalesce(jsonb_agg(x.value order by x.value), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_entries) g, jsonb_array_elements(g.value) x;
  v_invoice := "better_supabase"."create_invoice"(invoice_from_time.tenant,
    (coalesce(invoice_from_time.attrs, '{}'::jsonb) - 'origin') || jsonb_build_object('currency', v_currency,
      'title', coalesce(nullif(trim(invoice_from_time.attrs ->> 'title'), ''), 'Time')), v_lines);
  insert into "better_supabase"."time_invoice_entries" ("entry_id", "tenant_id", "invoice_id", "rate", "currency", "seconds")
  select u.id, invoice_from_time.tenant, (v_invoice ->> 'id')::uuid, u.rate, u.currency, round(u.seconds)::bigint
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
  where u.id::text in (select jsonb_array_elements_text(v_entries));
  perform "better_supabase".emit_event('time_entry.invoiced', jsonb_build_object('organizationId', invoice_from_time.tenant, 'invoiceId', v_invoice ->> 'id', 'entryIds', v_entries, 'currency', v_currency, 'total', v_total::text), 'invoices/' || (v_invoice ->> 'id'), (invoice_from_time.tenant::text)::text, null, 'better-supabase/billable-time');
  perform better_supabase.audit_event(
    event_type => 'time_entry.invoiced',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_invoice ->> 'id',
    summary => 'invoiced time',
    tenant => (invoice_from_time.tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', invoice_from_time.tenant, 'invoiceId', v_invoice ->> 'id', 'entryIds', v_entries, 'currency', v_currency, 'total', v_total::text)
  );
  return jsonb_build_object('invoiceId', v_invoice ->> 'id', 'currency', v_currency, 'total', v_total::text, 'entryIds', v_entries);
end;
$$;
revoke execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) to authenticated, service_role;

-- The entries an invoice billed, with the rate and seconds it billed.
create or replace function "better_supabase"."list_invoiced_time"(invoice uuid, page_size integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."invoices" x where x."id" = list_invoiced_time.invoice;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'billable_time.read'), false)) then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('entryId', q."entry_id", 'invoiceId', q."invoice_id", 'userId', q.user_id,
      'subjectType', q.subject_type, 'subjectId', q.subject_id, 'startedAt', q.started_at, 'seconds', q."seconds",
      'rate', q."rate"::text, 'currency', q."currency", 'createdAt', q."created_at") order by q.started_at, q."entry_id"), '[]'::jsonb)
    from (
      select d.*, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id, x."started_at" as started_at
      from "better_supabase"."time_invoice_entries" d join "better_supabase"."time_entries" x on x."id" = d."entry_id"
      where d."invoice_id" = list_invoiced_time.invoice
      order by x."started_at"
      limit least(greatest(coalesce(list_invoiced_time.page_size, 500), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_invoiced_time"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_invoiced_time"(uuid, integer) to authenticated, service_role;

-- What a project cost and earned, per currency: its time at the rate card's
-- cost (on the project and its work items), the time billed on invoices at
-- the billed rate and, with accounting, the posted expense and income lines
-- on its project dimension (expense claims and purchase bills). The margin is
-- the billed time and income less the time cost and expenses; budget use
-- compares the hours and, in the budget's currency, the cost to the budget.
create or replace function "better_supabase"."project_costs"(project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_project "better_supabase"."projects"%rowtype;
  v_result jsonb;
begin
  select * into v_project from "better_supabase"."projects" x where x."id" = project_costs.project_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_project."tenant_id", 'billable_time.read'), false)) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
  end if;
  with spent as (
    select extract(epoch from x."ended_at" - x."started_at") as seconds, card.cost, card.currency,
      d."rate" as billed_rate, d."currency"::text as billed_currency, d."seconds" as billed_seconds
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."cost_amount" as cost, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on true
    left join "better_supabase"."time_invoice_entries" d on d."entry_id" = x."id"
    where x."tenant_id" = v_project."tenant_id"
      and x."ended_at" is not null
      and ((x."subject_type" = 'project' and x."subject_id" = v_project."id"::text) or (x."subject_type" = 'task' and x."subject_id" in (
        select y."id"::text from "better_supabase"."tasks" y where y."project_id" = v_project."id"
      )))
  ),
  totals as (
    select u.currency, sum(u.time_cost)::bigint as time_cost, sum(u.billed)::bigint as billed,
      sum(u.expenses)::bigint as expenses, sum(u.income)::bigint as income
    from (
      select s.currency, round(s.seconds / 3600.0 * s.cost)::bigint as time_cost, 0::bigint as billed, 0::bigint as expenses, 0::bigint as income
      from spent s where s.cost is not null
      union all
      select s.billed_currency, 0, round(s.billed_seconds / 3600.0 * s.billed_rate)::bigint, 0, 0
      from spent s where s.billed_rate is not null
      union all
      select q.currency, 0, 0, q.expenses, q.income from (select l."currency"::text as currency,
        coalesce(sum(l."debit" - l."credit") filter (where a."type" = 'expense'), 0)::bigint as expenses,
        coalesce(sum(l."credit" - l."debit") filter (where a."type" = 'income'), 0)::bigint as income
      from "better_supabase"."accounting_entry_lines" l
      join "better_supabase"."accounting_entries" n on n."id" = l."entry_id"
      join "better_supabase"."accounting_accounts" a on a."id" = l."account_id"
      where l."tenant_id" = v_project."tenant_id"
        and n."status" in ('posted', 'reversed')
        and l."dimensions" ->> 'project' = v_project."id"::text
      group by l."currency") q
    ) u
    group by u.currency
  )
  select jsonb_build_object(
    'projectId', v_project."id",
    'organizationId', v_project."tenant_id",
    'hours', (select round(coalesce(sum(s.seconds), 0) / 3600.0, 2) from spent s),
    'uncostedHours', (select round(coalesce(sum(s.seconds) filter (where s.cost is null), 0) / 3600.0, 2) from spent s),
    'budgetAmount', v_project."budget_amount"::text,
    'budgetCurrency', v_project."budget_currency",
    'budgetHours', v_project."budget_hours",
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'currency', t.currency,
          'timeCost', t.time_cost::text,
          'billed', t.billed::text,
          'expenses', t.expenses::text,
          'income', t.income::text,
          'margin', (t.billed + t.income - t.time_cost - t.expenses)::text
        ) order by t.currency), '[]'::jsonb)
      from totals t))
  into v_result;
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."project_costs"(uuid) from public, anon;
grant execute on function "better_supabase"."project_costs"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
create policy bsb_tenant_scope_select on "better_supabase"."time_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."time_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
create policy bsb_tenant_scope_update on "better_supabase"."time_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."time_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_select on "better_supabase"."time_invoice_entries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_update on "better_supabase"."time_invoice_entries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:e03d1cc092ec5ad01389ac485d7354915fad1cc6732344906a9f3d41034c5eb8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block billable-time@1 managed
-- @bsb-hash sha256:7100db5bc6d9a8d1b244a16ffc40228c55f15d623f59c96694709209b3fd0c13
-- A rate card for time entries, by member, record or organization with effective dates, and draft invoices from unbilled billable time with one line per record, member or entry, in bigint minor units. Billed entries lock until the invoice is voided.
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
    drop policy if exists bsb_tenant_scope on "app_private"."time_rates";
    drop policy if exists bsb_tenant_scope_select on "app_private"."time_rates";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."time_rates";
    drop policy if exists bsb_tenant_scope_update on "app_private"."time_rates";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."time_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_select on "app_private"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_update on "app_private"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."time_invoice_entries";
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
-- Billable time: a rate card for time entries and invoices drafted from
-- unbilled time, in bigint minor units.

create table if not exists "app_private"."time_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid,
  "subject_type" text,
  "subject_id" text,
  -- Minor units of currency per hour (ADR 0037).
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "effective_from" date not null default current_date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null)),
  unique nulls not distinct ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
);
-- What an hour costs the organization, in the rate's currency (project costing).
alter table "app_private"."time_rates" add column if not exists "cost_amount" bigint check ("cost_amount" >= 0);
create index if not exists "time_rates_lookup_idx" on "app_private"."time_rates" ("tenant_id", "subject_type", "subject_id", "user_id", "effective_from" desc);
alter table "app_private"."time_rates" enable row level security;
revoke all on "app_private"."time_rates" from public, anon, authenticated;
grant select on "app_private"."time_rates" to authenticated;
grant all on "app_private"."time_rates" to service_role;
drop policy if exists "time_rates_read" on "app_private"."time_rates";
create policy time_rates_read on "app_private"."time_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- One row per billed time entry: the invoice and the rate it was billed at.
create table if not exists "app_private"."time_invoice_entries" (
  "entry_id" uuid primary key references "better_supabase"."time_entries" ("id") on delete restrict,
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "rate" bigint not null,
  "currency" char(3) not null,
  "seconds" bigint not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "time_invoice_entries_invoice_idx" on "app_private"."time_invoice_entries" ("invoice_id");
create index if not exists "time_invoice_entries_tenant_idx" on "app_private"."time_invoice_entries" ("tenant_id");
alter table "app_private"."time_invoice_entries" enable row level security;
revoke all on "app_private"."time_invoice_entries" from public, anon, authenticated;
grant select on "app_private"."time_invoice_entries" to authenticated;
grant all on "app_private"."time_invoice_entries" to service_role;
drop policy if exists "time_invoice_entries_read" on "app_private"."time_invoice_entries";
create policy time_invoice_entries_read on "app_private"."time_invoice_entries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- A billed entry keeps what it was billed for: it can't be deleted, and its
-- time, billable flag and rate can't change until the invoice is voided. Its
-- record can, so a merge can move it.
create or replace function "app_private"."billable_time_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "app_private"."time_invoice_entries" d where d."entry_id" = old."id") then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- restrict_violation, so an organization purge retries the table later.
  if tg_op = 'DELETE' then
    raise exception 'this entry is on an invoice; void the invoice to delete it' using errcode = '23001', hint = 'TIME_ENTRY_INVOICED';
  end if;
  if old."started_at" is distinct from new."started_at" or old."ended_at" is distinct from new."ended_at" or old."billable" is distinct from new."billable" or old."rate" is distinct from new."rate" or old."rate_currency" is distinct from new."rate_currency" then
    raise exception 'this entry is on an invoice; void the invoice to change it' using errcode = '55000', hint = 'TIME_ENTRY_INVOICED';
  end if;
  return new;
end;
$$;
revoke execute on function "app_private"."billable_time_guard"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_guard on "better_supabase"."time_entries";
create trigger bsb_billable_time_guard
  before update or delete on "better_supabase"."time_entries"
  for each row execute function "app_private"."billable_time_guard"();

-- Voiding an invoice releases its entries so they can be billed again.
create or replace function "app_private"."billable_time_release"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "app_private"."time_invoice_entries" d where d."invoice_id" = new."id";
  return new;
end;
$$;
revoke execute on function "app_private"."billable_time_release"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_release on "better_supabase"."invoices";
create trigger bsb_billable_time_release
  after update of "status" on "better_supabase"."invoices"
  for each row when (new."status" = 'void' and old."status" <> 'void')
  execute function "app_private"."billable_time_release"();

-- Sets the hourly rate for a member, a record, both, or the organization
-- (neither), from effective_from (today by default), with what the hour costs
-- the organization (cost_amount, for project costing). The same key and day
-- replaces the rate.
drop function if exists "app_private"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);
create or replace function "app_private"."set_time_rate"(tenant uuid, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null, cost_amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_time_rate.tenant, 'billable_time.manage'), false)) then
    raise exception 'not allowed to change the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    raise exception 'a rate is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.cost_amount < 0 then
    raise exception 'a cost is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not false then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "app_private"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "cost_amount", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), set_time_rate.cost_amount, auth.uid())
  on conflict ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "cost_amount" = excluded."cost_amount", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) from public, anon;
grant execute on function "app_private"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) to authenticated, service_role;

create or replace function "app_private"."delete_time_rate"(rate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."time_rates" x where x."id" = delete_time_rate.rate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'billable_time.manage'), false)) then
    raise exception 'no such rate you can change' using errcode = 'P0002', hint = 'TIME_RATE_NOT_FOUND';
  end if;
  delete from "app_private"."time_rates" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."delete_time_rate"(uuid) from public, anon;
grant execute on function "app_private"."delete_time_rate"(uuid) to authenticated, service_role;

-- The rate card, newest first per key. Filters narrow it to a member or a
-- record (organization-wide rates are those with neither).
create or replace function "app_private"."list_time_rates"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_time_rates.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'rate', q."rate"::text, 'currency', q."currency", 'effectiveFrom', q."effective_from", 'cost', q."cost_amount"::text, 'createdBy', q."created_by", 'createdAt', q."created_at") order by q."subject_type" nulls first, q."subject_id" nulls first, q."user_id" nulls first, q."effective_from" desc), '[]'::jsonb)
    from (
      select * from "app_private"."time_rates" x
      where x."tenant_id" = list_time_rates.tenant
        and (list_time_rates.user_id is null or x."user_id" = list_time_rates.user_id)
        and (list_time_rates.subject_type is null or (x."subject_type" = list_time_rates.subject_type and x."subject_id" = list_time_rates.subject_id))
      order by x."effective_from" desc
      limit least(greatest(coalesce(list_time_rates.page_size, 200), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "app_private"."list_time_rates"(uuid, uuid, text, text, integer) from public, anon;
grant execute on function "app_private"."list_time_rates"(uuid, uuid, text, text, integer) to authenticated, service_role;

-- The rate card entry that applies to a member's time on a record on a day:
-- member and record first, then the record, the member, the organization.
create or replace function "app_private"."time_rate"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, on_day date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', time_rate.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'userId', c."user_id", 'subjectType', c."subject_type", 'subjectId', c."subject_id", 'rate', c."rate"::text, 'currency', c."currency", 'effectiveFrom', c."effective_from", 'cost', c."cost_amount"::text, 'createdBy', c."created_by", 'createdAt', c."created_at") from "app_private"."time_rates" c
    where c."tenant_id" = time_rate.tenant
      and (c."user_id" is null or c."user_id" = time_rate.user_id)
      and (c."subject_type" is null or (c."subject_type" = time_rate.subject_type and c."subject_id" = time_rate.subject_id))
      and c."effective_from" <= coalesce(time_rate.on_day, current_date)
    order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
    limit 1
  );
end;
$$;
revoke execute on function "app_private"."time_rate"(uuid, uuid, text, text, date) from public, anon;
grant execute on function "app_private"."time_rate"(uuid, uuid, text, text, date) to authenticated, service_role;

-- What invoice_from_time would bill: the lines per currency, their totals,
-- and the billable entries no rate covers. scope: subject ({ type, id }),
-- userId, starts, ends (on started_at) and entryIds.
create or replace function "app_private"."unbilled_time"(tenant uuid, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(unbilled_time.scope, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', unbilled_time.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if unbilled_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text, 'currency', l.currency, 'amount', round(l.quantity * l.rate)::bigint::text, 'entryIds', l.entry_ids, 'subjectType', l.subject_type, 'subjectId', l.subject_id, 'userId', coalesce(l.member_text, l.user_text)) order by l.currency, l.first_at), '[]'::jsonb)
      from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "app_private"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "app_private"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object('amount', t.amount::text, 'currency', t.currency) order by t.currency), '[]'::jsonb)
      from (select l.currency, sum(round(l.quantity * l.rate))::bigint as amount
        from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "app_private"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "app_private"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l group by l.currency) t),
    'unrated', (select coalesce(jsonb_agg(u.id order by u.started_at), '[]'::jsonb)
      from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "app_private"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "app_private"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u where u.rate is null)
  );
end;
$$;
revoke execute on function "app_private"."unbilled_time"(uuid, jsonb, text) from public, anon;
grant execute on function "app_private"."unbilled_time"(uuid, jsonb, text) to authenticated, service_role;

-- Bills the unbilled time a scope selects on a new draft invoice. attrs go to
-- create_invoice (title, default Time; company; contact; termsDays; note); its currency
-- picks the entries in that currency, and without one the entries must share
-- one. Fails while a selected billable entry has no rate.
create or replace function "app_private"."invoice_from_time"(tenant uuid, attrs jsonb, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(invoice_from_time.scope, '{}'::jsonb);
  v_currency text := upper(invoice_from_time.attrs ->> 'currency');
  v_currencies text[];
  v_unrated integer;
  v_lines jsonb;
  v_entries jsonb;
  v_total bigint;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invoice_from_time.tenant, 'billable_time.invoice'), false)) then
    raise exception 'not allowed to invoice time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if invoice_from_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || invoice_from_time.tenant::text, 0));
  select count(*) filter (where u.rate is null), array_agg(distinct u.currency) filter (where u.rate is not null)
    into v_unrated, v_currencies
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "app_private"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "app_private"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u;
  if v_unrated > 0 then
    raise exception 'some billable entries have no rate; set one on the entry or the rate card' using errcode = '22023', hint = 'TIME_RATE_MISSING';
  end if;
  if v_currency is null then
    if coalesce(array_length(v_currencies, 1), 0) > 1 then
      raise exception 'the entries are billed in several currencies; name one' using errcode = '22023', hint = 'BILLABLE_TIME_CURRENCIES';
    end if;
    v_currency := v_currencies[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text) order by l.first_at), '[]'::jsonb),
    coalesce(jsonb_agg(l.entry_ids), '[]'::jsonb),
    coalesce(sum(round(l.quantity * l.rate)), 0)::bigint
    into v_lines, v_entries, v_total
  from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when invoice_from_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when invoice_from_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when invoice_from_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "app_private"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "app_private"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when invoice_from_time.group_by in ('member', 'entry') then u.user_id end,
      case when invoice_from_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l
  where l.currency = v_currency;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'no unbilled billable time matches' using errcode = 'P0002', hint = 'BILLABLE_TIME_EMPTY';
  end if;
  select coalesce(jsonb_agg(x.value order by x.value), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_entries) g, jsonb_array_elements(g.value) x;
  v_invoice := "better_supabase"."create_invoice"(invoice_from_time.tenant,
    (coalesce(invoice_from_time.attrs, '{}'::jsonb) - 'origin') || jsonb_build_object('currency', v_currency,
      'title', coalesce(nullif(trim(invoice_from_time.attrs ->> 'title'), ''), 'Time')), v_lines);
  insert into "app_private"."time_invoice_entries" ("entry_id", "tenant_id", "invoice_id", "rate", "currency", "seconds")
  select u.id, invoice_from_time.tenant, (v_invoice ->> 'id')::uuid, u.rate, u.currency, round(u.seconds)::bigint
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "app_private"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "app_private"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
  where u.id::text in (select jsonb_array_elements_text(v_entries));
  null;
  return jsonb_build_object('invoiceId', v_invoice ->> 'id', 'currency', v_currency, 'total', v_total::text, 'entryIds', v_entries);
end;
$$;
revoke execute on function "app_private"."invoice_from_time"(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function "app_private"."invoice_from_time"(uuid, jsonb, jsonb, text) to authenticated, service_role;

-- The entries an invoice billed, with the rate and seconds it billed.
create or replace function "app_private"."list_invoiced_time"(invoice uuid, page_size integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."invoices" x where x."id" = list_invoiced_time.invoice;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'billable_time.read'), false)) then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('entryId', q."entry_id", 'invoiceId', q."invoice_id", 'userId', q.user_id,
      'subjectType', q.subject_type, 'subjectId', q.subject_id, 'startedAt', q.started_at, 'seconds', q."seconds",
      'rate', q."rate"::text, 'currency', q."currency", 'createdAt', q."created_at") order by q.started_at, q."entry_id"), '[]'::jsonb)
    from (
      select d.*, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id, x."started_at" as started_at
      from "app_private"."time_invoice_entries" d join "better_supabase"."time_entries" x on x."id" = d."entry_id"
      where d."invoice_id" = list_invoiced_time.invoice
      order by x."started_at"
      limit least(greatest(coalesce(list_invoiced_time.page_size, 500), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "app_private"."list_invoiced_time"(uuid, integer) from public, anon;
grant execute on function "app_private"."list_invoiced_time"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."time_rates";
drop policy if exists bsb_tenant_scope_select on "app_private"."time_rates";
create policy bsb_tenant_scope_select on "app_private"."time_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."time_rates";
create policy bsb_tenant_scope_insert on "app_private"."time_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."time_rates";
create policy bsb_tenant_scope_update on "app_private"."time_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."time_rates";
create policy bsb_tenant_scope_delete on "app_private"."time_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."time_invoice_entries";
drop policy if exists bsb_tenant_scope_select on "app_private"."time_invoice_entries";
create policy bsb_tenant_scope_select on "app_private"."time_invoice_entries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."time_invoice_entries";
create policy bsb_tenant_scope_insert on "app_private"."time_invoice_entries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."time_invoice_entries";
create policy bsb_tenant_scope_update on "app_private"."time_invoice_entries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."time_invoice_entries";
create policy bsb_tenant_scope_delete on "app_private"."time_invoice_entries" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:e03d1cc092ec5ad01389ac485d7354915fad1cc6732344906a9f3d41034c5eb8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block billable-time@1 managed
-- @bsb-hash sha256:ef8dccb0eed2c51ec2e0d4766d02a6e272cfb0792f9ae51bb1f12353de5ee575
-- A rate card for time entries, by member, record or organization with effective dates, and draft invoices from unbilled billable time with one line per record, member or entry, in bigint minor units. Billed entries lock until the invoice is voided.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Billable time: a rate card for time entries and invoices drafted from
-- unbilled time, in bigint minor units.

create table if not exists "better_supabase"."time_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid,
  "subject_type" text,
  "subject_id" text,
  -- Minor units of currency per hour (ADR 0037).
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "effective_from" date not null default current_date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null)),
  unique nulls not distinct ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
);
-- What an hour costs the organization, in the rate's currency (project costing).
alter table "better_supabase"."time_rates" add column if not exists "cost_amount" bigint check ("cost_amount" >= 0);
create index if not exists "time_rates_lookup_idx" on "better_supabase"."time_rates" ("tenant_id", "subject_type", "subject_id", "user_id", "effective_from" desc);
alter table "better_supabase"."time_rates" enable row level security;
revoke all on "better_supabase"."time_rates" from public, anon, authenticated;
grant select on "better_supabase"."time_rates" to authenticated;
grant all on "better_supabase"."time_rates" to service_role;
drop policy if exists "time_rates_read" on "better_supabase"."time_rates";
create policy time_rates_read on "better_supabase"."time_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- One row per billed time entry: the invoice and the rate it was billed at.
create table if not exists "better_supabase"."time_invoice_entries" (
  "entry_id" uuid primary key references "better_supabase"."time_entries" ("id") on delete restrict,
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "rate" bigint not null,
  "currency" char(3) not null,
  "seconds" bigint not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "time_invoice_entries_invoice_idx" on "better_supabase"."time_invoice_entries" ("invoice_id");
create index if not exists "time_invoice_entries_tenant_idx" on "better_supabase"."time_invoice_entries" ("tenant_id");
alter table "better_supabase"."time_invoice_entries" enable row level security;
revoke all on "better_supabase"."time_invoice_entries" from public, anon, authenticated;
grant select on "better_supabase"."time_invoice_entries" to authenticated;
grant all on "better_supabase"."time_invoice_entries" to service_role;
drop policy if exists "time_invoice_entries_read" on "better_supabase"."time_invoice_entries";
create policy time_invoice_entries_read on "better_supabase"."time_invoice_entries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- A billed entry keeps what it was billed for: it can't be deleted, and its
-- time, billable flag and rate can't change until the invoice is voided. Its
-- record can, so a merge can move it.
create or replace function "better_supabase"."billable_time_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = old."id") then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- restrict_violation, so an organization purge retries the table later.
  if tg_op = 'DELETE' then
    raise exception 'this entry is on an invoice; void the invoice to delete it' using errcode = '23001', hint = 'TIME_ENTRY_INVOICED';
  end if;
  if old."started_at" is distinct from new."started_at" or old."ended_at" is distinct from new."ended_at" or old."billable" is distinct from new."billable" or old."rate" is distinct from new."rate" or old."rate_currency" is distinct from new."rate_currency" then
    raise exception 'this entry is on an invoice; void the invoice to change it' using errcode = '55000', hint = 'TIME_ENTRY_INVOICED';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_guard"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_guard on "better_supabase"."time_entries";
create trigger bsb_billable_time_guard
  before update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."billable_time_guard"();

-- Voiding an invoice releases its entries so they can be billed again.
create or replace function "better_supabase"."billable_time_release"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."time_invoice_entries" d where d."invoice_id" = new."id";
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_release"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_release on "better_supabase"."invoices";
create trigger bsb_billable_time_release
  after update of "status" on "better_supabase"."invoices"
  for each row when (new."status" = 'void' and old."status" <> 'void')
  execute function "better_supabase"."billable_time_release"();

-- Sets the hourly rate for a member, a record, both, or the organization
-- (neither), from effective_from (today by default), with what the hour costs
-- the organization (cost_amount, for project costing). The same key and day
-- replaces the rate.
drop function if exists "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);
create or replace function "better_supabase"."set_time_rate"(tenant uuid, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null, cost_amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_time_rate.tenant, 'billable_time.manage'), false)) then
    raise exception 'not allowed to change the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    raise exception 'a rate is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.cost_amount < 0 then
    raise exception 'a cost is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not false then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "cost_amount", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), set_time_rate.cost_amount, auth.uid())
  on conflict ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "cost_amount" = excluded."cost_amount", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_rate"(rate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_rates" x where x."id" = delete_time_rate.rate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'billable_time.manage'), false)) then
    raise exception 'no such rate you can change' using errcode = 'P0002', hint = 'TIME_RATE_NOT_FOUND';
  end if;
  delete from "better_supabase"."time_rates" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_rate"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_rate"(uuid) to authenticated, service_role;

-- The rate card, newest first per key. Filters narrow it to a member or a
-- record (organization-wide rates are those with neither).
create or replace function "better_supabase"."list_time_rates"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_time_rates.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'rate', q."rate"::text, 'currency', q."currency", 'effectiveFrom', q."effective_from", 'cost', q."cost_amount"::text, 'createdBy', q."created_by", 'createdAt', q."created_at") order by q."subject_type" nulls first, q."subject_id" nulls first, q."user_id" nulls first, q."effective_from" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = list_time_rates.tenant
        and (list_time_rates.user_id is null or x."user_id" = list_time_rates.user_id)
        and (list_time_rates.subject_type is null or (x."subject_type" = list_time_rates.subject_type and x."subject_id" = list_time_rates.subject_id))
      order by x."effective_from" desc
      limit least(greatest(coalesce(list_time_rates.page_size, 200), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) to authenticated, service_role;

-- The rate card entry that applies to a member's time on a record on a day:
-- member and record first, then the record, the member, the organization.
create or replace function "better_supabase"."time_rate"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, on_day date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', time_rate.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'userId', c."user_id", 'subjectType', c."subject_type", 'subjectId', c."subject_id", 'rate', c."rate"::text, 'currency', c."currency", 'effectiveFrom', c."effective_from", 'cost', c."cost_amount"::text, 'createdBy', c."created_by", 'createdAt', c."created_at") from "better_supabase"."time_rates" c
    where c."tenant_id" = time_rate.tenant
      and (c."user_id" is null or c."user_id" = time_rate.user_id)
      and (c."subject_type" is null or (c."subject_type" = time_rate.subject_type and c."subject_id" = time_rate.subject_id))
      and c."effective_from" <= coalesce(time_rate.on_day, current_date)
    order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) from public, anon;
grant execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) to authenticated, service_role;

-- What invoice_from_time would bill: the lines per currency, their totals,
-- and the billable entries no rate covers. scope: subject ({ type, id }),
-- userId, starts, ends (on started_at) and entryIds.
create or replace function "better_supabase"."unbilled_time"(tenant uuid, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(unbilled_time.scope, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', unbilled_time.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if unbilled_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text, 'currency', l.currency, 'amount', round(l.quantity * l.rate)::bigint::text, 'entryIds', l.entry_ids, 'subjectType', l.subject_type, 'subjectId', l.subject_id, 'userId', coalesce(l.member_text, l.user_text)) order by l.currency, l.first_at), '[]'::jsonb)
      from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object('amount', t.amount::text, 'currency', t.currency) order by t.currency), '[]'::jsonb)
      from (select l.currency, sum(round(l.quantity * l.rate))::bigint as amount
        from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l group by l.currency) t),
    'unrated', (select coalesce(jsonb_agg(u.id order by u.started_at), '[]'::jsonb)
      from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u where u.rate is null)
  );
end;
$$;
revoke execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) to authenticated, service_role;

-- Bills the unbilled time a scope selects on a new draft invoice. attrs go to
-- create_invoice (title, default Time; company; contact; termsDays; note); its currency
-- picks the entries in that currency, and without one the entries must share
-- one. Fails while a selected billable entry has no rate.
create or replace function "better_supabase"."invoice_from_time"(tenant uuid, attrs jsonb, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(invoice_from_time.scope, '{}'::jsonb);
  v_currency text := upper(invoice_from_time.attrs ->> 'currency');
  v_currencies text[];
  v_unrated integer;
  v_lines jsonb;
  v_entries jsonb;
  v_total bigint;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invoice_from_time.tenant, 'billable_time.invoice'), false)) then
    raise exception 'not allowed to invoice time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if invoice_from_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || invoice_from_time.tenant::text, 0));
  select count(*) filter (where u.rate is null), array_agg(distinct u.currency) filter (where u.rate is not null)
    into v_unrated, v_currencies
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u;
  if v_unrated > 0 then
    raise exception 'some billable entries have no rate; set one on the entry or the rate card' using errcode = '22023', hint = 'TIME_RATE_MISSING';
  end if;
  if v_currency is null then
    if coalesce(array_length(v_currencies, 1), 0) > 1 then
      raise exception 'the entries are billed in several currencies; name one' using errcode = '22023', hint = 'BILLABLE_TIME_CURRENCIES';
    end if;
    v_currency := v_currencies[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text) order by l.first_at), '[]'::jsonb),
    coalesce(jsonb_agg(l.entry_ids), '[]'::jsonb),
    coalesce(sum(round(l.quantity * l.rate)), 0)::bigint
    into v_lines, v_entries, v_total
  from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when invoice_from_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when invoice_from_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when invoice_from_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when invoice_from_time.group_by in ('member', 'entry') then u.user_id end,
      case when invoice_from_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l
  where l.currency = v_currency;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'no unbilled billable time matches' using errcode = 'P0002', hint = 'BILLABLE_TIME_EMPTY';
  end if;
  select coalesce(jsonb_agg(x.value order by x.value), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_entries) g, jsonb_array_elements(g.value) x;
  v_invoice := "better_supabase"."create_invoice"(invoice_from_time.tenant,
    (coalesce(invoice_from_time.attrs, '{}'::jsonb) - 'origin') || jsonb_build_object('currency', v_currency,
      'title', coalesce(nullif(trim(invoice_from_time.attrs ->> 'title'), ''), 'Time')), v_lines);
  insert into "better_supabase"."time_invoice_entries" ("entry_id", "tenant_id", "invoice_id", "rate", "currency", "seconds")
  select u.id, invoice_from_time.tenant, (v_invoice ->> 'id')::uuid, u.rate, u.currency, round(u.seconds)::bigint
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
  where u.id::text in (select jsonb_array_elements_text(v_entries));
  null;
  return jsonb_build_object('invoiceId', v_invoice ->> 'id', 'currency', v_currency, 'total', v_total::text, 'entryIds', v_entries);
end;
$$;
revoke execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) to authenticated, service_role;

-- The entries an invoice billed, with the rate and seconds it billed.
create or replace function "better_supabase"."list_invoiced_time"(invoice uuid, page_size integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."invoices" x where x."id" = list_invoiced_time.invoice;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'billable_time.read'), false)) then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('entryId', q."entry_id", 'invoiceId', q."invoice_id", 'userId', q.user_id,
      'subjectType', q.subject_type, 'subjectId', q.subject_id, 'startedAt', q.started_at, 'seconds', q."seconds",
      'rate', q."rate"::text, 'currency', q."currency", 'createdAt', q."created_at") order by q.started_at, q."entry_id"), '[]'::jsonb)
    from (
      select d.*, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id, x."started_at" as started_at
      from "better_supabase"."time_invoice_entries" d join "better_supabase"."time_entries" x on x."id" = d."entry_id"
      where d."invoice_id" = list_invoiced_time.invoice
      order by x."started_at"
      limit least(greatest(coalesce(list_invoiced_time.page_size, 500), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_invoiced_time"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_invoiced_time"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
create policy bsb_tenant_scope_select on "better_supabase"."time_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."time_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
create policy bsb_tenant_scope_update on "better_supabase"."time_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."time_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_select on "better_supabase"."time_invoice_entries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_update on "better_supabase"."time_invoice_entries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.billable-time.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);

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

create or replace function "api"."set_time_rate"(tenant uuid, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null, cost_amount bigint default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_time_rate"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) from public, anon;
grant execute on function "api"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) to authenticated, service_role;

create or replace function "api"."delete_time_rate"(rate_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_time_rate"($1) $$;
revoke execute on function "api"."delete_time_rate"(uuid) from public, anon;
grant execute on function "api"."delete_time_rate"(uuid) to authenticated, service_role;

create or replace function "api"."list_time_rates"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, page_size integer default 200)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_time_rates"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_time_rates"(uuid, uuid, text, text, integer) from public, anon;
grant execute on function "api"."list_time_rates"(uuid, uuid, text, text, integer) to authenticated, service_role;

create or replace function "api"."time_rate"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, on_day date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."time_rate"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."time_rate"(uuid, uuid, text, text, date) from public, anon;
grant execute on function "api"."time_rate"(uuid, uuid, text, text, date) to authenticated, service_role;

create or replace function "api"."unbilled_time"(tenant uuid, scope jsonb default null, group_by text default 'subject')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unbilled_time"($1, $2, $3) $$;
revoke execute on function "api"."unbilled_time"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."unbilled_time"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."invoice_from_time"(tenant uuid, attrs jsonb, scope jsonb default null, group_by text default 'subject')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."invoice_from_time"($1, $2, $3, $4) $$;
revoke execute on function "api"."invoice_from_time"(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function "api"."invoice_from_time"(uuid, jsonb, jsonb, text) to authenticated, service_role;

create or replace function "api"."list_invoiced_time"(invoice uuid, page_size integer default 500)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_invoiced_time"($1, $2) $$;
revoke execute on function "api"."list_invoiced_time"(uuid, integer) from public, anon;
grant execute on function "api"."list_invoiced_time"(uuid, integer) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:e03d1cc092ec5ad01389ac485d7354915fad1cc6732344906a9f3d41034c5eb8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block billable-time@1 managed
-- @bsb-hash sha256:a118a8d80f3b644b25dd6215b6623219a832651a87dc1ef159ddfc41a2285316
-- A rate card for time entries, by member, record or organization with effective dates, and draft invoices from unbilled billable time with one line per record, member or entry, in bigint minor units. Billed entries lock until the invoice is voided.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Billable time: a rate card for time entries and invoices drafted from
-- unbilled time, in bigint minor units.

-- better_supabase.time_rates is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."time_rates" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."time_rates" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."time_rates" add column if not exists "user_id" uuid;
alter table "better_supabase"."time_rates" add column if not exists "subject_type" text;
alter table "better_supabase"."time_rates" add column if not exists "subject_id" text;
alter table "better_supabase"."time_rates" add column if not exists "rate" bigint check ("rate" >= 0);
alter table "better_supabase"."time_rates" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."time_rates" add column if not exists "effective_from" date not null default current_date;
alter table "better_supabase"."time_rates" add column if not exists "created_by" uuid;
alter table "better_supabase"."time_rates" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_time_rates_rate_key" on "better_supabase"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from") nulls not distinct;
-- What an hour costs the organization, in the rate's currency (project costing).
alter table "better_supabase"."time_rates" add column if not exists "cost_amount" bigint check ("cost_amount" >= 0);
create index if not exists "time_rates_lookup_idx" on "better_supabase"."time_rates" ("tenant_id", "subject_type", "subject_id", "user_id", "effective_from" desc);
alter table "better_supabase"."time_rates" enable row level security;
grant select on "better_supabase"."time_rates" to authenticated;
grant all on "better_supabase"."time_rates" to service_role;
drop policy if exists bsb_time_rates_select on "better_supabase"."time_rates";
create policy bsb_time_rates_select on "better_supabase"."time_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- One row per billed time entry: the invoice and the rate it was billed at.
-- better_supabase.time_invoice_entries is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."time_invoice_entries" add column if not exists "entry_id" uuid references "better_supabase"."time_entries" ("id") on delete restrict;
alter table "better_supabase"."time_invoice_entries" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."time_invoice_entries" add column if not exists "invoice_id" uuid references "better_supabase"."invoices" ("id") on delete cascade;
alter table "better_supabase"."time_invoice_entries" add column if not exists "rate" bigint;
alter table "better_supabase"."time_invoice_entries" add column if not exists "currency" char(3);
alter table "better_supabase"."time_invoice_entries" add column if not exists "seconds" bigint;
alter table "better_supabase"."time_invoice_entries" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "time_invoice_entries_invoice_idx" on "better_supabase"."time_invoice_entries" ("invoice_id");
create index if not exists "time_invoice_entries_tenant_idx" on "better_supabase"."time_invoice_entries" ("tenant_id");
alter table "better_supabase"."time_invoice_entries" enable row level security;
grant select on "better_supabase"."time_invoice_entries" to authenticated;
grant all on "better_supabase"."time_invoice_entries" to service_role;
drop policy if exists bsb_time_invoice_entries_select on "better_supabase"."time_invoice_entries";
create policy bsb_time_invoice_entries_select on "better_supabase"."time_invoice_entries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- A billed entry keeps what it was billed for: it can't be deleted, and its
-- time, billable flag and rate can't change until the invoice is voided. Its
-- record can, so a merge can move it.
create or replace function "better_supabase"."billable_time_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = old."id") then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- restrict_violation, so an organization purge retries the table later.
  if tg_op = 'DELETE' then
    raise exception 'this entry is on an invoice; void the invoice to delete it' using errcode = '23001', hint = 'TIME_ENTRY_INVOICED';
  end if;
  if old."started_at" is distinct from new."started_at" or old."ended_at" is distinct from new."ended_at" or old."billable" is distinct from new."billable" or old."rate" is distinct from new."rate" or old."rate_currency" is distinct from new."rate_currency" then
    raise exception 'this entry is on an invoice; void the invoice to change it' using errcode = '55000', hint = 'TIME_ENTRY_INVOICED';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_guard"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_guard on "better_supabase"."time_entries";
create trigger bsb_billable_time_guard
  before update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."billable_time_guard"();

-- Voiding an invoice releases its entries so they can be billed again.
create or replace function "better_supabase"."billable_time_release"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."time_invoice_entries" d where d."invoice_id" = new."id";
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_release"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_release on "better_supabase"."invoices";
create trigger bsb_billable_time_release
  after update of "status" on "better_supabase"."invoices"
  for each row when (new."status" = 'void' and old."status" <> 'void')
  execute function "better_supabase"."billable_time_release"();

-- Sets the hourly rate for a member, a record, both, or the organization
-- (neither), from effective_from (today by default), with what the hour costs
-- the organization (cost_amount, for project costing). The same key and day
-- replaces the rate.
drop function if exists "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);
create or replace function "better_supabase"."set_time_rate"(tenant uuid, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null, cost_amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_time_rate.tenant, 'billable_time.manage'), false)) then
    raise exception 'not allowed to change the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    raise exception 'a rate is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.cost_amount < 0 then
    raise exception 'a cost is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not false then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "cost_amount", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), set_time_rate.cost_amount, auth.uid())
  on conflict ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "cost_amount" = excluded."cost_amount", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_rate"(rate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_rates" x where x."id" = delete_time_rate.rate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'billable_time.manage'), false)) then
    raise exception 'no such rate you can change' using errcode = 'P0002', hint = 'TIME_RATE_NOT_FOUND';
  end if;
  delete from "better_supabase"."time_rates" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_rate"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_rate"(uuid) to authenticated, service_role;

-- The rate card, newest first per key. Filters narrow it to a member or a
-- record (organization-wide rates are those with neither).
create or replace function "better_supabase"."list_time_rates"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_time_rates.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'rate', q."rate"::text, 'currency', q."currency", 'effectiveFrom', q."effective_from", 'cost', q."cost_amount"::text, 'createdBy', q."created_by", 'createdAt', q."created_at") order by q."subject_type" nulls first, q."subject_id" nulls first, q."user_id" nulls first, q."effective_from" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = list_time_rates.tenant
        and (list_time_rates.user_id is null or x."user_id" = list_time_rates.user_id)
        and (list_time_rates.subject_type is null or (x."subject_type" = list_time_rates.subject_type and x."subject_id" = list_time_rates.subject_id))
      order by x."effective_from" desc
      limit least(greatest(coalesce(list_time_rates.page_size, 200), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) to authenticated, service_role;

-- The rate card entry that applies to a member's time on a record on a day:
-- member and record first, then the record, the member, the organization.
create or replace function "better_supabase"."time_rate"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, on_day date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', time_rate.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'userId', c."user_id", 'subjectType', c."subject_type", 'subjectId', c."subject_id", 'rate', c."rate"::text, 'currency', c."currency", 'effectiveFrom', c."effective_from", 'cost', c."cost_amount"::text, 'createdBy', c."created_by", 'createdAt', c."created_at") from "better_supabase"."time_rates" c
    where c."tenant_id" = time_rate.tenant
      and (c."user_id" is null or c."user_id" = time_rate.user_id)
      and (c."subject_type" is null or (c."subject_type" = time_rate.subject_type and c."subject_id" = time_rate.subject_id))
      and c."effective_from" <= coalesce(time_rate.on_day, current_date)
    order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) from public, anon;
grant execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) to authenticated, service_role;

-- What invoice_from_time would bill: the lines per currency, their totals,
-- and the billable entries no rate covers. scope: subject ({ type, id }),
-- userId, starts, ends (on started_at) and entryIds.
create or replace function "better_supabase"."unbilled_time"(tenant uuid, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(unbilled_time.scope, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', unbilled_time.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if unbilled_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text, 'currency', l.currency, 'amount', round(l.quantity * l.rate)::bigint::text, 'entryIds', l.entry_ids, 'subjectType', l.subject_type, 'subjectId', l.subject_id, 'userId', coalesce(l.member_text, l.user_text)) order by l.currency, l.first_at), '[]'::jsonb)
      from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object('amount', t.amount::text, 'currency', t.currency) order by t.currency), '[]'::jsonb)
      from (select l.currency, sum(round(l.quantity * l.rate))::bigint as amount
        from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l group by l.currency) t),
    'unrated', (select coalesce(jsonb_agg(u.id order by u.started_at), '[]'::jsonb)
      from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u where u.rate is null)
  );
end;
$$;
revoke execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) to authenticated, service_role;

-- Bills the unbilled time a scope selects on a new draft invoice. attrs go to
-- create_invoice (title, default Time; company; contact; termsDays; note); its currency
-- picks the entries in that currency, and without one the entries must share
-- one. Fails while a selected billable entry has no rate.
create or replace function "better_supabase"."invoice_from_time"(tenant uuid, attrs jsonb, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(invoice_from_time.scope, '{}'::jsonb);
  v_currency text := upper(invoice_from_time.attrs ->> 'currency');
  v_currencies text[];
  v_unrated integer;
  v_lines jsonb;
  v_entries jsonb;
  v_total bigint;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invoice_from_time.tenant, 'billable_time.invoice'), false)) then
    raise exception 'not allowed to invoice time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if invoice_from_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || invoice_from_time.tenant::text, 0));
  select count(*) filter (where u.rate is null), array_agg(distinct u.currency) filter (where u.rate is not null)
    into v_unrated, v_currencies
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u;
  if v_unrated > 0 then
    raise exception 'some billable entries have no rate; set one on the entry or the rate card' using errcode = '22023', hint = 'TIME_RATE_MISSING';
  end if;
  if v_currency is null then
    if coalesce(array_length(v_currencies, 1), 0) > 1 then
      raise exception 'the entries are billed in several currencies; name one' using errcode = '22023', hint = 'BILLABLE_TIME_CURRENCIES';
    end if;
    v_currency := v_currencies[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text) order by l.first_at), '[]'::jsonb),
    coalesce(jsonb_agg(l.entry_ids), '[]'::jsonb),
    coalesce(sum(round(l.quantity * l.rate)), 0)::bigint
    into v_lines, v_entries, v_total
  from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when invoice_from_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when invoice_from_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when invoice_from_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when invoice_from_time.group_by in ('member', 'entry') then u.user_id end,
      case when invoice_from_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l
  where l.currency = v_currency;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'no unbilled billable time matches' using errcode = 'P0002', hint = 'BILLABLE_TIME_EMPTY';
  end if;
  select coalesce(jsonb_agg(x.value order by x.value), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_entries) g, jsonb_array_elements(g.value) x;
  v_invoice := "better_supabase"."create_invoice"(invoice_from_time.tenant,
    (coalesce(invoice_from_time.attrs, '{}'::jsonb) - 'origin') || jsonb_build_object('currency', v_currency,
      'title', coalesce(nullif(trim(invoice_from_time.attrs ->> 'title'), ''), 'Time')), v_lines);
  insert into "better_supabase"."time_invoice_entries" ("entry_id", "tenant_id", "invoice_id", "rate", "currency", "seconds")
  select u.id, invoice_from_time.tenant, (v_invoice ->> 'id')::uuid, u.rate, u.currency, round(u.seconds)::bigint
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
  where u.id::text in (select jsonb_array_elements_text(v_entries));
  null;
  return jsonb_build_object('invoiceId', v_invoice ->> 'id', 'currency', v_currency, 'total', v_total::text, 'entryIds', v_entries);
end;
$$;
revoke execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) to authenticated, service_role;

-- The entries an invoice billed, with the rate and seconds it billed.
create or replace function "better_supabase"."list_invoiced_time"(invoice uuid, page_size integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."invoices" x where x."id" = list_invoiced_time.invoice;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'billable_time.read'), false)) then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('entryId', q."entry_id", 'invoiceId', q."invoice_id", 'userId', q.user_id,
      'subjectType', q.subject_type, 'subjectId', q.subject_id, 'startedAt', q.started_at, 'seconds', q."seconds",
      'rate', q."rate"::text, 'currency', q."currency", 'createdAt', q."created_at") order by q.started_at, q."entry_id"), '[]'::jsonb)
    from (
      select d."entry_id", d."invoice_id", d."rate", d."currency", d."seconds", d."created_at", x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id, x."started_at" as started_at
      from "better_supabase"."time_invoice_entries" d join "better_supabase"."time_entries" x on x."id" = d."entry_id"
      where d."invoice_id" = list_invoiced_time.invoice
      order by x."started_at"
      limit least(greatest(coalesce(list_invoiced_time.page_size, 500), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_invoiced_time"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_invoiced_time"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
create policy bsb_tenant_scope_select on "better_supabase"."time_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."time_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
create policy bsb_tenant_scope_update on "better_supabase"."time_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."time_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_select on "better_supabase"."time_invoice_entries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_update on "better_supabase"."time_invoice_entries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:e03d1cc092ec5ad01389ac485d7354915fad1cc6732344906a9f3d41034c5eb8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block billable-time@1 managed
-- @bsb-hash sha256:067fdd77d63e2f35c560dbfb05d1d4e667193ab34d3e321b697564ba40eec2a5
-- A rate card for time entries, by member, record or organization with effective dates, and draft invoices from unbilled billable time with one line per record, member or entry, in bigint minor units. Billed entries lock until the invoice is voided.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Billable time: a rate card for time entries and invoices drafted from
-- unbilled time, in bigint minor units.

create table if not exists "better_supabase"."time_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "user_id" uuid,
  "subject_type" text,
  "subject_id" text,
  -- Minor units of currency per hour (ADR 0037).
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "effective_from" date not null default current_date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null)),
  unique nulls not distinct ("org_id", "user_id", "subject_type", "subject_id", "effective_from")
);
-- What an hour costs the organization, in the rate's currency (project costing).
alter table "better_supabase"."time_rates" add column if not exists "cost_amount" bigint check ("cost_amount" >= 0);
create index if not exists "time_rates_lookup_idx" on "better_supabase"."time_rates" ("org_id", "subject_type", "subject_id", "user_id", "effective_from" desc);
alter table "better_supabase"."time_rates" enable row level security;
revoke all on "better_supabase"."time_rates" from public, anon, authenticated;
grant select on "better_supabase"."time_rates" to authenticated;
grant all on "better_supabase"."time_rates" to service_role;
drop policy if exists "time_rates_read" on "better_supabase"."time_rates";
create policy time_rates_read on "better_supabase"."time_rates"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- One row per billed time entry: the invoice and the rate it was billed at.
create table if not exists "better_supabase"."time_invoice_entries" (
  "entry_id" uuid primary key references "better_supabase"."time_entries" ("id") on delete restrict,
  "org_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "rate" bigint not null,
  "currency" char(3) not null,
  "seconds" bigint not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "time_invoice_entries_invoice_idx" on "better_supabase"."time_invoice_entries" ("invoice_id");
create index if not exists "time_invoice_entries_tenant_idx" on "better_supabase"."time_invoice_entries" ("org_id");
alter table "better_supabase"."time_invoice_entries" enable row level security;
revoke all on "better_supabase"."time_invoice_entries" from public, anon, authenticated;
grant select on "better_supabase"."time_invoice_entries" to authenticated;
grant all on "better_supabase"."time_invoice_entries" to service_role;
drop policy if exists "time_invoice_entries_read" on "better_supabase"."time_invoice_entries";
create policy time_invoice_entries_read on "better_supabase"."time_invoice_entries"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('billable_time.read')));

-- A billed entry keeps what it was billed for: it can't be deleted, and its
-- time, billable flag and rate can't change until the invoice is voided. Its
-- record can, so a merge can move it.
create or replace function "better_supabase"."billable_time_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = old."id") then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- restrict_violation, so an organization purge retries the table later.
  if tg_op = 'DELETE' then
    raise exception 'this entry is on an invoice; void the invoice to delete it' using errcode = '23001', hint = 'TIME_ENTRY_INVOICED';
  end if;
  if old."started_at" is distinct from new."started_at" or old."ended_at" is distinct from new."ended_at" or old."billable" is distinct from new."billable" or old."rate" is distinct from new."rate" or old."rate_currency" is distinct from new."rate_currency" then
    raise exception 'this entry is on an invoice; void the invoice to change it' using errcode = '55000', hint = 'TIME_ENTRY_INVOICED';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_guard"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_guard on "better_supabase"."time_entries";
create trigger bsb_billable_time_guard
  before update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."billable_time_guard"();

-- Voiding an invoice releases its entries so they can be billed again.
create or replace function "better_supabase"."billable_time_release"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."time_invoice_entries" d where d."invoice_id" = new."id";
  return new;
end;
$$;
revoke execute on function "better_supabase"."billable_time_release"() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_release on "better_supabase"."invoices";
create trigger bsb_billable_time_release
  after update of "status" on "better_supabase"."invoices"
  for each row when (new."status" = 'void' and old."status" <> 'void')
  execute function "better_supabase"."billable_time_release"();

-- Sets the hourly rate for a member, a record, both, or the organization
-- (neither), from effective_from (today by default), with what the hour costs
-- the organization (cost_amount, for project costing). The same key and day
-- replaces the rate.
drop function if exists "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);
create or replace function "better_supabase"."set_time_rate"(tenant uuid, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null, cost_amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_time_rate.tenant, 'billable_time.manage'), false)) then
    raise exception 'not allowed to change the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    raise exception 'a rate is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.cost_amount < 0 then
    raise exception 'a cost is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not false then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."org_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."time_rates" ("org_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "cost_amount", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), set_time_rate.cost_amount, auth.uid())
  on conflict ("org_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "cost_amount" = excluded."cost_amount", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_rate"(rate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_rates" x where x."id" = delete_time_rate.rate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'billable_time.manage'), false)) then
    raise exception 'no such rate you can change' using errcode = 'P0002', hint = 'TIME_RATE_NOT_FOUND';
  end if;
  delete from "better_supabase"."time_rates" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_rate"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_rate"(uuid) to authenticated, service_role;

-- The rate card, newest first per key. Filters narrow it to a member or a
-- record (organization-wide rates are those with neither).
create or replace function "better_supabase"."list_time_rates"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_time_rates.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'rate', q."rate"::text, 'currency', q."currency", 'effectiveFrom', q."effective_from", 'cost', q."cost_amount"::text, 'createdBy', q."created_by", 'createdAt', q."created_at") order by q."subject_type" nulls first, q."subject_id" nulls first, q."user_id" nulls first, q."effective_from" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."time_rates" x
      where x."org_id" = list_time_rates.tenant
        and (list_time_rates.user_id is null or x."user_id" = list_time_rates.user_id)
        and (list_time_rates.subject_type is null or (x."subject_type" = list_time_rates.subject_type and x."subject_id" = list_time_rates.subject_id))
      order by x."effective_from" desc
      limit least(greatest(coalesce(list_time_rates.page_size, 200), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_time_rates"(uuid, uuid, text, text, integer) to authenticated, service_role;

-- The rate card entry that applies to a member's time on a record on a day:
-- member and record first, then the record, the member, the organization.
create or replace function "better_supabase"."time_rate"(tenant uuid, user_id uuid default null, subject_type text default null, subject_id text default null, on_day date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', time_rate.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('id', c."id", 'organizationId', c."org_id", 'userId', c."user_id", 'subjectType', c."subject_type", 'subjectId', c."subject_id", 'rate', c."rate"::text, 'currency', c."currency", 'effectiveFrom', c."effective_from", 'cost', c."cost_amount"::text, 'createdBy', c."created_by", 'createdAt', c."created_at") from "better_supabase"."time_rates" c
    where c."org_id" = time_rate.tenant
      and (c."user_id" is null or c."user_id" = time_rate.user_id)
      and (c."subject_type" is null or (c."subject_type" = time_rate.subject_type and c."subject_id" = time_rate.subject_id))
      and c."effective_from" <= coalesce(time_rate.on_day, current_date)
    order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) from public, anon;
grant execute on function "better_supabase"."time_rate"(uuid, uuid, text, text, date) to authenticated, service_role;

-- What invoice_from_time would bill: the lines per currency, their totals,
-- and the billable entries no rate covers. scope: subject ({ type, id }),
-- userId, starts, ends (on started_at) and entryIds.
create or replace function "better_supabase"."unbilled_time"(tenant uuid, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(unbilled_time.scope, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', unbilled_time.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if unbilled_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text, 'currency', l.currency, 'amount', round(l.quantity * l.rate)::bigint::text, 'entryIds', l.entry_ids, 'subjectType', l.subject_type, 'subjectId', l.subject_id, 'userId', coalesce(l.member_text, l.user_text)) order by l.currency, l.first_at), '[]'::jsonb)
      from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."org_id" = x."org_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."org_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object('amount', t.amount::text, 'currency', t.currency) order by t.currency), '[]'::jsonb)
      from (select l.currency, sum(round(l.quantity * l.rate))::bigint as amount
        from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."org_id" = x."org_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."org_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l group by l.currency) t),
    'unrated', (select coalesce(jsonb_agg(u.id order by u.started_at), '[]'::jsonb)
      from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."org_id" = x."org_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."org_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u where u.rate is null)
  );
end;
$$;
revoke execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."unbilled_time"(uuid, jsonb, text) to authenticated, service_role;

-- Bills the unbilled time a scope selects on a new draft invoice. attrs go to
-- create_invoice (title, default Time; company; contact; termsDays; note); its currency
-- picks the entries in that currency, and without one the entries must share
-- one. Fails while a selected billable entry has no rate.
create or replace function "better_supabase"."invoice_from_time"(tenant uuid, attrs jsonb, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(invoice_from_time.scope, '{}'::jsonb);
  v_currency text := upper(invoice_from_time.attrs ->> 'currency');
  v_currencies text[];
  v_unrated integer;
  v_lines jsonb;
  v_entries jsonb;
  v_total bigint;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invoice_from_time.tenant, 'billable_time.invoice'), false)) then
    raise exception 'not allowed to invoice time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if invoice_from_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || invoice_from_time.tenant::text, 0));
  select count(*) filter (where u.rate is null), array_agg(distinct u.currency) filter (where u.rate is not null)
    into v_unrated, v_currencies
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."org_id" = x."org_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."org_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u;
  if v_unrated > 0 then
    raise exception 'some billable entries have no rate; set one on the entry or the rate card' using errcode = '22023', hint = 'TIME_RATE_MISSING';
  end if;
  if v_currency is null then
    if coalesce(array_length(v_currencies, 1), 0) > 1 then
      raise exception 'the entries are billed in several currencies; name one' using errcode = '22023', hint = 'BILLABLE_TIME_CURRENCIES';
    end if;
    v_currency := v_currencies[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text) order by l.first_at), '[]'::jsonb),
    coalesce(jsonb_agg(l.entry_ids), '[]'::jsonb),
    coalesce(sum(round(l.quantity * l.rate)), 0)::bigint
    into v_lines, v_entries, v_total
  from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when invoice_from_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when invoice_from_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when invoice_from_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."org_id" = x."org_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."org_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when invoice_from_time.group_by in ('member', 'entry') then u.user_id end,
      case when invoice_from_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l
  where l.currency = v_currency;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'no unbilled billable time matches' using errcode = 'P0002', hint = 'BILLABLE_TIME_EMPTY';
  end if;
  select coalesce(jsonb_agg(x.value order by x.value), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_entries) g, jsonb_array_elements(g.value) x;
  v_invoice := "better_supabase"."create_invoice"(invoice_from_time.tenant,
    (coalesce(invoice_from_time.attrs, '{}'::jsonb) - 'origin') || jsonb_build_object('currency', v_currency,
      'title', coalesce(nullif(trim(invoice_from_time.attrs ->> 'title'), ''), 'Time')), v_lines);
  insert into "better_supabase"."time_invoice_entries" ("entry_id", "org_id", "invoice_id", "rate", "currency", "seconds")
  select u.id, invoice_from_time.tenant, (v_invoice ->> 'id')::uuid, u.rate, u.currency, round(u.seconds)::bigint
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."org_id" = x."org_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."org_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
  where u.id::text in (select jsonb_array_elements_text(v_entries));
  null;
  return jsonb_build_object('invoiceId', v_invoice ->> 'id', 'currency', v_currency, 'total', v_total::text, 'entryIds', v_entries);
end;
$$;
revoke execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) from public, anon;
grant execute on function "better_supabase"."invoice_from_time"(uuid, jsonb, jsonb, text) to authenticated, service_role;

-- The entries an invoice billed, with the rate and seconds it billed.
create or replace function "better_supabase"."list_invoiced_time"(invoice uuid, page_size integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."org_id" into v_tenant from "better_supabase"."invoices" x where x."id" = list_invoiced_time.invoice;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'billable_time.read'), false)) then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('entryId', q."entry_id", 'invoiceId', q."invoice_id", 'userId', q.user_id,
      'subjectType', q.subject_type, 'subjectId', q.subject_id, 'startedAt', q.started_at, 'seconds', q."seconds",
      'rate', q."rate"::text, 'currency', q."currency", 'createdAt', q."created_at") order by q.started_at, q."entry_id"), '[]'::jsonb)
    from (
      select d.*, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id, x."started_at" as started_at
      from "better_supabase"."time_invoice_entries" d join "better_supabase"."time_entries" x on x."id" = d."entry_id"
      where d."invoice_id" = list_invoiced_time.invoice
      order by x."started_at"
      limit least(greatest(coalesce(list_invoiced_time.page_size, 500), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_invoiced_time"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_invoiced_time"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_rates";
create policy bsb_tenant_scope_select on "better_supabase"."time_rates" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."time_rates" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_rates";
create policy bsb_tenant_scope_update on "better_supabase"."time_rates" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."time_rates" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_select on "better_supabase"."time_invoice_entries" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_insert on "better_supabase"."time_invoice_entries" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_update on "better_supabase"."time_invoice_entries" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope_delete on "better_supabase"."time_invoice_entries" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block-data billable-time
-- @bsb-hash sha256:e03d1cc092ec5ad01389ac485d7354915fad1cc6732344906a9f3d41034c5eb8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billable-time', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
