-- ==== schema supabase/schemas/900_better_supabase_119_billable_time.sql
-- better-supabase module: billable-time
-- @bsb-block billable-time@1 managed
-- @bsb-hash sha256:867e05b854f3eab86a9405af8e60967f9197e95b9eb8a517f4a67659b4c62409
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
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
  exception when undefined_table then null;
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
create index if not exists "time_rates_lookup_idx" on "better_supabase"."time_rates" ("tenant_id", "subject_type", "subject_id", "user_id", "effective_from" desc);
alter table "better_supabase"."time_rates" enable row level security;
revoke all on "better_supabase"."time_rates" from anon, authenticated;
grant select on "better_supabase"."time_rates" to authenticated;
grant all on "better_supabase"."time_rates" to service_role;
drop policy if exists "time_rates_read" on "better_supabase"."time_rates";
create policy "time_rates_read" on "better_supabase"."time_rates" for select to authenticated
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
revoke all on "better_supabase"."time_invoice_entries" from anon, authenticated;
grant select on "better_supabase"."time_invoice_entries" to authenticated;
grant all on "better_supabase"."time_invoice_entries" to service_role;
drop policy if exists "time_invoice_entries_read" on "better_supabase"."time_invoice_entries";
create policy "time_invoice_entries_read" on "better_supabase"."time_invoice_entries" for select to authenticated
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
-- (neither), from effective_from (today by default). The same key and day
-- replaces the rate.
create or replace function "better_supabase"."set_time_rate"(tenant uuid, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null)
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
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not false then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."workspace_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), auth.uid())
  on conflict ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date) from public, anon;
grant execute on function "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date) to authenticated, service_role;

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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
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
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'rate', q."rate"::text, 'currency', q."currency", 'effectiveFrom', q."effective_from", 'createdBy', q."created_by", 'createdAt', q."created_at") order by q."subject_type" nulls first, q."subject_id" nulls first, q."user_id" nulls first, q."effective_from" desc), '[]'::jsonb)
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
    select jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'userId', c."user_id", 'subjectType', c."subject_type", 'subjectId', c."subject_id", 'rate', c."rate"::text, 'currency', c."currency", 'effectiveFrom', c."effective_from", 'createdBy', c."created_by", 'createdAt', c."created_at") from "better_supabase"."time_rates" c
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

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."time_rates";
create policy bsb_tenant_scope on "better_supabase"."time_rates" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."time_invoice_entries";
create policy bsb_tenant_scope on "better_supabase"."time_invoice_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billable_time.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_119_billable_time.sql
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
