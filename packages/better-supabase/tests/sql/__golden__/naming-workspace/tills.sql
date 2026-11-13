-- ==== schema supabase/schemas/900_better_supabase_169_tills.sql
-- better-supabase module: tills
-- @bsb-block tills@1 managed
-- @bsb-hash sha256:c3dd425d53952a801390d1f8a8d31d5cfe2997e303d6d5a3cde8c38d330b8543
-- Till sessions with an opening float, cash in and out, end-of-day counts that book their difference in accounting, and cash deposits that reconcile to bank transactions.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Tills: sessions with an opening float, cash movements, an end-of-day count
-- that books its difference, deposits to the bank and their reconciliation.

-- A cash register or drawer. account_id is the accounting account that holds its
-- cash; without it the till books nothing in accounting. archived tills open no
-- sessions.
create table "better_supabase"."tills" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_tills_name_check check (length("name") >= 1 and length("name") <= 100),
  "currency" text not null constraint bsb_tills_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "account_id" uuid,
  "location" text constraint bsb_tills_location_check check ("location" is null or length("location") <= 200),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "name")
);
alter table "better_supabase"."tills" enable row level security;
revoke all on "better_supabase"."tills" from public, anon, authenticated;
grant select on "better_supabase"."tills" to authenticated;
grant all on "better_supabase"."tills" to service_role;
create policy bsb_tills_read on "better_supabase"."tills"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')));

-- One shift at a till, from the opening float to the closing count. A till has
-- at most one open session. Amounts are minor units of the till's currency.
create table "better_supabase"."till_sessions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "till_id" uuid not null references "better_supabase"."tills" ("id") on delete cascade,
  "status" text not null default 'open' constraint bsb_till_sessions_status_check check ("status" in ('open', 'closed')),
  "opening_float" bigint not null default 0 constraint bsb_till_sessions_opening_float_check check ("opening_float" >= 0),
  "opened_by" uuid,
  "opened_at" timestamptz not null default now(),
  "closed_by" uuid,
  "closed_at" timestamptz,
  "notes" text constraint bsb_till_sessions_notes_check check ("notes" is null or length("notes") <= 2000)
);
create index "till_sessions_list_idx" on "better_supabase"."till_sessions" ("tenant_id", "opened_at" desc, "id");
create index "till_sessions_opened_idx" on "better_supabase"."till_sessions" ("till_id", "opened_at" desc);
create unique index "till_sessions_open_key" on "better_supabase"."till_sessions" ("till_id") where "status" = 'open';
alter table "better_supabase"."till_sessions" enable row level security;
revoke all on "better_supabase"."till_sessions" from public, anon, authenticated;
grant select on "better_supabase"."till_sessions" to authenticated;
grant all on "better_supabase"."till_sessions" to service_role;
create policy bsb_till_sessions_read on "better_supabase"."till_sessions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')));

-- Cash that went into or out of the drawer during a session: cash sales and
-- refunds, and cash put in or taken out. The amount is above zero; the kind
-- gives the direction.
create table "better_supabase"."till_movements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "session_id" uuid not null references "better_supabase"."till_sessions" ("id") on delete cascade,
  "kind" text not null constraint bsb_till_movements_kind_check check ("kind" in ('cash_sale', 'cash_refund', 'cash_in', 'cash_out')),
  "amount" bigint not null constraint bsb_till_movements_amount_check check ("amount" > 0),
  "reason" text constraint bsb_till_movements_reason_check check ("reason" is null or length("reason") <= 500),
  "reference" text constraint bsb_till_movements_reference_check check ("reference" is null or length("reference") <= 200),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index "till_movements_session_idx" on "better_supabase"."till_movements" ("session_id", "created_at");
alter table "better_supabase"."till_movements" enable row level security;
revoke all on "better_supabase"."till_movements" from public, anon, authenticated;
grant select on "better_supabase"."till_movements" to authenticated;
grant all on "better_supabase"."till_movements" to service_role;
create policy bsb_till_movements_read on "better_supabase"."till_movements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')));

-- The end-of-day count of a session: what the drawer should hold, what was
-- counted (from denominations or a total) and the difference. entry_id is the
-- accounting entry that books a non-zero difference.
create table "better_supabase"."till_counts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "session_id" uuid not null references "better_supabase"."till_sessions" ("id") on delete cascade,
  "denominations" jsonb,
  "expected_amount" bigint not null,
  "counted_amount" bigint not null constraint bsb_till_counts_counted_amount_check check ("counted_amount" >= 0),
  "variance_amount" bigint not null,
  "counted_by" uuid,
  "counted_at" timestamptz not null default now(),
  "entry_id" uuid,
  "notes" text constraint bsb_till_counts_notes_check check ("notes" is null or length("notes") <= 2000),
  unique ("session_id")
);
alter table "better_supabase"."till_counts" enable row level security;
revoke all on "better_supabase"."till_counts" from public, anon, authenticated;
grant select on "better_supabase"."till_counts" to authenticated;
grant all on "better_supabase"."till_counts" to service_role;
create policy bsb_till_counts_read on "better_supabase"."till_counts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')));

-- Counted cash taken to the bank. A deposit is pending until it is matched to a
-- bank transaction in the banking block, then reconciled.
create table "better_supabase"."till_deposits" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "session_id" uuid not null references "better_supabase"."till_sessions" ("id") on delete cascade,
  "amount" bigint not null constraint bsb_till_deposits_amount_check check ("amount" > 0),
  "deposited_on" date not null,
  "reference" text constraint bsb_till_deposits_reference_check check ("reference" is null or length("reference") <= 200),
  "status" text not null default 'pending' constraint bsb_till_deposits_status_check check ("status" in ('pending', 'reconciled')),
  "entry_id" uuid,
  "bank_transaction_id" uuid,
  "reconciled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index "till_deposits_session_idx" on "better_supabase"."till_deposits" ("session_id");
alter table "better_supabase"."till_deposits" enable row level security;
revoke all on "better_supabase"."till_deposits" from public, anon, authenticated;
grant select on "better_supabase"."till_deposits" to authenticated;
grant all on "better_supabase"."till_deposits" to service_role;
create policy bsb_till_deposits_read on "better_supabase"."till_deposits"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')));


-- Creates a till. input is { name, currency, accountId, location }; accountId
-- is the accounting account that holds its cash. Needs tills.manage.
create or replace function "better_supabase"."create_till"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(create_till.input, '{}'::jsonb);
  v_account uuid;
  v_row "better_supabase"."tills";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_till.tenant is not null and coalesce(better_supabase.can('tenant', create_till.tenant, 'tills.manage'), false))) then
    raise exception 'not allowed to create tills' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if coalesce(trim(v_input ->> 'name'), '') = '' or coalesce(v_input ->> 'currency', '') !~ '^[A-Z]{3}$' then
    raise exception 'a till needs a name and an ISO 4217 currency such as EUR' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if coalesce(v_input ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
    v_account := (v_input ->> 'accountId')::uuid;
  elsif nullif(v_input ->> 'accountId', '') is not null then
    raise exception 'accountId is a uuid' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  begin
    insert into "better_supabase"."tills" ("tenant_id", "name", "currency", "account_id", "location")
    values (create_till.tenant, trim(v_input ->> 'name'), v_input ->> 'currency', v_account, nullif(trim(v_input ->> 'location'), ''))
    returning * into v_row;
  exception when unique_violation then
    raise exception 'a till with this name exists' using errcode = '22023', hint = 'TILL_INVALID';
  when check_violation then
    raise exception 'a till needs a name of up to 100 characters and a location of up to 200' using errcode = '22023', hint = 'TILL_INVALID';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'currency', v_row."currency", 'accountId', v_row."account_id", 'location', v_row."location", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_till"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_till"(uuid, jsonb) to authenticated, service_role;

-- Changes a till. input may hold name, accountId, location and archived (true
-- archives it, false brings it back). An archived till opens no sessions and a
-- till with an open session cannot be archived. The currency never changes.
-- Needs tills.manage.
create or replace function "better_supabase"."update_till"(till_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_till.input, '{}'::jsonb);
  v_row "better_supabase"."tills";
  v_account uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tills" x where x."id" = update_till.till_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tills.read'), false))) then
    raise exception 'no such till' using errcode = 'P0002', hint = 'TILL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tills.manage'), false))) then
    raise exception 'not allowed to change tills' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_input ? 'name' and coalesce(trim(v_input ->> 'name'), '') = '' then
    raise exception 'a till needs a name' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  v_account := v_row."account_id";
  if v_input ? 'accountId' then
    if coalesce(v_input ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      v_account := (v_input ->> 'accountId')::uuid;
    elsif v_input -> 'accountId' = 'null'::jsonb then
      v_account := null;
    else
      raise exception 'accountId is a uuid or null' using errcode = '22023', hint = 'TILL_INVALID';
    end if;
  end if;
  if v_input ->> 'archived' = 'true' and exists (select 1 from "better_supabase"."till_sessions" y where y."till_id" = v_row."id" and y."status" = 'open') then
    raise exception 'close the open session before archiving the till' using errcode = '55000', hint = 'TILL_STATUS';
  end if;
  begin
    update "better_supabase"."tills" x set
      "name" = case when v_input ? 'name' then trim(v_input ->> 'name') else x."name" end,
      "account_id" = v_account,
      "location" = case when v_input ? 'location' then nullif(trim(v_input ->> 'location'), '') else x."location" end,
      "archived_at" = case when v_input ->> 'archived' = 'true' then coalesce(x."archived_at", now())
        when v_input ->> 'archived' = 'false' then null else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when unique_violation then
    raise exception 'a till with this name exists' using errcode = '22023', hint = 'TILL_INVALID';
  when check_violation then
    raise exception 'a till needs a name of up to 100 characters and a location of up to 200' using errcode = '22023', hint = 'TILL_INVALID';
  end;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'currency', v_row."currency", 'accountId', v_row."account_id", 'location', v_row."location", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_till"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_till"(uuid, jsonb) to authenticated, service_role;

-- Tills by name. filters is { archived } (true lists archived ones too).
create or replace function "better_supabase"."list_tills"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_tills.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tills.tenant is not null and coalesce(better_supabase.can('tenant', list_tills.tenant, 'tills.read'), false))) then
    raise exception 'not allowed to read tills' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'name', y."name", 'currency', y."currency", 'accountId', y."account_id", 'location', y."location", 'archivedAt', y."archived_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."name")
    from "better_supabase"."tills" y
    where y."tenant_id" = list_tills.tenant
      and (v_filters ->> 'archived' = 'true' or y."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tills"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_tills"(uuid, jsonb) to authenticated, service_role;

-- Starts a shift at a till with the cash in the drawer (opening_float, minor
-- units). A till has one open session at a time. Needs tills.write.
create or replace function "better_supabase"."open_till_session"(till_id uuid, opening_float bigint default 0, notes text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_till "better_supabase"."tills";
  v_row "better_supabase"."till_sessions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_till from "better_supabase"."tills" x where x."id" = open_till_session.till_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_till."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_till."tenant_id", 'tills.read'), false))) then
    raise exception 'no such till' using errcode = 'P0002', hint = 'TILL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_till."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_till."tenant_id", 'tills.write'), false))) then
    raise exception 'not allowed to open till sessions' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_till."archived_at" is not null then
    raise exception 'an archived till opens no sessions' using errcode = '55000', hint = 'TILL_STATUS';
  end if;
  if coalesce(open_till_session.opening_float, 0) < 0 then
    raise exception 'the opening float is zero or more' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_till_session_open"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_till."id", coalesce(open_till_session.opening_float, 0);
    end if;
  end;
  begin
    insert into "better_supabase"."till_sessions" ("tenant_id", "till_id", "opening_float", "opened_by", "notes")
    values (v_till."tenant_id", v_till."id", coalesce(open_till_session.opening_float, 0), auth.uid(), nullif(trim(open_till_session.notes), ''))
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this till already has an open session' using errcode = '55000', hint = 'TILL_STATUS';
  when check_violation then
    raise exception 'notes are up to 2000 characters' using errcode = '22023', hint = 'TILL_INVALID';
  end;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_till_session_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'tillId', v_row."till_id", 'organizationId', v_row."tenant_id", 'status', v_row."status", 'openingFloat', v_row."opening_float"::text, 'expected', (select (v_row."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = v_row."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = v_row."till_id"), 'openedBy', v_row."opened_by", 'openedAt', v_row."opened_at", 'closedBy', v_row."closed_by", 'closedAt', v_row."closed_at", 'notes', v_row."notes");
end;
$$;
revoke execute on function "better_supabase"."open_till_session"(uuid, bigint, text) from public, anon;
grant execute on function "better_supabase"."open_till_session"(uuid, bigint, text) to authenticated, service_role;

-- A session with its movements, its count and its deposits.
create or replace function "better_supabase"."get_till_session"(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."till_sessions";
begin
  select * into v_row from "better_supabase"."till_sessions" x where x."id" = get_till_session.session_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tills.read'), false))) then
    raise exception 'no such till session' using errcode = 'P0002', hint = 'TILL_SESSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'tillId', v_row."till_id", 'organizationId', v_row."tenant_id", 'status', v_row."status", 'openingFloat', v_row."opening_float"::text, 'expected', (select (v_row."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = v_row."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = v_row."till_id"), 'openedBy', v_row."opened_by", 'openedAt', v_row."opened_at", 'closedBy', v_row."closed_by", 'closedAt', v_row."closed_at", 'notes', v_row."notes") || jsonb_build_object(
    'movements', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = y."session_id"), 'sessionId', y."session_id", 'kind', y."kind", 'amount', y."amount"::text, 'reason', y."reason", 'reference', y."reference", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."till_movements" y where y."session_id" = v_row."id"), '[]'::jsonb),
    'count', (select jsonb_build_object('id', y."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = y."session_id"), 'sessionId', y."session_id", 'denominations', y."denominations", 'expected', y."expected_amount"::text, 'counted', y."counted_amount"::text, 'variance', y."variance_amount"::text, 'countedBy', y."counted_by", 'countedAt', y."counted_at", 'entryId', y."entry_id", 'notes', y."notes") from "better_supabase"."till_counts" y where y."session_id" = v_row."id"),
    'deposits', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = y."session_id"), 'sessionId', y."session_id", 'amount', y."amount"::text, 'depositedOn', y."deposited_on", 'reference', y."reference", 'status', y."status", 'entryId', y."entry_id", 'bankTransactionId', y."bank_transaction_id", 'reconciledAt', y."reconciled_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."till_deposits" y where y."session_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_till_session"(uuid) from public, anon;
grant execute on function "better_supabase"."get_till_session"(uuid) to authenticated, service_role;

-- Sessions, newest first. filters is { tillId, status (each a value or a list of
-- them), sort, direction, facet, count, limit, after, offset, paged, total,
-- totalCap } (ADR 0749).
create or replace function "better_supabase"."list_till_sessions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_till_sessions.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_till_sessions.tenant is not null and coalesce(better_supabase.can('tenant', list_till_sessions.tenant, 'tills.read'), false))) then
    raise exception 'not allowed to read till sessions' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'tillId') then
      raise exception 'facet is one of status, tillId' using errcode = '22023', hint = 'TILL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'tillId' then (x."till_id")::text end) as v
      from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
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
      select 1 from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('openedAt', 'closedAt') then
    raise exception 'sort is one of openedAt, closedAt' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((x."opened_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."opened_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."opened_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((x."opened_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."opened_at" <= (v_after ->> 0)::timestamptz and ((x."opened_at" < (v_after ->> 0)::timestamptz) or (x."opened_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."opened_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'openedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((x."opened_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."opened_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."opened_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'openedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((x."opened_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."opened_at" <= (v_after ->> 0)::timestamptz and ((x."opened_at" < (v_after ->> 0)::timestamptz) or (x."opened_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."opened_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'closedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((coalesce(x."closed_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (coalesce(x."closed_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."closed_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'closedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tillId', x."till_id", 'organizationId', x."tenant_id", 'status', x."status", 'openingFloat', x."opening_float"::text, 'expected', (select (x."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = x."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = x."till_id"), 'openedBy', x."opened_by", 'openedAt', x."opened_at", 'closedBy', x."closed_by", 'closedAt', x."closed_at", 'notes', x."notes") as j, jsonb_build_array((coalesce(x."closed_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (coalesce(x."closed_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."closed_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."closed_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."closed_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."till_sessions" x
      where x."tenant_id" = list_till_sessions.tenant
        and (not (v_filters -> 'tillId' is not null and jsonb_typeof(v_filters -> 'tillId') <> 'null' and not (jsonb_typeof(v_filters -> 'tillId') = 'array' and jsonb_array_length(v_filters -> 'tillId') = 0)) or x."till_id"::text = any((case when jsonb_typeof(v_filters -> 'tillId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tillId')) else array[v_filters ->> 'tillId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_till_sessions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_till_sessions"(uuid, jsonb) to authenticated, service_role;


-- Records cash that went into or out of the drawer of an open session. kind is
-- cash_sale or cash_in (adds) or cash_refund or cash_out (removes); amount is
-- above zero, in minor units. Needs tills.write.
create or replace function "better_supabase"."record_till_movement"(session_id uuid, kind text, amount bigint, reason text default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_session "better_supabase"."till_sessions";
  v_till "better_supabase"."tills";
  v_row "better_supabase"."till_movements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_session from "better_supabase"."till_sessions" x where x."id" = record_till_movement.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_session."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_session."tenant_id", 'tills.read'), false))) then
    raise exception 'no such till session' using errcode = 'P0002', hint = 'TILL_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_session."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_session."tenant_id", 'tills.write'), false))) then
    raise exception 'not allowed to record cash movements' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_session."status" <> 'open' then
    raise exception 'cash can only be recorded on an open session' using errcode = '55000', hint = 'TILL_STATUS';
  end if;
  if record_till_movement.kind is null or record_till_movement.kind not in ('cash_sale', 'cash_refund', 'cash_in', 'cash_out') then
    raise exception 'kind is one of cash_sale, cash_refund, cash_in, cash_out' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if record_till_movement.amount is null or record_till_movement.amount <= 0 then
    raise exception 'the amount is above zero' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if record_till_movement.kind in ('cash_refund', 'cash_out') and record_till_movement.amount > (v_session."opening_float" + coalesce((select sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end) from "better_supabase"."till_movements" bm where bm."session_id" = v_session."id"), 0)) then
    raise exception 'the drawer does not hold that much cash' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  begin
    insert into "better_supabase"."till_movements" ("tenant_id", "session_id", "kind", "amount", "reason", "reference", "created_by")
    values (v_session."tenant_id", v_session."id", record_till_movement.kind, record_till_movement.amount,
      nullif(trim(record_till_movement.reason), ''), nullif(trim(record_till_movement.reference), ''), auth.uid())
    returning * into v_row;
  exception when check_violation then
    raise exception 'a reason is up to 500 and a reference up to 200 characters' using errcode = '22023', hint = 'TILL_INVALID';
  end;
  select * into v_till from "better_supabase"."tills" x where x."id" = v_session."till_id";
  null;
  return jsonb_build_object('id', v_row."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = v_row."session_id"), 'sessionId', v_row."session_id", 'kind', v_row."kind", 'amount', v_row."amount"::text, 'reason', v_row."reason", 'reference', v_row."reference", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_till_movement"(uuid, text, bigint, text, text) from public, anon;
grant execute on function "better_supabase"."record_till_movement"(uuid, text, bigint, text, text) to authenticated, service_role;

-- Ends a session with the end-of-day count. input is { denominations, amount,
-- notes }: denominations maps a note or coin value in minor units to how many
-- there are ({ "500": 3, "100": 12 }) and the count is their sum; without it,
-- amount is the counted total in minor units. The difference to the expected
-- cash is kept and, when the till has a cash account, booked in accounting.
-- Needs tills.write.
create or replace function "better_supabase"."close_till_session"(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(close_till_session.input, '{}'::jsonb);
  v_session "better_supabase"."till_sessions";
  v_till "better_supabase"."tills";
  v_count "better_supabase"."till_counts";
  v_expected bigint;
  v_counted bigint;
  v_entry uuid;
  v_entry_value record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_session from "better_supabase"."till_sessions" x where x."id" = close_till_session.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_session."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_session."tenant_id", 'tills.read'), false))) then
    raise exception 'no such till session' using errcode = 'P0002', hint = 'TILL_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_session."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_session."tenant_id", 'tills.write'), false))) then
    raise exception 'not allowed to close till sessions' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_session."status" <> 'open' then
    raise exception 'only an open session can be closed' using errcode = '55000', hint = 'TILL_STATUS';
  end if;
  if jsonb_typeof(v_input -> 'denominations') = 'object' then
    for v_entry_value in select key, value from jsonb_each(v_input -> 'denominations') loop
      if v_entry_value.key !~ '^[0-9]{1,12}$' or jsonb_typeof(v_entry_value.value) is distinct from 'number'
        or v_entry_value.value::text !~ '^[0-9]{1,9}$' then
        raise exception 'denominations maps a value in minor units to a whole count' using errcode = '22023', hint = 'TILL_INVALID';
      end if;
    end loop;
    select coalesce(sum(key::bigint * (value::text)::bigint), 0) into v_counted from jsonb_each(v_input -> 'denominations');
  elsif coalesce(v_input ->> 'amount', '') ~ '^[0-9]{1,18}$' then
    v_counted := (v_input ->> 'amount')::bigint;
  else
    raise exception 'give the counted denominations or a counted amount in minor units' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select * into v_till from "better_supabase"."tills" x where x."id" = v_session."till_id";
  v_expected := (v_session."opening_float" + coalesce((select sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end) from "better_supabase"."till_movements" bm where bm."session_id" = v_session."id"), 0));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_till_session_close"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_session."id", v_counted;
    end if;
  end;
  begin
    insert into "better_supabase"."till_counts" ("tenant_id", "session_id", "denominations", "expected_amount", "counted_amount", "variance_amount", "counted_by", "notes")
    values (v_session."tenant_id", v_session."id",
      case when jsonb_typeof(v_input -> 'denominations') = 'object' then v_input -> 'denominations' end,
      v_expected, v_counted, v_counted - v_expected, auth.uid(), nullif(trim(v_input ->> 'notes'), ''))
    returning * into v_count;
  exception when check_violation then
    raise exception 'notes are up to 2000 characters' using errcode = '22023', hint = 'TILL_INVALID';
  end;
  update "better_supabase"."till_sessions" x set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
  where x."id" = v_session."id" returning * into v_session;
  if v_count."variance_amount" <> 0 then
    
    if v_entry is not null then
      update "better_supabase"."till_counts" x set "entry_id" = v_entry where x."id" = v_count."id";
    end if;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_till_session_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_session."id";
    end if;
  end;
  select * into v_session from "better_supabase"."till_sessions" x where x."id" = v_session."id";
  return jsonb_build_object('id', v_session."id", 'tillId', v_session."till_id", 'organizationId', v_session."tenant_id", 'status', v_session."status", 'openingFloat', v_session."opening_float"::text, 'expected', (select (v_session."opening_float" + coalesce(sum(case when bm."kind" in ('cash_sale', 'cash_in') then bm."amount" else -bm."amount" end), 0))::text from "better_supabase"."till_movements" bm where bm."session_id" = v_session."id"), 'currency', (select bt."currency" from "better_supabase"."tills" bt where bt."id" = v_session."till_id"), 'openedBy', v_session."opened_by", 'openedAt', v_session."opened_at", 'closedBy', v_session."closed_by", 'closedAt', v_session."closed_at", 'notes', v_session."notes") || jsonb_build_object(
    'movements', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = y."session_id"), 'sessionId', y."session_id", 'kind', y."kind", 'amount', y."amount"::text, 'reason', y."reason", 'reference', y."reference", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."till_movements" y where y."session_id" = v_session."id"), '[]'::jsonb),
    'count', (select jsonb_build_object('id', y."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = y."session_id"), 'sessionId', y."session_id", 'denominations', y."denominations", 'expected', y."expected_amount"::text, 'counted', y."counted_amount"::text, 'variance', y."variance_amount"::text, 'countedBy', y."counted_by", 'countedAt', y."counted_at", 'entryId', y."entry_id", 'notes', y."notes") from "better_supabase"."till_counts" y where y."session_id" = v_session."id"),
    'deposits', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = y."session_id"), 'sessionId', y."session_id", 'amount', y."amount"::text, 'depositedOn', y."deposited_on", 'reference', y."reference", 'status', y."status", 'entryId', y."entry_id", 'bankTransactionId', y."bank_transaction_id", 'reconciledAt', y."reconciled_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."till_deposits" y where y."session_id" = v_session."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."close_till_session"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."close_till_session"(uuid, jsonb) to authenticated, service_role;

-- Takes counted cash to the bank from a closed session. input is { amount,
-- depositedOn, reference }; the deposits of a session never exceed its count.
-- With accounting and a cash account on the till, the deposit is booked as bank
-- against cash. It stays pending until it is reconciled. Needs tills.manage.
create or replace function "better_supabase"."deposit_till_cash"(session_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(deposit_till_cash.input, '{}'::jsonb);
  v_session "better_supabase"."till_sessions";
  v_till "better_supabase"."tills";
  v_count "better_supabase"."till_counts";
  v_amount bigint;
  v_on date;
  v_entry uuid;
  v_row "better_supabase"."till_deposits";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_session from "better_supabase"."till_sessions" x where x."id" = deposit_till_cash.session_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_session."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_session."tenant_id", 'tills.read'), false))) then
    raise exception 'no such till session' using errcode = 'P0002', hint = 'TILL_SESSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_session."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_session."tenant_id", 'tills.manage'), false))) then
    raise exception 'not allowed to deposit till cash' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  select * into v_count from "better_supabase"."till_counts" x where x."session_id" = v_session."id";
  if v_session."status" <> 'closed' or v_count."id" is null then
    raise exception 'cash can only be deposited from a closed, counted session' using errcode = '55000', hint = 'TILL_STATUS';
  end if;
  if coalesce(v_input ->> 'amount', '') !~ '^[0-9]{1,18}$' or (v_input ->> 'amount')::bigint = 0 then
    raise exception 'amount is above zero, in minor units' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  v_amount := (v_input ->> 'amount')::bigint;
  if coalesce(v_input ->> 'depositedOn', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    v_on := (v_input ->> 'depositedOn')::date;
  elsif nullif(v_input ->> 'depositedOn', '') is null then
    v_on := (now() at time zone 'UTC')::date;
  else
    raise exception 'depositedOn is a date such as 2026-10-31' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  if v_amount + coalesce((select sum(y."amount") from "better_supabase"."till_deposits" y where y."session_id" = v_session."id"), 0) > v_count."counted_amount" then
    raise exception 'the deposits would exceed the counted cash of the session' using errcode = '22023', hint = 'TILL_INVALID';
  end if;
  select * into v_till from "better_supabase"."tills" x where x."id" = v_session."till_id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_till_deposit"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_session."id", v_amount;
    end if;
  end;
  begin
    insert into "better_supabase"."till_deposits" ("tenant_id", "session_id", "amount", "deposited_on", "reference", "created_by")
    values (v_session."tenant_id", v_session."id", v_amount, v_on, nullif(trim(v_input ->> 'reference'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation then
    raise exception 'a reference is up to 200 characters' using errcode = '22023', hint = 'TILL_INVALID';
  end;
  
  if v_entry is not null then
    update "better_supabase"."till_deposits" x set "entry_id" = v_entry where x."id" = v_row."id" returning * into v_row;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_till_deposit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = v_row."session_id"), 'sessionId', v_row."session_id", 'amount', v_row."amount"::text, 'depositedOn', v_row."deposited_on", 'reference', v_row."reference", 'status', v_row."status", 'entryId', v_row."entry_id", 'bankTransactionId', v_row."bank_transaction_id", 'reconciledAt', v_row."reconciled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."deposit_till_cash"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."deposit_till_cash"(uuid, jsonb) to authenticated, service_role;

-- Matches a pending deposit to the bank transaction that shows it, through the
-- banking block, and marks it reconciled. The transaction's amount must equal
-- the deposit's. Needs tills.manage.
create or replace function "better_supabase"."reconcile_till_deposit"(deposit_id uuid, bank_transaction_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."till_deposits";
  v_till "better_supabase"."tills";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."till_deposits" x where x."id" = reconcile_till_deposit.deposit_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tills.read'), false))) then
    raise exception 'no such cash deposit' using errcode = 'P0002', hint = 'TILL_DEPOSIT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tills.manage'), false))) then
    raise exception 'not allowed to reconcile cash deposits' using errcode = '42501', hint = 'TILL_FORBIDDEN';
  end if;
  if v_row."status" <> 'pending' then
    raise exception 'this deposit is already reconciled' using errcode = '55000', hint = 'TILL_STATUS';
  end if;
  raise exception 'reconciling needs the banking and accounting blocks' using errcode = '22023', hint = 'TILL_INVALID';
  update "better_supabase"."till_deposits" x set "status" = 'reconciled', "bank_transaction_id" = reconcile_till_deposit.bank_transaction_id, "reconciled_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  select y.* into v_till from "better_supabase"."tills" y join "better_supabase"."till_sessions" z on z."till_id" = y."id" where z."id" = v_row."session_id";
  null;
  return jsonb_build_object('id', v_row."id", 'currency', (select bt."currency" from "better_supabase"."tills" bt join "better_supabase"."till_sessions" bs on bs."till_id" = bt."id" where bs."id" = v_row."session_id"), 'sessionId', v_row."session_id", 'amount', v_row."amount"::text, 'depositedOn', v_row."deposited_on", 'reference', v_row."reference", 'status', v_row."status", 'entryId', v_row."entry_id", 'bankTransactionId', v_row."bank_transaction_id", 'reconciledAt', v_row."reconciled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."reconcile_till_deposit"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."reconcile_till_deposit"(uuid, uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."tills" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."tills" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."tills" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."tills" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."till_sessions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."till_sessions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."till_sessions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."till_sessions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."till_movements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."till_movements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."till_movements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."till_movements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."till_counts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."till_counts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."till_counts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."till_counts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."till_deposits" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tills.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."till_deposits" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."till_deposits" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."till_deposits" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_169_tills.sql
-- better-supabase module: tills
-- @bsb-block-data tills
-- @bsb-hash sha256:97aebb68082028b87343d802ec0cfa32a1001cebdc3f3b6c6f100af8709fdbfc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tills', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
